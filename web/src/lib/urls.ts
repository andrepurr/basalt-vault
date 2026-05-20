const APP_HOST = 'app.btva.io';
const MAIN_HOST = 'btva.io';

/** True when running on the app subdomain (production) or /app path (dev) */
export function isAppDomain(): boolean {
  return window.location.hostname === APP_HOST;
}

/** Absolute URL to the app subdomain */
export function appUrl(path = ''): string {
  return `https://${APP_HOST}${path}`;
}

/** Absolute URL to the main domain */
export function mainUrl(path = ''): string {
  return `https://${MAIN_HOST}${path}`;
}
