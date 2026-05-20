import { motion } from 'motion/react';
import { useState, useEffect } from 'react';
import styles from './Fees.module.css';

const fadeIn = {
  hidden: { opacity: 0 },
  visible: (d: number) => ({
    opacity: 1,
    transition: { delay: d * 0.03, duration: 0.2, ease: 'easeOut' },
  }),
};

const draw = {
  hidden: { opacity: 0 },
  visible: (d: number) => ({
    opacity: 1,
    transition: { delay: d * 0.03, duration: 0.2, ease: 'easeOut' },
  }),
};

/** Visual formula breakdown diagram */
function FormulaFlowDiagram() {
  const steps = [
    { label: 'gasLimit(op)', x: 80, y: 38, w: 120 },
    { label: '+ callbackGas', x: 240, y: 38, w: 130 },
    { label: '= estimatedGas', x: 420, y: 38, w: 140, highlight: true },
    { label: 'baseAmount', x: 80, y: 105, w: 120 },
    { label: '+ perOracle \u00D7 3', x: 240, y: 105, w: 140 },
    { label: '+ (est \u00D7 mult)\n/ 10\u00B3\u2070', x: 420, y: 105, w: 140 },
    { label: '= adjustedGas', x: 620, y: 72, w: 130, highlight: true },
    { label: '\u00D7 gasPrice', x: 620, y: 145, w: 120 },
    { label: '= feeMin', x: 420, y: 145, w: 120, highlight: true },
  ];

  return (
    <svg viewBox="0 0 760 185" className={styles.svg}>
      <defs>
        <marker id="fee-arr" markerWidth="6" markerHeight="5" refX="5" refY="2.5" orient="auto">
          <path d="M0,0 L6,2.5 L0,5" fill="var(--ember-500)" />
        </marker>
      </defs>
      {/* Connection lines */}
      {[
        [0, 1], [1, 2], [3, 4], [4, 5], [2, 6], [5, 6], [6, 7], [7, 8],
      ].map(([f, t], i) => {
        const a = steps[f], b = steps[t];
        return (
          <motion.line key={i}
            x1={a.x + a.w / 2 + 10} y1={a.y} x2={b.x - b.w / 2 + 10} y2={b.y}
            stroke="var(--border-default)" strokeWidth={1} markerEnd="url(#fee-arr)"
            variants={draw} initial="hidden" whileInView="visible" custom={i}
            viewport={{ once: true }} />
        );
      })}
      {steps.map((s, i) => (
        <motion.g key={s.label}
          variants={fadeIn} initial="hidden" whileInView="visible" custom={i}
          viewport={{ once: true }}>
          <rect x={s.x - s.w / 2 + 10} y={s.y - 16} width={s.w} height={s.label.includes('\n') ? 40 : 32} rx={4}
            fill={s.highlight ? 'rgba(255,106,61,0.06)' : 'var(--bg-raised)'}
            stroke={s.highlight ? 'var(--ember-500)' : 'var(--border-default)'} strokeWidth={1} />
          {s.label.split('\n').map((line, li) => (
            <text key={li}
              x={s.x + 10} y={s.y + li * 14 + (s.label.includes('\n') ? -1 : 3)}
              textAnchor="middle" fontSize={11} fontFamily="var(--font-mono)"
              fill={s.highlight ? 'var(--ember-500)' : 'var(--fg-muted)'}>{line}</text>
          ))}
        </motion.g>
      ))}
    </svg>
  );
}

/** Fee buffer tiers bar chart */
function TierBarDiagram() {
  const tiers = [
    { name: 'Low', pct: 110, color: 'var(--fg-faint)', w: 50 },
    { name: 'Med', pct: 120, color: 'var(--sulfur-500)', w: 55 },
    { name: 'Safe', pct: 130, color: 'var(--mineral-500)', w: 65 },
    { name: 'Max', pct: 150, color: 'var(--ember-500)', w: 75 },
  ];

  return (
    <svg viewBox="0 0 540 130" className={styles.svg}>
      {tiers.map((t, i) => {
        const barW = t.w * 4;
        const y = 15 + i * 28;
        return (
          <motion.g key={t.name}
            initial={{ opacity: 0 }}
            whileInView={{ opacity: 1 }}
            viewport={{ once: true }}
            transition={{ delay: i * 0.03, duration: 0.2, ease: 'easeOut' }}>
            <text x={38} y={y + 13} textAnchor="end" fontSize={11}
              fontFamily="var(--font-mono)" fontWeight={600} fill={t.color}>
              {t.name}
            </text>
            <rect x={48} y={y} width={barW} height={20} rx={3}
              fill={t.color} opacity={0.15} />
            <rect x={48} y={y} width={barW} height={20} rx={3}
              fill={t.color} opacity={0.6} />
            <text x={barW + 58} y={y + 14} fontSize={11}
              fontFamily="var(--font-mono)" fill={t.color} fontWeight={500}>
              {t.pct}%
            </text>
            <text x={barW + 100} y={y + 14} fontSize={9}
              fontFamily="var(--font-sans)" fill="var(--fg-faint)">
              {t.name === 'Low' ? '+10% buffer — risk of skip' :
               t.name === 'Med' ? '+20% — moderate buffer' :
               t.name === 'Safe' ? '+30% — recommended default' :
               '+50% — volatile gas'}
            </text>
          </motion.g>
        );
      })}
    </svg>
  );
}

