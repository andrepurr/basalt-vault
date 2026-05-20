import { Header } from '../components/layout/Header';
import { Hero } from '../components/landing/Hero';
import { StrategyChart } from '../components/landing/StrategyChart';
import { WhyBasalt } from '../components/landing/WhyBasalt';
import { Schematics } from '../components/landing/Schematics';
import { Mechanics } from '../components/landing/Mechanics';
import { Stats } from '../components/landing/Stats';
import { Footer } from '../components/layout/Footer';

export function Landing() {
  return (
    <>
      <a href="#main-content" className="skip-link">Skip to main content</a>
      <Header />
      <main id="main-content">
        <Hero />
        <StrategyChart />
        <WhyBasalt />
        <Schematics />
        <Mechanics />
        <Stats />
      </main>
      <Footer />
    </>
  );
}
