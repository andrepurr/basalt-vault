import React from 'react';
import styles from './SettleFlow.module.css';

const nodes = [
  {
    step: '01 \u00b7 request',
    name: 'User deposits',
    desc: 'Collateral + borrow intent enter the queue. Vault freezes.',
    live: false,
  },
  {
    step: '02 \u00b7 wrap',
    name: 'GMX wraps GM-BTC',
    desc: 'Async leg \u2014 GMX prices the position. Keeper finalizes in ~2s.',
    live: false,
  },
  {
    step: '03 \u00b7 settle',
    name: 'Keeper finalizes',
    desc: 'Reads wrap result, posts to Dolomite, unfreezes vault.',
    live: true,
  },
  {
    step: '04 \u00b7 open',
    name: 'Vault active',
    desc: 'Health computed. User can adjust, close, or compound.',
    live: false,
  },
];

const actors = [
  { label: 'user', col: styles.actorC1, live: false },
  { label: 'on-chain', col: styles.actorC2, live: false },
  { label: 'keeper', col: styles.actorC3, live: true },
  { label: 'user', col: styles.actorC4, live: false },
];

function Connector() {
  return (
    <div className={styles.connector}>
      <div className={styles.line} />
      <div className={styles.head} />
      <div className={styles.pellet} />
      <div className={styles.pellet} />
      <div className={styles.pellet} />
    </div>
  );
}

export function SettleFlow() {
  return (
    <div className={styles.stage}>
      <div className={styles.label}>Schematic &middot; 01</div>
      <div className={styles.title}>
        How a vault settles &mdash; async wrap with keeper finalization
      </div>

      <div className={styles.flow}>
        {nodes.map((node, i) => (
          <React.Fragment key={node.step}>
            {i > 0 && <Connector />}
            <div
              className={`${styles.node}${node.live ? ` ${styles.live}` : ''}`}
            >
              <div className={styles.step}>{node.step}</div>
              <div className={styles.name}>{node.name}</div>
              <div className={styles.desc}>{node.desc}</div>
            </div>
          </React.Fragment>
        ))}

        {actors.map((a) => (
          <div
            key={a.label + a.col}
            className={`${styles.actor} ${a.col}${a.live ? ` ${styles.actorLive}` : ''}`}
          >
            {a.label}
          </div>
        ))}
      </div>
    </div>
  );
}
