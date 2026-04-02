# mac-package-updater

A single script to update all package managers and global packages on macOS, with a mandatory security audit after every run.

## What it updates

| Tool | What runs |
|------|-----------|
| Homebrew formulae | `brew update && brew upgrade` |
| Homebrew casks | `brew upgrade --cask` *(requires `--casks`)* |
| npm global packages | `npm update -g` |
| pip3 packages | `pip3 install --upgrade <outdated>` |
| Ruby gems | `gem update` |
| Rust toolchains | `rustup update` |
| Mac App Store apps | `mas upgrade` *(requires [`mas`](https://github.com/mas-cli/mas))* |

Any tool that is not installed is skipped automatically — no errors, no configuration needed.

## Security audit

After every update run, the script scans for known vulnerabilities:

- `npm audit` — checks global npm packages against the npm advisory database
- `pip-audit` — checks Python packages against OSV/PyPI advisories *(if installed)*
- `brew audit --strict` — checks Homebrew formula integrity

**If any audit tool finds issues, the script exits with a non-zero code.** The update is not considered complete until the audit is clean.

## Usage

```bash
# Make executable (once)
chmod +x update-packages.sh

# Preview what would run — nothing is changed
./update-packages.sh --dry-run

# Update everything (formulae only, no casks)
./update-packages.sh

# Also upgrade Homebrew casks (GUI apps)
./update-packages.sh --casks

# Skip major version bumps — print them for manual review instead
./update-packages.sh --skip-major

# Combine flags
./update-packages.sh --casks --skip-major --dry-run
```

## Flags

| Flag | Description |
|------|-------------|
| `--dry-run` | Print what would run; touch nothing |
| `--casks` | Also upgrade Homebrew casks |
| `--skip-major` | Skip packages with a major version bump; list them for manual review |

## Why `--skip-major`?

Major version bumps carry the highest supply-chain risk — they are more likely to introduce breaking changes or, in rare cases, malicious code (see: xz-utils, event-stream). This flag lets you keep everything else current while manually reviewing and testing major upgrades on your own schedule.

## Optional: install `pip-audit`

`pip-audit` is not installed by default on macOS. To enable Python vulnerability scanning:

```bash
pip3 install pip-audit
```

## Optional: install `mas`

`mas` enables App Store app updates from the terminal:

```bash
brew install mas
```

## Requirements

- macOS (Darwin)
- bash 3.2+ (ships with macOS)
- At least one of the supported package managers installed

## License

MIT — see [LICENSE](LICENSE).
