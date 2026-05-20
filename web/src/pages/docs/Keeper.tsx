import { motion } from 'motion/react';
import { useState, useEffect } from 'react';
import styles from './Keeper.module.css';

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

/** Keeper lifecycle diagram — what triggers keeper and what keeper does */
function KeeperLifecycleDiagram() {
  const rows = [
    { trigger: 'deposit()', keeper: 'finalizeDeposit()', time: '~2s', handler: 'DepositHandler' },
    { trigger: 'withdraw()', keeper: 'finalizeWithdraw()', time: '~2s', handler: 'WithdrawHandler' },
    { trigger: 'rebalanceVault()', keeper: 'finalizeRebalance()', time: '~2s', handler: 'ManagerContract' },
  ];

  return (
    <svg viewBox="0 0 700 200" className={styles.svg}>
      <defs>
        <marker id="kp-arr" markerWidth="6" markerHeight="5" refX="5" refY="2.5" orient="auto">
          <path d="M0,0 L6,2.5 L0,5" fill="var(--ember-500)" />
        </marker>
      </defs>
      {/* Header */}
      <text x={80} y={20} textAnchor="middle" fontSize={11} fontFamily="var(--font-mono)"
        fill="var(--fg-faint)" fontWeight={600}>USER ACTION</text>
      <text x={300} y={20} textAnchor="middle" fontSize={11} fontFamily="var(--font-mono)"
        fill="var(--fg-faint)" fontWeight={600}>STATE</text>
      <text x={550} y={20} textAnchor="middle" fontSize={11} fontFamily="var(--font-mono)"
        fill="var(--fg-faint)" fontWeight={600}>KEEPER / USER</text>

      {rows.map((r, i) => {
        const y = 45 + i * 55;
        return (
          <motion.g key={r.trigger}
            variants={fadeIn} initial="hidden" whileInView="visible" custom={i}
            viewport={{ once: true }}>
            {/* Trigger box */}
            <rect x={10} y={y} width={140} height={34} rx={4}
              fill="var(--bg-raised)" stroke="var(--mineral-500)" strokeWidth={1} />
            <text x={80} y={y + 20} textAnchor="middle" fontSize={11}
              fontFamily="var(--font-mono)" fill="var(--mineral-500)">{r.trigger}</text>

            {/* Arrow to PENDING */}
            <motion.line x1={150} y1={y + 17} x2={225} y2={y + 17}
              stroke="var(--border-default)" strokeWidth={1} markerEnd="url(#kp-arr)"
              variants={draw} initial="hidden" whileInView="visible" custom={i * 3}
              viewport={{ once: true }} />

            {/* PENDING state */}
            <rect x={230} y={y} width={100} height={34} rx={17}
              fill="none" stroke="var(--sulfur-500)" strokeWidth={1.5} />
            <text x={280} y={y + 20} textAnchor="middle" fontSize={11}
              fontFamily="var(--font-mono)" fill="var(--sulfur-500)">PENDING</text>

            {/* Timing label */}
            <text x={370} y={y + 14} textAnchor="middle" fontSize={9}
              fontFamily="var(--font-mono)" fill="var(--fg-faint)">{r.time}</text>

            {/* Arrow to finalize */}
            <motion.line x1={330} y1={y + 17} x2={450} y2={y + 17}
              stroke="var(--ember-500)" strokeWidth={1} strokeDasharray="4 3"
              markerEnd="url(#kp-arr)"
              variants={draw} initial="hidden" whileInView="visible" custom={i * 3 + 1}
              viewport={{ once: true }} />

            {/* Finalize box */}
            <rect x={455} y={y} width={170} height={34} rx={4}
              fill="rgba(255,106,61,0.06)" stroke="var(--ember-500)" strokeWidth={1} />
            <text x={540} y={y + 14} textAnchor="middle" fontSize={11}
              fontFamily="var(--font-mono)" fill="var(--ember-500)">{r.keeper}</text>
            <text x={540} y={y + 27} textAnchor="middle" fontSize={9}
              fontFamily="var(--font-mono)" fill="var(--fg-faint)">{r.handler}</text>
          </motion.g>
        );
      })}
    </svg>
  );
}

