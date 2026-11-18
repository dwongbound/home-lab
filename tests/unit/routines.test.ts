// Routines: the words the page shows, the checks before a routine is sent
// to Jarvis, the sample source, the API routes and what the live source
// asks Jarvis for.
import { describe, expect, it, vi } from 'vitest'
import { createApi } from '../../server/app.mjs'
import { loadConfig } from '../../server/config.mjs'
import { createLiveSource } from '../../server/sources/live.mjs'
import { createMockSource } from '../../server/sources/mock.mjs'
import { cleanRoutine, fromJarvisRoutine, parseRoutineBook, toJarvisRoutine } from '../../server/sources/routines.mjs'
import { actionLine, blankAction, blankRoutine, blankTrigger, clockLabel, daysLabel, routineProblem, triggerLine } from '../../src/lib/routines'
import type { RoutineOptions } from '../../src/types'
import { callApi } from './helpers'

const PAGE = { 'x-home-lab': '1' }
const LOGIN = { ...PAGE, 'tailscale-user-login': 'dylan@example.com' }

const OPTIONS: RoutineOptions = {
  devices: [{ entity: 'light.lamp', name: 'Lamp', kind: 'light', commands: ['turn_on', 'turn_off', 'toggle'] }, { entity: 'climate.t', name: 'Thermostat', kind: 'climate', commands: ['set_temperature', 'set_hvac_mode'] }],
  scenes: [{ entity: 'scene.movie', name: 'Movie night' }],
  apps: [{ entity: 'media_player.tv', name: 'Apple TV', apps: ['Jarvis', 'Netflix'] }],
  zones: ['home'],
}

describe('routine words', () => {
  it('says when a routine runs', () => {
    expect(clockLabel('08:30')).toBe('8:30 AM')
    expect(clockLabel('00:05')).toBe('12:05 AM')
    expect(clockLabel('23:00')).toBe('11:00 PM')
    expect(daysLabel([])).toBe('every day')
    expect(daysLabel(['mon', 'tue', 'wed', 'thu', 'fri'])).toBe('weekdays')
    expect(daysLabel(['sun', 'sat'])).toBe('weekends')
    expect(daysLabel(['wed', 'mon'])).toBe('Mon, Wed')
    expect(triggerLine({ type: 'time', at: '22:15', days: [] })).toBe('At 10:15 PM, every day')
    expect(triggerLine({ type: 'arrive', zone: 'home', minAway: 15 })).toBe('When I get home after 15 min away')
    expect(triggerLine({ type: 'arrive', zone: 'home', minAway: 0 })).toBe('When I get home')
    expect(triggerLine({ type: 'asleep' })).toBe('When I go to sleep')
    expect(triggerLine({ type: 'manual' })).toBe('Only when I tap Run')
  })

  it('says what each step does, by the device’s name', () => {
    expect(actionLine({ type: 'device', entity: 'light.lamp', command: 'turn_off' }, OPTIONS)).toBe('Turn off: Lamp')
    expect(actionLine({ type: 'device', entity: 'climate.t', command: 'set_temperature', value: 66 }, OPTIONS)).toBe('Thermostat: set temperature to 66')
    expect(actionLine({ type: 'device', entity: 'light.gone', command: 'turn_on' }, OPTIONS)).toBe('Turn on: light.gone')
    expect(actionLine({ type: 'scene', entity: 'scene.movie' }, OPTIONS)).toBe('Scene: Movie night')
    expect(actionLine({ type: 'app', entity: 'media_player.tv', app: 'Jarvis' }, OPTIONS)).toBe('Open Jarvis on Apple TV')
    expect(actionLine({ type: 'email', to: 'a@b.co', subject: 'Goodnight', body: 'x', confirm: true }, OPTIONS)).toBe('Email a@b.co: Goodnight')
    expect(actionLine({ type: 'wait', seconds: 120 }, OPTIONS)).toBe('Wait 2 min')
    expect(actionLine({ type: 'wait', seconds: 45 }, OPTIONS)).toBe('Wait 45 s')
  })

  it('starts new triggers and steps sensibly, asking first for emails and Jarvis asks', () => {
    expect(blankRoutine()).toEqual({ name: '', enabled: true, trigger: { type: 'manual' }, actions: [] })
    expect(blankTrigger('arrive')).toEqual({ type: 'arrive', zone: 'home', minAway: 15 })
    expect(blankAction('device', OPTIONS)).toEqual({ type: 'device', entity: 'light.lamp', command: 'turn_on' })
    expect(blankAction('app', OPTIONS)).toEqual({ type: 'app', entity: 'media_player.tv', app: 'Jarvis' })
    expect(blankAction('email', OPTIONS)).toMatchObject({ confirm: true })
    expect(blankAction('ask', OPTIONS)).toMatchObject({ confirm: true })
  })

  it('says what a routine is missing before it can be saved', () => {
    const draft = blankRoutine()
    expect(routineProblem(draft)).toBe('Give the routine a name')
    draft.name = 'Bedtime'
    expect(routineProblem(draft)).toBe('Add at least one step')
    draft.actions = [{ type: 'device', entity: 'light.lamp', command: 'turn_off' }, { type: 'email', to: 'nobody', subject: 's', body: 'b', confirm: true }]
    expect(routineProblem(draft)).toBe('Step 2: check the email address')
    draft.actions[1] = { type: 'device', entity: 'climate.t', command: 'set_temperature' }
    expect(routineProblem(draft)).toBe('Step 2: give it a value')
    draft.actions[1] = { type: 'notify', text: 'Night' }
    expect(routineProblem(draft)).toBeNull()
  })
})

