import { useLayoutEffect, useRef, useState } from 'react'
import { Icon, type IconName } from './Icon'

// The top bar: host name on the left, pill navigation in the middle, and
// data source, refresh, the kiosk button and avatar on the right. In kiosk
// mode the right side is just Close. Navigation is plain links
// to #hashes, so it works with the keyboard, back button and bookmarks.
// The light on the current pill is one element that slides from pill to
// pill, rather than each pill lighting up on its own. It carries a dark
// copy of the pills that moves the other way, so whatever the light passes
// over reads dark on light all the way across, like a segmented control.

export type View = 'overview' | 'home' | 'claude' | 'money' | 'services' | 'schedule' | 'preferences'
// Settings lives at #preferences: claude.ai reserves #settings, and the
// preview page is hosted there.
export const VIEWS: { id: View; label: string; icon: IconName }[] = [
  { id: 'overview', label: 'Overview', icon: 'home' },
  { id: 'home', label: 'Home', icon: 'bulb' },
  { id: 'claude', label: 'Claude', icon: 'claude' },
  { id: 'money', label: 'Money', icon: 'money' },
  { id: 'services', label: 'Services', icon: 'services' },
  { id: 'schedule', label: 'Schedule', icon: 'schedule' },
  { id: 'preferences', label: 'Settings', icon: 'settings' },
]

interface Props {
  view: View
  source: 'mock' | 'live' | null
  refreshing: boolean
  onRefresh: () => void
  /** Whether kiosk mode is on (src/useKiosk.ts). */
  kiosk: boolean
  onKiosk: () => void
  onKioskClose: () => void
}

/** Where the sliding light sits: under the current pill, in px from the bar's edge. */
function useIndicator(view: View) {
  const navRef = useRef<HTMLElement>(null)
  const [box, setBox] = useState<{ x: number; w: number } | null>(null)

  // Measured before paint, so the light never shows in the wrong place.
  // Re-measured when the bar resizes (narrow screens hide the labels).
  useLayoutEffect(() => {
    const nav = navRef.current
    if (nav === null) return
    const place = () => {
      const current = nav.querySelector<HTMLElement>('[aria-current="page"]')
      if (current) setBox({ x: current.offsetLeft, w: current.offsetWidth })
    }
    place()
    if (typeof ResizeObserver === 'undefined') return
    const observer = new ResizeObserver(place)
    observer.observe(nav)
    return () => observer.disconnect()
  }, [view])

  return { navRef, box }
}

/** The top bar. */
export function TopNav({ view, source, refreshing, onRefresh, kiosk, onKiosk, onKioskClose }: Props) {
  const { navRef, box } = useIndicator(view)
  return (
    <header className="topbar">
      <a className="topbar__host" href="#overview" aria-label="jarvis overview">
        <span className="topbar__orb" aria-hidden="true" />
        <span>jarvis</span>
      </a>
      <nav aria-label="Sections" className="pills" ref={navRef}>
        {box ? (
          <span
            className="pills__light"
            aria-hidden="true"
            style={{ transform: `translateX(${box.x}px)`, width: box.w }}
          >
            <span className="pills__ink" style={{ transform: `translateX(${-box.x}px)` }}>
              {VIEWS.map((v) => (
                <span key={v.id} className="pill">
                  <Icon name={v.icon} size={16} />
                  <span className="pill__label">{v.label}</span>
                </span>
              ))}
            </span>
          </span>
        ) : null}
        {VIEWS.map((v) => (
          <a key={v.id} href={`#${v.id}`} className="pill" aria-current={v.id === view ? 'page' : undefined}>
            <Icon name={v.icon} size={16} />
            <span className="pill__label">{v.label}</span>
          </a>
        ))}
      </nav>
      {kiosk ? (
        <div className="topbar__end">
          <button type="button" className="btn kiosk__close" onClick={onKioskClose} aria-label="Close kiosk mode">Close</button>
        </div>
      ) : (
      <div className="topbar__end">
        {source === 'mock' ? <span className="chip" title="Numbers are made up until the live source is switched on">Sample data</span> : null}
        <button type="button" className="icon-btn" onClick={onRefresh} aria-label="Refresh now" data-spinning={refreshing || undefined}>
          <Icon name="refresh" size={16} />
        </button>
        <button type="button" className="icon-btn" onClick={onKiosk} aria-label="Kiosk mode" title="Kiosk mode: full screen, moving through the tabs">
          <Icon name="expand" size={16} />
        </button>
        <span className="avatar" aria-label="Dylan">DW</span>
      </div>
      )}
    </header>
  )
}
