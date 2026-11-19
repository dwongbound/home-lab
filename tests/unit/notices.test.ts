import { describe, expect, it } from 'vitest'
import { parseClear, parseKeep, parseNotices, parsePushDevice, parseUnkeep } from '../../server/sources/notices.mjs'
import { createMockSource } from '../../server/sources/mock.mjs'
import { createApi } from '../../server/app.mjs'
import { callApi } from './helpers'

const ACTION_HEADER = { 'x-home-lab': '1' }
const TOKEN = 'ab12'.repeat(16)

describe('parseNotices', () => {
  it('keeps well-formed notices in order and drops ones with no id, kind or title', () => {
    const parsed = parseNotices({
      notices: [
        { id: 'n1', kind: 'need', title: ' Send the email? ', source: 'approval', created: '2026-11-18T08:00:00Z', approval_id: 'a1' },
        { id: 'n2', kind: 'loud', title: 'Unknown kind' },
        { id: 'bad id!', kind: 'fyi', title: 'Bad id' },
        { id: 'n3', kind: 'fyi', title: '' },
        { id: 'n4', kind: 'heads', title: 'Rain at 4', source: 'weather', created: 'soon', approval_id: 7 },
      ],
    })
    expect(parsed).toEqual([
      { id: 'n1', kind: 'need', title: 'Send the email?', body: '', source: 'approval', created: '2026-11-18T08:00:00Z', approvalId: 'a1' },
      { id: 'n4', kind: 'heads', title: 'Rain at 4', body: '', source: 'message', created: null },
    ])
  })

  it('passes on the chat turn a notice previews, when it is a whole number', () => {
    const parsed = parseNotices({
      notices: [
        { id: 'n1', kind: 'heads', title: 'Start of day', source: 'reminder', turn_id: 412 },
        { id: 'n2', kind: 'heads', title: 'No turn', turn_id: '412' },
      ],
    })
    expect(parsed?.[0]).toHaveProperty('turnId', 412)
    expect(parsed?.[1]).not.toHaveProperty('turnId')
  })

  it('is null for an answer that isn’t a list, and caps a long one at 30', () => {
    expect(parseNotices(null)).toBeNull()
    expect(parseNotices({ notices: 'x' })).toBeNull()
    const many = Array.from({ length: 40 }, (_, n) => ({ id: `n${n}`, kind: 'fyi', title: 'Done' }))
    expect(parseNotices({ notices: many })).toHaveLength(30)
  })
})

describe('parseClear and parsePushDevice', () => {
  it('takes some ids or all, and nothing else', () => {
    expect(parseClear({ all: true })).toEqual({ all: true })
    expect(parseClear({ ids: ['n1', 'n2'] })).toEqual({ ids: ['n1', 'n2'] })
    expect(parseClear({ ids: [] })).toBeNull()
    expect(parseClear({ ids: ['ok', 'not ok'] })).toBeNull()
    expect(parseClear({})).toBeNull()
  })

  it('takes a hex token for a known platform, environment and bundle', () => {
    const device = { token: TOKEN.toUpperCase(), platform: 'ios', environment: 'production', bundle: 'com.example.app', name: ' iPhone ' }
    expect(parsePushDevice(device)).toEqual({ token: TOKEN, platform: 'ios', environment: 'production', bundle: 'com.example.app', name: 'iPhone' })
    expect(parsePushDevice({ ...device, token: 'zz' })).toBeNull()
    expect(parsePushDevice({ ...device, platform: 'android' })).toBeNull()
    expect(parsePushDevice({ ...device, environment: 'test' })).toBeNull()
    expect(parsePushDevice({ ...device, bundle: 'has spaces' })).toBeNull()
  })
})

describe('POST /api/jarvis/notices/clear', () => {
  it('needs the page header and ids, then those notices are gone from the snapshot', async () => {
    const api = createApi(createMockSource())
    const before = (await callApi(api, 'GET', '/api/snapshot')).json().notices
    expect(before.map((n: { kind: string }) => n.kind)).toEqual(['need', 'heads', 'fyi'])
    const id = before[1].id
    expect((await callApi(api, 'POST', '/api/jarvis/notices/clear', {}, JSON.stringify({ ids: [id] }))).statusCode).toBe(403)
    expect((await callApi(api, 'POST', '/api/jarvis/notices/clear', ACTION_HEADER, JSON.stringify({ ids: 'n1' }))).statusCode).toBe(400)
    expect((await callApi(api, 'POST', '/api/jarvis/notices/clear', ACTION_HEADER, JSON.stringify({ ids: [id] }))).json()).toEqual({ ok: true, message: 'Cleared' })
    const after = (await callApi(api, 'GET', '/api/snapshot')).json().notices
    expect(after.map((n: { id: string }) => n.id)).toEqual([before[0].id, before[2].id])
    await callApi(api, 'POST', '/api/jarvis/notices/clear', ACTION_HEADER, JSON.stringify({ all: true }))
    expect((await callApi(api, 'GET', '/api/snapshot')).json().notices).toEqual([])
  })
})