describe('checking a routine before Jarvis gets it', () => {
  const good = {
    name: '  Bedtime  ',
    trigger: { type: 'time', at: '22:30', days: ['sun', 'mon', 'nope'] },
    actions: [
      { type: 'device', entity: 'light.lamp', command: 'turn_off', extra: 'dropped' },
      { type: 'email', to: 'a@b.co', subject: 'Night', body: 'Going to bed' },
      { type: 'wait', seconds: 99999 },
    ],
  }

  it('trims, orders the days, caps a wait, and asks first unless told not to', () => {
    const { routine } = cleanRoutine(good)
    expect(routine).toEqual({
      name: 'Bedtime',
      enabled: true,
      trigger: { type: 'time', at: '22:30', days: ['mon', 'sun'] },
      actions: [
        { type: 'device', entity: 'light.lamp', command: 'turn_off' },
        { type: 'email', to: 'a@b.co', subject: 'Night', body: 'Going to bed', confirm: true },
        { type: 'wait', seconds: 600 },
      ],
    })
    const quiet = cleanRoutine({ ...good, actions: [{ type: 'ask', text: 'Lock up', confirm: false }] })
    expect(quiet.routine!.actions[0].confirm).toBe(false)
  })

  it('says what is wrong in plain words', () => {
    expect(cleanRoutine(null).problem).toBe('Give the routine a name')
    expect(cleanRoutine({ ...good, trigger: { type: 'time', at: '25:00' } }).problem).toBe('Pick when the routine should run')
    expect(cleanRoutine({ ...good, trigger: { type: 'full-moon' } }).problem).toBe('Pick when the routine should run')
    expect(cleanRoutine({ ...good, actions: [] }).problem).toBe('Add at least one step')
    expect(cleanRoutine({ ...good, actions: Array(21).fill({ type: 'wait', seconds: 1 }) }).problem).toBe('A routine can have up to 20 steps')
    expect(cleanRoutine({ ...good, actions: [good.actions[0], { type: 'email', to: 'nobody', subject: 's', body: 'b' }] }).problem).toBe('Step 2 is missing something')
    expect(cleanRoutine({ ...good, actions: [{ type: 'unlock-door' }] }).problem).toBe('Step 1 is missing something')
  })

  it('speaks Jarvis’s words on the way out and the page’s on the way back', () => {
    const arrive = cleanRoutine({ name: 'Home', trigger: { type: 'arrive', minAway: 5000 }, actions: [{ type: 'scene', entity: 'scene.movie' }] }).routine!
    expect(arrive.trigger).toEqual({ type: 'arrive', zone: 'home', minAway: 1440 })
    expect(toJarvisRoutine(arrive).trigger).toEqual({ type: 'arrive', zone: 'home', min_away: 1440 })
    // Several addresses go to Jarvis as a list and come back as one line.
    const mail = cleanRoutine({ name: 'Night', trigger: { type: 'asleep' }, actions: [{ type: 'email', to: 'a@b.co ,c@d.co', subject: 's', body: 'b' }] }).routine!
    expect(mail.actions[0]).toMatchObject({ to: 'a@b.co, c@d.co' })
    expect(toJarvisRoutine(mail).actions[0]).toMatchObject({ to: ['a@b.co', 'c@d.co'] })
    expect(fromJarvisRoutine({ id: 'x', name: 'Night', actions: [{ type: 'email', to: ['a@b.co', 'c@d.co'] }] })!.actions[0]).toMatchObject({ to: 'a@b.co, c@d.co' })
    const back = fromJarvisRoutine({ id: 'r1', name: 'Home', trigger: { type: 'arrive', zone: 'home', min_away: 20 }, actions: [{ type: 'scene', entity: 'scene.movie' }, 'junk'], last_run: { at: '2026-11-18T08:00:00Z', ok: false, detail: 'TV did not answer' } })
    expect(back).toEqual({
      id: 'r1',
      name: 'Home',
      enabled: true,
      trigger: { type: 'arrive', zone: 'home', minAway: 20 },
      actions: [{ type: 'scene', entity: 'scene.movie' }],
      lastRun: { at: '2026-11-18T08:00:00Z', ok: false, detail: 'TV did not answer' },
    })
    expect(fromJarvisRoutine({ name: 'no id' })).toBeNull()
  })

  it('keeps only the well-formed parts of Jarvis’s answer', () => {
    const book = parseRoutineBook({
      routines: [{ id: 'r1', name: 'Bedtime', trigger: { type: 'time', at: '22:00' }, actions: [] }, { nope: true }],
      options: { devices: [{ entity: 'light.lamp', name: 'Lamp', kind: 'light', commands: ['turn_on', 7] }, { name: 'no entity' }], apps: [{ entity: 'media_player.tv' }], zones: ['home', 3] },
    })
    expect(book.routines).toHaveLength(1)
    expect(book.routines[0].trigger).toEqual({ type: 'time', at: '22:00', days: [] })
    expect(book.options).toEqual({
      devices: [{ entity: 'light.lamp', name: 'Lamp', kind: 'light', commands: ['turn_on'] }],
      scenes: [],
      apps: [{ entity: 'media_player.tv', name: 'media_player.tv', apps: [] }],
      zones: ['home'],
    })
    expect(parseRoutineBook(null)).toEqual({ routines: [], options: { devices: [], scenes: [], apps: [], zones: [] } })
  })
})

