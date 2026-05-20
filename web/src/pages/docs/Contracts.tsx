import { motion } from 'motion/react';
import { useState, useEffect } from 'react';
import styles from './Contracts.module.css';

const draw = {
  hidden: { opacity: 0 },
  visible: (d: number) => ({
    opacity: 1,
    transition: { delay: d * 0.03, duration: 0.2, ease: 'easeOut' },
  }),
};

const fadeIn = {
  hidden: { opacity: 0 },
  visible: (d: number) => ({
    opacity: 1,
    transition: { delay: d * 0.03, duration: 0.2, ease: 'easeOut' },
  }),
};

/** Enhanced data flow diagram — shows how contracts interact */
function DataFlowDiagram() {
  const boxes: { label: string; x: number; y: number; w: number; color: string; sub?: string }[] = [
    { label: 'User Wallet', x: 370, y: 24, w: 120, color: 'var(--mineral-500)', sub: 'EOA' },
    { label: 'ZapIn', x: 110, y: 115, w: 100, color: 'var(--ember-500)', sub: 'USDC\u2192GM' },
    { label: 'DepositHandler', x: 300, y: 115, w: 130, color: 'var(--ember-500)', sub: 'GM\u2192Vault' },
    { label: 'WithdrawHandler', x: 500, y: 115, w: 140, color: 'var(--ember-500)', sub: 'Vault\u2192WBTC' },
    { label: 'VaultCore', x: 300, y: 215, w: 130, color: 'var(--fg-default)', sub: 'universalCall' },
    { label: 'VaultState', x: 500, y: 215, w: 120, color: 'var(--fg-default)', sub: 'storage' },
    { label: 'ManagerContract', x: 110, y: 215, w: 140, color: 'var(--sulfur-500)', sub: 'governance' },
    { label: 'ManagerHandler', x: 110, y: 310, w: 140, color: 'var(--ember-500)', sub: 'rebalance' },
    { label: 'FeeSplitter', x: 500, y: 310, w: 120, color: 'var(--fg-muted)', sub: '20% HWM' },
    { label: 'ZapOut', x: 680, y: 115, w: 100, color: 'var(--ember-500)', sub: 'WBTC\u2192USDC' },
  ];

  const edges: [number, number][] = [
    [0, 1], [0, 2], [0, 3], [2, 4], [3, 4], [4, 5],
    [6, 7], [7, 4], [4, 8], [3, 9],
  ];

  return (
    <svg viewBox="0 0 780 360" className={styles.svg}>
      <defs>
        <marker id="ct-arr" markerWidth="6" markerHeight="5" refX="5" refY="2.5" orient="auto">
          <path d="M0,0 L6,2.5 L0,5" fill="var(--ember-500)" />
        </marker>
      </defs>
      {edges.map(([f, t], i) => {
        const a = boxes[f], b = boxes[t];
        return (
          <motion.line key={i}
            x1={a.x} y1={a.y + 22} x2={b.x} y2={b.y - 6}
            stroke="var(--border-default)" strokeWidth={1} markerEnd="url(#ct-arr)"
            variants={draw} initial="hidden" whileInView="visible" custom={i}
            viewport={{ once: true }} />
        );
      })}
      {boxes.map((b, i) => (
        <motion.g key={b.label}
          variants={fadeIn} initial="hidden" whileInView="visible" custom={i}
          viewport={{ once: true }}>
          <rect x={b.x - b.w / 2} y={b.y - 16} width={b.w} height={36} rx={4}
            fill="var(--bg-raised)" stroke={b.color} strokeWidth={1} />
          <text x={b.x} y={b.y + 1} textAnchor="middle" fontSize={11}
            fontFamily="var(--font-mono)" fontWeight={600} fill={b.color}>
            {b.label}
          </text>
          {b.sub && (
            <text x={b.x} y={b.y + 14} textAnchor="middle" fontSize={9}
              fontFamily="var(--font-mono)" fill="var(--fg-faint)">
              {b.sub}
            </text>
          )}
        </motion.g>
      ))}
    </svg>
  );
}

