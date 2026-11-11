import { useState, type FormEvent } from 'react'
import { changeMemory, searchMemory, useMemory } from '../api/client'
import { ago } from '../lib/format'
import type { MemoryFact, MemoryHit } from '../types'
import { ConfirmDialog } from './ConfirmDialog'
import { Spinner } from './Spinner'

// What Jarvis remembers, on the Settings page. Two parts:
//   - Facts: the short notes Jarvis keeps in mind in every conversation,
//     picked up from chats by the 3:30 am pass or told to him here. Each can
//     be forgotten (after a confirm), and new ones added.
//   - Search: the same search Jarvis runs before he answers, over every
//     saved conversation (Telegram, Siri, this page, voice).
// His private memory.md is never shown or changed here.

/** Where a past moment came from, in words. */
function chatName(chat: string): string {
  if (chat === 'web') return 'This page'
  if (chat === 'voice') return 'Voice'
  if (chat === 'siri') return 'Siri'
  if (chat.startsWith('tg') || chat === 'telegram') return 'Telegram'
  return chat || 'Chat'
}

/** "Learned overnight" or "You told him", with how long ago. */
function factMeta(fact: MemoryFact, now: Date): string {
  const when = fact.learned ? ago(fact.learned, now) : ''
  const how = fact.from === 'you' ? 'You told him' : 'Learned from a chat'
  return when ? `${how} · ${when}` : how
}

/** The panel. */
export function MemoryPanel({ now }: { now: Date }) {
  const { data: memory, error, isLoading, mutate } = useMemory()
  const [adding, setAdding] = useState('')
  const [saving, setSaving] = useState(false)
  const [note, setNote] = useState('')
  const [forgetting, setForgetting] = useState<MemoryFact | null>(null)
  const [forgetBusy, setForgetBusy] = useState(false)
  const [forgetError, setForgetError] = useState<string | null>(null)
  const [query, setQuery] = useState('')
  const [searching, setSearching] = useState(false)
  const [hits, setHits] = useState<MemoryHit[] | null>(null)

  /** Tells Jarvis to remember what's in the box. */
  async function remember(e: FormEvent) {
    e.preventDefault()
    const text = adding.trim()
    if (!text || saving) return
    setSaving(true)
    const result = await changeMemory({ op: 'remember', text })
    setSaving(false)
    setNote(result.message)
    if (result.ok) {
      setAdding('')
      await mutate()
    }
  }

  /** Forgets the fact the confirm dialog is about. */
  async function forget() {
    if (!forgetting) return
    setForgetBusy(true)
    setForgetError(null)
    const result = await changeMemory({ op: 'forget', id: forgetting.id })
    setForgetBusy(false)
    if (!result.ok) {
      setForgetError(result.message)
      return
    }
    setForgetting(null)
    setNote('Forgotten')
    await mutate()
  }

  /** Searches past conversations for what's in the search box. */
  async function search(e: FormEvent) {
    e.preventDefault()
    const q = query.trim()
    if (!q || searching) return
    setSearching(true)
    setHits(await searchMemory(q))
    setSearching(false)
  }

  let body
  if (isLoading) {
    body = <div className="memory__wait"><Spinner label="Asking Jarvis what he remembers…" /></div>
  } else if (error || memory === null || memory === undefined) {
    body = <p className="empty">Jarvis isn’t answering, so his memory can’t be shown right now. Open this page through Tailscale, with Jarvis running on the PC.</p>
  } else {
    body = (
      <>
        {memory.facts.length === 0 ? (
          <p className="empty">Nothing yet. Jarvis picks things up from your chats every night at 3:30 am.</p>
        ) : (
          <ul className="memory__facts" aria-label="Things Jarvis remembers">
            {memory.facts.map((f) => (
              <li key={f.id} className="memory__fact">
                <div>
                  <p className="memory__text">{f.text}</p>
                  <p className="memory__meta">{factMeta(f, now)}</p>
                </div>
                <button type="button" className="btn btn--quiet" aria-label={`Forget: ${f.text}`} onClick={() => { setForgetError(null); setForgetting(f) }}>Forget</button>
              </li>
            ))}
          </ul>
        )}
        <form className="memory__form" onSubmit={remember}>
          <label htmlFor="memory-add" className="jarvis__label">Something for Jarvis to remember</label>
          <input
            id="memory-add"
            className="jarvis__input"
            value={adding}
            onChange={(e) => setAdding(e.target.value)}
            placeholder="Tell Jarvis something to remember"
            autoComplete="off"
            maxLength={500}
            disabled={saving}
          />
          <button type="submit" className="btn btn--primary" disabled={saving || !adding.trim()}>Remember</button>
        </form>
        {saving ? <div className="memory__wait"><Spinner label="Saving…" /></div> : null}
        <p className="cloud__foot" role="status">
          {note || `${memory.turns.toLocaleString()} conversation turns saved for search${memory.lastDistill ? ` · last learned ${ago(memory.lastDistill, now)}` : ''}`}
        </p>
      </>
    )
  }

  return (
    <section className="glass panel memory" aria-labelledby="memory-title">
      <h2 id="memory-title" className="panel__title">What Jarvis remembers</h2>
      <p className="panel__sub">He keeps these in mind in every conversation. Each night at 3:30 am he adds what he picked up from your chats. Stays on the PC.</p>
      {body}

      <h3 className="memory__heading">Search past conversations</h3>
      <p className="panel__sub">The same search Jarvis runs before he answers you, across Telegram, Siri, voice and this page.</p>
      <form className="memory__form" onSubmit={search} role="search">
        <label htmlFor="memory-search" className="jarvis__label">Search past conversations</label>
        <input
          id="memory-search"
          className="jarvis__input"
          type="search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="e.g. volleyball, the big light"
          autoComplete="off"
          disabled={searching}
        />
        <button type="submit" className="btn" disabled={searching || !query.trim()}>Search</button>
      </form>
      {searching ? <div className="memory__wait"><Spinner label="Searching past conversations…" /></div> : null}
      {hits !== null && !searching ? (
        hits.length === 0 ? (
          <p className="empty">Nothing found for “{query.trim()}”.</p>
        ) : (
          <ul className="memory__hits" aria-label="Search results">
            {hits.map((h, i) => (
              <li key={i} className="memory__hit">
                <p className="memory__text">{h.text}</p>
                <p className="memory__meta">{h.role === 'user' ? 'You' : 'Jarvis'} · {chatName(h.chat)}{h.at ? ` · ${ago(h.at, now)}` : ''}</p>
              </li>
            ))}
          </ul>
        )
      ) : null}

      {forgetting ? (
        <ConfirmDialog
          title="Forget this?"
          body={`Jarvis will stop keeping “${forgetting.text}” in mind. Your past conversations stay searchable.`}
          confirmLabel="Forget"
          busyLabel="Forgetting…"
          busy={forgetBusy}
          error={forgetError}
          onConfirm={() => void forget()}
          onClose={() => setForgetting(null)}
        />
      ) : null}
    </section>
  )
}
