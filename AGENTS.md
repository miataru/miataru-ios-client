# Miataru Repository Rules

These rules apply to the repository. `miataru/AGENTS.md` adds app-specific test,
simulator, and localization details.

## Source of truth and documentation

- Verify Current behavior against source, target settings, and active test plans.
  Distinguish Current, P0 target, Later, and historical records. Distinguish a
  development build from an App Store release or an accepted upload.
- Keep the living project and topic documentation aligned with completed changes.
  `documentation/README.md` owns the map; the documentation inventory records
  every tracked document and its authority. Historical plans are evidence, not
  instructions to implement or claims of Current behavior.
- Update the test catalog and gap matrix together when tests change. Update the
  App Store description only for verified release-facing behavior.

## Work and commit boundary

- Start with `git status --short`, scoped searches, and a scoped diff. Preserve
  unrelated changes. Review the final diff and `git diff --check` before tests;
  review staged paths and the staged diff before committing.
- Add a focused deterministic regression for a bug when feasible. For persisted
  data or settings changes, verify compatibility with the previous released
  representation and preserve valid user state on read/recovery failures.
- Use `cd miataru && ./scripts/verify.sh affected --dry-run --explain` to inspect
  selection and `./scripts/verify.sh affected` for ordinary work. Use the full
  `release` lane for project, test-plan, or verification-infrastructure changes
  and before a requested distribution. A focused zero-test, hung, or partial
  run is not green. Report exact lane, test count, result, and artifact path.
- Before each Xcode test lane, run the project metadata preflight. Give Xcode
  commands one owner and retain their session and result. Do not start an
  overlapping simulator run or restart a quiet/lost run without checking its
  retained status. Use only dedicated Miataru simulators.
- For each completed app-code, project-setting, or distributable-asset commit,
  increment the main app `CURRENT_PROJECT_VERSION` exactly once in both
  configurations. Keep the WidgetKit extension's resolved version/build equal.
  Change `MARKETING_VERSION` only for a deliberate version decision. Update
  `miataru/CHANGELOG.md` under that marketing version before the commit.
- After the selected gate passes, commit only the reviewed scope with an English
  message unless the user says not to. Push only on request. Archive and upload
  only on a release request; a normal app commit does not trigger distribution.

## Privacy and release evidence

- Keep DeviceKey storage and widget behavior compatible with the current app.
  Do not add secret-bearing log, diagnostic, document, or test-artifact copies.
- For a release, test the committed input with full Unit and serial functional
  UI coverage plus affected localization/screenshot checks. Changes to location
  sharing, background behavior, permissions, or Live Activities require a
  documented physical iPhone check before upload.
- Verify archive app/widget metadata, signing, architecture, and dSYMs. Report
  archive, App Store Connect upload acceptance, Apple processing, App Review,
  and physical-device acceptance as separate states. Never infer a later state
  from an earlier success.

# BEGIN SwiftProjectGraph
## Local project graph

- Before broad source inspection, use `swift_graph_context` with a focused task query.
- Use the graph for ambiguous behavior, signature-only APIs, semantic or multi-hop dependencies, architecture orientation, tests, and blast-radius analysis.
- Use `swift_graph_file_api` for APIs, filtered `swift_graph_trace` for dependencies, and `swift_graph_impact` for blast radius.
- Do not use `swift_graph_context` or `swift_graph_find_all` for one known literal, exact symbol spelling, or simple single-file occurrence search; targeted `rg` is faster and usually smaller. Use graph search when ranking, document status, grouping, or cross-file relationships add value.
- Treat syntax-only, inferred, and stale-semantic edges as navigation hints: overloads, dynamic dispatch, reflection, generated code, and common short names can remain ambiguous. Prefer `semantic` confidence after a compatible build and confirm behavior in source before editing.
- Prefer symbol targets over whole-file targets for `swift_graph_impact`; file impact is intentionally broader.
- Keep context queries centered on one primary entity or behavior. Apply relationship, path, and status filters before increasing result limits or token budgets.
- If MCP is unavailable, call the matching command through `tools/SwiftProjectGraph/run.sh`.
- Graph data is a navigation and analysis aid; source code, project files, and repository source-of-truth rules remain authoritative.
- Never load the complete graph database or large JSON dumps into model context. Queries fail closed when fingerprints are stale; refresh through the post-patch evaluator, selected verification, or the commit process before Current-behavior claims.
- Update `tools/SwiftProjectGraph/project.json` when targets, architecture paths, document status, or verification commands change.
- After a successful build/test verification and before a planned commit, run `tools/SwiftProjectGraph/run.sh enrich`, then confirm the resulting syntax/semantic state with `tools/SwiftProjectGraph/run.sh doctor`. Enrich only after the build that is meant to validate the change.
- When versioned benchmark cases exist, run `tools/SwiftProjectGraph/run.sh benchmark-suite` after changing graph ranking, compression, relationships, refresh behavior, or output contracts.
# END SwiftProjectGraph

## Opt-in Codex team and command ownership

- At planning, ask whether this chat uses Team or no Team when the choice is
  open. Team is active only after the user says “mit Team” or “Team aktivieren”;
  “ohne Team” or “Team deaktivieren” returns to solo work. Without Team, do not
  delegate. A request to document these rules does not activate Team.
- Team work uses at most two subagents and exactly one writer. Every delegation
  sets an explicit model, reasoning effort, and `fork_turns="none"`; the task
  name ends in `_luna` or `_sol`. No nested spawning. Give an agent one coherent
  slice with owned files and its focused verification; reuse that agent for
  follow-up within the slice.
- Prefer Luna 6 for bounded implementation, inventory, review, localization,
  and simulator diagnostics. Use higher Luna effort for difficult Swift,
  concurrency, persistence, migration, or debugging. Sol is a Root-only choice
  unless the user grants the exact one-time task with
  `Sol-Subagent einmalig freigeben: <task_name>`. The hook is a second check;
  the user's choice and Root policy are authoritative.
- Subagents do not commit, push, archive, or upload. A simulator diagnostician
  writes evidence only under `miataru/artifacts/`. Root owns final integration,
  metadata, graph enrichment, diff review, verification, and commit.
- Name one owner for every Xcode, graph, archive, or upload invocation. Retain
  its session, artifact directory, and status record. Handoff transfers
  observation of that invocation; it never starts a replacement. If a session
  is lost, inspect the original process and `verify.sh status --lane <lane>`
  before Root decides whether a replacement is needed. Never overlap simulator
  lanes or graph database writers.
