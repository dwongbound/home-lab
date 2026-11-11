// Which page to draw: the dashboard, or the full-screen Talk page at /talk
// (also #talk, for builds served from a folder, like the preview).

/** True when the address is the Talk page. */
export function isTalkPage(loc: { pathname: string; hash: string }): boolean {
  if (loc.hash === '#talk') return true
  return loc.pathname.replace(/\/+$/, '').endsWith('/talk')
}
