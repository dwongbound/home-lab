import { describe, expect, it } from 'vitest'
import { createApi } from '../../server/app.mjs'
import { REPLY_QUOTE_MAX, parseHistory, parseReplyTo } from '../../server/sources/history.mjs'
import { createMockSource } from '../../server/sources/mock.mjs'
import { callApi } from './helpers'

const ACTION_HEADER = { 'x-home-lab': '1' }

describe('parseReplyTo', () => {
  it('takes a turn id as a number or text, and nothing at all', () => {
    expect(parseReplyTo(412)).toBe(412)
    expect(parseReplyTo('412')).toBe(412)
    expect(parseReplyTo(undefined)).toBeUndefined()
    expect(parseReplyTo(null)).toBeUndefined()
  })

  it('refuses anything that is not a turn id', () => {
    for (const bad of [0, -3, 1.5, '', 'abc', '12 ', {}, [], true]) {
      expect(parseReplyTo(bad)).toBeNull()
    }
  })
})

describe('parseHistory with replies', () => {
  it('keeps which message a turn replies to, with a short quote', () => {
    const long = 'x'.repeat(REPLY_QUOTE_MAX + 50)
    const parsed = parseHistory({
      turns: [
        { id: 7, role: 'assistant', text: 'Dinner is at 7.', at: 't1' },
        { id: 8, role: 'user', text: 'AM or PM?', at: 't2', reply_to: { id: 7, role: 'assistant', text: 'Dinner is at 7.' } },
        { id: 9, role: 'user', text: 'and this', at: 't3', reply_to: { id: 2, role: 'user', text: long } },
        { id: 10, role: 'user', text: 'broken', at: 't4', reply_to: { id: 'seven', text: 'x' } },
        { id: 11, role: 'user', text: 'no quote', at: 't5', reply_to: { id: 7 } },
      ],
    })
    const turns = parsed.turns as unknown as Array<{ replyTo?: unknown }>
    expect(turns[0].replyTo).toBeUndefined()
    expect(turns[1].replyTo).toEqual({ id: 7, role: 'jarvis', text: 'Dinner is at 7.' })
    expect(turns[2].replyTo).toEqual({ id: 2, role: 'user', text: 'x'.repeat(REPLY_QUOTE_MAX) })
    expect(turns[3].replyTo).toBeUndefined()
    expect(turns[4].replyTo).toBeUndefined()
  })
})

describe('POST /api/jarvis/chat with replyTo', () => {
  it('passes the turn being replied to on to the source', async () => {
    let seen: { replyTo?: number } = {}
    const source = {
      ...createMockSource(),
      chat: async (_text: string, caller: { replyTo?: number }, onEvent: (e: unknown) => void) => {
        seen = caller
        onEvent({ type: 'done', ok: true })
      },
    }
    const api = createApi(source)
    const res = await callApi(api, 'POST', '/api/jarvis/chat', ACTION_HEADER, JSON.stringify({ text: 'AM or PM?', replyTo: 7 }))
    expect(res.statusCode).toBe(200)
    expect(seen.replyTo).toBe(7)
    await callApi(api, 'POST', '/api/jarvis/chat', ACTION_HEADER, JSON.stringify({ text: 'plain' }))
    expect(seen.replyTo).toBeUndefined()
  })

  it('answers 400 in plain words when replyTo is not a turn id', async () => {
    const api = createApi(createMockSource())
    const res = await callApi(api, 'POST', '/api/jarvis/chat', ACTION_HEADER, JSON.stringify({ text: 'hi', replyTo: 'that one' }))
    expect(res.statusCode).toBe(400)
    expect(res.json().message).toContain('replyTo')
  })

  it('shows the quoted message on the reply in the sample history', async () => {
    const api = createApi(createMockSource())
    await callApi(api, 'POST', '/api/jarvis/chat', ACTION_HEADER, JSON.stringify({ text: 'is the lamp on?' }))
    await callApi(api, 'POST', '/api/jarvis/chat', ACTION_HEADER, JSON.stringify({ text: 'turn it off then', replyTo: 2 }))
    const turns = (await callApi(api, 'GET', '/api/jarvis/history')).json().turns
    expect(turns[2].replyTo).toMatchObject({ id: 2, role: 'jarvis' })
    expect(turns[2].replyTo.text.length).toBeGreaterThan(0)
  })
})
