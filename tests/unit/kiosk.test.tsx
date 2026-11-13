// Kiosk mode: the order it moves through the tabs, when it waits, what
// Money shows there, and the button that starts and stops it.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, render, renderHook, screen } from '@testing-library/react'
import { KIOSK_DWELL_MS, KIOSK_IDLE_MS, KIOSK_VIEWS, kioskDueAt, nextKioskView } from '../../src/lib/kiosk'
import { kioskPurchases } from '../../src/lib/money'
import { KioskMode, useKiosk } from '../../src/useKiosk'
import { useHashView } from '../../src/useHashView'
import { Money } from '../../src/views/Money'
import { TopNav } from '../../src/components/TopNav'
import { createMockSource } from '../../server/sources/mock.mjs'
import type { MoneyTransaction, Snapshot } from '../../src/types'

const now = new Date('2026-11-10T18:00:00Z')

beforeEach(() => {
  window.location.hash = ''
  localStorage.clear()
})
afterEach(() => {
  vi.useRealTimers()
  delete document.documentElement.dataset.modal
})

describe('kiosk order and timing', () => {
  it('goes Overview, Home, Claude, Money, Services, Schedule, then back to Overview', () => {
    expect(KIOSK_VIEWS).toEqual(['overview', 'home', 'claude', 'money', 'services', 'schedule'])
    expect(nextKioskView('overview')).toBe('home')
    expect(nextKioskView('money')).toBe('services')
    expect(nextKioskView('schedule')).toBe('overview')
    // Settings isn't in the cycle, so it starts over.
    expect(nextKioskView('preferences')).toBe('overview')
  })

  it('waits a full dwell on each tab, and a full idle wait after a touch', () => {
    const shown = Date.parse('2026-11-13T09:00:00Z')
    // Never touched: just the dwell.
    expect(kioskDueAt(shown, 0)).toBe(shown + KIOSK_DWELL_MS)
    expect(kioskDueAt(shown, shown + 5000)).toBe(shown + 5000 + KIOSK_IDLE_MS)
  })
})

describe('kioskPurchases', () => {
  it('keeps purchases only: no pay, refunds or transfers', () => {
    const tx = (id: string, amount: number, type?: MoneyTransaction['type']): MoneyTransaction => ({ id, date: '2026-11-10', merchant: id, category: 'x', amount, type })
    const kept = kioskPurchases([tx('coffee', 5), tx('pay', -3000, 'income'), tx('refund', -20), tx('move', 500, 'transfer'), tx('odd', 10, 'income'), tx('shoes', 90, 'regular')])
    expect(kept.map((t) => t.id)).toEqual(['coffee', 'shoes'])
  })
})

describe('useKiosk', () => {
  /** The hook as App uses it, reading the page from the hash. */
  const renderKiosk = () => renderHook(() => useKiosk(useHashView()))

  it('moves to the next tab after the dwell, and is remembered', () => {
    vi.useFakeTimers()
    const { result } = renderKiosk()
    expect(result.current.on).toBe(false)
    act(() => result.current.start())
    expect(result.current.on).toBe(true)
    expect(localStorage.getItem('home-lab:v1:kiosk')).toBe('on')
    act(() => { vi.advanceTimersByTime(KIOSK_DWELL_MS - 2000) })
    expect(window.location.hash).toBe('')
    act(() => { vi.advanceTimersByTime(3000) })
    expect(window.location.hash).toBe('#home')
    act(() => result.current.stop())
    expect(localStorage.getItem('home-lab:v1:kiosk')).toBe('off')
  })

  it('waits a minute after a touch, and stays put while a pop-up is open', () => {
    vi.useFakeTimers()
    const { result } = renderKiosk()
    act(() => result.current.start())
    act(() => { vi.advanceTimersByTime(5000) })
    act(() => { window.dispatchEvent(new Event('pointerdown')) })
    act(() => { vi.advanceTimersByTime(KIOSK_DWELL_MS) })
    expect(window.location.hash).toBe('')
    document.documentElement.dataset.modal = ''
    act(() => { vi.advanceTimersByTime(KIOSK_IDLE_MS * 2) })
    expect(window.location.hash).toBe('')
    delete document.documentElement.dataset.modal
    act(() => { vi.advanceTimersByTime(KIOSK_IDLE_MS + 2000) })
    expect(window.location.hash).toBe('#home')
  })

  it('starts from the Overview when turned on in Settings', () => {
    window.location.hash = '#preferences'
    const { result } = renderKiosk()
    act(() => result.current.start())
    expect(window.location.hash).toBe('#overview')
  })
})

describe('kiosk on the page', () => {
  it('the top bar has a Kiosk mode button, and in kiosk mode just Close', () => {
    const onKiosk = vi.fn()
    const onClose = vi.fn()
    const { rerender } = render(<TopNav view="overview" source="mock" refreshing={false} onRefresh={() => {}} kiosk={false} onKiosk={onKiosk} onKioskClose={onClose} />)
    screen.getByRole('button', { name: 'Kiosk mode' }).click()
    expect(onKiosk).toHaveBeenCalled()
    rerender(<TopNav view="overview" source="mock" refreshing={false} onRefresh={() => {}} kiosk onKiosk={onKiosk} onKioskClose={onClose} />)
    expect(screen.queryByRole('button', { name: 'Refresh now' })).not.toBeInTheDocument()
    const close = screen.getByRole('button', { name: 'Close kiosk mode' })
    expect(close).toHaveTextContent('Close')
    close.click()
    expect(onClose).toHaveBeenCalled()
  })

  it('Money in kiosk mode shows recent purchases with amounts, and no net worth, balances or pay', async () => {
    const data = (await createMockSource().snapshot()) as Snapshot
    render(<KioskMode.Provider value><Money data={data} now={now} /></KioskMode.Provider>)
    expect(screen.getByRole('heading', { name: 'Recent purchases' })).toBeInTheDocument()
    for (const gone of ['Net worth', 'Cash', 'Card balances', 'Accounts', 'This month', 'Worth a look']) {
      expect(screen.queryByRole('heading', { name: gone })).not.toBeInTheDocument()
    }
    expect(screen.queryByRole('button', { name: 'Show amounts' })).not.toBeInTheDocument()
    expect(screen.queryByLabelText('hidden')).not.toBeInTheDocument()
    expect(screen.queryByText('Payroll')).not.toBeInTheDocument()
    expect(screen.queryByText('$48,210')).not.toBeInTheDocument()
    expect(screen.getAllByText(/^\$\d/).length).toBeGreaterThan(2)
  })

  it('kiosk mode does not open an account from the hash', async () => {
    const data = (await createMockSource().snapshot()) as Snapshot
    const account = data.cloud!.money!.accounts[0]
    window.location.hash = `#money/a/${account.id}`
    render(<KioskMode.Provider value><Money data={data} now={now} /></KioskMode.Provider>)
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })
})
