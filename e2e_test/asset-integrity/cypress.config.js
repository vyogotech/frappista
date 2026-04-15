const { defineConfig } = require("cypress");

const BASE_URL = process.env.BASE_URL || "http://127.0.0.1:8001";

module.exports = defineConfig({
  e2e: {
    baseUrl: BASE_URL,
    specPattern: "cypress/e2e/**/*.cy.js",
    supportFile: false,
  },
  env: {
    BASE_URL,
    ADMIN_USER: process.env.ADMIN_USER || "Administrator",
    ADMIN_PASSWORD: process.env.ADMIN_PASSWORD || "admin",
  },
  video: false,
  screenshotOnRunFailure: true,
  screenshotsFolder: "cypress/screenshots",
});
