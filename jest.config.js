const { jestConfig } = require("@salesforce/sfdx-lwc-jest/config");

module.exports = {
  ...jestConfig,
  modulePathIgnorePatterns: ["<rootDir>/.localdevserver"],
  collectCoverageFrom: [
    "force-app/main/default/lwc/**/*.js",
    "!force-app/main/default/lwc/**/*.html",
    "!force-app/main/default/lwc/**/*.css",
    "!force-app/main/default/lwc/**/__tests__/**",
    "!force-app/main/default/lwc/**/*.js-meta.xml"
  ],
  coverageThreshold: {
    global: {
      branches: 75,
      functions: 90,
      lines: 85,
      statements: 85
    }
  }
};
