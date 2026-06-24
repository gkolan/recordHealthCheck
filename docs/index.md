---
title: Home
---

Record Health Check is a metadata-driven framework for running data-quality checks against a Salesforce record, right on its **record page**. It is **advisory** and read-only, so it never blocks a save and never writes a field. You define **Check Sets** and **Rules** in Custom Metadata; an Apex engine evaluates the open record, and the component shows each result as **pass**, **fail**, **skipped**, or **error**.

This site is the full documentation. The source lives at [github.com/gkolan/recordHealthCheck](https://github.com/gkolan/recordHealthCheck).

## Get started

- [Getting Started](installation/getting-started.md) — deploy the package and run your first check
- [Sandbox setup](installation/sandbox.md) — try it in a sandbox or scratch org

## Guides

- [CLI commands](guides/cli-commands.md)
- [Configuration guide](guides/configuration-guide.md)
- [Debug mode](guides/debug-mode.md)
- [LLM configuration](guides/llm-configuration.md)

## Metadata reference

- [Custom Metadata Types and Fields](metadata/index.md)
- [Check Set fields](metadata/check-set.md)
- [Rule fields](metadata/rule-fields.md)

## Examples

- [Examples index](examples/index.md) — copy-paste patterns for every check type

## Apex and extensibility

- [Plugin contract](apex/plugin-contract.md)
- [Plugin reference](apex/plugin-reference.md)

## Reference

- [Architecture map](reference/architecture-map.md)
- [Design specification](reference/record-health-check-design-spec.md)
- [Design spec (modular)](spec/index.md) — the formal contract, split by topic

---

Maintained by [Gautam Kolan](https://github.com/gkolan). Licensed under the [Apache License, Version 2.0](https://github.com/gkolan/recordHealthCheck/blob/main/LICENSE).
