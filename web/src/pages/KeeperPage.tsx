import { useState, useCallback, useEffect } from 'react';
import { motion } from 'motion/react';
import { useAccount, useConnect, useDisconnect, useWalletClient, useSwitchChain } from 'wagmi';
import { injected } from 'wagmi/connectors';
import { parseAbi, type Address } from 'viem';
import { arbitrum } from 'wagmi/chains';
import { Header } from '../components/layout/Header';
import { Footer } from '../components/layout/Footer';
import { arbClient } from '../lib/arbClient';
import styles from './KeeperPage.module.css';

const ARBITRUM_CHAIN_ID = arbitrum.id; // 42161
const REFETCH_INTERVAL_MS = 12_000; // ~1 Arbitrum block

// Deployment 4 addresses
const C = {
  VAULT_CORE_NFT_FACTORY: '0xf8bd4b049b330B96B4e495245cd8babCF82FbFea' as Address,
  MANAGER_CONTRACT: '0x19CD1BDec491d555145F6DDD3474C052b8d10E75' as Address,
  DEPOSIT_HANDLER: '0xaf262a3098c29a478C0F78275D68CEaD87c7DD63' as Address,
  WITHDRAW_HANDLER: '0xCC48c39Ec0e46eC147Fb6dfE3f26af471088Bd84' as Address,
  MANAGE_HANDLER: '0x7FCD2e53a95814cD1DBa09594b849a5159f04768' as Address,
  FEE_ACCOUNTING_HANDLER: '0x4EC35d4dE14f2621bDd27aAb9d8A5B706A8088CC' as Address,
  ASYNC_RECOVERY_HANDLER: '0x4439036e883F4bd42d923AFA57C7c070beA99544' as Address,
};

// Minimal ABIs for keeper operations
const DEPOSIT_HANDLER_ABI = parseAbi([
  'function finalizeDeposit(address targetVaultCore) external',
  'function deposit(address targetVaultCore, uint256 amountGmE18, uint256 userSlippageBps) external payable',
]);

const WITHDRAW_HANDLER_ABI = parseAbi([
  'function finalizeWithdraw(address targetVaultCore) external',
]);

const MANAGER_CONTRACT_ABI = parseAbi([
  'function rebalanceVault(address handler, address vault, uint256 managerSlippageBps) external payable',
  'function finalizeRebalance(address handler, address vault) external',
  'function setVaultTargetLtv(address handler, address vault, uint256 bps) external',
  'function finalizeDeposit(address depositHandler, address targetVaultCore) external',
  'function finalizeWithdraw(address withdrawHandler, address targetVaultCore) external',
]);

const FACTORY_ABI = parseAbi([
  'function createVaultCore(address owner) external returns (uint256 tokenId, address vaultCore)',
  'function nextTokenId() external view returns (uint256)',
  'function vaultByTokenId(uint256 tokenId) external view returns (address)',
  'function ownerOf(uint256 tokenId) external view returns (address)',
]);

const VAULT_CORE_ABI = parseAbi([
  'function basaltState() external view returns (address)',
]);

const VAULT_STATE_ABI = parseAbi([
  'function depositState() external view returns (uint8)',
  'function withdrawState() external view returns (uint8)',
  'function rebalanceState() external view returns (uint8)',
  'function lastFinalizedGmCollateralE18() external view returns (uint256)',
  'function lastFinalizedWbtcDebtE8() external view returns (uint256)',
  'function lastFinalizedNavUsdE18() external view returns (uint256)',
  'function totalDepositedGmE18() external view returns (uint256)',
  'function targetLtvBps() external view returns (uint256)',
]);

const MANAGE_HANDLER_READ_ABI = parseAbi([
  'function currentLtvBps(address targetVaultCore) external view returns (uint256)',
]);


function truncAddr(a: string) { return `${a.slice(0, 6)}...${a.slice(-4)}`; }

/** Parse wallet/RPC error into a human-readable log message */
function parseTxError(e: unknown): string {
  const err = e as { shortMessage?: string; message?: string; details?: string; cause?: { shortMessage?: string } };
  const msg = err.shortMessage || err.cause?.shortMessage || err.details || err.message || 'Unknown error';
  if (/user rejected|user denied/i.test(msg)) return 'Transaction cancelled by user';
  if (/insufficient funds/i.test(msg)) return 'Not enough ETH for gas';
  return msg;
}

