// Jarvis's "Tasks I could help with": what he noticed and what he'd do,
// each with Hide and Start (Dylan, 2026-11-14: "this is how proactive
// jarvis should be"). Start asks him in the chat; Hide drops it for good.
import { useState } from 'react'
import { hideOffer } from '../api/client'
import type { JarvisOffer } from '../types'
import { Icon } from './Icon'

interface Props {
  offers: JarvisOffer[]
  /** Start tapped: the chat opens and Jarvis gets on with it. */
  onStart: (offer: JarvisOffer) => void
  /** True while Jarvis is answering, so a second Start waits. */
  busy: boolean
}

/** The offer cards, or nothing when there are none. */
export function OfferCards({ offers, onStart, busy }: Props) {
  // Cards tapped away here, before the next snapshot drops them.
  const [gone, setGone] = useState<Set<string>>(() => new Set())
  const [error, setError] = useState('')
  const shown = offers.filter((o) => !gone.has(o.id))
  if (shown.length === 0) return null

  /** Takes a card off the page now. */
  function drop(id: string) {
    setGone((g) => new Set(g).add(id))
  }

  /** Hide: gone now, and Jarvis is told; it comes back if he couldn't be. */
  async function hide(offer: JarvisOffer) {
    setError('')
    drop(offer.id)
    const result = await hideOffer(offer.id)
    if (!result.ok) {
      setGone((g) => { const next = new Set(g); next.delete(offer.id); return next })
      setError(result.message)
    }
  }

  /** Start: the card goes, and the chat takes over. */
  function start(offer: JarvisOffer) {
    drop(offer.id)
    onStart(offer)
  }

  return (
    <div className="offers">
      <h3 className="offers__title">Tasks I could help with</h3>
      <ul className="offers__list">
        {shown.map((offer) => (
          <li key={offer.id} className="offer">
            <div className="offer__top">
              <span className="offer__icon"><Icon name="sparkle" size={18} /></span>
              <div>
                <p className="offer__name">{offer.title}</p>
                {offer.body ? <p className="offer__body">{offer.body}</p> : null}
                {/* Start counts as him asking for exactly this, so say what it asks. */}
                <p className="offer__ask">Start asks: “{offer.startText}”</p>
              </div>
            </div>
            <div className="offer__actions">
              <button type="button" className="btn" onClick={() => void hide(offer)} aria-label={`Hide: ${offer.title}`}>Hide</button>
              <button type="button" className="btn btn--primary" disabled={busy} onClick={() => start(offer)} aria-label={`Start: ${offer.title}`}>Start</button>
            </div>
          </li>
        ))}
      </ul>
      {error ? <p className="device__error" role="alert">{error}</p> : null}
    </div>
  )
}
