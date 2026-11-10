import { Icon } from '../components/Icon'

// The Shell page: a terminal on jarvis, in a frame. The terminal is ttyd
// running tmux on the PC, reached through the page's own server at /shell/
// (server/shell.mjs), which lets in only the Tailscale logins in
// SHELL_USERS. tmux keeps the session, so a long command carries on if the
// phone locks, and the same session is there next time.

const SHELL_URL = './shell/'
// The shareable preview has no server behind it, so no terminal either.
const IS_STATIC_BUILD = import.meta.env.VITE_DATA === 'static'

/** The Shell page. */
export function Shell() {
  return (
    <>
      <section className="hero hero--small">
        <h1 className="hero__title">Shell</h1>
        <p className="hero__sub">A terminal on jarvis as dwong. It keeps running when you leave.</p>
      </section>
      <section className="glass panel terminal" aria-labelledby="terminal-title">
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
    </>
  )
}
