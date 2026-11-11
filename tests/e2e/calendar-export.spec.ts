import { readFile } from 'node:fs/promises';
import { expect, test } from '@playwright/test';

/**
 * The calendar of events offers two downloads. Each one must produce a real
 * file with the dated name and the right magic bytes: `PK` for the zipped
 * `.docx`, `%PDF-` for the PDF.
 */
test.describe('calendar downloads', () => {
  test.skip(
    !process.env.SIMS_TEST_EMAIL || !process.env.SIMS_TEST_PASSWORD,
    'set SIMS_TEST_EMAIL and SIMS_TEST_PASSWORD to run the calendar download tests',
  );

  test('the calendar of events downloads as Word and as PDF', async ({ page }) => {
    const response = await page.goto('/calendar', { waitUntil: 'domcontentloaded' });
    expect(response?.status(), '/calendar must answer with 200').toBe(200);

    await expect(page.getByRole('heading', { name: 'Calendar of events', exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Download Word' })).toBeEnabled();
    await expect(page.getByRole('button', { name: 'Download PDF' })).toBeEnabled();

    const wordDownload = page.waitForEvent('download');
    await page.getByRole('button', { name: 'Download Word' }).click();
    const word = await wordDownload;
    expect(word.suggestedFilename()).toMatch(/^calendar-of-events-\d{4}-\d{2}-\d{2}\.docx$/);
    const wordPath = await word.path();
    if (!wordPath) throw new Error('the Word download never reached disk');
    const wordBytes = await readFile(wordPath);
    // A .docx is a zip archive: it opens with the "PK" local-file header.
    expect(wordBytes.subarray(0, 2).toString('latin1')).toBe('PK');
    expect(wordBytes.byteLength).toBeGreaterThan(1000);

    const pdfDownload = page.waitForEvent('download');
    await page.getByRole('button', { name: 'Download PDF' }).click();
    const pdf = await pdfDownload;
    expect(pdf.suggestedFilename()).toMatch(/^calendar-of-events-\d{4}-\d{2}-\d{2}\.pdf$/);
    const pdfPath = await pdf.path();
    if (!pdfPath) throw new Error('the PDF download never reached disk');
    const pdfBytes = await readFile(pdfPath);
    expect(pdfBytes.subarray(0, 5).toString('latin1')).toBe('%PDF-');
    expect(pdfBytes.byteLength).toBeGreaterThan(1000);
  });
});
