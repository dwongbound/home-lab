// Jarvis's orb, design D (Dylan, 2026-11-16): a see-through glass core
// inside a constellation of points that turns in 3D around it. The same
// orb as the iPhone app (ios/App/OrbView.swift); keep the two in step.
//
// These are the sums; JarvisOrb.tsx draws them on two canvases, one behind
// the glass core and one in front of it.

import type { OrbState } from '../components/JarvisOrb'

/** One point of the constellation: x and y on the screen, z toward you, each -1..1. */
export interface OrbPoint { x: number; y: number; z: number }

/** How many points the constellation has. */
export const ORB_POINTS = 60

/** How far the constellation reaches, as a share of the core's diameter (the core's edge is 0.5). */
export const ORB_REACH = 0.9

/**
 * How each state looks: the points' colour (r, g, b), how fast the
 * constellation turns (radians a second), and how far out it sits (1 = normal).
 * Idle doesn't turn at all: the orb sits inside a glass panel, and a loop
 * that never stops makes iOS redraw that panel's blur every frame
 * (Dylan's iPhone, 2026-11-12).
 */
export function orbLook(state: OrbState): { color: [number, number, number]; speed: number; spread: number } {
  if (state === 'listening') return { color: [196, 236, 214], speed: 0.35, spread: 1 }
  if (state === 'thinking') return { color: [236, 230, 255], speed: 1.4, spread: 0.9 }
  if (state === 'working') return { color: [250, 226, 190], speed: 0.9, spread: 1.2 }
  if (state === 'speaking') return { color: [255, 255, 255], speed: 0.6, spread: 1 }
  return { color: [242, 239, 233], speed: 0, spread: 1 }
}

/** The tilt toward the viewer, so the constellation reads as a ball rather than a ring. */
const TILT = 0.45

/**
 * Points spread evenly on a unit sphere (a golden-angle spiral), turned
 * about the vertical axis by `angle` and tilted toward the viewer.
 */
export function orbPoints(count: number, angle: number): OrbPoint[] {
  const out: OrbPoint[] = []
  for (let i = 0; i < count; i++) {
    const y0 = 1 - (i / (count - 1)) * 2
    const ring = Math.sqrt(1 - y0 * y0)
    const a = i * 2.39996 + angle
    const x = Math.cos(a) * ring
    const z0 = Math.sin(a) * ring
    out.push({
      x,
      y: y0 * Math.cos(TILT) - z0 * Math.sin(TILT),
      z: y0 * Math.sin(TILT) + z0 * Math.cos(TILT),
    })
  }
  return out
}

/** A point's dot: bigger and brighter the nearer it is (radius in px for a given core size, and opacity). */
export function orbDot(point: OrbPoint, core: number): { radius: number; alpha: number } {
  const near = (point.z + 1) / 2
  // Tiny orbs (the Ask bar's 30 px one) keep their dots visible.
  const unit = Math.max(core / 120, 0.35)
  return { radius: (0.7 + near * 1.5) * unit, alpha: 0.18 + near * 0.8 }
}
