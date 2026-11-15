import { describe, expect, it } from 'vitest'
import { parseOffers } from '../../server/sources/offers.mjs'
import { createMockSource } from '../../server/sources/mock.mjs'
import { createApi } from '../../server/app.mjs'
import { callApi } from './helpers'

const ACTION_HEADER = { 'x-home-lab': '1' }

describe('parseOffers', () => {
  it('keeps plain-words offers, at most three, and drops broken or machine-looking ones', () => {
    const raw = {
      greeting: 'Well, good morning, Dylan! Tapestry plays at 9 on court 4.',
      offers: [
        { id: 'a1', title: 'Find a cover for Sunday', body: 'Sam declined. I can draft a note.', start_text: 'Draft the note.' },
        { id: 'a2', title: 'Email bob@example.com about it', start_text: 'Go' },
        { id: 'a3', title: 'No start text' },
        { id: 'a4', title: 'Two', start_text: 'Go' },
        { id: 'a5', title: 'Three', start_text: 'Go' },
        { id: 'a6', title: 'Four', start_text: 'Go' },
      ],
    }
    const parsed = parseOffers(raw)!
    expect(parsed.greeting).toMatch(/^Well, good morning/)
    expect(parsed.offers.map((o) => o.id)).toEqual(['a1', 'a4', 'a5'])
    expect(parsed.offers[0]).toMatchObject({ title: 'Find a cover for Sunday', startText: 'Draft the note.' })
  })

  it('is null for an answer that isn’t offers', () => {
    expect(parseOffers(null)).toBeNull()
    expect(parseOffers({ offers: 'x' })).toBeNull()
  })
})

describe('POST /api/jarvis/offers/hide', () => {
  it('needs the page header and an id, then the offer is gone from the snapshot', async () => {
    const api = createApi(createMockSource())
    const before = (await callApi(api, 'GET', '/api/snapshot')).json().offers.offers
    const id = before[0].id
    expect((await callApi(api, 'POST', '/api/jarvis/offers/hide', {}, JSON.stringify({ id }))).statusCode).toBe(403)
    expect((await callApi(api, 'POST', '/api/jarvis/offers/hide', ACTION_HEADER, JSON.stringify({ id: 'bad id!' }))).statusCode).toBe(400)
    expect((await callApi(api, 'POST', '/api/jarvis/offers/hide', ACTION_HEADER, JSON.stringify({ id }))).json()).toEqual({ ok: true, message: 'Hidden' })
    const after = (await callApi(api, 'GET', '/api/snapshot')).json().offers.offers
    expect(after.map((o: { id: string }) => o.id)).not.toContain(id)
  })

  it('Start passes the offer to Jarvis with the chat', async () => {
    let seen: unknown = null
    const source = { ...createMockSource(), chat: async (_t: string, caller: unknown, onEvent: (e: unknown) => void) => { seen = caller; onEvent({ type: 'done', ok: true }) } }
    const api = createApi(source)
    await callApi(api, 'POST', '/api/jarvis/chat', ACTION_HEADER, JSON.stringify({ text: 'Draft it', offerId: 'o-cover' }))
    expect(seen).toMatchObject({ offerId: 'o-cover' })
  })
})
