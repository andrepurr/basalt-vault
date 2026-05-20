import { motion } from 'motion/react';
import { useState, useEffect } from 'react';
import styles from './UserGuide.module.css';

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const draw: any = {
  hidden: { opacity: 0 },
  visible: (d: number) => ({
    opacity: 1,
    transition: { delay: d * 0.03, duration: 0.2, ease: 'easeOut' },
  }),
};

function DepositFlowDiagram() {
  const steps = ['USDC', 'Zap \u2192 GM', 'Deposit\nto Vault', 'Loop\nWBTC\u2192GM', 'Position\nOpen'];
  return (
    <svg viewBox="0 0 720 90" className={styles.svg}>
      <defs>
        <marker id="uga" markerWidth="6" markerHeight="5" refX="5" refY="2.5" orient="auto">
          <path d="M0,0 L6,2.5 L0,5" fill="var(--ember-500)" />
        </marker>
      </defs>
      {steps.map((label, i) => {
        const x = 60 + i * 150;
        return (
          <g key={label}>
            <motion.rect
              x={x - 48} y={25} width={96} height={40} rx={4}
              fill="var(--bg-raised)" stroke={i === steps.length - 1 ? 'var(--mineral-500)' : 'var(--border-default)'} strokeWidth={1}
              initial={{ opacity: 0 }}
              whileInView={{ opacity: 1 }}
              viewport={{ once: true }}
              transition={{ delay: i * 0.03, duration: 0.2, ease: 'easeOut' }}
            />
            {label.split('\n').map((l, li) => (
              <motion.text key={li}
                x={x} y={45 + li * 13 + (label.includes('\n') ? -3 : 3)}
                textAnchor="middle" fontSize={10} fontFamily="var(--font-mono)"
                fill={i === steps.length - 1 ? 'var(--mineral-500)' : 'var(--fg-muted)'}
                initial={{ opacity: 0 }} whileInView={{ opacity: 1 }} viewport={{ once: true }}
                transition={{ delay: i * 0.03, duration: 0.2, ease: 'easeOut' }}
              >{l}</motion.text>
            ))}
            {i < steps.length - 1 && (
              <motion.line
                x1={x + 48} y1={45} x2={x + 102} y2={45}
                stroke="var(--ember-500)" strokeWidth={1.5} markerEnd="url(#uga)"
                variants={draw} initial="hidden" whileInView="visible" custom={i}
                viewport={{ once: true }}
              />
            )}
          </g>
        );
      })}
    </svg>
  );
}

function WithdrawFlowDiagram() {
  const steps = ['Request\nWithdraw', 'Unwrap\nGM→WBTC', 'Swap\nWBTC→USDC', 'Receive\nStables'];
  return (
    <svg viewBox="0 0 560 90" className={styles.svg}>
      {steps.map((label, i) => {
        const x = 50 + i * 150;
        return (
          <g key={label}>
            <motion.rect
              x={x - 48} y={25} width={96} height={40} rx={4}
              fill="var(--bg-raised)" stroke={i === steps.length - 1 ? 'var(--mineral-500)' : 'var(--border-default)'} strokeWidth={1}
              initial={{ opacity: 0 }}
              whileInView={{ opacity: 1 }}
              viewport={{ once: true }}
              transition={{ delay: i * 0.03, duration: 0.2, ease: 'easeOut' }}
            />
            {label.split('\n').map((l, li) => (
              <motion.text key={li}
                x={x} y={42 + li * 13}
                textAnchor="middle" fontSize={10} fontFamily="var(--font-mono)"
                fill={i === steps.length - 1 ? 'var(--mineral-500)' : 'var(--fg-muted)'}
                initial={{ opacity: 0 }} whileInView={{ opacity: 1 }} viewport={{ once: true }}
                transition={{ delay: i * 0.03, duration: 0.2, ease: 'easeOut' }}
              >{l}</motion.text>
            ))}
            {i < steps.length - 1 && (
              <motion.line
                x1={x + 48} y1={45} x2={x + 102} y2={45}
                stroke="var(--ember-500)" strokeWidth={1.5} markerEnd="url(#uga)"
                variants={draw} initial="hidden" whileInView="visible" custom={i}
                viewport={{ once: true }}
              />
            )}
          </g>
        );
      })}
    </svg>
  );
}

function LtvZoneDiagram() {
  return (
    <svg viewBox="0 0 500 100" className={styles.svg}>
      {/* Zones */}
      <rect x={20} y={20} width={230} height={50} rx={3} fill="rgba(100,200,130,0.06)" stroke="var(--mineral-500)" strokeWidth={0.5} />
      <rect x={250} y={20} width={90} height={50} rx={3} fill="rgba(200,180,60,0.06)" stroke="var(--sulfur-500)" strokeWidth={0.5} />
      <rect x={340} y={20} width={140} height={50} rx={3} fill="rgba(200,60,60,0.06)" stroke="var(--magma-500, #e55)" strokeWidth={0.5} />

      <text x={135} y={50} textAnchor="middle" fontSize={11} fontFamily="var(--font-mono)" fill="var(--mineral-500)">SAFE 0–70%</text>
      <text x={295} y={50} textAnchor="middle" fontSize={10} fontFamily="var(--font-mono)" fill="var(--sulfur-500)">70–83.8%</text>
      <text x={410} y={50} textAnchor="middle" fontSize={10} fontFamily="var(--font-mono)" fill="var(--magma-500, #e55)">LIQUIDATION</text>

      {/* Current dot */}
      <motion.circle
        cx={155} cy={45} r={5} fill="var(--ember-500)"
        initial={{ opacity: 0 }} whileInView={{ opacity: 1 }} viewport={{ once: true }}
        transition={{ delay: 0.06, duration: 0.2, ease: 'easeOut' }}
      />
      <text x={155} y={84} textAnchor="middle" fontSize={9} fontFamily="var(--font-mono)" fill="var(--ember-500)">You: ~50%</text>
    </svg>
  );
}

