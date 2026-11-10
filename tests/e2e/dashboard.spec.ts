// User stories, on desktop and phone:
//   - I open the page and see how jarvis is doing.
//   - I move between Overview, Services, Schedule and Settings, and it glides.
//   - I switch a light, dim a lamp and unlock the door from the Home page.
//   - I unload Gemma before gaming, and see it working until it's done.
//   - I pick a sky in Settings and it's remembered.
//   - With reduced motion on, nothing moves.
import { expect, test } from '@playwright/test'

test('overview shows the PC at a glance', async ({ page }) => {
  await page.goto('/')
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Dylan')
  for (const label of ['Memory', 'GPU memory', 'Processor', 'Free on C:']) {
    await expect(page.getByRole('heading', { name: label, exact: true })).toBeVisible()
  }
  await expect(page.getByRole('heading', { name: 'Ask Jarvis' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Today', exact: true })).toBeVisible()
  // Kept to a glance: the chart, services and Gemma live on their own pages.
  await expect(page.getByRole('heading', { name: 'Jarvis requests' })).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'Unload Gemma' })).toHaveCount(0)
})

test('Schedule has the requests chart; Services has every service and the Gemma card', async ({ page }) => {
  await page.goto('/#schedule')
  await expect(page.getByRole('heading', { name: 'Jarvis requests' })).toBeVisible()
  await page.goto('/#services')
  await expect(page.getByRole('link', { name: 'Open Home Assistant' })).toHaveAttribute('href', 'http://192.168.68.94:8123')
  await expect(page.getByRole('button', { name: 'Unload Gemma' })).toBeVisible()
})

test('changing page cross-fades and slides the pill light, and never with reduced motion', async ({ browser }) => {
  for (const reducedMotion of ['no-preference', 'reduce'] as const) {
    const context = await browser.newContext({ reducedMotion })
    const page = await context.newPage()
    await page.goto(test.info().project.use.baseURL + '/')
    await expect(page.getByRole('heading', { name: 'Ask Jarvis' })).toBeVisible()
    // Count view transitions the page starts.
    await page.evaluate(() => {
      const w = window as unknown as { transitions: number }
      w.transitions = 0
      const start = document.startViewTransition.bind(document)
      document.startViewTransition = ((cb?: () => void) => { w.transitions++; return start(cb) }) as typeof document.startViewTransition
    })
    const nav = page.getByRole('navigation', { name: 'Sections' })
    await nav.getByRole('link', { name: 'Services' }).click()
    await expect(page.getByRole('heading', { level: 1, name: 'Services' })).toBeVisible()
    const transitions = await page.evaluate(() => (window as unknown as { transitions: number }).transitions)
    expect(transitions).toBe(reducedMotion === 'reduce' ? 0 : 1)
    // One light, sitting under the current pill once it settles.
    await expect(nav.locator('.pills__light')).toHaveCount(1)
    const current = await nav.getByRole('link', { name: 'Services' }).boundingBox()
    // Within a pixel: the bar's 1 px border and subpixel layout can round either way.
    await expect.poll(async () => Math.abs((await nav.locator('.pills__light').boundingBox())!.x - current!.x)).toBeLessThanOrEqual(1.5)
    await context.close()
  }
})

test('pill navigation reaches every page and keeps the back button working', async ({ page }) => {
  await page.goto('/')
  const nav = page.getByRole('navigation', { name: 'Sections' })
  for (const name of ['Home', 'Money', 'Services', 'Schedule', 'Settings']) {
    await nav.getByRole('link', { name }).click()
    await expect(page.getByRole('heading', { level: 1, name })).toBeVisible()
    await expect(nav.getByRole('link', { name })).toHaveAttribute('aria-current', 'page')
  }
  await page.goBack()
  await expect(page.getByRole('heading', { level: 1, name: 'Schedule' })).toBeVisible()
})

test('unloading Gemma blocks the dialog until it finishes, then loading it back works', async ({ page }) => {
  await page.goto('/#services')
  await page.getByRole('button', { name: 'Unload Gemma' }).click()
  const dialog = page.getByRole('dialog')
  await expect(dialog).toContainText('Unload Gemma?')
  await expect(dialog.getByRole('button', { name: 'Close' })).toBeVisible()

  await dialog.getByRole('button', { name: 'Unload', exact: true }).click()
  await expect(dialog.getByText('Unloading Gemma…')).toBeVisible()
  await expect(dialog.getByRole('button', { name: 'Close' })).toBeDisabled()

  await expect(page.getByRole('status').filter({ hasText: 'Gemma unloaded' })).toBeVisible()
  await expect(page.getByText('Unloaded', { exact: true })).toBeVisible()

  // Put it back so the next test starts from the same state.
  await page.getByRole('button', { name: 'Load Gemma' }).click()
  await page.getByRole('dialog').getByRole('button', { name: 'Load', exact: true }).click()
  await expect(page.getByRole('button', { name: 'Unload Gemma' })).toBeVisible({ timeout: 10_000 })
})

test('Close dismisses the dialog with Esc or the button', async ({ page }) => {
  await page.goto('/#services')
  await page.getByRole('button', { name: 'Unload Gemma' }).click()
  await page.keyboard.press('Escape')
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await page.getByRole('button', { name: 'Unload Gemma' }).click()
  await page.getByRole('dialog').getByRole('button', { name: 'Close' }).click()
  await expect(page.getByRole('dialog')).toHaveCount(0)
})

