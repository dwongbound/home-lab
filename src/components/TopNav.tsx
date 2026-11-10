import { Icon, type IconName } from './Icon'

// The top bar: host name on the left, pill navigation in the middle, and
// data source, refresh and avatar on the right. Navigation is plain links
// to #hashes, so it works with the keyboard, back button and bookmarks.

export type View = 'overview' | 'claude' | 'services' | 'schedule' | 'preferences'
// Settings lives at #preferences: claude.ai reserves #settings, and the
// preview page is hosted there.
export const VIEWS: { id: View; label: string; icon: IconName }[] = [
  { id: 'overview', label: 'Overview', icon: 'home' },
  { id: 'claude', label: 'Claude', icon: 'claude' },
  { id: 'services', label: 'Services', icon: 'services' },
  { id: 'schedule', label: 'Schedule', icon: 'schedule' },
  { id: 'preferences', label: 'Settings', icon: 'settings' },
]

interface Props {
  view: View
  source: 'mock' | 'live' | null
  refreshing: boolean
  onRefresh: () => void
}

/** The top bar. */
export function TopNav({ view, source, refreshing, onRefresh }: Props) {
  return (
    <header className="topbar">
      <a className="topbar__host" href="#overview" aria-label="jarvis overview">
        <span className="topbar__orb" aria-hidden="true" />
        <span>jarvis</span>
      </a>
      <nav aria-label="Sections" className="pills">
        {VIEWS.map((v) => (
          <a key={v.id} href={`#${v.id}`} className="pill" aria-current={v.id === view ? 'page' : undefined}>
            {/* The light highlight behind the active pill. Only one exists at
                a time, so a page change slides it from pill to pill. */}
            {v.id === view ? <span className="pill__glow" aria-hidden="true" /> : null}
            <Icon name={v.icon} size={16} />
            <span className="pill__label">{v.label}</span>
          </a>
        ))}
      </nav>
      <div className="topbar__end">
        {source === 'mock' ? <span className="chip" title="Numbers are made up until the live source is switched on">Sample data</span> : null}
        <button type="button" className="icon-btn" onClick={onRefresh} aria-label="Refresh now" data-spinning={refreshing || undefined}>
          <Icon name="refresh" size={16} />
        </button>
        <span className="avatar" aria-label="Dylan">DW</span>
      </div>
    </header>
  )
}
