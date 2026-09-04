# Stash for iOS

`Stash.xcodeproj` is generated (by [XcodeGen](https://github.com/yonaskolb/XcodeGen))
from `project.yml` and is gitignored — it is never committed and never
survives a `git pull`/branch switch as-is.

**Run `cd ios && xcodegen generate` after every pull** (and after any
`project.yml` edit) before opening/building in Xcode. Skipping this is the
#1 cause of "Cannot find 'StashType' in scope" (or any other in-repo type)
errors in Xcode: you're looking at a stale project referencing source files
that have since moved/renamed/been added, or a project generated against an
older `project.yml`.

Unit tests: `cd StashKit && swift test`. Release pipeline: see
`../docs/RELEASING.md`.
