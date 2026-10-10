import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    include: ['services/enrichment-evals/**/*.test.ts'],
    setupFiles: ['services/enrichment-evals/offline.ts'],
    testTimeout: 5_000,
  },
});
