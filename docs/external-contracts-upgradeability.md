# External Contracts — Upgradeability Audit

Checked: 2026-04-28

Basalt Vault integrates with GMX v2 and Dolomite on Arbitrum One.
This document tracks which external contracts are upgradeable (proxy)
and which are immutable, so we know what can change under us.

## Summary

| Contract | Address | Upgradeable | Implementation | Risk |
|---|---|---|---|---|
| **Dolomite** | | | | |
| DolomiteMargin | [0x6Bd7...9072](https://arbiscan.io/address/0x6Bd780E7fDf01D77e4d475c821f1e7AE05409072) | No | — | Low |
| VaultFactory | [0x1E8e...d0eF](https://arbiscan.io/address/0x1E8e8B7a2F827b3bc12B00eE402145061b7050eF) | No | — | Low |
| GM Wrapper | [0xc58c...06D8](https://arbiscan.io/address/0xc58ccFB7c8207Ab9b1b2cE89b292c5dB353E06D8) | **Yes** | [0xf525...d1ec](https://arbiscan.io/address/0xf525b07085b7D79eb4D5c14194E496bE65B9d1ec) | High |
| GM Unwrapper | [0x2B9D...2758](https://arbiscan.io/address/0x2B9D148fABCAA522015492d205CAD9F2b4852758) | **Yes** | [0x76ae...27CC](https://arbiscan.io/address/0x76aeBE84012abDEf340dcb92f418b1B2423027CC) | High |
| Isolation Vault (ours) | per-user, created via VaultCoreNftFactory [0xf8bd...bFea](https://arbiscan.io/address/0xa1ba8dc91211aaf2ddf45bbd05f88c8632e8ac83) | **Yes** | per-vault, read via `dolomiteVault().implementation()` | High |
| **GMX v2** | | | | |
| DataStore | [0xFD70...d8](https://arbiscan.io/address/0xFD70de6b91282D8017aA4E741e9Ae325CAb992d8) | No | — | Low |
| ExchangeRouter | [0x1C3f...6A41](https://arbiscan.io/address/0x1C3fa76e6E1088bCE750f23a5BFcffa1efEF6A41) | No | — | Low |
| DepositHandler | [0x3387...d42](https://arbiscan.io/address/0x33871b8568eDC4adf33338cdD8cF52a0eCC84D42) | No | — | Low |
| WithdrawalHandler | [0x11e9...77fd](https://arbiscan.io/address/0x11e9E7464f3Bc887a7290ec41fCd22f619b177fd) | No | — | Low |

## What "High Risk" means

Dolomite can upgrade GM Wrapper, GM Unwrapper, and all Isolation Vault
implementations at any time via VaultFactory. A malicious or buggy
upgrade could change how async wrap/unwrap works, alter callback
behavior, or modify vault storage layout. Monitor Dolomite governance
announcements and re-verify after any upgrade.

## Re-verification commands

```bash
RPC="https://arbitrum-mainnet.infura.io/v3/<YOUR_KEY>"

# Dolomite — check implementation() on proxies
cast call 0xc58ccFB7c8207Ab9b1b2cE89b292c5dB353E06D8 "implementation()(address)" --rpc-url $RPC
cast call 0x2B9D148fABCAA522015492d205CAD9F2b4852758 "implementation()(address)" --rpc-url $RPC

# Isolation Vault — per-user vault; replace <VAULT_CORE> with the address
# returned by VaultCoreNftFactory (0xa1ba8dc91211aaf2ddf45bbd05f88c8632e8ac83)
# after issueVault() is called for the user
DOLOMITE_VAULT=$(cast call <VAULT_CORE> "dolomiteVault()(address)" --rpc-url $RPC)
cast call $DOLOMITE_VAULT "implementation()(address)" --rpc-url $RPC

# GMX — verify no proxy (should fail or return nothing)
cast call 0xFD70de6b91282D8017aA4E741e9Ae325CAb992d8 "implementation()(address)" --rpc-url $RPC
cast call 0x1C3fa76e6E1088bCE750f23a5BFcffa1efEF6A41 "implementation()(address)" --rpc-url $RPC

# DolomiteMargin — verify no proxy
cast call 0x6Bd780E7fDf01D77e4d475c821f1e7AE05409072 "implementation()(address)" --rpc-url $RPC
```

If any implementation address changes from what is listed above,
investigate the upgrade before continuing vault operations.