const ADDRESSES: {
  name: string; addr: string; role: string;
  tag: 'singleton' | 'per-vault' | 'external' | 'governance';
  functions?: { name: string; desc: string }[];
}[] = [
  {
    name: 'VaultCoreNftFactory', addr: '0xf8bd4b049b330B96B4e495245cd8babCF82FbFea',
    role: 'Mints ERC-721 vault NFTs. Creates VaultCore + VaultState clones.',
    tag: 'singleton',
    functions: [
      { name: 'createVaultCore(owner)', desc: 'Mint new vault NFT + deploy clone' },
      { name: 'vaultByTokenId(id)', desc: 'Look up vault address by token ID' },
      { name: 'ownerOf(id)', desc: 'ERC-721 owner query' },
    ],
  },
  {
    name: 'ManagerContract', addr: '0x19CD1BDec491d555145F6DDD3474C052b8d10E75',
    role: 'Protocol governance. Routes rebalance, LTV, and fee operations through handlers.',
    tag: 'governance',
    functions: [
      { name: 'rebalanceVault(handler, vault, slippage)', desc: 'Trigger position rebalance' },
      { name: 'finalizeRebalance(handler, vault)', desc: 'Finalize async rebalance' },
      { name: 'setVaultTargetLtv(handler, vault, bps)', desc: 'Update target LTV' },
    ],
  },
  {
    name: 'ZapIn', addr: '0x269eBA590C84B92F32213894d1399A22e258cD77',
    role: 'Converts USDC to GM token via GMX v2 market deposit. Async — GMX keeper settles.',
    tag: 'singleton',
    functions: [
      { name: 'zapIn(usdcE6, slippageBps)', desc: 'Swap USDC to GM (payable for exec fee)' },
    ],
  },
  {
    name: 'ZapOut', addr: '0x640599576EA91715950555E9Ff5e95Ee95a2272D',
    role: 'Converts WBTC to USDC via Uniswap V3 swap. Synchronous.',
    tag: 'singleton',
    functions: [
      { name: 'zapOut(wbtcE8, slippageBps)', desc: 'Swap WBTC to USDC via Uni V3' },
    ],
  },
  {
    name: 'DepositHandler', addr: '0xaf262a3098c29a478C0F78275D68CEaD87c7DD63',
    role: 'Handles GM deposit into vault. Manages Dolomite collateral + borrow loop.',
    tag: 'singleton',
    functions: [
      { name: 'deposit(vault, gmE18, slippageBps)', desc: 'Deposit GM into vault (payable)' },
      { name: 'finalizeDeposit(vault)', desc: 'Finalize pending deposit after GMX settles' },
    ],
  },
  {
    name: 'WithdrawHandler', addr: '0xCC48c39Ec0e46eC147Fb6dfE3f26af471088Bd84',
    role: 'Handles vault withdrawal. Repays debt, unwraps GM, returns WBTC.',
    tag: 'singleton',
    functions: [
      { name: 'withdraw(vault, amount, minWbtcE8)', desc: 'Withdraw from vault position (payable for async)' },
      { name: 'finalizeWithdraw(vault)', desc: 'Finalize pending withdrawal' },
    ],
  },
  {
    name: 'ManagerHandler', addr: '0x7FCD2e53a95814cD1DBa09594b849a5159f04768',
    role: 'Reads and manages vault position parameters. LTV queries.',
    tag: 'singleton',
    functions: [
      { name: 'currentLtvBps(vault)', desc: 'Read current LTV in basis points' },
    ],
  },
  {
    name: 'FeeAccountingHandler', addr: '0x4EC35d4dE14f2621bDd27aAb9d8A5B706A8088CC',
    role: 'Accrues and distributes performance fees based on high-water mark.',
    tag: 'singleton',
  },
  {
    name: 'AsyncRecoveryHandler', addr: '0x4439036e883F4bd42d923AFA57C7c070beA99544',
    role: 'Handles stuck async operations. Vault NFT owner or protocol manager can cancel and recover after deadline + grace period.',
    tag: 'singleton',
  },
  {
    name: 'FeeSplitter', addr: '0xB441Ac82263C85bD00e881023E957F512308B016',
    role: 'Splits accrued performance fees to fee-share holders.',
    tag: 'singleton',
  },
  {
    name: 'GmUnwrapper', addr: '0xD3D4D1d7A73Ba4D5CEb50426a835351C2A2BA99E',
    role: 'Unwraps GM tokens during async withdrawal settlement.',
    tag: 'singleton',
  },
  {
    name: 'VaultCore + VaultState', addr: 'Deployed per-user via Factory',
    role: 'Per-vault clone pair. VaultCore routes calls, VaultState holds position and accounting data.',
    tag: 'per-vault',
  },
  {
    name: 'GM Token (BTC/USDC)', addr: '0x47c031236e19d024b42f8AE6780E44A573170703',
    role: 'GMX v2 market token. Earns trading fees from perpetual traders.',
    tag: 'external',
  },
  {
    name: 'WBTC', addr: '0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f',
    role: 'Wrapped BTC on Arbitrum. Borrowed against GM collateral.',
    tag: 'external',
  },
  {
    name: 'USDC', addr: '0xaf88d065e77c8cC2239327C5EDb3A432268e5831',
    role: 'Native USDC on Arbitrum. Primary deposit/withdraw token.',
    tag: 'external',
  },
];

