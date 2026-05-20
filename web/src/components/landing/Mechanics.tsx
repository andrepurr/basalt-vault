import { motion } from 'motion/react';
import { useCallback } from 'react';
import { mechanicsSteps } from '../../lib/landingContent';
import styles from './Mechanics.module.css';

function StepCard({ step, index }: { step: typeof mechanicsSteps[0]; index: number }) {
  const handleMouse = useCallback((e: React.MouseEvent<HTMLDivElement>) => {
    const r = e.currentTarget.getBoundingClientRect();
    e.currentTarget.style.setProperty('--mx', `${e.clientX - r.left}px`);
    e.currentTarget.style.setProperty('--my', `${e.clientY - r.top}px`);
  }, []);

  return (
    <motion.div
      className={styles.card}
      onMouseMove={handleMouse}
      initial={{ opacity: 0, y: 28 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: '-50px' }}
      transition={{ duration: 0.45, delay: index * 0.09, ease: [0.2, 0.8, 0.2, 1] }}
    >
      <div className={styles.glow} />
      <div className={styles.num}>{step.number}</div>
      <div className={styles.cardTitle}>{step.title}</div>
      <div className={styles.cardDesc}>{step.description}</div>
    </motion.div>
  );
}

export function Mechanics() {
  return (
    <section id="mechanics" className={styles.section}>
      <motion.div
        className={styles.head}
        initial={{ opacity: 0, y: 20 }}
        whileInView={{ opacity: 1, y: 0 }}
        viewport={{ once: true, margin: '-60px' }}
        transition={{ duration: 0.5, ease: [0.2, 0.8, 0.2, 1] }}
      >
        <div className={styles.eyebrow}>The vault lifecycle</div>
        <h2 className={styles.title}>Four moves. Zero discretion.</h2>
      </motion.div>

      <div className={styles.grid}>
        {mechanicsSteps.map((step, i) => (
          <StepCard key={step.number} step={step} index={i} />
        ))}
      </div>

      {/* Horizontal connector line */}
      <div className={styles.connector}>
        <motion.div
          className={styles.connectorFill}
          initial={{ scaleX: 0 }}
          whileInView={{ scaleX: 1 }}
          viewport={{ once: true, margin: '-80px' }}
          transition={{ duration: 1.2, ease: [0.2, 0.8, 0.2, 1] }}
        />
      </div>
    </section>
  );
}