/** Unstuck flow diagram */
function UnstuckDiagram() {
  const steps = [
    { label: 'Operation\nstarts', x: 60, y: 50 },
    { label: 'PENDING', x: 180, y: 50 },
    { label: 'Deadline\n(60s)', x: 300, y: 50 },
    { label: 'Grace\n(+10min)', x: 420, y: 50 },
    { label: 'Anyone\ncan cancel', x: 540, y: 50 },
  ];

  return (
    <svg viewBox="0 0 660 115" className={styles.svg}>
      <defs>
        <marker id="us-arr" markerWidth="6" markerHeight="5" refX="5" refY="2.5" orient="auto">
          <path d="M0,0 L6,2.5 L0,5" fill="var(--ember-500)" />
        </marker>
      </defs>
      {steps.map((s, i) => (
        <motion.g key={s.label}
          initial={{ opacity: 0 }}
          whileInView={{ opacity: 1 }}
          viewport={{ once: true }}
          transition={{ delay: i * 0.03, duration: 0.2, ease: 'easeOut' }}>
          <rect x={s.x - 55} y={s.y - 18} width={110} height={40} rx={4}
            fill={i === 4 ? 'rgba(255,106,61,0.06)' : 'var(--bg-raised)'}
            stroke={i === 4 ? 'var(--ember-500)' : i === 1 ? 'var(--sulfur-500)' : 'var(--border-default)'}
            strokeWidth={1} />
          {s.label.split('\n').map((line, li) => (
            <text key={li} x={s.x} y={s.y + li * 14 - (s.label.includes('\n') ? 3 : 1)}
              textAnchor="middle" fontSize={11} fontFamily="var(--font-mono)"
              fill={i === 4 ? 'var(--ember-500)' : i === 1 ? 'var(--sulfur-500)' : 'var(--fg-muted)'}>
              {line}
            </text>
          ))}
          {i < steps.length - 1 && (
            <motion.line x1={s.x + 55} y1={s.y + 2} x2={steps[i + 1].x - 55} y2={steps[i + 1].y + 2}
              stroke="var(--border-default)" strokeWidth={1} markerEnd="url(#us-arr)"
              initial={{ opacity: 0 }}
              whileInView={{ opacity: 1 }}
              viewport={{ once: true }}
              transition={{ delay: i * 0.03, duration: 0.2, ease: 'easeOut' }} />
          )}
        </motion.g>
      ))}
      {/* Timeline bar */}
      <motion.rect x={10} y={92} width={640} height={4} rx={2}
        fill="var(--border-faint)"
        initial={{ opacity: 0 }} whileInView={{ opacity: 1 }} viewport={{ once: true }}
        transition={{ delay: 0.06, duration: 0.2, ease: 'easeOut' }} />
      <text x={60} y={108} textAnchor="middle" fontSize={9} fontFamily="var(--font-mono)" fill="var(--fg-faint)">t=0</text>
      <text x={300} y={108} textAnchor="middle" fontSize={9} fontFamily="var(--font-mono)" fill="var(--fg-faint)">+60s</text>
      <text x={420} y={108} textAnchor="middle" fontSize={9} fontFamily="var(--font-mono)" fill="var(--fg-faint)">+10min</text>
      <text x={540} y={108} textAnchor="middle" fontSize={9} fontFamily="var(--font-mono)" fill="var(--ember-500)">unstuck</text>
    </svg>
  );
}

