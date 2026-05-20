import { BrowserRouter, Routes, Route, Navigate } from 'react-router';
import { Landing } from './pages/Landing';
import { App2Page } from './pages/App2Page';
import { KeeperPage } from './pages/KeeperPage';
import { DocLayout } from './components/docs/DocLayout';
import { Overview } from './pages/docs/Overview';
import { Architecture } from './pages/docs/Architecture';
import { UserGuide } from './pages/docs/UserGuide';
import { Contracts } from './pages/docs/Contracts';
import { Fees } from './pages/docs/Fees';
import { Keeper } from './pages/docs/Keeper';
import { Security } from './pages/docs/Security';
import { Risks } from './pages/docs/Risks';
import { isAppDomain, appUrl } from './lib/urls';

function ExternalRedirect({ to }: { to: string }) {
  window.location.replace(to);
  return null;
}

export function App() {
  const onAppDomain = isAppDomain();

  return (
    <BrowserRouter>
      <Routes>
        {onAppDomain ? (
          <>
            <Route path="/" element={<App2Page />} />
            <Route path="/keeper" element={<KeeperPage />} />
            <Route path="*" element={<Navigate to="/" replace />} />
          </>
        ) : (
          <>
            <Route path="/" element={<Landing />} />
            <Route path="/app" element={<ExternalRedirect to={appUrl()} />} />
            <Route path="/app2" element={<ExternalRedirect to={appUrl()} />} />
            <Route path="/app/keeper" element={<ExternalRedirect to={appUrl('/keeper')} />} />
            <Route path="/docs" element={<DocLayout />}>
              <Route index element={<Navigate to="/docs/overview" replace />} />
              <Route path="overview" element={<Overview />} />
              <Route path="architecture" element={<Architecture />} />
              <Route path="user-guide" element={<UserGuide />} />
              <Route path="contracts" element={<Contracts />} />
              <Route path="fees" element={<Fees />} />
              <Route path="keeper" element={<Keeper />} />
              <Route path="security" element={<Security />} />
              <Route path="risks" element={<Risks />} />
            </Route>
          </>
        )}
      </Routes>
    </BrowserRouter>
  );
}
