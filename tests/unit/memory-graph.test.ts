import { describe, expect, it } from 'vitest'
import { isNodeId, parseGraph, parseNode } from '../../server/sources/memory-graph.mjs'
import { createApi } from '../../server/app.mjs'
import { createMockSource } from '../../server/sources/mock.mjs'
import { callApi } from './helpers'

describe('parseGraph', () => {
  it('keeps usable nodes and only the links that join two of them', () => {
    const graph = parseGraph({
      nodes: [
        { id: 'p1', type: 'person', name: ' Sam ', group: 'People', facts: 4, links: 2, updated: '2026-11-26T10:00:00Z' },
        { id: 'x1', type: 'spaceship', name: 'Trip', facts: -2, links: 'many' },
        { id: 'p1', type: 'person', name: 'Sam again' },
        { id: 'bad id!', name: 'Nope' },
        { id: 'p2', name: '' },
      ],
      links: [{ from: 'p1', to: 'x1', kind: 'going on' }, { from: 'p1', to: 'missing' }, { from: 'p1', to: 'p1' }],
    })
    expect(graph).toEqual({
      nodes: [
        { id: 'p1', type: 'person', name: 'Sam', group: 'People', facts: 4, links: 2, updated: '2026-11-26T10:00:00Z' },
        { id: 'x1', type: 'other', name: 'Trip', group: '', facts: 0, links: 0, updated: null },
      ],
      links: [{ from: 'p1', to: 'x1', kind: 'going on' }],
    })
  })

  it('is null when the answer is not a graph', () => {
    expect(parseGraph(null)).toBeNull()
    expect(parseGraph({ facts: [] })).toBeNull()
  })
})

describe('parseNode', () => {
  it('opens a node with its facts, links and open loops', () => {
    const node = parseNode({
      id: 'p1', type: 'person', name: 'Sam', aliases: ['Sammy', 3, ''], group: 'People',
      facts: [{ id: 'f1', text: 'Likes tea', source: 'chat', updated: '2026-11-25', confidence: 1.4 }, { id: 'f2' }],
      links: [{ id: 'x1', name: 'Trip', type: 'plan', kind: 'going on' }, { id: 'x2' }],
      loops: ['Call back', { text: 'Book the table', due: '2026-12-01' }, {}],
    })
    expect(node).toEqual({
      id: 'p1', type: 'person', name: 'Sam', aliases: ['Sammy'], group: 'People',
      facts: [{ id: 'f1', text: 'Likes tea', source: 'chat', updated: '2026-11-25', confidence: 1 }],
      links: [{ id: 'x1', name: 'Trip', type: 'plan', kind: 'going on' }],
      loops: [{ text: 'Call back', due: null }, { text: 'Book the table', due: '2026-12-01' }],
    })
  })

  it('is null without an id or a name, and checks ids', () => {
    expect(parseNode({ id: 'p1' })).toBeNull()
    expect(parseNode({ name: 'Sam' })).toBeNull()
    expect(isNodeId('people.sam-1')).toBe(true)
    expect(isNodeId('../etc')).toBe(false)
    expect(isNodeId('')).toBe(false)
  })
})

describe('memory web API', () => {
  it('serves the sample web and opens one node', async () => {
    const api = createApi(createMockSource())
    const graph = (await callApi(api, 'GET', '/api/jarvis/memory/graph')).json().graph
    expect(graph.nodes.length).toBeGreaterThan(2)
    expect(typeof graph.nodes[0].facts).toBe('number')
    expect(graph.links.every((link: { from: string; to: string }) => graph.nodes.some((n: { id: string }) => n.id === link.from) && graph.nodes.some((n: { id: string }) => n.id === link.to))).toBe(true)
    const first = graph.nodes[0]
    const node = (await callApi(api, 'GET', `/api/jarvis/memory/node/${first.id}`)).json().node
    expect(node.name).toBe(first.name)
    expect(node.facts.length).toBe(first.facts)
    expect(node.links.length).toBe(first.links)
  })

  it('refuses a bad id and says when a node is gone', async () => {
    const api = createApi(createMockSource())
    expect((await callApi(api, 'GET', '/api/jarvis/memory/node/bad%20id!')).statusCode).toBe(400)
    const gone = await callApi(api, 'GET', '/api/jarvis/memory/node/n-nothing')
    expect(gone.statusCode).toBe(404)
    expect(gone.json().gone).toBe(true)
  })

  it("passes the caller's login on", async () => {
    const seen: unknown[] = []
    const api = createApi({
      ...createMockSource(),
      memoryGraph: async (caller: unknown) => { seen.push(caller); return null },
      memoryNode: async (_id: string, caller: unknown) => { seen.push(caller); return { node: null, gone: false } },
    })
    const login = { 'tailscale-user-login': 'me@example.com' }
    await callApi(api, 'GET', '/api/jarvis/memory/graph', login)
    await callApi(api, 'GET', '/api/jarvis/memory/node/p1', login)
    expect(seen).toEqual([{ login: 'me@example.com' }, { login: 'me@example.com' }])
  })
})
