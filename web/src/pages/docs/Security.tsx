import { motion } from 'motion/react';
import { useState, useEffect } from 'react';
import styles from './Security.module.css';

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

/** State guard diagram — all-idle + cooldown check */
function StateGuardDiagram() {
  const machines = ['Deposit', 'Withdraw', 'Rebalance'];
  const colors = ['var(--mineral-500)', 'var(--sulfur-500)', 'var(--ember-500)'];

  return (
    <svg viewBox="0 0 620 190" className={styles.svg}>
      <defs>
        <marker id="sg-arr" markerWidth="6" markerHeight="5" refX="5" refY="2.5" orient="auto">
          <path d="M0,0 L6,2.5 L0,5" fill="var(--ember-500)" />
        </marker>
      </defs>
      {/* Three state machines */}
      {machines.map((m, i) => {
        const y = 25 + i * 55;
        return (
          <motion.g key={m}
            variants={fadeIn} initial="hidden" whileInView="visible" custom={i}
            viewport={{ once: true }}>
            <rect x={20} y={y} width={120} height={34} rx={17}
              fill="none" stroke={colors[i]} strokeWidth={1.5} />
            <text x={80} y={y + 20} textAnchor="middle" fontSize={11}
              fontFamily="var(--font-mono)" fontWeight={600} fill={colors[i]}>
              {m}: IDLE
            </text>
          </motion.g>
        );
      })}

      {/* AND gate */}
      <motion.g variants={fadeIn} initial="hidden" whileInView="visible" custom={3} viewport={{ once: true }}>
        {machines.map((_, i) => (
          <motion.line key={i} x1={140} y1={42 + i * 55} x2={220} y2={95}
            stroke="var(--border-default)" strokeWidth={1}
            variants={draw} initial="hidden" whileInView="visible" custom={i}
            viewport={{ once: true }} />
        ))}
        <rect x={220} y={77} width={70} height={38} rx={4}
          fill="var(--bg-raised)" stroke="var(--fg-default)" strokeWidth={1.5} />
        <text x={255} y={100} textAnchor="middle" fontSize={12}
          fontFamily="var(--font-mono)" fontWeight={700} fill="var(--fg-default)">AND</text>
      </motion.g>

      {/* Cooldown check */}
      <motion.g variants={fadeIn} initial="hidden" whileInView="visible" custom={4} viewport={{ once: true }}>
        <motion.line x1={290} y1={96} x2={360} y2={96}
          stroke="var(--border-default)" strokeWidth={1} markerEnd="url(#sg-arr)"
          variants={draw} initial="hidden" whileInView="visible" custom={4}
          viewport={{ once: true }} />
        <rect x={365} y={77} width={100} height={38} rx={4}
          fill="var(--bg-raised)" stroke="var(--sulfur-500)" strokeWidth={1} />
        <text x={415} y={92} textAnchor="middle" fontSize={11}
          fontFamily="var(--font-mono)" fill="var(--sulfur-500)">Cooldown</text>
        <text x={415} y={106} textAnchor="middle" fontSize={9}
          fontFamily="var(--font-mono)" fill="var(--fg-faint)">1 block</text>
      </motion.g>

      {/* OK to proceed */}
      <motion.g variants={fadeIn} initial="hidden" whileInView="visible" custom={5} viewport={{ once: true }}>
        <motion.line x1={465} y1={96} x2={515} y2={96}
          stroke="var(--ember-500)" strokeWidth={1.5} markerEnd="url(#sg-arr)"
          variants={draw} initial="hidden" whileInView="visible" custom={5}
          viewport={{ once: true }} />
        <rect x={520} y={77} width={80} height={38} rx={4}
          fill="rgba(255,106,61,0.08)" stroke="var(--ember-500)" strokeWidth={1.5} />
        <text x={560} y={100} textAnchor="middle" fontSize={12}
          fontFamily="var(--font-mono)" fontWeight={700} fill="var(--ember-500)">ALLOW</text>
      </motion.g>
    </svg>
  );
}

