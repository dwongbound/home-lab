import { useEffect, useRef, useState, type FormEvent, type RefObject } from 'react'
import { answerApproval, loadApprovals, loadChatHistory, streamJarvis, warmJarvis, type ApprovalEvent, type ChatResult } from '../api/client'
import { CATCH_UP_EVERY_MS, CATCH_UP_MS, findAnswer } from '../lib/chatCatchUp'
import type { Approval, ApprovalBy, ApprovalOutcome, ChatTurn, RunningTask } from '../types'
import { BackgroundTasks } from './BackgroundTasks'
import { canTalkUnprompted, openTalkLine, talkUrl, type TalkLine } from '../lib/talk'
import { outcomeText, readableSummary, settledAs, toolLabel } from '../lib/approvals'
import { JarvisOrb, type OrbHandle, type OrbState } from './JarvisOrb'
import { useScrollLock } from '../useScrollLock'

// Talking to Jarvis from the home page. The Overview keeps a slim bar: the
// orb, a box, Ask and Talk. Asking opens the chat: a fixed-size sheet with a
// big orb that thinks while Jarvis works and pulses as the reply types out.
// Talk makes it hands-free (and is the only way he speaks replies aloud):
// the orb follows your voice while Jarvis listens, he answers out loud in
// his own voice from the PC, and it listens again until you stop (talk
// over him and he stops). The conversation outlives closing the sheet and
// changing pages, for this visit.

interface Turn { id: number; question: string; answer: string; ok: boolean; done: boolean; approvals?: ApprovalView[] }
/** An approval as the chat shows it: waiting, being sent, or settled (and how). */
interface ApprovalView extends Approval {
  outcome?: ApprovalOutcome
  by?: ApprovalBy
  sending?: boolean
  error?: string
}

// On /talk the orb follows the screen (Dylan, 2026-11-12): smaller on a
// phone so more words fit, bigger on an iPad or TV across the room.
// 12% of the short side, never under 40 px or over 160 px.
const TALK_PAGE_ORB = 'clamp(40px, 12vmin, 160px)'

// Kept outside React so the conversation survives the Overview unmounting
// when Dylan visits another page and comes back.
let savedTurns: Turn[] = []

/** On /talk the status line hides unless it asks for something, says it's muted, or says why Talk stopped. */
function quietStatus(page: boolean, tapToStart: boolean, waiting: boolean, state: OrbState, notice: string, muted: boolean): boolean {
  if (!page) return false
  // Slow lookups say what he's doing, so the wait doesn't feel like nothing.
  if (tapToStart || waiting || muted || state === 'working') return false
  if (state === 'idle' && notice) return false
  return true
}

/** What the orb's status line says in each state; when idle, why Talk ended (if it ended by itself). */
function statusText(state: OrbState, notice = '', page = false, tapToStart = false): string {
  if (state === 'idle' && notice) return notice
  if (state === 'thinking') return 'Jarvis is thinking…'
  if (state === 'working') return 'Jarvis is looking that up'
  if (state === 'speaking') return 'Jarvis is answering'
  if (state === 'listening') return 'Listening… just talk'
  // /talk has nothing to type in, so it only points at Talk (or anywhere, before the first tap).
  if (page && tapToStart) return 'Tap anywhere to start'
  if (page) return 'Tap Talk to start'
  return 'Type below, or tap Talk'
}

/** The chat sheet's status line: an OK it's waiting for first, then muted, then the orb's state. */
function sheetStatus(waiting: boolean, muted: boolean, state: OrbState, notice: string, page: boolean, tapToStart: boolean, workLabel: string): string {
  if (waiting) return 'Waiting for your OK'
  if (muted) return 'Muted. Jarvis can still talk.'
  if (state === 'working' && workLabel) return workLabel
  return statusText(state, notice, page, tapToStart)
}

/**
 * What the row under the bar says: his last reply, or the status while one
 * is coming, or a nudge to start once we know there's no chat yet. Blank
 * (but still taking its space) until the history has been checked.
 */
function lastLine(last: Turn | null, historyChecked: boolean, state: OrbState, notice: string): string {
  if (last) return last.answer || statusText(state, notice)
  if (historyChecked) return 'No chat yet. Ask anything, or tap Talk'
  return '\u00a0'
}

