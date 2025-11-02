/// <reference types="vitest" />

import { defineConfig } from "vite";

export default defineConfig({
  test: {
    environment: "clarinet",
    singleThread: true,
    setupFiles: [
      "node_modules/@hirosystems/clarinet-sdk/vitest-helpers/src/vitest.setup.ts",
    ],
    environmentOptions: {
      clarinet: {
        manifestPath: "./Clarinet.toml",
        coverage: false,
        costs: false,
        initBeforeEach: false,
      },
    },
  },
});
