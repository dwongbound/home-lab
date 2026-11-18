import { describe, expect, it } from 'vitest'
import { createApi, parseChatImages } from '../../server/app.mjs'
import { createMockSource } from '../../server/sources/mock.mjs'
import { callApi } from './helpers'

const ACTION_HEADER = { 'x-home-lab': '1' }
const PHOTO = { media_type: 'image/jpeg', data: 'aGVsbG8=' }

describe('parseChatImages', () => {
  it('takes up to four base64 photos of a known kind', () => {
    expect(parseChatImages(undefined)).toEqual([])
    expect(parseChatImages([PHOTO, { type: 'image/png', data: 'AAAA' }])).toEqual([
      { type: 'image/jpeg', data: 'aGVsbG8=' },
      { type: 'image/png', data: 'AAAA' },
    ])
    expect(parseChatImages([PHOTO, PHOTO, PHOTO, PHOTO, PHOTO])).toBeNull()
    expect(parseChatImages([{ media_type: 'application/pdf', data: 'AAAA' }])).toBeNull()
    expect(parseChatImages([{ media_type: 'image/jpeg', data: 'not base64!' }])).toBeNull()
    expect(parseChatImages('photo')).toBeNull()
    expect(parseChatImages([{ media_type: 'image/heic', data: 'AAAA' }])).toBeNull()
  })
})

describe('POST /api/jarvis/chat with photos', () => {
  it('passes the photos to the source, and a photo needs no text', async () => {
    let seen: { images?: unknown[] } = {}
    let heard = 'unset'
    const source = {
      ...createMockSource(),
      chat: async (text: string, caller: { images?: unknown[] }, onEvent: (e: unknown) => void) => {
        heard = text
        seen = caller
        onEvent({ type: 'done', ok: true })
      },
    }
    const api = createApi(source)
    const res = await callApi(api, 'POST', '/api/jarvis/chat', ACTION_HEADER, JSON.stringify({ text: '', images: [PHOTO] }))
    expect(res.statusCode).toBe(200)
    expect(heard).toBe('')
    expect(seen.images).toEqual([{ type: 'image/jpeg', data: 'aGVsbG8=' }])
  })

  it('refuses a wrong kind of file, and an empty message with no photo', async () => {
    const api = createApi(createMockSource())
    const bad = JSON.stringify({ text: 'hi', images: [{ media_type: 'text/plain', data: 'AAAA' }] })
    expect((await callApi(api, 'POST', '/api/jarvis/chat', ACTION_HEADER, bad)).statusCode).toBe(400)
    expect((await callApi(api, 'POST', '/api/jarvis/chat', ACTION_HEADER, JSON.stringify({ text: ' ' }))).statusCode).toBe(400)
  })
})

describe('POST /api/jarvis/chat/meal', () => {
  it('needs the page header, a key and one of the three choices', async () => {
    const api = createApi(createMockSource())
    const answer = JSON.stringify({ key: 'm1', choice: 'leftovers' })
    expect((await callApi(api, 'POST', '/api/jarvis/chat/meal', {}, answer)).statusCode).toBe(403)
    expect((await callApi(api, 'POST', '/api/jarvis/chat/meal', ACTION_HEADER, JSON.stringify({ key: 'm1', choice: 'maybe' }))).statusCode).toBe(400)
    expect((await callApi(api, 'POST', '/api/jarvis/chat/meal', ACTION_HEADER, answer)).json()).toEqual({ ok: true, message: 'Logged as leftovers.' })
  })
})
