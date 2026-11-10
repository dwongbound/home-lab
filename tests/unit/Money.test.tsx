// The Money page: amounts hidden until asked, and what it says before
// Copilot data arrives.
import { describe, expect, it } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Money } from '../../src/views/Money'
import { createMockSource } from '../../server/sources/mock.mjs'
import type { Snapshot } from '../../src/types'

const now = new Date('2026-11-10T18:00:00Z')

async function snapshot(): Promise<Snapshot> {
  return (await createMockSource().snapshot()) as Snapshot
}

describe('Money', () => {
  it('hides every amount until Show amounts, then hides them again', async () => {
    const data = await snapshot()
    const user = userEvent.setup()
    render(<Money data={data} now={now} />)

    expect(screen.queryByText('$6,420.55')).not.toBeInTheDocument()
    expect(screen.getAllByLabelText('hidden').length).toBeGreaterThan(5)

    await user.click(screen.getByRole('button', { name: 'Show amounts' }))
    expect(screen.getByText('$6,420.55')).toBeInTheDocument()
    expect(screen.getByText('$48,210')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Hide amounts' })).toHaveAttribute('aria-pressed', 'true')

    await user.click(screen.getByRole('button', { name: 'Hide amounts' }))
    expect(screen.queryByText('$6,420.55')).not.toBeInTheDocument()
  })

  it('shows accounts, recent transactions with income as +, and flags', async () => {
    const user = userEvent.setup()
    render(<Money data={await snapshot()} now={now} />)
    await user.click(screen.getByRole('button', { name: 'Show amounts' }))
    expect(screen.getByRole('heading', { name: 'Accounts' })).toBeInTheDocument()
    expect(screen.getByText('Payroll')).toBeInTheDocument()
    expect(screen.getByText('$3,450.00').parentElement).toHaveTextContent('+$3,450.00')
    expect(screen.getByText(/Shopping is at 97%/)).toBeInTheDocument()
  })

  it('says the digest needs setting up when there is no digest', async () => {
    render(<Money data={{ ...(await snapshot()), cloud: null }} now={now} />)
    expect(screen.getByText(/once the Claude digest is set up/)).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Show amounts' })).not.toBeInTheDocument()
  })

  it('says Copilot is not connected yet when the digest has no money section', async () => {
    const data = await snapshot()
    render(<Money data={{ ...data, cloud: { ...data.cloud!, money: undefined } }} now={now} />)
    expect(screen.getByText(/starts reading your Copilot connector/)).toBeInTheDocument()
  })
})
