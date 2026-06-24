<!--
Thanks for contributing! Keep changes focused: one logical change per PR.
See CONTRIBUTING.md for the full workflow.
-->

## Summary

<!-- What does this change and why? Link the issue it closes, e.g. "Closes #12". -->

## Type of change

- [ ] Bug fix
- [ ] New feature / evaluator
- [ ] Documentation
- [ ] Build / tooling

## Testing

<!-- How did you verify this? Paste the relevant command output. -->

- [ ] `npm run prettier:verify`
- [ ] `npm run lint`
- [ ] `npm test` (61 Jest tests)
- [ ] `npm run test:unit:coverage` (coverage thresholds enforced)
- [ ] Apex: `sf project deploy validate` with `RunLocalTests` in a clean scratch org (if Apex changed)

## Checklist

- [ ] Tests added/updated for every behavior change (positive **and** misconfiguration where applicable).
- [ ] Did **not** weaken CRUD/FLS, the 25-Rule run cap, the 5-way Apex concurrency cap, debug-detail authorization, or result normalization.
- [ ] Docs updated in the same change set; design-spec changes edit the canonical monolith and the generated `docs/spec/` files together.
- [ ] `CHANGELOG.md` updated under **Unreleased**.
