import { motion } from 'motion/react';
import { useState, useEffect } from 'react';
import styles from './Overview.module.css';

/* ── Sequential flow: each node lights up in order ── */

function StrategyLoopDiagram() {
  const nodes = [
    { label: 'USDC', x: 70, y: 40, color: 'var(--mineral-500)' },
    { label: 'ZapIn', x: 200, y: 40, color: 'var(--ember-500)' },
    { label: 'GM Token', x: 340, y: 40, color: 'var(--fg-default)' },
    { label: 'Collateral', x: 480, y: 40, color: 'var(--fg-default)' },
    { label: 'Borrow WBTC', x: 480, y: 130, color: 'var(--sulfur-500)' },
    { label: 'Wrap \u2192 GM', x: 340, y: 130, color: 'var(--ember-500)' },
  ];

  const edges: { from: number; to: number; label?: string; loop?: boolean }[] = [
    { from: 0, to: 1 },
    { from: 1, to: 2, label: 'GMX v2' },
    { from: 2, to: 3, label: 'deposit' },
    { from: 3, to: 4, label: 'borrow' },
    { from: 4, to: 5, label: 'wrap' },
    { from: 5, to: 3, label: 'loop', loop: true },
  ];

  return (
    <svg viewBox="0 0 560 175" className={styles.svg}>
      <defs>
        <marker id="ov-arr" markerWidth="7" markerHeight="5" refX="6" refY="2.5" orient="auto">
          <path d="M0,0 L7,2.5 L0,5" fill="var(--ember-500)" />
        </marker>
      </defs>

      {/* Edges — sequential draw */}
      {edges.map((e, i) => {
        const a = nodes[e.from], b = nodes[e.to];
        const dx = b.x - a.x, dy = b.y - a.y;
        const x1 = a.x + Math.sign(dx) * 52;
        const y1 = a.y + (dy !== 0 ? Math.sign(dy) * 18 : 0);
        const x2 = b.x - Math.sign(dx) * 52;
        const y2 = b.y - (dy !== 0 ? Math.sign(dy) * 18 : 0);

        return (
          <g key={`e${i}`}>
            <motion.line
              x1={x1} y1={y1} x2={x2} y2={y2}
              stroke={e.loop ? 'var(--ember-500)' : 'var(--border-default)'}
              strokeWidth={e.loop ? 1.5 : 1}
              strokeDasharray={e.loop ? '5 4' : 'none'}
              markerEnd="url(#ov-arr)"
              initial={{ opacity: 0 }}
              whileInView={{ opacity: 1 }}
              viewport={{ once: true }}
              transition={{ delay: i * 0.03, duration: 0.2, ease: 'easeOut' }}
            />
            {e.label && (
              <motion.text
                x={(x1 + x2) / 2} y={Math.min(y1, y2) - 8}
                textAnchor="middle" fontSize={9} fontFamily="var(--font-mono)"
                fill={e.loop ? 'var(--ember-500)' : 'var(--fg-faint)'}
                fontWeight={e.loop ? 600 : 400}
                initial={{ opacity: 0 }}
                whileInView={{ opacity: 1 }}
                viewport={{ once: true }}
                transition={{ delay: i * 0.03, duration: 0.2, ease: 'easeOut' }}
              >{e.label}</motion.text>
            )}
          </g>
        );
      })}

      {/* Nodes — sequential appear */}
      {nodes.map((n, i) => (
        <motion.g key={n.label}
          initial={{ opacity: 0 }}
          whileInView={{ opacity: 1 }}
          viewport={{ once: true }}
          transition={{ delay: i * 0.03, duration: 0.2, ease: 'easeOut' }}>
          <rect x={n.x - 50} y={n.y - 16} width={100} height={32} rx={5}
            fill="var(--bg-raised)" stroke={n.color} strokeWidth={1.2} />
          <text x={n.x} y={n.y + 4} textAnchor="middle"
            fontSize={11} fontFamily="var(--font-mono)" fontWeight={600}
            fill={n.color}>{n.label}</text>
        </motion.g>
      ))}

      {/* "until target LTV" label */}
      <motion.text x={410} y={165} textAnchor="middle" fontSize={10}
        fontFamily="var(--font-mono)" fill="var(--ember-500)" fontWeight={600}
        initial={{ opacity: 0 }}
        whileInView={{ opacity: 1 }}
        viewport={{ once: true }}
        transition={{ delay: 0.1, duration: 0.2, ease: 'easeOut' }}>
        loops until 50% LTV
      </motion.text>
    </svg>
  );
}

