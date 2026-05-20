import { TransitionLink } from '../common/TransitionLink';
import { isAppDomain, appUrl, mainUrl } from '../../lib/urls';
import styles from './Footer.module.css';

function BrandMark() {
  return (
    <svg width="20" height="20" viewBox="0 0 64 64" fill="none" aria-hidden="true">
      <g stroke="currentColor" strokeWidth="3" strokeLinejoin="miter">
        <path d="M32 4 L56 18 V46 L32 60 L8 46 V18 Z" fill="none" />
        <path d="M32 4 V32 L8 18" />
        <path d="M32 32 L56 18" />
        <path d="M32 32 V60" />
      </g>
      <circle cx="32" cy="32" r="4" fill="var(--ember-500)" />
    </svg>
  );
}

function getColumns() {
  const onApp = isAppDomain();
  const docPath = (p: string) => onApp ? mainUrl(`/docs/${p}`) : `/docs/${p}`;
  return [
    {
      heading: 'Product',
      links: [
        { label: 'Open App', href: onApp ? '/' : appUrl() },
        { label: 'Overview', href: docPath('overview') },
        { label: 'User Guide', href: docPath('user-guide') },
      ],
    },
    {
      heading: 'Technical',
      links: [
        { label: 'Architecture', href: docPath('architecture') },
        { label: 'Contracts', href: docPath('contracts') },
        { label: 'Fee Structure', href: docPath('fees') },
      ],
    },
    {
      heading: 'Operations',
      links: [
        { label: 'Keeper', href: docPath('keeper') },
        { label: 'Security', href: docPath('security') },
        { label: 'Risks', href: docPath('risks') },
        { label: 'Keeper Dashboard', href: onApp ? '/keeper' : appUrl('/keeper') },
      ],
    },
  ];
}

export function Footer() {
  const columns = getColumns();
  return (
    <footer className={styles.footer}>
      <div className={styles.inner}>
        <div className={styles.left}>
          <div className={styles.brand}>
            <BrandMark />
            <span className={styles.brandName}>BASALT VAULT</span>
          </div>
          <div className={styles.chainInfo}>Arbitrum One &middot; chainId 42161</div>
        </div>
        <div className={styles.columns}>
          {columns.map((col) => (
            <div key={col.heading}>
              <div className={styles.colHeading}>{col.heading}</div>
              {col.links.map((link) => (
                'external' in link && link.external ? (
                  <a key={link.label} href={link.href} className={styles.link}
                    target="_blank" rel="noopener noreferrer">
                    {link.label}
                  </a>
                ) : (
                  <TransitionLink key={link.label} to={link.href} className={styles.link}>
                    {link.label}
                  </TransitionLink>
                )
              ))}
            </div>
          ))}
        </div>
      </div>
      <div className={styles.bottom}>
        <span className={styles.copy}>&copy; 2026 Basalt Vault</span>
        <span className={styles.badge}>Built on Arbitrum</span>
      </div>
    </footer>
  );
}
