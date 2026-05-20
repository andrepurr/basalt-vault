import { useState, useMemo, useEffect, useCallback } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import {
  useAccount, useConnect, useDisconnect,
  useSwitchChain, useWriteContract,
} from 'wagmi';
import { injected } from 'wagmi/connectors';
import { parseAbi, parseUnits, formatUnits, keccak256, toBytes, type Address } from 'viem';
import { arbitrum } from 'wagmi/chains';
import { CONTRACTS } from '../lib/contracts';
import { useExecFee } from '../lib/useExecFee';
import { arbClient } from '../lib/arbClient';
import { Header } from '../components/layout/Header';
import s from './App2Page.module.css';

// ═══════════════════════════════════════════════════════════════════════
//  Constants
// ═══════════════════════════════════════════════════════════════════════

const ARBITRUM_CHAIN_ID = arbitrum.id;
const REFETCH_MS = 12_000;
const C = CONTRACTS[42161];
const MAX_UINT256 = 2n ** 256n - 1n;
const DOLOMITE_EXEC_FEE = 1_000_000_000_000_000n; // 0.001 ETH
const DOLOMITE_MARGIN = '0x6Bd780E7fDf01D77e4d475c821f1e7AE05409072' as Address;
// VaultIssued(uint256 indexed tokenId, address indexed owner, address indexed vaultCore)
const VAULT_ISSUED_TOPIC = keccak256(toBytes('VaultIssued(uint256,address,address)'));
const DOLOMITE_MARKET_GM = 32n;
const DOLOMITE_MARKET_WBTC = 4n;
const ISOLATION_ACCOUNT = 100n;

// ═══════════════════════════════════════════════════════════════════════
//  ABIs
// ═══════════════════════════════════════════════════════════════════════

const VAULT_CORE_ABI = parseAbi([
  'function basaltState() external view returns (address)',
  'function basaltMath() external view returns (address)',
]);

const VAULT_STATE_ABI = parseAbi([
  'function depositState() external view returns (uint8)',
  'function withdrawState() external view returns (uint8)',
  'function rebalanceState() external view returns (uint8)',
  'function totalDepositedGmE18() external view returns (uint256)',
  'function totalDepositedUsdE18() external view returns (uint256)',
  'function totalWithdrawnUsdE18() external view returns (uint256)',
  'function managerAccruedFeeUsdE18() external view returns (uint256)',
  'function dolomiteIsolationVault() external view returns (address)',
]);

const DOLOMITE_ABI = parseAbi([
  'function getAccountWei((address owner, uint256 number) account, uint256 marketId) external view returns ((bool sign, uint256 value))',
  'function getMarketPrice(uint256 marketId) external view returns ((uint256 value))',
]);

const FACTORY_ABI = parseAbi([
  'function nextTokenId() external view returns (uint256)',
  'function ownerOf(uint256 tokenId) external view returns (address)',
  'function vaultByTokenId(uint256 tokenId) external view returns (address)',
  'function balanceOf(address owner) external view returns (uint256)',
  'function createVaultCore(address owner) external returns (uint256 tokenId, address vaultCore)',
]);



const ERC20_ABI = parseAbi([
  'function balanceOf(address) external view returns (uint256)',
  'function approve(address,uint256) external returns (bool)',
  'function allowance(address,address) external view returns (uint256)',
  'function totalSupply() external view returns (uint256)',
]);

const DEPOSIT_HANDLER_ABI = parseAbi([
  'function deposit(address targetVaultCore, uint256 amountGmE18, uint256 userSlippageBps) external payable',
  'function finalizeDeposit(address targetVaultCore) external',
]);

const WITHDRAW_HANDLER_ABI = parseAbi([
  'function withdraw(address targetVaultCore, uint256 sharesToWithdraw, uint256 minWbtcOutE8) external payable',
  'function finalizeWithdraw(address targetVaultCore) external',
]);

const ZAP_IN_ABI = parseAbi([
  'function zapIn(uint256 usdcAmountE6, uint256 swapSlippageBps) external payable returns (bytes32)',
]);

const ZAP_OUT_ABI = parseAbi([
  'function zapOut(uint256 wbtcAmountE8, uint256 swapSlippageBps) external returns (uint256)',
]);

// ═══════════════════════════════════════════════════════════════════════
//  Types
// ═══════════════════════════════════════════════════════════════════════

interface VaultData {
  navUsd: number;
  ltvPct: number;
  gmCollateral: number;
  wbtcDebt: number;
  depositPending: boolean;
  withdrawPending: boolean;
  rebalancePending: boolean;
  vaultStateAddr: Address | null;
  totalDepositedGmE18: bigint;
  navUsdE18: bigint;
  managerFeeE18: bigint;
  ownershipE18: bigint;
}

interface UserBalances {
  usdcE6: bigint;
  gmE18: bigint;
  ownershipRaw: bigint;
  wbtcE8: bigint;
  ethWei: bigint;
}

type Tab = 'deposit' | 'withdraw';
type DepositMode = 'usdc' | 'gm';
type WithdrawMode = 'withdraw' | 'zapout';
type FeeTier = '10' | '20' | '30' | '50';

type FlowStatus =
  | { type: 'idle' }
  | { type: 'tx'; label: string }
  | { type: 'waiting-keeper' }
  | { type: 'gm-ready'; amount: string }
  | { type: 'deposit-pending' }
  | { type: 'deposit-done' }
  | { type: 'withdraw-pending' }
  | { type: 'withdraw-done' }
  | { type: 'wbtc-ready'; sats: string }
  | { type: 'error'; message: string };

// ═══════════════════════════════════════════════════════════════════════
//  Helpers
// ═══════════════════════════════════════════════════════════════════════

function parseWalletError(err: unknown): string {
  const e = err as { shortMessage?: string; message?: string; details?: string; cause?: { shortMessage?: string } };
  const msg = e.shortMessage || e.cause?.shortMessage || e.details || e.message || 'Unknown error';
  if (/user rejected|user denied/i.test(msg)) return 'Transaction cancelled by user';
  if (/insufficient funds/i.test(msg)) return 'Not enough ETH for gas';
  if (/execution reverted/i.test(msg)) return msg;
  return msg;
}

// ═══════════════════════════════════════════════════════════════════════
//  VaultGem — procedural crystal from address hash
// ═══════════════════════════════════════════════════════════════════════

function addrToSeed(addr: string): number {
  let h = 0;
  for (let i = 2; i < addr.length; i++) h = ((h << 5) - h + addr.charCodeAt(i)) | 0;
  return Math.abs(h);
}

function VaultGem({ addr, size = 20 }: { addr: string; size?: number }) {
  const seed = addrToSeed(addr);
  const hue1 = seed % 360;
  const hue2 = (hue1 + 40 + (seed >> 8) % 80) % 360;
  const hue3 = (hue1 + 160 + (seed >> 16) % 40) % 360;
  const facets = 3 + (seed >> 4) % 4; // 3-6 facets
  const rotation = (seed >> 12) % 60 - 30;
  const pulseSpeed = 2 + (seed >> 6) % 3;

  const c1 = `hsl(${hue1}, 70%, 55%)`;
  const c2 = `hsl(${hue2}, 60%, 45%)`;
  const c3 = `hsl(${hue3}, 80%, 65%)`;
  const glow = `hsl(${hue1}, 80%, 60%)`;

  // Generate polygon points for crystal shape
  const points: string[] = [];
  const cx = size / 2, cy = size / 2, r = size * 0.4;
  for (let i = 0; i < facets; i++) {
    const angle = (Math.PI * 2 * i) / facets - Math.PI / 2;
    const jitter = 0.7 + ((seed >> (i * 3)) % 100) / 200; // 0.7-1.2
    const px = cx + Math.cos(angle) * r * jitter;
    const py = cy + Math.sin(angle) * r * jitter;
    points.push(`${px.toFixed(1)},${py.toFixed(1)}`);
  }

  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`}
      style={{ flexShrink: 0, filter: `drop-shadow(0 0 3px ${glow})`, transform: `rotate(${rotation}deg)` }}>
      <defs>
        <linearGradient id={`gem-${addr}`} x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stopColor={c1} />
          <stop offset="50%" stopColor={c2} />
          <stop offset="100%" stopColor={c3} />
        </linearGradient>
      </defs>
      <polygon points={points.join(' ')} fill={`url(#gem-${addr})`} opacity="0.9">
        <animate attributeName="opacity" values="0.7;1;0.7" dur={`${pulseSpeed}s`} repeatCount="indefinite" />
      </polygon>
      {/* Inner highlight facet */}
      <polygon points={points.slice(0, Math.ceil(facets / 2)).join(' ') + ` ${cx},${cy}`}
        fill={c3} opacity="0.25" />
    </svg>
  );
}

