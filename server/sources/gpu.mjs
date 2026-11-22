// Who is using the graphics card right now, for the pie chart on Services
// and in the apps (Dylan, 2026-11-18). Under WSL nvidia-smi gives the totals
// but no per-process memory, so the names come from the two things that load
// models: Ollama (/api/ps, its local models) and Jarvis (GET /gpu, his own
// speech and voice models). Whatever is used but unnamed is one "Everything
// else" row: Windows, the desktop and driver overhead.

const MB = 1024 ** 2
const MAX_MODELS = 12
/** Below this, the unnamed leftover is measurement noise and gets no slice. */
const OTHER_MIN_MB = 50

/** A whole number of megabytes above zero, or null. */
function megabytes(value) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) return null
  return Math.round(value)
}

/** A trimmed string no longer than max, or null when it isn't one or is empty. */
function words(value, max) {
  if (typeof value !== 'string') return null
  return value.trim().slice(0, max) || null
}

/** nvidia-smi's "used, total, utilization" line as numbers, or null when it isn't one. */
export function parseSmi(stdout) {
  const [usedMb, totalMb, utilization] = String(stdout).trim().split('\n')[0].split(',').map((part) => Number(part.trim()))
  if (!Number.isFinite(usedMb) || !Number.isFinite(totalMb) || totalMb <= 0) return null
  let busy = null
  // Older drivers print "[N/A]" for utilization under WSL.
  if (Number.isFinite(utilization)) busy = Math.min(100, Math.max(0, Math.round(utilization)))
  return { usedMb: Math.round(usedMb), totalMb: Math.round(totalMb), utilization: busy }
}

/** Jarvis's own models that are on the card now (GET /gpu), as rows; [] for anything else. */
export function parseJarvisGpu(raw) {
  if (!Array.isArray(raw?.models)) return []
  const rows = []
  for (const model of raw.models.slice(0, MAX_MODELS)) {
    const name = words(model?.name, 40)
    const mb = megabytes(model?.mb)
    if (name === null || mb === null || model.loaded !== true) continue
    rows.push({ name, role: words(model.role, 60) ?? 'Speech model', mb, kind: 'speech' })
  }
  return rows
}

/** "ornith-1.5:9b" as "Ornith": the family name, capitalised. */
function modelName(tag) {
  const family = String(tag).split(/[-:]/)[0]
  if (family === '') return String(tag)
  return family[0].toUpperCase() + family.slice(1)
}

/** Ollama's loaded models (/api/ps entries) as rows; ones wholly in normal memory are left out. */
export function ollamaRows(models, watchModel) {
  const rows = []
  for (const model of models.slice(0, MAX_MODELS)) {
    const mb = megabytes((model?.size_vram ?? 0) / MB)
    if (mb === null || typeof model.name !== 'string') continue
    let role = 'Local model'
    if (model.name === watchModel) role = 'Local brain'
    rows.push({ name: modelName(model.name), role, mb, kind: 'local' })
  }
  return rows
}

/**
 * The card's totals and who holds what, biggest first. The named rows are
 * trimmed so they never add up to more than is really in use (Ollama's and
 * Jarvis's figures are measured at other moments than nvidia-smi's).
 */
export function buildGpu(smi, rows) {
  if (smi === null) return null
  const users = [...rows].sort((a, b) => b.mb - a.mb)
  let named = 0
  for (const user of users) {
    user.mb = Math.min(user.mb, Math.max(0, smi.usedMb - named))
    named += user.mb
  }
  const other = smi.usedMb - named
  if (other >= OTHER_MIN_MB) users.push({ name: 'Everything else', role: 'Windows, the desktop and drivers', mb: other, kind: 'other' })
  return { totalMb: smi.totalMb, usedMb: smi.usedMb, utilization: smi.utilization, users: users.filter((user) => user.mb > 0) }
}
