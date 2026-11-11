import { useCallback, useEffect, useState } from 'react'
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
import { shownPhase } from './lib/sky'

// The whole page: backdrop, top bar, and whichever view the hash names.
// It owns the three page-level states: waiting for the first snapshot
// (blocking spinner), can't reach the server (error with Try again), and
// ready.

// Long enough for the slowest landing animation (styles.css) to finish.
const LANDING_MS = 2600

/** The app. */
export function App() {
  const { data, error, isValidating, mutate } = useSnapshot()
  const view = useHashView()
  const now = useNow()
  const [sky, setSky] = useState<SkyChoice>(() => readSky() as SkyChoice)
  const [toast, setToast] = useState<string | null>(null)
  // Keep the screen on (Settings), for the iPad as an always-on display.
  const [awake, setAwake] = useState(readAwake)
  const wake = useWakeLock(awake)

  // Toasts clear themselves after 4 seconds.
  useEffect(() => {
    if (!toast) return
    const id = setTimeout(() => setToast(null), 4000)
    return () => clearTimeout(id)
  }, [toast])

  // The landing plays once, when the first snapshot arrives, and is then
  // switched off so it never replays (page changes have their own crossfade).
  const hasData = data !== undefined
  const [landing, setLanding] = useState(true)
  useEffect(() => {
    if (!hasData) return
    const id = setTimeout(() => setLanding(false), LANDING_MS)
    return () => clearTimeout(id)
  }, [hasData])

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
      <Backdrop now={now} override={sky} landing={landing} />
      {/* data-landing waits for the data, so the arrival plays on the real page, not the spinner. */}
      {/* data-sky lets the glass darken its tint under the bright day sky (styles.css). */}
      {/* data-view lets the Overview fill exactly one screen on a display-sized window. */}
      <div className="shell" data-view={view} data-sky={shownPhase(now, sky)} data-landing={landing && hasData ? '' : undefined}>
        <TopNav view={view} source={data?.source ?? null} refreshing={isValidating} onRefresh={refresh} />
        {/* Anything needing him right now sits above every page, not inside Today. */}
        {data ? <AlertBanner alerts={activeAlerts(data, now)} /> : null}
        <DigestRefreshing.Provider value={digestRefreshing}>
          <main className="main" key={data ? 'ready' : 'waiting'}>{body}</main>
        </DigestRefreshing.Provider>
        {data && error ? <p className="stale" role="status">Last update failed. Showing numbers from {new Date(data.generatedAt).toLocaleTimeString()}.</p> : null}
      </div>
      {toast ? <p className="toast" role="status">{toast}</p> : null}
    </>
  )
}