const tocItems = [
  { id: 'deposit', label: 'Deposit' },
  { id: 'withdraw', label: 'Withdraw' },
  { id: 'safety', label: 'LTV safety' },
  { id: 'risks', label: 'Risks' },
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
    <button
      className={styles.backToTop}
      onClick={() => window.scrollTo({ top: 0, behavior: 'smooth' })}
      aria-label="Back to top"
    >
      <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
        <path d="M8 14V2M3 7l5-5 5 5" />
      </svg>
    </button>
  );
}

export function UserGuide() {
  return (
    <article className={styles.page}>
      <h1 className={styles.pageTitle}>User guide</h1>

      <nav className={styles.toc} aria-label="Table of contents">
        {tocItems.map((item) => (
          <a key={item.id} href={`#${item.id}`} className={styles.tocLink}>
            {item.label}
          </a>
        ))}
      </nav>
      <p className={styles.subtitle}>
        How to deposit, withdraw, and understand your position. This is a pseudo-delta
        neutral strategy — residual BTC exposure exists. Read the risks.
      </p>

      <section className={styles.section}>
        <h2 className={styles.sectionTitle}>What is Basalt Vault</h2>
        <p className={styles.body}>
          A <span className={styles.highlight}>non-custodial</span> Arbitrum protocol that creates a leveraged GM-BTC/USDC position
          with WBTC debt hedging most BTC exposure. <span className={styles.highlight}>One NFT = one vault</span>. The NFT is the
          only key. No shared pools. No admin keys.
        </p>
        <p className={styles.body}>
          Strategy: deposit GM as collateral on Dolomite, <span className={styles.highlight}>borrow WBTC</span> against it, wrap
          WBTC back into GM — loop to <span className={styles.highlight}>50% LTV</span>. Residual delta exists because GM contains
          both BTC and USDC, and WBTC debt offsets only the BTC component.
        </p>
      </section>

      <hr className={styles.divider} />

      <section className={styles.section} id="deposit">
        <h2 className={styles.sectionTitle}>Deposit flow</h2>
        <div className={styles.diagramWrap}>
          <DepositFlowDiagram />
        </div>
        <ol className={styles.steps}>
          <li>Approve USDC to ZapIn. Minimum 1 GM equivalent.</li>
          <li>ZapIn swaps stables to GM via GMX v2 market.</li>
          <li>GM deposited as collateral. Handler selects branch based on vault state.</li>
          <li>Vault borrows WBTC, wraps to more GM. Loops until target LTV (50%).</li>
          <li>Keeper finalizes async GMX settlement (~2s). Position open.</li>
        </ol>
      </section>

      <hr className={styles.divider} />

      <section className={styles.section} id="withdraw">
        <h2 className={styles.sectionTitle}>Withdraw flow</h2>
        <div className={styles.diagramWrap}>
          <WithdrawFlowDiagram />
        </div>
        <ol className={styles.steps}>
          <li>Withdraw from vault via WithdrawHandler (closes position, returns WBTC).</li>
          <li>Keeper finalizes the async unwrap.</li>
          <li>Approve WBTC to ZapOut. ZapOut swaps WBTC to USDC via Uniswap V3.</li>
          <li>USDC transferred to your wallet.</li>
        </ol>
      </section>

      <hr className={styles.divider} />

      <section className={styles.section} id="safety">
        <h2 className={styles.sectionTitle}>LTV safety zones</h2>
        <div className={styles.diagramWrap}>
          <LtvZoneDiagram />
        </div>
        <p className={styles.body}>
          Target LTV is <span className={styles.highlight}>50%</span>. Everything below 70% is safe — the vault <span className={styles.highlight}>auto-rebalances</span>
          back to target. Between 70% and 83.8% is the caution zone. Liquidation happens
          at Dolomite's LT (<span className={styles.highlight}>~83.8%</span>). The vault never operates above 70% by design.
        </p>
      </section>

      <hr className={styles.divider} />

      <section className={styles.section} id="risks">
        <h2 className={styles.sectionTitle}>Risks</h2>
        <ul className={styles.list}>
          <li>Residual BTC delta. This is NOT fully delta-neutral. Backtest max drawdown: -5.7%.</li>
          <li>Smart contract risk. Contracts are immutable — bugs cannot be patched.</li>
          <li>GMX/Dolomite dependency. Protocol relies on third-party solvency.</li>
          <li>Oracle risk. Chainlink staleness or manipulation could affect positions.</li>
          <li>Async settlement. GMX wrap/unwrap takes ~2s. Extreme volatility during settlement = risk.</li>
        </ul>
      </section>

      <BackToTop />
    </article>
  );
}
