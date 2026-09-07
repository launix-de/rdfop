import { test, expect } from '@playwright/test';
import { createHelpers } from './rdf-playwright-helpers.mjs';

function sortTests(cases) {
  return [...cases].sort((a, b) => {
    const ao = a.order ?? '';
    const bo = b.order ?? '';
    if (ao === bo) return String(a.id).localeCompare(String(b.id));
    if (!ao) return 1;
    if (!bo) return -1;
    return String(ao).localeCompare(String(bo));
  });
}

const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;

test('UUID generation falls back without crypto.randomUUID', async ({ page, baseURL }) => {
  await page.addInitScript(() => {
    Object.defineProperty(globalThis.crypto, 'randomUUID', {
      configurable: true,
      value: undefined,
    });
  });
  await page.goto(`${baseURL}/view/main`);
  const uuid = await page.evaluate(() => window.rdfopUUID());
  expect(uuid).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
});

test('embedded RDF Playwright suite', async ({ page, request, baseURL }) => {
  test.setTimeout(120000);
  const resp = await request.get(`${baseURL}/rdfop-playwright-tests`);
  expect(resp.ok()).toBeTruthy();
  const filter = process.env.RDFOP_TEST_FILTER || '';
  const body = await resp.text();
  const cases = sortTests(body.split('\n').filter(Boolean).map(line => {
    const row = JSON.parse(line);
    return {
      id: row['?id'],
      label: row['?label'],
      for: row['?target'],
      order: row['?ord'],
      code: row['?code'],
    };
  })).filter(tc => {
    if (!filter) return true;
    const hay = `${tc.id || ''}\n${tc.label || ''}\n${tc.for || ''}`;
    return hay.includes(filter);
  });
  expect(cases.length).toBeGreaterThan(0);
  for (const tc of cases) {
    await test.step(tc.label || tc.id, async () => {
      const browser = page.context().browser();
      const caseContext = await browser.newContext();
      const casePage = await caseContext.newPage();
      const helpers = createHelpers({ page: casePage, request, baseURL });
      const run = new AsyncFunction('page', 'request', 'expect', 'helpers', 'baseURL', tc.code);
      try {
        await run(casePage, request, expect, helpers, baseURL);
      } finally {
        await caseContext.close();
      }
    });
  }
});