const tocItems = [
  { id: 'overview', label: 'Overview' },
  { id: 'lifecycle', label: 'Lifecycle' },
  { id: 'actions', label: 'Actions' },
  { id: 'unstuck', label: 'Unstuck' },
  { id: 'monitoring', label: 'Monitoring' },
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

export function Keeper() {
  return (
    <article className={styles.page}>
      <h1 className={styles.pageTitle}>Keeper Operations</h1>

      <nav className={styles.toc} aria-label="Table of contents">
        {tocItems.map((item) => (
          <a key={item.id} href={`#${item.id}`} className={styles.tocLink}>{item.label}</a>
        ))}
      </nav>

      <p className={styles.subtitle}>
        Keepers <span className={styles.highlight}>finalize async operations</span> (deposit, withdraw, rebalance) after GMX settlement.
        The keeper dashboard reads vault state and triggers finalization.
      </p>

      <section className={styles.section} id="overview">
        <h2 className={styles.sectionTitle}>What is a keeper</h2>
        <p className={styles.body}>
          GMX v2 operations are <span className={styles.highlight}>asynchronous</span>. When you deposit or withdraw, a <span className={styles.highlight}>GMX keeper</span>
          settles the order first (~2 seconds on Arbitrum). Then a <span className={styles.highlight}>Basalt keeper</span> (or the
          user themselves) calls the <span className={styles.highlight}>finalize</span> function to complete the vault operation.
        </p>
        <p className={styles.body}>
          The keeper dashboard at <code>app.btva.io/keeper</code> provides a UI for these operations.
          It requires connecting with the protocol manager or operational role wallet.
        </p>
      </section>

      <hr className={styles.divider} />

      <section className={styles.section} id="lifecycle">
        <h2 className={styles.sectionTitle}>Keeper lifecycle</h2>
        <div className={styles.diagramWrap}>
          <KeeperLifecycleDiagram />
        </div>
        <p className={styles.body}>
          Each operation follows the same pattern: user triggers → state becomes <span className={styles.highlight}>PENDING</span> →
          GMX keeper settles → Basalt keeper/user finalizes → state returns to <span className={styles.highlight}>IDLE</span>.
          All three state machines (deposit, withdraw, rebalance) must be IDLE before
          a new operation can start.
        </p>
      </section>

      <hr className={styles.divider} />

      <section className={styles.section} id="actions">
        <h2 className={styles.sectionTitle}>Keeper actions</h2>
        <div className={styles.actionGrid}>
          {[
            {
              name: 'finalizeDeposit',
              contract: 'DepositHandler',
              desc: 'Completes pending deposit. Borrows WBTC, wraps to GM, loops to target LTV.',
              sig: 'finalizeDeposit(address targetVaultCore)',
            },
            {
              name: 'finalizeWithdraw',
              contract: 'WithdrawHandler',
              desc: 'Completes pending withdrawal. Repays WBTC debt, returns collateral to user.',
              sig: 'finalizeWithdraw(address targetVaultCore)',
            },
            {
              name: 'finalizeRebalance',
              contract: 'ManagerContract',
              desc: 'Completes pending rebalance after GMX wraps/unwraps settle.',
              sig: 'finalizeRebalance(address handler, address vault)',
            },
            {
              name: 'rebalanceVault',
              contract: 'ManagerContract',
              desc: 'Triggers LTV rebalance when position drifts from target. Payable for exec fee.',
              sig: 'rebalanceVault(address handler, address vault, uint256 slippageBps)',
            },
            {
              name: 'setVaultTargetLtv',
              contract: 'ManagerContract',
              desc: 'Updates the target LTV for a vault. Range 4,800–5,200 bps.',
              sig: 'setVaultTargetLtv(address handler, address vault, uint256 bps)',
            },
            {
              name: 'readVaultState',
              contract: 'VaultState (via VaultCore)',
              desc: 'Reads current state: deposit/withdraw/rebalance states, NAV, LTV, collateral, debt.',
              sig: 'multicall: depositState(), withdrawState(), rebalanceState(), gmCollateral, wbtcDebt, navUsd, totalDepositedGm, currentLtvBps',
            },
          ].map((a, i) => (
            <motion.div key={a.name} className={styles.actionCard}
              initial={{ opacity: 0 }}
              whileInView={{ opacity: 1 }}
              viewport={{ once: true }}
              transition={{ delay: i * 0.03, duration: 0.2, ease: 'easeOut' }}>
              <div className={styles.actionName}>{a.name}</div>
              <div className={styles.actionContract}>{a.contract}</div>
              <div className={styles.actionDesc}>{a.desc}</div>
              <div className={styles.actionSig}>{a.sig}</div>
            </motion.div>
          ))}
        </div>
      </section>

      <hr className={styles.divider} />

      <section className={styles.section} id="unstuck">
        <h2 className={styles.sectionTitle}>Unstuck mechanism</h2>
        <p className={styles.body}>
          GMX settles wraps in ~2s; the Basalt keeper finalizes in ~2s after that. If something goes wrong and the operation is stuck past the
          <span className={styles.highlight}>deadline + grace period</span>, the vault NFT owner or protocol manager can cancel via
          <span className={styles.highlight}>AsyncRecoveryHandler</span> and recover funds. This is a safety net that almost never triggers.
        </p>
        <div className={styles.diagramWrap}>
          <UnstuckDiagram />
        </div>
      </section>

      <hr className={styles.divider} />

      <section className={styles.section} id="monitoring">
        <h2 className={styles.sectionTitle}>Monitoring</h2>
        <p className={styles.body}>
          The keeper dashboard supports auto-refresh at ~12-second intervals (one Arbitrum
          block). It reads vault state via a single multicall RPC call that returns:
        </p>
        <ul className={styles.list}>
          <li>Deposit/withdraw/rebalance state (IDLE or PENDING)</li>
          <li>Current LTV in basis points</li>
          <li>NAV in USD (18 decimals)</li>
          <li>GM collateral (18 decimals)</li>
          <li>WBTC debt (8 decimals)</li>
          <li>Total deposited GM</li>
        </ul>
        <p className={styles.body}>
          RPC reads use viem's PublicClient with fallback transports: local nginx proxy
          (<code>/rpc</code>, <code>/rpc2</code>) → public Arbitrum RPC.
        </p>
      </section>

      <BackToTop />
    </article>
  );
}
