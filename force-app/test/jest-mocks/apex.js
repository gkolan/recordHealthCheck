// Generic stub for @salesforce/apex/* imports in Jest.
// Each import becomes an independent jest.fn() via jest.genMockFromModule,
// but since this module just exports a function, tests must call
// jest.mock('@salesforce/apex/...', () => jest.fn(), { virtual: true })
// or override via mockResolvedValue / mockImplementation per test.
const fn = jest.fn();
module.exports = fn;