const tocItems = [
  { id: 'exec-fee', label: 'Execution fee' },
  { id: 'formula', label: 'Formula' },
  { id: 'tiers', label: 'Buffer tiers' },
  { id: 'cost', label: 'Cost breakdown' },
  { id: 'performance', label: 'Performance fee' },
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

export function Fees() {
  return (
    <article className={styles.page}>
      <h1 className={styles.pageTitle}>Fee Structure</h1>

      <nav className={styles.toc} aria-label="Table of contents">
        {tocItems.map((item) => (
          <a key={item.id} href={`#${item.id}`} className={styles.tocLink}>{item.label}</a>
        ))}
      </nav>

      <p className={styles.subtitle}>
        Two types of fees: <span className={styles.highlight}>GMX execution fees</span> (gas for async operations) and protocol
        <span className={styles.highlight}>performance fees</span> (20% above high-water mark). No deposit or withdrawal fees.
      </p>

      <section className={styles.section} id="exec-fee">
        <h2 className={styles.sectionTitle}>GMX execution fee</h2>
        <p className={styles.body}>
          GMX v2 operations (deposit/withdraw GM tokens) are <span className={styles.highlight}>asynchronous</span>. A keeper finalizes
          them on-chain. The execution fee covers gas for the <span className={styles.highlight}>keeper transaction</span>. It is paid
          in ETH as <code>msg.value</code> when calling deposit or withdraw.
        </p>
        <p className={styles.body}>
          The fee is computed from on-chain constants fetched via multicall from the GMX
          DataStore, Chainlink ETH/USD oracle, and current gas price. It auto-refreshes
          every 10 minutes in the UI.
        </p>
      </section>

      <hr className={styles.divider} />

      <section className={styles.section} id="formula">
        <h2 className={styles.sectionTitle}>Formula</h2>
        <div className={styles.diagramWrap}>
          <FormulaFlowDiagram />
        </div>
        <div className={styles.formulaBox}>
          <span className={styles.formulaVar}>estimatedGas</span> = gasLimit(op) + callbackGas{'\n'}
          <span className={styles.formulaVar}>adjustedGas</span>  = baseAmount + perOracle × oracleCount{'\n'}
          {'                '}+ (estimatedGas × multiplier) / 10<sup>30</sup>{'\n'}
          <span className={styles.formulaVar}>feeMin</span>       = adjustedGas × gasPrice{'\n'}
          {'\n'}
          <span className={styles.formulaComment}>// Buffer tiers applied to feeMin:</span>{'\n'}
          <span className={styles.formulaVar}>feeLow</span>       = feeMin × 110 / 100  <span className={styles.formulaComment}>// +10%</span>{'\n'}
          <span className={styles.formulaVar}>feeMed</span>       = feeMin × 120 / 100  <span className={styles.formulaComment}>// +20%</span>{'\n'}
          <span className={styles.formulaVar}>feeSafe</span>      = feeMin × 130 / 100  <span className={styles.formulaComment}>// +30% ← default</span>{'\n'}
          <span className={styles.formulaVar}>feeMax</span>       = feeMin × 150 / 100  <span className={styles.formulaComment}>// +50%</span>
        </div>
        <p className={styles.body}>
          Constants: <code>oracleCount = 3</code> (BTC long + USDC short + index).
          <code> callbackGas = 0</code> for ZapIn path (BasaltZapIn creates GMX deposit with
          callbackGasLimit: 0). <code>FLOAT_PRECISION = 10<sup>30</sup></code> — GMX's
          internal precision constant.
        </p>
      </section>

      <hr className={styles.divider} />

      <section className={styles.section} id="tiers">
        <h2 className={styles.sectionTitle}>Buffer tiers</h2>
        <p className={styles.body}>
          The UI defaults to <strong>Safe (+30%)</strong>. Lower buffers risk the <span className={styles.highlight}>keeper
          skipping</span> your transaction if gas spikes between submission and execution.
        </p>
        <div className={styles.diagramWrap}>
          <TierBarDiagram />
        </div>
        <div className={styles.tierGrid}>
          {[
            { name: 'Low', value: '+10%', desc: 'Minimum buffer. Risk of keeper skip.', cls: styles.tierLow },
            { name: 'Med', value: '+20%', desc: 'Moderate buffer. Usually sufficient.', cls: styles.tierMin },
            { name: 'Safe', value: '+30%', desc: 'Recommended default. Reliable execution.', cls: styles.tierSafe },
            { name: 'Max', value: '+50%', desc: 'For volatile gas conditions.', cls: styles.tierMax },
          ].map((t, i) => (
            <motion.div key={t.name} className={`${styles.tierCell} ${t.cls}`}
              initial={{ opacity: 0 }}
              whileInView={{ opacity: 1 }}
              viewport={{ once: true }}
              transition={{ delay: i * 0.03, duration: 0.2, ease: 'easeOut' }}>
              <div className={styles.tierName}>{t.name}</div>
              <div className={styles.tierValue}>{t.value}</div>
              <div className={styles.tierDesc}>{t.desc}</div>
            </motion.div>
          ))}
        </div>
      </section>

      <hr className={styles.divider} />

      <section className={styles.section} id="cost">
        <h2 className={styles.sectionTitle}>Cost breakdown</h2>
        <p className={styles.body}>
          A USDC deposit involves <span className={styles.highlight}>two async hops</span>, each requiring an execution fee.
          Direct GM deposit requires only one hop. First deposit adds <span className={styles.highlight}>0.001 ETH</span> for
          Dolomite isolation vault creation.
        </p>
        <div className={styles.costBreakdown}>
          <div className={styles.costBox}>
            <div className={styles.costLabel}>ZapIn fee</div>
            <div className={styles.costValue}>GMX exec</div>
          </div>
          <div className={styles.costOp}>+</div>
          <div className={styles.costBox}>
            <div className={styles.costLabel}>Deposit fee</div>
            <div className={styles.costValue}>GMX exec</div>
          </div>
          <div className={styles.costOp}>=</div>
          <div className={styles.costBox}>
            <div className={styles.costLabel}>Total</div>
            <div className={styles.costValue}>2× exec fee</div>
          </div>
        </div>
        <p className={styles.body}>
          Withdraw execution fee is a single hop. ZapOut (WBTC → USDC via Uniswap V3)
          is synchronous — no execution fee, only normal gas.
        </p>
      </section>

      <hr className={styles.divider} />

      <section className={styles.section} id="performance">
        <h2 className={styles.sectionTitle}>Performance fee</h2>
        <p className={styles.body}>
          <span className={styles.highlight}>20% of profit</span> above the <span className={styles.highlight}>high-water mark</span> (HWM). Accrued by FeeAccountingHandler,
          distributed through FeeSplitter. No fee is charged on the principal or if the
          vault is underwater. The HWM only moves up — never resets.
        </p>
        <div style={{
          background: 'var(--bg-raised)', border: '1px solid var(--border-faint)',
          borderRadius: 'var(--radius-2)', padding: '14px 18px', margin: '16px 0',
          display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16,
        }}>
          <div>
            <div style={{ font: '500 10px/1 var(--font-mono)', color: 'var(--fg-faint)', marginBottom: 6, textTransform: 'uppercase' }}>
              Rate
            </div>
            <div style={{ font: '700 20px/1 var(--font-mono)', color: 'var(--fg-default)' }}>
              2,000 bps
            </div>
            <div style={{ font: '400 11px/1.4 var(--font-sans)', color: 'var(--fg-faint)', marginTop: 4 }}>
              20% of profit above HWM
            </div>
          </div>
          <div>
            <div style={{ font: '500 10px/1 var(--font-mono)', color: 'var(--fg-faint)', marginBottom: 6, textTransform: 'uppercase' }}>
              Distribution
            </div>
            <div style={{ font: '700 20px/1 var(--font-mono)', color: 'var(--fg-default)' }}>
              FeeSplitter
            </div>
            <div style={{ font: '400 11px/1.4 var(--font-sans)', color: 'var(--fg-faint)', marginTop: 4 }}>
              Split to fee-share holders
            </div>
          </div>
        </div>
      </section>

      <BackToTop />
    </article>
  );
}