describe('POST /api/jarvis/push/register', () => {
  it('needs the page header and a real-looking token', async () => {
    const api = createApi(createMockSource())
    const device = { token: TOKEN, platform: 'ios', environment: 'sandbox', bundle: 'com.example.app' }
    expect((await callApi(api, 'POST', '/api/jarvis/push/register', {}, JSON.stringify(device))).statusCode).toBe(403)
    expect((await callApi(api, 'POST', '/api/jarvis/push/register', ACTION_HEADER, JSON.stringify({ ...device, token: 'nope' }))).statusCode).toBe(400)
    expect((await callApi(api, 'POST', '/api/jarvis/push/register', ACTION_HEADER, JSON.stringify(device))).json()).toEqual({ ok: true, message: 'Registered' })
  })
})

describe('keeping a notice or a chat message', () => {
  it('reads kept: true off a notice and knows the "kept" source', () => {
    const raw = { notices: [{ id: 'k7', kind: 'fyi', title: 'Call the shop', source: 'kept', turn_id: 7, kept: true }, { id: 'n1', kind: 'heads', title: 'Rain', kept: 'yes' }] }
    expect(parseNotices(raw)).toEqual([
      { id: 'k7', kind: 'fyi', title: 'Call the shop', body: '', source: 'kept', created: null, turnId: 7, kept: true },
      { id: 'n1', kind: 'heads', title: 'Rain', body: '', source: 'message', created: null },
    ])
  })

  it('takes a turn id or a notice id to keep, and an id to let go', () => {
    expect(parseKeep({ turnId: 12 })).toEqual({ turnId: 12 })
    expect(parseKeep({ id: 'n1' })).toEqual({ id: 'n1' })
    expect(parseKeep({ turnId: 0 })).toBeNull()
    expect(parseKeep({ turnId: '12' })).toBeNull()
    expect(parseKeep({ id: 'has spaces' })).toBeNull()
    expect(parseKeep(null)).toBeNull()
    expect(parseUnkeep({ id: 'k12' })).toBe('k12')
    expect(parseUnkeep({ id: 5 })).toBeNull()
  })

  it('keeps a notice through Clear all, keeps a chat message once, and lets both go', async () => {
    const api = createApi(createMockSource())
    const before = (await callApi(api, 'GET', '/api/snapshot')).json().notices
    expect((await callApi(api, 'POST', '/api/jarvis/notices/keep', {}, JSON.stringify({ id: before[1].id }))).statusCode).toBe(403)
    expect((await callApi(api, 'POST', '/api/jarvis/notices/keep', ACTION_HEADER, JSON.stringify({ turn: 3 }))).statusCode).toBe(400)
    expect((await callApi(api, 'POST', '/api/jarvis/notices/keep', ACTION_HEADER, JSON.stringify({ id: 'nope' }))).statusCode).toBe(409)
    const kept = (await callApi(api, 'POST', '/api/jarvis/notices/keep', ACTION_HEADER, JSON.stringify({ id: before[1].id }))).json()
    expect(kept).toMatchObject({ ok: true, message: 'Kept', notice: { id: before[1].id, kept: true } })
    await callApi(api, 'POST', '/api/jarvis/notices/keep', ACTION_HEADER, JSON.stringify({ turnId: 12 }))
    const again = (await callApi(api, 'POST', '/api/jarvis/notices/keep', ACTION_HEADER, JSON.stringify({ turnId: 12 }))).json()
    expect(again.notice).toMatchObject({ id: 'k12', source: 'kept', turnId: 12, kept: true })
    await callApi(api, 'POST', '/api/jarvis/notices/clear', ACTION_HEADER, JSON.stringify({ all: true }))
    await callApi(api, 'POST', '/api/jarvis/notices/clear', ACTION_HEADER, JSON.stringify({ ids: ['k12'] }))
    const left = (await callApi(api, 'GET', '/api/snapshot')).json().notices
    expect(left.map((n: { id: string }) => n.id)).toEqual(['k12', before[1].id])
    expect((await callApi(api, 'POST', '/api/jarvis/notices/unkeep', {}, JSON.stringify({ id: 'k12' }))).statusCode).toBe(403)
    expect((await callApi(api, 'POST', '/api/jarvis/notices/unkeep', ACTION_HEADER, JSON.stringify({}))).statusCode).toBe(400)
    expect((await callApi(api, 'POST', '/api/jarvis/notices/unkeep', ACTION_HEADER, JSON.stringify({ id: 'k12' }))).json()).toEqual({ ok: true, message: 'Let go' })
    await callApi(api, 'POST', '/api/jarvis/notices/unkeep', ACTION_HEADER, JSON.stringify({ id: before[1].id }))
    expect((await callApi(api, 'GET', '/api/snapshot')).json().notices).toEqual([])
  })
})
