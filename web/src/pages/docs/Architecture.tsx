import { motion } from 'motion/react';
import { useState, useEffect } from 'react';
import styles from './Architecture.module.css';

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

function ContractMapDiagram() {
  const contracts = [
    { label: 'ManagerContract', x: 300, y: 30, immutable: true },
    { label: 'NftFactory', x: 300, y: 100, immutable: true },
    { label: 'VaultCore', x: 180, y: 180 },
    { label: 'VaultState', x: 420, y: 180 },
    { label: 'Deposit\nHandler', x: 60, y: 270 },
    { label: 'Withdraw\nHandler', x: 170, y: 270 },
    { label: 'Manager\nHandler', x: 280, y: 270 },
    { label: 'Recovery\nHandler', x: 390, y: 270 },
    { label: 'Fee\nHandler', x: 500, y: 270 },
    { label: 'FeeSplitter', x: 540, y: 100, immutable: true },
  ];

  const edges: [number, number][] = [
    [0, 1], [1, 2], [1, 3], [2, 4], [2, 5], [2, 6], [2, 7], [2, 8], [0, 9],
  ];

  return (
    <svg viewBox="0 0 640 330" className={styles.svg}>
      <defs>
        <marker id="arr" markerWidth="6" markerHeight="5" refX="5" refY="2.5" orient="auto">
          <path d="M0,0 L6,2.5 L0,5" fill="var(--ember-500)" />
        </marker>
      </defs>
      {edges.map(([from, to], i) => {
        const a = contracts[from], b = contracts[to];
        return (
          <motion.line key={i}
            x1={a.x} y1={a.y + 18} x2={b.x} y2={b.y - 4}
            stroke="var(--border-default)" strokeWidth={1}
            markerEnd="url(#arr)"
            variants={draw} initial="hidden" whileInView="visible" custom={i}
            viewport={{ once: true }}
          />
        );
      })}
      {contracts.map((c, i) => (
        <motion.g key={c.label}
          variants={fadeIn} initial="hidden" whileInView="visible" custom={i}
          viewport={{ once: true }}
        >
          <rect
            x={c.x - 48} y={c.y - 14} width={96} height={28} rx={3}
            fill={c.immutable ? 'rgba(255,106,61,0.08)' : 'var(--bg-raised)'}
            stroke={c.immutable ? 'var(--ember-500)' : 'var(--border-default)'}
            strokeWidth={1}
          />
          {c.label.split('\n').map((line, li) => (
            <text key={li}
              x={c.x} y={c.y + (li * 12) - (c.label.includes('\n') ? 3 : 0) + 2}
              textAnchor="middle" fontSize={9} fontFamily="var(--font-mono)"
              fill={c.immutable ? 'var(--ember-500)' : 'var(--fg-muted)'}
            >{line}</text>
          ))}
        </motion.g>
      ))}
    </svg>
  );
}

function StateMachineDiagram() {
  const machines = [
    { name: 'Deposit', states: ['IDLE', 'PENDING'], color: 'var(--mineral-500)' },
    { name: 'Withdraw', states: ['IDLE', 'PENDING'], color: 'var(--sulfur-500)' },
    { name: 'Rebalance', states: ['IDLE', 'PENDING'], color: 'var(--ember-500)' },
  ];

  return (
    <svg viewBox="0 0 420 200" className={styles.svg}>
      {machines.map((m, mi) => {
        const y = 30 + mi * 60;
        return (
          <g key={m.name}>
            <text x={20} y={y + 16} fontSize={11} fontFamily="var(--font-mono)"
              fill={m.color} fontWeight={600}>{m.name}</text>
            {m.states.map((s, si) => {
              const x = 140 + si * 160;
              return (
                <g key={s}>
                  <motion.rect
                    x={x - 44} y={y} width={88} height={28} rx={14}
                    fill="none" stroke={si === 0 ? m.color : 'var(--border-default)'}
                    strokeWidth={si === 0 ? 1.5 : 1}
                    variants={fadeIn} initial="hidden" whileInView="visible" custom={mi * 3 + si}
                    viewport={{ once: true }}
                  />
                  <text x={x} y={y + 17} textAnchor="middle" fontSize={9}
                    fontFamily="var(--font-mono)"
                    fill={si === 0 ? m.color : 'var(--fg-muted)'}>{s}</text>
                  {si < m.states.length - 1 && (
                    <motion.line
                      x1={x + 44} y1={y + 14} x2={x + 116} y2={y + 14}
                      stroke="var(--border-default)" strokeWidth={1} markerEnd="url(#arr)"
                      variants={draw} initial="hidden" whileInView="visible" custom={mi * 3 + si}
                      viewport={{ once: true }}
                    />
                  )}
                </g>
              );
            })}
          </g>
        );
      })}
    </svg>
  );
}

