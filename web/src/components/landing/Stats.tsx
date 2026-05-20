import { useRef } from 'react';
import { motion, useScroll, useTransform } from 'motion/react';
import { parameterRows } from '../../lib/landingContent';
import { useReducedMotion } from '../../hooks/useReducedMotion';
import styles from './Stats.module.css';

function Marquee({ children, reverse = false }: { children: React.ReactNode; reverse?: boolean }) {
  const reduced = useReducedMotion();
  return (
    <div className={styles.marqueeTrack}>
      <motion.div
        className={styles.marqueeInner}
        animate={reduced ? {} : { x: reverse ? ['0%', '-50%'] : ['-50%', '0%'] }}
        transition={{ duration: 30, ease: 'linear', repeat: Infinity }}
      >
        {children}
        {children}
      </motion.div>
    </div>
  );
}

function ParamTile({ name, value, desc, index }: { name: string; value: string; desc: string; index: number }) {
  const ref = useRef<HTMLDivElement>(null);
  const { scrollYProgress } = useScroll({ target: ref, offset: ['start end', 'end start'] });
  const y = useTransform(scrollYProgress, [0, 1], [40, -40]);
  const reduced = useReducedMotion();

  return (
    <motion.div
      ref={ref}
      className={styles.tile}
      style={reduced ? undefined : { y }}
      initial={reduced ? {} : { opacity: 0, scale: 0.95 }}
      whileInView={reduced ? {} : { opacity: 1, scale: 1 }}
      transition={reduced ? {} : { duration: 0.5, delay: index * 0.08 }}
      viewport={{ once: true, margin: '-50px' }}
    >
      <div className={styles.tileValue}>{value}</div>
      <div className={styles.tileName}>{name}</div>
      <div className={styles.tileDesc}>{desc}</div>
    </motion.div>
  );
}

export function Stats() {
  const reduced = useReducedMotion();
  const topRow = parameterRows.slice(0, 4);
  const bottomRow = parameterRows.slice(4);

  return (
    <section className={styles.section}>
      <Marquee>
        <div className={styles.ticker}>
          {parameterRows.map(([name, val]) => (
            <span key={name} className={styles.tickerItem}>
              <span className={styles.tickerLabel}>{name}</span>
              <span className={styles.tickerValue}>{val}</span>
            </span>
          ))}
        </div>
      </Marquee>

      <div className={styles.content}>
        <motion.h2
          className={styles.bigTitle}
          initial={reduced ? {} : { opacity: 0, y: 30 }}
          whileInView={reduced ? {} : { opacity: 1, y: 0 }}
          transition={reduced ? {} : { duration: 0.6 }}
          viewport={{ once: true }}
        >
          The numbers,<br />in full.
        </motion.h2>

        <div className={styles.bentoTop}>
          {topRow.map(([name, value, desc], i) => (
            <ParamTile key={name} name={name} value={value} desc={desc} index={i} />
          ))}
        </div>
        <div className={styles.bentoBottom}>
          {bottomRow.map(([name, value, desc], i) => (
            <ParamTile key={name} name={name} value={value} desc={desc} index={i + 4} />
          ))}
        </div>
      </div>

      <Marquee reverse>
        <div className={styles.ticker}>
          {[...parameterRows].reverse().map(([name, val]) => (
            <span key={name} className={styles.tickerItem}>
              <span className={styles.tickerLabel}>{name}</span>
              <span className={styles.tickerValue}>{val}</span>
            </span>
          ))}
        </div>
      </Marquee>
    </section>
  );
}
