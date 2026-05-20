import { motion } from 'motion/react';
import { useState, useEffect } from 'react';
import styles from './Risks.module.css';

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

/* ─── Architecture diagram: immutable core + swappable handlers ─── */
function CoreHandlerDiagram() {
  return (
    <svg viewBox="0 0 620 230" className={styles.svg}>
      <defs>
        <marker id="rk-arr" markerWidth="6" markerHeight="5" refX="5" refY="2.5" orient="auto">
          <path d="M0,0 L6,2.5 L0,5" fill="var(--ember-500)" />
        </marker>
        <marker id="rk-arr-m" markerWidth="6" markerHeight="5" refX="5" refY="2.5" orient="auto">
          <path d="M0,0 L6,2.5 L0,5" fill="var(--mineral-500)" />
        </marker>
      </defs>

      {/* Immutable core block */}
      <motion.g variants={fadeIn} initial="hidden" whileInView="visible" custom={0} viewport={{ once: true }}>
        <rect x={20} y={60} width={170} height={110} rx={8}
          fill="rgba(255,106,61,0.04)" stroke="var(--ember-500)" strokeWidth={2} />
        <text x={105} y={85} textAnchor="middle" fontSize={13}
          fontFamily="var(--font-mono)" fontWeight={700} fill="var(--ember-500)">VaultCore</text>
        <text x={105} y={102} textAnchor="middle" fontSize={10}
          fontFamily="var(--font-mono)" fill="var(--fg-faint)">IMMUTABLE</text>
        <text x={105} y={122} textAnchor="middle" fontSize={9}
          fontFamily="var(--font-sans)" fill="var(--fg-muted)">universalCall()</text>
        <text x={105} y={136} textAnchor="middle" fontSize={9}
          fontFamily="var(--font-sans)" fill="var(--fg-muted)">proposeHandler()</text>
        <text x={105} y={150} textAnchor="middle" fontSize={9}
          fontFamily="var(--font-sans)" fill="var(--fg-muted)">acceptHandler()</text>
      </motion.g>

      {/* Arrow to handlers */}
      <motion.g variants={fadeIn} initial="hidden" whileInView="visible" custom={1} viewport={{ once: true }}>
        <motion.line x1={190} y1={115} x2={250} y2={115}
          stroke="var(--ember-500)" strokeWidth={1.5} markerEnd="url(#rk-arr)"
          variants={draw} initial="hidden" whileInView="visible" custom={1}
          viewport={{ once: true }} />
      </motion.g>

      {/* Handler slots */}
      {[
        { name: 'DepositHandler', y: 15, color: 'var(--mineral-500)' },
        { name: 'WithdrawHandler', y: 60, color: 'var(--mineral-500)' },
        { name: 'ManagerHandler', y: 105, color: 'var(--sulfur-500)' },
        { name: 'FeeAccounting', y: 150, color: 'var(--sulfur-500)' },
        { name: 'AsyncRecovery', y: 195, color: 'var(--fg-muted)' },
      ].map((h, i) => (
        <motion.g key={h.name} variants={fadeIn} initial="hidden" whileInView="visible" custom={i + 2}
          viewport={{ once: true }}>
          <rect x={255} y={h.y} width={150} height={32} rx={4}
            fill="var(--bg-raised)" stroke={h.color} strokeWidth={1} />
          <text x={330} y={h.y + 20} textAnchor="middle" fontSize={10}
            fontFamily="var(--font-mono)" fontWeight={600} fill={h.color}>{h.name}</text>
        </motion.g>
      ))}

      {/* Swappable label */}
      <motion.g variants={fadeIn} initial="hidden" whileInView="visible" custom={7} viewport={{ once: true }}>
        <rect x={420} y={90} width={100} height={50} rx={6}
          fill="rgba(100,200,130,0.06)" stroke="var(--mineral-500)" strokeWidth={1} strokeDasharray="4 3" />
        <text x={470} y={112} textAnchor="middle" fontSize={10}
          fontFamily="var(--font-mono)" fontWeight={600} fill="var(--mineral-500)">SWAPPABLE</text>
        <text x={470} y={128} textAnchor="middle" fontSize={9}
          fontFamily="var(--font-sans)" fill="var(--fg-faint)">propose + accept</text>
      </motion.g>

      {/* NFT owner accept */}
      <motion.g variants={fadeIn} initial="hidden" whileInView="visible" custom={8} viewport={{ once: true }}>
        <rect x={530} y={90} width={80} height={50} rx={4}
          fill="rgba(255,106,61,0.06)" stroke="var(--ember-500)" strokeWidth={1} />
        <text x={570} y={112} textAnchor="middle" fontSize={10}
          fontFamily="var(--font-mono)" fontWeight={600} fill="var(--ember-500)">NFT Owner</text>
        <text x={570} y={128} textAnchor="middle" fontSize={9}
          fontFamily="var(--font-sans)" fill="var(--fg-faint)">must accept</text>
      </motion.g>

      {/* Arrow from swappable to NFT owner */}
      <motion.line x1={520} y1={115} x2={528} y2={115}
        stroke="var(--ember-500)" strokeWidth={1} markerEnd="url(#rk-arr)"
        variants={draw} initial="hidden" whileInView="visible" custom={8}
        viewport={{ once: true }} />
    </svg>
  );
}