function ControlFlowDiagram() {
  return (
    <svg viewBox="0 0 500 180" className={styles.svg}>
      <defs>
        <marker id="arr2" markerWidth="6" markerHeight="5" refX="5" refY="2.5" orient="auto">
          <path d="M0,0 L6,2.5 L0,5" fill="var(--ember-500)" />
        </marker>
      </defs>
      {/* NFT Owner */}
      <motion.g variants={fadeIn} initial="hidden" whileInView="visible" custom={0} viewport={{ once: true }}>
        <rect x={10} y={40} width={100} height={32} rx={3} fill="rgba(100,200,130,0.08)" stroke="var(--mineral-500)" strokeWidth={1} />
        <text x={60} y={60} textAnchor="middle" fontSize={10} fontFamily="var(--font-mono)" fill="var(--mineral-500)">NFT Owner</text>
      </motion.g>

      {/* Protocol Manager */}
      <motion.g variants={fadeIn} initial="hidden" whileInView="visible" custom={1} viewport={{ once: true }}>
        <rect x={10} y={110} width={100} height={32} rx={3} fill="rgba(255,106,61,0.08)" stroke="var(--ember-500)" strokeWidth={1} />
        <text x={60} y={130} textAnchor="middle" fontSize={10} fontFamily="var(--font-mono)" fill="var(--ember-500)">Manager</text>
      </motion.g>

      {/* Handler */}
      <motion.g variants={fadeIn} initial="hidden" whileInView="visible" custom={2} viewport={{ once: true }}>
        <rect x={200} y={70} width={100} height={40} rx={3} fill="var(--bg-raised)" stroke="var(--border-default)" strokeWidth={1} />
        <text x={250} y={94} textAnchor="middle" fontSize={10} fontFamily="var(--font-mono)" fill="var(--fg-muted)">Handler</text>
      </motion.g>

      {/* VaultCore */}
      <motion.g variants={fadeIn} initial="hidden" whileInView="visible" custom={3} viewport={{ once: true }}>
        <rect x={380} y={70} width={100} height={40} rx={3} fill="rgba(255,106,61,0.06)" stroke="var(--ember-500)" strokeWidth={1} />
        <text x={430} y={87} textAnchor="middle" fontSize={9} fontFamily="var(--font-mono)" fill="var(--ember-500)">VaultCore</text>
        <text x={430} y={100} textAnchor="middle" fontSize={8} fontFamily="var(--font-mono)" fill="var(--fg-faint)">universalCall</text>
      </motion.g>

      {/* Arrows */}
      <motion.line x1={110} y1={56} x2={200} y2={82} stroke="var(--mineral-500)" strokeWidth={1} markerEnd="url(#arr2)" variants={draw} initial="hidden" whileInView="visible" custom={4} viewport={{ once: true }} />
      <motion.line x1={110} y1={126} x2={200} y2={98} stroke="var(--ember-500)" strokeWidth={1} markerEnd="url(#arr2)" variants={draw} initial="hidden" whileInView="visible" custom={5} viewport={{ once: true }} />
      <motion.line x1={300} y1={90} x2={380} y2={90} stroke="var(--border-default)" strokeWidth={1} markerEnd="url(#arr2)" variants={draw} initial="hidden" whileInView="visible" custom={6} viewport={{ once: true }} />
    </svg>
  );
}

