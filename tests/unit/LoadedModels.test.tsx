// What's in GPU memory on the Services page: each model with its job,
// memory and when it unloads.
import { describe, expect, it } from 'vitest'
import { render, screen } from '@testing-library/react'
import { LoadedModels } from '../../src/components/LoadedModels'

const now = new Date('2026-11-11T01:00:00Z')

describe('LoadedModels', () => {
  it('says what the watch model does, its memory and when it unloads', () => {
    render(<LoadedModels now={now} models={[
      { name: 'ornith-1.5:9b', role: 'watch', vramGb: 5.3, until: '2026-11-11T01:52:00Z', parameters: '9.7B', quantization: 'Q4_K_M', contextLength: 8192 },
      { name: 'gemma4:12b', role: 'chat', vramGb: 4.1, until: null, parameters: null, quantization: null, contextLength: null },
    ]} />)
    expect(screen.getByText('9.4 of 12 GB used by models')).toBeInTheDocument()
    expect(screen.getByText(/in the background, and answers when Claude/)).toBeInTheDocument()
    expect(screen.getByText(/Unloads in 52 min if unused · 9.7B parameters · Q4_K_M · 8,192 token context/)).toBeInTheDocument()
    expect(screen.getByText(/Chat model for Jarvis/)).toBeInTheDocument()
    expect(screen.getByText('Stays loaded')).toBeInTheDocument()
  })

  it('says when nothing is loaded', () => {
    render(<LoadedModels now={now} models={[]} />)
    expect(screen.getByText(/No model is loaded/)).toBeInTheDocument()
  })
})