/** True on a phone or tablet, where focusing a text box opens the keyboard. */
function isTouchScreen(): boolean {
  return typeof window.matchMedia === 'function' && window.matchMedia('(pointer: coarse)').matches
}

// How close to the bottom (px) still counts as reading the newest line.
const BOTTOM_SLACK_PX = 48

/** True when a scroll box is at, or within a finger's slack of, its bottom. */
function atBottom(el: HTMLElement): boolean {
  return el.scrollHeight - el.scrollTop - el.clientHeight <= BOTTOM_SLACK_PX
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
  /**
   * The /talk page: no bar, just the chat filling the screen, ready for a
   * tap on Talk. Close goes back to the dashboard.
   */
  page?: boolean
  /** /talk: the work Dylan sent to the background, shown beside the orb until it finishes. */
  tasks?: RunningTask[]
}

/** The bar on the Overview, plus the chat sheet it opens (or, on /talk, only the sheet). */
export function JarvisPanel({ live, page = false, tasks = [] }: Props) {
  const [text, setText] = useState('')
  const [state, setState] = useState<OrbState>('idle')
  const [turns, setTurnsState] = useState<Turn[]>(savedTurns)
  // Whether the saved chat has been fetched (or wasn't needed), for the row under the bar.
  const [historyChecked, setHistoryChecked] = useState(savedTurns.length > 0)
  const [open, setOpen] = useState(page)
  // /talk only: Talk is waiting for the first tap anywhere on the screen.
  const [tapToStart, setTapToStart] = useState(false)
  const [talkingOn, setTalkingOn] = useState(false)
  // /talk's Mute (Dylan, 2026-11-12): Jarvis keeps answering and speaking, but hears nothing.
  const [mutedOn, setMutedOn] = useState(false)
  const [heard, setHeard] = useState('')
  // Why Talk ended by itself (no microphone, the line dropped), shown in the status line.
  const [notice, setNotice] = useState('')
  // What Jarvis is off doing while the orb shows working ("Searching the web.").
  const [workLabel, setWorkLabel] = useState('')
  const barOrb = useRef<OrbHandle>(null)
  const sheetOrb = useRef<OrbHandle>(null)
  // Refs, not state, because the talk loop reads them between awaits.
  const talking = useRef(false)
  const muted = useRef(false)
  const line = useRef<TalkLine | null>(null)
  // The turn the voice line is answering right now.
  const talkTurn = useRef(-1)
  const busy = state !== 'idle' || talkingOn

  /** Updates the turns here and in the copy that outlives this page. */
  function setTurns(update: (t: Turn[]) => Turn[]) {
    setTurnsState((t) => { savedTurns = update(t); return savedTurns })
  }

  /** Shows a new approval under the turn it belongs to (the latest when unsure). */
  function addApproval(turnId: number, approval: Approval) {
    setTurns((t) => {
      const target = t.some((x) => x.id === turnId) ? turnId : t[t.length - 1]?.id
      return t.map((x) => {
        if (x.id !== target) return x
        if (x.approvals?.some((a) => a.id === approval.id)) return x
        return { ...x, approvals: [...(x.approvals ?? []), approval] }
      })
    })
  }

  /** Changes one approval wherever it is in the chat. */
  function updateApproval(id: string, change: (a: ApprovalView) => ApprovalView) {
    setTurns((t) => t.map((x) => {
      if (!x.approvals?.some((a) => a.id === id)) return x
      return { ...x, approvals: x.approvals.map((a) => (a.id === id ? change(a) : a)) }
    }))
  }

  /** Marks an approval settled: Approved, Denied, or held for later ("wait"), and who answered. */
  function settleApproval(id: string, ok: boolean, by: ApprovalBy, later = false) {
    updateApproval(id, (a) => ({ ...a, outcome: settledAs(ok, later), by, sending: false, error: undefined }))
  }

  /** Hands one approval event from the reply stream to the turn it's for. */
  function onApprovalEvent(turnId: number, event: ApprovalEvent) {
    if (event.type === 'approval') addApproval(turnId, event.approval)
    else settleApproval(event.id, event.ok, event.by, event.later === true)
  }

  /** Approve or Deny tapped: tells Jarvis, and shows the answer once he has it. */
  async function answer(id: string, ok: boolean) {
    updateApproval(id, (a) => ({ ...a, sending: true, error: undefined }))
    const result = await answerApproval(id, ok)
    if (result.ok) settleApproval(id, ok, 'page')
    else updateApproval(id, (a) => ({ ...a, sending: false, error: result.message }))
  }

  /**
   * Jarvis started a slow lookup (label) or finished it (null): the orb
   * switches to its working sweep and the status says what he's doing,
   * then back to thinking until his words arrive.
   */
  function onWorking(label: string | null) {
    if (label === null) {
      setWorkLabel('')
      setState((s) => (s === 'working' ? 'thinking' : s))
      return
    }
    setWorkLabel(label)
    setState('working')
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
    void ask(question)
  }

  /** Asks one question and types out the reply. */
  async function ask(question: string) {
    setState('thinking')
    const id = savedTurns.length
    const askedAt = Date.now()
    setTurns((t) => [...t, { id, question, answer: '', ok: true, done: false }])
    let result: ChatResult
    try {
      result = await streamJarvis(
        question,
        (soFar, added) => {
          setState('speaking')
          // Longer words land a little harder, so the pulse follows the text.
          pulse(Math.min(1, 0.45 + added.trim().length / 12))
          setTurns((t) => t.map((x) => (x.id === id ? { ...x, answer: soFar } : x)))
        },
        (event) => onApprovalEvent(id, event),
        onWorking,
      )
    } catch (err) {
      result = { ok: false, message: err instanceof Error ? err.message : 'The request failed' }
    }
    if (result.dropped) result = await catchUp(id, question, askedAt, result.message)
    const answer = result.message
    setTurns((t) => t.map((x) => (x.id === id ? { ...x, answer, ok: result.ok, done: true } : x)))
    setState('idle')
  }

  /**
   * The page lost the reply stream (the phone left the page), but Jarvis
   * keeps working at home. Waits for his answer to show up in the saved
   * chat, checking while the page is on screen, and brings back any
   * approval he's waiting on. soFar is what had arrived before the drop.
   */
  async function catchUp(id: number, question: string, askedAt: number, soFar: string): Promise<ChatResult> {
    // The orb keeps thinking (or shows "Waiting for your OK") meanwhile.
    const giveUpAt = Date.now() + CATCH_UP_MS
    while (Date.now() < giveUpAt) {
      // Background tabs can't fetch on iOS anyway; check again once it's back on screen.
      if (document.visibilityState === 'visible') {
        const found = findAnswer(await loadChatHistory(), question, askedAt)
        if (found !== null) return { ok: true, message: found }
        for (const approval of await loadApprovals()) addApproval(id, approval)
      }
      await wait(CATCH_UP_EVERY_MS)
    }
    return { ok: false, message: soFar || 'Lost touch with Jarvis. Ask again, or check Telegram.' }
  }

  /** Hands-free Talk: the real voice line with live data, the demo otherwise. */
  async function startTalk() {
    if (talking.current) return
    talking.current = true
    setTalkingOn(true)
    // Each Talk starts able to hear you, whatever it was left on.
    setMute(false)
    setOpen(true)
    setNotice('')
    if (live) await openLine()
    else await demoLoop()
  }

  /** Mutes or unmutes the microphone; the line, his replies and his voice carry on. */
  function setMute(next: boolean) {
    muted.current = next
    setMutedOn(next)
    line.current?.setMuted(next)
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
        // Your words as Whisper hears them, shown while you're still talking.
        onHearing: (sofar) => { if (talking.current) setHeard(sofar) },
        onHeard: (question) => {
          setHeard('')
          const id = savedTurns.length
          talkTurn.current = id
          setTurns((t) => [...t, { id, question, answer: '', ok: true, done: false }])
        },
        onReply: (added) => updateTalkTurn((x) => ({ ...x, answer: x.answer + added })),
        onWorking: (label) => { if (talking.current) onWorking(label) },
        onDone: () => updateTalkTurn((x) => ({ ...x, done: true })),
        onInterrupted: () => updateTalkTurn((x) => ({ ...x, done: true })),
        onLevel: pulse,
        onClosed: (message) => endTalk(message),
        onApproval: (approval) => addApproval(talkTurn.current, approval),
        onApprovalDone: settleApproval,
      })
    } catch (err) {
      endTalk(err instanceof Error ? err.message : 'Talk didn’t start')
    }
    // Muted while the line was still opening: apply it now.
    line.current?.setMuted(muted.current)
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
      // Muted, the demo hears no new questions; it picks up again on Unmute.
      while (talking.current && muted.current) await wait(300)
      if (!talking.current) break
      const question = await demoTurn(DEMO_QUESTIONS[demo % DEMO_QUESTIONS.length])
      demo++
      setHeard('')
      if (!talking.current || question === null) break
      await ask(question)
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
    // The demo loop and ask() reset the state themselves; the voice line doesn't.
    if (live) setState('idle')
  }

  /** Closes the sheet; talking stops. */
  function close() {
    stopTalk()
    setOpen(false)
  }

  /** The /talk page's first tap, which lets iOS open the microphone and play sound. */
  function tapStart() {
    setTapToStart(false)
    void startTalk()
  }

  // /talk starts talking as it opens (Dylan, 2026-11-11). Where the browser
  // wants a tap first (iOS), the whole screen becomes the button instead.
  useEffect(() => {
    if (!page) return
    let gone = false
    // The demo needs no microphone, so sample data always starts straight away.
    const ready = live ? canTalkUnprompted() : Promise.resolve(true)
    void ready.then((ok) => {
      if (gone) return
      if (ok) void startTalk()
      else setTapToStart(true)
    })
    return () => { gone = true }
  }, [])

  // First visit: pick up the conversation where Jarvis left it (it lives on
  // the PC, so a reload or another device sees the same chat).
  useEffect(() => {
    if (savedTurns.length > 0) return
    let live = true
    void loadChatHistory().then(async (lines) => {
      if (!live) return
      if (savedTurns.length === 0 && lines.length > 0) setTurns(() => toTurns(lines))
      setHistoryChecked(true)
      // Anything Jarvis was still waiting on before a reload comes back as a card.
      const waiting = await loadApprovals()
      if (!live) return
      for (const approval of waiting) addApproval(-1, approval)
    })
    return () => { live = false }
  }, [])

  // Opening the sheet gets Jarvis's chat engine going while Dylan types
  // (Talk's own line does the same for voice when it connects).
  useEffect(() => {
    if (open && live) void warmJarvis()
  }, [open, live])

  // Leaving the page stops the microphone and the voice.
  useEffect(() => () => stopTalk(), [])

  const sheet = (
    <ChatSheet
      turns={turns}
      state={state}
      orbRef={sheetOrb}
      text={text}
      onText={setText}
      onSend={send}
      talking={talkingOn}
      page={page}
      tasks={tasks}
      tapToStart={tapToStart}
      onTapStart={tapStart}
      heard={heard}
      notice={notice}
      onTalk={() => void startTalk()}
      onStopTalk={stopTalk}
      muted={mutedOn}
      workLabel={workLabel}
      onMute={() => setMute(!muted.current)}
      onAnswer={(id, ok) => void answer(id, ok)}
      onClose={close}
    />
  )
  if (page) return sheet

  const last = turns.length > 0 ? turns[turns.length - 1] : null
  const lastText = lastLine(last, historyChecked, state, notice)

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
      {/* Always there, even before the history arrives, so the panels below
          don't jump down when it does (Dylan, 2026-11-11: "a little shake"). */}
      <button type="button" className="jarvis__last" onClick={() => setOpen(true)}>
        <span className="jarvis__last-label">Jarvis</span>
        <span className="jarvis__last-text">{lastText}</span>
        <span className="jarvis__last-open">Open chat</span>
      </button>
      {open ? sheet : null}
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
  /** Hands-free talk is on. */
  talking: boolean
  /** The /talk page: the sheet always fills the screen and Talk is the main button. */
  page: boolean
  /** /talk: background work to show beside the orb. */
  tasks: RunningTask[]
  /** /talk is waiting for a first tap anywhere before it can talk. */
  tapToStart: boolean
  /** That first tap. */
  onTapStart: () => void
  /** What's being heard right now, while listening. */
  heard: string
  /** Why Talk ended by itself, if it did. */
  notice: string
  onTalk: () => void
  onStopTalk: () => void
  /** /talk: the microphone is muted while Talk carries on. */
  muted: boolean
  /** /talk: Mute or Unmute tapped. */
  onMute: () => void
  /** What Jarvis is doing while the orb shows working. */
  workLabel: string
  /** Approve (true) or Deny (false) tapped on one of Jarvis's requests. */
  onAnswer: (id: string, ok: boolean) => void
  onClose: () => void
}

