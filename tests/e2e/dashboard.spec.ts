// User stories, on desktop and phone:
//   - I open the page and see how jarvis is doing.
//   - I move between Overview, Services, Schedule and Settings, and it glides.
//   - I unload Gemma before gaming, and see it working until it's done.
//   - I pick a sky in Settings and it's remembered.
//   - The first load lands with a show; with reduced motion on, nothing moves.
//   - I tap any money row, Today row, event or email for a pop-up with more, and links out.
//   - Purchases still in "Other" stand out so I know to sort them.
//   - The iPad can stay on as a wall display, with the whole Overview on one screen.
//   - I swipe sideways to change tab.
//   - In Safari, changing tab never shows the panels dark before they frost.
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

test('an alert is a banner across the top, not a row in Today, and Close hides it', async ({ page }) => {
  await page.goto('/')
  // The sample Jarvis is degraded.
  const banner = page.getByRole('alert')
  await expect(banner).toContainText('Jarvis: Running, code changed since start')
  await expect(page.locator('.timeline')).not.toContainText('code changed since start')
  await expect(banner.getByRole('link')).toHaveAttribute('href', '#services')
  // It follows to every page.
  await page.getByRole('navigation', { name: 'Sections' }).getByRole('link', { name: 'Money' }).click()
  await expect(page.getByRole('alert')).toBeVisible()
  await page.getByRole('alert').getByRole('button', { name: 'Close' }).click()
  await expect(page.getByRole('alert')).toHaveCount(0)
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
    // Safari (the iPad) changes page without one; it slides the contents instead.
    const safari = await page.evaluate(() => /AppleWebKit/.test(navigator.userAgent) && !/Chrome/.test(navigator.userAgent))
    expect(transitions).toBe(reducedMotion === 'reduce' || safari ? 0 : 1)
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

test('the thermostat shows the room temperature, and + and the mode buttons change it', async ({ page }) => {
  await page.goto('/#home')
  const tile = page.getByRole('region', { name: 'Thermostat' })
  await expect(tile).toBeVisible()
  await expect(tile.getByText('Inside')).toBeVisible()
  // The thermostat comes first on the page.
  await expect(page.locator('.grid--devices > .device').first()).toHaveAttribute('aria-label', 'Thermostat')
  const target = tile.locator('.thermo__target')
  const before = Number((await target.textContent())!.replace(/\D/g, ''))
  // Two quick taps send one command, for two steps.
  const sent = page.waitForRequest((r) => r.url().endsWith('/api/home/control'))
  await tile.getByRole('button', { name: 'Warmer' }).click()
  await tile.getByRole('button', { name: 'Warmer' }).click()
  await expect(target).toContainText(`${before + 2}°`)
  expect((await sent).postDataJSON()).toEqual({ entity: 'climate.thermostat', command: 'target', value: before + 2 })
  // Back down, and modes are buttons that show which one is on.
  await tile.getByRole('button', { name: 'Cooler' }).click()
  await tile.getByRole('button', { name: 'Cooler' }).click()
  const heat = tile.getByRole('group', { name: 'Mode' }).getByRole('button', { name: 'Heat', exact: true })
  await expect(heat).toHaveAttribute('aria-pressed', 'true')
  const box = (await heat.boundingBox())!
  expect(box.height).toBeGreaterThanOrEqual(44)
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

/** Swipes across the page with one finger, from (x1, y) to (x2, y). */
async function swipe(page: import('@playwright/test').Page, x1: number, x2: number, y: number) {
  await page.evaluate(([a, b, yy]) => {
    const target = document.elementFromPoint(a, yy) ?? document.body
    const touch = (x: number) => new Touch({ identifier: 1, target, clientX: x, clientY: yy })
    target.dispatchEvent(new TouchEvent('touchstart', { bubbles: true, touches: [touch(a)], changedTouches: [touch(a)] }))
    target.dispatchEvent(new TouchEvent('touchend', { bubbles: true, touches: [], changedTouches: [touch(b)] }))
  }, [x1, x2, y])
}

/** Puts one finger down at (x1, y) and drags it to (x2, y) without lifting it. */
async function dragFinger(page: import('@playwright/test').Page, x1: number, x2: number, y: number) {
  await page.evaluate(([a, b, yy]) => {
    const target = document.elementFromPoint(a, yy) ?? document.body
    const touch = (x: number) => new Touch({ identifier: 1, target, clientX: x, clientY: yy })
    target.dispatchEvent(new TouchEvent('touchstart', { bubbles: true, touches: [touch(a)], changedTouches: [touch(a)] }))
    for (let i = 1; i <= 8; i++) {
      const x = a + ((b - a) * i) / 8
      target.dispatchEvent(new TouchEvent('touchmove', { bubbles: true, touches: [touch(x)], changedTouches: [touch(x)] }))
    }
  }, [x1, x2, y])
}

/** Lifts the finger at (x, y). */
async function liftFinger(page: import('@playwright/test').Page, x: number, y: number) {
  await page.evaluate(([xx, yy]) => {
    const target = document.elementFromPoint(xx, yy) ?? document.body
    const touch = new Touch({ identifier: 1, target, clientX: xx, clientY: yy })
    target.dispatchEvent(new TouchEvent('touchend', { bubbles: true, touches: [], changedTouches: [touch] }))
  }, [x, y])
}

test('while swiping, the page follows the finger, and springs back from a short swipe', async ({ page }, info) => {
  test.skip(info.project.name === 'desktop', 'Swiping is for touch screens')
  await page.goto('/#home')
  await expect(page.getByRole('heading', { level: 1, name: 'Home' })).toBeVisible()
  await expect(page.locator('.shell[data-landing]')).toHaveCount(0, { timeout: 5000 })
  const { width, height } = page.viewportSize()!
  const y = Math.round(height * 0.6)
  const title = page.locator('.main .hero').first()
  const shift = () => title.evaluate((el) => new DOMMatrix(getComputedStyle(el).transform).m41 + (parseFloat(getComputedStyle(el).translate.split(' ')[0]) || 0))
  // Finger halfway across a short way: the title moves with it, the glass doesn't.
  await dragFinger(page, Math.round(width * 0.6), Math.round(width * 0.6) - 50, y)
  expect(await shift()).toBeLessThan(-10)
  const panel = page.locator('.main .glass').first()
  expect(await panel.evaluate((el) => getComputedStyle(el).translate)).toBe('none')
  // Too short to count: it springs back and stays on Home.
  await liftFinger(page, Math.round(width * 0.6) - 50, y)
  await expect.poll(() => page.locator('main.main').getAttribute('data-swipe')).toBeNull()
  expect(Math.abs(await shift())).toBeLessThan(1)
  await expect(page.getByRole('heading', { level: 1, name: 'Home' })).toBeVisible()
  // A long slow drag counts: the contents glide out and the next tab glides in.
  await dragFinger(page, Math.round(width * 0.8), Math.round(width * 0.3), y)
  await liftFinger(page, Math.round(width * 0.3), y)
  await expect(page.locator('main.main')).toHaveAttribute('data-swipe', 'leave')
  await expect(page.getByRole('heading', { level: 1, name: 'Claude' })).toBeVisible()
  await expect.poll(() => page.evaluate(() => document.documentElement.dataset.enter ?? 'done')).toBe('done')
  expect(await page.locator('main.main').getAttribute('data-swipe')).toBeNull()
})

test('on the iPad the whole Overview fits the screen with no scrolling', async ({ page }, info) => {
  test.skip(info.project.name === 'phone', 'A phone scrolls the Overview')
  await page.goto('/')
  await expect(page.getByRole('heading', { name: 'Ask Jarvis' })).toBeVisible()
  const extra = await page.evaluate(() => document.documentElement.scrollHeight - window.innerHeight)
  expect(extra).toBeLessThanOrEqual(0)
  // Today and the Claude threads are on screen, not pushed below it.
  for (const name of ['Today', 'Claude threads']) {
    const box = (await page.getByRole('heading', { name, exact: true }).boundingBox())!
    expect(box.y + box.height).toBeLessThan(page.viewportSize()!.height)
  }
})

test('the iPad held upright fits the Overview too', async ({ browser }) => {
  const context = await browser.newContext({ viewport: { width: 834, height: 1194 }, hasTouch: true, isMobile: true })
  const page = await context.newPage()
  await page.goto(test.info().project.use.baseURL + '/')
  await expect(page.getByRole('heading', { name: 'Ask Jarvis' })).toBeVisible()
  const extra = await page.evaluate(() => document.documentElement.scrollHeight - window.innerHeight)
  expect(extra).toBeLessThanOrEqual(0)
  await context.close()
})

test('swiping sideways changes tab, and not inside a text box', async ({ page }, info) => {
  test.skip(info.project.name === 'desktop', 'Swiping is for touch screens')
  await page.goto('/#home')
  await expect(page.getByRole('heading', { level: 1, name: 'Home' })).toBeVisible()
  const { width, height } = page.viewportSize()!
  const y = Math.round(height * 0.6)
  // Finger moving left: the next tab.
  await swipe(page, Math.round(width * 0.7), Math.round(width * 0.25), y)
  await expect(page.getByRole('heading', { level: 1, name: 'Claude' })).toBeVisible()
  // Moving right: back again.
  await swipe(page, Math.round(width * 0.25), Math.round(width * 0.7), y)
  await expect(page.getByRole('heading', { level: 1, name: 'Home' })).toBeVisible()
  // A short nudge isn't a swipe.
  await swipe(page, Math.round(width * 0.5), Math.round(width * 0.5) - 30, y)
  await expect(page.getByRole('heading', { level: 1, name: 'Home' })).toBeVisible()
  // Nor is a drag in the Ask Jarvis box.
  await page.goto('/')
  const input = (await page.getByRole('textbox', { name: 'Question for Jarvis' }).boundingBox())!
  await swipe(page, input.x + input.width * 0.8, input.x + 10, input.y + input.height / 2)
  await expect(page.getByRole('heading', { level: 1, name: /Dylan/ })).toBeVisible()
})

test('in Safari, changing tab keeps the glass frosted and slides the contents in', async ({ browser }) => {
  const context = await browser.newContext({
    viewport: { width: 1194, height: 834 },
    userAgent: 'Mozilla/5.0 (iPad; CPU OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1',
  })
  const page = await context.newPage()
  await page.goto(test.info().project.use.baseURL + '/')
  await expect(page.getByRole('heading', { name: 'Ask Jarvis' })).toBeVisible()
  await expect(page.locator('.shell[data-landing]')).toHaveCount(0, { timeout: 5000 })
  await page.evaluate(() => {
    const w = window as unknown as { transitions: number }
    w.transitions = 0
    const start = document.startViewTransition.bind(document)
    document.startViewTransition = ((cb?: () => void) => { w.transitions++; return start(cb) }) as typeof document.startViewTransition
  })
  await page.getByRole('navigation', { name: 'Sections' }).getByRole('link', { name: 'Money' }).click()
  await expect(page.getByRole('heading', { level: 1, name: 'Money' })).toBeVisible()
  // No snapshot crossfade; the live glass is there, frosted, from the first frame.
  expect(await page.evaluate(() => (window as unknown as { transitions: number }).transitions)).toBe(0)
  expect(await page.evaluate(() => document.documentElement.dataset.enter)).toBe('next')
  const blur = await page.locator('.main .glass').first().evaluate((el) => getComputedStyle(el).backdropFilter)
  expect(blur).toContain('blur(26px)')
  await expect.poll(() => page.evaluate(() => document.documentElement.dataset.enter ?? 'done')).toBe('done')
  await context.close()
})

test('while the first snapshot is on its way, a full-page "Jarvis is thinking" loader shows, still with reduced motion', async ({ browser }) => {
  for (const reducedMotion of ['no-preference', 'reduce'] as const) {
    const context = await browser.newContext({ reducedMotion })
    const page = await context.newPage()
    // Hold the first snapshot back so the loader can be seen.
    let release = () => {}
    const held = new Promise<void>((resolve) => { release = resolve })
    await page.route('**/api/snapshot', async (route) => { await held; await route.continue() })
    await page.goto(test.info().project.use.baseURL + '/')
    const loader = page.getByRole('status').filter({ hasText: 'Jarvis is thinking' })
    await expect(loader).toBeVisible()
    const moving = await page.evaluate(() => document.getAnimations().filter((a) => (a.effect as KeyframeEffect | null)?.target instanceof Element && ((a.effect as KeyframeEffect).target as Element).closest('.thinking')).length)
    if (reducedMotion === 'reduce') expect(moving).toBe(0)
    else expect(moving).toBeGreaterThan(3)
    release()
    await expect(page.getByRole('heading', { name: 'Ask Jarvis' })).toBeVisible()
    await expect(loader).toHaveCount(0)
    await context.close()
  }
})