describe('/api/jarvis/routines (sample data)', () => {
  it('lists the routines with what their steps can use', async () => {
    const book = (await callApi(createApi(createMockSource()), 'GET', '/api/jarvis/routines')).json().book
    expect(book.routines.map((r: { name: string }) => r.name)).toEqual(['Bedtime', 'Arrive home', 'Weekday morning'])
    expect(book.options.devices.length).toBeGreaterThan(0)
    expect(book.options.apps[0].apps).toContain('Jarvis')
  })

  it('saves a new one, edits it, runs it and deletes it', async () => {
    const api = createApi(createMockSource())
    const names = async () => (await callApi(api, 'GET', '/api/jarvis/routines')).json().book.routines.map((r: { name: string }) => r.name)
    const routine = { name: 'Lights out', trigger: { type: 'manual' }, actions: [{ type: 'notify', text: 'Night' }] }

    expect((await callApi(api, 'POST', '/api/jarvis/routines', {}, JSON.stringify({ op: 'save', routine }))).statusCode).toBe(403)
    expect((await callApi(api, 'POST', '/api/jarvis/routines', PAGE, JSON.stringify({ op: 'save', routine: { ...routine, actions: [] } }))).json().message).toBe('Add at least one step')
    expect((await callApi(api, 'POST', '/api/jarvis/routines', PAGE, '{"op":"explode","id":"r1"}')).statusCode).toBe(400)
    expect((await callApi(api, 'POST', '/api/jarvis/routines', PAGE, '{"op":"run"}')).statusCode).toBe(400)

    expect((await callApi(api, 'POST', '/api/jarvis/routines', PAGE, JSON.stringify({ op: 'save', routine }))).json()).toEqual({ ok: true, message: 'Saved' })
    expect(await names()).toContain('Lights out')
    await callApi(api, 'POST', '/api/jarvis/routines', PAGE, JSON.stringify({ op: 'save', routine: { ...routine, id: 'r10', name: 'Lights off' } }))
    expect(await names()).toEqual(['Bedtime', 'Arrive home', 'Weekday morning', 'Lights off'])

    expect((await callApi(api, 'POST', '/api/jarvis/routines', PAGE, '{"op":"run","id":"r10"}')).json()).toEqual({ ok: true, message: 'Ran 1 step' })
    const ran = (await callApi(api, 'GET', '/api/jarvis/routines')).json().book.routines[3]
    expect(ran.lastRun.ok).toBe(true)

    expect((await callApi(api, 'POST', '/api/jarvis/routines', PAGE, '{"op":"delete","id":"r10"}')).json().ok).toBe(true)
    expect(await names()).not.toContain('Lights off')
    expect((await callApi(api, 'POST', '/api/jarvis/routines', PAGE, '{"op":"delete","id":"r10"}')).statusCode).toBe(502)
  })
})

