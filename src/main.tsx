// Entry point. Fonts are bundled (not fetched from Google) so the page
// still looks right if the PC is offline.
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import '@fontsource-variable/bricolage-grotesque'
import '@fontsource-variable/figtree'
import './styles.css'
import { App } from './App'
import { TalkPage } from './views/TalkPage'
import { isTalkPage } from './lib/talkPage'

// The longest the page waits for its fonts before drawing anyway.
const FONT_WAIT_MS = 700

/**
 * Loads the two page fonts before the first paint, so text doesn't swap
 * from the fallback font a moment later and nudge the top bar and panels
 * (Dylan, 2026-11-11). Gives up after FONT_WAIT_MS, or right away in
 * browsers without the font loading API (tests).
 */
function fontsLoaded(): Promise<unknown> {
  if (typeof document.fonts?.load !== 'function') return Promise.resolve()
  const fonts = Promise.all([
    document.fonts.load('600 17px "Bricolage Grotesque Variable"'),
    document.fonts.load('400 15px "Figtree Variable"'),
    document.fonts.load('600 15px "Figtree Variable"'),
  ]).catch(() => undefined)
  const timeout = new Promise((resolve) => setTimeout(resolve, FONT_WAIT_MS))
  return Promise.race([fonts, timeout])
}

void fontsLoaded().then(() => {
  createRoot(document.getElementById('root')!).render(
    <StrictMode>
      {/* /talk is its own full-screen page; everything else is the dashboard. */}
      {isTalkPage(window.location) ? <TalkPage /> : <App />}
    </StrictMode>,
  )
})