/** Protocol stack — clean layered diagram */
function ProtocolStackDiagram() {
  const layers: { label: string; y: number; x: number; w: number; color: string; desc: string }[] = [
    { label: 'Basalt Vault', y: 15, x: 20, w: 440, color: 'var(--ember-500)', desc: 'Your isolated position' },
    { label: 'GMX v2', y: 70, x: 20, w: 210, color: 'var(--mineral-500)', desc: 'Yield source (GM fees)' },
    { label: 'Dolomite', y: 70, x: 250, w: 210, color: 'var(--sulfur-500)', desc: 'Leverage (borrow WBTC)' },
    { label: 'Uniswap V3', y: 125, x: 20, w: 135, color: 'var(--fg-muted)', desc: 'Exit swaps' },
    { label: 'Chainlink', y: 125, x: 170, w: 135, color: 'var(--fg-muted)', desc: 'Price oracles' },
    { label: 'Arbitrum One', y: 125, x: 325, w: 135, color: 'var(--fg-muted)', desc: 'L2 chain' },
  ];

  return (
    <svg viewBox="0 0 480 175" className={styles.svg}>
      {layers.map((l, i) => (
        <motion.g key={l.label}
          initial={{ opacity: 0 }}
          whileInView={{ opacity: 1 }}
          viewport={{ once: true }}
          transition={{ delay: i * 0.03, duration: 0.2, ease: 'easeOut' }}>
          <rect x={l.x} y={l.y} width={l.w} height={42} rx={5}
            fill="var(--bg-raised)" stroke={l.color} strokeWidth={1.2} />
          <text x={l.x + l.w / 2} y={l.y + 18} textAnchor="middle"
            fontSize={12} fontFamily="var(--font-mono)" fontWeight={700}
            fill={l.color}>{l.label}</text>
          <text x={l.x + l.w / 2} y={l.y + 33} textAnchor="middle"
            fontSize={9} fontFamily="var(--font-sans)"
            fill="var(--fg-faint)">{l.desc}</text>
        </motion.g>
      ))}
    </svg>
  );
}

/** NFT isolation — clean 3-column */
function IsolationDiagram() {
  const vaults = [
    { id: '#1', x: 80 },
    { id: '#2', x: 240 },
    { id: '#3', x: 400 },
  ];

  return (
    <svg viewBox="0 0 480 165" className={styles.svg}>
      <defs>
        <marker id="iso-arr" markerWidth="6" markerHeight="5" refX="5" refY="2.5" orient="auto">
          <path d="M0,0 L6,2.5 L0,5" fill="var(--ember-500)" />
        </marker>
      </defs>

      {/* Factory */}
      <motion.g
        initial={{ opacity: 0 }}
        whileInView={{ opacity: 1 }}
        viewport={{ once: true }}
        transition={{ duration: 0.2, ease: 'easeOut' }}>
        <rect x={190} y={8} width={100} height={28} rx={5}
          fill="rgba(255,106,61,0.08)" stroke="var(--ember-500)" strokeWidth={1.2} />
        <text x={240} y={26} textAnchor="middle" fontSize={11}
          fontFamily="var(--font-mono)" fontWeight={600} fill="var(--ember-500)">NFT Factory</text>
      </motion.g>

      {vaults.map((v, i) => (
        <motion.g key={v.id}
          initial={{ opacity: 0 }}
          whileInView={{ opacity: 1 }}
          viewport={{ once: true }}
          transition={{ delay: i * 0.03, duration: 0.2, ease: 'easeOut' }}>
          {/* Arrow from factory */}
          <motion.line x1={240} y1={36} x2={v.x} y2={65}
            stroke="var(--border-default)" strokeWidth={1} markerEnd="url(#iso-arr)"
            initial={{ opacity: 0 }}
            whileInView={{ opacity: 1 }}
            viewport={{ once: true }}
            transition={{ delay: i * 0.03, duration: 0.2, ease: 'easeOut' }} />

          {/* Vault box */}
          <rect x={v.x - 55} y={65} width={110} height={72} rx={6}
            fill="var(--bg-raised)" stroke="var(--border-default)" strokeWidth={1} />

          {/* NFT badge */}
          <rect x={v.x + 28} y={59} width={30} height={16} rx={8}
            fill="var(--ember-500)" />
          <text x={v.x + 43} y={70} textAnchor="middle" fontSize={8}
            fontFamily="var(--font-mono)" fontWeight={700} fill="white">NFT</text>

          <text x={v.x} y={83} textAnchor="middle" fontSize={11}
            fontFamily="var(--font-mono)" fontWeight={700} fill="var(--fg-default)">
            Vault {v.id}
          </text>
          <text x={v.x} y={98} textAnchor="middle" fontSize={9}
            fontFamily="var(--font-mono)" fill="var(--fg-faint)">VaultCore + State</text>
          <text x={v.x} y={112} textAnchor="middle" fontSize={9}
            fontFamily="var(--font-mono)" fill="var(--fg-faint)">Dolomite #100</text>
          <text x={v.x} y={126} textAnchor="middle" fontSize={8}
            fontFamily="var(--font-mono)" fill="var(--fg-faint)" opacity={0.6}>isolated</text>
        </motion.g>
      ))}

      <motion.text x={240} y={155} textAnchor="middle" fontSize={10}
        fontFamily="var(--font-mono)" fill="var(--fg-faint)"
        initial={{ opacity: 0 }}
        whileInView={{ opacity: 0.7 }}
        viewport={{ once: true }}
        transition={{ delay: 0.06, duration: 0.2, ease: 'easeOut' }}>
        no shared state between vaults
      </motion.text>
    </svg>
  );
}