describe('routines from the real Jarvis', () => {
  const config = loadConfig({ DATA_SOURCE: 'live', HA_TOKEN: 'token' })

  /** An API over a live source whose Jarvis answers with `answer`, plus the calls it got. */
  function liveApi(answer: (url: string, init?: RequestInit) => Response) {
    const fetch = vi.fn(async (url: string, init?: RequestInit) => answer(String(url), init))
    return { api: createApi(createLiveSource(config, { fetch })), fetch }
  }

  it('reads them with the viewer’s Tailscale login, and shows nothing without one or from an older Jarvis', async () => {
    const { api, fetch } = liveApi(() => Response.json({ routines: [{ id: 'r1', name: 'Bedtime', trigger: { type: 'asleep' }, actions: [] }], options: {} }))
    expect((await callApi(api, 'GET', '/api/jarvis/routines')).json().book).toBeNull()
    expect(fetch).not.toHaveBeenCalled()
    const book = (await callApi(api, 'GET', '/api/jarvis/routines', LOGIN)).json().book
    expect(book.routines[0].name).toBe('Bedtime')
    expect(fetch.mock.calls[0][0]).toBe(`${config.jarvisApiUrl}/routines`)
    expect((fetch.mock.calls[0][1]?.headers as Record<string, string>)['tailscale-user-login']).toBe('dylan@example.com')

    const old = liveApi(() => new Response('not found', { status: 404 }))
    expect((await callApi(old.api, 'GET', '/api/jarvis/routines', LOGIN)).json().book).toBeNull()
  })

  it('saves in Jarvis’s words, and runs and deletes by id', async () => {
    const { api, fetch } = liveApi((url) => {
      if (url.endsWith('/run')) return Response.json({ ok: true, detail: 'Ran 2 steps' })
      return Response.json({ ok: true })
    })
    const routine = { name: 'Home', trigger: { type: 'arrive', minAway: 20 }, actions: [{ type: 'app', entity: 'media_player.tv', app: 'Jarvis' }] }
    expect((await callApi(api, 'POST', '/api/jarvis/routines', PAGE, JSON.stringify({ op: 'save', routine }))).json().message).toBe('Open this page through Tailscale to change routines')
    expect(fetch).not.toHaveBeenCalled()

    expect((await callApi(api, 'POST', '/api/jarvis/routines', LOGIN, JSON.stringify({ op: 'save', routine }))).json()).toEqual({ ok: true, message: 'Saved' })
    expect(fetch.mock.calls[0][0]).toBe(`${config.jarvisApiUrl}/routines`)
    expect(JSON.parse(String(fetch.mock.calls[0][1]?.body)).routine.trigger).toEqual({ type: 'arrive', zone: 'home', min_away: 20 })

    expect((await callApi(api, 'POST', '/api/jarvis/routines', LOGIN, '{"op":"run","id":"r 1"}')).json()).toEqual({ ok: true, message: 'Ran 2 steps' })
    expect(fetch.mock.calls[1][0]).toBe(`${config.jarvisApiUrl}/routines/r%201/run`)
    expect((await callApi(api, 'POST', '/api/jarvis/routines', LOGIN, '{"op":"delete","id":"r1"}')).json()).toEqual({ ok: true, message: 'Deleted' })
    expect(fetch.mock.calls[2][0]).toBe(`${config.jarvisApiUrl}/routines/r1/delete`)
  })

  it('passes on what went wrong', async () => {
    const failed = liveApi(() => Response.json({ ok: false, detail: 'Step 2: the TV did not answer' }))
    const res = await callApi(failed.api, 'POST', '/api/jarvis/routines', LOGIN, '{"op":"run","id":"r1"}')
    expect(res.statusCode).toBe(502)
    expect(res.json().message).toBe('Step 2: the TV did not answer')

    const old = liveApi(() => new Response('not found', { status: 404 }))
    const routine = { name: 'x', trigger: { type: 'manual' }, actions: [{ type: 'notify', text: 'hi' }] }
    expect((await callApi(old.api, 'POST', '/api/jarvis/routines', LOGIN, JSON.stringify({ op: 'save', routine }))).json().message).toBe('Jarvis can’t run routines yet')

    const down = liveApi(() => { throw new Error('connect ECONNREFUSED') })
    expect((await callApi(down.api, 'POST', '/api/jarvis/routines', LOGIN, '{"op":"delete","id":"r1"}')).json().message).toBe('Jarvis is not answering')
  })
})
