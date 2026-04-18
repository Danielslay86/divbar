# Contributing

Fork, branch, make sure all tests pass, open a PR.

```bash
bash test_suite.sh
```

## Setup

Clone and run the suite. You don't need a desktop environment installed — tests run in a `/tmp` sandbox with mock dialog binaries.

```bash
git clone https://github.com/danielslay86/divbar.git
cd divbar
bash test_suite.sh -v
```

## Code style

Function and local variable names are `lowercase_with_underscores`. Constants and exported variables are `UPPERCASE`. Always quote variable expansions (`"$var"`, not `$var`). Use POSIX `=` for string comparison, not `==`. Error messages go to stderr (`echo "Error: ..." >&2`). Don't use `eval` anywhere.

## Tests

Tests live in `test_suite.sh`. The framework gives you:

| Helper | What it does |
|---|---|
| `assert "desc" "condition"` | Eval condition, pass/fail |
| `assert_file_exists "desc" "path"` | File must exist |
| `assert_file_missing "desc" "path"` | File must not exist |
| `assert_file_contains "desc" "path" "pattern"` | Grep match |
| `assert_equals "desc" "expected" "actual"` | String equality |
| `assert_executable "desc" "path"` | Has exec bit |

New features need tests. New desktop environments need detection tests in section 4 (backend matrix) and integration tests in section 10b (multi-DE add).

## Adding div assets

Drop images in `assets/vertical/` (for top/bottom taskbars) or `assets/horizontal/` (for left/right taskbars). Filenames should be lowercase and hyphenated (`dark-gray.png`, `neon-blue.svg`). Vertical divs work best at 4-8px wide, horizontal at 4-8px tall. Transparent backgrounds. PNG or SVG.

## PR checklist

- [ ] `bash test_suite.sh` passes with zero failures
- [ ] New features have tests
- [ ] No `eval` anywhere
- [ ] All variable expansions quoted

## License

Contributions are licensed MIT.
