// Playbooks: the words the page shows, the checks before a playbook is sent
// to Jarvis, the sample source, the API routes and what the live source
// asks Jarvis for.
import { describe, expect, it, vi } from 'vitest'
import { createApi } from '../../server/app.mjs'
import { loadConfig } from '../../server/config.mjs'
import { createLiveSource } from '../../server/sources/live.mjs'
import { createMockSource } from '../../server/sources/mock.mjs'
import { cleanPlaybook, fromJarvisDraft, fromJarvisPlaybook, parsePlaybookBook, toJarvisPlaybook } from '../../server/sources/playbooks.mjs'
import { blankPlaybook, blankStep, stepChoices, blankTrigger, clockLabel, daysLabel, draftOf, failedChecks, playbookProblem, stepLine, triggerLine } from '../../src/lib/playbooks'
import type { Playbook, PlaybookOptions } from '../../src/types'
import { callApi } from './helpers'

const PAGE = { 'x-home-lab': '1' }
const LOGIN = { ...PAGE, 'tailscale-user-login': 'dylan@example.com' }

const OPTIONS: PlaybookOptions = {
  devices: [{ entity: 'light.lamp', name: 'Lamp', kind: 'light', commands: ['turn_on', 'turn_off', 'toggle'] }, { entity: 'climate.t', name: 'Thermostat', kind: 'climate', commands: ['set_temperature', 'set_hvac_mode'] }],
  scenes: [{ entity: 'scene.movie', name: 'Movie night' }],
  apps: [{ entity: 'media_player.tv', name: 'Apple TV', apps: ['Jarvis', 'Netflix'] }],
  zones: ['home'],
  jobs: [{ id: 'nightly', name: 'The nightly self-improvement pass' }],
}

describe('playbook words', () => {
  it('says when a playbook runs', () => {
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
    expect(triggerLine({ type: 'manual' })).toBe('When I ask, or the job comes up')
  })

  it('says what each step does, by the device’s name', () => {
    expect(stepLine({ type: 'device', entity: 'light.lamp', command: 'turn_off' }, OPTIONS)).toBe('Turn off: Lamp')
    expect(stepLine({ type: 'device', entity: 'climate.t', command: 'set_temperature', value: 66 }, OPTIONS)).toBe('Thermostat: set temperature to 66')
    expect(stepLine({ type: 'device', entity: 'light.gone', command: 'turn_on' }, OPTIONS)).toBe('Turn on: light.gone')
    expect(stepLine({ type: 'scene', entity: 'scene.movie' }, OPTIONS)).toBe('Scene: Movie night')
    expect(stepLine({ type: 'app', entity: 'media_player.tv', app: 'Jarvis' }, OPTIONS)).toBe('Open Jarvis on Apple TV')
    expect(stepLine({ type: 'email', to: 'a@b.co', subject: 'Goodnight', body: 'x', confirm: true }, OPTIONS)).toBe('Email a@b.co: Goodnight')
    expect(stepLine({ type: 'wait', seconds: 120 }, OPTIONS)).toBe('Wait 2 min')
    expect(stepLine({ type: 'wait', seconds: 45 }, OPTIONS)).toBe('Wait 45 s')
    expect(stepLine({ type: 'job', job: 'nightly' }, OPTIONS)).toBe('Run: The nightly self-improvement pass')
    expect(stepLine({ type: 'job', job: 'gone' }, OPTIONS)).toBe('Run: gone')
  })

  it('starts new triggers and steps sensibly, without asking first in a playbook you wrote', () => {
    expect(blankPlaybook()).toMatchObject({ name: '', enabled: true, purpose: '', trigger: { type: 'manual' }, steps: [], done: [], decisions: [] })
    expect(blankTrigger('arrive')).toEqual({ type: 'arrive', zone: 'home', minAway: 15 })
    expect(blankStep('device', OPTIONS)).toEqual({ type: 'device', entity: 'light.lamp', command: 'turn_on' })
    expect(blankStep('app', OPTIONS)).toEqual({ type: 'app', entity: 'media_player.tv', app: 'Jarvis' })
    // A playbook you wrote doesn't ask before sending; a thinking step lets Jarvis pick who does it.
    expect(blankStep('email', OPTIONS)).toMatchObject({ confirm: false })
    expect(blankStep('think', OPTIONS)).toEqual({ type: 'think', text: '', model: 'auto' })
  })

  it('says what a playbook is missing before it can be saved', () => {
    const draft = blankPlaybook()
    expect(playbookProblem(draft)).toBe('Give the playbook a name')
    draft.name = 'Bedtime'
    expect(playbookProblem(draft)).toBe('Add at least one step')
    draft.steps = [{ type: 'device', entity: 'light.lamp', command: 'turn_off' }, { type: 'email', to: 'nobody', subject: 's', body: 'b', confirm: true }]
    expect(playbookProblem(draft)).toBe('Step 2: check the email address')
    draft.steps[1] = { type: 'device', entity: 'climate.t', command: 'set_temperature' }
    expect(playbookProblem(draft)).toBe('Step 2: give it a value')
    draft.steps[1] = { type: 'notify', text: 'Night' }
    expect(playbookProblem(draft)).toBeNull()
  })
})

