import { useCallback, useEffect, useRef, useState } from 'react'
import { useSnapshot } from './api/client'
import { DigestRefreshing, useDigestRefresh } from './api/digestRefresh'
import { Backdrop } from './components/Backdrop'
import { TopNav } from './components/TopNav'
import { ThinkingLoader } from './components/ThinkingLoader'
import { AlertBanner } from './components/AlertBanner'
import { activeAlerts } from './lib/agenda'
import { Overview } from './views/Overview'
import { Services } from './views/Services'
import { Claude } from './views/Claude'
import { Money } from './views/Money'
import { Home } from './views/Home'
import { Schedule } from './views/Schedule'
import { Settings, type SkyChoice } from './views/Settings'
import { swipeToView, useHashView } from './useHashView'
import { useSwipeNav } from './useSwipeNav'
import { useNow } from './useNow'
import { readAwake, readSky, writeAwake, writeSky } from './lib/prefs'
import { useWakeLock } from './useWakeLock'
import { useReveal } from './useReveal'
import { KioskMode, useKiosk } from './useKiosk'
import { shownPhase } from './lib/sky'

// The whole page: backdrop, top bar, and whichever view the hash names.
// It owns the three page-level states: waiting for the first snapshot
// (blocking spinner), can't reach the server (error with Try again), and
// ready.

/** The app. */
export function App() {
  const { data, error, isValidating, mutate } = useSnapshot()
  const view = useHashView()
  const now = useNow()
  const [sky, setSky] = useState<SkyChoice>(() => readSky() as SkyChoice)
  const [toast, setToast] = useState<string | null>(null)
  // Keep the screen on (Settings), for the iPad as an always-on display.
  const [awake, setAwake] = useState(readAwake)
  // Kiosk mode: full screen, moving through the tabs by itself. It keeps the screen on too.
  const kiosk = useKiosk(view)
  const wake = useWakeLock(awake || kiosk.on)

  // Toasts clear themselves after 4 seconds.
  useEffect(() => {
    if (!toast) return
    const id = setTimeout(() => setToast(null), 4000)
    return () => clearTimeout(id)
  }, [toast])

  // When the first snapshot arrives the page simply appears: no landing
  // animation. Every version of one shook on Dylan's iPhone (2026-11-11).
  const hasData = data !== undefined

  // Panels fade in on the first load and on every page change, and below
  // the screen as they're scrolled to. The main element is replaced once the
  // data arrives (its key), and each page brings new panels, so watch again
  // on either.
  const mainRef = useRef<HTMLElement>(null)
  useReveal(mainRef, `${hasData ? 'ready' : 'waiting'}:${view}`)

  // Swiping sideways changes tab, on touch screens.
  useSwipeNav(view, swipeToView)

  const chooseSky = useCallback((s: SkyChoice) => { setSky(s); writeSky(s) }, [])
  const chooseAwake = useCallback((on: boolean) => { setAwake(on); writeAwake(on) }, [])
  const refresh = useCallback(() => { void mutate() }, [mutate])
  // Opening the page asks Jarvis for a fresh digest; panels say so meanwhile.
  const digestRefreshing = useDigestRefresh(data?.cloud?.updatedAt ?? null, refresh)

  let body: React.ReactNode
  if (!data && error) {
    body = (
      <section className="glass panel state" role="alert">
        <h1 className="panel__title">Can’t reach the jarvis server</h1>
        <p>{error.message}. Check that <code>npm start</code> is running on the PC, then try again.</p>
        <button type="button" className="btn btn--primary" onClick={refresh}>Try again</button>
      </section>
    )
  } else if (!data) {
    body = <section className="state state--loading"><ThinkingLoader /></section>
  } else if (view === 'claude') {
    body = <Claude data={data} now={now} />
  } else if (view === 'home') {
    body = <Home data={data} now={now} />
  } else if (view === 'money') {
    body = <Money data={data} now={now} />
  } else if (view === 'services') {
    body = <Services data={data} now={now} onToast={setToast} />
  } else if (view === 'schedule') {
    body = <Schedule data={data} now={now} />
  } else if (view === 'preferences') {
    body = <Settings data={data} now={now} sky={sky} onSky={chooseSky} awake={awake} wake={wake} onAwake={chooseAwake} />
  } else {
    body = <Overview data={data} now={now} />
  }

  return (
    <>
      <Backdrop now={now} override={sky} />
      {/* data-sky lets the glass darken its tint under the bright day sky (styles.css). */}
      {/* data-view lets the Overview fill exactly one screen on a display-sized window. */}
      <div className="shell" data-view={view} data-sky={shownPhase(now, sky)} data-kiosk={kiosk.on || undefined}>
        <TopNav view={view} source={data?.source ?? null} refreshing={isValidating} onRefresh={refresh} kiosk={kiosk.on} onKiosk={kiosk.start} onKioskClose={kiosk.stop} />
        {/* Anything needing him right now sits above every page, not inside Today. */}
        {data ? <AlertBanner alerts={activeAlerts(data, now)} /> : null}
        <DigestRefreshing.Provider value={digestRefreshing}>
          <KioskMode.Provider value={kiosk.on}>
            <main className="main" ref={mainRef} key={data ? 'ready' : 'waiting'}>{body}</main>
          </KioskMode.Provider>
        </DigestRefreshing.Provider>
        {data && error ? <p className="stale" role="status">Last update failed. Showing numbers from {new Date(data.generatedAt).toLocaleTimeString()}.</p> : null}
      </div>
      {toast ? <p className="toast" role="status">{toast}</p> : null}
    </>
  )
}