export function KeeperPage() {
  const { address, isConnected, chain } = useAccount();
  const { connect, isPending: isConnecting } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain } = useSwitchChain();
  const { data: walletClient } = useWalletClient();

  const isWrongChain = isConnected && chain?.id !== ARBITRUM_CHAIN_ID;

  const [log, setLog] = useState<string[]>(['Ready. Connect MetaMask with operational role.']);
  const [vaultAddr, setVaultAddr] = useState('');
  const [targetLtv, setTargetLtv] = useState('5000');
  const [slippage, setSlippage] = useState('100');
  const [execFee, setExecFee] = useState('0.0003');
  const [autoRefresh, setAutoRefresh] = useState(false);

  // All Vaults overview state
  interface VaultRow {
    tokenId: number;
    vaultCore: Address;
    owner: Address;
    currentLtvBps: number;
    targetLtvBps: number;
    deviationBps: number;
    depositState: number;
    withdrawState: number;
    rebalanceState: number;
  }
  const [allVaults, setAllVaults] = useState<VaultRow[]>([]);
  const [loadingVaults, setLoadingVaults] = useState(false);

  const addLog = useCallback((msg: string) => {
    setLog(prev => [`[${new Date().toLocaleTimeString()}] ${msg}`, ...prev].slice(0, 100));
  }, []);

  async function sendTx(description: string, fn: () => Promise<`0x${string}`>) {
    try {
      addLog(`... ${description}...`);
      const hash = await fn();
      addLog(`Tx sent: ${truncAddr(hash)} -- https://arbiscan.io/tx/${hash}`);
      const receipt = await arbClient.waitForTransactionReceipt({ hash });
      if (receipt.status === 'success') {
        addLog(`OK ${description} -- confirmed (block ${receipt.blockNumber})`);
      } else {
        addLog(`FAIL ${description} -- REVERTED`);
      }
      return receipt;
    } catch (e: unknown) {
      addLog(`FAIL ${description} -- ${parseTxError(e)}`);
      return null;
    }
  }

  const vaultAddress = (vaultAddr || '') as Address;
  const fee = BigInt(Math.floor(parseFloat(execFee) * 1e18));

  // Actions
  async function finalizeDeposit() {
    if (!walletClient || !vaultAddress) return;
    await sendTx('finalizeDeposit', () =>
      walletClient.writeContract({
        address: C.MANAGER_CONTRACT, abi: MANAGER_CONTRACT_ABI,
        functionName: 'finalizeDeposit', args: [C.DEPOSIT_HANDLER, vaultAddress],
      })
    );
  }

  async function finalizeWithdraw() {
    if (!walletClient || !vaultAddress) return;
    await sendTx('finalizeWithdraw', () =>
      walletClient.writeContract({
        address: C.MANAGER_CONTRACT, abi: MANAGER_CONTRACT_ABI,
        functionName: 'finalizeWithdraw', args: [C.WITHDRAW_HANDLER, vaultAddress],
      })
    );
  }

  async function rebalance() {
    if (!walletClient || !vaultAddress) return;
    await sendTx('rebalanceVault', () =>
      walletClient.writeContract({
        address: C.MANAGER_CONTRACT, abi: MANAGER_CONTRACT_ABI,
        functionName: 'rebalanceVault', args: [C.MANAGE_HANDLER, vaultAddress, BigInt(slippage)],
        value: fee,
      })
    );
  }

  async function finalizeRebalance() {
    if (!walletClient || !vaultAddress) return;
    await sendTx('finalizeRebalance', () =>
      walletClient.writeContract({
        address: C.MANAGER_CONTRACT, abi: MANAGER_CONTRACT_ABI,
        functionName: 'finalizeRebalance', args: [C.MANAGE_HANDLER, vaultAddress],
      })
    );
  }

  async function setTargetLtvCall() {
    if (!walletClient || !vaultAddress) return;
    await sendTx(`setVaultTargetLtv(${targetLtv})`, () =>
      walletClient.writeContract({
        address: C.MANAGER_CONTRACT, abi: MANAGER_CONTRACT_ABI,
        functionName: 'setVaultTargetLtv', args: [C.MANAGE_HANDLER, vaultAddress, BigInt(targetLtv)],
      })
    );
  }

  async function createVault() {
    if (!walletClient || !address) return;
    await sendTx('createVaultCore', () =>
      walletClient.writeContract({
        address: C.VAULT_CORE_NFT_FACTORY, abi: FACTORY_ABI,
        functionName: 'createVaultCore', args: [address],
      })
    );
  }


  const loadAllVaults = useCallback(async () => {
    setLoadingVaults(true);
    addLog('Loading all vaults...');
    try {
      const nextId = await arbClient.readContract({
        address: C.VAULT_CORE_NFT_FACTORY, abi: FACTORY_ABI, functionName: 'nextTokenId',
      }) as bigint;

      const rows: VaultRow[] = [];
      for (let i = 1n; i < nextId; i++) {
        try {
          const [owner, vc] = await Promise.all([
            arbClient.readContract({ address: C.VAULT_CORE_NFT_FACTORY, abi: FACTORY_ABI, functionName: 'ownerOf', args: [i] }) as Promise<Address>,
            arbClient.readContract({ address: C.VAULT_CORE_NFT_FACTORY, abi: FACTORY_ABI, functionName: 'vaultByTokenId', args: [i] }) as Promise<Address>,
          ]);

          const stateAddr = await arbClient.readContract({ address: vc, abi: VAULT_CORE_ABI, functionName: 'basaltState' }) as Address;

          const res = await arbClient.multicall({
            contracts: [
              { address: stateAddr, abi: VAULT_STATE_ABI, functionName: 'depositState' },
              { address: stateAddr, abi: VAULT_STATE_ABI, functionName: 'withdrawState' },
              { address: stateAddr, abi: VAULT_STATE_ABI, functionName: 'rebalanceState' },
              { address: stateAddr, abi: VAULT_STATE_ABI, functionName: 'targetLtvBps' },
              { address: C.MANAGE_HANDLER, abi: MANAGE_HANDLER_READ_ABI, functionName: 'currentLtvBps', args: [vc] },
            ],
          });

          const ok = (idx: number) => res[idx].status === 'success';
          const v = (idx: number) => res[idx].result;

          const dS = ok(0) ? Number(v(0)) : 0;
          const wS = ok(1) ? Number(v(1)) : 0;
          const rS = ok(2) ? Number(v(2)) : 0;
          const tgt = ok(3) ? Number(v(3)) : 0;
          const cur = ok(4) ? Number(v(4)) : 0;

          rows.push({
            tokenId: Number(i), vaultCore: vc, owner,
            currentLtvBps: cur, targetLtvBps: tgt, deviationBps: cur - tgt,
            depositState: dS, withdrawState: wS, rebalanceState: rS,
          });
        } catch { /* burned token */ }
      }

      setAllVaults(rows);
      addLog(`Loaded ${rows.length} vaults`);
    } catch (e: unknown) {
      addLog(`FAIL loadAllVaults: ${parseTxError(e)}`);
    } finally {
      setLoadingVaults(false);
    }
  }, [addLog]);

  async function rebalanceVault(vc: Address) {
    if (!walletClient) return;
    await sendTx(`rebalanceVault(${truncAddr(vc)})`, () =>
      walletClient.writeContract({
        address: C.MANAGER_CONTRACT, abi: MANAGER_CONTRACT_ABI,
        functionName: 'rebalanceVault', args: [C.MANAGE_HANDLER, vc, BigInt(slippage)],
        value: fee,
      })
    );
  }

  async function finalizeRebalanceVault(vc: Address) {
    if (!walletClient) return;
    await sendTx(`finalizeRebalance(${truncAddr(vc)})`, () =>
      walletClient.writeContract({
        address: C.MANAGER_CONTRACT, abi: MANAGER_CONTRACT_ABI,
        functionName: 'finalizeRebalance', args: [C.MANAGE_HANDLER, vc],
      })
    );
  }

  async function finalizeDepositVault(vc: Address) {
    if (!walletClient) return;
    await sendTx(`finalizeDeposit(${truncAddr(vc)})`, () =>
      walletClient.writeContract({
        address: C.MANAGER_CONTRACT, abi: MANAGER_CONTRACT_ABI,
        functionName: 'finalizeDeposit', args: [C.DEPOSIT_HANDLER, vc],
      })
    );
  }

  async function finalizeWithdrawVault(vc: Address) {
    if (!walletClient) return;
    await sendTx(`finalizeWithdraw(${truncAddr(vc)})`, () =>
      walletClient.writeContract({
        address: C.MANAGER_CONTRACT, abi: MANAGER_CONTRACT_ABI,
        functionName: 'finalizeWithdraw', args: [C.WITHDRAW_HANDLER, vc],
      })
    );
  }

  const readVaultState = useCallback(async () => {
    if (!vaultAddress) return;
    try {
      addLog('Reading vault state...');
      // Step 1: get VaultState address
      const stateAddr = await arbClient.readContract({
        address: vaultAddress, abi: VAULT_CORE_ABI, functionName: 'basaltState',
      }) as Address;

      // Step 2: multicall on VaultState
      const results = await arbClient.multicall({
        contracts: [
          { address: stateAddr, abi: VAULT_STATE_ABI, functionName: 'depositState' },
          { address: stateAddr, abi: VAULT_STATE_ABI, functionName: 'withdrawState' },
          { address: stateAddr, abi: VAULT_STATE_ABI, functionName: 'rebalanceState' },
          { address: stateAddr, abi: VAULT_STATE_ABI, functionName: 'lastFinalizedGmCollateralE18' },
          { address: stateAddr, abi: VAULT_STATE_ABI, functionName: 'lastFinalizedWbtcDebtE8' },
          { address: stateAddr, abi: VAULT_STATE_ABI, functionName: 'lastFinalizedNavUsdE18' },
          { address: stateAddr, abi: VAULT_STATE_ABI, functionName: 'totalDepositedGmE18' },
          { address: C.MANAGE_HANDLER, abi: MANAGE_HANDLER_READ_ABI, functionName: 'currentLtvBps', args: [vaultAddress] },
        ],
      });

      const states = ['IDLE', 'PENDING'];
      const ok = (i: number) => results[i].status === 'success';
      const val = (i: number) => results[i].status === 'success' ? results[i].result : null;

      const d = ok(0) ? states[val(0) as number] ?? '?' : '?';
      const w = ok(1) ? states[val(1) as number] ?? '?' : '?';
      const r = ok(2) ? states[val(2) as number] ?? '?' : '?';
      const gmE18 = ok(3) ? Number(val(3) as bigint) / 1e18 : 0;
      const wbtcDebtE8 = ok(4) ? Number(val(4) as bigint) / 1e8 : 0;
      const navUsdE18 = ok(5) ? Number(val(5) as bigint) / 1e18 : 0;
      const totalDepGm = ok(6) ? Number(val(6) as bigint) / 1e18 : 0;
      const ltvBps = ok(7) ? Number(val(7) as bigint) : 0;

      addLog(`States -- D:${d} W:${w} R:${r}`);
      addLog(`LTV: ${(ltvBps / 100).toFixed(1)}% | NAV: $${navUsdE18.toFixed(2)} | GM: ${gmE18.toFixed(4)} | WBTC debt: ${wbtcDebtE8.toFixed(6)}`);
      addLog(`Total deposited GM: ${totalDepGm.toFixed(4)}`);
    } catch (e: unknown) {
      addLog(`FAIL Read failed: ${parseTxError(e)}`);
    }
  }, [vaultAddress, addLog]);

  // Auto-refresh every ~12s when toggled on
  useEffect(() => {
    if (!autoRefresh || !isConnected || isWrongChain || !vaultAddr) return;
    const timer = setInterval(readVaultState, REFETCH_INTERVAL_MS);
    return () => clearInterval(timer);
  }, [autoRefresh, isConnected, isWrongChain, vaultAddr, readVaultState]);

  return (
    <>
      <a href="#main-content" className="skip-link">Skip to main content</a>
      <Header />
      <main id="main-content" className={styles.page}>
        <div className={styles.topBar}>
          <h1 className={styles.title}>Keeper Dashboard</h1>
          {isConnected ? (
            <div className={styles.connected}>
              {isWrongChain && (
                <button className={styles.connectBtn} style={{ background: 'var(--magma-500, #e55)' }}
                  onClick={() => switchChain({ chainId: ARBITRUM_CHAIN_ID })}>
                  Switch to Arbitrum
                </button>
              )}
              <span className={styles.addr}>{truncAddr(address!)}</span>
              <button className={styles.disconnectBtn} onClick={() => disconnect()} aria-label="Disconnect wallet">x</button>
            </div>
          ) : (
            <button className={styles.connectBtn} disabled={isConnecting}
              onClick={() => connect({ connector: injected() })}>
              {isConnecting ? 'Connecting...' : 'Connect MetaMask'}
            </button>
          )}
        </div>

        {!isConnected && (
          <div className={styles.prompt}>Connect MetaMask with the operational role address to use keeper functions.</div>
        )}

        {isConnected && isWrongChain && (
          <div className={styles.prompt}>Wrong network. Switch to Arbitrum One to continue.</div>
        )}

        {isConnected && !isWrongChain && (
          <>
            {/* All Vaults Overview */}
            <div className={styles.section}>
              <div className={styles.sectionTitle} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <span>All Vaults</span>
                <button className={styles.smallBtn} onClick={loadAllVaults} disabled={loadingVaults}
                  style={{ marginBottom: 0, height: 28, fontSize: 9 }}>
                  {loadingVaults ? 'Loading...' : 'Refresh'}
                </button>
              </div>
              {allVaults.length === 0 && !loadingVaults && (
                <div style={{ font: '400 11px/1.5 var(--font-mono)', color: 'var(--fg-faint)', padding: '8px 0' }}>
                  Click Refresh to load all vaults
                </div>
              )}
              {allVaults.map(v => {
                const states = ['IDLE', 'PENDING'];
                const dS = states[v.depositState] ?? '?';
                const wS = states[v.withdrawState] ?? '?';
                const rS = states[v.rebalanceState] ?? '?';
                const hasPending = v.depositState === 1 || v.withdrawState === 1 || v.rebalanceState === 1;
                const devAbs = Math.abs(v.deviationBps);
                const needsRebalance = v.currentLtvBps > 0 && v.targetLtvBps > 0 && !hasPending &&
                  ((v.deviationBps > 0 && devAbs >= 700) || (v.deviationBps < 0 && devAbs >= 1700));

                const devColor = needsRebalance ? 'var(--magma-500, #e55)' :
                  devAbs > 300 ? 'var(--ember-500, #ff6a3d)' : 'var(--fg-muted)';

                return (
                  <div key={v.tokenId} style={{
                    display: 'flex', alignItems: 'center', gap: 8, padding: '6px 8px',
                    background: needsRebalance ? 'rgba(229,85,85,0.06)' : 'var(--bg-inset)',
                    borderRadius: 'var(--radius-2)', marginBottom: 4,
                    border: needsRebalance ? '1px solid rgba(229,85,85,0.2)' : '1px solid transparent',
                  }}>
                    <span style={{ font: '600 10px/1 var(--font-mono)', color: 'var(--fg-muted)', minWidth: 20 }}>#{v.tokenId}</span>
                    <button
                      style={{ font: '400 10px/1 var(--font-mono)', color: 'var(--ember-500)', background: 'none', border: 'none', cursor: 'pointer', padding: 0 }}
                      onClick={() => { setVaultAddr(v.vaultCore); }}
                      title={v.vaultCore}
                    >{truncAddr(v.vaultCore)}</button>
                    <span style={{ font: '500 10px/1 var(--font-mono)', color: 'var(--fg-default)', minWidth: 55 }}>
                      LTV {(v.currentLtvBps / 100).toFixed(1)}%
                    </span>
                    <span style={{ font: '400 9px/1 var(--font-mono)', color: 'var(--fg-faint)', minWidth: 50 }}>
                      tgt {(v.targetLtvBps / 100).toFixed(1)}%
                    </span>
                    <span style={{ font: '600 9px/1 var(--font-mono)', color: devColor, minWidth: 55 }}>
                      {v.deviationBps > 0 ? '+' : ''}{v.deviationBps} bp
                    </span>
                    <span style={{ font: '400 8px/1 var(--font-mono)', color: hasPending ? 'var(--ember-500)' : 'var(--fg-faint)', minWidth: 60 }}>
                      D:{dS} W:{wS} R:{rS}
                    </span>
                    <span style={{ flex: 1 }} />
                    {v.depositState === 1 && (
                      <button className={styles.smallBtn} style={{ height: 24, fontSize: 8, padding: '0 6px' }}
                        onClick={() => finalizeDepositVault(v.vaultCore)}>fin.dep</button>
                    )}
                    {v.withdrawState === 1 && (
                      <button className={styles.smallBtn} style={{ height: 24, fontSize: 8, padding: '0 6px' }}
                        onClick={() => finalizeWithdrawVault(v.vaultCore)}>fin.wd</button>
                    )}
                    {v.rebalanceState === 1 && (
                      <button className={styles.smallBtn} style={{ height: 24, fontSize: 8, padding: '0 6px' }}
                        onClick={() => finalizeRebalanceVault(v.vaultCore)}>fin.reb</button>
                    )}
                    {!hasPending && v.currentLtvBps > 0 && (
                      <button className={styles.smallBtn}
                        style={{ height: 24, fontSize: 8, padding: '0 6px',
                          borderColor: needsRebalance ? 'var(--magma-500, #e55)' : undefined,
                          color: needsRebalance ? 'var(--magma-500, #e55)' : undefined,
                        }}
                        onClick={() => rebalanceVault(v.vaultCore)}>rebalance</button>
                    )}
                  </div>
                );
              })}
            </div>

            {/* Vault address input */}
            <div className={styles.section}>
              <div className={styles.sectionTitle}>Target vault</div>
              <div className={styles.inputRow}>
                <input className={styles.inp} value={vaultAddr} onChange={e => setVaultAddr(e.target.value)} placeholder="0x... vault core address" />
                <button className={styles.smallBtn} onClick={() => readVaultState()}>Read state</button>
                <button className={styles.smallBtn} onClick={createVault}>Create new</button>
              </div>
              <label style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 6, font: '400 10px/1 var(--font-mono)', color: 'var(--fg-muted)', cursor: 'pointer' }}>
                <input type="checkbox" checked={autoRefresh} onChange={e => setAutoRefresh(e.target.checked)} />
                Auto-refresh (~12s)
              </label>
            </div>

            {/* Params */}
            <div className={styles.section}>
              <div className={styles.sectionTitle}>Params</div>
              <div className={styles.paramRow}>
                <label>Exec fee (ETH)</label>
                <input className={styles.paramInp} value={execFee} onChange={e => setExecFee(e.target.value)} />
              </div>
              <div className={styles.paramRow}>
                <label>Slippage (bps)</label>
                <input className={styles.paramInp} value={slippage} onChange={e => setSlippage(e.target.value)} />
              </div>
              <div className={styles.paramRow}>
                <label>Target LTV (bps)</label>
                <input className={styles.paramInp} value={targetLtv} onChange={e => setTargetLtv(e.target.value)} />
                <button className={styles.smallBtn} onClick={setTargetLtvCall}>Set</button>
                <span style={{ font: '400 9px/1 var(--font-mono)', color: 'var(--fg-faint)', marginLeft: 4 }}>Requires configurator role</span>
              </div>
            </div>

            {/* Finalize */}
            <div className={styles.section}>
              <div className={styles.sectionTitle}>Finalize (keeper)</div>
              <div className={styles.btnGrid}>
                <button className={styles.actionBtn} onClick={finalizeDeposit}>finalizeDeposit</button>
                <button className={styles.actionBtn} onClick={finalizeWithdraw}>finalizeWithdraw</button>
                <button className={styles.actionBtn} onClick={finalizeRebalance}>finalizeRebalance</button>
              </div>
            </div>

            {/* Rebalance */}
            <div className={styles.section}>
              <div className={styles.sectionTitle}>Rebalance (manager)</div>
              <div className={styles.btnGrid}>
                <button className={styles.actionBtn} onClick={rebalance}>rebalanceVault</button>
              </div>
            </div>

            {/* Contracts ref */}
            <details className={styles.section}>
              <summary className={styles.sectionTitle}>Addresses (Deployment 4)</summary>
              <div className={styles.addrGrid}>
                {Object.entries(C).map(([k, v]) => (
                  <div key={k} className={styles.addrRow}>
                    <span className={styles.addrK}>{k}</span>
                    <a href={`https://arbiscan.io/address/${v}`} target="_blank" rel="noopener noreferrer" className={styles.addrV}>{truncAddr(v)}</a>
                  </div>
                ))}
              </div>
            </details>
          </>
        )}

        {/* Log */}
        <div className={styles.logSection}>
          <div className={styles.sectionTitle}>Log</div>
          <div className={styles.logBox}>
            {log.map((l, i) => (
              <motion.div key={`${i}-${l.slice(0,20)}`} className={styles.logLine}
                initial={i === 0 ? { opacity: 0, x: -8 } : {}}
                animate={{ opacity: 1, x: 0 }}>
                {l}
              </motion.div>
            ))}
          </div>
        </div>
      </main>
      <Footer />
    </>
  );
}
