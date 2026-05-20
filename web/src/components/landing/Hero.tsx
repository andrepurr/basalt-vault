import { motion, useScroll, useTransform } from 'motion/react';
import { useRef, useState, useEffect, useCallback } from 'react';
import { Button } from '../common/Button';
import { useReducedMotion } from '../../hooks/useReducedMotion';
import { appUrl } from '../../lib/urls';
import { heroStats, protocolBadges } from '../../lib/landingContent';
import styles from './Hero.module.css';


const subtitleLines = [
  'Earn GM trading fees with leveraged exposure, hedged by WBTC debt.',
  'Critical invariants proven with symbolic testing. Math you can verify.',
  'Full vault isolation — one NFT, one Dolomite account, zero shared state.',
  '2-year hourly backtest. 17,500 data points. Slippage and fees included.',
  'Immutable handlers. Opt-in upgrades — your vault survives any protocol change.',
  'Deposit USDC — the vault handles looping, hedging, and rebalancing.',
];

function TypewriterSlider() {
  const [lineIdx, setLineIdx] = useState(0);
  const [charIdx, setCharIdx] = useState(0);
  const [deleting, setDeleting] = useState(false);
  const reduced = useReducedMotion();
  const line = subtitleLines[lineIdx];

  useEffect(() => {
    if (reduced) { setCharIdx(line.length); return; }
    if (!deleting) {
      if (charIdx < line.length) {
        const t = setTimeout(() => setCharIdx(c => c + 1), 28 + Math.random() * 20);
        return () => clearTimeout(t);
      }
      const pause = setTimeout(() => setDeleting(true), 2800);
      return () => clearTimeout(pause);
    } else {
      if (charIdx > 0) {
        const t = setTimeout(() => setCharIdx(c => c - 1), 14);
        return () => clearTimeout(t);
      }
      setDeleting(false);
      setLineIdx(i => (i + 1) % subtitleLines.length);
    }
  }, [charIdx, deleting, line, reduced]);

  const goTo = useCallback((i: number) => {
    setDeleting(false); setLineIdx(i); setCharIdx(0);
  }, []);

  return (
    <div className={styles.typewriter}>
      <span className={styles.typewriterText}>
        {line.slice(0, charIdx)}
        <span className={styles.cursor} />
      </span>
      <div className={styles.sliderNav}>
        {subtitleLines.map((_, i) => (
          <button key={i} className={`${styles.pip} ${i === lineIdx ? styles.pipActive : ''}`}
            onClick={() => goTo(i)} aria-label={`Line ${i + 1}`} />
        ))}
      </div>
    </div>
  );
}

export function Hero() {
  const reduced = useReducedMotion();
  const ref = useRef<HTMLElement>(null);
  const { scrollYProgress } = useScroll({ target: ref, offset: ['start start', 'end start'] });
  const contentY = useTransform(scrollYProgress, [0, 1], [0, -100]);
  const contentOp = useTransform(scrollYProgress, [0, 0.5], [1, 0]);
  const numY = useTransform(scrollYProgress, [0, 1], [0, -50]);

  const fade = (delay: number) => ({
    initial: { opacity: 0, y: 32 } as const,
    animate: { opacity: 1, y: 0 } as const,
    transition: { delay, duration: 0.8, ease: [0.16, 1, 0.3, 1] as const },
  });

  return (
    <section ref={ref} className={styles.hero}>
      {/* Animated rings */}
      <div className={styles.rings}>
        <div className={styles.ring1} />
        <div className={styles.ring2} />
        <div className={styles.ring3} />
        <div className={styles.ring4} />
        <div className={styles.ring5} />
      </div>
      {/* Glow blobs */}
      <div className={styles.blobWrap}>
        <div className={styles.blob1} />
        <div className={styles.blob2} />
      </div>
      {/* Noise grain */}
      <div className={styles.grain} />

      <motion.div className={styles.content} style={reduced ? {} : { y: contentY, opacity: contentOp }}>
        <motion.div className={styles.eyebrow} {...fade(0.05)}>
          Dolomite + GMX &middot; Arbitrum One
        </motion.div>

        <div className={styles.headRow}>
          <motion.h1 className={styles.title} {...fade(0.2)}>
            On-chain<br />hedged<br />BTC yield.
          </motion.h1>

          <motion.div className={styles.numBlock} style={reduced ? {} : { y: numY }} {...fade(0.15)}>
            <div className={styles.numTop}>
              <span className={styles.numVal}>10.4</span>
              <span className={styles.numPct}>%</span>
            </div>
            <span className={styles.numTag}>Projected APY</span>
          </motion.div>
        </div>

        <motion.div className={styles.sub} {...fade(0.35)}>
          Leveraged GM yield, hedged BTC exposure. Fully on-chain.
        </motion.div>

        <motion.div className={styles.sliderArea} {...fade(0.45)}>
          <TypewriterSlider />
        </motion.div>

        <motion.div className={styles.band} {...fade(0.55)}>
          <div className={styles.bandL}>
            <Button variant="primary" size="lg" href={appUrl()}>Open app</Button>
            <Button variant="ghost" size="lg" href="/docs">Docs</Button>
          </div>
          <div className={styles.bandR}>
            {heroStats.map(({ label, value }) => (
              <div key={label} className={styles.stat}>
                <span className={styles.statL}>{label}</span>
                <span className={styles.statV}>{value}</span>
              </div>
            ))}
          </div>
        </motion.div>

        <motion.div className={styles.trustRow} {...fade(0.65)}>
          <span className={styles.trustLabel}>Built on</span>
          {protocolBadges.map(({ name, detail }) => (
            <div key={name} className={styles.trustBadge}>
              <span className={styles.trustName}>{name}</span>
              <span className={styles.trustDetail}>{detail}</span>
            </div>
          ))}
        </motion.div>
      </motion.div>
    </section>
  );
}