describe('checking a playbook before Jarvis gets it', () => {
  const good = {
    name: '  Bedtime  ',
    trigger: { type: 'time', at: '22:30', days: ['sun', 'mon', 'nope'] },
    steps: [
      { type: 'device', entity: 'light.lamp', command: 'turn_off', extra: 'dropped' },
      { type: 'email', to: 'a@b.co', subject: 'Night', body: 'Going to bed' },
      { type: 'wait', seconds: 99999 },
    ],
  }

  it('trims, orders the days, caps a wait, and only asks before an email when told to', () => {
    const { playbook } = cleanPlaybook(good)
    expect(playbook).toEqual({
      name: 'Bedtime',
      enabled: true,
      purpose: '',
      whenToUse: '',
      trigger: { type: 'time', at: '22:30', days: ['mon', 'sun'] },
      inputs: [],
      steps: [
        { type: 'device', entity: 'light.lamp', command: 'turn_off' },
        { type: 'email', to: 'a@b.co', subject: 'Night', body: 'Going to bed', confirm: false },
        { type: 'wait', seconds: 600 },
      ],
      decisions: [],
      done: [],
      edgeCases: [],
      standard: '',
      badVersion: '',
    })
    const asks = cleanPlaybook({ ...good, steps: [{ type: 'email', to: 'a@b.co', subject: 's', body: 'b', confirm: true }] })
    expect(asks.playbook!.steps[0]).toMatchObject({ confirm: true })
  })

  it('keeps what the job is for, its done checklist, decisions and the rest, dropping empty rows', () => {
    const { playbook } = cleanPlaybook({
      ...good,
      purpose: '  Shut the place down  ',
      whenToUse: 'When I say goodnight',
      inputs: [{ name: 'Calendars', where: 'Work, Church' }, { name: 'half', where: '' }],
      decisions: [{ if: 'Guests are over', then: 'Leave the porch light on' }, { if: '', then: 'nothing' }],
      done: ['Every light is off', '  ', 7],
      edgeCases: ['The TV ignores the first off'],
      standard: 'Quiet',
      badVersion: 'Lights left on',
      steps: [{ type: 'think', text: 'Check the doors', model: 'worker' }, { type: 'think', text: 'Say goodnight', model: 'gpt' }],
    })
    expect(playbook).toMatchObject({
      purpose: 'Shut the place down',
      whenToUse: 'When I say goodnight',
      inputs: [{ name: 'Calendars', where: 'Work, Church' }],
      decisions: [{ if: 'Guests are over', then: 'Leave the porch light on' }],
      done: ['Every light is off'],
      edgeCases: ['The TV ignores the first off'],
      standard: 'Quiet',
      badVersion: 'Lights left on',
      steps: [{ type: 'think', text: 'Check the doors', model: 'worker' }, { type: 'think', text: 'Say goodnight', model: 'auto' }],
    })
    // On the way to Jarvis: his field names, made by Dylan, and no model where he's to pick.
    const out = toJarvisPlaybook(playbook!)
    expect(out).toMatchObject({ when_to_use: 'When I say goodnight', edge_cases: ['The TV ignores the first off'], bad_version: 'Lights left on', made_by: 'dylan' })
    expect(out).not.toHaveProperty('whenToUse')
    expect(out.steps).toEqual([{ type: 'think', text: 'Check the doors', model: 'worker' }, { type: 'think', text: 'Say goodnight' }])
  })

  it('says what is wrong in plain words', () => {
    expect(cleanPlaybook(null).problem).toBe('Give the playbook a name')
    expect(cleanPlaybook({ ...good, trigger: { type: 'time', at: '25:00' } }).problem).toBe('Pick when the playbook should run')
    expect(cleanPlaybook({ ...good, trigger: { type: 'full-moon' } }).problem).toBe('Pick when the playbook should run')
    expect(cleanPlaybook({ ...good, steps: [] }).problem).toBe('Add at least one step')
    expect(cleanPlaybook({ ...good, steps: Array(21).fill({ type: 'wait', seconds: 1 }) }).problem).toBe('A playbook can have up to 20 steps')
    expect(cleanPlaybook({ ...good, steps: [good.steps[0], { type: 'email', to: 'nobody', subject: 's', body: 'b' }] }).problem).toBe('Step 2 is missing something')
    expect(cleanPlaybook({ ...good, steps: [{ type: 'unlock-door' }] }).problem).toBe('Step 1 is missing something')
  })

  it('speaks Jarvis’s words on the way out and the page’s on the way back', () => {
    const arrive = cleanPlaybook({ name: 'Home', trigger: { type: 'arrive', minAway: 5000 }, steps: [{ type: 'scene', entity: 'scene.movie' }] }).playbook!
    expect(arrive.trigger).toEqual({ type: 'arrive', zone: 'home', minAway: 1440 })
    expect(toJarvisPlaybook(arrive).trigger).toEqual({ type: 'arrive', zone: 'home', min_away: 1440 })
    // Several addresses go to Jarvis as a list and come back as one line.
    const mail = cleanPlaybook({ name: 'Night', trigger: { type: 'asleep' }, steps: [{ type: 'email', to: 'a@b.co ,c@d.co', subject: 's', body: 'b' }] }).playbook!
    expect(mail.steps[0]).toMatchObject({ to: 'a@b.co, c@d.co' })
    expect(toJarvisPlaybook(mail).steps[0]).toMatchObject({ to: ['a@b.co', 'c@d.co'] })
    expect(fromJarvisPlaybook({ id: 'x', name: 'Night', steps: [{ type: 'email', to: ['a@b.co', 'c@d.co'] }] })!.steps[0]).toMatchObject({ to: 'a@b.co, c@d.co' })
    const back = fromJarvisPlaybook({
      id: 'r1',
      name: 'Home',
      purpose: 'Welcome me home',
      when_to_use: 'When I walk in',
      made_by: 'jarvis',
      trigger: { type: 'arrive', zone: 'home', min_away: 20 },
      steps: [{ type: 'scene', entity: 'scene.movie', model: 'code' }, 'junk', { type: 'ask', text: 'Say hi' }, { type: 'think', text: 'Plan dinner', model: 'claude' }],
      done: ['The TV is on'],
      edge_cases: ['TV asleep'],
      last_run: { at: '2026-11-18T08:00:00Z', ok: false, detail: '1 of 1 checks failed', checks: [{ item: 'The TV is on', ok: false, why: 'it did not answer' }, { nope: 1 }] },
    })
    expect(back).toEqual({
      id: 'r1',
      name: 'Home',
      enabled: true,
      purpose: 'Welcome me home',
      whenToUse: 'When I walk in',
      trigger: { type: 'arrive', zone: 'home', minAway: 20 },
      inputs: [],
      // Fixed steps lose Jarvis's "code" tag; an older "ask" step reads as a thinking step.
      steps: [{ type: 'scene', entity: 'scene.movie' }, { type: 'think', text: 'Say hi', model: 'auto' }, { type: 'think', text: 'Plan dinner', model: 'claude' }],
      decisions: [],
      done: ['The TV is on'],
      edgeCases: ['TV asleep'],
      standard: '',
      badVersion: '',
      madeBy: 'jarvis',
      lastRun: { at: '2026-11-18T08:00:00Z', ok: false, detail: '1 of 1 checks failed', checks: [{ item: 'The TV is on', ok: false, why: 'it did not answer' }] },
    })
    // The editor starts from everything but the id-less extras; the row lists what didn't hold.
    expect(draftOf(back as Playbook)).not.toHaveProperty('lastRun')
    expect(draftOf(back as Playbook)).not.toHaveProperty('madeBy')
    expect(failedChecks(back as Playbook)).toEqual(['The TV is on: it did not answer'])
    // An older Jarvis calls the steps "actions".
    expect(fromJarvisPlaybook({ id: 'o', name: 'Old', actions: [{ type: 'wait', seconds: 5 }] })!.steps).toEqual([{ type: 'wait', seconds: 5 }])
    expect(fromJarvisPlaybook({ name: 'no id' })).toBeNull()
  })

  it('keeps only the well-formed parts of Jarvis’s answer', () => {
    const book = parsePlaybookBook({
      playbooks: [{ id: 'r1', name: 'Bedtime', trigger: { type: 'time', at: '22:00' }, steps: [] }, { nope: true }],
      options: { devices: [{ entity: 'light.lamp', name: 'Lamp', kind: 'light', commands: ['turn_on', 7] }, { name: 'no entity' }], apps: [{ entity: 'media_player.tv' }], zones: ['home', 3], jobs: [{ id: 'nightly', name: 'The nightly pass' }, { name: 'no id' }] },
    })
    expect(book.playbooks).toHaveLength(1)
    expect(book.playbooks[0].trigger).toEqual({ type: 'time', at: '22:00', days: [] })
    expect(book.options).toEqual({
      devices: [{ entity: 'light.lamp', name: 'Lamp', kind: 'light', commands: ['turn_on'] }],
      scenes: [],
      apps: [{ entity: 'media_player.tv', name: 'media_player.tv', apps: [] }],
      zones: ['home'],
      jobs: [{ id: 'nightly', name: 'The nightly pass' }],
    })
    expect(parsePlaybookBook(null)).toEqual({ playbooks: [], options: { devices: [], scenes: [], apps: [], zones: [], jobs: [] } })
  })
})

