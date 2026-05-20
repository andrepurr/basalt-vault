import { useId } from 'react';
import styles from './HealthCurve.module.css';

const yLabels = [
  { pct: '100%', top: '0%' },
  { pct: '70% cap', top: '30%' },
  { pct: '40%', top: '60%' },
  { pct: '0%', top: '100%' },
];

const xLabels = ['\u221240%', '\u221230%', '\u221220%', '\u221210%', 'spot', '+10%'];

export function HealthCurve() {
  const uid = useId();
  const gradId = `health-curve-grad-${uid}`;
  return (
    <div className={styles.stage}>
      <div className={styles.label}>Schematic &middot; 02</div>
      <div className={styles.title}>
        Health vs collateral price &mdash; where liquidation lives
      </div>

      <div className={styles.chartWrap}>
        <div className={styles.chart}>
          {yLabels.map((y) => (
            <span
              key={y.pct}
              className={styles.yLabel}
              style={{ top: y.top }}
            >
              {y.pct}
            </span>
          ))}

          <div className={styles.zoneLiq}>
            <span className={styles.zoneLiqLabel}>
              liquidation @ 70% LTV
            </span>
          </div>

          <svg
            className={styles.svg}
            viewBox="0 0 600 240"
            preserveAspectRatio="none"
          >
            <defs>
              <linearGradient id={gradId} x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor="var(--ember-500)" stopOpacity={0.5} />
                <stop offset="100%" stopColor="var(--ember-500)" stopOpacity={0} />
              </linearGradient>
            </defs>

            {/* Fill under curve */}
            <path
              className={styles.curveFill}
              fill={`url(#${gradId})`}
              d="M 600 240 L 600 168 C 480 172, 360 176, 280 184 C 200 192, 140 206, 80 218 C 50 224, 20 232, 0 236 L 0 240 Z"
            />

            {/* Main LTV curve */}
            <path
              className={styles.curve}
              d="M 600 168 C 480 172, 360 176, 280 184 C 200 192, 140 206, 80 218 C 50 224, 20 232, 0 236"
            />

            {/* 70% cap intersection line */}
            <line
              x1="140"
              y1="72"
              x2="140"
              y2="240"
              stroke="var(--magma-500)"
              strokeDasharray="3,3"
              strokeWidth={1}
            />
            <circle cx="140" cy="72" r="4" fill="var(--magma-500)" />

            {/* Now dot */}
            <circle className={styles.nowDot} cx="420" cy="172" r="5" />
          </svg>

          {/* Annotation: now */}
          <div
            className={`${styles.anno} ${styles.annoNow}`}
            style={{ left: 'calc(70% - 60px)', top: '65%' }}
          >
            <span className={styles.annoKey}>now</span>LTV 49.8% &middot; BTC $94k
          </div>

          {/* Annotation: liquidation */}
          <div
            className={`${styles.anno} ${styles.annoLiq}`}
            style={{ left: 'calc(23% - 70px)', top: '18%' }}
          >
            <span className={styles.annoKey}>liq @</span>BTC $66.4k &middot; &minus;29%
          </div>
        </div>

        <div className={styles.xAxis}>
          {xLabels.map((x) => (
            <span key={x}>{x}</span>
          ))}
        </div>

        <div className={styles.axesTitles}>
          <span className={styles.axesTitlePrimary}>Y &middot; LTV</span>
          <span>X &middot; BTC price move</span>
        </div>
      </div>
    </div>
  );
}
