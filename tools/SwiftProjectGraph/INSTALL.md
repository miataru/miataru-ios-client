# Install SwiftProjectGraph in another repository

SwiftProjectGraph is copied into each repository and indexes only that project.
Its parser, search, hooks, and MCP server run locally without an LLM or network
request. The versioned tool and configuration travel with the repository; the
generated graph does not.

## Copy and install

1. Copy `tools/SwiftProjectGraph/` from a repository with the desired tool
   version. Omit `graph/` and the source repository's `project.json`.
2. From the target Git root, preview installation:

   ```bash
   tools/SwiftProjectGraph/run.sh install \
     --project-root . --codex --agents AGENTS.md --dry-run
   ```

3. Install the repository-scoped Codex configuration and graph-first rule:

   ```bash
   tools/SwiftProjectGraph/run.sh install \
     --project-root . --codex --agents AGENTS.md
   ```

4. Review the generated `project.json`. Auto-discovery finds `.xcodeproj`
   metadata, `Package.swift`, common `Sources`, `Tests`, documentation, and
   script roots. Select explicit schemes, test plans/targets, documentation
   statuses, architecture flows, and IndexStore paths when a repository has
   several projects or packages.
5. Build and validate the first graph:

   ```bash
   tools/SwiftProjectGraph/run.sh build --full
   tools/SwiftProjectGraph/run.sh doctor
   tools/SwiftProjectGraph/run.sh test
   ```

6. Open the repository as trusted in Codex. Inspect and trust its hooks with
   `/hooks`, restart Codex, then verify `codex mcp list` and `/mcp`. A project
   configuration is intentionally not injected into an already running task.

The installer edits only marker-bounded TOML and AGENTS sections. It merges its
own two hook entries by command identity and is safe to run repeatedly. Paths
are validated against the Git root; MCP results never expose file content from
outside the configured repository.

## What the graph saves

| Tool | Use | Typical token saving |
| --- | --- | --- |
| `swift_graph_context` | Small task packet with signatures, docs, relations, tests | Replaces broad directory and file reads |
| `swift_graph_find_code` | Ranked symbol, behavior, path, heading, or concept search | Replaces repeated exploratory searches |
| `swift_graph_file_api` | All declarations without method bodies | Replaces full-file API inspection |
| `swift_graph_trace` | Bounded callers, callees, extensions, references | Replaces manual dependency chasing |
| `swift_graph_find_all` | Complete regex matches with path/line grouping | Replaces large raw search output |
| `swift_graph_repo_map` | Subsystems, hubs, targets, configured flows | Replaces repeated architecture orientation |
| `swift_graph_impact` | Blast radius for symbol, file, or `git-diff`, plus tests/docs/verification | Reduces missed consumers and follow-up turns |
| `swift_graph_freshness` | Read-only syntax/semantic state | Prevents analysis of stale generated data |

The graph is intentionally not the default for every lookup. Prefer targeted
`rg` for one exact literal, a known symbol spelling, or a simple occurrence in a
known file/root. Prefer MCP for ambiguous behavior, signature-only APIs,
document-status-aware ranking, semantic or multi-hop traversal, test discovery,
architecture orientation, and impact analysis. Keep each context query centered
on one entity or behavior and use `relationship_types`, `path`, and `status`
filters before expanding limits.

Results default to compact signatures and one-line relationships. They include
path, line, document status, confidence, freshness, estimated tokens, and
omission counts where applicable. Ask for source excerpts only after the graph
has narrowed the relevant locations (`context --source` or MCP
`include_source: true`). Never paste `index.sqlite3` or a large
graph export into model context.

## Daily use and refresh timing

- Startup does not rebuild the graph.
- A lightweight `PostToolUse` evaluator classifies Codex `apply_patch`, `Edit`,
  and `Write` changes. Code, project structure, graph implementation, large, or
  broad patches request an immediate refresh; low-impact edits wait for
  verification and the commit workflow.
- Evaluator requests are pooled under one repository lock. One process owns the
  graph writer while concurrent agents attach their generations; the owner
  absorbs at most three serial passes and leaves later work for verification.
- Every CLI and MCP query checks fingerprints without changing the database and
  fails closed when syntax inputs are stale. Run an explicit `build` only when
  an out-of-band query is needed before verification.
- `scripts/verify.sh` or the repository's equivalent should call `build` and
  `test` so CI/local verification also checks the tool.
- Agent workflows that commit completed work should run `enrich` after their
  successful build/test lane and immediately before the planned commit, then
  use `doctor` to confirm the resulting syntax and semantic state. In team mode,
  Root owns this final refresh rather than allowing parallel builders. Running
  `enrich` before that build would only import the previous compiler index.
- Use `build --full` after changing parser/schema versions or when diagnosing a
  cache problem. Normal work should use incremental `build`.

Syntax indexing is always available with Xcode's bundled SwiftSyntax and
SwiftParser. It provides declarations, containment, imports, construction,
calls, references, inheritance/conformance candidates, tests, docs, and source
ranges. Semantic IndexStore enrichment requires a compatible completed Xcode or
SwiftPM build. Until enrichment is available, results explicitly report
`semantic=unavailable`; they do not present heuristic resolution as compiler
truth.

## Update, uninstall, and troubleshoot

To update, preserve the destination `project.json` and ignored `graph/`, replace
the other files with a newer copy, run `install` again, then `build --full` and
`doctor`. Configuration schema incompatibility fails with a short diagnostic
instead of replacing the cache or printing a Swift stack trace.

Projects can keep versioned cases below `Benchmarks/` and run
`run.sh benchmark-suite --config <file>`. The runner compares a warm persistent
MCP with explicit shell baselines and records latency, characters, estimated
tokens, precision@5, recall, and every missing expectation. Raw JSON is written
to ignored `graph/`; accepted measurements belong in a versioned report.

Remove Codex integration while keeping the tool and project configuration:

```bash
tools/SwiftProjectGraph/run.sh uninstall \
  --project-root . --agents AGENTS.md --dry-run
tools/SwiftProjectGraph/run.sh uninstall \
  --project-root . --agents AGENTS.md
```

Then remove `tools/SwiftProjectGraph/` manually only if the repository should no
longer carry the tool. The ignored `graph/` is disposable and can always be
rebuilt. `doctor` reports missing configuration, path violations, database
health, syntax freshness, semantic availability, and indexed counts. Exit code
3 means stale inputs, 64 means invalid CLI use, 78 means invalid configuration,
and 1 means an operational/database failure.