describe('/api/jarvis/playbooks (sample data)', () => {
  it('lists the playbooks with what their steps can use', async () => {
    const book = (await callApi(createApi(createMockSource()), 'GET', '/api/jarvis/playbooks')).json().book
    expect(book.playbooks.map((r: { name: string }) => r.name)).toEqual(['Bedtime', 'Arrive home', 'Plan my week'])
    expect(book.options.devices.length).toBeGreaterThan(0)
    expect(book.options.apps[0].apps).toContain('Jarvis')
  })

  it('saves a new one, edits it, runs it and deletes it', async () => {
    const api = createApi(createMockSource())
    const names = async () => (await callApi(api, 'GET', '/api/jarvis/playbooks')).json().book.playbooks.map((r: { name: string }) => r.name)
    const playbook = { name: 'Lights out', trigger: { type: 'manual' }, steps: [{ type: 'notify', text: 'Night' }], done: ['I was told goodnight'] }

    expect((await callApi(api, 'POST', '/api/jarvis/playbooks', {}, JSON.stringify({ op: 'save', playbook }))).statusCode).toBe(403)
    expect((await callApi(api, 'POST', '/api/jarvis/playbooks', PAGE, JSON.stringify({ op: 'save', playbook: { ...playbook, steps: [] } }))).json().message).toBe('Add at least one step')
    expect((await callApi(api, 'POST', '/api/jarvis/playbooks', PAGE, '{"op":"explode","id":"r1"}')).statusCode).toBe(400)
    expect((await callApi(api, 'POST', '/api/jarvis/playbooks', PAGE, '{"op":"run"}')).statusCode).toBe(400)
    // A draft from a description comes back to look over and isn't saved.
    expect((await callApi(api, 'POST', '/api/jarvis/playbooks', PAGE, '{"op":"draft","text":" "}')).statusCode).toBe(400)
    const drafted = (await callApi(api, 'POST', '/api/jarvis/playbooks', PAGE, JSON.stringify({ op: 'draft', text: 'At 11 pm turn everything off' }))).json()
    expect(drafted.ok).toBe(true)
    expect(drafted.playbook.trigger).toEqual({ type: 'time', at: '23:00', days: [] })
    expect(drafted.playbook.id).toBeUndefined()
    expect(await names()).not.toContain(drafted.playbook.name)

    expect((await callApi(api, 'POST', '/api/jarvis/playbooks', PAGE, JSON.stringify({ op: 'save', playbook }))).json()).toEqual({ ok: true, message: 'Saved' })
    expect(await names()).toContain('Lights out')
    await callApi(api, 'POST', '/api/jarvis/playbooks', PAGE, JSON.stringify({ op: 'save', playbook: { ...playbook, id: 'r10', name: 'Lights off' } }))
    expect(await names()).toEqual(['Bedtime', 'Arrive home', 'Plan my week', 'Lights off'])

    expect((await callApi(api, 'POST', '/api/jarvis/playbooks', PAGE, '{"op":"run","id":"r10"}')).json()).toEqual({ ok: true, message: 'Ran 1 step, the check passed', checks: [{ item: 'I was told goodnight', ok: true, why: '' }] })
    const ran = (await callApi(api, 'GET', '/api/jarvis/playbooks')).json().book.playbooks[3]
    expect(ran.lastRun.ok).toBe(true)

    expect((await callApi(api, 'POST', '/api/jarvis/playbooks', PAGE, '{"op":"delete","id":"r10"}')).json().ok).toBe(true)
    expect(await names()).not.toContain('Lights off')
    expect((await callApi(api, 'POST', '/api/jarvis/playbooks', PAGE, '{"op":"delete","id":"r10"}')).statusCode).toBe(502)
  })
})