const tocItems = [
  { id: 'smart-contract', label: 'Smart contract' },
  { id: 'protocol-deps', label: 'Protocol deps' },
  { id: 'market', label: 'Market risk' },
  { id: 'operational', label: 'Operational' },
  { id: 'isolation', label: 'Isolation' },
  { id: 'summary', label: 'Summary' },
];

function Const({ children }: { children: React.ReactNode }) {
  return <span className={styles.constPill}>{children}</span>;
}

function SeverityBadge({ level }: { level: 'critical' | 'high' | 'medium' | 'low' }) {
  const cls = level === 'critical' ? styles.severityCritical
    : level === 'high' ? styles.severityHigh
    : level === 'medium' ? styles.severityMedium
    : styles.severityLow;
  return <span className={`${styles.riskSeverity} ${cls}`}>{level}</span>;
}

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

export function Risks() {
  return (
    <article className={styles.page}>
      <h1 className={styles.pageTitle}>Risk Assessment</h1>

      <nav className={styles.toc} aria-label="Table of contents">
        {tocItems.map((item) => (
          <a key={item.id} href={`#${item.id}`} className={styles.tocLink}>{item.label}</a>
        ))}
      </nav>

      <div className={styles.disclaimer}>
        <strong>Honest disclosure.</strong> No smart contract system is provably unhackable.
        We believe Basalt is more robust than the vast majority of DeFi protocols due to its
        immutable core, per-vault isolation, and symbolic testing (Halmos). But we cannot guarantee zero bugs.
        This page documents every risk we are aware of and how each is mitigated.
      </div>

      {/* ═══════ SMART CONTRACT RISK ═══════ */}
      <section className={styles.section} id="smart-contract">
        <h2 className={styles.sectionTitle}>Smart contract risk</h2>

        <p className={styles.body}>
          Basalt uses a <span className={styles.highlight}>dual architecture</span>: an immutable core (<span className={styles.mono}>VaultCore</span>)
          paired with swappable handler contracts. This design makes deliberate trade-offs between
          safety and patchability.
        </p>

        <div className={styles.diagramWrap}>
          <CoreHandlerDiagram />
        </div>

        <div className={styles.riskGrid}>
          <motion.div className={styles.riskCard}
            variants={fadeIn} initial="hidden" whileInView="visible" custom={0}
            viewport={{ once: true }}>
            <div className={styles.riskHeader}>
              <SeverityBadge level="high" />
              <span className={styles.riskTitle}>Immutable core bugs</span>
            </div>
            <div className={styles.riskDesc}>
              VaultCore is deployed once and cannot be upgraded. If a bug exists in <span className={styles.mono}>universalCall()</span>,
              handler slot logic, or the deadman switch, it cannot be patched. The core is intentionally
              minimal (~270 lines) to reduce attack surface.
            </div>
          </motion.div>

          <motion.div className={styles.riskCard}
            variants={fadeIn} initial="hidden" whileInView="visible" custom={1}
            viewport={{ once: true }}>
            <div className={styles.riskHeader}>
              <SeverityBadge level="medium" />
              <span className={styles.riskTitle}>Handler upgrade flow</span>
            </div>
            <div className={styles.riskDesc}>
              Handlers can be replaced via a two-step process: the protocol manager proposes, the NFT owner
              accepts. This means bugs <em>can</em> be fixed, but a malicious handler could be proposed.
              The NFT owner is the final gatekeeper — no upgrade happens without their explicit <span className={styles.mono}>acceptHandler()</span> call.
            </div>
          </motion.div>

          <motion.div className={styles.riskCard}
            variants={fadeIn} initial="hidden" whileInView="visible" custom={2}
            viewport={{ once: true }}>
            <div className={styles.riskHeader}>
              <SeverityBadge level="medium" />
              <span className={styles.riskTitle}>Protocol manager change</span>
            </div>
            <div className={styles.riskDesc}>
              The protocol manager (ManagerContract) can be replaced via an on-chain vote requiring
              <Const>80%</Const> approval from fee participants (FeeSplitter token holders, snapshot-based).
              This is a governance risk mitigated by supermajority threshold and snapshot voting
              to prevent flash-loan attacks.
            </div>
          </motion.div>
        </div>
      </section>

      <hr className={styles.divider} />

      {/* ═══════ PROTOCOL DEPENDENCY RISK ═══════ */}
      <section className={styles.section} id="protocol-deps">
        <h2 className={styles.sectionTitle}>Protocol dependency risk</h2>
        <p className={styles.body}>
          Basalt is built on top of three external protocols. If any of them fails, Basalt positions are affected.
          This is an inherent trade-off of composable DeFi.
        </p>

        <div className={styles.riskGrid}>
          <motion.div className={styles.riskCard}
            variants={fadeIn} initial="hidden" whileInView="visible" custom={0}
            viewport={{ once: true }}>
            <div className={styles.riskHeader}>
              <SeverityBadge level="critical" />
              <span className={styles.riskTitle}>GMX v2</span>
            </div>
            <div className={styles.riskDesc}>
              GM tokens are the core collateral. If GMX v2 suffers a hack, oracle manipulation, or
              liquidity crisis, GM token value could drop to zero. Basalt cannot protect against
              GMX protocol failure — it is a fundamental dependency.
              The emergency handler provides a unwind path with a <Const>30-min TWAP</Const> and
              chunked withdrawal (1% of GM supply per chunk) to exit orderly.
            </div>
          </motion.div>

          <motion.div className={styles.riskCard}
            variants={fadeIn} initial="hidden" whileInView="visible" custom={1}
            viewport={{ once: true }}>
            <div className={styles.riskHeader}>
              <SeverityBadge level="critical" />
              <span className={styles.riskTitle}>Dolomite</span>
            </div>
            <div className={styles.riskDesc}>
              Dolomite provides leverage via isolation accounts (account #100). If Dolomite is compromised
              or becomes insolvent, borrowed USDC could be lost. Position isolation means each vault has
              its own Dolomite account — one vault's liquidation does not cascade to others.
            </div>
          </motion.div>

          <motion.div className={styles.riskCard}
            variants={fadeIn} initial="hidden" whileInView="visible" custom={2}
            viewport={{ once: true }}>
            <div className={styles.riskHeader}>
              <SeverityBadge level="high" />
              <span className={styles.riskTitle}>Chainlink oracles</span>
            </div>
            <div className={styles.riskDesc}>
              Price feeds for WBTC and USDC are sourced from Chainlink. Staleness protection rejects
              prices older than <Const>90,000s (~25h)</Const>. Absolute sanity ceilings reject
              WBTC prices above <Const>$10M</Const> and USDC above <Const>$10</Const>.
              Cross-source validation compares Chainlink vs Dolomite prices with a <Const>0.25%</Const> spread guard.
              None of this helps if Chainlink itself is compromised at the protocol level.
            </div>
          </motion.div>

          <motion.div className={styles.riskCard}
            variants={fadeIn} initial="hidden" whileInView="visible" custom={3}
            viewport={{ once: true }}>
            <div className={styles.riskHeader}>
              <SeverityBadge level="medium" />
              <span className={styles.riskTitle}>Arbitrum sequencer</span>
            </div>
            <div className={styles.riskDesc}>
              All operations check the Chainlink sequencer uptime feed. After a sequencer restart,
              a <Const>3,600s (1h)</Const> grace period blocks all actions to let oracles catch up.
              Extended outages (hours/days) could prevent withdrawals and rebalances, leaving positions
              exposed to market moves.
            </div>
          </motion.div>
        </div>
      </section>

      <hr className={styles.divider} />

      {/* ═══════ MARKET RISK ═══════ */}
      <section className={styles.section} id="market">
        <h2 className={styles.sectionTitle}>Market risk</h2>
        <p className={styles.body}>
          Basalt targets delta-neutral exposure through a leveraged GM position hedged via Dolomite borrowing.
          This is not a perfect hedge — residual risk remains.
        </p>

        <div className={styles.riskGrid}>
          <motion.div className={styles.riskCard}
            variants={fadeIn} initial="hidden" whileInView="visible" custom={0}
            viewport={{ once: true }}>
            <div className={styles.riskHeader}>
              <SeverityBadge level="high" />
              <span className={styles.riskTitle}>Residual BTC delta</span>
            </div>
            <div className={styles.riskDesc}>
              The vault is not fully delta-neutral. Between rebalances, BTC price moves create residual
              exposure. Rebalance thresholds are configurable within <Const>5-20%</Const> deviation.
              Backtest maximum drawdown: approximately -5.7%.
            </div>
          </motion.div>

          <motion.div className={styles.riskCard}
            variants={fadeIn} initial="hidden" whileInView="visible" custom={1}
            viewport={{ once: true }}>
            <div className={styles.riskHeader}>
              <SeverityBadge level="high" />
              <span className={styles.riskTitle}>Liquidation risk</span>
            </div>
            <div className={styles.riskDesc}>
              If LTV exceeds Dolomite's liquidation threshold (~83.8%), the position gets liquidated.
              Basalt enforces a hard cap at <Const>MAX_SAFE_LTV = 70%</Const> and
              targets <Const>50% LTV</Const> (configurable <Const>48-52%</Const>).
              A 30%+ instantaneous BTC crash without rebalance could breach the cap.
            </div>
          </motion.div>

          <motion.div className={styles.riskCard}
            variants={fadeIn} initial="hidden" whileInView="visible" custom={2}
            viewport={{ once: true }}>
            <div className={styles.riskHeader}>
              <SeverityBadge level="medium" />
              <span className={styles.riskTitle}>GM token depegging</span>
            </div>
            <div className={styles.riskDesc}>
              GM tokens represent LP positions in GMX v2 pools. If the underlying pool becomes imbalanced
              (e.g., large trader losses), GM token value could deviate from its theoretical NAV.
              The ZapIn contract checks pool imbalance within <Const>0.1-2%</Const> bounds.
            </div>
          </motion.div>

          <motion.div className={styles.riskCard}
            variants={fadeIn} initial="hidden" whileInView="visible" custom={3}
            viewport={{ once: true }}>
            <div className={styles.riskHeader}>
              <SeverityBadge level="medium" />
              <span className={styles.riskTitle}>Slippage during async settlement</span>
            </div>
            <div className={styles.riskDesc}>
              GMX wrap/unwrap operations settle asynchronously (~2s on Arbitrum). During this window,
              prices can move. Deposit slippage is capped at <Const>0.5-5%</Const>, manager
              per-rebalance slippage at <Const>0.5–10%</Const>, configurable vault cap <Const>1–10%</Const>.
              Emergency swaps use a <Const>30-min TWAP</Const> with <Const>1%</Const> slippage cap.
            </div>
          </motion.div>
        </div>
      </section>

      <hr className={styles.divider} />

      {/* ═══════ OPERATIONAL RISK ═══════ */}
      <section className={styles.section} id="operational">
        <h2 className={styles.sectionTitle}>Operational risk</h2>
        <p className={styles.body}>
          The protocol relies on off-chain keeper infrastructure for finalizing async operations
          and triggering rebalances.
        </p>

        <div className={styles.guardGrid}>
          {[
            {
              icon: '\u23F1',
              title: 'Keeper liveness',
              desc: `Keeper must finalize deposits, withdrawals, and rebalances within a configurable deadline (60s-60min, default 60s). If the keeper goes offline, the vault NFT owner or protocol manager can call finalization after the deadline expires.`,
            },
            {
              icon: '\u26A1',
              title: 'Deadman switch',
              desc: `If the protocol manager is inactive for ~2,628,000 blocks (~1 year on Arbitrum), the NFT owner can trigger the deadman switch and gain full manager privileges over their vault.`,
            },
            {
              icon: '\u26D4',
              title: 'Async recovery',
              desc: `If an async operation (GMX wrap/unwrap) gets stuck past the deadline + grace period, the vault NFT owner or protocol manager can cancel and recover via AsyncRecoveryHandler. Prevents permanent fund lockup.`,
            },
          ].map((g, i) => (
            <motion.div key={g.title} className={styles.guardCard}
              initial={{ opacity: 0 }}
              whileInView={{ opacity: 1 }}
              viewport={{ once: true }}
              transition={{ delay: i * 0.03, duration: 0.2, ease: 'easeOut' }}>
              <span className={styles.guardIcon}>{g.icon}</span>
              <div className={styles.guardTitle}>{g.title}</div>
              <div className={styles.guardDesc}>{g.desc}</div>
            </motion.div>
          ))}
        </div>

        <p className={styles.body}>
          <strong>Key management.</strong> The ManagerContract separates six roles:
          <span className={styles.highlight}> owner</span>,
          <span className={styles.highlight}> configurator</span>,
          <span className={styles.highlight}> operational</span> (keeper),
          <span className={styles.highlight}> handlerProposer</span>, and
          <span className={styles.highlight}> addressProposer</span>, and
          <span className={styles.highlight}> feeCollector</span> (controls fee sweep destination, two-step transfer).
          Compromise of the operational key allows rebalances and finalizations but cannot withdraw user
          funds, change handlers, or modify safety parameters. The configurator can only adjust parameters
          within hardcoded bounds (e.g., target LTV 48-52%).
        </p>
      </section>

      <hr className={styles.divider} />

      {/* ═══════ POSITION ISOLATION ═══════ */}
      <section className={styles.section} id="isolation">
        <h2 className={styles.sectionTitle}>Position isolation</h2>
        <p className={styles.body}>
          Each vault is a separate <span className={styles.highlight}>VaultCore + VaultState</span> contract pair
          with its own Dolomite isolation account (#100). This is the strongest isolation model in DeFi:
        </p>

        <ul className={styles.list}>
          <li>
            <strong>No shared pools.</strong> Funds are never commingled. Each vault holds its own
            GM tokens, borrows its own USDC, and has its own state machines.
          </li>
          <li>
            <strong>No cross-vault contagion.</strong> A bug exploited in Vault #1 does not affect
            Vault #2. There is no shared storage, no shared collateral, no shared debt.
          </li>
          <li>
            <strong>NFT ownership.</strong> Only the ERC-721 holder can deposit, withdraw, or
            accept handler upgrades for their vault. The protocol manager cannot move user funds.
          </li>
          <li>
            <strong>State machine guards.</strong> Three independent state machines (deposit, withdraw,
            rebalance) must all be IDLE before any new operation. A <Const>1-block cooldown</Const> prevents
            same-block reentrancy.
          </li>
        </ul>
      </section>

      <hr className={styles.divider} />

      {/* ═══════ MITIGATION SUMMARY TABLE ═══════ */}
      <section className={styles.section} id="summary">
        <h2 className={styles.sectionTitle}>Risk &amp; mitigation summary</h2>
        <table className={styles.summaryTable}>
          <thead>
            <tr>
              <th>Risk</th>
              <th>What can go wrong</th>
              <th>How we mitigate</th>
              <th>Residual</th>
            </tr>
          </thead>
          <tbody>
            {([
              ['Core contract bug', 'Funds at risk, can\'t patch immutable code', 'Minimal core (~270 LOC), Halmos symbolic testing, no proxy patterns', 'Medium'],
              ['Handler vulnerability', 'Funds at risk via malicious handler', 'Swappable via propose+accept, NFT owner must consent, old handler immutable', 'Low'],
              ['GMX v2 failure', 'GM token value drops to zero, collateral lost', 'Emergency unwind with 30-min TWAP, chunked withdrawal (1% per chunk)', 'Critical'],
              ['Dolomite insolvency', 'Borrowed USDC lost, position unrecoverable', 'Per-vault isolation accounts (#100), no cross-vault contagion', 'Critical'],
              ['Oracle manipulation', 'Wrong LTV calculation, incorrect liquidation', 'Staleness check (25h), price ceilings, Chainlink-vs-Dolomite spread guard (0.25%)', 'Low'],
              ['Sequencer downtime', 'Operations blocked, positions exposed to market', '1h grace period after restart, all operations blocked until oracles stabilize', 'Medium'],
              ['BTC crash >30%', 'LTV breaches liquidation threshold (~83.8%)', 'MAX_SAFE_LTV 70%, target 50%, keeper rebalances, owner can rebalance above 70%', 'High'],
              ['Keeper offline', 'Async operations stuck, no rebalances', 'NFT owner or manager can finalize after deadline, deadman switch after ~1 year', 'Medium'],
              ['Async operation stuck', 'Funds locked in pending GMX operation', 'NFT owner or manager cancels via AsyncRecoveryHandler after deadline + grace', 'Low'],
              ['Manager key compromise', 'Malicious rebalances, parameter changes', 'Cannot withdraw funds, role separation (6 roles), 80% vote to replace manager', 'Medium'],
            ] as [string, string, string, string][]).map(([risk, impact, mitigation, residual]) => (
              <tr key={risk}>
                <td>{risk}</td>
                <td>{impact}</td>
                <td>{mitigation}</td>
                <td style={{
                  color: residual === 'Critical' ? '#e55'
                    : residual === 'High' ? 'var(--ember-500)'
                    : residual === 'Medium' ? 'var(--sulfur-500)'
                    : 'var(--mineral-500)'
                }}>{residual}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>

      <BackToTop />
    </article>
  );
}