const tagClass: Record<string, string> = {
  singleton: styles.roleSingleton,
  'per-vault': styles.rolePerVault,
  external: styles.roleExternal,
  governance: styles.roleGovernance,
};

const tocItems = [
  { id: 'data-flow', label: 'Data flow' },
  { id: 'addresses', label: 'Addresses' },
  { id: 'functions', label: 'Key functions' },
];

function BackToTop() {
  const [visible, setVisible] = useState(false);
  useEffect(() => {
    const onScroll = () => setVisible(window.scrollY > 400);
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);
  if (!visible) return null;
  return (
    <button className={styles.backToTop}
      onClick={() => window.scrollTo({ top: 0, behavior: 'smooth' })}
      aria-label="Back to top">
      <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="2">
        <path d="M8 14V2M3 7l5-5 5 5" />
      </svg>
    </button>
  );
}

export function Contracts() {
  return (
    <article className={styles.page}>
      <h1 className={styles.pageTitle}>Contracts</h1>

      <nav className={styles.toc} aria-label="Table of contents">
        {tocItems.map((item) => (
          <a key={item.id} href={`#${item.id}`} className={styles.tocLink}>{item.label}</a>
        ))}
      </nav>

      <p className={styles.subtitle}>
        Deployment 4 — <span className={styles.highlight}>Arbitrum One</span> (chain 42161). All handler contracts are <span className={styles.highlight}>immutable singletons</span>.
        Per-vault contracts (VaultCore, VaultState) are created by the <span className={styles.highlight}>factory</span>.
      </p>

      <section className={styles.section} id="data-flow">
        <h2 className={styles.sectionTitle}>Data flow</h2>
        <p className={styles.body}>
          Users interact with <span className={styles.highlight}>handlers</span> directly. Handlers call <span className={styles.highlight}>VaultCore</span> via <span className={styles.highlight}>universalCall</span>.
          The <span className={styles.highlight}>ManagerContract</span> routes governance operations (rebalance, fee, LTV) through
          the same handlers.
        </p>
        <div className={styles.diagramWrap}>
          <DataFlowDiagram />
        </div>
      </section>

      <hr className={styles.divider} />

      <section className={styles.section} id="addresses">
        <h2 className={styles.sectionTitle}>Contract addresses</h2>
        <table className={styles.addrTable}>
          <thead>
            <tr><th>Contract</th><th>Address</th><th>Type</th></tr>
          </thead>
          <tbody>
            {ADDRESSES.map((a, i) => (
              <motion.tr key={a.name}
                initial={{ opacity: 0 }}
                whileInView={{ opacity: 1 }}
                viewport={{ once: true }}
                transition={{ delay: i * 0.03, duration: 0.2, ease: 'easeOut' }}>
                <td>{a.name}</td>
                <td>
                  <a href={`https://arbiscan.io/address/${a.addr}`}
                    target="_blank" rel="noopener noreferrer" className={styles.addrLink}>
                    {a.addr.slice(0, 6)}...{a.addr.slice(-4)}
                  </a>
                </td>
                <td><span className={`${styles.roleTag} ${tagClass[a.tag]}`}>{a.tag}</span></td>
              </motion.tr>
            ))}
          </tbody>
        </table>
      </section>

      <hr className={styles.divider} />

      <section className={styles.section} id="functions">
        <h2 className={styles.sectionTitle}>Key functions</h2>
        {ADDRESSES.filter(a => a.functions).map(a => (
          <div key={a.name} style={{ marginBottom: 20 }}>
            <h3 style={{
              font: '600 14px/1.3 var(--font-mono)', color: 'var(--fg-default)',
              margin: '0 0 8px',
            }}>{a.name}</h3>
            <p style={{ font: '400 12px/1.5 var(--font-sans)', color: 'var(--fg-faint)', margin: '0 0 8px' }}>
              {a.role}
            </p>
            <div className={styles.fnGrid}>
              {a.functions!.map(fn => (
                <div key={fn.name} className={styles.fnItem}>
                  <div className={styles.fnName}>{fn.name}</div>
                  <div className={styles.fnDesc}>{fn.desc}</div>
                </div>
              ))}
            </div>
          </div>
        ))}
      </section>

      <BackToTop />
    </article>
  );
}
