// The page at the bare URL: the backend's health in plain HTML, drawn from
// the snapshot the apps already get. No scripts; it reloads itself.

/** Escapes text for HTML. */
function esc(value) {
  return String(value ?? '').replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`)
}

/** One labelled bar: used of total, with the numbers beside it. */
function bar(label, used, total, unit) {
  const pct = total > 0 ? Math.min(100, Math.round((used / total) * 100)) : 0
  return `<div class="row"><span>${esc(label)}</span><meter min="0" max="100" value="${pct}"></meter><span>${esc(used)} of ${esc(total)} ${unit}</span></div>`
}

/** MB as GB with one decimal. */
function gb(mb) {
  return Math.round(mb / 102.4) / 10
}

/** The whole page for one snapshot. */
export function metricsPage(snap) {
  const parts = []

  parts.push('<h2>Services</h2>')
  for (const s of snap.services ?? []) {
    parts.push(`<div class="row"><span class="dot ${esc(s.status)}"></span><span>${esc(s.name)}</span><span class="dim">${esc(s.detail)}</span></div>`)
  }

  parts.push('<h2>Machine</h2>')
  if (snap.gpu) {
    const busy = snap.gpu.utilization === null ? '' : ` (${snap.gpu.utilization}% busy)`
    parts.push(bar(`Graphics card${busy}`, gb(snap.gpu.usedMb), gb(snap.gpu.totalMb), 'GB'))
  }
  if (snap.ram) parts.push(bar('Memory', gb(snap.ram.usedMb), gb(snap.ram.totalMb), 'GB'))
  for (const d of snap.disks ?? []) parts.push(bar(d.name, d.usedGb, d.totalGb, 'GB'))

  parts.push('<h2>Running jobs</h2>')
  const running = snap.jobs?.running ?? []
  if (running.length === 0) parts.push('<p class="dim">Nothing running.</p>')
  for (const j of running) {
    parts.push(`<div class="row"><span>${esc(j.label)}</span><span class="dim">${esc(j.step ?? j.state)}</span></div>`)
  }

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="15">
<title>jarvis backend</title>
<style>
:root { color-scheme: light dark; font: 15px/1.4 system-ui, sans-serif; }
body { max-width: 40rem; margin: 2rem auto; padding: 0 16px; }
h2 { font-size: 1rem; margin: 1.5rem 0 0.5rem; }
.row { display: flex; gap: 0.75rem; align-items: center; min-height: 44px; border-bottom: 1px solid #8884; }
.row > :last-child { margin-left: auto; text-align: right; }
meter { flex: 1; }
.dim { opacity: 0.6; }
.dot { flex: none; width: 10px; height: 10px; border-radius: 50%; background: #d33; }
.dot.up { background: #2a2; }
.dot.degraded { background: #d90; }
</style>
</head>
<body>
<h1>${esc(snap.host?.name ?? 'jarvis')}</h1>
<p class="dim">Updated ${esc(snap.generatedAt)}</p>
${parts.join('\n')}
</body>
</html>
`
}
