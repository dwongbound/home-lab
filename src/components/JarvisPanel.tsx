import { useEffect, useRef, useState, type FormEvent, type RefObject } from 'react'
import { loadChatHistory, streamJarvis } from '../api/client'
import type { ChatTurn } from '../types'
import { readSpeak, writeSpeak } from '../lib/prefs'
import { canSpeak, speak, stopSpeaking } from '../lib/speech'
import { openTalkLine, talkUrl, type TalkLine } from '../lib/talk'
import { JarvisOrb, type OrbHandle, type OrbState } from './JarvisOrb'

// Talking to Jarvis from the home page. The Overview keeps a slim bar: the
// orb, a box, Ask and Talk. Asking opens the chat: a fixed-size sheet with a
// big orb that thinks while Jarvis works and pulses as the reply types out
// (and with the voice, when "Speak replies" is on). Talk makes it hands-free:
// the orb follows your voice while Jarvis listens, he answers out loud in
// his own voice from the PC, and it listens again until you stop (talk
// over him and he stops). The conversation outlives closing the sheet and
// changing pages, for this visit.

interface Turn { id: number; question: string; answer: string; ok: boolean; done: boolean }

// Kept outside React so the conversation survives the Overview unmounting
// when Dylan visits another page and comes back.
let savedTurns: Turn[] = []

/** What the orb's status line says in each state; when idle, why Talk ended (if it ended by itself). */
function statusText(state: OrbState, notice = ''): string {
  if (state === 'idle' && notice) return notice
  if (state === 'thinking') return 'Jarvis is thinking…'
  if (state === 'speaking') return 'Jarvis is answering'
  if (state === 'listening') return 'Listening… just talk'
  return 'Type below, or tap Talk'
}

// With sample data there's no Jarvis to talk to, so Talk plays these turns
// and the whole hands-free loop can still be seen (the preview, and tests).
const DEMO_QUESTIONS = ["What's on my schedule today?", 'Is the living room lamp on?', "How's the weather for flying tomorrow?"]

/** Pairs saved chat lines into question-and-answer turns for the sheet. */
function toTurns(lines: ChatTurn[]): Turn[] {
  const turns: Turn[] = []
  for (const line of lines) {
    if (line.role === 'user') {
      turns.push({ id: turns.length, question: line.text, answer: '', ok: true, done: true })
    } else if (turns.length > 0 && turns[turns.length - 1].answer === '') {
      turns[turns.length - 1].answer = line.text
    }
  }
  return turns
}

