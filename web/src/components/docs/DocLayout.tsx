import { useEffect } from 'react';
import { Outlet, useLocation } from 'react-router';
import { Header } from '../layout/Header';
import { Footer } from '../layout/Footer';
import { DocNav } from './DocNav';
import styles from './DocLayout.module.css';

export function DocLayout() {
  const { pathname } = useLocation();

  useEffect(() => {
    window.scrollTo(0, 0);
  }, [pathname]);

  return (
    <>
      <Header />
      <div className={styles.wrapper}>
        <DocNav />
        <main className={styles.content}>
          <Outlet />
        </main>
      </div>
      <Footer />
    </>
  );
}
