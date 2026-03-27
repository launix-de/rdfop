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

test('embedded RDF Playwright suite', async ({ page, request, baseURL }) => {
  const resp = await request.get(`${baseURL}/rdfop-playwright-tests`);
  expect(resp.ok()).toBeTruthy();
  const cases = sortTests(await resp.json());
  const helpers = createHelpers({ page, request, baseURL });
  for (const tc of cases) {
    await test.step(tc.label || tc.id, async () => {
      const run = new AsyncFunction('page', 'request', 'expect', 'helpers', 'baseURL', tc.code);
      await run(page, request, expect, helpers, baseURL);
    });
  }
});
