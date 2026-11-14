// /talk pausing without hanging up (Dylan, 2026-11-14): Pause dozes a
// Jarvis that can wake on "Hey Jarvis", he dozes by himself when you're
// done, and Talk or the wake word brings him back.
import { describe, expect, it, vi } from 'vitest'
import { act, render, screen, fireEvent } from '@testing-library/react'
import type { TalkHandlers, TalkLine } from '../../src/lib/talk'

let handlers: TalkHandlers | null = null
const line: TalkLine = { close: vi.fn(), setMuted: vi.fn(), canDoze: () => true, doze: vi.fn(), wake: vi.fn() }

vi.mock('../../src/lib/talk', () => ({
  canTalkUnprompted: async () => true,
  talkUrl: () => 'ws://x/api/jarvis/talk',
  openTalkLine: async (_url: string, on: TalkHandlers) => { handlers = on; return line },
}))
vi.mock('../../src/api/client', () => ({
  answerApproval: vi.fn(),
  loadApprovals: async () => [],
  loadChatHistory: async () => [],
  streamJarvis: vi.fn(),
  warmJarvis: async () => {},
}))

const { JarvisPanel } = await import('../../src/components/JarvisPanel')

describe('/talk dozing', () => {
  it('pauses into "Hey Jarvis" listening, wakes on Talk, and dozes by itself', async () => {
    HTMLDialogElement.prototype.showModal ??= function (this: HTMLDialogElement) { this.open = true }
    HTMLDialogElement.prototype.close ??= function (this: HTMLDialogElement) { this.open = false }
    render(<JarvisPanel live page />)
    const pause = await screen.findByRole('button', { name: 'Pause' })
    fireEvent.click(pause)
    expect(line.doze).toHaveBeenCalled()
    act(() => handlers!.onState('dozing'))
    expect(screen.getByRole('status')).toHaveTextContent('Paused. Say “Hey Jarvis” or tap Talk')
    fireEvent.click(screen.getByRole('button', { name: 'Talk' }))
    expect(line.wake).toHaveBeenCalled()
    expect(line.close).not.toHaveBeenCalled()
    act(() => handlers!.onState('listening'))
    expect(screen.getByRole('button', { name: 'Pause' })).toBeInTheDocument()
    // "Anything else?" "No, that's all.": he dozes on his own, line still open.
    act(() => handlers!.onState('dozing'))
    expect(screen.getByRole('button', { name: 'Talk' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Mute' })).toBeInTheDocument()
  })
})
