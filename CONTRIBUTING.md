# Contributing

Thanks for your interest in improving Record Health Check. This guide explains
how to report a bug, request a feature, and open a pull request. It is written so
that someone new to the project can follow it step by step.

Please read the [Code of Conduct](CODE_OF_CONDUCT.md) before participating. By
contributing, you agree that your contributions are licensed under the
[Apache License, Version 2.0](LICENSE).

## Ways to contribute

| I want to…                  | Do this                                                                                                                       |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| **Report a bug**            | Open a [Bug report](https://github.com/gkolan/recordHealthCheck/issues/new?template=bug_report.yml) issue                     |
| **Request a feature**       | Open a [Feature request](https://github.com/gkolan/recordHealthCheck/issues/new?template=feature_request.yml) issue           |
| **Ask a question**          | Start a [GitHub Discussion](https://github.com/gkolan/recordHealthCheck/discussions) (or open an issue if Discussions is off) |
| **Report a security issue** | **Do not** open a public issue: follow the [Security policy](SECURITY.md)                                                     |
| **Fix code or docs**        | Open a pull request (see below)                                                                                               |

## Reporting a bug: step by step

1. **Search first.** Check [existing issues](https://github.com/gkolan/recordHealthCheck/issues)
   so you do not file a duplicate.
2. Go to **Issues → New issue → Bug report**.
3. Fill in every field. The most useful reports include:
   - What you expected vs. what happened.
   - The **Check Set** and **Rule** Developer Names involved (not screenshots of labels only).
   - The object and a sketch of the field/query values that triggered it.
   - Whether **Debug Mode** was on, and the `[RHC]` summary from the browser console
     (see [Debug Mode guide](docs/guides/debug-mode.md)). **Redact record data and Org IDs.**
   - Org type (Production / Sandbox / Scratch) and API version.
4. Submit. A maintainer will triage and may ask for a minimal reproduction.

**Never paste** Salesforce access tokens, session IDs, full Org IDs, or real customer
record data into an issue.

## Opening a pull request: step by step

1. **Fork** the repo and **clone** your fork:
   ```bash
   git clone https://github.com/<your-username>/recordHealthCheck.git
   cd recordHealthCheck
   npm ci
   ```
2. **Create a focused branch** (one change per branch):
   ```bash
   git checkout -b fix/short-description
   ```
3. **Make your change.** Keep it small and include tests for every behavior change.
4. **Run the local gates** before you push (all must pass):
   ```bash
   npm run prettier:verify
   npm run lint
   npm test                    # 61 Jest tests
   npm run test:unit:coverage  # enforces LWC coverage thresholds
   ```
5. **Commit and push** to your fork:
   ```bash
   git commit -m "Fix: short description of the change"
   git push -u origin fix/short-description
   ```
6. **Open the PR** against `main`. The PR template will prompt you for a summary,
   testing notes, and a checklist. Link the issue it closes (e.g. `Closes #12`).
7. CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs prettier, lint,
   Jest with coverage, and XML validation on every PR. Keep it green.

A maintainer ([CODEOWNERS](CODEOWNERS) is auto-requested) will review. Address
feedback by pushing more commits to the same branch.

## Quality bar (what reviewers enforce)

- **Tests are required** for every behavior change: both a positive test and a
  misconfiguration/negative test where applicable.
- **Coverage thresholds** are enforced by `coverageThreshold` in
  [`jest.config.js`](jest.config.js): statements **85**, branches **75**,
  functions **90**, lines **85**. `npm run test:unit:coverage` exits non-zero if
  they are not met.
- **Apex changes** must also pass the project Apex test suite and a validation
  deployment (`sf project deploy validate`) with `RunLocalTests` in a clean
  scratch org.
- **Never weaken** CRUD/FLS enforcement, the 25-Rule run cap, the 5-way Apex
  concurrency cap, debug-detail authorization, or result normalization just to
  make a test pass.
- **New evaluator features** must update runtime validation, deploy-time
  validation, reason-code documentation, and both positive and misconfiguration
  tests. Do not add another parser or comparator copy: extend the shared modules.

See [`docs/reference/architecture-map.md`](docs/reference/architecture-map.md) to find where things live.

## Documentation changes

Docs must match the code at the same commit. Follow these authoring standards:

- **Active voice**: name the actor in instructions ("Assign the permission set" not "The permission set should be assigned").
- **No filler**: avoid _simply_, _just_, _easily_, _straightforward_, _it's worth noting_, _as mentioned above_ unless they carry technical meaning (for example "not just presence").
- **Code blocks**: introduce every block with a sentence ending in a colon; use fenced blocks with a language identifier (`bash`, `apex`, `sql`, `json`).
- **No em-dashes**: replace each em-dash by hand with a period, comma, or parentheses, never a blanket swap to a colon.

The design specification is canonical
in [`docs/reference/record-health-check-design-spec.md`](docs/reference/record-health-check-design-spec.md);
the per-topic files under [`docs/spec/`](docs/spec/index.md) are **generated** from it.
