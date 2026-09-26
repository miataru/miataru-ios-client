# Documentation Inventory and Cleanup

The [complete TSV inventory](DOCUMENTATION_INVENTORY.tsv) has one row per versioned or newly added document with path, purpose, status, authority, and required action. Regenerate with `miataru/scripts/documentation-inventory.py --write` and verify with `--check`. The inventory includes all 30 historical `.cursor/plans`, retained `.specstory` records, local package documentation, dependency licenses, dated audits, current project and topic documents, and historical design PDFs/OmniGraffle/RTF and web references. Vendored texts and examples are marked with a vendor authority and are updated only with their dependency.

`Current` means the document describes the development checkout and must be checked against source and Xcode settings. `P0 target` and `Later` are proposals. `historisch` is retained evidence, not a Current instruction. The app and widget share development metadata 3.5 build 2 in this checkout. Neither the source version nor an archived changelog entry proves the current App Store state.

## Review decisions

- The project overview, feature guide, development guide, root README, and App Store copy had stale 3.2-series headings. They now distinguish the 3.5 build 2 checkout from distribution status. The App Store copy is a draft; release-facing claims need validation during a requested release.
- The test catalog's 338-case figure was a June snapshot. The current test sources, synchronized targets, test plans, and `.xcresult` summary define active execution; the catalog now labels its detailed rows as a historical baseline. The gap matrix preserves dated decisions and records the new affected selector.
- The 30 Cursor plans are individually linked from the documentation map as historical proposals. Current behavior belongs to app code and living topic references. Existing `.specstory` records remain untouched, while active rules no longer request new records.
- SwiftProjectGraph and Codex Team configuration are repository process documents. Generated graph data and test artifacts remain ignored.

## Maintenance

Run the inventory check and active-link check with the `tooling` lane. Update the relevant living topic and the test catalog/gap matrix when behavior or tests change. Keep Current, P0 target, Later, and historical status explicit when a proposal spans implemented and future stages.
