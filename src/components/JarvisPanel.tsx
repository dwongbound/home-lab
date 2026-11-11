import { useEffect, useRef, useState, type FormEvent, type RefObject } from 'react'
import { streamJarvis } from '../api/client'
import { readSpeak, writeSpeak } from '../lib/prefs'
import { canSpeak, speak, stopSpeaking } from '../lib/speech'
import { JarvisOrb, type OrbHandle, type OrbState } from './JarvisOrb'

// Talking to Jarvis from the home page. The Overview keeps a slim bar: the
// orb, a box and Ask. Asking opens the chat: a fixed-size sheet with a big
// orb that thinks while Jarvis works and pulses as the reply types out (and
// with the voice, when "Speak replies" is on). The conversation outlives
// closing the sheet and changing pages, for this visit.

interface Turn { id: number; question: string; answer: string; ok: boolean; done: boolean }

// Kept outside React so the conversation survives the Overview unmounting
// when Dylan visits another page and comes back.
let savedTurns: Turn[] = []

/** What the orb's status line says in each state. */
function statusText(state: OrbState): string {
  if (state === 'thinking') return 'Jarvis is thinking…'
  if (state === 'speaking') return 'Jarvis is answering'
  return 'Jarvis is listening'
}

/** The bar on the Overview, plus the chat sheet it opens. */
export function JarvisPanel() {
  const [text, setText] = useState('')
  const [state, setState] = useState<OrbState>('idle')
  const [turns, setTurnsState] = useState<Turn[]>(savedTurns)
  const [open, setOpen] = useState(false)
  const [speakOn, setSpeakOn] = useState(readSpeak)
  const barOrb = useRef<OrbHandle>(null)
  const sheetOrb = useRef<OrbHandle>(null)
  const busy = state !== 'idle'

  /** Updates the turns here and in the copy that outlives this page. */
  function setTurns(update: (t: Turn[]) => Turn[]) {
    setTurnsState((t) => { savedTurns = update(t); return savedTurns })
  }

  /** One beat on both orbs (the bar's is visible behind the sheet's backdrop). */
  function pulse(amount: number) {
    barOrb.current?.pulse(amount)
    sheetOrb.current?.pulse(amount)
  }

  /** Sends the question, types out the reply, and reads it aloud if asked. */
  async function send(e: FormEvent) {
    e.preventDefault()
    const question = text.trim()
    if (!question || busy) return
    setOpen(true)
    setText('')
    setState('thinking')
    const id = savedTurns.length
    setTurns((t) => [...t, { id, question, answer: '', ok: true, done: false }])
    let result
    try {
      result = await streamJarvis(question, (soFar, added) => {
        setState('speaking')
        // Longer words land a little harder, so the pulse follows the text.
        pulse(Math.min(1, 0.45 + added.trim().length / 12))
        setTurns((t) => t.map((x) => (x.id === id ? { ...x, answer: soFar } : x)))
      })
    } catch (err) {
      result = { ok: false, message: err instanceof Error ? err.message : 'The request failed' }
    }
    const answer = result.message
    setTurns((t) => t.map((x) => (x.id === id ? { ...x, answer, ok: result.ok, done: true } : x)))
    if (result.ok && speakOn && canSpeak()) {
      setState('speaking')
      await speak(answer, () => pulse(0.6 + Math.random() * 0.4))
    }
    setState('idle')
  }

  /** Turns reading aloud on or off, and remembers it for this browser. */
  function toggleSpeak() {
    const next = !speakOn
    setSpeakOn(next)
    writeSpeak(next)
    if (!next) stopSpeaking()
  }

  /** Closes the sheet; anything being read aloud stops. */
  function close() {
    stopSpeaking()
    setOpen(false)
  }

  const last = turns.length > 0 ? turns[turns.length - 1] : null

  return (
    <section className="glass panel jarvis" aria-labelledby="jarvis-title">
      <h2 id="jarvis-title" className="jarvis__label">Ask Jarvis</h2>
      <JarvisOrb ref={barOrb} state={state} size={30} />
      <form className="jarvis__form" onSubmit={send}>
        <label htmlFor="jarvis-input" className="jarvis__label">Question for Jarvis</label>
        <input
          id="jarvis-input"
          className="jarvis__input"
          value={open ? '' : text}
          onChange={(e) => setText(e.target.value)}
          placeholder="Ask Jarvis anything"
          autoComplete="off"
          disabled={busy || open}
        />
        <button type="submit" className="btn btn--primary" disabled={busy || open || !text.trim()}>Ask</button>
      </form>
      {last && !open ? (
        <button type="button" className="jarvis__last" onClick={() => setOpen(true)}>
          <span className="jarvis__last-label">Jarvis</span>
          <span className="jarvis__last-text">{last.answer || statusText(state)}</span>
          <span className="jarvis__last-open">Open chat</span>
        </button>
      ) : null}
      {open ? (
        <ChatSheet
          turns={turns}
          state={state}
          orbRef={sheetOrb}
          text={text}
          onText={setText}
          onSend={send}
          speakOn={speakOn}
          onToggleSpeak={toggleSpeak}
          onClose={close}
        />
      ) : null}
    </section>
  )
}

