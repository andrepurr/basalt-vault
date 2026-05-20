import { motion } from 'motion/react';
import styles from './Schematics.module.css';

const draw = {
  hidden: { pathLength: 0, opacity: 0 },
  visible: { pathLength: 1, opacity: 1, transition: { duration: 1.5, ease: 'easeInOut' } },
};

function SettleFlow() {
  const steps = ['Deposit', 'Wrap GM', 'Wait Keeper', 'Finalize', 'Position Open'];
  return (
    <div className={styles.diagram}>
      <div className={styles.diagramLabel}>Settlement flow</div>
      <svg viewBox="0 0 860 80" className={styles.flowSvg}>
        {steps.map((label, i) => {
          const x = 40 + i * 180;
          return (
            <g key={label}>
              <motion.rect
                x={x - 35} y={20} width={100} height={40} rx={4}
                fill="none" stroke="var(--border-default)" strokeWidth={1.5}
                initial={{ opacity: 0, scale: 0.8 }}
                whileInView={{ opacity: 1, scale: 1 }}
                viewport={{ once: true }}
                transition={{ delay: i * 0.15, duration: 0.4 }}
              />
              <motion.text
                x={x + 15} y={45} textAnchor="middle"
                fill="var(--fg-muted)" fontSize={11} fontFamily="var(--font-mono)"
                initial={{ opacity: 0 }}
                whileInView={{ opacity: 1 }}
                viewport={{ once: true }}
                transition={{ delay: i * 0.15 + 0.2 }}
              >
                {label}
              </motion.text>
              {i < steps.length - 1 && (
                <motion.line
                  x1={x + 65} y1={40} x2={x + 145} y2={40}
                  stroke="var(--ember-500)" strokeWidth={1.5}
                  variants={draw} initial="hidden" whileInView="visible"
                  viewport={{ once: true }}
                  transition={{ delay: i * 0.15 + 0.3, duration: 0.6 }}
                  markerEnd="url(#arrowhead)"
                />
              )}
            </g>
          );
        })}
        <defs>
          <marker id="arrowhead" markerWidth="8" markerHeight="6" refX="7" refY="3" orient="auto">
            <path d="M0,0 L8,3 L0,6" fill="var(--ember-500)" />
          </marker>
        </defs>
      </svg>
    </div>
  );
}

function HealthCurve() {
  return (
    <div className={styles.diagram}>
      <div className={styles.diagramLabel}>LTV health zones</div>
      <svg viewBox="0 0 400 220" className={styles.curveSvg}>
        {/* Safe zone: 0-70% */}
        <rect x={40} y={94} width={320} height={86} fill="rgba(100, 200, 130, 0.06)" rx={2} />
        <text x={50} y={155} fill="var(--mineral-500)" fontSize={10} fontFamily="var(--font-mono)" opacity={0.7}>SAFE 0–70%</text>

        {/* Owner rebalance zone: 70-80% */}
        <rect x={40} y={54} width={320} height={40} fill="rgba(200, 180, 60, 0.06)" rx={2} />
        <text x={50} y={78} fill="var(--sulfur-500)" fontSize={10} fontFamily="var(--font-mono)" opacity={0.7}>OWNER CAN REBALANCE 70%+</text>

        {/* Liquidation zone: 83%+ */}
        <rect x={40} y={20} width={320} height={34} fill="rgba(200, 60, 60, 0.06)" rx={2} />
        <text x={50} y={42} fill="var(--magma-500)" fontSize={10} fontFamily="var(--font-mono)" opacity={0.7}>LIQUIDATION 83%+</text>

        {/* Target line at 50% */}
        <motion.line
          x1={40} y1={134} x2={360} y2={134}
          stroke="var(--ember-500)" strokeWidth={1} strokeDasharray="4 4"
          variants={draw} initial="hidden" whileInView="visible" viewport={{ once: true }}
        />
        <text x={365} y={138} fill="var(--ember-500)" fontSize={9} fontFamily="var(--font-mono)">Target 50%</text>

        {/* Hard cap line at 70% */}
        <motion.line
          x1={40} y1={94} x2={360} y2={94}
          stroke="var(--sulfur-500)" strokeWidth={1} strokeDasharray="4 4"
          variants={draw} initial="hidden" whileInView="visible" viewport={{ once: true }}
          transition={{ delay: 0.3 }}
        />
        <text x={365} y={98} fill="var(--sulfur-500)" fontSize={9} fontFamily="var(--font-mono)">Cap 70%</text>

        {/* Liquidation line at 83% */}
        <motion.line
          x1={40} y1={54} x2={360} y2={54}
          stroke="var(--magma-500)" strokeWidth={1} strokeDasharray="4 4"
          variants={draw} initial="hidden" whileInView="visible" viewport={{ once: true }}
          transition={{ delay: 0.5 }}
        />
        <text x={365} y={58} fill="var(--magma-500)" fontSize={9} fontFamily="var(--font-mono)">Liq 83%</text>

        {/* Current position dot at target */}
        <motion.circle
          cx={200} cy={134} r={6}
          fill="var(--ember-500)"
          initial={{ scale: 0 }}
          whileInView={{ scale: 1 }}
          viewport={{ once: true }}
          transition={{ delay: 0.8, type: 'spring', stiffness: 200 }}
        />
        <motion.circle
          cx={200} cy={134} r={6}
          fill="none" stroke="var(--ember-500)" strokeWidth={2}
          initial={{ scale: 0, opacity: 1 }}
          whileInView={{ scale: 3, opacity: 0 }}
          viewport={{ once: true }}
          transition={{ delay: 0.8, duration: 1.5, repeat: Infinity }}
        />
        <text x={210} y={130} fill="var(--fg-default)" fontSize={10} fontFamily="var(--font-mono)">Target 50%</text>

        {/* Deadman switch note */}
        <text x={40} y={210} fill="var(--fg-faint)" fontSize={9} fontFamily="var(--font-mono)" opacity={0.6}>
          Deadman switch: if manager inactive ~1 year, NFT owner becomes full manager
        </text>
      </svg>
    </div>
  );
}

