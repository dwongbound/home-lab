// Jarvis's memory as a web: every thing he knows (a person, a place, a plan)
// is a node, and links say how they connect (Dylan, 2026-11-26: bubbles to
// drag around in the apps, a tap shows what's in one). Jarvis answers
// GET /memory/graph (no fact text, so it stays small) and GET /memory/node/{id};
// this file checks his answers and renames them for the apps.

const MAX_NODES = 2000
const MAX_LINKS = 8000
const MAX_FACTS = 200
const MAX_NODE_LINKS = 200
// Jarvis's ids are paths in his own words ("people/sam", "loops/book the table"), so they may hold
// slashes and spaces; anything printable goes, since an id is only ever sent on percent-encoded.
const ID = /^[^\u0000-\u001f\u007f]{1,120}$/
const TYPES = ['person', 'place', 'project', 'routine', 'preference', 'plan', 'loop']

/** True for an id Jarvis could have given a node or a fact: some printable text with no stray space at either end. */
export function isNodeId(value) {
  return typeof value === 'string' && ID.test(value) && value.trim() === value
}

/** The node id from the end of a request path, percent-decoded; null when it can't be decoded or isn't an id. */
export function nodeIdFromPath(rest) {
  let id = null
  try {
    id = decodeURIComponent(rest)
  } catch {
    return null
  }
  if (!isNodeId(id)) return null
  return id
}

/** A trimmed string no longer than max, or '' when it isn't one. */
function words(value, max) {
  if (typeof value !== 'string') return ''
  return value.trim().slice(0, max)
}

/** A whole number of zero or more, or 0 for anything else. */
function count(value) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) return 0
  return Math.floor(value)
}

/** One of the kinds of thing the apps draw differently; anything new is "other". */
function nodeType(value) {
  if (TYPES.includes(value)) return value
  return 'other'
}

/** An ISO time as given, or null when it isn't a string. */
function when(value) {
  return words(value, 40) || null
}

/**
 * The whole web for the apps: `{nodes, links}`. Nodes without a usable id or
 * name are dropped, and so is any link that doesn't join two kept nodes.
 * Null when the answer isn't a graph (an older Jarvis).
 */
export function parseGraph(raw) {
  if (!Array.isArray(raw?.nodes)) return null
  const nodes = []
  const known = new Set()
  for (const node of raw.nodes.slice(0, MAX_NODES)) {
    const name = words(node?.name, 80)
    if (!isNodeId(node?.id) || name === '' || known.has(node.id)) continue
    known.add(node.id)
    nodes.push({
      id: node.id, type: nodeType(node.type), name, group: words(node.group, 40),
      facts: count(node.facts), links: count(node.links), updated: when(node.updated),
    })
  }
  const links = []
  const list = Array.isArray(raw.links) ? raw.links.slice(0, MAX_LINKS) : []
  for (const link of list) {
    if (!known.has(link?.from) || !known.has(link?.to) || link.from === link.to) continue
    links.push({ from: link.from, to: link.to, kind: words(link.kind, 40) })
  }
  return { nodes, links }
}

/** One fact inside a node, or null when it has no id or text. */
function toFact(raw) {
  const text = words(raw?.text, 2000)
  if (!isNodeId(raw?.id) || text === '') return null
  let confidence = null
  if (typeof raw.confidence === 'number' && Number.isFinite(raw.confidence)) {
    confidence = Math.min(1, Math.max(0, raw.confidence))
  }
  return { id: raw.id, text, source: words(raw.source, 40), updated: when(raw.updated), confidence }
}

/** One thing a node connects to, or null when it has no id or name. */
function toNodeLink(raw) {
  const name = words(raw?.name, 80)
  if (!isNodeId(raw?.id) || name === '') return null
  return { id: raw.id, name, type: nodeType(raw.type), kind: words(raw.kind, 40) }
}

/**
 * One node opened up: what he knows about it and what it connects to.
 * `loops` are the open things tied to it, as plain lines. Null when the
 * answer isn't a node.
 */
export function parseNode(raw) {
  const name = words(raw?.name, 80)
  if (!isNodeId(raw?.id) || name === '') return null
  const aliases = (Array.isArray(raw.aliases) ? raw.aliases : []).map((alias) => words(alias, 80)).filter((alias) => alias !== '')
  const facts = (Array.isArray(raw.facts) ? raw.facts.slice(0, MAX_FACTS) : []).map(toFact).filter((fact) => fact !== null)
  const links = (Array.isArray(raw.links) ? raw.links.slice(0, MAX_NODE_LINKS) : []).map(toNodeLink).filter((link) => link !== null)
  const loops = []
  for (const loop of Array.isArray(raw.loops) ? raw.loops.slice(0, 50) : []) {
    // A loop is a line of text, or an object with the line in `text` and maybe a `due` day.
    const text = words(typeof loop === 'string' ? loop : loop?.text, 300)
    if (text !== '') loops.push({ text, due: when(loop?.due) })
  }
  return { id: raw.id, type: nodeType(raw.type), name, aliases: aliases.slice(0, 20), group: words(raw.group, 40), facts, links, loops }
}
