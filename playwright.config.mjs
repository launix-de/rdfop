import { defineConfig } from '@playwright/test';

const baseURL = process.env.RDFOP_BASE_URL || 'http://localhost:3443';
const port = new URL(baseURL).port || '3443';

export default defineConfig({
  testDir: './tests',
  timeout: 30000,
  fullyParallel: false,
  workers: 1,
  use: {
    baseURL,
    headless: true,
  },
  webServer: {
    command: `./run.sh --api-port=${port}`,
    url: `${baseURL}/view/main`,
    reuseExistingServer: true,
    timeout: 120000,
  },
});