describe('playbooks from the real Jarvis', () => {
  const config = loadConfig({ DATA_SOURCE: 'live', HA_TOKEN: 'token' })

  /** An API over a live source whose Jarvis answers with `answer`, plus the calls it got. */
  function liveApi(answer: (url: string, init?: RequestInit) => Response) {
    const fetch = vi.fn(async (url: string, init?: RequestInit) => answer(String(url), init))
    return { api: createApi(createLiveSource(config, { fetch })), fetch }
  }

  it('reads them with the viewer’s Tailscale login, and shows nothing without one or from an older Jarvis', async () => {
    const { api, fetch } = liveApi(() => Response.json({ playbooks: [{ id: 'r1', name: 'Bedtime', trigger: { type: 'asleep' }, steps: [] }], options: {} }))
    expect((await callApi(api, 'GET', '/api/jarvis/playbooks')).json().book).toBeNull()
    expect(fetch).not.toHaveBeenCalled()
    const book = (await callApi(api, 'GET', '/api/jarvis/playbooks', LOGIN)).json().book
    expect(book.playbooks[0].name).toBe('Bedtime')
    expect(fetch.mock.calls[0][0]).toBe(`${config.jarvisApiUrl}/playbooks`)
    expect((fetch.mock.calls[0][1]?.headers as Record<string, string>)['tailscale-user-login']).toBe('dylan@example.com')

    const old = liveApi(() => new Response('not found', { status: 404 }))
    expect((await callApi(old.api, 'GET', '/api/jarvis/playbooks', LOGIN)).json().book).toBeNull()
  })

  it('saves in Jarvis’s words, and runs and deletes by id', async () => {
    const { api, fetch } = liveApi((url) => {
      if (url.endsWith('/run')) return Response.json({ ok: true, detail: 'Ran 2 steps', checks: [{ item: 'TV is on', ok: true }] })
      return Response.json({ ok: true })
    })
    const playbook = { name: 'Home', trigger: { type: 'arrive', minAway: 20 }, steps: [{ type: 'app', entity: 'media_player.tv', app: 'Jarvis' }] }
    expect((await callApi(api, 'POST', '/api/jarvis/playbooks', PAGE, JSON.stringify({ op: 'save', playbook }))).json().message).toBe('Open this page through Tailscale to change playbooks')
    expect(fetch).not.toHaveBeenCalled()

    expect((await callApi(api, 'POST', '/api/jarvis/playbooks', LOGIN, JSON.stringify({ op: 'save', playbook }))).json()).toEqual({ ok: true, message: 'Saved' })
    expect(fetch.mock.calls[0][0]).toBe(`${config.jarvisApiUrl}/playbooks`)
    expect(JSON.parse(String(fetch.mock.calls[0][1]?.body)).playbook.trigger).toEqual({ type: 'arrive', zone: 'home', min_away: 20 })

    expect((await callApi(api, 'POST', '/api/jarvis/playbooks', LOGIN, '{"op":"run","id":"r 1"}')).json()).toEqual({ ok: true, message: 'Ran 2 steps', checks: [{ item: 'TV is on', ok: true, why: '' }] })
    expect(fetch.mock.calls[1][0]).toBe(`${config.jarvisApiUrl}/playbooks/r%201/run`)
    expect((await callApi(api, 'POST', '/api/jarvis/playbooks', LOGIN, '{"op":"delete","id":"r1"}')).json()).toEqual({ ok: true, message: 'Deleted' })
    expect(fetch.mock.calls[2][0]).toBe(`${config.jarvisApiUrl}/playbooks/r1/delete`)
  })

  it('passes on what went wrong', async () => {
    const failed = liveApi(() => Response.json({ ok: false, detail: 'Step 2: the TV did not answer' }))
    const res = await callApi(failed.api, 'POST', '/api/jarvis/playbooks', LOGIN, '{"op":"run","id":"r1"}')
    expect(res.statusCode).toBe(502)
    expect(res.json().message).toBe('Step 2: the TV did not answer')

    const old = liveApi(() => new Response('not found', { status: 404 }))
    const playbook = { name: 'x', trigger: { type: 'manual' }, steps: [{ type: 'notify', text: 'hi' }] }
    expect((await callApi(old.api, 'POST', '/api/jarvis/playbooks', LOGIN, JSON.stringify({ op: 'save', playbook }))).json().message).toBe('Jarvis can’t run playbooks yet')

    const down = liveApi(() => { throw new Error('connect ECONNREFUSED') })
    expect((await callApi(down.api, 'POST', '/api/jarvis/playbooks', LOGIN, '{"op":"delete","id":"r1"}')).json().message).toBe('Jarvis is not answering')
  })

  it('reads a playbook Jarvis drafted as an editor draft: no id, author or last run', () => {
    const draft = fromJarvisDraft({ name: 'Lights out', trigger: { type: 'arrive', zone: 'home', min_away: 20 }, steps: [{ type: 'notify', text: 'Home' }], made_by: 'jarvis', done: ['Told me'] })
    expect(draft).toMatchObject({ name: 'Lights out', trigger: { type: 'arrive', zone: 'home', minAway: 20 }, done: ['Told me'] })
    expect(draft).not.toHaveProperty('id')
    expect(draft).not.toHaveProperty('madeBy')
    expect(fromJarvisDraft(null)).toBeNull()
    expect(fromJarvisDraft({ steps: [] })).toBeNull()
  })
})

