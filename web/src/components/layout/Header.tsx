import { useState, useEffect } from 'react';
import { TransitionLink } from '../common/TransitionLink';
import { motion, AnimatePresence } from 'motion/react';
import { useAccount, useConnect, useDisconnect } from 'wagmi';
import { injected } from 'wagmi/connectors';
import { isAppDomain, appUrl, mainUrl } from '../../lib/urls';
import styles from './Header.module.css';

function BrandMark() {
  return (
    <svg width="24" height="24" viewBox="0 0 64 64" fill="none" aria-hidden="true">
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

const DEPLOYER = '0x6E31dB49Bb37C96AaB9178D6c1Fcd706D626bc93';

const baseLinks = [
  { label: 'Docs', href: '/docs' },
  { label: 'GitHub', href: 'https://github.com/xeyax/basalt-vault', external: true },
];

export function Header() {
  const [scrolled, setScrolled] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);
  const { isConnected, address, chain } = useAccount();
  const { connect, isPending: isConnecting } = useConnect();
  const { disconnect } = useDisconnect();
  const onApp = isAppDomain();
  const isAppPage = onApp;
  const shortAddr = address ? `${address.slice(0, 6)}...${address.slice(-4)}` : '';
  const isDeployer = address?.toLowerCase() === DEPLOYER.toLowerCase();
  const docsHref = onApp ? mainUrl('/docs') : '/docs';
  const keeperHref = onApp ? '/keeper' : appUrl('/keeper');
  const navLinks: typeof baseLinks = isDeployer
    ? [{ label: 'Docs', href: docsHref, external: onApp }, { label: 'GitHub', href: 'https://github.com/xeyax/basalt-vault', external: true }, { label: 'Keeper', href: keeperHref, external: false }]
    : [{ label: 'Docs', href: docsHref, external: onApp }, { label: 'GitHub', href: 'https://github.com/xeyax/basalt-vault', external: true }];

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 20);
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  useEffect(() => {
    if (mobileOpen) {
      document.body.style.overflow = 'hidden';
      return () => { document.body.style.overflow = ''; };
    }
  }, [mobileOpen]);

  return (
    <>
      <motion.nav
        className={`${styles.nav} ${scrolled ? styles.scrolled : ''}`}
        initial={{ y: -80 }}
        animate={{ y: 0 }}
        transition={{ duration: 0.6, ease: [0.2, 0.8, 0.2, 1] }}
      >
        <div className={styles.inner}>
          <TransitionLink to={onApp ? mainUrl() : '/'} className={styles.brand}>
            <motion.div
              whileHover={{ rotate: 30 }}
              transition={{ type: 'spring', stiffness: 300, damping: 15 }}
            >
              <BrandMark />
            </motion.div>
            <span className={styles.brandName}>BASALT</span>
            <span className={styles.brandSuffix}>VAULT</span>
          </TransitionLink>

          <div className={styles.links}>
            {navLinks.map((link, i) => (
              <motion.div
                key={link.label}
                initial={{ opacity: 0, y: -10 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.3 + i * 0.08 }}
              >
                {link.external ? (
                  <a href={link.href} className={styles.link} target="_blank" rel="noopener noreferrer">
                    {link.label}
                  </a>
                ) : (
                  <TransitionLink to={link.href} className={styles.link}>
                    {link.label}
                  </TransitionLink>
                )}
              </motion.div>
            ))}
          </div>

          {isAppPage ? (
            <div className={styles.walletArea}>
              {isConnected && chain && (
                <span className={styles.chainBadge}>
                  <span className={styles.chainDot} />
                  {chain.name}
                </span>
              )}
              {isConnected && address ? (
                <>
                  <span className={styles.walletAddr}>{shortAddr}</span>
                  <button className={styles.disconnectBtn} onClick={() => disconnect()}>
                    Disconnect
                  </button>
                </>
              ) : (
                <button className={styles.cta} disabled={isConnecting}
                  onClick={() => connect({ connector: injected() })}>
                  {isConnecting ? 'Connecting...' : 'Connect Wallet'}
                </button>
              )}
            </div>
          ) : (
            <TransitionLink to={appUrl()} className={styles.cta}>
              Open app
            </TransitionLink>
          )}

          <button
            className={styles.burger}
            onClick={() => setMobileOpen(!mobileOpen)}
            aria-label="Toggle navigation menu"
            aria-expanded={mobileOpen}
          >
            <span className={`${styles.burgerLine} ${mobileOpen ? styles.burgerOpen1 : ''}`} />
            <span className={`${styles.burgerLine} ${mobileOpen ? styles.burgerOpen2 : ''}`} />
          </button>
        </div>
      </motion.nav>

      <AnimatePresence>
        {mobileOpen && (
          <motion.nav
            className={styles.mobileMenu}
            aria-label="Mobile navigation"
            initial={{ opacity: 0, y: -20 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -20 }}
            transition={{ duration: 0.3, ease: [0.2, 0.8, 0.2, 1] }}
          >
            {navLinks.map((link, i) => (
              <motion.div
                key={link.label}
                initial={{ opacity: 0, x: -20 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: i * 0.08 }}
              >
                {link.external ? (
                  <a href={link.href} className={styles.mobileLink} target="_blank" rel="noopener noreferrer"
                    onClick={() => setMobileOpen(false)}>
                    {link.label}
                  </a>
                ) : (
                  <TransitionLink to={link.href} className={styles.mobileLink}
                    onClick={() => setMobileOpen(false)}>
                    {link.label}
                  </TransitionLink>
                )}
              </motion.div>
            ))}
            <TransitionLink to={appUrl()} className={styles.mobileCta} onClick={() => setMobileOpen(false)}>
              Open app
            </TransitionLink>
          </motion.nav>
        )}
      </AnimatePresence>
    </>
  );
}
