import { motion } from 'motion/react';
import { useCallback } from 'react';
import styles from './WhyBasalt.module.css';

const cards = [
  {
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
        <path d="M7 11V7a5 5 0 0 1 10 0v4" />
      </svg>
    ),
    title: 'Immutable core, patchable handlers',
    desc: 'No proxies. Core contracts are immutable. But modular handler slots let the protocol adapt if Dolomite upgrades — every patch requires explicit NFT-owner approval on-chain.',
    wide: true,
  },
  {
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z" />
        <path d="M10 12l2 2 4-4" />
      </svg>
    ),
    title: 'Open parameters',
    desc: 'All protocol constants published on-chain. Every number verifiable on Arbiscan.',
  },
  {
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
      </svg>
    ),
    title: 'On-chain hedging',
    desc: 'WBTC debt cancels BTC exposure. Delta-neutral without off-chain coordination.',
  },
  {
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <circle cx="12" cy="12" r="10" />
        <path d="M12 6v6l4 2" />
      </svg>
    ),
    title: 'Owner fallback controls',
    desc: 'Above 70% LTV the NFT owner can rebalance directly. If the manager goes dark for ~1 year, the deadman switch fires and the owner becomes full manager.',
  },
  {
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <rect x="2" y="2" width="8" height="8" rx="1" />
        <rect x="14" y="2" width="8" height="8" rx="1" />
        <rect x="2" y="14" width="8" height="8" rx="1" />
        <rect x="14" y="14" width="8" height="8" rx="1" />
      </svg>
    ),
    title: 'Isolated positions',
    desc: 'One NFT = one vault. Own Dolomite isolation account. No shared pool risk.',
  },
  {
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <path d="M2 12h4l3-9 6 18 3-9h4" />
      </svg>
    ),
    title: 'Adaptive rebalancing',
    desc: 'Automated LTV targeting, 4800-5200 bps band. No human discretion.',
  },
];

function SpotlightCard({ card, index }: { card: typeof cards[0]; index: number }) {
  const handleMouse = useCallback((e: React.MouseEvent<HTMLDivElement>) => {
    const rect = e.currentTarget.getBoundingClientRect();
    e.currentTarget.style.setProperty('--mx', `${e.clientX - rect.left}px`);
    e.currentTarget.style.setProperty('--my', `${e.clientY - rect.top}px`);
  }, []);

  return (
    <motion.div
      className={card.wide ? styles.cardWide : styles.card}
      onMouseMove={handleMouse}
      initial={{ opacity: 0, y: 24 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: '-60px' }}
      transition={{ duration: 0.4, delay: index * 0.07, ease: [0.2, 0.8, 0.2, 1] }}
    >
      <div className={styles.spotlight} />
      <div className={styles.cardIcon}>{card.icon}</div>
      <div className={styles.cardTitle}>{card.title}</div>
      <div className={styles.cardDesc}>{card.desc}</div>
    </motion.div>
  );
}

export function WhyBasalt() {
  return (
    <section className={styles.section}>
      <motion.h2
        className={styles.sectionTitle}
        initial={{ opacity: 0, y: 20 }}
        whileInView={{ opacity: 1, y: 0 }}
        viewport={{ once: true, margin: '-60px' }}
        transition={{ duration: 0.5, ease: [0.2, 0.8, 0.2, 1] }}
      >
        Verify everything on-chain.
      </motion.h2>

      <div className={styles.grid}>
        {cards.map((card, i) => (
          <SpotlightCard key={card.title} card={card} index={i} />
        ))}
      </div>
    </section>
  );
}
