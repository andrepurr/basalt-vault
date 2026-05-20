import { useRef, useState, useCallback, useEffect, useId } from 'react';
import { motion, useInView } from 'motion/react';
import { useReducedMotion } from '../../hooks/useReducedMotion';
import rawData from '../../lib/chartData.json';
import styles from './StrategyChart.module.css';

type Point = { d: string; basalt: number; gm: number; btc: number; fifty: number };
const { points, maxDdPct, apy, finalNav } = rawData as {
  points: Point[];
  rebalanceDays: number[];
  maxDdDay: number;
  maxDdPct: number;
  apy: number;
  rebalanceCount: number;
  finalNav: number;
};

const SERIES = [
  { key: 'basalt' as const, label: 'Basalt', color: '#ff6a3d', main: true },
  { key: 'gm' as const, label: 'GM', color: '#64c882', main: false },
  { key: 'fifty' as const, label: '50/50', color: '#a78bfa', main: false },
  { key: 'btc' as const, label: 'BTC', color: '#f7931a', main: false },
];

const DRAW_MS = 2500;
const W = 900, H = 400;
const P = { t: 8, r: 80, b: 8, l: 8 }; // right padding for race labels
const pW = W - P.l - P.r, pH = H - P.t - P.b;

function bounds() {
  let min = Infinity, max = -Infinity;
  for (const p of points)
    for (const s of SERIES) {
      if (p[s.key] < min) min = p[s.key];
      if (p[s.key] > max) max = p[s.key];
    }
  return { min: min * 0.95, max: max * 1.04 };
}

function makePath(key: 'basalt' | 'gm' | 'btc' | 'fifty', gMin: number, gMax: number) {
  const r = gMax - gMin;
  return points.map((p, i) => {
    const x = P.l + (i / (points.length - 1)) * pW;
    const y = P.t + pH - ((p[key] - gMin) / r) * pH;
    return `${i === 0 ? 'M' : 'L'}${x.toFixed(1)},${y.toFixed(1)}`;
  }).join('');
}

/** Marquee in the same style as Stats section */
function Marquee({ children }: { children: React.ReactNode }) {
  const reduced = useReducedMotion();
  return (
    <div className={styles.marqueeTrack}>
      <motion.div
        className={styles.marqueeInner}
        animate={reduced ? {} : { x: ['-50%', '0%'] }}
        transition={{ duration: 50, ease: 'linear', repeat: Infinity }}
      >
        {children}
        {children}
      </motion.div>
    </div>
  );
}

