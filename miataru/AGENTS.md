# Agent Rules

## Commit Workflow

- Before every commit that includes code or project changes, create a `.specstory` history entry for the current chat in `.specstory/history/` using the existing timestamped filename and markdown format.
- Stage and include that `.specstory` file in the same commit.
- Update `CHANGELOG.md` in the same commit following the main app `MARKETING_VERSION` (`miataru.xcodeproj/project.pbxproj`, miataru target).
- Write commit messages in English.