function fmtNum(n: number, d: number): string {
  if (n === 0) return '0';
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(d)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(d)}K`;
  return n.toFixed(d);
}

function fmtSats(wbtcE8: bigint): string {
  const sats = Number(wbtcE8);
  if (sats >= 1_000_000) return `${(sats / 1_000_000).toFixed(2)}M`;
  if (sats >= 1_000) return `${(sats / 1_000).toFixed(1)}K`;
  return sats.toFixed(0);
}

function fmtEthShort(wei: bigint): string {
  const eth = Number(wei) / 1e18;
  if (eth >= 10) return eth.toFixed(2);
  if (eth >= 1) return eth.toFixed(3);
  return eth.toFixed(4);
}

// ═══════════════════════════════════════════════════════════════════════
//  LTV Bar — animated needle with floating value
// ═══════════════════════════════════════════════════════════════════════

function LtvBar({ ltvPct, visible }: { ltvPct: number; visible: boolean }) {
  const clampedPct = Math.min(Math.max(ltvPct, 0), 100);
  const pos = `${clampedPct}%`;
  const color = clampedPct < 70 ? 'var(--mineral-500)' : clampedPct < 83.8 ? 'var(--sulfur-500)' : 'var(--magma-500)';
  const colorClass = clampedPct < 70 ? s.ltvHealthy : clampedPct < 83.8 ? s.ltvWarning : s.ltvDanger;

  return (
    <div className={s.ltvBar} style={!visible ? { opacity: 0 } : undefined}>
      {/* Current value label — above needle */}
      <div className={s.ltvValueRow}>
        <motion.div
          className={`${s.ltvValueBubble} ${colorClass}`}
          style={{ left: pos }}
          animate={{ left: pos }}
          transition={{ type: 'tween', duration: 2, ease: 'easeInOut' }}
        >
          {clampedPct.toFixed(2)}%
        </motion.div>
      </div>
      {/* Track */}
      <div className={s.ltvTrack}>
        <div className={s.ltvZoneGreen} />
        <div className={s.ltvZoneYellow} />
        <div className={s.ltvZoneRed} />
        {/* Glow behind needle */}
        <motion.div
          className={s.ltvGlow}
          style={{ background: color }}
          animate={{ left: pos }}
          transition={{ type: 'tween', duration: 2, ease: 'easeInOut' }}
        />
        <motion.div
          className={s.ltvNeedle}
          style={{ background: color, boxShadow: `0 0 6px ${color}` }}
          animate={{ left: pos }}
          transition={{ type: 'tween', duration: 2, ease: 'easeInOut' }}
        />
      </div>
      {/* Zone labels */}
      <div className={s.ltvLabels}>
        <span>0%</span>
        <span className={s.ltvLabel70}>70</span>
        <span className={s.ltvLabel78}>83.8</span>
        <span className={s.ltvLabelEnd}>100%</span>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════
//  Main App2Page
// ═══════════════════════════════════════════════════════════════════════

export function App2Page() {
  // ── State ──
  const [tab, setTab] = useState<Tab>('deposit');
  const [depositMode, setDepositMode] = useState<DepositMode>('usdc');
  const [withdrawMode, setWithdrawMode] = useState<WithdrawMode>('withdraw');
  const [amount, setAmount] = useState('');
  const [slippage, setSlippage] = useState('100');
  const [vaultAddr, setVaultAddr] = useState('');
  const [vaultData, setVaultData] = useState<VaultData | null>(null);
  const [balances, setBalances] = useState<UserBalances | null>(null);
  const [loading, setLoading] = useState(false);
  const [vaultDetected, setVaultDetected] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [flow, setFlow] = useState<FlowStatus>({ type: 'idle' });
  const [showManual, setShowManual] = useState(false);
  const [creating, setCreating] = useState(false);
  const [feeTier, setFeeTier] = useState<FeeTier>('30');
  const [allVaults, setAllVaults] = useState<string[]>([]);
  const [vaultDropdown, setVaultDropdown] = useState(false);
  const [withdrawPct, setWithdrawPct] = useState(() => localStorage.getItem('basalt_withdraw_pct') || '');
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [copied, setCopied] = useState(false);
  const [maxRaw, setMaxRaw] = useState<bigint | null>(null);

  // ── Wagmi hooks ──
  const { isConnected, chain, address } = useAccount();
  const { connect, isPending: isConnecting } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain } = useSwitchChain();
  const { writeContractAsync } = useWriteContract();

  const isWrongChain = isConnected && chain?.id !== ARBITRUM_CHAIN_ID;

  // ── Exec fee ──
  const { quote: depositFeeQuote, ethUsd: depositEthUsd } = useExecFee('deposit');
  const { quote: withdrawFeeQuote, ethUsd: withdrawEthUsd } = useExecFee('withdraw');

  const isFirstDeposit = !vaultData || vaultData.totalDepositedGmE18 === 0n;
  const pickFee = (q: typeof depositFeeQuote) => {
    if (!q) return 0n;
    const pct = BigInt(100 + Number(feeTier));
    return (q.feeMinWei * pct) / 100n;
  };
  const gmxFee = pickFee(depositFeeQuote);
  const depositExtra = isFirstDeposit ? DOLOMITE_EXEC_FEE : 0n;
  const depositValue = gmxFee + depositExtra;
  const zapInFee = gmxFee;
  const withdrawFee = pickFee(withdrawFeeQuote);

  // ── Read vault data (all live from Dolomite) ──
  const readVault = useCallback(async () => {
    if (!vaultAddr || !address) return;
    const addr = vaultAddr as Address;
    setLoading(true);
    try {
      const stateAddr = await arbClient.readContract({
        address: addr, abi: VAULT_CORE_ABI, functionName: 'basaltState',
      }) as Address;

      // Step 1: get isolation vault address + vault state
      const stateResults = await arbClient.multicall({
        contracts: [
          { address: stateAddr, abi: VAULT_STATE_ABI, functionName: 'dolomiteIsolationVault' },
          { address: stateAddr, abi: VAULT_STATE_ABI, functionName: 'depositState' },
          { address: stateAddr, abi: VAULT_STATE_ABI, functionName: 'withdrawState' },
          { address: stateAddr, abi: VAULT_STATE_ABI, functionName: 'rebalanceState' },
          { address: stateAddr, abi: VAULT_STATE_ABI, functionName: 'totalDepositedGmE18' },
          { address: stateAddr, abi: VAULT_STATE_ABI, functionName: 'totalDepositedUsdE18' },
          { address: stateAddr, abi: VAULT_STATE_ABI, functionName: 'totalWithdrawnUsdE18' },
          { address: stateAddr, abi: VAULT_STATE_ABI, functionName: 'managerAccruedFeeUsdE18' },
          { address: C.USDC as Address, abi: ERC20_ABI, functionName: 'balanceOf', args: [address] },
          { address: C.GM_TOKEN as Address, abi: ERC20_ABI, functionName: 'balanceOf', args: [address] },
          { address: C.WBTC as Address, abi: ERC20_ABI, functionName: 'balanceOf', args: [address] },
        ],
      });

      const sv = (i: number): bigint => stateResults[i].status === 'success' ? (stateResults[i].result as bigint) : 0n;
      const isoVault = stateResults[0].status === 'success' ? (stateResults[0].result as Address) : ('0x0000000000000000000000000000000000000000' as Address);
      const depositStateVal = stateResults[1].status === 'success' ? Number(stateResults[1].result) : 0;
      const withdrawStateVal = stateResults[2].status === 'success' ? Number(stateResults[2].result) : 0;
      const rebalanceStateVal = stateResults[3].status === 'success' ? Number(stateResults[3].result) : 0;
      const totalDepositedGmRaw = sv(4);
      const totalDepositedUsdRaw = sv(5);
      const totalWithdrawnUsdRaw = sv(6);
      const managerFeeRaw = sv(7);

      // Step 2: live Dolomite reads — balances + prices
      const isoAccount = { owner: isoVault, number: ISOLATION_ACCOUNT };
      const dolomiteResults = await arbClient.multicall({
        contracts: [
          { address: DOLOMITE_MARGIN, abi: DOLOMITE_ABI, functionName: 'getAccountWei', args: [isoAccount, DOLOMITE_MARKET_GM] },
          { address: DOLOMITE_MARGIN, abi: DOLOMITE_ABI, functionName: 'getAccountWei', args: [isoAccount, DOLOMITE_MARKET_WBTC] },
          { address: DOLOMITE_MARGIN, abi: DOLOMITE_ABI, functionName: 'getMarketPrice', args: [DOLOMITE_MARKET_GM] },
          { address: DOLOMITE_MARGIN, abi: DOLOMITE_ABI, functionName: 'getMarketPrice', args: [DOLOMITE_MARKET_WBTC] },
        ],
      });

      // Parse Dolomite Wei structs: { sign: bool, value: bigint }
      const gmWei = dolomiteResults[0].status === 'success' ? (dolomiteResults[0].result as { sign: boolean; value: bigint }) : { sign: true, value: 0n };
      const wbtcWei = dolomiteResults[1].status === 'success' ? (dolomiteResults[1].result as { sign: boolean; value: bigint }) : { sign: true, value: 0n };
      const gmPriceE18 = dolomiteResults[2].status === 'success' ? ((dolomiteResults[2].result as { value: bigint }).value) : 0n;
      // WBTC price from Dolomite is E28 (36 - 8 decimals)
      const wbtcPriceE28 = dolomiteResults[3].status === 'success' ? ((dolomiteResults[3].result as { value: bigint }).value) : 0n;

      // Live collateral (sign=true, GM market)
      const gmCollateralE18 = gmWei.sign && gmWei.value > 0n ? gmWei.value : 0n;
      // Live debt (sign=false, WBTC market)
      const wbtcDebtE8 = !wbtcWei.sign && wbtcWei.value > 0n ? wbtcWei.value : 0n;
      // Live surplus (sign=true, WBTC market)
      const wbtcSurplusE8 = wbtcWei.sign && wbtcWei.value > 0n ? wbtcWei.value : 0n;

      // Compute live NAV: gmCollateral * gmPrice + wbtcSurplus * wbtcPrice - wbtcDebt * wbtcPrice
      // gmPrice is E18, wbtcPrice is E28
      const gmValueE18 = gmPriceE18 > 0n ? gmCollateralE18 * gmPriceE18 / (10n ** 18n) : 0n;
      const wbtcPriceE18 = wbtcPriceE28 / (10n ** 10n); // E28 → E18
      const debtValueE18 = wbtcPriceE18 > 0n ? wbtcDebtE8 * wbtcPriceE18 / (10n ** 8n) : 0n;
      const surplusValueE18 = wbtcPriceE18 > 0n ? wbtcSurplusE8 * wbtcPriceE18 / (10n ** 8n) : 0n;
      const navUsdRaw = gmValueE18 + surplusValueE18 > debtValueE18 ? gmValueE18 + surplusValueE18 - debtValueE18 : 0n;

      const navUsd = Number(navUsdRaw) / 1e18;
      const gmCollateral = Number(gmCollateralE18) / 1e18;
      const wbtcDebt = Number(wbtcDebtE8) / 1e8;

      // Live LTV = debtValue / collateralValue * 10000
      const ltvBps = gmValueE18 > 0n ? Number(debtValueE18 * 10000n / gmValueE18) : 0;

      // Single-owner vault: NFT holder owns 100% (represented as 1e18 internally)
      const OWNERSHIP_UNIT = 1000000000000000000n; // 1e18 = 100% ownership
      const hasDeposits = totalDepositedGmRaw > 0n;
      const ownershipRaw = hasDeposits ? OWNERSHIP_UNIT : 0n;

      setVaultData({
        navUsd,
        ltvPct: ltvBps / 100,
        gmCollateral,
        wbtcDebt,
        depositPending: depositStateVal === 1,
        withdrawPending: withdrawStateVal === 1,
        rebalancePending: rebalanceStateVal === 1,
        vaultStateAddr: stateAddr,
        totalDepositedGmE18: totalDepositedGmRaw,
        navUsdE18: navUsdRaw,
        managerFeeE18: managerFeeRaw,
        ownershipE18: ownershipRaw,
      });

      let ethBal = 0n;
      try { ethBal = await arbClient.getBalance({ address }); } catch { /* non-critical */ }
      setBalances({ usdcE6: sv(8), gmE18: sv(9), wbtcE8: sv(10), ownershipRaw, ethWei: ethBal });
    } catch (err) {
      import.meta.env.DEV && console.error('[Basalt] readVault error:', err);
      setVaultData(null);
      setBalances(null);
    }
    setLoading(false);
  }, [vaultAddr, address]);

  // ── Detect ALL vaults owned by user ──
  const detectVault = useCallback(async () => {
    if (!address) { setVaultDetected(true); return; }

    const timeout = setTimeout(() => { setVaultDetected(true); }, 15000);

    try {
      const [balRes, nextRes] = await arbClient.multicall({
        contracts: [
          { address: C.VAULT_CORE_NFT_FACTORY as Address, abi: FACTORY_ABI, functionName: 'balanceOf', args: [address] },
          { address: C.VAULT_CORE_NFT_FACTORY as Address, abi: FACTORY_ABI, functionName: 'nextTokenId' },
        ],
      });

      const bal = balRes.status === 'success' ? Number(balRes.result) : 0;
      const nextId = nextRes.status === 'success' ? Number(nextRes.result) : 0;

      if (bal === 0 || nextId === 0) {
        clearTimeout(timeout);
        setVaultDetected(true);
        return;
      }

      const calls = [];
      for (let i = 1; i <= nextId; i++) {
        calls.push({ address: C.VAULT_CORE_NFT_FACTORY as Address, abi: FACTORY_ABI, functionName: 'ownerOf' as const, args: [BigInt(i)] });
        calls.push({ address: C.VAULT_CORE_NFT_FACTORY as Address, abi: FACTORY_ABI, functionName: 'vaultByTokenId' as const, args: [BigInt(i)] });
      }

      const results = await arbClient.multicall({ contracts: calls });
      const found: string[] = [];

      for (let i = 0; i < results.length; i += 2) {
        const ownerRes = results[i];
        const vaultRes = results[i + 1];
        if (ownerRes.status === 'success' && (ownerRes.result as string).toLowerCase() === address.toLowerCase()) {
          const vault = vaultRes.status === 'success' ? (vaultRes.result as string) : '';
          if (vault) found.push(vault);
        }
      }

      clearTimeout(timeout);
      if (found.length > 0) {
        setAllVaults(found);
        const cached = localStorage.getItem('basalt_vault_' + address.toLowerCase());
        const active = cached && found.includes(cached) ? cached : found[0];
        localStorage.setItem('basalt_vault_' + address.toLowerCase(), active);
        setVaultAddr(active);
        setVaultDetected(true);
        return;
      }
    } catch (err) {
      clearTimeout(timeout);
      import.meta.env.DEV && console.error('[Basalt] detectVault error:', err);
    }
    setVaultDetected(true);
  }, [address]);

  // ── Auto-detect on connect ──
  useEffect(() => {
    if (!isConnected || !address) return;
    const cached = localStorage.getItem('basalt_vault_' + address.toLowerCase());
    if (cached) {
      setVaultAddr(cached);
    } else {
      setVaultAddr('');
      setVaultData(null);
      setBalances(null);
    }
    // Always detect all vaults so the switcher dropdown works
    setVaultDetected(false);
    detectVault();
  }, [isConnected, address]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => { if (isConnected && vaultAddr) readVault(); }, [isConnected, vaultAddr, readVault]);
  useEffect(() => {
    if (!isConnected || !vaultAddr) return;
    const t = setInterval(readVault, REFETCH_MS);
    return () => clearInterval(t);
  }, [isConnected, vaultAddr, readVault]);

  function selectVault(v: string) {
    if (!address) return;
    localStorage.setItem('basalt_vault_' + address.toLowerCase(), v);
    setVaultAddr(v);
    setVaultData(null);
    setBalances(null);
    setVaultDropdown(false);
  }

  function addVaultToList(v: string) {
    setAllVaults(prev => prev.includes(v) ? prev : [...prev, v]);
  }

  // ── Create vault ──
  async function createVault() {
    if (!address) return;
    setCreating(true);
    setError(null);
    try {
      const tx = await writeContractAsync({
        address: C.VAULT_CORE_NFT_FACTORY as Address,
        abi: FACTORY_ABI,
        functionName: 'createVaultCore',
        args: [address],
      });
      const receipt = await arbClient.waitForTransactionReceipt({ hash: tx, timeout: 120_000 });
      const factoryAddr = (C.VAULT_CORE_NFT_FACTORY as string).toLowerCase();
      const log = receipt.logs.find(l => l.address.toLowerCase() === factoryAddr && l.topics[0] === VAULT_ISSUED_TOPIC);
      if (log && log.topics[3]) {
        const vc = '0x' + log.topics[3].slice(26);
        localStorage.setItem('basalt_vault_' + address.toLowerCase(), vc);
        addVaultToList(vc);
        setVaultAddr(vc);
      } else {
        const nextId = await arbClient.readContract({
          address: C.VAULT_CORE_NFT_FACTORY as Address, abi: FACTORY_ABI, functionName: 'nextTokenId',
        }) as bigint;
        const vault = await arbClient.readContract({
          address: C.VAULT_CORE_NFT_FACTORY as Address, abi: FACTORY_ABI, functionName: 'vaultByTokenId', args: [nextId - 1n],
        });
        localStorage.setItem('basalt_vault_' + address.toLowerCase(), vault as string);
        addVaultToList(vault as string);
        setVaultAddr(vault as string);
      }
    } catch (err) {
      const msg = parseWalletError(err);
      if (/timed out|timeout/i.test(msg) && address) {
        try {
          await new Promise(r => setTimeout(r, 3000));
          const bal = await arbClient.readContract({
            address: C.VAULT_CORE_NFT_FACTORY as Address, abi: FACTORY_ABI, functionName: 'balanceOf', args: [address],
          });
          if (Number(bal) > 0) {
            const nextId = await arbClient.readContract({
              address: C.VAULT_CORE_NFT_FACTORY as Address, abi: FACTORY_ABI, functionName: 'nextTokenId',
            }) as bigint;
            const vault = await arbClient.readContract({
              address: C.VAULT_CORE_NFT_FACTORY as Address, abi: FACTORY_ABI, functionName: 'vaultByTokenId', args: [nextId - 1n],
            });
            localStorage.setItem('basalt_vault_' + address.toLowerCase(), vault as string);
            setVaultAddr(vault as string);
            setCreating(false);
            return;
          }
        } catch { /* ignore */ }
      }
      if (!/cancelled|rejected|denied/i.test(msg)) setError(msg);
    }
    setCreating(false);
  }

  // ── Finalize pending ──
  async function finalize(pendingType: 'deposit' | 'withdraw') {
    setBusy(true);
    setError(null);
    try {
      // Read fresh state from chain before sending finalize
      const stateAddr = await arbClient.readContract({
        address: vaultAddr as Address, abi: VAULT_CORE_ABI, functionName: 'basaltState',
      }) as Address;
      const stateKey = pendingType === 'deposit' ? 'depositState' : 'withdrawState';
      const freshState = await arbClient.readContract({
        address: stateAddr, abi: VAULT_STATE_ABI, functionName: stateKey,
      }) as number;
      if (freshState === 0) {
        setFlow({ type: 'idle' });
        readVault();
        setBusy(false);
        return;
      }

      const handler = pendingType === 'deposit' ? C.DEPOSIT_HANDLER : C.WITHDRAW_HANDLER;
      const abi = pendingType === 'deposit' ? DEPOSIT_HANDLER_ABI : WITHDRAW_HANDLER_ABI;
      const fn = pendingType === 'deposit' ? 'finalizeDeposit' : 'finalizeWithdraw';
      const tx = await writeContractAsync({
        address: handler as Address, abi, functionName: fn, args: [vaultAddr as Address],
      });
      await arbClient.waitForTransactionReceipt({ hash: tx });
      readVault();
    } catch (err) {
      setError(parseWalletError(err));
    }
    setBusy(false);
  }

  // ═══════════════════════════════════════════════════════════════════
  //  Swap: USDC -> GM (zapIn only, then poll for GM arrival)
  // ═══════════════════════════════════════════════════════════════════
  async function swapUsdcToGm() {
    if (!address) return;
    if (zapInFee === 0n) { setFlow({ type: 'error', message: 'Execution fee not loaded yet — wait a moment' }); return; }
    const usdcRaw = maxRaw ?? parseUnits(amount || '0', 6);
    if (usdcRaw === 0n) return;
    const slipBps = BigInt(slippage);

    setBusy(true); setFlow({ type: 'tx', label: 'Approving USDC...' }); setError(null);

    try {
      // 1. Approve USDC
      const currentAllowance = await arbClient.readContract({
        address: C.USDC as Address, abi: ERC20_ABI,
        functionName: 'allowance', args: [address, C.ZAP_IN as Address],
      });
      if (currentAllowance < usdcRaw) {
        const a1 = await writeContractAsync({
          address: C.USDC as Address, abi: ERC20_ABI,
          functionName: 'approve', args: [C.ZAP_IN as Address, MAX_UINT256],
        });
        await arbClient.waitForTransactionReceipt({ hash: a1, timeout: 120_000 });
      }

      // 2. ZapIn
      setFlow({ type: 'tx', label: 'Swapping USDC → GM...' });
      const z = await writeContractAsync({
        address: C.ZAP_IN as Address, abi: ZAP_IN_ABI,
        functionName: 'zapIn', args: [usdcRaw, slipBps], value: zapInFee,
      });
      await arbClient.waitForTransactionReceipt({ hash: z, timeout: 120_000 });

      // 3. Poll for GM arrival
      setFlow({ type: 'waiting-keeper' });
      setBusy(false);
      const gmBefore = await arbClient.readContract({
        address: C.GM_TOKEN as Address, abi: ERC20_ABI,
        functionName: 'balanceOf', args: [address],
      }) as bigint;
      for (let i = 0; i < 30; i++) {
        await new Promise(r => setTimeout(r, 2000));
        try {
          const gmNow = await arbClient.readContract({
            address: C.GM_TOKEN as Address, abi: ERC20_ABI,
            functionName: 'balanceOf', args: [address],
          });
          if (gmNow > gmBefore) {
            const received = formatUnits(gmNow - gmBefore, 18);
            const gmAmt = parseFloat(received).toFixed(2);
            // Auto-switch to Deposit GM tab with amount pre-filled
            setTab('deposit');
            setDepositMode('gm');
            // Delay to run after useEffect resets
            setTimeout(() => {
              setFlow({ type: 'gm-ready', amount: gmAmt });
              setAmount(gmAmt);
            }, 0);
            readVault();
            return;
          }
        } catch { /* retry */ }
      }
      setFlow({ type: 'error', message: 'GM did not arrive. Keeper may be delayed.' });
    } catch (err) {
      { const msg = parseWalletError(err); /cancelled|rejected|denied/i.test(msg) ? setFlow({ type: 'idle' }) : setFlow({ type: 'error', message: msg }); }
    }
    setBusy(false);
  }

  // ═══════════════════════════════════════════════════════════════════
  //  Deposit: direct GM deposit
  // ═══════════════════════════════════════════════════════════════════
  async function depositGm() {
    if (!address) return;
    if (depositValue === 0n) { setFlow({ type: 'error', message: 'Execution fee not loaded yet — wait a moment' }); return; }
    const gmRaw = maxRaw ?? parseUnits(amount || '0', 18);
    if (gmRaw === 0n) return;
    const MIN_DEPOSIT_GM = 1000000000000000000n; // 1e18 = 1 GM minimum (BasaltConstants.sol)
    if (gmRaw < MIN_DEPOSIT_GM) { setFlow({ type: 'error', message: 'Minimum deposit: 1 GM' }); return; }
    const slipBps = BigInt(slippage);

    setBusy(true); setFlow({ type: 'tx', label: 'Approving GM...' }); setError(null);

    try {
      const gmAllowance = await arbClient.readContract({
        address: C.GM_TOKEN as Address, abi: ERC20_ABI,
        functionName: 'allowance', args: [address, C.DEPOSIT_HANDLER as Address],
      });
      if (gmAllowance < gmRaw) {
        const a = await writeContractAsync({
          address: C.GM_TOKEN as Address, abi: ERC20_ABI,
          functionName: 'approve', args: [C.DEPOSIT_HANDLER as Address, MAX_UINT256],
        });
        await arbClient.waitForTransactionReceipt({ hash: a, timeout: 120_000 });
      }

      setFlow({ type: 'tx', label: 'Depositing GM...' });
      const d = await writeContractAsync({
        address: C.DEPOSIT_HANDLER as Address, abi: DEPOSIT_HANDLER_ABI,
        functionName: 'deposit', args: [vaultAddr as Address, gmRaw, slipBps], value: depositValue,
      });
      await arbClient.waitForTransactionReceipt({ hash: d, timeout: 120_000 });
      setFlow({ type: 'deposit-pending' });
      readVault();
    } catch (err) {
      { const msg = parseWalletError(err); /cancelled|rejected|denied/i.test(msg) ? setFlow({ type: 'idle' }) : setFlow({ type: 'error', message: msg }); }
    }
    setBusy(false);
  }

  // ═══════════════════════════════════════════════════════════════════
  //  Withdraw: vault position -> WBTC
  // ═══════════════════════════════════════════════════════════════════
  async function withdrawPosition() {
    if (!address) return;
    if (withdrawFee === 0n) { setFlow({ type: 'error', message: 'Execution fee not loaded yet — wait a moment' }); return; }
    const withdrawRaw = withdrawAmountRaw;
    if (withdrawRaw === 0n) return;
    if (withdrawOverLimit) { setFlow({ type: 'error', message: `Max withdraw: ${maxWithdrawPct}% (LTV limit)` }); return; }

    setBusy(true); setFlow({ type: 'tx', label: 'Withdrawing...' }); setError(null);

    try {
      // Scale minWbtcOut by withdraw percentage (partial withdraw = proportional debt)
      const withdrawFraction = parseFloat(withdrawPct) / 100;
      const proportionalDebtSats = Number(vaultData?.wbtcDebt ?? 0) * 1e8 * withdrawFraction;
      const minWbtcOutE8 = BigInt(Math.max(1, Math.floor(proportionalDebtSats * (10000 - Number(slippage)) / 10000)));

      // Sync branches (wbtcDebt == 0) call requireNoValue(), so only send fee when async
      const needsExecFee = (vaultData?.wbtcDebt ?? 0) > 0;

      const tx = await writeContractAsync({
        address: C.WITHDRAW_HANDLER as Address,
        abi: WITHDRAW_HANDLER_ABI,
        functionName: 'withdraw',
        args: [vaultAddr as Address, withdrawRaw, minWbtcOutE8],
        value: needsExecFee ? withdrawFee : 0n,
      });
      await arbClient.waitForTransactionReceipt({ hash: tx });
      setFlow({ type: 'withdraw-pending' });
      readVault();
    } catch (err) {
      { const msg = parseWalletError(err); /cancelled|rejected|denied/i.test(msg) ? setFlow({ type: 'idle' }) : setFlow({ type: 'error', message: msg }); }
    }
    setBusy(false);
  }

  // ═══════════════════════════════════════════════════════════════════
  //  ZapOut: WBTC -> USDC
  // ═══════════════════════════════════════════════════════════════════
  async function zapOutWbtc() {
    if (!address) return;
    const wbtcRaw = maxRaw ?? parseUnits(amount || '0', 8);
    if (wbtcRaw === 0n) return;
    const slipBps = BigInt(slippage);

    setBusy(true); setFlow({ type: 'tx', label: 'Swapping WBTC → USDC...' }); setError(null);

    try {
      const wbtcAllowance = await arbClient.readContract({
        address: C.WBTC as Address, abi: ERC20_ABI,
        functionName: 'allowance', args: [address, C.ZAP_OUT as Address],
      });
      if (wbtcAllowance < wbtcRaw) {
        setFlow({ type: 'tx', label: 'Approving WBTC...' });
        const approveTx = await writeContractAsync({
          address: C.WBTC as Address, abi: ERC20_ABI,
          functionName: 'approve', args: [C.ZAP_OUT as Address, MAX_UINT256],
        });
        await arbClient.waitForTransactionReceipt({ hash: approveTx });
        setFlow({ type: 'tx', label: 'Swapping WBTC → USDC...' });
      }

      const zapTx = await writeContractAsync({
        address: C.ZAP_OUT as Address, abi: ZAP_OUT_ABI,
        functionName: 'zapOut', args: [wbtcRaw, slipBps],
      });
      await arbClient.waitForTransactionReceipt({ hash: zapTx });
      setFlow({ type: 'idle' });
      readVault();
    } catch (err) {
      { const msg = parseWalletError(err); /cancelled|rejected|denied/i.test(msg) ? setFlow({ type: 'idle' }) : setFlow({ type: 'error', message: msg }); }
    }
    setBusy(false);
  }

  // ── Derived values ──
  const hasGm = (balances?.gmE18 ?? 0n) > 0n;
  const hasWbtc = (balances?.wbtcE8 ?? 0n) > 0n;
  const usdcBal = balances ? formatUnits(balances.usdcE6, 6) : '0';
  const gmBal = balances ? formatUnits(balances.gmE18, 18) : '0';
  const positionBal = balances ? formatUnits(balances.ownershipRaw, 18) : '0';
  const wbtcBal = balances ? formatUnits(balances.wbtcE8, 8) : '0';
  const wbtcSats = balances ? fmtSats(balances.wbtcE8) : '0';
  const ethBal = balances ? fmtEthShort(balances.ethWei) : '0';

  // Sync flow status from on-chain pending states
  useEffect(() => {
    if (vaultData?.depositPending && flow.type === 'idle') setFlow({ type: 'deposit-pending' });
    if (vaultData?.withdrawPending && flow.type === 'idle') setFlow({ type: 'withdraw-pending' });
    if (!vaultData?.depositPending && flow.type === 'deposit-pending') {
      setFlow({ type: 'deposit-done' });
      setTimeout(() => setFlow(f => f.type === 'deposit-done' ? { type: 'idle' } : f), 6000);
    }
    if (!vaultData?.withdrawPending && flow.type === 'withdraw-pending') {
      setFlow({ type: 'withdraw-done' });
      setTimeout(() => setFlow(f => f.type === 'withdraw-done' ? { type: 'idle' } : f), 8000);
    }
  }, [vaultData?.depositPending, vaultData?.withdrawPending]); // eslint-disable-line react-hooks/exhaustive-deps

  const currentBalance = useMemo(() => {
    if (tab === 'deposit') return depositMode === 'usdc' ? usdcBal : gmBal;
    return withdrawMode === 'withdraw' ? positionBal : wbtcBal;
  }, [tab, depositMode, withdrawMode, usdcBal, gmBal, positionBal, wbtcBal]);

  // Withdraw: max % of position that can be withdrawn (limited by accrued fees)
  // eligible = ownership * (NAV - managerFee) / NAV
  // Max % = min(eligible, ownership) / ownership * 100
  const maxWithdrawPct = useMemo(() => {
    if (!vaultData || !balances || balances.ownershipRaw === 0n) return 100;
    const { navUsdE18, managerFeeE18, ownershipE18 } = vaultData;
    if (navUsdE18 === 0n || ownershipE18 === 0n) return 100;
    if (managerFeeE18 === 0n) return 100; // no fee accrued = 100%
    if (managerFeeE18 >= navUsdE18) return 0;
    const eligibleE18 = ownershipE18 * (navUsdE18 - managerFeeE18) / navUsdE18;
    if (eligibleE18 >= balances.ownershipRaw) return 100;
    // eligible < ownership — cap at eligible/ownership %
    return Math.floor(Number(eligibleE18 * 10000n / balances.ownershipRaw)) / 100;
  }, [vaultData, balances]);

  const withdrawEstUsd = useMemo(() => {
    if (!vaultData || !withdrawPct) return null;
    const pct = parseFloat(withdrawPct);
    if (isNaN(pct) || pct <= 0) return null;
    return (vaultData.navUsd * pct / 100).toFixed(2);
  }, [vaultData, withdrawPct]);

  const withdrawAmountRaw = useMemo(() => {
    if (!balances || !withdrawPct) return 0n;
    const pct = parseFloat(withdrawPct);
    if (isNaN(pct) || pct <= 0) return 0n;
    return balances.ownershipRaw * BigInt(Math.round(pct * 100)) / 10000n;
  }, [balances, withdrawPct]);

  const withdrawOverLimit = !!withdrawPct && parseFloat(withdrawPct) > maxWithdrawPct;

  const currentToken = useMemo(() => {
    if (tab === 'deposit') return depositMode === 'usdc' ? 'USDC' : 'GM';
    return withdrawMode === 'withdraw' ? 'Position' : 'WBTC';
  }, [tab, depositMode, withdrawMode]);

  const currentDecimals = useMemo(() => {
    if (tab === 'deposit') return depositMode === 'usdc' ? 2 : 6;
    return withdrawMode === 'withdraw' ? 4 : 6;
  }, [tab, depositMode, withdrawMode]);

  const feeEthUsd = tab === 'deposit' ? depositEthUsd : withdrawEthUsd;

  // All 4 fee tiers for button labels — no useMemo, direct compute
  const feeQuote = tab === 'deposit' ? depositFeeQuote : withdrawFeeQuote;
  const feeTiers = (() => {
    if (!feeQuote) return null;
    const base = feeQuote.feeMinWei;
    const extra = isFirstDeposit && tab === 'deposit' && depositMode === 'gm' ? DOLOMITE_EXEC_FEE : 0n;
    const mult = 1n; // each sub-tab has its own fee tier
    return (['10', '20', '30', '50'] as const).map(pct => {
      const wei = (base * BigInt(100 + Number(pct)) / 100n) * mult + extra;
      const eth = Number(wei) / 1e18;
      const usd = feeEthUsd > 0 ? (eth * feeEthUsd).toFixed(2) : null;
      return { pct, wei, eth, usd };
    });
  })();

  // Reset on tab or mode change
  useEffect(() => { setAmount(''); setMaxRaw(null); setError(null); setFlow({ type: 'idle' }); }, [tab]);
  useEffect(() => { setAmount(''); setMaxRaw(null); setError(null); setFlow({ type: 'idle' }); }, [depositMode, withdrawMode]);

  // Action handler — changes based on flow status
  function handleAction() {
    // Finalize states
    if (flow.type === 'deposit-pending') { finalize('deposit'); return; }
    if (flow.type === 'withdraw-pending') { finalize('withdraw'); return; }
    // Navigate states
    if (flow.type === 'gm-ready') { setTab('deposit'); setDepositMode('gm'); return; }
    if (flow.type === 'wbtc-ready') { setTab('withdraw'); setWithdrawMode('zapout'); return; }
    // Normal actions
    if (tab === 'deposit') {
      depositMode === 'usdc' ? swapUsdcToGm() : depositGm();
    } else {
      withdrawMode === 'withdraw' ? withdrawPosition() : zapOutWbtc();
    }
  }

  function handleMax() {
    if (!balances) return;
    // Store raw bigint for the active token to avoid parseFloat precision loss
    if (tab === 'deposit') {
      if (depositMode === 'usdc') {
        setMaxRaw(balances.usdcE6);
        setAmount(balances.usdcE6 > 0n ? formatUnits(balances.usdcE6, 6) : '');
      } else {
        setMaxRaw(balances.gmE18);
        setAmount(balances.gmE18 > 0n ? formatUnits(balances.gmE18, 18) : '');
      }
    } else {
      if (withdrawMode === 'zapout') {
        setMaxRaw(balances.wbtcE8);
        setAmount(balances.wbtcE8 > 0n ? formatUnits(balances.wbtcE8, 8) : '');
      } else {
        setMaxRaw(balances.ownershipRaw);
        setAmount(balances.ownershipRaw > 0n ? formatUnits(balances.ownershipRaw, 18) : '');
      }
    }
  }

  const actionLabel = useMemo(() => {
    if (flow.type === 'deposit-pending') return 'Finalize Deposit';
    if (flow.type === 'withdraw-pending') return 'Finalize Withdraw';
    if (flow.type === 'gm-ready') return '→ Deposit GM';
    if (flow.type === 'wbtc-ready') return '→ WBTC → USDC';
    if (tab === 'deposit') return depositMode === 'usdc' ? 'Swap USDC to GM' : 'Deposit GM';
    return withdrawMode === 'withdraw' ? 'Withdraw WBTC' : 'Swap WBTC to USDC';
  }, [tab, depositMode, withdrawMode, flow.type]);

  const isWithdrawPctMode = tab === 'withdraw' && withdrawMode === 'withdraw';
  const feeReady = tab === 'deposit' ? zapInFee > 0n : withdrawFee > 0n;
  const canSubmit = flow.type === 'deposit-pending' || flow.type === 'withdraw-pending'
    || flow.type === 'gm-ready' || flow.type === 'wbtc-ready'
    || (isWithdrawPctMode ? (!busy && feeReady && !!withdrawPct && parseFloat(withdrawPct) > 0 && !withdrawOverLimit) : (!busy && feeReady && !!amount && parseFloat(amount) > 0));

  // ═══════════════════════════════════════════════════════════════════
  //  Render
  // ═══════════════════════════════════════════════════════════════════

  return (
    <div className={s.page}>
      <Header />

      {/* ── Not connected ── */}
      {!isConnected && (
        <motion.div className={s.onboarding}
          initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }}>
          <svg width="48" height="48" viewBox="0 0 64 64" fill="none">
            <g stroke="var(--fg-subtle)" strokeWidth="1.5" strokeLinejoin="miter" opacity="0.4">
              <path d="M32 4 L56 18 V46 L32 60 L8 46 V18 Z" fill="none" />
              <path d="M32 4 V32 L8 18" /><path d="M32 32 L56 18" /><path d="M32 32 V60" />
            </g>
            <circle cx="32" cy="32" r="4" fill="var(--ember-500)" />
          </svg>
          <h2 className={s.onboardTitle}>Basalt Vault</h2>
          <p className={s.onboardDesc}>
            Isolated vault strategy on Arbitrum. Deposit USDC, earn yield, withdraw anytime.
          </p>
          <button className={s.createBtn} disabled={isConnecting}
            onClick={() => connect({ connector: injected() })}>
            {isConnecting ? 'Connecting...' : 'Connect Wallet'}
          </button>
        </motion.div>
      )}

      {/* ── Wrong chain ── */}
      {isConnected && isWrongChain && (
        <motion.div className={s.onboarding}
          initial={{ opacity: 0 }} animate={{ opacity: 1 }}>
          <h2 className={s.onboardTitle}>Switch to Arbitrum</h2>
          <p className={s.onboardDesc}>Basalt Vault operates on Arbitrum One.</p>
          <button className={s.createBtn} onClick={() => switchChain({ chainId: ARBITRUM_CHAIN_ID })}>
            Switch Network
          </button>
        </motion.div>
      )}

      {/* ── Connected, scanning for vault ── */}
      {isConnected && !isWrongChain && !vaultAddr && !vaultDetected && (
        <div className={s.scanning}>
          <div className={s.scanSpin} />
          <span style={{ font: '400 13px/1 var(--font-sans)', color: 'var(--fg-muted)' }}>
            Scanning for your vault...
          </span>
          <input className={s.manualInput} placeholder="Or paste vault address 0x..."
            onKeyDown={e => {
              if (e.key === 'Enter' && (e.target as HTMLInputElement).value) {
                const v = (e.target as HTMLInputElement).value;
                localStorage.setItem('basalt_vault_' + address!.toLowerCase(), v);
                setVaultAddr(v);
              }
            }} />
        </div>
      )}

      {/* ── Connected, no vault found ── */}
      {isConnected && !isWrongChain && !vaultAddr && vaultDetected && (
        <motion.div className={s.onboarding}
          initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }}>
          <svg width="48" height="48" viewBox="0 0 64 64" fill="none">
            <g stroke="var(--fg-subtle)" strokeWidth="1.5" strokeLinejoin="miter" opacity="0.4">
              <path d="M32 4 L56 18 V46 L32 60 L8 46 V18 Z" fill="none" />
              <path d="M32 4 V32 L8 18" /><path d="M32 32 L56 18" /><path d="M32 32 V60" />
            </g>
            <circle cx="32" cy="32" r="4" fill="var(--ember-500)" />
          </svg>
          <h2 className={s.onboardTitle}>Create Your Vault</h2>
          <p className={s.onboardDesc}>
            Each vault is a unique NFT. Fully isolated position, only you control it.
          </p>
          <div className={s.onboardFeatures}>
            {[
              { icon: '\u2B21', title: '1 NFT = 1 Vault', desc: 'Your vault is a unique NFT you own' },
              { icon: '\u2726', title: 'Fully isolated', desc: 'No shared pools. Your funds, your position' },
              { icon: '\u26A1', title: 'Only you decide', desc: 'Deposit, withdraw, rebalance — your call' },
            ].map(f => (
              <div key={f.title} className={s.featureItem}>
                <span className={s.featureIcon}>{f.icon}</span>
                <div>
                  <div className={s.featureTitle}>{f.title}</div>
                  <div className={s.featureDesc}>{f.desc}</div>
                </div>
              </div>
            ))}
          </div>
          <button className={s.createBtn} onClick={createVault} disabled={creating}>
            {creating ? 'Creating...' : 'Create Vault'}
          </button>
          {error && <div className={s.errorMsg} style={{ marginTop: 8 }}>{error}</div>}
          <button className={s.manualLink} onClick={() => setShowManual(!showManual)}>
            I already have a vault address
          </button>
          {showManual && (
            <input className={s.manualInput} placeholder="0x..."
              onKeyDown={e => {
                if (e.key === 'Enter') {
                  const v = (e.target as HTMLInputElement).value;
                  localStorage.setItem('basalt_vault_' + address!.toLowerCase(), v);
                  setVaultAddr(v);
                }
              }}
              onBlur={e => {
                if (e.target.value) {
                  localStorage.setItem('basalt_vault_' + address!.toLowerCase(), e.target.value);
                  setVaultAddr(e.target.value);
                }
              }} />
          )}
        </motion.div>
      )}

      {/* ══════════════════════════════════════════════════════════════
       *  VAULT UI — stats + card
       * ══════════════════════════════════════════════════════════════ */}
      {isConnected && !isWrongChain && vaultAddr && (
        <motion.div style={{ width: '100%', display: 'flex', flexDirection: 'column', alignItems: 'center' }}
          initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }}>

          {/* Vault address — copy + dropdown + create */}
          <div className={s.vaultAddrRow}>
            <VaultGem addr={vaultAddr} size={22} />
            <button className={`${s.vaultAddrBtn} ${copied ? s.vaultAddrCopied : ''}`}
              onClick={() => {
                try { navigator.clipboard.writeText(vaultAddr); } catch {
                  const ta = document.createElement('textarea');
                  ta.value = vaultAddr; ta.style.position = 'fixed'; ta.style.opacity = '0';
                  document.body.appendChild(ta); ta.select(); document.execCommand('copy');
                  document.body.removeChild(ta);
                }
                setCopied(true);
                setTimeout(() => setCopied(false), 1500);
              }}
              title="Copy address">
              {copied ? '✓ Copied' : `${vaultAddr.slice(0, 6)}...${vaultAddr.slice(-4)}`}
              {!copied && <span className={s.copyIcon}>⎘</span>}
            </button>
            {allVaults.length > 1 && (
              <div style={{ position: 'relative' }}>
                <button className={s.vaultCreateBtn} onClick={() => setVaultDropdown(!vaultDropdown)}
                  title="Switch vault">▼</button>
                {vaultDropdown && (
                  <div className={s.vaultDropdown}>
                    {allVaults.map((v, i) => (
                      <button key={v} className={`${s.vaultDropItem} ${v === vaultAddr ? s.vaultDropActive : ''}`}
                        onClick={() => selectVault(v)}>
                        <VaultGem addr={v} size={16} />
                        #{i + 1} {v.slice(0, 6)}...{v.slice(-4)}
                      </button>
                    ))}
                  </div>
                )}
              </div>
            )}
            <button className={s.vaultCreateBtn} disabled={creating}
              title="Create new vault"
              onClick={() => setShowCreateModal(true)}>
              {creating ? '...' : '+'}
            </button>
          </div>

          {/* Stats bar — always rendered, placeholder when no data */}
          <div className={s.statsBar} style={!vaultData ? { opacity: 0.35 } : undefined}>
            <div className={s.statCell}>
              <div className={s.statLabel}>NAV</div>
              <div className={s.statValue}>{vaultData ? `$${fmtNum(vaultData.navUsd, 2)}` : '—'}</div>
            </div>
            <div className={s.statCell}>
              <div className={s.statLabel}>LTV</div>
              <div className={`${s.statValue} ${vaultData ? (vaultData.ltvPct < 70 ? s.ltvHealthy : vaultData.ltvPct < 83.8 ? s.ltvWarning : s.ltvDanger) : ''}`}>{vaultData ? `${vaultData.ltvPct.toFixed(1)}%` : '—'}</div>
            </div>
            <div className={s.statCell}>
              <div className={s.statLabel}>Collateral</div>
              <div className={s.statValue}>{vaultData ? `${fmtNum(vaultData.gmCollateral, 2)} GM` : '—'}</div>
            </div>
            <div className={s.statCell}>
              <div className={s.statLabel}>Debt</div>
              <div className={s.statValue}>{vaultData ? `${Math.round(vaultData.wbtcDebt * 1e8)} sats` : '—'}</div>
            </div>
          </div>

          {/* LTV bar — always rendered, hidden when no data */}
          <LtvBar ltvPct={vaultData?.ltvPct ?? 0} visible={!!vaultData} />

          {/* Rebalance pending banner */}
          {vaultData?.rebalancePending && (
            <div className={s.pendingBanner}>
              <span className={s.pendingLabel}>
                <span className={s.statusPulse} />
                Rebalance in progress
              </span>
            </div>
          )}

          {/* Main card */}
          <div className={s.card}>
            {/* Tab bar */}
            <div className={s.tabBar}>
              <button
                className={`${s.tabBtn} ${tab === 'deposit' ? s.tabActive : ''}`}
                onClick={() => setTab('deposit')}
              >
                Deposit
              </button>
              <button
                className={`${s.tabBtn} ${tab === 'withdraw' ? s.tabActive : ''}`}
                onClick={() => setTab('withdraw')}
              >
                Withdraw
              </button>
              <motion.div
                className={s.tabIndicator}
                animate={{ x: tab === 'deposit' ? 0 : '100%' }}
                transition={{ type: 'tween', duration: 0.2, ease: 'easeInOut' }}
              />
            </div>

            {/* Card body — wait for data before showing */}
              <div className={s.cardBody}>
                {!vaultData ? (
                  <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', minHeight: 200 }}>
                    <span className={s.stepSpin} />
                  </div>
                ) : (<>
                {/* Sub-action selector */}
                <div className={s.subActions}>
                  {tab === 'deposit' ? (
                    <>
                      <button className={s.subBtn} onClick={() => setDepositMode('usdc')}>
                        {depositMode === 'usdc' && <motion.div layoutId="subLine" className={s.subPill} transition={{ type: 'tween', duration: 0.2, ease: 'easeInOut' }} />}
                        <span className={s.subLabel} style={depositMode === 'usdc' ? { color: 'var(--fg-default)' } : undefined}>USDC → GM</span>
                      </button>
                      <button className={s.subBtn} onClick={() => setDepositMode('gm')}>
                        {depositMode === 'gm' && <motion.div layoutId="subLine" className={s.subPill} transition={{ type: 'tween', duration: 0.2, ease: 'easeInOut' }} />}
                        <span className={s.subLabel} style={depositMode === 'gm' ? { color: 'var(--fg-default)' } : undefined}>Deposit GM</span>
                      </button>
                      <div /><div />
                    </>
                  ) : (
                    <>
                      <div /><div />
                      <button className={s.subBtn} onClick={() => setWithdrawMode('withdraw')}>
                        {withdrawMode === 'withdraw' && <motion.div layoutId="subLine" className={s.subPill} transition={{ type: 'tween', duration: 0.2, ease: 'easeInOut' }} />}
                        <span className={s.subLabel} style={withdrawMode === 'withdraw' ? { color: 'var(--fg-default)' } : undefined}>Withdraw WBTC</span>
                      </button>
                      <button className={s.subBtn} onClick={() => setWithdrawMode('zapout')}>
                        {withdrawMode === 'zapout' && <motion.div layoutId="subLine" className={s.subPill} transition={{ type: 'tween', duration: 0.2, ease: 'easeInOut' }} />}
                        <span className={s.subLabel} style={withdrawMode === 'zapout' ? { color: 'var(--fg-default)' } : undefined}>WBTC → USDC</span>
                      </button>
                    </>
                  )}
                </div>

                {/* Wallet balances */}
                <div className={s.balancesRow}>
                  <span className={s.balancesLabel}>Wallet</span>
                  {tab === 'deposit' ? (
                    <>
                      <span>{parseFloat(usdcBal).toFixed(2)} <em>USDC</em></span>
                      <span>{parseFloat(gmBal).toFixed(2)} <em>GM</em></span>
                    </>
                  ) : (
                    <>
                      <span>{wbtcSats} <em>sats</em></span>
                      <span>{parseFloat(usdcBal).toFixed(2)} <em>USDC</em></span>
                    </>
                  )}
                  <span>{ethBal} <em>ETH</em></span>
                </div>

                {/* Amount input — or % input for withdraw */}
                {isWithdrawPctMode ? (
                  <div className={s.inputRow}>
                    <div className={s.inputWrap}>
                      <input
                        className={s.rangeSlider}
                        type="range"
                        min="0"
                        max={maxWithdrawPct}
                        step="1"
                        value={withdrawPct || '0'}
                        onChange={e => { setWithdrawPct(e.target.value); localStorage.setItem('basalt_withdraw_pct', e.target.value); }}
                        disabled={busy}
                      />
                      <span className={s.pctValue}>{withdrawPct || '0'}%</span>
                      <button className={s.maxBtn} onClick={() => { setWithdrawPct(String(maxWithdrawPct)); localStorage.setItem('basalt_withdraw_pct', String(maxWithdrawPct)); }}
                        disabled={busy}>MAX</button>
                    </div>
                    <div className={s.withdrawEst} style={{ visibility: withdrawEstUsd ? 'visible' : 'hidden' }}>
                      ≈ ${withdrawEstUsd || '0.00'}
                    </div>
                  </div>
                ) : (
                  <div className={s.inputRow}>
                    <div className={s.inputWrap}>
                      <input
                        className={s.amountInput}
                        inputMode="decimal"
                        pattern="[0-9]*\.?[0-9]*"
                        value={amount}
                        onChange={e => { setAmount(e.target.value.replace(/[^0-9.]/g, '')); setMaxRaw(null); }}
                        placeholder="0.00"
                        disabled={busy || flow.type === 'waiting-keeper'}
                      />
                      <button className={s.maxBtn} onClick={handleMax}
                        disabled={busy || flow.type === 'waiting-keeper'}>MAX</button>
                    </div>
                    <div className={s.withdrawEst} style={{ visibility: 'hidden' }}>&nbsp;</div>
                  </div>
                )}

                {/* Slippage */}
                <div className={s.slippageRow}>
                  <span className={s.slippageLabel}>Slippage</span>
                  <div className={s.slippageBtns}>
                    {[
                      { bps: '50',  label: '0.5%', sz: 32 },
                      { bps: '100', label: '1%',   sz: 38 },
                      { bps: '200', label: '2%',   sz: 44 },
                      { bps: '500', label: '5%',   sz: 48 },
                    ].map(({ bps, label, sz }) => (
                      <button key={bps}
                        className={`${s.slipBtn} ${slippage === bps ? s.slipActive : ''}`}
                        style={{ width: sz, height: sz, padding: 0 }}
                        onClick={() => setSlippage(bps)}>{label}</button>
                    ))}
                  </div>
                </div>

                {/* Execution fee */}
                <div className={s.slippageRow}>
                  <span className={s.slippageLabel}>Exec fee ETH</span>
                  <div className={s.slippageBtns}>
                    {feeTiers ? feeTiers.map(({ pct, usd }, i) => {
                      const sz = [32, 38, 44, 48][i];
                      return (
                        <button key={pct}
                          className={`${s.slipBtn} ${feeTier === pct ? s.slipActive : ''}`}
                          style={{ width: sz, height: sz, padding: 0 }}
                          onClick={() => setFeeTier(pct as FeeTier)}>
                          {usd ? `$${usd}` : `+${pct}%`}
                        </button>
                      );
                    }) : (
                      ['...', '...', '...', '...'].map((label, i) => {
                        const sz = [32, 38, 44, 48][i];
                        return <div key={i} className={s.slipBtn}
                          style={{ width: sz, height: sz, padding: 0, opacity: 0.3 }}>{label}</div>;
                      })
                    )}
                  </div>
                </div>

                {/* First deposit notice */}
                {isFirstDeposit && tab === 'deposit' && flow.type === 'idle' && (
                  <div className={s.statusZone}>
                    <div className={s.statusRow}>
                      <span className={s.statusTextPending}>First deposit — exec fee includes 0.001 ETH Dolomite</span>
                    </div>
                  </div>
                )}

                {/* ── Status zone ── */}
                <AnimatePresence mode="wait">
                  {flow.type !== 'idle' && (
                    <motion.div
                      key={flow.type}
                      className={s.statusZone}
                      initial={{ opacity: 0, height: 0 }}
                      animate={{ opacity: 1, height: 'auto' }}
                      exit={{ opacity: 0, height: 0 }}
                      transition={{ duration: 0.2 }}
                    >
                      {flow.type === 'tx' && (
                        <div className={s.statusRow}>
                          <span className={s.stepSpin} />
                          <span className={s.statusText}>{flow.label}</span>
                        </div>
                      )}
                      {flow.type === 'waiting-keeper' && (
                        <div className={s.statusRow}>
                          <span className={s.statusPulse} />
                          <span className={s.statusText}>Waiting for keeper...</span>
                        </div>
                      )}
                      {flow.type === 'gm-ready' && (
                        <div className={s.pendingBlock}>
                          <div className={s.pendingHeader}>
                            <span className={s.pendingStepDot} style={{ background: 'var(--state-success)', width: 8, height: 8 }} />
                            <span className={s.pendingTitle} style={{ color: 'var(--state-success)' }}>
                              {flow.amount} GM received — ready to deposit
                            </span>
                          </div>
                          <div className={s.pendingHint}>
                            Hit <strong>Deposit GM</strong> below to add it to your vault
                          </div>
                        </div>
                      )}
                      {flow.type === 'deposit-pending' && (
                        <div className={s.pendingBlock}>
                          <div className={s.pendingHeader}>
                            <span className={s.pendingOrb} />
                            <span className={s.pendingTitle}>Finalizing deposit</span>
                          </div>
                          <div className={s.pendingSteps}>
                            <div className={s.pendingStep}>
                              <span className={s.pendingStepDot} style={{ background: 'var(--state-success)' }} />
                              <span>Transaction confirmed</span>
                            </div>
                            <div className={`${s.pendingStep} ${s.pendingStepActive}`}>
                              <span className={s.pendingStepPulse} />
                              <span>Keeper finalizing — usually 2–4s</span>
                            </div>
                          </div>
                          <div className={s.pendingHint}>
                            You can also finalize manually below
                          </div>
                        </div>
                      )}
                      {flow.type === 'withdraw-pending' && (
                        <div className={s.pendingBlock}>
                          <div className={s.pendingHeader}>
                            <span className={s.pendingOrb} />
                            <span className={s.pendingTitle}>Finalizing withdrawal</span>
                          </div>
                          <div className={s.pendingSteps}>
                            <div className={s.pendingStep}>
                              <span className={s.pendingStepDot} style={{ background: 'var(--state-success)' }} />
                              <span>Withdrawal submitted</span>
                            </div>
                            <div className={`${s.pendingStep} ${s.pendingStepActive}`}>
                              <span className={s.pendingStepPulse} />
                              <span>Keeper finalizing — usually 2–4s</span>
                            </div>
                            <div className={s.pendingStep}>
                              <span className={s.pendingStepDot} />
                              <span>WBTC arrives in wallet</span>
                            </div>
                          </div>
                          <div className={s.pendingHint}>
                            You can also finalize manually below
                          </div>
                        </div>
                      )}
                      {flow.type === 'wbtc-ready' && (
                        <div className={s.pendingBlock}>
                          <div className={s.pendingHeader}>
                            <span className={s.pendingStepDot} style={{ background: 'var(--state-success)', width: 8, height: 8 }} />
                            <span className={s.pendingTitle} style={{ color: 'var(--state-success)' }}>
                              Withdrawal complete — {flow.sats} sats received
                            </span>
                          </div>
                          <div className={s.pendingHint}>
                            Swap WBTC → USDC using the <strong>WBTC → USDC</strong> tab below
                          </div>
                        </div>
                      )}
                      {flow.type === 'deposit-done' && (
                        <div className={s.pendingBlock} style={{ borderColor: 'rgba(34,197,94,0.2)', background: 'rgba(34,197,94,0.04)' }}>
                          <div className={s.pendingHeader}>
                            <motion.span
                              className={s.pendingStepDot}
                              style={{ background: '#22c55e', width: 10, height: 10, boxShadow: '0 0 8px #22c55e' }}
                              initial={{ scale: 0 }} animate={{ scale: 1 }}
                              transition={{ type: 'spring', stiffness: 400, damping: 12 }}
                            />
                            <span className={s.pendingTitle} style={{ color: '#22c55e' }}>
                              Deposit finalized by keeper
                            </span>
                          </div>
                          <div className={s.pendingSteps}>
                            <div className={s.pendingStep}>
                              <span className={s.pendingStepDot} style={{ background: '#22c55e' }} />
                              <span>GM deposited as collateral</span>
                            </div>
                            <div className={s.pendingStep}>
                              <span className={s.pendingStepDot} style={{ background: '#22c55e' }} />
                              <span>WBTC borrowed and looped</span>
                            </div>
                            <div className={s.pendingStep}>
                              <span className={s.pendingStepDot} style={{ background: '#22c55e' }} />
                              <span>Position active — earning yield</span>
                            </div>
                          </div>
                        </div>
                      )}
                      {flow.type === 'withdraw-done' && (
                        <div className={s.pendingBlock} style={{ borderColor: 'rgba(34,197,94,0.2)', background: 'rgba(34,197,94,0.04)' }}>
                          <div className={s.pendingHeader}>
                            <motion.span
                              className={s.pendingStepDot}
                              style={{ background: '#22c55e', width: 10, height: 10, boxShadow: '0 0 8px #22c55e' }}
                              initial={{ scale: 0 }} animate={{ scale: 1 }}
                              transition={{ type: 'spring', stiffness: 400, damping: 12 }}
                            />
                            <span className={s.pendingTitle} style={{ color: '#22c55e' }}>
                              Withdrawal finalized
                            </span>
                          </div>
                          <div className={s.pendingSteps}>
                            <div className={s.pendingStep}>
                              <span className={s.pendingStepDot} style={{ background: '#22c55e' }} />
                              <span>WBTC sent to your wallet</span>
                            </div>
                          </div>
                          <div className={s.pendingHint}>
                            Swap WBTC → USDC using the <strong>WBTC → USDC</strong> tab
                          </div>
                        </div>
                      )}
                      {flow.type === 'error' && (
                        <div className={s.statusRow}>
                          <span className={s.statusTextError}>{flow.message}</span>
                        </div>
                      )}
                    </motion.div>
                  )}
                </AnimatePresence>

                {/* Spacer pushes button to bottom */}
                <div className={s.cardSpacer} />

                {/* Action button */}
                <button className={s.actionBtn} disabled={!canSubmit} onClick={handleAction}>
                  {actionLabel}
                </button>

                {error && <div className={s.errorMsg}>{error}</div>}
                </>)}
              </div>
          </div>


          {/* Footer links */}
          <div className={s.vaultFooter}>
            <a href="https://btva.io/docs/user-guide" className={s.footerLink}>User Guide</a>
            <a href="https://btva.io/docs/architecture" className={s.footerLink}>Architecture</a>
          </div>

          {/* Create vault modal */}
          <AnimatePresence>
            {showCreateModal && (
              <motion.div className={s.modalOverlay}
                initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
                <motion.div className={s.modalCard}
                  initial={{ opacity: 0, y: 24, scale: 0.95 }} animate={{ opacity: 1, y: 0, scale: 1 }} exit={{ opacity: 0, y: 24, scale: 0.95 }}
                  transition={{ type: 'tween', duration: 0.25, ease: 'easeOut' }}>
                  <div style={{ display: 'flex', justifyContent: 'center', marginBottom: 16 }}>
                    <motion.div
                      animate={{ rotate: [0, 5, -5, 0], scale: [1, 1.05, 1] }}
                      transition={{ duration: 4, repeat: Infinity, ease: 'easeInOut' }}>
                      <VaultGem addr={`0x${Date.now().toString(16).padStart(40, 'a')}`} size={64} />
                    </motion.div>
                  </div>
                  <h2 className={s.onboardTitle}>Create New Vault</h2>
                  <p className={s.onboardDesc}>
                    Each vault is a unique NFT. Fully isolated position, only you control it.
                  </p>
                  <div className={s.onboardFeatures}>
                    {[
                      { icon: '\u2B21', title: '1 NFT = 1 Vault', desc: 'Your vault is a unique NFT you own' },
                      { icon: '\u2726', title: 'Fully isolated', desc: 'No shared pools. Your funds, your position' },
                      { icon: '\u26A1', title: 'Only you decide', desc: 'Deposit, withdraw, rebalance — your call' },
                    ].map(f => (
                      <div key={f.title} className={s.featureItem}>
                        <span className={s.featureIcon}>{f.icon}</span>
                        <div>
                          <div className={s.featureTitle}>{f.title}</div>
                          <div className={s.featureDesc}>{f.desc}</div>
                        </div>
                      </div>
                    ))}
                  </div>
                  <button className={s.createBtn}
                    onClick={() => { setShowCreateModal(false); createVault(); }}
                    disabled={creating}>
                    {creating ? 'Creating...' : 'Create Vault'}
                  </button>
                  <button className={s.manualLink} onClick={() => setShowCreateModal(false)}>
                    Cancel
                  </button>
                  {error && <div className={s.errorMsg} style={{ marginTop: 8 }}>{error}</div>}
                </motion.div>
              </motion.div>
            )}
          </AnimatePresence>
        </motion.div>
      )}

    </div>
  );
}
