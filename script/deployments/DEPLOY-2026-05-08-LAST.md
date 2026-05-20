# Basalt Vault — Deployment 6 (2026-05-08)

Full redeploy on Arbitrum One. All contracts verified on Arbiscan.

## Changes from Deployment 5

- **VaultCore**: added `receive() external payable {}` (Dolomite ETH refund fix)
- **ManagerContract**: owner fallback on operational/configurator/proposer roles + 180-day voting timeout
- **VaultCoreNftFactory**: payable cast for new VaultCore
- **DeployMainnet.s.sol**: fixed protocolOwner sourcing + role assignment to deployer

## Deployed Addresses

| Contract | Address |
|----------|---------|
| BasaltMath | `0xbbfce8b98bd817fe2059a227c32ae086b4ed0c11` |
| DepositHandler | `0xf41150e3800f81b2a7987cf7dc84852855d669d6` |
| WithdrawHandler | `0x73e9395d046fbe5b8ae6bcdb4c5304bb974d1520` |
| ManagerHandler | `0xbc5150333eede35f511f0fca17b02a99fe29fec3` |
| AsyncRecoveryHandler | `0xa430d5d60d1bcb29e7e8a0a8663e644bb377fe72` |
| FeeAccountingHandler | `0x32ccb39393427801483226531be02eaf4284d6ce` |
| VaultCore (impl) | `0x8cc187846e3bee690cbb37c431701c4c587550f1` |
| VaultState (impl) | `0x9be65dfdb5a108151af95524072420d5c2075ddf` |
| InitialCoreAddressBook | `0xcd2f28939e4b9f4d2af772137396ec42ad6d8143` |
| FeeSplitter | `0x807bc93a1a3336572b4d43065baae5bb87c5bc20` |
| ManagerContract | `0x638505776382d471091f9bb8301118023d6dabb3` |
| VaultCoreNftFactory | `0x08e466fb09617d16ed27da9ea43ba601665f3b89` |
| BasaltZapIn | `0x1236384c4614c0ccc463e1ead98cb896ca2c9e87` |
| BasaltZapOut | `0x69a445d1950b053fe70a2c48a5925ab0848dd47a` |
| BasaltGmUnwrapper | `0x6c5dd45766b996aeeeb5d311d79e8d0e4c44ed98` |

## Recovery Handler (legacy vaults)

| Contract | Address |
|----------|---------|
| WithdrawRecoveryHandler | `0x9B9824CF4834dE8b9213e1D5E4B6C009141268e8` |

## External Addresses (unchanged, Arbitrum One)

| Name | Address |
|------|---------|
| GM Token (BTC/USDC) | `0x47c031236e19d024b42f8AE6780E44A573170703` |
| WBTC | `0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f` |
| USDC | `0xaf88d065e77c8cC2239327C5EDb3A432268e5831` |
| WETH | `0x82aF49447D8a07e3bd95BD0d56f35241523fBab1` |
| Dolomite Margin | `0x6Bd780E7fDf01D77e4d475c821f1e7AE05409072` |
| Dolomite VaultFactory | `0x1E8e8B7a2F827b3bc12B00eE402145061b7050eF` |
| GMX ExchangeRouter | `0x1C3fa76e6E1088bCE750f23a5BFcffa1efEF6A41` |
| GMX Router | `0x7452c558d45f8afC8c83dAe62C3f8A5BE19c71f6` |
| GMX DataStore | `0xFD70de6b91282D8017aA4E741e9Ae325CAb992d8` |
| GMX DepositVault | `0xF89e77e8Dc11691C9e8757e84aaFbCD8A67d7A55` |
| GMX WithdrawalVault | `0x0628D46b5D145f183AdB6Ef1f2c97eD1C4701C55` |
| Uniswap V3 SwapRouter | `0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45` |

## Roles

| Role | Address |
|------|---------|
| Owner (all roles) | `0x6E31dB49Bb37C96AaB9178D6c1Fcd706D626bc93` |
| Operational (Keeper) | `0x6E31dB49Bb37C96AaB9178D6c1Fcd706D626bc93` |

## Ownership Verification (cast, 2026-05-08)

- `ManagerContract.owner()` = `0x6E31...bc93` ✓
- `VaultCoreNftFactory.owner()` = `0x6E31...bc93` ✓
- `FeeSplitter.balanceOf(owner)` = 1e18 / 1e18 (100% BFS) ✓
- All roles (operational, configurator, feeCollector) = `0x6E31...bc93` ✓
