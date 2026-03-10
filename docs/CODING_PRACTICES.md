# Coding Practices

This project uses practical, low-friction standards to keep the menu bar app reliable and easy to evolve.

## Core Engineering Principles

- Prefer small, focused functions over large multi-purpose blocks.
- Keep side effects localized (file IO, network, keychain, UI updates).
- Use explicit and descriptive variable names over abbreviations.
- Preserve behavior while refactoring; changes should be mechanical unless intentionally changing behavior.
- Add comments only where intent is not obvious from code structure.

## Swift Guidelines

- Follow Swift naming conventions (`camelCase` for variables/functions, `PascalCase` for types).
- Use value types (`struct`, `enum`) for deterministic business logic.
- Keep pure logic separate from app framework wiring where possible.
- Use early returns and guard statements to reduce nested control flow.
- Prefer explicit helper types (`UsageRateCalculator`, `UsageHistoryRecorder`) for grouped logic.

## Formatting and Linting

This repository standardizes indentation to **4 spaces**.

- `.editorconfig` defines:
    - `indent_style = space`
    - `indent_size = 4`
    - `tab_width = 4`
- `.swift-format` enforces Swift formatting with 4-space indentation.

Run locally:

```bash
./scripts/format.sh
./scripts/lint.sh
```

## Testing Standards

- Add unit tests for new pure logic and edge cases.
- Include regression tests when fixing bugs.
- Keep tests deterministic (fixed dates/timestamps, no random values without seeding).
- Run tests before and after major refactors:

```bash
swift test --parallel
```

## Refactoring Checklist

Before finalizing a refactor:

1. Verify behavior is unchanged for existing flows.
2. Run format + lint checks.
3. Run test suite.
4. Build the app (`./build.sh`) to confirm integration.
5. Commit in logical increments with conventional commit messages.
