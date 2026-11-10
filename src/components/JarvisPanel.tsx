import { useState, type FormEvent } from 'react'
import { askJarvis } from '../api/client'
import { Spinner } from './Spinner'

// The Ask Jarvis box: type a question, Jarvis answers through the same
// /ask endpoint the Siri Shortcut uses. The page keeps this visit's
// questions and answers; Jarvis keeps its own memory.

interface Turn { id: number; question: string; answer: string; ok: boolean }

/** The panel, with this visit's conversation, newest at the bottom. */
export function JarvisPanel() {
  const [text, setText] = useState('')
  const [busy, setBusy] = useState(false)
  const [turns, setTurns] = useState<Turn[]>([])

  /** Sends the question and adds Jarvis's answer (or why it failed). */
  async function send(e: FormEvent) {
    e.preventDefault()
    const question = text.trim()
    if (!question || busy) return
    setBusy(true)
    let answer: string
    let ok = false
    try {
      const result = await askJarvis(question)
      answer = result.message
      ok = result.ok
    } catch (err) {
      answer = err instanceof Error ? err.message : 'The request failed'
    }
    setTurns((t) => [...t, { id: t.length, question, answer, ok }])
    setText('')
    setBusy(false)
  }

  return (
    <section className="glass panel jarvis" aria-labelledby="jarvis-title">
      <header className="panel__head">
        <div>
          <h2 id="jarvis-title" className="panel__title">Ask Jarvis</h2>
          <p className="panel__sub">Same Jarvis as Telegram and Siri</p>
        </div>
      </header>
      {turns.length > 0 ? (
        <ol className="jarvis__turns" aria-live="polite">
          {turns.map((t) => (
            <li key={t.id} className="jarvis__turn">
              <p className="jarvis__q">{t.question}</p>
              <p className={t.ok ? 'jarvis__a' : 'jarvis__a jarvis__a--error'}>{t.answer}</p>
            </li>
          ))}
        </ol>
      ) : null}
      <form className="jarvis__form" onSubmit={send}>
        <label htmlFor="jarvis-input" className="jarvis__label">Question for Jarvis</label>
        <input
          id="jarvis-input"
          className="jarvis__input"
          value={text}
          onChange={(e) => setText(e.target.value)}
          placeholder="Turn off the living room lamp"
          autoComplete="off"
          disabled={busy}
        />
        <button type="submit" className="btn btn--primary" disabled={busy || !text.trim()}>Ask</button>
      </form>
      {busy ? <Spinner label="Jarvis is thinking…" /> : null}
    </section>
  )
}