/** Isolation security model diagram */
function IsolationSecurityDiagram() {
  return (
    <svg viewBox="0 0 580 155" className={styles.svg}>
      {/* Attacker */}
      <motion.g variants={fadeIn} initial="hidden" whileInView="visible" custom={0} viewport={{ once: true }}>
        <rect x={10} y={52} width={100} height={40} rx={4}
          fill="rgba(200,60,60,0.06)" stroke="var(--magma-500, #e55)" strokeWidth={1} />
        <text x={60} y={76} textAnchor="middle" fontSize={11}
          fontFamily="var(--font-mono)" fill="var(--magma-500, #e55)">Attacker</text>
      </motion.g>

      {/* Cross = blocked */}
      <motion.g variants={fadeIn} initial="hidden" whileInView="visible" custom={1} viewport={{ once: true }}>
        <motion.line x1={115} y1={72} x2={190} y2={72}
          stroke="var(--magma-500, #e55)" strokeWidth={1.5} strokeDasharray="4 4"
          variants={draw} initial="hidden" whileInView="visible" custom={1}
          viewport={{ once: true }} />
        <text x={152} y={63} textAnchor="middle" fontSize={16} fill="var(--magma-500, #e55)" fontWeight={700}>&times;</text>
      </motion.g>

      {/* Vault A */}
      <motion.g variants={fadeIn} initial="hidden" whileInView="visible" custom={2} viewport={{ once: true }}>
        <rect x={200} y={10} width={140} height={55} rx={6}
          fill="var(--bg-raised)" stroke="var(--mineral-500)" strokeWidth={1} />
        <text x={270} y={32} textAnchor="middle" fontSize={12}
          fontFamily="var(--font-mono)" fontWeight={600} fill="var(--mineral-500)">Vault #1</text>
        <text x={270} y={48} textAnchor="middle" fontSize={9}
          fontFamily="var(--font-mono)" fill="var(--fg-faint)">Owner: 0xABC...</text>
      </motion.g>

      {/* Vault B */}
      <motion.g variants={fadeIn} initial="hidden" whileInView="visible" custom={3} viewport={{ once: true }}>
        <rect x={200} y={80} width={140} height={55} rx={6}
          fill="var(--bg-raised)" stroke="var(--ember-500)" strokeWidth={1} />
        <text x={270} y={102} textAnchor="middle" fontSize={12}
          fontFamily="var(--font-mono)" fontWeight={600} fill="var(--ember-500)">Vault #2</text>
        <text x={270} y={118} textAnchor="middle" fontSize={9}
          fontFamily="var(--font-mono)" fill="var(--fg-faint)">Owner: 0xDEF...</text>
      </motion.g>

      {/* No shared state */}
      <motion.g variants={fadeIn} initial="hidden" whileInView="visible" custom={4} viewport={{ once: true }}>
        <line x1={270} y1={65} x2={270} y2={80} stroke="var(--border-faint)" strokeWidth={1} strokeDasharray="2 3" />
        <text x={395} y={74} fontSize={11} fontFamily="var(--font-mono)" fill="var(--fg-faint)">
          no shared state
        </text>
      </motion.g>

      {/* NFT = only key */}
      <motion.g variants={fadeIn} initial="hidden" whileInView="visible" custom={5} viewport={{ once: true }}>
        <rect x={450} y={20} width={110} height={34} rx={17}
          fill="rgba(255,106,61,0.08)" stroke="var(--ember-500)" strokeWidth={1} />
        <text x={505} y={41} textAnchor="middle" fontSize={11}
          fontFamily="var(--font-mono)" fontWeight={600} fill="var(--ember-500)">NFT = key</text>

        <rect x={450} y={90} width={110} height={34} rx={17}
          fill="rgba(100,200,130,0.08)" stroke="var(--mineral-500)" strokeWidth={1} />
        <text x={505} y={111} textAnchor="middle" fontSize={11}
          fontFamily="var(--font-mono)" fontWeight={600} fill="var(--mineral-500)">NFT = key</text>
      </motion.g>
    </svg>
  );
}

