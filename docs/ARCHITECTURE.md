# Architecture Guide

This document explains project layout, where new files should live, and how to update `build.sh` when adding features.

## High-Level Architecture

The app is a native macOS menu bar application with:

- UI/event orchestration in app delegate files
- usage data acquisition through API modules
- shared domain logic in a testable core module
- optional persistence/history utilities

## Directory Layout

### Application Source

- `src/` is the root for app Swift files.
- Core/entry files stay at `src` root:
  - `main.swift`
  - `ClaudeUsage.swift`
  - `AppDelegate+...` extension files
  - shared constants/time/sound/core files

### Feature Grouping in `src`

Use subfolders for shared functionality:

- `src/api/`
  - network/API models, request logic, auth/token access
- `src/graph/`
  - usage graph/heatmap generation and related rendering logic
- `src/history/`
  - history persistence, migration, and sample/rate storage helpers

### Tests

- `tests/` contains test targets and test files.
- Keep test directory names lowercase.

### Legacy/Other

- `docs/` contains process and architecture documentation.

## File Placement Rules

When adding a new file, place it by responsibility:

1. **App startup / global wiring**
   - `src/` root
2. **API contracts/fetchers**
   - `src/api/`
3. **Graph/visual data generation**
   - `src/graph/`
4. **History/storage/migration**
   - `src/history/`
5. **Cross-cutting pure domain logic**
   - `src/` root (or `src/core` if a future split is introduced)
6. **Unit tests**
   - `tests/<TargetName>/`

## How to Update `build.sh` for New Features

`build.sh` uses a direct `swiftc` command with an explicit list of files.
When you add new Swift files that are needed at runtime, update this list.

### Steps

1. Add your new file to the `swiftc` source list in `build.sh`.
2. Keep order logical (root/core first, feature modules after).
3. Rebuild with:
   - `./build.sh`
4. Run tests:
   - `swift test --parallel`
5. Run lint:
   - `./scripts/lint.sh`

### Example

If you add `src/api/BillingAPI.swift`, include it in `build.sh` near other API files:

```bash
src/api/UsageAPIModels.swift \
src/api/ClaudeDesktopUsageAPI.swift \
src/api/OAuthUsageAPI.swift \
src/api/BillingAPI.swift \
```

## How to Update Package/Test Paths

If test/core files move, update:

- `Package.swift`:
  - target `path`
  - `sources`
  - `exclude`
  - test target `path`

Then run `swift test --parallel` to validate.

## CI and Formatting Expectations

Before merging:

1. `swift test --parallel` passes
2. `./scripts/lint.sh` passes (formatting/lint rules)
3. `./build.sh` succeeds

Formatting uses 4-space indentation (`.swift-format` + `.editorconfig`).