/** Waits ms milliseconds. */
function wait(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

interface Props {
  /** True with live data: Talk opens the real voice line to Jarvis. Otherwise it plays the demo. */
  live: boolean
}

/** The bar on the Overview, plus the chat sheet it opens. */
export function JarvisPanel({ live }: Props) {
  const [text, setText] = useState('')
  const [state, setState] = useState<OrbState>('idle')
  const [turns, setTurnsState] = useState<Turn[]>(savedTurns)
  const [open, setOpen] = useState(false)
  const [speakOn, setSpeakOn] = useState(readSpeak)
  const [talkingOn, setTalkingOn] = useState(false)
  const [heard, setHeard] = useState('')
  // Why Talk ended by itself (no microphone, the line dropped), shown in the status line.
  const [notice, setNotice] = useState('')
  const barOrb = useRef<OrbHandle>(null)
  const sheetOrb = useRef<OrbHandle>(null)
  // Refs, not state, because the talk loop reads them between awaits.
  const talking = useRef(false)
  const line = useRef<TalkLine | null>(null)
  // The turn the voice line is answering right now.
  const talkTurn = useRef(-1)
  const busy = state !== 'idle' || talkingOn

  /** Updates the turns here and in the copy that outlives this page. */
  function setTurns(update: (t: Turn[]) => Turn[]) {
    setTurnsState((t) => { savedTurns = update(t); return savedTurns })
  }

  /** One beat on both orbs (the bar's is visible behind the sheet's backdrop). */
  function pulse(amount: number) {
    barOrb.current?.pulse(amount)
    sheetOrb.current?.pulse(amount)
  }

  /** Sends the box's question from either form. */
  function send(e: FormEvent) {
    e.preventDefault()
    const question = text.trim()
    if (!question || busy) return
    setText('')
    setOpen(true)
    void ask(question, speakOn)
  }

  /** Asks one question, types out the reply, and reads it aloud if asked. */
  async function ask(question: string, aloud: boolean) {
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
    if (result.ok && aloud && canSpeak()) {
      setState('speaking')
      await speak(answer, () => pulse(0.6 + Math.random() * 0.4))
    }
    setState('idle')
  }

  /** Hands-free Talk: the real voice line with live data, the demo otherwise. */
  async function startTalk() {
    if (talking.current) return
    talking.current = true
    setTalkingOn(true)
    setOpen(true)
    setNotice('')
    if (live) await openLine()
    else await demoLoop()
  }

  /** Updates the turn the voice line is answering. */
  function updateTalkTurn(change: (t: Turn) => Turn) {
    const id = talkTurn.current
    setTurns((t) => t.map((x) => (x.id === id ? change(x) : x)))
  }

  /**
   * Opens the voice line. From then on Jarvis drives: he says when he's
   * listening, thinking or speaking, what he heard, and his reply, and the
   * orb follows whichever voice matters.
   */
  async function openLine() {
    setState('listening')
    try {
      line.current = await openTalkLine(talkUrl(window.location), {
        onState: (s) => { if (talking.current) setState(s) },
        onHeard: (question) => {
          const id = savedTurns.length
          talkTurn.current = id
          setTurns((t) => [...t, { id, question, answer: '', ok: true, done: false }])
        },
        onReply: (added) => updateTalkTurn((x) => ({ ...x, answer: x.answer + added })),
        onDone: () => updateTalkTurn((x) => ({ ...x, done: true })),
        onInterrupted: () => updateTalkTurn((x) => ({ ...x, done: true })),
        onLevel: pulse,
        onClosed: (message) => endTalk(message),
      })
    } catch (err) {
      endTalk(err instanceof Error ? err.message : 'Talk didn’t start')
    }
    // Stopped while the line was still opening: hang it up now.
    if (!talking.current) line.current?.close()
  }

  /** Talk ended by itself; message says why. */
  function endTalk(message: string) {
    talking.current = false
    line.current = null
    setTalkingOn(false)
    setState('idle')
    setNotice(message)
  }

  /** The sample-data loop: hear a demo question, answer it out loud, and go again until stopped. */
  async function demoLoop() {
    let demo = 0
    while (talking.current) {
      setState('listening')
      const question = await demoTurn(DEMO_QUESTIONS[demo % DEMO_QUESTIONS.length])
      demo++
      setHeard('')
      if (!talking.current || question === null) break
      await ask(question, true)
    }
    setState('idle')
  }

  /** The demo's pretend turn: the words appear as if heard, with the orb following a voice. */
  async function demoTurn(question: string): Promise<string | null> {
    await wait(700)
    const words = question.split(' ')
    for (let i = 0; i < words.length; i++) {
      if (!talking.current) return null
      setHeard(words.slice(0, i + 1).join(' '))
      pulse(0.5 + Math.random() * 0.5)
      await wait(260)
    }
    await wait(600)
    return question
  }

  /** Ends hands-free talk; anything being heard or said stops. */
  function stopTalk() {
    talking.current = false
    setTalkingOn(false)
    setHeard('')
    line.current?.close()
    line.current = null
    stopSpeaking()
    // The demo loop and ask() reset the state themselves; the voice line doesn't.
    if (live) setState('idle')
  }

  /** Turns reading aloud on or off, and remembers it for this browser. */
  function toggleSpeak() {
    const next = !speakOn
    setSpeakOn(next)
    writeSpeak(next)
    if (!next) stopSpeaking()
  }

  /** Closes the sheet; talking and anything being read aloud stop. */
  function close() {
    stopTalk()
    setOpen(false)
  }

  // First visit: pick up the conversation where Jarvis left it (it lives on
  // the PC, so a reload or another device sees the same chat).
  useEffect(() => {
    if (savedTurns.length > 0) return
    let live = true
    void loadChatHistory().then((lines) => {
      if (live && savedTurns.length === 0 && lines.length > 0) setTurns(() => toTurns(lines))
    })
    return () => { live = false }
  }, [])

  // Leaving the page stops the microphone and the voice.
  useEffect(() => () => stopTalk(), [])

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
        {/* Like a messaging app: Talk while the box is empty, Ask once there's
            something typed, so the phone's narrow bar keeps a wide box. */}
        {text.trim() && !open ? (
          <button type="submit" className="btn btn--primary" disabled={busy}>Ask</button>
        ) : (
          <button type="button" className="btn" disabled={busy || open} onClick={() => void startTalk()}>Talk</button>
        )}
      </form>
      {last && !open ? (
        <button type="button" className="jarvis__last" onClick={() => setOpen(true)}>
          <span className="jarvis__last-label">Jarvis</span>
          <span className="jarvis__last-text">{last.answer || statusText(state, notice)}</span>
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
          talking={talkingOn}
          heard={heard}
          notice={notice}
          onTalk={() => void startTalk()}
          onStopTalk={stopTalk}
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
  /** Hands-free talk is on. */
  talking: boolean
  /** What's being heard right now, while listening. */
  heard: string
  /** Why Talk ended by itself, if it did. */
  notice: string
  onTalk: () => void
  onStopTalk: () => void
  onClose: () => void
}

/** The chat itself: a fixed-size native dialog, so focus and Esc come from the browser. */
function ChatSheet({ turns, state, orbRef, text, onText, onSend, speakOn, onToggleSpeak, talking, heard, notice, onTalk, onStopTalk, onClose }: SheetProps) {
  const ref = useRef<HTMLDialogElement>(null)
  const list = useRef<HTMLOListElement>(null)
  const input = useRef<HTMLInputElement>(null)
  const busy = state !== 'idle' || talking

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
  }, [turns, heard])

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
        <p className="chat__status" role="status">{statusText(state, notice)}</p>
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
        {heard ? <li className="chat__turn"><p className="chat__q chat__q--heard">{heard}</p></li> : null}
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
        <div className="chat__buttons">
          {talking ? (
            <button type="button" className="btn btn--primary" onClick={onStopTalk}>Stop talking</button>
          ) : (
            <button type="button" className="btn" disabled={state !== 'idle'} onClick={onTalk}>Talk</button>
          )}
          <button type="button" className="btn" onClick={onClose}>Close</button>
        </div>
      </div>
    </dialog>
  )
}