const tocItems = [
  { id: 'isolation', label: 'Isolation' },
  { id: 'state-guards', label: 'State guards' },
  { id: 'access', label: 'Access control' },
  { id: 'immutability', label: 'Immutability' },
  { id: 'risks', label: 'Risk factors' },
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

export function Security() {
  return (
    <article className={styles.page}>
      <h1 className={styles.pageTitle}>Security Model</h1>

      <nav className={styles.toc} aria-label="Table of contents">
        {tocItems.map((item) => (
          <a key={item.id} href={`#${item.id}`} className={styles.tocLink}>{item.label}</a>
        ))}
      </nav>

      <p className={styles.subtitle}>
        Basalt is designed around <span className={styles.highlight}>isolation</span>, <span className={styles.highlight}>immutability</span>, and <span className={styles.highlight}>minimal trust</span>. No admin keys
        over user funds. No shared pools. No upgradeability on handler contracts.
      </p>

      <section className={styles.section} id="isolation">
        <h2 className={styles.sectionTitle}>Vault isolation</h2>
        <p className={styles.body}>
          Each vault is a separate <span className={styles.highlight}>VaultCore + VaultState</span> clone with its own Dolomite
          <span className={styles.highlight}>isolation account</span> (#100). One vault cannot access another vault's state or funds.
          Compromise of one vault does not affect others.
        </p>
        <div className={styles.diagramWrap}>
          <IsolationSecurityDiagram />
        </div>
        <div className={styles.guardGrid}>
          {[
            { icon: '\u26E8', title: 'Per-vault state', desc: 'Each vault has isolated storage — VaultState is a separate contract' },
            { icon: '\u2702', title: 'No shared pools', desc: 'Funds never commingled. Each position is independently managed.' },
            { icon: '\u26BF', title: 'NFT ownership', desc: 'Only the ERC-721 holder can deposit, withdraw, or accept upgrades.' },
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
      </section>

      <hr className={styles.divider} />

      <section className={styles.section} id="state-guards">
        <h2 className={styles.sectionTitle}>State machine guards</h2>
        <p className={styles.body}>
          Three independent <span className={styles.highlight}>state machines</span> (deposit, withdraw, rebalance) protect against
          concurrent operations. All three must be <span className={styles.highlight}>IDLE</span> before any new operation can start.
          A <span className={styles.highlight}>1-block cooldown</span> is armed after each deposit finalization.
        </p>
        <div className={styles.diagramWrap}>
          <StateGuardDiagram />
        </div>
      </section>

      <hr className={styles.divider} />

      <section className={styles.section} id="access">
        <h2 className={styles.sectionTitle}>Access control matrix</h2>
        <p className={styles.body}>
          Two roles interact with vaults: <span className={styles.highlight}>NFT owner</span> and <span className={styles.highlight}>protocol manager</span>. Their permissions
          are strictly separated.
        </p>
        <table className={styles.matrixTable}>
          <thead>
            <tr>
              <th>Action</th>
              <th>NFT Owner</th>
              <th>Manager</th>
              <th>Anyone</th>
            </tr>
          </thead>
          <tbody>
            {[
              ['Deposit', true, false, false],
              ['Withdraw', true, false, false],
              ['Finalize deposit', true, true, false],
              ['Finalize withdraw', true, true, false],
              ['Rebalance (past threshold)', true, true, false],
              ['Finalize rebalance', true, true, false],
              ['Set target LTV', false, true, false],
              ['Accrue fees', false, true, false],
              ['Accept upgrade', true, false, false],
              ['Unstuck (after grace)', true, true, false],
            ].map(([action, owner, manager, anyone]) => (
              <tr key={action as string}>
                <td>{action}</td>
                <td className={owner ? styles.check : styles.cross}>{owner ? '\u2713' : '\u2014'}</td>
                <td className={manager ? styles.check : styles.cross}>{manager ? '\u2713' : '\u2014'}</td>
                <td className={anyone ? styles.check : styles.cross}>{anyone ? '\u2713' : '\u2014'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>

      <hr className={styles.divider} />

      <section className={styles.section} id="immutability">
        <h2 className={styles.sectionTitle}>Immutability</h2>
        <p className={styles.body}>
          All handler contracts are <span className={styles.highlight}>immutable</span> — deployed once, never upgraded. The ManagerContract,
          NftFactory, and FeeSplitter are also immutable singletons. This eliminates the risk of
          malicious upgrades but means bugs cannot be patched post-deployment.
        </p>
        <p className={styles.body}>
          Handler upgrades are <span className={styles.highlight}>opt-in</span> per vault: the protocol proposes a new handler, and the
          NFT owner must explicitly accept it. No forced upgrades.
        </p>
        <div className={styles.guardGrid}>
          {[
            { icon: '\u2693', title: 'No proxy patterns', desc: 'Handlers are plain contracts — no delegatecall, no storage collisions' },
            { icon: '\u2611', title: 'Opt-in upgrades', desc: 'Owner must accept new handlers. Protocol cannot force upgrades.' },
            { icon: '\u26A0', title: 'Cannot patch bugs', desc: 'Trade-off of immutability: bugs are permanent. Code is the final word.' },
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
      </section>

      <hr className={styles.divider} />

      <section className={styles.section} id="risks">
        <h2 className={styles.sectionTitle}>Risk factors</h2>
        <ul className={styles.list}>
          <li><strong>Smart contract risk.</strong> Immutable contracts — bugs cannot be patched. Audit status: unaudited.</li>
          <li><strong>Residual BTC delta.</strong> Not fully delta-neutral. Backtest max drawdown: -5.7%.</li>
          <li><strong>Protocol dependency.</strong> Relies on GMX v2, Dolomite, Uniswap V3 solvency and correct operation.</li>
          <li><strong>Oracle risk.</strong> Chainlink feed staleness or manipulation could affect fee estimation and position health.</li>
          <li><strong>Async settlement risk.</strong> GMX wrap/unwrap takes ~2s. Extreme volatility during settlement window could cause unexpected outcomes.</li>
          <li><strong>Liquidation risk.</strong> If LTV exceeds Dolomite's liquidation threshold (~83.8%), the position gets liquidated. The vault targets 50% LTV with a hard cap at 70%.</li>
          <li><strong>Manager risk.</strong> Protocol manager can trigger rebalances and propose handler upgrades. Cannot withdraw user funds. Above 70% LTV, the NFT owner can rebalance directly. Deadman switch (~1 year inactivity) transfers full control to the owner.</li>
        </ul>
      </section>

      <BackToTop />
    </article>
  );
}
