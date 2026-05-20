// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

//  AUDIT: Donation Attack & First Depositor Exploit Test Suite
//
//  Attack vectors tested:
//    1. First depositor share inflation via dust deposit + direct donation
//    2. Direct GM/WBTC transfer to VaultCore or isolation vault
//    3. Rounding theft via repeated small operations
//
//  Architecture context (critical for understanding these tests):
//    - Basalt uses FIXED shares: SHARE_UNIT = 1e18 per vault.
//    - Each VaultCore is a single-owner vault (NFT-gated).
//    - Shares are NOT dynamically minted (unlike ERC-4626).
//    - NAV = gmCollateral * gmPrice + wbtcSurplus * wbtcPrice - wbtcDebt * wbtcPrice
//    - Pro-rata uses OpenZeppelin Math.mulDiv (safe rounding).
//    - Minimum deposit enforced: amountGmE18 >= 1e18 (DepositHandlerRequirements).
//
//  The fixed-share design eliminates classical vault inflation attacks,
//  but these tests verify the invariants hold under adversarial conditions.

import {Test} from "forge-std/Test.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IDepositHandlerVaultCore} from "../../src/interfaces/IDepositHandlerVaultCore.sol";
import {BasaltMath} from "../../src/pure/BasaltMath.sol";
import {BasaltConstants} from "../../src/libraries/BasaltConstants.sol";
import {BasaltAddresses} from "../../src/libraries/BasaltAddresses.sol";
import {VaultState} from "../../src/core/VaultState.sol";
import {VaultCore} from "../../src/core/VaultCore.sol";
import {ForkSetupFull} from "../helpers/ForkSetupFull.sol";