const tocItems = [
  { id: 'strategy', label: 'Strategy' },
  { id: 'stack', label: 'Protocol stack' },
  { id: 'isolation', label: 'Isolation model' },
  { id: 'stats', label: 'Key numbers' },
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

export function Overview() {
  return (
    <article className={styles.page}>
      <h1 className={styles.pageTitle}>Protocol Overview</h1>

      <nav className={styles.toc} aria-label="Table of contents">
        {tocItems.map((item) => (
          <a key={item.id} href={`#${item.id}`} className={styles.tocLink}>{item.label}</a>
        ))}
      </nav>

      <p className={styles.subtitle}>
        Basalt Vault is a <span className={styles.highlight}>non-custodial</span> leveraged
        GM-BTC/USDC strategy on Arbitrum One. Each vault is an <span className={styles.highlight}>isolated
        ERC-721</span>. No shared pools. No admin keys over user funds.
      </p>

      <section className={styles.section} id="strategy">
        <h2 className={styles.sectionTitle}>How the strategy works</h2>
        <p className={styles.body}>
          Deposit USDC. It gets swapped to <span className={styles.highlight}>GM</span> (GMX v2
          BTC/USDC market token) via ZapIn. GM is deposited as collateral on Dolomite,
          <span className={styles.highlight}> WBTC is borrowed</span> against it, and wrapped
          back into more GM — looping until <span className={styles.highlight}>50% LTV</span>.
          The WBTC debt hedges the BTC component, creating a pseudo-delta-neutral position.
        </p>
        <div className={styles.diagramWrap}>
          <StrategyLoopDiagram />
        </div>
        <p className={styles.body}>
          Yield comes from <span className={styles.highlight}>GM market-making fees</span> —
          traders pay to open/close leveraged positions on GMX. The vault earns yield on the
          full collateral while debt cost is minimal.
        </p>
      </section>

      <hr className={styles.divider} />

      <section className={styles.section} id="stack">
        <h2 className={styles.sectionTitle}>Protocol stack</h2>
        <p className={styles.body}>
          Basalt composes <span className={styles.highlight}>three battle-tested DeFi protocols</span> on Arbitrum.
        </p>
        <div className={styles.diagramWrap}>
          <ProtocolStackDiagram />
        </div>
        <div className={styles.stackGrid}>
          {[
            { name: 'GMX v2', desc: 'Perpetual DEX — GM tokens earn trading fees', tag: 'Yield source' },
            { name: 'Dolomite', desc: 'Margin protocol — isolation mode lending', tag: 'Leverage' },
            { name: 'Uniswap V3', desc: 'DEX — WBTC/USDC ZapOut swaps', tag: 'Exit liquidity' },
            { name: 'Chainlink', desc: 'Price feeds — ETH/USD for fee estimation', tag: 'Oracle' },
          ].map((s, i) => (
            <motion.div key={s.name} className={styles.stackCard}
              initial={{ opacity: 0 }}
              whileInView={{ opacity: 1 }}
              viewport={{ once: true }}
              transition={{ delay: i * 0.03, duration: 0.2, ease: 'easeOut' }}>
              <div className={styles.stackLabel}>{s.name}</div>
              <div className={styles.stackDesc}>{s.desc}</div>
              <span className={styles.stackTag}>{s.tag}</span>
            </motion.div>
          ))}
        </div>
      </section>

      <hr className={styles.divider} />

      <section className={styles.section} id="isolation">
        <h2 className={styles.sectionTitle}>NFT isolation model</h2>
        <p className={styles.body}>
          Every vault is a <span className={styles.highlight}>separate clone</span> (VaultCore
          + VaultState), minted as an ERC-721 by the Factory. Each vault has its
          own <span className={styles.highlight}>Dolomite isolation account (#100)</span>.
          The NFT is the <span className={styles.highlight}>only key</span>.
        </p>
        <div className={styles.diagramWrap}>
          <IsolationDiagram />
        </div>
      </section>

      <hr className={styles.divider} />

      <section className={styles.section} id="stats">
        <h2 className={styles.sectionTitle}>Key numbers</h2>
        <div className={styles.statRow}>
          {[
            { value: '19.7%', label: 'Backtest APY' },
            { value: '-5.7%', label: 'Max drawdown' },
            { value: '~0', label: 'Delta' },
            { value: '83.8%', label: 'Liquidation LT' },
          ].map((s, i) => (
            <motion.div key={s.label} className={styles.statCell}
              initial={{ opacity: 0 }}
              whileInView={{ opacity: 1 }}
              viewport={{ once: true }}
              transition={{ delay: i * 0.03, duration: 0.2, ease: 'easeOut' }}>
              <div className={styles.statValue}>{s.value}</div>
              <div className={styles.statLabel}>{s.label}</div>
            </motion.div>
          ))}
        </div>
        <p className={styles.body}>
          Pseudo-delta-neutral. Residual BTC exposure exists. Backtest numbers are
          <span className={styles.highlight}> not guarantees</span> of future performance.
        </p>
      </section>

      <BackToTop />
    </article>
  );
}
