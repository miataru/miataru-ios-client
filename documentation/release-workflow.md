# Miataru Release Workflow

This page describes the evidence required for a requested distribution. Source
metadata in the checkout is a development state; it does not prove an archive,
upload, Apple processing, or App Review outcome.

## Before distribution

1. Record the exact commit and confirm a clean, reviewed scope. App and widget
   must resolve to the same `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`
   in Debug and Release: `miataru/scripts/verify-metadata.py`.
2. Run `cd miataru && ./scripts/verify.sh release` against that commit. Preserve
   both retained Unit/UI `.xcresult` bundles, executed counts, failures/skips,
   and the aggregate release status. The two Xcode invocations run in sequence.
   Run affected screenshot scenarios and all affected shipped locales on the
   dedicated screenshot devices. A zero-test, hung, partial, or failing lane
   is not release evidence.
3. For changes to location sharing, background behavior, permissions, or Live
   Activities, document a physical iPhone check before upload. Include device,
   iOS version, tested permission/background states, observed delivery and
   recovery behavior, and result. Simulator results do not substitute for it.

## Archive and handoff

Archive the tested commit with the `miataru` scheme in Release configuration
and an explicit `.xcarchive` path. Keep the archive and export log. Inspect the
archive's app and widget `Info.plist` values, signing identities and
entitlements, supported architectures, and app/extension dSYMs. Compare all
metadata with the tested commit and changelog. A successful archive is only
an archive result.

Export and upload only when requested. Keep the export options used for the
actual destination, the exported IPA, uploader output, and App Store Connect
acceptance response. Check Apple processing separately later; an uploader
success does not prove processing, App Review, or availability. Record each
state with its timestamp and evidence path. Do not change the tested commit
between gate, archive, and upload without rerunning affected checks.

For ordinary completed app changes, commit the selected scope after its gate;
do not archive or upload. Push is also separate and requires a request.
