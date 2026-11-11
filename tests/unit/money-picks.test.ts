// The store for categories picked on the Money page: saving, clearing,
// moving the reminder, dropping picks Copilot has sorted, and the file.
import { mkdtemp, readFile, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'
import { createPickStore } from '../../server/money-picks.mjs'
import { createPickFile } from '../../server/money-picks-file.mjs'

const NOW = new Date('2026-11-11T01:00:00Z')
const venmo = { op: 'pick', id: 'x5', category: 'Lessons', merchant: 'Venmo Alex', date: '2026-11-10T10:00:00Z', amount: 120, remindAt: '2026-11-12T04:00:00Z' }

describe('pick store', () => {
  it('saves a pick, replaces it, and the first one sets the reminder', async () => {
    const store = createPickStore({ now: () => NOW })
    expect(await store.change(venmo)).toEqual({ ok: true, message: 'Saved: Lessons' })
    await store.change({ ...venmo, category: 'Golf', remindAt: '2026-12-01T00:00:00Z' })
    const view = await store.read()
    expect(view.picks).toEqual([{ id: 'x5', category: 'Golf', merchant: 'Venmo Alex', date: '2026-11-10T10:00:00Z', amount: 120, pickedAt: NOW.toISOString() }])
    expect(view.remindAt).toBe('2026-11-12T04:00:00Z')
  })

  it('refuses a pick without a category or amount, and unknown changes', async () => {
    const store = createPickStore()
    expect((await store.change({ ...venmo, category: ' ' })).ok).toBe(false)
    expect((await store.change({ ...venmo, amount: 'lots' })).ok).toBe(false)
    expect((await store.change({ op: 'delete-everything' })).ok).toBe(false)
    expect((await store.read()).picks).toEqual([])
  })

  it('clears picks and drops the reminder with the last one', async () => {
    const store = createPickStore()
    await store.change(venmo)
    await store.change({ ...venmo, id: 'x6', merchant: 'Amazon' })
    await store.change({ op: 'clear', ids: ['x5'] })
    expect((await store.read()).picks.map((p) => p.id)).toEqual(['x6'])
    await store.change({ op: 'clear', ids: ['x6'] })
    expect(await store.read()).toEqual({ picks: [], remindAt: null })
  })

  it('moves the reminder only while picks are waiting', async () => {
    const store = createPickStore()
    expect((await store.change({ op: 'remind', at: '2026-11-13T04:00:00Z' })).ok).toBe(false)
    await store.change(venmo)
    await store.change({ op: 'remind', at: '2026-11-13T04:00:00Z' })
    expect((await store.read()).remindAt).toBe('2026-11-13T04:00:00.000Z')
  })

  it('drops a pick once the digest shows the purchase with a real category', async () => {
    const store = createPickStore()
    await store.change(venmo)
    await store.change({ ...venmo, id: 'x6' })
    const view = await store.read([{ id: 'x5', category: 'Education' }, { id: 'x6', category: 'Other' }])
    expect(view.picks.map((p) => p.id)).toEqual(['x6'])
  })

  it('keeps picks in a file across restarts, and starts empty from a broken one', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'picks-'))
    const file = join(dir, 'nested', 'money-picks.json')
    await createPickStore({ storage: createPickFile(file) }).change(venmo)
    const again = await createPickStore({ storage: createPickFile(file) }).read()
    expect(again.picks.map((p) => p.category)).toEqual(['Lessons'])
    expect(JSON.parse(await readFile(file, 'utf8')).remindAt).toBe('2026-11-12T04:00:00Z')

    await writeFile(file, '{not json')
    expect(await createPickStore({ storage: createPickFile(file) }).read()).toEqual({ picks: [], remindAt: null })
    expect(createPickFile('')).toBeNull()
  })
})
