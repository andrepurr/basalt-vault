# Recovery Guide — Stuck Withdraw

If your vault's withdraw is stuck in PENDING state, follow these steps to recover your funds via Arbiscan.

You will need the wallet that owns the vault NFT (the wallet you used to create the vault).

---

## Step 1: Check if your vault is stuck

Go to your VaultState contract on Arbiscan (ask the team for the address) and call:

- `withdrawState()` — if it returns `1`, your withdraw is stuck

## Step 2: Accept the Recovery Handler

A recovery handler has already been proposed to your vault. You just need to accept it.

1. Open your **VaultCore** contract on Arbiscan:
   - Find your vault address (ask the team or check your NFT)
   - Go to `https://arbiscan.io/address/<YOUR_VAULT_ADDRESS>#writeContract`

2. Connect your wallet (the NFT owner wallet)

3. Click **"Connect to Web3"** and connect with MetaMask / WalletConnect

4. Find the function **`acceptHandler`** (no parameters needed)

5. Click **"Write"** and confirm the transaction in your wallet

6. Wait for confirmation

## Step 3: Execute Recovery

1. Open the **WithdrawRecoveryHandler** contract on Arbiscan:
   - Address: [`0x9B9824CF4834dE8b9213e1D5E4B6C009141268e8`](https://arbiscan.io/address/0x9B9824CF4834dE8b9213e1D5E4B6C009141268e8#writeContract)

2. Click **"Connect to Web3"** (same wallet as above)

3. Find the function **`recover`**

4. In the `vaultCore` field, paste **your VaultCore address**

5. Click **"Write"** and confirm the transaction

6. Wait for confirmation — your WBTC will be sent to your wallet

## Step 4: Verify

Check your wallet — you should see the WBTC balance increase. The vault's `withdrawState` should now be `0` (IDLE).

---

## What happens during recovery

- The recovery handler withdraws your WBTC surplus from the Dolomite position
- 1 satoshi (~$0.001) is left in the position to prevent a technical issue with Dolomite's fee refund mechanism
- Your vault returns to IDLE state and can be used normally again

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `NotNftOwner()` | Wrong wallet connected | Connect the wallet that owns the vault NFT |
| `not pending` | Vault is not stuck | Nothing to recover — vault is already IDLE |
| `no surplus to recover` | Position is empty | Contact the team |
| Transaction reverts on `acceptHandler` | Proposal not submitted yet | Contact the team to submit the proposal first |

## Need help?

Contact the Basalt team via Telegram.