describe('a step that runs one of Jarvis’s own jobs', () => {
  const nightly = { name: 'Nightly self-improvement', trigger: { type: 'time', at: '03:30', days: [] }, steps: [{ type: 'job', job: 'nightly', model: 'code' }] }

  it('reads Jarvis’s step, and sends it back unchanged in meaning', () => {
    const fromJarvis = fromJarvisPlaybook({ id: 'nightly', ...nightly })!
    expect(fromJarvis.steps).toEqual([{ type: 'job', job: 'nightly' }])
    const { playbook } = cleanPlaybook({ ...fromJarvis, enabled: false })
    expect(playbook!.steps).toEqual([{ type: 'job', job: 'nightly' }])
    expect(playbook!.enabled).toBe(false)
    expect(toJarvisPlaybook(playbook!).steps).toEqual([{ type: 'job', job: 'nightly' }])
  })

  it('refuses a job step with no job or an odd id', () => {
    expect(cleanPlaybook({ ...nightly, steps: [{ type: 'job' }] }).problem).toBe('Step 1 is missing something')
    expect(cleanPlaybook({ ...nightly, steps: [{ type: 'job', job: '../x' }] }).problem).toBe('Step 1 is missing something')
  })

  it('offers the job step only when Jarvis lists jobs', () => {
    expect(stepChoices(OPTIONS).map((c) => c.type)).toContain('job')
    expect(stepChoices({ ...OPTIONS, jobs: [] }).map((c) => c.type)).not.toContain('job')
    expect(blankStep('job', OPTIONS)).toEqual({ type: 'job', job: 'nightly' })
    expect(playbookProblem({ ...blankPlaybook(), name: 'N', steps: [{ type: 'job', job: '' }] })).toMatch(/pick a job/)
  })
})