interface SheetProps {
  turns: Turn[]
  state: OrbState
  orbRef: RefObject<OrbHandle | null>
  text: string
  onText: (v: string) => void
  onSend: (e: FormEvent) => void
  speakOn: boolean
  onToggleSpeak: () => void
  onClose: () => void
}

/** The chat itself: a fixed-size native dialog, so focus and Esc come from the browser. */
function ChatSheet({ turns, state, orbRef, text, onText, onSend, speakOn, onToggleSpeak, onClose }: SheetProps) {
  const ref = useRef<HTMLDialogElement>(null)
  const list = useRef<HTMLOListElement>(null)
  const input = useRef<HTMLInputElement>(null)
  const busy = state !== 'idle'

  // Open as a modal on mount (jsdom has no showModal, so there it's just marked open).
  useEffect(() => {
    const d = ref.current
    if (!d || d.open) return
    if (typeof d.showModal === 'function') d.showModal()
    else d.setAttribute('open', '')
    return () => { if (typeof d.close === 'function') d.close() }
  }, [])

  // Keep the newest words in view as the reply types out.
  useEffect(() => {
    const el = list.current
    if (el) el.scrollTop = el.scrollHeight
  }, [turns])

  // Back to the box once Jarvis is done, ready for the next question.
  useEffect(() => {
    if (!busy) input.current?.focus()
  }, [busy])

  return (
    <dialog
      ref={ref}
      className="dialog dialog--chat glass"
      aria-labelledby="chat-title"
      onCancel={(e) => { e.preventDefault(); onClose() }}
      onClick={(e) => { if (e.target === e.currentTarget) onClose() }}
    >
      <header className="chat__head">
        <JarvisOrb ref={orbRef} state={state} size={64} />
        <h2 id="chat-title" className="dialog__title">Jarvis</h2>
        <p className="chat__status" role="status">{statusText(state)}</p>
      </header>
      <ol ref={list} className="chat__turns" aria-live="polite">
        {turns.map((t) => (
          <li key={t.id} className="chat__turn">
            <p className="chat__q">{t.question}</p>
            {t.answer ? (
              <p className={t.ok ? 'chat__a' : 'chat__a chat__a--error'}>
                {t.answer}
                {!t.done ? <span className="chat__caret" aria-hidden="true" /> : null}
              </p>
            ) : null}
          </li>
        ))}
      </ol>
      <form className="chat__form" onSubmit={onSend}>
        <label htmlFor="chat-input" className="jarvis__label">Message Jarvis</label>
        <input
          ref={input}
          id="chat-input"
          className="jarvis__input"
          value={text}
          onChange={(e) => onText(e.target.value)}
          placeholder="Message Jarvis"
          autoComplete="off"
          disabled={busy}
        />
        <button type="submit" className="btn btn--primary" disabled={busy || !text.trim()}>Send</button>
      </form>
      <div className="dialog__actions chat__actions">
        {canSpeak() ? (
          <button type="button" role="switch" aria-checked={speakOn} className="switch chat__speak" onClick={onToggleSpeak}>
            <span className="switch__track" aria-hidden="true"><span className="switch__knob" /></span>
            Speak replies
          </button>
        ) : null}
        <button type="button" className="btn" onClick={onClose}>Close</button>
      </div>
    </dialog>
  )
}
