import { expect, type Page } from '@playwright/test';

/**
 * Wait until the page content has replaced the `Loading…` fallback.
 *
 * Next.js streams the page: the shell and the Suspense fallback arrive first,
 * the resolved content follows in a later chunk. So the test waits for the
 * **content** rather than for the fallback to disappear - at the moment the
 * document is parsed the fallback may not even be attached yet, and waiting
 * for it to vanish would pass on an empty page.
 *
 * React then reveals the streamed boundary with `requestAnimationFrame`. A
 * browser that is not painting - a background tab, a headless run that never
 * composites - never fires that callback, so the boundary stays pending even
 * though the server sent the content. When the content does not arrive in
 * time, the test flushes React's own reveal queue so the assertion stays
 * about the application and not about the compositor.
 */
export async function waitForContent(page: Page): Promise<void> {
  const main = page.locator('main');

  const hasContent = async () => {
    const text = (await main.innerText().catch(() => '')).trim();
    return text.length > 20 && !text.startsWith('Loading…');
  };

  try {
    await expect.poll(hasContent, { timeout: 15_000, intervals: [200] }).toBe(true);
    return;
  } catch {
    // The frame never came: flush React's queued reveal and try again.
    await page.evaluate(() => {
      const w = window as unknown as {
        $RV?: (queue: unknown[]) => void;
        $RB?: unknown[];
      };
      if (typeof w.$RV === 'function' && w.$RB && w.$RB.length) w.$RV(w.$RB);
    });
    await expect.poll(hasContent, { timeout: 15_000, intervals: [200] }).toBe(true);
  }
}