export function StrategyChart() {
  const svgRef = useRef<SVGSVGElement>(null);
  const sectionRef = useRef<HTMLElement>(null);
  const isInView = useInView(sectionRef, { once: true, margin: '-120px' });
  const [hover, setHover] = useState<number | null>(null);
  const [raceIdx, setRaceIdx] = useState(0);
  const [drawDone, setDrawDone] = useState(false);
  const uid = useId();
  const bGradId = `bGrad-${uid}`;
  const aFillId = `aFill-${uid}`;
  const glowId = `glow-${uid}`;
  const { min: gMin, max: gMax } = bounds();
  const range = gMax - gMin;

  const paths = Object.fromEntries(
    SERIES.map((s) => [s.key, makePath(s.key, gMin, gMax)])
  ) as Record<string, string>;

  // Race animation — rAF-driven so labels track line tip exactly (no setInterval drift)
  useEffect(() => {
    if (!isInView) return;
    setRaceIdx(0);
    setDrawDone(false);
    const LINE_DELAY_MS = 150; // must match Basalt path transition delay
    let raf: number;
    let start: number | null = null;

    const tick = (now: number) => {
      if (!start) start = now;
      const elapsed = now - start - LINE_DELAY_MS;
      if (elapsed < 0) { raf = requestAnimationFrame(tick); return; }
      const progress = Math.min(elapsed / DRAW_MS, 1);
      setRaceIdx(Math.min(Math.floor(progress * points.length), points.length - 1));
      if (progress < 1) {
        raf = requestAnimationFrame(tick);
      } else {
        setTimeout(() => setDrawDone(true), 300);
      }
    };

    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [isInView]);

  const racePoint = points[raceIdx];
  const liveReturn = ((racePoint.basalt / 10000 - 1) * 100);
  const lastPt = points[points.length - 1];

  const onMove = useCallback((e: React.MouseEvent<SVGSVGElement>) => {
    if (!drawDone) return;
    const rect = svgRef.current!.getBoundingClientRect();
    const mx = ((e.clientX - rect.left) / rect.width) * W;
    setHover(Math.max(0, Math.min(points.length - 1,
      Math.round(((mx - P.l) / pW) * (points.length - 1)))));
  }, [drawDone]);

  const hx = hover !== null ? P.l + (hover / (points.length - 1)) * pW : 0;
  const hp = hover !== null ? points[hover] : null;

  // Race label positions
  const raceX = P.l + (raceIdx / (points.length - 1)) * pW;

  return (
    <section ref={sectionRef} className={styles.section}>
      {/* Header — live % */}
      <motion.div
        className={styles.head}
        initial={{ opacity: 0, y: 24 }}
        whileInView={{ opacity: 1, y: 0 }}
        viewport={{ once: true, margin: '-60px' }}
        transition={{ duration: 0.6, ease: [0.16, 1, 0.3, 1] }}
      >
        <div className={styles.eyebrow}>2-year backtest</div>
        <h2 className={styles.title}>
          <span className={styles.accent} key={raceIdx}>
            {liveReturn >= 0 ? '+' : ''}{liveReturn.toFixed(1)}%
          </span>
          {' '}vs holding.
        </h2>
      </motion.div>

      {/* Chart */}
      <div className={styles.chartArea}>
        <svg ref={svgRef} viewBox={`0 0 ${W} ${H}`} className={styles.svg}
          role="img" aria-label="2-year backtest chart comparing Basalt, GM, 50/50, and BTC returns"
          onMouseMove={onMove} onMouseLeave={() => setHover(null)}>
          <defs>
            <linearGradient id={bGradId} x1="0%" y1="0%" x2="100%" y2="0%">
              <stop offset="0%" stopColor="#ff4500">
                <animate attributeName="stop-color" values="#ff4500;#ff6a3d;#ff8c00;#ff6a3d;#ff4500" dur="4s" repeatCount="indefinite" />
              </stop>
              <stop offset="100%" stopColor="#ff8c00">
                <animate attributeName="stop-color" values="#ff8c00;#ff4500;#ff6a3d;#ff4500;#ff8c00" dur="4s" repeatCount="indefinite" />
              </stop>
            </linearGradient>
            <linearGradient id={aFillId} x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#ff6a3d" stopOpacity={0.15} />
              <stop offset="100%" stopColor="#ff6a3d" stopOpacity={0} />
            </linearGradient>
            <filter id={glowId}><feGaussianBlur stdDeviation="5" result="b" /><feMerge><feMergeNode in="b" /><feMergeNode in="SourceGraphic" /></feMerge></filter>
          </defs>

          {/* Area fill */}
          <motion.path
            d={paths.basalt + `L${P.l + pW},${P.t + pH}L${P.l},${P.t + pH}Z`}
            fill={`url(#${aFillId})`}
            initial={{ opacity: 0 }}
            animate={isInView ? { opacity: 1 } : {}}
            transition={{ duration: 1.5, delay: 0.15 }}
          />

          {/* Secondary lines */}
          {SERIES.filter(s => !s.main).map((s, idx) => (
            <motion.path key={s.key} d={paths[s.key]} fill="none"
              stroke={s.color} strokeWidth={1.2} opacity={0.35}
              initial={{ pathLength: 0 }}
              animate={isInView ? { pathLength: 1 } : {}}
              transition={{ duration: DRAW_MS / 1000, delay: 0.15, ease: 'linear' }}
            />
          ))}

          {/* Basalt glow */}
          <motion.path d={paths.basalt} fill="none"
            stroke="#ff6a3d" strokeWidth={8} opacity={0.12} filter={`url(#${glowId})`}
            initial={{ pathLength: 0 }}
            animate={isInView ? { pathLength: 1 } : {}}
            transition={{ duration: DRAW_MS / 1000, delay: 0.15, ease: 'linear' }}
          />
          {/* Basalt line */}
          <motion.path d={paths.basalt} fill="none"
            stroke={`url(#${bGradId})`} strokeWidth={2.5} strokeLinecap="round"
            initial={{ pathLength: 0 }}
            animate={isInView ? { pathLength: 1 } : {}}
            transition={{ duration: DRAW_MS / 1000, delay: 0.15, ease: 'linear' }}
          />

          {/* $10k baseline + label */}
          {(() => {
            const baseY = P.t + pH - ((10000 - gMin) / range) * pH;
            return <g>
              <line x1={P.l} y1={baseY} x2={P.l + pW} y2={baseY}
                stroke="var(--fg-faint)" strokeWidth={0.5} strokeDasharray="6 4" opacity={0.25} />
              <text x={P.l + 4} y={baseY - 6} fontSize={10}
                fontFamily="var(--font-mono)" fill="var(--fg-faint)" opacity={0.4}>$10k</text>
            </g>;
          })()}

          {/* Year markers */}
          {points.map((pt, i) => {
            if (pt.d.slice(5) !== '01-01') return null;
            const x = P.l + (i / (points.length - 1)) * pW;
            return <g key={pt.d}>
              <line x1={x} y1={P.t} x2={x} y2={P.t + pH}
                stroke="var(--fg-faint)" strokeWidth={0.5} strokeDasharray="4 6" opacity={0.2} />
              <text x={x} y={P.t + pH + 16} textAnchor="middle" fontSize={11}
                fontFamily="var(--font-mono)" fill="var(--fg-faint)" opacity={0.5}>{pt.d.slice(0, 4)}</text>
            </g>;
          })}

          {/* Race labels at tip — stacked vertically to avoid overlap */}
          {isInView && (() => {
            const pt = racePoint;
            // Sort by value to stack from top
            const sorted = SERIES.map(s => ({
              ...s,
              y: P.t + pH - ((pt[s.key] - gMin) / range) * pH,
              pct: (pt[s.key] / 10000 - 1) * 100,
            })).sort((a, b) => a.y - b.y); // top to bottom

            // Push apart if too close (min 18px gap)
            const minGap = 18;
            for (let i = 1; i < sorted.length; i++) {
              if (sorted[i].y - sorted[i - 1].y < minGap) {
                sorted[i].y = sorted[i - 1].y + minGap;
              }
            }

            return sorted.map((s) => (
              <text key={s.key} x={raceX + 8} y={s.y + 5}
                fontSize={s.main ? 15 : 12}
                fontFamily="var(--font-mono)"
                fontWeight={s.main ? 700 : 500}
                fill={s.color}
                opacity={s.main ? 1 : 0.6}
              >
                {s.pct >= 0 ? '+' : ''}{s.pct.toFixed(0)}%
              </text>
            ));
          })()}

          {/* Pulse at end */}
          {drawDone && (() => {
            const py = P.t + pH - ((lastPt.basalt - gMin) / range) * pH;
            return <>
              <circle cx={P.l + pW} cy={py} r={4} fill="#ff6a3d" />
              <motion.circle cx={P.l + pW} cy={py} r={4} fill="none"
                stroke="#ff6a3d" strokeWidth={1.5}
                animate={{ scale: [1, 4], opacity: [0.8, 0] }}
                transition={{ duration: 1.5, repeat: Infinity }}
              />
            </>;
          })()}

          {/* Hover */}
          {hover !== null && hp && drawDone && (
            <g>
              <line x1={hx} y1={0} x2={hx} y2={H}
                stroke="#ff6a3d" strokeWidth={0.5} opacity={0.25} />
              {SERIES.map((s) => {
                const y = P.t + pH - ((hp[s.key] - gMin) / range) * pH;
                return <circle key={s.key} cx={hx} cy={y} r={s.main ? 5 : 3}
                  fill={s.color} stroke="var(--bg-canvas)" strokeWidth={2} />;
              })}
            </g>
          )}
        </svg>

        {/* Tooltip */}
        {hover !== null && hp && drawDone && (
          <div className={styles.tooltip} style={{ left: `${(hx / W) * 100}%` }}>
            <div className={styles.ttDate}>{hp.d}</div>
            {SERIES.map((s) => (
              <div key={s.key} className={styles.ttRow}>
                <span className={styles.pillDot} style={{ background: s.color, width: 6, height: 6 }} />
                <span className={styles.ttName}>{s.label}</span>
                <span style={{ color: s.color, fontWeight: 700 }}>${hp[s.key].toLocaleString()}</span>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Marquee tape — same style as Stats */}
      <Marquee>
        <div className={styles.ticker}>
          <span className={styles.tickerItem}>
            <span className={styles.tickerLabel}>Backtest APY</span>
            <span className={styles.tickerValue}>{apy.toFixed(2)}%</span>
          </span>
          <span className={styles.tickerItem}>
            <span className={styles.tickerLabel}>Max Drawdown</span>
            <span className={styles.tickerValueRed}>{maxDdPct.toFixed(2)}%</span>
          </span>
          <span className={styles.tickerItem}>
            <span className={styles.tickerLabel}>$10K becomes</span>
            <span className={styles.tickerValue}>${finalNav.toLocaleString()}</span>
          </span>
          <span className={styles.tickerItem}>
            <span className={styles.tickerLabel}>Backtest</span>
            <span className={styles.tickerValue}>2 years</span>
          </span>
        </div>
      </Marquee>

      <p className={styles.fine}>
        Past performance does not guarantee future results
      </p>
    </section>
  );
}
