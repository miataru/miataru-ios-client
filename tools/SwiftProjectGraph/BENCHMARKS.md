# Miataru SwiftProjectGraph Benchmark

The versioned [cases](Benchmarks/miataru.json) compare one warm local MCP process with targeted `rg`/`sed` shell commands. Run `tools/SwiftProjectGraph/run.sh benchmark-suite` from the repository root; raw results go to ignored `graph/benchmark-latest.json`.

Accepted local run: 2026-09-25T19:30:53Z; MCP startup 49.26 ms. Both routes found all configured expected terms in these three cases. A known literal remains faster to inspect with `rg`; the graph supplies ranked relationships and compact APIs for ambiguous questions.

| Case | MCP ms | Shell ms | MCP recall | Shell recall |
|---|---:|---:|---:|---:|
| `location-policy-api` | 100.39 | 32.56 | 1.00 | 1.00 |
| `location-delivery-context` | 276.80 | 36.81 | 1.00 | 1.00 |
| `exact-setting-control` | 362.18 | 35.97 | 1.00 | 1.00 |

These are navigation microbenchmarks on the current checkout, not app runtime measurements or guarantees for later hardware. The shell baselines have handpicked search terms and favor a developer who already knows where to look.
