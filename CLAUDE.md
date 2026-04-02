# CLAUDE.md — Project Guidelines

Guidelines for working on this project with Claude Code.

## Core principles

**Safe by default**
- The script never modifies system files or paths outside of package manager conventions.
- `--casks` is opt-in because Homebrew cask upgrades can replace running GUI applications.
- `--skip-major` is opt-in because it requires per-package processing; the default (upgrade all) is still safe and intentional.
- The script runs with `set -euo pipefail`. Do not suppress errors silently unless you also handle the failure case visibly.

**Graceful error handling**
- Use `warn()` for recoverable issues; never silently swallow errors.
- Use `skipped()` when a tool is not installed — absence is not an error.
- All upgrade commands should have a `|| true` fallback so a single failed package does not abort the entire run.

**Security audit is mandatory, not optional**
- The audit section always runs after updates. It must never be removed or made opt-out.
- The script exits with code 1 if any audit tool reports vulnerabilities. This is intentional — the caller must be aware of issues.
- If `npm audit` or `pip-audit` produce findings, the user must act before considering the update complete.
- If adding a new package manager section, add a corresponding audit step.

**Dry-run is a strict no-op**
- `--dry-run` must print what would run but never invoke any update or audit command that mutates state.
- Every destructive or network action must be guarded by `if $DRY_RUN`.
- Audit commands in dry-run mode should print `[dry-run] <command>` only.

**Generic and portable**
- No hardcoded usernames, absolute paths specific to one machine, internal hostnames, or any personally identifiable information in the script, README, comments, or commit messages.
- All tool paths must be derived from `command -v` or `$HOME`.
- Requires only bash 3.2+ and standard macOS built-in tools. New binary dependencies require a detection + skip path.

**Consistency with existing patterns**
- New package manager sections follow the established structure: `log()` to announce, run update, `ok()` or `skipped()`.
- Detection variables use the `HAS_*` naming convention.
- Dry-run output uses the `[dry-run] <command>` format with 6-space indent.
- Each new tool needs a corresponding audit step in the Security Audit section.

## What this script intentionally does NOT do

- Modify or install packages in project-local `node_modules`, `venv`, or similar directories.
- Uninstall packages or remove old versions (other than what brew/rustup do natively).
- Run with elevated privileges (`sudo`) — package managers handle their own privilege escalation.
- Operate outside of macOS (Darwin).
- Suppress or skip the security audit.
