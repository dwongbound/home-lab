// Builds the SVG path for a sparkline. Coordinates are rounded to one
// decimal to keep the markup small (rendering-svg-precision).
/**
 * SVG path data for `values` scaled to fit width x height, with `pad`
 * pixels of breathing room. Fewer than two points gives an empty string.
 */
export function sparkPath(values: number[], width: number, height: number, pad = 2): string {
  if (values.length < 2) return ''
  let min = Infinity
  let max = -Infinity
  for (const v of values) { if (v < min) min = v; if (v > max) max = v }
  const span = max - min || 1
  const step = (width - pad * 2) / (values.length - 1)
  let d = ''
  for (let i = 0; i < values.length; i++) {
    const x = pad + i * step
    const y = height - pad - ((values[i] - min) / span) * (height - pad * 2)
    d += `${i === 0 ? 'M' : 'L'}${x.toFixed(1)} ${y.toFixed(1)}`
  }
  return d
}
