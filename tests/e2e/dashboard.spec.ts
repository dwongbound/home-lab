// User stories, on desktop and phone:
//   - I open the page and see how jarvis is doing.
//   - I move between Overview, Services, Schedule and Settings, and it glides.
//   - I unload Gemma before gaming, and see it working until it's done.
//   - I pick a sky in Settings and it's remembered.
//   - The first load lands with a show; with reduced motion on, nothing moves.
//   - I tap any money row, Today row, event or email for a pop-up with more, and links out.
//   - Purchases still in "Other" stand out so I know to sort them.
//   - The iPad can stay on as a wall display.
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

test("Today on the overview combines alerts, the calendar and Jarvis's day", async ({ page }) => {
  await page.goto('/')
  const today = page.locator('.timeline')
  // The sample Jarvis is degraded, so an alert leads the list, whatever the time.
  await expect(today.locator('.timeline__item').first()).toContainText('Jarvis: Running, code changed since start')
  await expect(today.locator('.timeline__item').first()).toContainText('Alert')
})

test('opening the page asks Jarvis for a fresh digest, showing the last one meanwhile', async ({ page }) => {
  await page.goto('/#schedule')
  const calendar = page.locator('section', { has: page.getByRole('heading', { name: 'Calendar' }) })
  await expect(calendar.getByText('Updating from Jarvis…')).toBeVisible()
  // The last digest stays on screen while Jarvis works.
  await expect(calendar.getByText('Flight block N8318B')).toBeVisible()
  // The sample refresh takes 4 s; the page looks every 5 s.
  await expect(calendar.getByText('Updating from Jarvis…')).toHaveCount(0, { timeout: 15_000 })
  await expect(calendar.getByText('Updated just now')).toBeVisible()
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
  for (const name of ['Home', 'Money', 'Services', 'Shell', 'Schedule', 'Settings']) {
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

test('the first load lands with a show, once, and the glass ends fully frosted', async ({ page }) => {
  await page.goto('/')
  await expect(page.locator('.shell[data-landing]')).toHaveCount(1)
  await expect(page.locator('.backdrop[data-landing]')).toHaveCount(1)
  // It switches itself off, and changing page doesn't bring it back.
  await expect(page.locator('.shell[data-landing]')).toHaveCount(0, { timeout: 5000 })
  await page.getByRole('navigation', { name: 'Sections' }).getByRole('link', { name: 'Home' }).click()
  await expect(page.getByRole('heading', { level: 1, name: 'Home' })).toBeVisible()
  await expect(page.locator('[data-landing]')).toHaveCount(0)
  const blur = await page.locator('.main .glass').first().evaluate((el) => getComputedStyle(el).backdropFilter)
  expect(blur).toContain('blur(26px)')
})

test('Shell shows the terminal frame, and says so when the shell is off', async ({ page }) => {
  await page.goto('/#shell')
  await expect(page.getByRole('heading', { level: 1, name: 'Shell' })).toBeVisible()
  // The test server has no SHELL_USERS, so the frame explains instead of opening a terminal.
  const frame = page.frameLocator('iframe[title="Terminal on jarvis"]')
  await expect(frame.getByText('The shell is off')).toBeVisible()
  await expect(page.getByRole('link', { name: 'Open the terminal full screen' })).toHaveAttribute('href', './shell/')
  // The terminal spans the page's full content width, as wide as the hero above it.
  const frameWidth = await page.locator('iframe[title="Terminal on jarvis"]').evaluate((el) => el.getBoundingClientRect().width)
  const heroWidth = await page.locator('.hero').evaluate((el) => el.getBoundingClientRect().width)
  expect(frameWidth).toBeGreaterThan(heroWidth - 80)
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
  expect(overflow).toBeLessThanOrEqual(0)
})

test('Money flags purchases to sort, and every row opens a detail that Close and Back dismiss', async ({ page }) => {
  await page.goto('/#money')
  await expect(page.getByRole('heading', { level: 1, name: 'Money' })).toBeVisible()
  // The "undefined" from Venmo is gone, and the row is marked to sort.
  const venmo = page.getByRole('link', { name: /Venmo Alex/ })
  await expect(venmo).not.toContainText('undefined')
  await expect(venmo).toContainText('needs a category')
  // $0 accounts wait behind a button.
  await expect(page.getByText('Old Checking')).toHaveCount(0)

  await page.getByRole('link', { name: /One purchase needs a category/ }).click()
  const dialog = page.getByRole('dialog', { name: 'Needs a category' })
  await expect(dialog).toBeVisible()
  // From the list, straight into the purchase.
  await dialog.getByRole('link', { name: /Venmo Alex/ }).click()
  await expect(page.getByRole('dialog', { name: 'Venmo Alex' })).toContainText('Lesson')
  await page.getByRole('dialog').getByRole('button', { name: 'Close' }).click()
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await expect(page).toHaveURL(/#money$/)

  // An account shows what's been on it; Back closes the pop-up.
  await page.getByRole('link', { name: /Sapphire/ }).click()
  await expect(page.getByRole('dialog', { name: 'Sapphire' })).toContainText('Trader Joe’s')
  await page.goBack()
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await expect(page.getByRole('heading', { level: 1, name: 'Money' })).toBeVisible()
})

test('the detail pop-up fits the screen and stays one size', async ({ page }) => {
  await page.goto('/#money/sort')
  const dialog = page.getByRole('dialog', { name: 'Needs a category' })
  await expect(dialog).toBeVisible()
  const box = (await dialog.boundingBox())!
  const view = page.viewportSize()!
  expect(box.width).toBeLessThanOrEqual(view.width - 31)
  expect(box.height).toBeLessThanOrEqual(view.height - 31)
  await page.goto('/#money/t/x4')
  const other = (await page.getByRole('dialog', { name: 'Spotify' }).boundingBox())!
  expect(Math.round(other.height)).toBe(Math.round(box.height))
})

test('Today and calendar rows open their details, with a link to Google Calendar', async ({ page }) => {
  await page.goto('/#schedule')
  await page.locator('section', { has: page.getByRole('heading', { name: 'Calendar' }) }).getByRole('link', { name: /Flight block N8318B/ }).click()
  const dialog = page.getByRole('dialog', { name: 'Flight block N8318B' })
  await expect(dialog).toContainText('Santa Monica Airport')
  await expect(dialog.getByRole('link', { name: 'Open in Calendar' })).toHaveAttribute('target', '_blank')
  await dialog.getByRole('button', { name: 'Close' }).click()

  await page.getByRole('link', { name: /OAuth verification/ }).click()
  await expect(page.getByRole('dialog').getByRole('link', { name: 'Open in Gmail' })).toBeVisible()
  await page.keyboard.press('Escape')
  await expect(page.getByRole('dialog')).toHaveCount(0)

  await page.goto('/')
  await page.locator('.timeline').getByRole('link').first().click()
  await expect(page.getByRole('dialog')).toBeVisible()
})

test('Settings can keep the screen on, and remembers it', async ({ page }) => {
  await page.goto('/#preferences')
  const awake = page.getByRole('switch', { name: 'Keep the screen on' })
  await expect(awake).toHaveAttribute('aria-checked', 'false')
  await awake.click()
  await expect(awake).toHaveAttribute('aria-checked', 'true')
  await expect(page.getByRole('status').filter({ hasText: /^On\./ })).toBeVisible()
  await page.reload()
  await expect(page.getByRole('switch', { name: 'Keep the screen on' })).toHaveAttribute('aria-checked', 'true')
})

test('every page fits without sideways scrolling, and tappable rows are finger-sized on touch', async ({ page }, info) => {
  for (const hash of ['#money', '#schedule', '#home', '#preferences', '#claude']) {
    await page.goto('/' + hash)
    await expect(page.getByRole('heading', { level: 1 })).toBeVisible()
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
    expect(overflow, hash).toBeLessThanOrEqual(0)
  }
  if (info.project.name === 'desktop') return
  await page.goto('/#money')
  const heights = await page.locator('.row-link').evaluateAll((els) => els.map((el) => el.getBoundingClientRect().height))
  expect(Math.min(...heights)).toBeGreaterThanOrEqual(44)
})
