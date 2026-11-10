// The requests chart's bars grow in once per visit to the page, not every
// time Schedule is opened again (replaying it made tab changes stutter).
import { render } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { RequestsChart } from '../../src/components/RequestsChart'

const days = [{ day: 'Mon', count: 4, today: true }]

describe('RequestsChart', () => {
  it('grows in the first time only', () => {
    const first = render(<RequestsChart days={days} />)
    expect(first.container.querySelector('.chart')).toHaveAttribute('data-grow')
    first.unmount()
    const again = render(<RequestsChart days={days} />)
    expect(again.container.querySelector('.chart')).not.toHaveAttribute('data-grow')
  })
})