const tocItems = [
  { id: 'contract-map', label: 'Contract map' },
  { id: 'control-flow', label: 'Control flow' },
  { id: 'state-machine', label: 'State machines' },
  { id: 'constants', label: 'Key constants' },
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

export function Architecture() {
  return (
    <article className={styles.page}>
      <h1 className={styles.pageTitle}>Architecture</h1>

      <nav className={styles.toc} aria-label="Table of contents">
        {tocItems.map((item) => (
          <a key={item.id} href={`#${item.id}`} className={styles.tocLink}>
            {item.label}
          </a>
        ))}
      </nav>
      <p className={styles.subtitle}>
        Pseudo-delta neutral GM-BTC/USDC leveraged position protocol on Arbitrum One.
        Honest about residual exposure. Immutable handlers.
      </p>

      <section className={styles.section} id="contract-map">
        <h2 className={styles.sectionTitle}>Contract map</h2>
        <p className={styles.body}>
          Each vault is a clone of <span className={styles.highlight}>VaultCore + VaultState</span>, minted as an <span className={styles.highlight}>ERC-721</span>.
          Orange = immutable. Handlers encode logic and mutate state through <span className={styles.highlight}>universalCall</span>.
        </p>
        <div className={styles.diagramWrap}>
          <ContractMapDiagram />
        </div>
      </section>

      <hr className={styles.divider} />

      <section className={styles.section} id="control-flow">
        <h2 className={styles.sectionTitle}>Control flow</h2>
        <p className={styles.body}>
          Two initiators: <span className={styles.highlight}>NFT owner</span> and <span className={styles.highlight}>protocol manager</span>. Both reach vault logic through handlers.
        </p>
        <div className={styles.diagramWrap}>
          <ControlFlowDiagram />
        </div>

        <div className={styles.twoCol}>
          <div>
            <h3 className={styles.subsectionTitle}>NFT owner</h3>
            <ul className={styles.list}>
              <li>Deposit, withdraw</li>
              <li>Rebalance (when LTV drifts)</li>
              <li>Accept handler upgrades</li>
              <li>Cancel stuck operations after grace period</li>
            </ul>
          </div>
          <div>
            <h3 className={styles.subsectionTitle}>Protocol manager</h3>
            <ul className={styles.list}>
              <li>Rebalance anytime</li>
              <li>Set risk parameters</li>
              <li>Accrue + withdraw fees</li>
              <li>Propose upgrades</li>
            </ul>
          </div>
        </div>
      </section>

      <hr className={styles.divider} />

      <section className={styles.section} id="state-machine">
        <h2 className={styles.sectionTitle}>State machines</h2>
        <p className={styles.body}>
          Three independent sub-machines. All require <span className={styles.highlight}>all-idle + cooldown-passed</span> to start.
          Cooldown = <span className={styles.highlight}>1 block</span>, armed after deposit finalize.
        </p>
        <div className={styles.diagramWrap}>
          <StateMachineDiagram />
        </div>
      </section>

      <hr className={styles.divider} />

      <section className={styles.section} id="constants">
        <h2 className={styles.sectionTitle}>Key constants</h2>
        <div className={styles.constGrid}>
          {[
            ['MAX_SAFE_LTV', '7,000 bps (70%)'],
            ['TARGET_LTV', '5,000 bps (50%)'],
            ['TARGET_RANGE', '4,800–5,200 bps'],
            ['PERFORMANCE_FEE', '2,000 bps (20%)'],
            ['COOLDOWN', '1 block'],
            ['KEEPER_DEADLINE', '60s (60s–60m)'],
            ['UNSTUCK_GRACE', '10 min'],
            ['LIQUIDATION_LT', '~83.8% (Dolomite)'],
            ['ISOLATION_ACCOUNT', '#100'],
            ['GOV_THRESHOLD', '80% past supply'],
          ].map(([k, v]) => (
            <div key={k} className={styles.constItem}>
              <span className={styles.constKey}>{k}</span>
              <span className={styles.constVal}>{v}</span>
            </div>
          ))}
        </div>
      </section>

      <BackToTop />
    </article>
  );
}
