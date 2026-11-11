// The /talk page's own identity for "Add to Home Screen" (Dylan, 2026-11-11).
// iOS reads the manifest and app title from the HTML as served, before any
// script runs, so /talk can't borrow the dashboard's head and swap it later:
// the server hands it a head that already names the Talk app.

/** Whether a URL path is the Talk page (/talk or /talk/, under any folder). */
export function isTalkPagePath(pathname) {
  return pathname.replace(/\/+$/, '').endsWith('/talk')
}

/**
 * Turns the dashboard's index.html into the Talk page's: its own manifest
 * (separate app id and start_url ./talk), home-screen name and tab title.
 */
export function talkHead(html) {
  return html
    .replace('href="./manifest.webmanifest"', 'href="./talk.webmanifest"')
    .replace('<meta name="apple-mobile-web-app-title" content="Jarvis" />', '<meta name="apple-mobile-web-app-title" content="Talk" />')
    .replace('<title>Jarvis home lab</title>', '<title>Talk to Jarvis</title>')
}
