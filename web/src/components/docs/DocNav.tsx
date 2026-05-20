import { useLocation } from 'react-router';
import { TransitionLink } from '../common/TransitionLink';
import styles from './DocNav.module.css';

interface NavItem {
  label: string;
  to: string;
  hash?: boolean;
}

interface NavGroup {
  title: string;
  items: NavItem[];
}

const NAV_GROUPS: NavGroup[] = [
  {
    title: 'Getting started',
    items: [
      { label: 'Overview', to: '/docs/overview' },
      { label: 'User guide', to: '/docs/user-guide' },
    ],
  },
  {
    title: 'Architecture',
    items: [
      { label: 'Contract map', to: '/docs/architecture' },
      { label: 'Contracts', to: '/docs/contracts' },
      { label: 'Fee structure', to: '/docs/fees' },
    ],
  },
  {
    title: 'Operations',
    items: [
      { label: 'Keeper', to: '/docs/keeper' },
      { label: 'Security', to: '/docs/security' },
      { label: 'Risks', to: '/docs/risks' },
    ],
  },
  {
    title: 'Reference',
    items: [
      { label: 'State machines', to: '/docs/architecture#state-machine', hash: true },
      { label: 'LTV safety', to: '/docs/user-guide#safety', hash: true },
      { label: 'Constants', to: '/docs/architecture#constants', hash: true },
      { label: 'Risk summary', to: '/docs/risks#summary', hash: true },
    ],
  },
];

export function DocNav() {
  const location = useLocation();

  return (
    <aside className={styles.sidebar}>
      {NAV_GROUPS.map((group) => (
        <div key={group.title} className={styles.group}>
          <div className={styles.groupLabel}>{group.title}</div>
          {group.items.map((item) => {
            const isActive = !item.hash && location.pathname === item.to;
            return (
              <TransitionLink
                key={item.to}
                to={item.to}
                className={isActive ? styles.linkActive : styles.link}
              >
                {item.label}
              </TransitionLink>
            );
          })}
        </div>
      ))}
    </aside>
  );
}
