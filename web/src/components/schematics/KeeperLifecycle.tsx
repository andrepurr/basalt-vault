import styles from './KeeperLifecycle.module.css';

type StopStatus = 'done' | 'live' | 'pending';

interface Stop {
  name: string;
  time: string;
  desc: string;
  status: StopStatus;
}

const stops: Stop[] = [
  { name: 'Queued', time: 't = 0s', desc: 'User tx confirmed, vault frozen', status: 'done' },
  { name: 'Wrap sent', time: 't \u2248 4s', desc: 'GMX accepts wrap order', status: 'done' },
  { name: 'Pricing', time: 't \u2248 60s', desc: 'Async wrap settling on GMX', status: 'live' },
  { name: 'Keeper picks up', time: 't \u2248 75s', desc: 'Reads result, posts to Dolomite', status: 'pending' as const },
  { name: 'Finalized', time: 't \u2248 90s', desc: 'Vault active, health computed', status: 'pending' as const },
];

function stopClass(status: StopStatus) {
  if (status === 'done') return `${styles.stop} ${styles.done}`;
  if (status === 'live') return `${styles.stop} ${styles.liveDot}`;
  return styles.stop;
}

export function KeeperLifecycle() {
  return (
    <div className={styles.stage}>
      <div className={styles.label}>Schematic &middot; 03</div>
      <div className={styles.title}>
        Keeper lifecycle &mdash; GMX ~2s, keeper ~2s, vault owner safety net if stuck
      </div>

      <div className={styles.timeline}>
        <div className={styles.progress} />
        <div className={styles.scan} />
      </div>

      <div className={styles.stops}>
        {stops.map((s) => (
          <div key={s.name} className={stopClass(s.status)}>
            <div className={styles.dot} />
            <div className={styles.stopName}>{s.name}</div>
            <div className={styles.stopTime}>{s.time}</div>
            <div className={styles.stopDesc}>{s.desc}</div>
          </div>
        ))}
      </div>

      <div className={styles.branch}>
        <div className={styles.card}>
          <div className={styles.cardLabel}>Happy path</div>
          Keeper finalizes within <b>~90 seconds</b>. Vault unfreezes; user can adjust.
        </div>
        <div className={`${styles.card} ${styles.cardDanger}`}>
          <div className={styles.cardLabel}>Stuck path</div>
          If stuck past grace period &rarr; vault NFT owner or protocol manager can <b>cancel and recover</b>.
          Safety net that almost never triggers.
        </div>
      </div>
    </div>
  );
}