test('the sky choice is remembered across reloads', async ({ page }) => {
  await page.goto('/#preferences')
  await page.getByRole('radio', { name: 'Night' }).click()
  await expect(page.locator('.backdrop')).toHaveAttribute('data-phase', 'night')
  await page.reload()
  await expect(page.getByRole('radio', { name: 'Night' })).toHaveAttribute('aria-checked', 'true')
  await expect(page.locator('.backdrop')).toHaveAttribute('data-phase', 'night')
})

test('nothing animates with reduced motion', async ({ browser }) => {
  const context = await browser.newContext({ reducedMotion: 'reduce' })
  const page = await context.newPage()
  await page.goto(test.info().project.use.baseURL + '/')
  await expect(page.getByRole('heading', { name: 'Ask Jarvis' })).toBeVisible()
  const running = await page.evaluate(() => document.getAnimations().length)
  expect(running).toBe(0)
  await context.close()
})

test('no sideways scrolling', async ({ page }) => {
  await page.goto('/')
  await expect(page.getByRole('heading', { name: 'Ask Jarvis' })).toBeVisible()
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
  expect(overflow).toBeLessThanOrEqual(0)
})

test('the Claude page shows threads waiting on me first, linked to the thread', async ({ page }) => {
  await page.goto('/')
  await page.getByRole('navigation', { name: 'Sections' }).getByRole('link', { name: 'Claude' }).click()
  await expect(page.getByRole('heading', { level: 1, name: 'Claude' })).toBeVisible()
  const threads = page.getByRole('region', { name: 'Claude threads' })
  await expect(threads.getByRole('heading', { level: 3 }).first()).toHaveText(/Waiting on you/)
  await expect(threads.getByRole('link', { name: 'Fix unverified app warning on calendar picker' })).toHaveAttribute('target', '_blank')
  await expect(page.getByRole('region', { name: 'Shipping' })).toContainText('tapworship.com')
})

test('Home: tap a light on and off, with a spinner while Home Assistant works', async ({ page }) => {
  await page.goto('/#home')
  await expect(page.getByRole('heading', { level: 1, name: 'Home' })).toBeVisible()
  const porch = page.getByRole('button', { name: 'Porch light' })
  await expect(porch).toHaveAttribute('aria-pressed', 'false')
  await porch.click()
  await expect(page.getByText('Turning on…')).toBeVisible()
  await expect(page.getByRole('status').filter({ hasText: 'Porch light turned on' })).toBeVisible()
  await expect(porch).toHaveAttribute('aria-pressed', 'true')
  await expect(page.locator('.hero__sub')).toContainText('2 lights on')
  // Put it back for the next test.
  await porch.click()
  await expect(porch).toHaveAttribute('aria-pressed', 'false')
})

test('Home: dimming a lamp sends the level once you let go', async ({ page }) => {
  await page.goto('/#home')
  const slider = page.getByRole('slider', { name: 'Living room lamp brightness' })
  await expect(slider).toHaveValue('60')
  await slider.focus()
  await page.keyboard.press('ArrowRight')
  await expect(page.getByRole('status').filter({ hasText: 'Living room lamp set to 61%' })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Living room lamp' })).toContainText('On, 61%')
  await page.keyboard.press('ArrowLeft')
  await expect(page.getByRole('button', { name: 'Living room lamp' })).toContainText('On, 60%')
})

test('Home: unlocking the front door asks first, and Close leaves it locked', async ({ page }) => {
  await page.goto('/#home')
  await page.getByRole('button', { name: 'Unlock Front door' }).click()
  const dialog = page.getByRole('dialog')
  await expect(dialog).toContainText('Unlock Front door?')
  await dialog.getByRole('button', { name: 'Close' }).click()
  await expect(page.getByRole('button', { name: 'Unlock Front door' })).toContainText('Locked')

  await page.getByRole('button', { name: 'Unlock Front door' }).click()
  await page.getByRole('dialog').getByRole('button', { name: 'Unlock', exact: true }).click()
  await expect(page.getByRole('dialog').getByText('Unlocking…')).toBeVisible()
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await expect(page.locator('.hero__sub')).toContainText('Front door unlocked')
  // Locking needs no confirm.
  await page.getByRole('button', { name: 'Lock Front door' }).click()
  await expect(page.getByRole('button', { name: 'Unlock Front door' })).toContainText('Locked')
})

test('Home: the thermostat steps one degree, and the page never scrolls sideways', async ({ page }) => {
  await page.goto('/#home')
  const thermostat = page.getByRole('button', { name: 'Thermostat', exact: true })
  await expect(thermostat).toContainText('Heat to 70°')
  await page.getByRole('button', { name: 'Raise Thermostat' }).click()
  await expect(thermostat).toContainText('Heat to 71°')
  await page.getByRole('button', { name: 'Lower Thermostat' }).click()
  await expect(thermostat).toContainText('Heat to 70°')
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
  expect(overflow).toBeLessThanOrEqual(0)
})

test('Home: a TV that is playing can pause and change volume', async ({ page }) => {
  await page.goto('/#home')
  const tv = page.getByRole('button', { name: 'Living room Apple TV', exact: true })
  await expect(tv).toContainText('Playing')
  await page.getByRole('button', { name: 'Pause Living room Apple TV' }).click()
  await expect(tv).toContainText('Paused')
  await page.getByRole('button', { name: 'Play Living room Apple TV' }).click()
  await expect(tv).toContainText('Playing')
  await expect(page.getByRole('slider', { name: 'Living room Apple TV volume' })).toHaveValue('30')
})
