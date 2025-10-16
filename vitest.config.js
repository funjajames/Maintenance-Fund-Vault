/// <reference types="vitest" />

import { defineConfig } from "vite";

export default defineConfig({
  test: {
    environment: "clarinet",
    singleThread: true,
  },
});