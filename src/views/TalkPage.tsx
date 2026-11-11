import { useEffect } from 'react'
import { useSnapshot } from '../api/client'
import { Backdrop } from '../components/Backdrop'
import { JarvisPanel } from '../components/JarvisPanel'
import { ThinkingLoader } from '../components/ThinkingLoader'
import { readSky } from '../lib/prefs'
import { useNow } from '../useNow'
import { useWakeLock } from '../useWakeLock'

// The /talk page (Dylan, 2026-11-11): nothing but the chat with Jarvis,
// filling the screen, ready for a tap on Talk. Saved to the home screen it
// opens straight here as its own app (talk.webmanifest). The tap is needed
// because iOS only lets a page use the microphone after one.

/**
 * Points "Add to Home Screen" at this page: its own manifest (start_url
 * /talk) and name, so the icon opens Talk rather than the dashboard.
 */
function useTalkInstall() {
  useEffect(() => {
    document.title = 'Talk to Jarvis'
    document.querySelector('link[rel="manifest"]')?.setAttribute('href', './talk.webmanifest')
    document.querySelector('meta[name="apple-mobile-web-app-title"]')?.setAttribute('content', 'Talk')
  }, [])
}

/** The whole /talk page: the sky behind, the chat sheet in front. */
export function TalkPage() {
  const { data } = useSnapshot()
  const now = useNow()
  useTalkInstall()
  // Safari drops the microphone when the screen locks, so keep it on here.
  useWakeLock(true)

  let body: React.ReactNode = <section className="state state--loading"><ThinkingLoader /></section>
  // The snapshot only says whether there's a real Jarvis to talk to (live)
  // or the demo (sample data).
  if (data) body = <JarvisPanel live={data.source === 'live'} page />

  return (
    <>
      <Backdrop now={now} override={readSky()} />
      <div className="shell" data-view="talk">{body}</div>
    </>
  )
}
