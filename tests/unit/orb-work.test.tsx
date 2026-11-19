// @vitest-environment jsdom
import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'
import { JarvisOrb } from '../../src/components/JarvisOrb'
import type { RunningTask } from '../../src/types'

afterEach(cleanup)

const job: RunningTask = { id: 'r1', label: 'Making drive times mention parking', state: 'running', startedAt: null, model: null, step: null }

describe('the orb\'s work dots', () => {
  it('has nothing to tap when no work is running', () => {
    render(<JarvisOrb state="idle" size={64} />)
    expect(screen.queryByRole('button')).toBeNull()
  })

  it('opens a note for a lit dot, and Close shuts it', () => {
    render(<JarvisOrb state="idle" size={64} work={[job]} />)
    const dot = screen.getByRole('button', { name: 'Jarvis is working: Making drive times mention parking' })
    fireEvent.click(dot)
    expect(screen.getByRole('status').textContent).toContain('Making drive times mention parking')
    expect(screen.getByRole('status').textContent).toContain('Running')
    fireEvent.click(screen.getByRole('button', { name: 'Close' }))
    expect(screen.queryByRole('status')).toBeNull()
  })

  it('closes the note on a tap anywhere else, and when the job finishes', () => {
    const { rerender } = render(<JarvisOrb state="idle" size={64} work={[job]} />)
    const name = 'Jarvis is working: Making drive times mention parking'
    fireEvent.click(screen.getByRole('button', { name }))
    fireEvent.pointerDown(document.body)
    expect(screen.queryByRole('status')).toBeNull()
    fireEvent.click(screen.getByRole('button', { name }))
    rerender(<JarvisOrb state="idle" size={64} work={[]} />)
    expect(screen.queryByRole('status')).toBeNull()
  })
})