function KeeperLifecycle() {
  const states = [
    { label: 'IDLE', cx: 60, cy: 50 },
    { label: 'PENDING', cx: 180, cy: 50 },
    { label: 'SETTLING', cx: 180, cy: 140 },
    { label: 'DONE', cx: 60, cy: 140 },
  ];
  return (
    <div className={styles.diagram}>
      <div className={styles.diagramLabel}>Keeper state machine</div>
      <svg viewBox="0 0 240 190" className={styles.keeperSvg}>
        {states.map((s, i) => (
          <g key={s.label}>
            <motion.circle
              cx={s.cx} cy={s.cy} r={28}
              fill={i === 0 ? 'rgba(255,106,61,0.1)' : 'none'}
              stroke={i === 0 ? 'var(--ember-500)' : 'var(--border-default)'}
              strokeWidth={1.5}
              initial={{ scale: 0 }}
              whileInView={{ scale: 1 }}
              viewport={{ once: true }}
              transition={{ delay: i * 0.15 }}
            />
            <motion.text
              x={s.cx} y={s.cy + 4} textAnchor="middle"
              fill={i === 0 ? 'var(--ember-500)' : 'var(--fg-muted)'}
              fontSize={9} fontFamily="var(--font-mono)"
              initial={{ opacity: 0 }}
              whileInView={{ opacity: 1 }}
              viewport={{ once: true }}
              transition={{ delay: i * 0.15 + 0.1 }}
            >
              {s.label}
            </motion.text>
          </g>
        ))}
        {/* Arrows: IDLE→PENDING→SETTLING→DONE→IDLE */}
        {[
          { x1: 88, y1: 50, x2: 152, y2: 50 },
          { x1: 180, y1: 78, x2: 180, y2: 112 },
          { x1: 152, y1: 140, x2: 88, y2: 140 },
          { x1: 60, y1: 112, x2: 60, y2: 78 },
        ].map((l, i) => (
          <motion.line
            key={i} {...l}
            stroke="var(--border-default)" strokeWidth={1}
            markerEnd="url(#arrowhead)"
            variants={draw} initial="hidden" whileInView="visible"
            viewport={{ once: true }}
            transition={{ delay: i * 0.2 + 0.4, duration: 0.5 }}
          />
        ))}
      </svg>
    </div>
  );
}

export function Schematics() {
  return (
    <section className={styles.section}>
      <motion.div
        className={styles.head}
        initial={{ opacity: 0, y: 20 }}
        whileInView={{ opacity: 1, y: 0 }}
        viewport={{ once: true, margin: '-60px' }}
        transition={{ duration: 0.5, ease: [0.2, 0.8, 0.2, 1] }}
      >
        <div className={styles.eyebrow}>Technical schematics</div>
        <h2 className={styles.title}>Under the hood.</h2>
      </motion.div>

      <div className={styles.topRow}>
        <SettleFlow />
      </div>
      <div className={styles.bottomRow}>
        <HealthCurve />
        <KeeperLifecycle />
      </div>
    </section>
  );
}
