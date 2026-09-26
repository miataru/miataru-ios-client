# SwiftProjectGraph

SwiftProjectGraph is a repository-local, deterministic code and documentation
index for Swift, SwiftUI, Xcode, and SwiftPM projects. It uses the SwiftSyntax
and SwiftParser libraries shipped with Xcode and stores its ignored per-project
cache in `graph/`; it does not use a model, network service, or shared database.
Its bootstrap wrapper relies only on macOS system tools and Xcode, so project
graph commands do not require a separate `rg` installation.

`project.json` is the versioned source of project-specific roots, documentation
status, subsystems, verification commands, and search vocabulary. Source code,
project files, and repository source-of-truth rules remain authoritative.

```bash
tools/SwiftProjectGraph/run.sh build --full
tools/SwiftProjectGraph/run.sh build
tools/SwiftProjectGraph/run.sh check
tools/SwiftProjectGraph/run.sh doctor
tools/SwiftProjectGraph/run.sh context 'location update outbox' --tokens 3000
tools/SwiftProjectGraph/run.sh api LocationManager.swift
tools/SwiftProjectGraph/run.sh trace LocationManager --direction incoming --depth 2
tools/SwiftProjectGraph/run.sh trace LocationManager --direction incoming --relations constructs
tools/SwiftProjectGraph/run.sh impact LocationManager
tools/SwiftProjectGraph/run.sh impact --git-diff
tools/SwiftProjectGraph/run.sh impact --format json --targets-json '["miataru/miataru/LocationManagers/LocationManager.swift"]'
tools/SwiftProjectGraph/run.sh find-all 'LocationManager\\s*\\(' --path miataru --status Current
tools/SwiftProjectGraph/run.sh mcp
tools/SwiftProjectGraph/run.sh benchmark-suite
```

The incremental build hashes file contents and replaces records only for added,
changed, or removed files. Generated SQLite, manifest, metrics, map, and binary
artifacts live below `graph/` and are intentionally not versioned.

The CLI also provides `query`, `find-all`, `repo-map`, `benchmark`,
`benchmark-suite`, and parser
fixture tests. Its STDIO MCP server exposes compact context, ranked code search,
file API, relationship trace, complete search, repository map, impact, and
freshness tools. CLI and MCP queries check fingerprints without mutating the
graph and fail closed when syntax inputs are stale. A lightweight post-patch
evaluator rebuilds immediately for code, project structure, graph
implementation, large, or broad patches; low-impact changes wait for selected
verification and the commit refresh. Parallel agent requests share one
repository lock and coalesce behind one builder for at most three serial
passes. The default broad/large thresholds are eight files or 400 changed
lines. Syntax and semantic-index freshness are reported separately. Syntax
edges carry `syntax` or
`inferred` confidence; `enrich` reads configured local Xcode IndexStores through
`libIndexStore` and adds USR/role-backed edges with `semantic` confidence. If no
compatible build index exists, semantic results remain explicitly unavailable.
For commit-oriented agent work, run `enrich` after the successful build/test
lane and before committing, then verify the resulting state with `doctor`.
When no configured IndexStore exists, `enrich` first runs
`build-index.sh`: a generic iOS build in `.build/swiftgraph-index` with
`COMPILER_INDEX_STORE_ENABLE=YES`. This dedicated DerivedData is used only by
SwiftProjectGraph and does not participate in app release or test artifacts.

Use the graph when ranking, signatures without bodies, document status,
semantic/multi-hop relationships, tests, architecture, or impact information
matters. For one known literal, exact symbol spelling, or a simple occurrence in
one file/root, targeted `rg` is faster and normally produces fewer tokens.
Context queries should name one primary entity or behavior; filter relationship
types, paths, and status before increasing limits or token budgets.

Root-level Markdown is indexed automatically, and `doctor` reports linked
documentation outside configured roots. Context groups results by subsystem and
caps repetition per file. Protocol requirements and matching implementations
are connected locally; a protocol-typed receiver can also yield an inferred
dynamic call when syntax alone is otherwise ambiguous. `impact` excludes
same-file implementation detail and groups external consumers, tests,
documents, and verification. Its JSON contract is intentionally stricter for
automation: only semantic external edges are emitted, while syntax/inferred
relationships remain navigation hints in the human-readable view. See [BENCHMARKS.md](BENCHMARKS.md) for Miataru measurements for the
versioned MCP-versus-shell measurements and known tradeoffs.

See [INSTALL.md](INSTALL.md) for copying the tool into another repository,
Codex setup, daily workflows, upgrades, uninstallation, and troubleshooting.
