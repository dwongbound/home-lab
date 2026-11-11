import { Icon } from './Icon'

// A terminal on jarvis, in a frame, on the Services page (it had its own
// Shell tab until Dylan dropped it, 2026-11-11). The terminal is ttyd
// running tmux on the PC, reached through the page's own server at /shell/
// (server/shell.mjs), which lets in only the Tailscale logins in
// SHELL_USERS. tmux keeps the session, so a long command carries on if the
// phone locks, and the same session is there next time.

const SHELL_URL = './shell/'
// The shareable preview has no server behind it, so no terminal either.
const IS_STATIC_BUILD = import.meta.env.VITE_DATA === 'static'

/**
 * The terminal panel on Services. The ↗ button opens the same tmux session
 * full screen in a new tab, so a command started in one is there in the other.
 */
export function TerminalPanel() {
  return (
      <section className="glass panel terminal terminal--compact" aria-labelledby="terminal-title">
        <header className="panel__head">
          <h2 id="terminal-title" className="panel__title">Terminal</h2>
          {IS_STATIC_BUILD ? null : (
            <a className="icon-btn shell__open" href={SHELL_URL} target="_blank" rel="noreferrer" aria-label="Open the terminal full screen">
              <Icon name="external" size={16} />
            </a>
          )}
        </header>
        {IS_STATIC_BUILD ? (
          <p className="empty">On jarvis this is a live terminal. The preview has no PC behind it.</p>
        ) : (
          <iframe className="shell__frame" src={SHELL_URL} title="Terminal on jarvis" />
        )}
      </section>
  )
}
