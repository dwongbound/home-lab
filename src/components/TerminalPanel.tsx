import { useEffect, useRef, useState, type FormEvent } from 'react'
import { Icon } from './Icon'
import { TERM_KEYS, findTerm, sendKey, terminalText } from '../lib/terminalKeys'
import { useScrollLock } from '../useScrollLock'

// A terminal on jarvis, in a frame, on the Services page (it had its own
// Shell tab until Dylan dropped it, 2026-11-11). The terminal is ttyd
// running tmux on the PC, reached through the page's own server at /shell/
// (server/shell.mjs), which lets in only the Tailscale logins in
// SHELL_USERS. tmux keeps the session, so a long command carries on if the
// phone locks, and the same session is there next time.
// Under the frame, a key bar (Dylan, 2026-11-17): Ctrl+C and the other keys
// an iPhone keyboard lacks, plus Paste and Copy (src/lib/terminalKeys.ts).

const SHELL_URL = './shell/'
// The shareable preview has no server behind it, so no terminal either.
const IS_STATIC_BUILD = import.meta.env.VITE_DATA === 'static'
// How long "Copied" and the like stay under the keys.
const NOTE_MS = 2500

/** Which pop-up is open: paste text in by hand, or copy text out by hand. */
type ClipDialog = { mode: 'paste' } | { mode: 'copy'; text: string } | null

/**
 * The terminal panel on Services. The ↗ button opens the same tmux session
 * full screen in a new tab, so a command started in one is there in the other.
 */
export function TerminalPanel() {
  const frame = useRef<HTMLIFrameElement>(null)
  const [note, setNote] = useState('')
  const [dialog, setDialog] = useState<ClipDialog>(null)

  // Clear the note a moment after it appears.
  useEffect(() => {
    if (!note) return
    const t = window.setTimeout(() => setNote(''), NOTE_MS)
    return () => window.clearTimeout(t)
  }, [note])

  /** Sends one key, then gives the terminal focus back so typing carries on there. */
  function press(data: string) {
    const term = findTerm(frame.current)
    if (!term) {
      setNote('The terminal isn’t ready.')
      return
    }
    sendKey(term, data)
    term.focus()
  }

  /** Pastes the clipboard in; where the browser won't share it, opens a box to paste into. */
  async function paste() {
    const term = findTerm(frame.current)
    if (!term) {
      setNote('The terminal isn’t ready.')
      return
    }
    try {
      const text = await navigator.clipboard.readText()
      if (text) {
        term.paste(text)
        term.focus()
        setNote('Pasted.')
        return
      }
    } catch {
      // Refused or unsupported (e.g. Firefox): fall through to the box.
    }
    setDialog({ mode: 'paste' })
  }

  /** Copies the selection, or the whole screen; where the browser won't allow it, shows the text to copy by hand. */
  async function copy() {
    const term = findTerm(frame.current)
    if (!term) {
      setNote('The terminal isn’t ready.')
      return
    }
    const selected = term.hasSelection()
    const text = terminalText(term)
    try {
      await navigator.clipboard.writeText(text)
      setNote(selected ? 'Copied the selection.' : 'Copied the screen.')
    } catch {
      setDialog({ mode: 'copy', text })
    }
  }

  /** Types what he pasted into the box into the terminal. */
  function sendPasted(text: string) {
    const term = findTerm(frame.current)
    setDialog(null)
    if (!term || !text) return
    term.paste(text)
    term.focus()
    setNote('Pasted.')
  }

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
          <>
            <iframe ref={frame} className="shell__frame" src={SHELL_URL} title="Terminal on jarvis" />
            <div className="termkeys" role="toolbar" aria-label="Terminal keys">
              {TERM_KEYS.map((k) => (
                // preventDefault on pointer down keeps focus (and the phone keyboard) in the terminal.
                <button key={k.label} type="button" className="termkeys__key" aria-label={k.name} onPointerDown={(e) => e.preventDefault()} onClick={() => press(k.data)}>
                  {k.label}
                </button>
              ))}
              <button type="button" className="termkeys__key termkeys__key--wide" onClick={paste}>Paste</button>
              <button type="button" className="termkeys__key termkeys__key--wide" onClick={copy}>Copy</button>
            </div>
            <p className="termkeys__note" role="status">{note}</p>
          </>
        )}
        {dialog ? <ClipboardDialog dialog={dialog} onSend={sendPasted} onClose={() => setDialog(null)} /> : null}
      </section>
  )
}

/**
 * The fixed-size pop-up for when the browser won't share the clipboard:
 * a box to paste into (then Send), or the terminal's text, selected, to copy by hand.
 */
function ClipboardDialog({ dialog, onSend, onClose }: { dialog: NonNullable<ClipDialog>; onSend: (text: string) => void; onClose: () => void }) {
  const ref = useRef<HTMLDialogElement>(null)
  const box = useRef<HTMLTextAreaElement>(null)
  const [text, setText] = useState(dialog.mode === 'copy' ? dialog.text : '')
  useScrollLock()

  // Open as a modal on mount (jsdom has no showModal, so there it's just marked open);
  // the copy text starts selected so one Copy from the system menu takes it all.
  useEffect(() => {
    const d = ref.current
    if (!d || d.open) return
    if (typeof d.showModal === 'function') d.showModal()
    else d.setAttribute('open', '')
    if (dialog.mode === 'copy') box.current?.select()
    else box.current?.focus()
    return () => { if (typeof d.close === 'function') d.close() }
  }, [dialog.mode])

  /** Sends the pasted text to the terminal. */
  function submit(e: FormEvent) {
    e.preventDefault()
    onSend(text)
  }

  const pasting = dialog.mode === 'paste'
  return (
    <dialog
      ref={ref}
      className="dialog glass dialog--clip"
      aria-labelledby="clip-title"
      onCancel={(e) => { e.preventDefault(); onClose() }}
      onClick={(e) => { if (e.target === e.currentTarget) onClose() }}
    >
      <h2 id="clip-title" className="dialog__title">{pasting ? 'Paste into the terminal' : 'Copy from the terminal'}</h2>
      <form id="clip-form" className="clip" onSubmit={submit} aria-label={pasting ? 'Text to paste' : 'Text to copy'}>
        <label className="clip__label" htmlFor="clip-text">
          {pasting ? 'Paste here, then Send.' : 'Select the text and copy it.'}
        </label>
        <textarea
          id="clip-text"
          ref={box}
          className="clip__text"
          value={text}
          readOnly={!pasting}
          spellCheck={false}
          autoCapitalize="off"
          autoCorrect="off"
          onChange={(e) => setText(e.target.value)}
        />
      </form>
      <div className="dialog__actions">
        <button type="button" className="btn btn--quiet" onClick={onClose}>Close</button>
        {pasting ? <button type="submit" form="clip-form" className="btn btn--primary" disabled={!text}>Send</button> : null}
      </div>
    </dialog>
  )
}