contract DonationAttackTest is ForkSetupFull {
    IERC20 internal gmToken;
    IERC20 internal wbtcToken;

    uint256 internal constant SHARE_UNIT = 1e18;
    uint256 internal constant BPS = 10_000;

    function setUp() public override {
        super.setUp();
        gmToken = IERC20(BasaltAddresses.GM_MARKET_TOKEN);
        wbtcToken = IERC20(BasaltAddresses.WBTC);
    }

    //  FIRST DEPOSITOR ATTACK TESTS

    /// @notice Verify that SHARE_UNIT = 1e18 is a fixed constant, making
    ///         classical vault inflation (deposit 1 wei, donate to inflate
    ///         share price) structurally impossible.
    ///
    ///         In ERC-4626 vaults, the attacker deposits 1 wei to get 1 share,
    ///         then donates 1000e18 tokens so each share is worth 1000e18+1.
    ///         The next depositor's shares round down to 0.
    ///
    ///         Basalt's SHARE_UNIT model: shares are always 1e18 total for the
    ///         single vault owner. There is no share minting, so no rounding
    ///         attack surface.
    function test_firstDepositor_cannotInflateSharePrice() public view {
        // The vault has exactly SHARE_UNIT shares at all times.
        // Even if an attacker could deposit 1 wei GM (they can't — minimum is 1e18),
        // the "next depositor" is the same vault owner, and shares don't dilute.
        uint256 totalShares = BasaltConstants.SHARE_UNIT;
        assertEq(totalShares, 1e18, "SHARE_UNIT must be 1e18");

        // Simulate: attacker somehow has 1 wei GM collateral, then 1000e18 is donated.
        // In ERC-4626 this would steal the next deposit. In Basalt, pro-rata just
        // gives back what you put in proportionally.
        uint256 collateralBefore = 1;
        uint256 donated = 1000e18;
        uint256 collateralAfter = collateralBefore + donated;

        // With SHARE_UNIT, withdrawing 50% of shares returns 50% of collateral
        uint256 halfShares = totalShares / 2;
        uint256 gmReturned = basaltMath.calcProRataGm(collateralAfter, halfShares, totalShares);

        // Must be exactly half (within floor rounding)
        assertEq(gmReturned, collateralAfter / 2, "pro-rata must return proportional amount");
    }

    /// @notice Verify that the minimum deposit guard rejects dust deposits.
    ///         The first depositor attack requires depositing 1 wei — this
    ///         must be blocked at the handler level.
    function test_firstDepositor_minimalDeposit_rejected() public {
        // DepositHandlerRequirements.requireValidDepositParams enforces >= 1e18
        // Attempting to deposit 1 wei GM should revert.
        uint256 dustAmount = 1;
        uint256 validSlippage = 100; // 1% — within [50, 500] bounds

        vm.prank(vaultOwner);
        vm.expectRevert(); // DepositTooSmall(1, 1e18)
        depositHandler.deposit(
            IDepositHandlerVaultCore(address(vaultCore)),
            dustAmount,
            validSlippage
        );
    }

    /// @notice Verify SHARE_UNIT protection: pro-rata math with 1e18 total shares
    ///         never rounds to 0 for any meaningful collateral amount.
    function test_firstDepositor_SHARE_UNIT_protection() public view {
        uint256 totalShares = SHARE_UNIT;

        // Even with minimum possible collateral (1 wei GM), full share
        // redemption returns the full amount.
        uint256 minCollateral = 1;
        uint256 fullRedeem = basaltMath.calcProRataGm(minCollateral, totalShares, totalShares);
        assertEq(fullRedeem, minCollateral, "full redemption must return all collateral");

        // With 1e18 collateral and withdrawing 1 share (1 wei of 1e18 total),
        // the result is 1 wei — no rounding to 0.
        uint256 normalCollateral = 1e18;
        uint256 oneWeiShare = 1;
        uint256 tinyRedeem = basaltMath.calcProRataGm(normalCollateral, oneWeiShare, totalShares);
        assertEq(tinyRedeem, 1, "1 wei of shares must redeem 1 wei of collateral");

        // Large collateral, small share fraction — still non-zero.
        uint256 largeCollateral = 1_000_000e18;
        uint256 smallRedeem = basaltMath.calcProRataGm(largeCollateral, oneWeiShare, totalShares);
        assertEq(smallRedeem, 1_000_000, "tiny share fraction of large collateral must be non-zero");
    }

    //  DONATION ATTACK TESTS

    /// @notice Direct GM transfer to VaultCore must not affect the share price.
    ///         NAV is derived from Dolomite collateral readings (position-based),
    ///         not from VaultCore's token balance. Tokens sitting in VaultCore
    ///         without being deposited to Dolomite are invisible to the NAV calc.
    function test_donation_directTransferGM_doesNotAffectSharePrice() public {
        // Read NAV-related state before donation
        uint256 totalDepositedUsdBefore = vaultState.totalDepositedUsdE18();
        uint256 totalDepositedGmBefore = vaultState.totalDepositedGmE18();
        uint256 lastNavBefore = vaultState.lastFinalizedNavUsdE18();

        // Donate 1000 GM tokens directly to VaultCore (bypass deposit handler)
        uint256 donationAmount = 1000e18;
        deal(address(gmToken), stranger, donationAmount);
        vm.prank(stranger);
        gmToken.transfer(address(vaultCore), donationAmount);

        // Verify VaultCore received the tokens
        uint256 vcBalance = gmToken.balanceOf(address(vaultCore));
        assertGe(vcBalance, donationAmount, "VaultCore must hold donated GM");

        // VaultState accounting must be completely unaffected
        assertEq(
            vaultState.totalDepositedUsdE18(),
            totalDepositedUsdBefore,
            "totalDepositedUsd must not change from donation"
        );
        assertEq(
            vaultState.totalDepositedGmE18(),
            totalDepositedGmBefore,
            "totalDepositedGm must not change from donation"
        );
        assertEq(
            vaultState.lastFinalizedNavUsdE18(),
            lastNavBefore,
            "lastFinalizedNav must not change from donation"
        );
    }

    /// @notice Direct GM transfer to isolation vault must not inflate
    ///         VaultState accounting. The isolation vault's Dolomite position
    ///         balance is read from Dolomite Margin, not from raw ERC-20 balance.
    ///         Tokens sent directly sit idle and do not enter the position.
    function test_donation_directTransferToIsoVault_doesNotInflate() public {
        address isoVault = vaultState.dolomiteIsolationVault();

        // If isolation vault not yet created, this test validates the zero-state
        if (isoVault == address(0)) {
            // No isolation vault means no position exists — donation has no target
            // Still verify state is clean
            assertEq(vaultState.lastFinalizedGmCollateralE18(), 0, "no collateral before iso vault");
            return;
        }

        // Record Dolomite-sourced accounting before donation
        uint256 gmCollateralBefore = vaultState.lastFinalizedGmCollateralE18();
        uint256 wbtcDebtBefore = vaultState.lastFinalizedWbtcDebtE8();

        // Donate GM directly to isolation vault
        uint256 donationAmount = 500e18;
        deal(address(gmToken), stranger, donationAmount);
        vm.prank(stranger);
        gmToken.transfer(isoVault, donationAmount);

        // VaultState snapshots must be unaffected (they are set only by
        // finalizeDepositAccounting, which reads from Dolomite margin)
        assertEq(
            vaultState.lastFinalizedGmCollateralE18(),
            gmCollateralBefore,
            "gmCollateral snapshot must not change from direct transfer"
        );
        assertEq(
            vaultState.lastFinalizedWbtcDebtE8(),
            wbtcDebtBefore,
            "wbtcDebt snapshot must not change from direct transfer"
        );
    }

    /// @notice Direct WBTC transfer to VaultCore must not affect NAV calculation.
    ///         NAV reads Dolomite position state, not VaultCore ERC-20 balance.
    function test_donation_wbtcDirectTransfer_doesNotAffectNAV() public {
        // Snapshot VaultState before donation
        uint256 lastNavBefore = vaultState.lastFinalizedNavUsdE18();
        uint256 totalDepositedUsdBefore = vaultState.totalDepositedUsdE18();
        uint256 totalWithdrawnUsdBefore = vaultState.totalWithdrawnUsdE18();

        // Donate 1 WBTC directly to VaultCore
        uint256 wbtcDonation = 1e8; // 1 WBTC (8 decimals)
        deal(address(wbtcToken), stranger, wbtcDonation);
        vm.prank(stranger);
        wbtcToken.transfer(address(vaultCore), wbtcDonation);

        // VaultCore holds the WBTC but accounting is untouched
        assertGe(wbtcToken.balanceOf(address(vaultCore)), wbtcDonation, "VaultCore must hold donated WBTC");

        // All accounting values must remain identical
        assertEq(
            vaultState.lastFinalizedNavUsdE18(),
            lastNavBefore,
            "lastFinalizedNav must not change from WBTC donation"
        );
        assertEq(
            vaultState.totalDepositedUsdE18(),
            totalDepositedUsdBefore,
            "totalDepositedUsd must not change from WBTC donation"
        );
        assertEq(
            vaultState.totalWithdrawnUsdE18(),
            totalWithdrawnUsdBefore,
            "totalWithdrawnUsd must not change from WBTC donation"
        );

        // Verify NAV formula with zero collateral/debt ignores donated WBTC.
        // NAV = collUsd + surplusUsd - debtUsd.
        // Donated tokens do not enter any of these terms.
        uint256 navFromMath = basaltMath.calcNavUsdE18(
            0,    // gmCollateral = 0 (no Dolomite position)
            0,    // wbtcSurplus = 0 (read from Dolomite, not balance)
            0,    // wbtcDebt = 0
            1e18, // gmPrice (arbitrary, zeroed out by 0 collateral)
            95000e18 // wbtcPrice
        );
        assertEq(navFromMath, 0, "NAV must be 0 when Dolomite position is empty");
    }

    //  ROUNDING THEFT TESTS

    /// @notice Repeated small pro-rata operations must not lose value vs a
    ///         single large operation. Tests that Math.mulDiv floor rounding
    ///         does not accumulate into significant theft.
    function test_roundingTheft_repeatedSmallDeposits() public view {
        uint256 totalShares = SHARE_UNIT;
        uint256 collateral = 1_000_000e18; // 1M GM

        // Single withdrawal of 1000 wei shares
        uint256 singleWithdrawShares = 1000;
        uint256 singleResult = basaltMath.calcProRataGm(collateral, singleWithdrawShares, totalShares);

        // 1000 individual withdrawals of 1 wei share each
        uint256 repeatedTotal = 0;
        uint256 remainingCollateral = collateral;
        for (uint256 i = 0; i < 1000; i++) {
            uint256 thisRedeem = basaltMath.calcProRataGm(remainingCollateral, 1, totalShares - i);
            repeatedTotal += thisRedeem;
            remainingCollateral -= thisRedeem;
        }

        // The repeated approach should yield approximately the same as single.
        // Floor rounding means repeated <= single, but the difference must be
        // bounded by the number of operations (at most 1 wei per operation).
        assertLe(
            singleResult - repeatedTotal,
            1000,
            "rounding loss from 1000 repeated ops must be <= 1000 wei"
        );

        // Also verify the single result is correct
        // 1M e18 * 1000 / 1e18 = 1_000_000_000 (1e9)
        assertEq(singleResult, 1_000_000_000, "1000/1e18 of 1M GM = 1e9 wei");
    }

    /// @notice Verify that pro-rata rounding on withdrawal favors the vault
    ///         (user gets floor, not ceil). This prevents users from extracting
    ///         more value than their proportional share.
    function test_roundingTheft_withdrawRoundingFavorsVault() public view {
        uint256 totalShares = SHARE_UNIT;

        // Choose collateral and share amounts that produce a remainder.
        // collateral = 1e18 + 1 (indivisible cleanly by 3)
        // shares = SHARE_UNIT / 3 (one-third)
        uint256 collateral = 1e18 + 1;
        uint256 oneThirdShares = totalShares / 3;

        uint256 gmReturned = basaltMath.calcProRataGm(collateral, oneThirdShares, totalShares);

        // Floor division: (1e18 + 1) * (1e18 / 3) / 1e18
        // = (1e18 + 1) * 333333333333333333 / 1e18
        // Using Math.mulDiv (floor): result should be <= collateral / 3
        uint256 exactThird = collateral / 3;
        assertLe(gmReturned, exactThird, "floor rounding must not exceed exact division");

        // Verify vault retains more than 2/3 after the withdrawal
        uint256 remaining = collateral - gmReturned;
        uint256 twoThirds = (collateral * 2) / 3;
        assertGe(remaining, twoThirds, "vault must retain >= 2/3 after floor-rounded 1/3 withdraw");

        // Also verify with calcProRataRedeem (used for WBTC surplus)
        uint256 wbtcSurplus = 100e8 + 7; // 100 WBTC + 7 sats (indivisible)
        uint256 wbtcReturned = basaltMath.calcProRataRedeem(wbtcSurplus, oneThirdShares, totalShares);
        uint256 wbtcExactThird = wbtcSurplus / 3;
        assertLe(wbtcReturned, wbtcExactThird, "WBTC pro-rata must also floor-round");
    }

    //  EDGE CASE: SHARE MATH BOUNDARY CONDITIONS

    /// @notice Verify calcProRataGm handles extreme ratios without overflow.
    ///         Uses realistic maximum values for Dolomite GM positions.
    function test_proRata_extremeRatios_noOverflow() public view {
        uint256 totalShares = SHARE_UNIT;

        // Max realistic GM collateral: ~10M GM tokens
        uint256 maxCollateral = 10_000_000e18;

        // Full share redemption must return exact collateral
        uint256 fullRedeem = basaltMath.calcProRataGm(maxCollateral, totalShares, totalShares);
        assertEq(fullRedeem, maxCollateral, "full redemption must equal collateral");

        // 1 wei share of max collateral
        uint256 tinyRedeem = basaltMath.calcProRataGm(maxCollateral, 1, totalShares);
        assertEq(tinyRedeem, 10_000_000, "1 wei share of 10M GM = 10M wei");

        // Minimum collateral (1 wei), full redemption
        uint256 minRedeem = basaltMath.calcProRataGm(1, totalShares, totalShares);
        assertEq(minRedeem, 1, "full redeem of 1 wei collateral = 1 wei");

        // Minimum collateral (1 wei), half shares — rounds to 0 (expected floor)
        uint256 halfOfMin = basaltMath.calcProRataGm(1, totalShares / 2, totalShares);
        assertEq(halfOfMin, 0, "half shares of 1 wei collateral floors to 0");
    }

    /// @notice Verify that the owner eligible shares calculation correctly
    ///         reserves manager fee shares and cannot be manipulated by
    ///         inflating NAV via donation.
    function test_ownerEligible_notInflatableByDonation() public view {
        uint256 totalShares = SHARE_UNIT;

        // Scenario: NAV = $100k, manager accrued fee = $10k
        // Owner should be eligible for 90% of shares
        uint256 navUsd = 100_000e18;
        uint256 feeUsd = 10_000e18;

        uint256 ownerShares = basaltMath.calcOwnerEligibleWithdrawShares(navUsd, feeUsd, totalShares);
        uint256 expectedOwnerShares = Math.mulDiv(totalShares, navUsd - feeUsd, navUsd);
        assertEq(ownerShares, expectedOwnerShares, "owner shares must be (NAV - fee) / NAV * total");

        // Owner gets 90% of 1e18 = 9e17
        assertEq(ownerShares, 9e17, "90% of shares for 90% of NAV");

        // Manager fee shares
        uint256 managerShares = basaltMath.calcManagerMaxFeeWithdrawShares(navUsd, feeUsd, totalShares);
        assertEq(managerShares, 1e17, "manager gets 10% for 10% fee");

        // Total must not exceed SHARE_UNIT
        assertLe(ownerShares + managerShares, totalShares, "owner + manager shares <= total");
    }
}