/**
 * The chat itself: a fixed-size native dialog, so focus and Esc come from
 * the browser. One line along the bottom: the box, then Send and Talk, or
 * Stop talking in their place while talking. Close is the × at the top right.
 */
function ChatSheet({ turns, state, orbRef, text, onText, onSend, talking, page, tasks, tapToStart, onTapStart, heard, notice, onTalk, onStopTalk, muted, onMute, workLabel, onAnswer, onClose }: SheetProps) {
  const ref = useRef<HTMLDialogElement>(null)
  useScrollLock()
  const list = useRef<HTMLOListElement>(null)
  const input = useRef<HTMLInputElement>(null)
  const busy = state !== 'idle' || talking
  // Jarvis is waiting on an Approve or Deny somewhere in the chat.
  const waiting = turns.some((t) => t.approvals?.some((a) => !a.outcome))

  // Open as a modal on mount (jsdom has no showModal, so there it's just marked open).
  useEffect(() => {
    const d = ref.current
    if (!d || d.open) return
    if (typeof d.showModal === 'function') d.showModal()
    else d.setAttribute('open', '')
    // Focus the box itself, not ×: Safari draws the focus ring on whatever
    // showModal picks, and × is first while the message box is disabled.
    if (document.activeElement !== input.current) d.focus()
    return () => { if (typeof d.close === 'function') d.close() }
  }, [])

  // Whether the chat is scrolled to (or near) the newest line. Scrolling up
  // to read back turns this off, so new words don't drag him down again
  // (Dylan, 2026-11-11); scrolling back down, or Latest, turns it on.
  const following = useRef(true)
  const [behind, setBehind] = useState(false)

  /** Notes whether he's at the bottom after he (or the page) scrolls the chat. */
  function onScroll() {
    const el = list.current
    if (!el) return
    following.current = atBottom(el)
    if (following.current) setBehind(false)
  }

  /** Jumps to the newest line and follows it again. */
  function toLatest() {
    const el = list.current
    following.current = true
    setBehind(false)
    if (el) el.scrollTop = el.scrollHeight
  }

  // Keep the newest words in view as the reply types out, unless he has
  // scrolled up; then offer Latest instead.
  useEffect(() => {
    const el = list.current
    if (!el) return
    if (following.current) el.scrollTop = el.scrollHeight
    else setBehind(true)
  }, [turns, heard])

  // A question he just typed always brings him to the bottom to see it answered.
  const turnCount = turns.length
  useEffect(() => {
    if (!talking) toLatest()
  }, [turnCount])

  // Back to the box once Jarvis is done, ready for the next question. Not
  // on a phone or tablet: there focusing pops the keyboard over the reply.
  useEffect(() => {
    if (!busy && !isTouchScreen()) input.current?.focus()
  }, [busy])

  return (
    <dialog
      ref={ref}
      // On /talk it isn't a card at all: no glass, it's the page itself.
      className={page ? 'dialog dialog--chat' : 'dialog dialog--chat glass'}
      tabIndex={-1}
      // Talk mode takes the whole screen (Dylan, 2026-11-11), with a bigger orb.
      // The /talk page always does, even before Talk is tapped.
      data-talking={talking || page ? '' : undefined}
      data-page={page ? '' : undefined}
      aria-labelledby="chat-title"
      // Esc closes the sheet; /talk is a page of its own with nothing to close.
      onCancel={(e) => { e.preventDefault(); if (!page) onClose() }}
      // A tap outside the sheet closes it, except on /talk where there's nothing outside.
      onClick={(e) => { if (!page && e.target === e.currentTarget) onClose() }}
    >
      {/* /talk has no Close (Dylan, 2026-11-11): it is the whole page. */}
      {page ? null : (
        <button type="button" className="icon-btn chat__close" aria-label="Close" onClick={onClose}>
          <svg width="16" height="16" viewBox="0 0 16 16" aria-hidden="true"><path d="M3.5 3.5l9 9M12.5 3.5l-9 9" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" /></svg>
        </button>
      )}
      <header className="chat__head">
        <JarvisOrb ref={orbRef} state={state} size={page ? TALK_PAGE_ORB : 64} />
        <h2 id="chat-title" className="dialog__title">Jarvis</h2>
        {page ? <BackgroundTasks tasks={tasks} /> : null}
        {/* /talk shows only "Jarvis" over the orb (Dylan, 2026-11-11); the status stays for
            screen readers and shows when there's something to do: a first tap, an OK, or why Talk ended. */}
        <p className="chat__status" role="status" data-quiet={quietStatus(page, tapToStart, waiting, state, notice, talking && muted) ? '' : undefined}>
          {sheetStatus(waiting, talking && muted, state, notice, page, tapToStart, workLabel)}
        </p>
      </header>
      <ol ref={list} className="chat__turns" aria-live="polite" onScroll={onScroll}>
        {turns.map((t, i) => (
          <li key={t.id} className="chat__turn">
            <p className="chat__q">{t.question}</p>
            {(t.approvals ?? []).map((a) => (
              <ApprovalCard key={a.id} approval={a} talking={talking} onAnswer={onAnswer} />
            ))}
            {t.answer ? (
              <p className={t.ok ? 'chat__a' : 'chat__a chat__a--error'}>
                {t.answer}
                {/* The cursor rides the reply as it streams, then keeps blinking after his latest one, like a terminal. */}
                {!t.done || (i === turns.length - 1 && !heard) ? <span className="chat__caret" aria-hidden="true" /> : null}
              </p>
            ) : null}
          </li>
        ))}
        {heard ? <li className="chat__turn"><p className="chat__q chat__q--heard">{heard}</p></li> : null}
      </ol>
      {behind ? (
        <button type="button" className="btn chat__latest" onClick={toLatest}>Latest ↓</button>
      ) : null}
      {page ? (
        // /talk is voice only: no typing, just one big button that talks and pauses.
        // Pausing closes the voice line, so he stops mid-sentence too; tapping again picks back up.
        <div className="chat__form chat__form--voice">
          {talking ? (
            <>
              {/* Mute stops only the microphone: he still answers and speaks (Dylan, 2026-11-12). */}
              <button type="button" className="btn chat__mute" aria-pressed={muted} onClick={onMute}>
                {muted ? 'Unmute' : 'Mute'}
              </button>
              <button type="button" className="btn btn--primary chat__voice" onClick={onStopTalk}>Pause</button>
            </>
          ) : (
            <button type="button" className="btn btn--primary chat__voice" disabled={state !== 'idle'} onClick={onTalk}>Talk</button>
          )}
        </div>
      ) : (
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
          {talking ? (
            <button type="button" className="btn btn--primary" onClick={onStopTalk}>Stop talking</button>
          ) : (
            <>
              <button type="submit" className="btn btn--primary" disabled={busy || !text.trim()}>Send</button>
              <button type="button" className="btn" disabled={state !== 'idle'} onClick={onTalk}>Talk</button>
            </>
          )}
        </form>
      )}
      {tapToStart ? (
        // Covers the whole screen so the first tap can land anywhere.
        <button type="button" className="chat__tapstart" aria-label="Tap anywhere to start" onClick={onTapStart} />
      ) : null}
    </dialog>
  )
}

/**
 * Jarvis asking before he writes a file or runs a command on the PC: what
 * he wants to do, exactly, with Approve and Deny. In Talk, saying yes or no
 * answers it too. Once settled it shrinks to the answer.
 */
function ApprovalCard({ approval: a, talking, onAnswer }: { approval: ApprovalView; talking: boolean; onAnswer: (id: string, ok: boolean) => void }) {
  return (
    <div className="approval" role="group" aria-label={`Jarvis asks: ${toolLabel(a.tool)}`} data-outcome={a.outcome}>
      <p className="approval__tool">{toolLabel(a.tool)}</p>
      <p className="approval__summary">{readableSummary(a.summary)}</p>
      {a.outcome ? (
        <p className="approval__outcome">{outcomeText(a)}</p>
      ) : (
        <div className="approval__actions">
          <button type="button" className="btn" disabled={a.sending} onClick={() => onAnswer(a.id, false)}>Deny</button>
          <button type="button" className="btn btn--primary" disabled={a.sending} onClick={() => onAnswer(a.id, true)}>Approve</button>
          {talking ? <span className="approval__hint">or say yes, no or wait</span> : null}
        </div>
      )}
      {a.error ? <p className="approval__error" role="alert">{a.error}</p> : null}
    </div>
  )
}
