import { describe, expect, it, vi } from 'vitest'
import { createApi, feedbackFrom } from '../../server/app.mjs'
import { createMockSource } from '../../server/sources/mock.mjs'
import { createLiveSource } from '../../server/sources/live.mjs'
import { loadConfig } from '../../server/config.mjs'
import { callApi } from './helpers'

const ACTION_HEADER = { 'x-home-lab': '1' }

// "That was wrong" on one of Jarvis's replies.
describe('feedbackFrom', () => {
  it('needs his answer; the question and the note may be empty', () => {
    expect(feedbackFrom({ question: ' Drive to KTOA? ', answer: 'Only from your phone. ', note: '' }))
      .toEqual({ question: 'Drive to KTOA?', answer: 'Only from your phone.', note: '' })
    expect(feedbackFrom({ answer: 'x' })).toEqual({ question: '', answer: 'x', note: '' })
    expect(feedbackFrom({ question: 'q', answer: '  ' })).toBeNull()
    expect(feedbackFrom({ question: 1, answer: 'x' })).toBeNull()
    expect(feedbackFrom({ answer: 'x', note: 'n'.repeat(2001) })).toBeNull()
    expect(feedbackFrom(null)).toBeNull()
  })
})

describe('POST /api/jarvis/feedback', () => {
  it('needs the page header and an answer, then reaches Jarvis', async () => {
    const source = createMockSource()
    const api = createApi(source)
    const body = JSON.stringify({ question: 'q', answer: 'a', note: 'should be b' })
    expect((await callApi(api, 'POST', '/api/jarvis/feedback', {}, body)).statusCode).toBe(403)
    expect((await callApi(api, 'POST', '/api/jarvis/feedback', ACTION_HEADER, '{}')).statusCode).toBe(400)
    const res = await callApi(api, 'POST', '/api/jarvis/feedback', ACTION_HEADER, body)
    expect(res.json()).toEqual({ ok: true, message: 'Thanks. Jarvis will work on it tonight.' })
  })

  it('live: posts to Jarvis /feedback with his login, the time and the chat', async () => {
    const config = loadConfig({ DATA_SOURCE: 'live', HA_TOKEN: 'token' })
    const fetch = vi.fn(async () => Response.json({ ok: true, id: 'fb-1' }))
    const source = createLiveSource(config, { fetch, execFile: vi.fn(), statfs: vi.fn() })
    const flag = { question: 'q', answer: 'a', note: 'b' }
    expect(await source.sendFeedback(flag, {})).toMatchObject({ ok: false })
    expect(await source.sendFeedback(flag, { login: 'dylan@example.com' })).toMatchObject({ ok: true })
    const [url, init] = fetch.mock.calls[0] as unknown as [string, RequestInit]
    expect(url).toBe(`${config.jarvisApiUrl}/feedback`)
    expect((init.headers as Record<string, string>)['tailscale-user-login']).toBe('dylan@example.com')
    expect(JSON.parse(String(init.body))).toMatchObject({ question: 'q', answer: 'a', note: 'b', chat: 'web' })
  })
})
