# Contributing

Thanks for your interest in `mcp`. Contributions — bug reports, fixes, docs, and
features that fit the [project scope](README.md#scope--roadmap) — are welcome.

## Ground rules

- **Zero runtime dependencies.** The library uses the Crystal standard library
  only (`json`, `log`, `http`, `socket`). A change that pulls in a runtime shard
  will not be merged — this constraint is what lets consumers vendor a tiny,
  audit-friendly dependency.
- **Stay protocol-faithful.** Field names and shapes follow MCP revision
  `2025-06-18`. Cite the spec for protocol changes rather than inferring.
- **Keep the API additive.** This is a published `1.x`: new capabilities should
  appear through the existing seams (derived capabilities, the handler's method
  router, shared `MCP::Content` blocks, `MCP::Session`) without breaking the
  `1.0` surface. Breaking changes wait for `2.0`.

## Development setup

The toolchain is managed with [mise](https://mise.jdx.dev):

```sh
mise install      # install the pinned Crystal
mise dev:deps     # shards install
```

Common tasks:

```sh
mise dev:spec     # run the spec suite (Spectator)
mise dev:ameba    # static analysis
mise dev:format   # format src/, spec/ and examples/
mise dev:check    # build-check + ameba + spec  (run this before every commit)
```

## Workflow

1. Open an issue first for anything non-trivial, so the design can be agreed
   before code.
2. Work on a branch; keep commits focused.
3. **Test-drive it.** New behaviour comes with a spec; a bug fix comes with a
   failing test first. The suite must stay green.
4. Run `mise dev:check` and make sure it passes (build, ameba, specs).
5. Update `CHANGELOG.md` (the `Unreleased` section) and any relevant docs.
6. Open a pull request describing the change and the reasoning.

## Style

- Comments go **above** the code they describe, never inline.
- Code, comments, and test descriptions are in **English**.
- Use named arguments on non-trivial calls.
- Let `mise dev:format` settle formatting; let `ameba` settle lints.

## Reporting bugs

Include the Crystal version, the `mcp` version, a minimal reproduction (ideally a
small server like those in [`examples/`](examples/)), and the JSON-RPC exchange
you observed versus expected.
