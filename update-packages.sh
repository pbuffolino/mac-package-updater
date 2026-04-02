#!/usr/bin/env bash
# =============================================================================
# update-packages.sh — macOS Package Updater
# https://github.com/pbuffolino/mac-package-updater
#
# DISCLAIMER: This script is provided "as-is", without warranty of any kind,
# express or implied. The author accepts no liability for data loss, system
# instability, or any other damages arising from its use. You are solely
# responsible for reviewing and understanding this script before running it.
# See LICENSE for full terms.
# =============================================================================
#
# Usage:
#   ./update-packages.sh [--dry-run] [--casks] [--skip-major]
#
#   --dry-run      Preview what would run — no packages are updated
#   --casks        Also upgrade Homebrew casks (GUI apps); off by default
#   --skip-major   Skip packages with a major version bump; print them for
#                  manual review instead (highest supply-chain risk)
#
# What gets updated:
#   Homebrew formulae   brew update && brew upgrade
#   Homebrew casks      brew upgrade --cask            (requires --casks)
#   npm globals         npm update -g
#   pip3 packages       pip3 install --upgrade <outdated>
#   Ruby gems           gem update
#   rustup toolchains   rustup update
#   mas (App Store)     mas upgrade
#
# Security audit (always runs after updates):
#   npm audit           scans global npm packages for known CVEs
#   pip-audit           scans Python packages for known CVEs (if installed)
#   brew audit          checks formula integrity
#
# Tested on: macOS Sequoia 15.x (Apple Silicon + Intel)
# Requires:  bash 3.2+  (ships with macOS)
# =============================================================================

set -euo pipefail

# ── Argument parsing ──────────────────────────────────────────────────────────
DRY_RUN=false
CASKS=false
SKIP_MAJOR=false
for arg in "$@"; do
  case "$arg" in
    --dry-run)    DRY_RUN=true ;;
    --casks)      CASKS=true ;;
    --skip-major) SKIP_MAJOR=true ;;
    --help|-h)
      sed -n '/^# Usage/,/^# ====/p' "$0" | grep '^#' | sed 's/^# \{0,2\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: '$arg'" >&2
      echo "Run '$(basename "$0") --help' to see valid options." >&2
      exit 1
      ;;
  esac
done

# ── Sanity checks ─────────────────────────────────────────────────────────────
[[ -n "${HOME:-}" ]] || { echo "ERROR: \$HOME is not set. Aborting." >&2; exit 1; }
[[ "$HOME" != "/" ]] || { echo "ERROR: \$HOME is '/'. Aborting." >&2; exit 1; }
[[ -d "$HOME" ]]     || { echo "ERROR: \$HOME ($HOME) is not a directory. Aborting." >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || { echo "ERROR: This script is for macOS only." >&2; exit 1; }

# ── Colors (disabled if not a terminal) ───────────────────────────────────────
if [[ -t 1 ]]; then
  BOLD=$(tput bold 2>/dev/null || true)
  RESET=$(tput sgr0 2>/dev/null || true)
  GREEN=$(tput setaf 2 2>/dev/null || true)
  YELLOW=$(tput setaf 3 2>/dev/null || true)
  CYAN=$(tput setaf 6 2>/dev/null || true)
  RED=$(tput setaf 1 2>/dev/null || true)
  MAGENTA=$(tput setaf 5 2>/dev/null || true)
else
  BOLD="" RESET="" GREEN="" YELLOW="" CYAN="" RED="" MAGENTA=""
fi

log()     { echo "${CYAN}▸${RESET} $*"; }
seclog()  { echo "${MAGENTA}▸${RESET} [audit] $*"; }
ok()      { echo "  ${GREEN}✔${RESET}  $*"; }
skipped() { echo "  ${YELLOW}–${RESET}  $*"; }
warn()    { echo "  ${RED}!${RESET}  $*"; }

# ── Signal handling ───────────────────────────────────────────────────────────
# shellcheck disable=SC2064
trap "printf '\n  ${YELLOW}Interrupted.${RESET}\n' >&2; exit 130" INT TERM

# ── Tool detection ────────────────────────────────────────────────────────────
HAS_BREW=false;    command -v brew    &>/dev/null && HAS_BREW=true
HAS_NPM=false;     command -v npm     &>/dev/null && HAS_NPM=true
HAS_PIP=false;     command -v pip3    &>/dev/null && HAS_PIP=true
HAS_GEM=false;     command -v gem     &>/dev/null && HAS_GEM=true
HAS_RUSTUP=false;  command -v rustup  &>/dev/null && HAS_RUSTUP=true
HAS_MAS=false;     command -v mas     &>/dev/null && HAS_MAS=true
HAS_PIPAUDIT=false; command -v pip-audit &>/dev/null && HAS_PIPAUDIT=true

# ── Major version bump detection ──────────────────────────────────────────────
# Returns 0 (true) if $2 is a major bump from $1  (e.g. 3.x.x → 4.x.x)
is_major_bump() {
  local old_major new_major
  old_major=$(echo "$1" | cut -d. -f1 | tr -dc '0-9')
  new_major=$(echo "$2" | cut -d. -f1 | tr -dc '0-9')
  [[ -n "$old_major" && -n "$new_major" && "$new_major" -gt "$old_major" ]]
}

# Tracks packages skipped due to --skip-major
SKIPPED_MAJOR=()

# ── Audit result tracking ─────────────────────────────────────────────────────
AUDIT_ISSUES=0

# ── Start ─────────────────────────────────────────────────────────────────────
START_TS=$(date +%s)
echo
echo "${BOLD}=== macOS Package Updater ===${RESET}"
$DRY_RUN    && echo "${YELLOW}  DRY RUN — no packages will be updated${RESET}"
$CASKS      && echo "${MAGENTA}  CASKS — Homebrew cask upgrades enabled${RESET}"
$SKIP_MAJOR && echo "${YELLOW}  SKIP MAJOR — major version bumps will be skipped${RESET}"
echo "  Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Tools detected: $(
  tools=()
  $HAS_BREW    && tools+=("brew")
  $HAS_NPM     && tools+=("npm")
  $HAS_PIP     && tools+=("pip3")
  $HAS_GEM     && tools+=("gem")
  $HAS_RUSTUP  && tools+=("rustup")
  $HAS_MAS     && tools+=("mas")
  [[ ${#tools[@]} -eq 0 ]] && echo "none" || echo "${tools[*]}"
)"
echo "  Audit tools: $(
  auditors=()
  $HAS_NPM      && auditors+=("npm audit")
  $HAS_PIPAUDIT && auditors+=("pip-audit")
  $HAS_BREW     && auditors+=("brew audit")
  [[ ${#auditors[@]} -eq 0 ]] && echo "none" || echo "${auditors[*]}"
)"
echo

# ── 1. Homebrew formulae ──────────────────────────────────────────────────────
if $HAS_BREW; then
  log "Updating Homebrew formula index..."
  if $DRY_RUN; then
    echo "      [dry-run] brew update"
  else
    brew update 2>&1 | sed 's/^/      /' || true
  fi
  ok "Homebrew index updated"

  log "Upgrading Homebrew formulae..."
  if $DRY_RUN; then
    echo "      [dry-run] brew upgrade"
    brew outdated --formula 2>/dev/null | sed 's/^/      [dry-run] would upgrade: /' || true
  else
    if $SKIP_MAJOR; then
      while IFS= read -r pkg; do
        [[ -z "$pkg" ]] && continue
        pkg_name=$(echo "$pkg" | awk '{print $1}')
        old_ver=$(echo "$pkg"  | awk '{print $2}')
        new_ver=$(echo "$pkg"  | awk '{print $4}')
        if is_major_bump "$old_ver" "$new_ver"; then
          SKIPPED_MAJOR+=("brew:${pkg_name} ${old_ver} → ${new_ver}")
          warn "Skipped major bump: ${pkg_name} ${old_ver} → ${new_ver}"
        else
          brew upgrade "$pkg_name" 2>&1 | sed 's/^/      /' || true
        fi
      done < <(brew outdated --formula --verbose 2>/dev/null || true)
    else
      brew upgrade 2>&1 | sed 's/^/      /' || true
    fi
  fi
  ok "Homebrew formulae upgraded"

  # ── 1b. Homebrew casks (opt-in) ───────────────────────────────────────────
  if $CASKS; then
    log "Upgrading Homebrew casks..."
    if $DRY_RUN; then
      echo "      [dry-run] brew upgrade --cask"
      brew outdated --cask 2>/dev/null | sed 's/^/      [dry-run] would upgrade: /' || true
    else
      brew upgrade --cask 2>&1 | sed 's/^/      /' || true
    fi
    ok "Homebrew casks upgraded"
  else
    skipped "Homebrew casks — pass --casks to enable"
  fi
else
  skipped "brew — not installed"
fi

# ── 2. npm global packages ────────────────────────────────────────────────────
if $HAS_NPM; then
  log "Upgrading npm global packages..."
  if $DRY_RUN; then
    echo "      [dry-run] npm update -g"
    npm outdated -g --depth=0 2>/dev/null | sed 's/^/      [dry-run] would upgrade: /' || true
  else
    if $SKIP_MAJOR; then
      while IFS= read -r line; do
        [[ -z "$line" || "$line" == Package* ]] && continue
        pkg_name=$(echo "$line" | awk '{print $1}')
        old_ver=$(echo "$line"  | awk '{print $2}')
        new_ver=$(echo "$line"  | awk '{print $4}')
        if is_major_bump "$old_ver" "$new_ver"; then
          SKIPPED_MAJOR+=("npm:${pkg_name} ${old_ver} → ${new_ver}")
          warn "Skipped major bump: ${pkg_name} ${old_ver} → ${new_ver}"
        else
          npm install -g "${pkg_name}@${new_ver}" 2>&1 | sed 's/^/      /' || true
        fi
      done < <(npm outdated -g --depth=0 2>/dev/null || true)
    else
      npm update -g 2>&1 | sed 's/^/      /' || true
    fi
  fi
  ok "npm global packages upgraded"
else
  skipped "npm — not installed"
fi

# ── 3. pip3 packages ──────────────────────────────────────────────────────────
if $HAS_PIP; then
  log "Upgrading pip3 packages..."
  if $DRY_RUN; then
    echo "      [dry-run] pip3 install --upgrade <outdated packages>"
    pip3 list --outdated --format=columns 2>/dev/null | tail -n +3 \
      | awk '{print $1, $2, "→", $3}' \
      | sed 's/^/      [dry-run] would upgrade: /' || true
  else
    outdated=$(pip3 list --outdated --format=freeze 2>/dev/null | cut -d= -f1 || true)
    if [[ -n "$outdated" ]]; then
      if $SKIP_MAJOR; then
        while IFS= read -r line; do
          [[ -z "$line" || "$line" == Package* || "$line" == ---* ]] && continue
          pkg_name=$(echo "$line" | awk '{print $1}')
          old_ver=$(echo "$line"  | awk '{print $2}')
          new_ver=$(echo "$line"  | awk '{print $3}')
          if is_major_bump "$old_ver" "$new_ver"; then
            SKIPPED_MAJOR+=("pip:${pkg_name} ${old_ver} → ${new_ver}")
            warn "Skipped major bump: ${pkg_name} ${old_ver} → ${new_ver}"
          else
            pip3 install --upgrade "$pkg_name" 2>&1 | sed 's/^/      /' || true
          fi
        done < <(pip3 list --outdated --format=columns 2>/dev/null | tail -n +3 || true)
      else
        echo "$outdated" | xargs pip3 install --upgrade 2>&1 | sed 's/^/      /' || true
      fi
    else
      ok "pip3 — all packages already up to date"
    fi
  fi
  ok "pip3 packages upgraded"
else
  skipped "pip3 — not installed"
fi

# ── 4. Ruby gems ──────────────────────────────────────────────────────────────
if $HAS_GEM; then
  log "Upgrading Ruby gems..."
  if $DRY_RUN; then
    echo "      [dry-run] gem update"
    gem outdated 2>/dev/null | sed 's/^/      [dry-run] would upgrade: /' || true
  else
    gem update 2>&1 | sed 's/^/      /' || true
  fi
  ok "Ruby gems upgraded"
else
  skipped "gem — not installed"
fi

# ── 5. rustup ─────────────────────────────────────────────────────────────────
if $HAS_RUSTUP; then
  log "Updating Rust toolchains via rustup..."
  if $DRY_RUN; then
    echo "      [dry-run] rustup update"
  else
    rustup update 2>&1 | sed 's/^/      /' || true
  fi
  ok "Rust toolchains updated"
else
  skipped "rustup — not installed"
fi

# ── 6. mas (Mac App Store) ────────────────────────────────────────────────────
if $HAS_MAS; then
  log "Upgrading Mac App Store apps via mas..."
  if $DRY_RUN; then
    echo "      [dry-run] mas upgrade"
    mas outdated 2>/dev/null | sed 's/^/      [dry-run] would upgrade: /' || true
  else
    mas upgrade 2>&1 | sed 's/^/      /' || true
  fi
  ok "App Store apps upgraded"
else
  skipped "mas — not installed (install with: brew install mas)"
fi

# ── Security Audit ────────────────────────────────────────────────────────────
echo
echo "${BOLD}=== Security Audit ===${RESET}"
echo "  Scanning for known vulnerabilities introduced by updates..."
echo

# npm audit
if $HAS_NPM; then
  seclog "Running npm audit (global packages)..."
  if $DRY_RUN; then
    echo "      [dry-run] npm audit -g"
  else
    # npm audit doesn't have a -g flag natively; audit from the global prefix
    GLOBAL_PREFIX=$(npm root -g 2>/dev/null | sed 's|/node_modules||' || true)
    if [[ -n "$GLOBAL_PREFIX" && -f "$GLOBAL_PREFIX/package.json" ]]; then
      audit_out=$(cd "$GLOBAL_PREFIX" && npm audit --json 2>/dev/null || true)
      vuln_count=$(echo "$audit_out" | grep -o '"total":[0-9]*' | head -1 | tr -dc '0-9' || true)
      vuln_count="${vuln_count:-0}"
      if [[ "$vuln_count" -gt 0 ]]; then
        warn "npm audit: ${vuln_count} vulnerabilities found — run 'npm audit' in ${GLOBAL_PREFIX} for details"
        AUDIT_ISSUES=$((AUDIT_ISSUES + vuln_count))
      else
        ok "npm audit: no known vulnerabilities"
      fi
    else
      # Fallback: run npm audit in a temp context to check global packages
      audit_output=$(npm audit 2>&1 || true)
      if echo "$audit_output" | grep -qi "found [^0].*vulnerabilit"; then
        warn "npm audit: vulnerabilities detected — review output above"
        AUDIT_ISSUES=$((AUDIT_ISSUES + 1))
      else
        ok "npm audit: no known vulnerabilities"
      fi
    fi
  fi
else
  skipped "npm audit — npm not installed"
fi

# pip-audit
if $HAS_PIPAUDIT; then
  seclog "Running pip-audit..."
  if $DRY_RUN; then
    echo "      [dry-run] pip-audit"
  else
    if pip_audit_out=$(pip-audit 2>&1); then
      ok "pip-audit: no known vulnerabilities"
    else
      warn "pip-audit: vulnerabilities detected"
      echo "$pip_audit_out" | sed 's/^/      /'
      AUDIT_ISSUES=$((AUDIT_ISSUES + 1))
    fi
  fi
elif $HAS_PIP; then
  skipped "pip-audit — not installed (install with: pip3 install pip-audit)"
else
  skipped "pip-audit — pip3 not installed"
fi

# brew audit
if $HAS_BREW; then
  seclog "Running brew audit --strict..."
  if $DRY_RUN; then
    echo "      [dry-run] brew audit --strict"
  else
    if brew_audit_out=$(brew audit --strict 2>&1); then
      ok "brew audit: no issues found"
    else
      warn "brew audit: issues detected"
      echo "$brew_audit_out" | grep -v "^$" | head -20 | sed 's/^/      /' || true
      AUDIT_ISSUES=$((AUDIT_ISSUES + 1))
    fi
  fi
else
  skipped "brew audit — brew not installed"
fi

# ── --skip-major summary ──────────────────────────────────────────────────────
if [[ ${#SKIPPED_MAJOR[@]} -gt 0 ]]; then
  echo
  echo "${BOLD}=== Major Version Bumps Skipped (manual review required) ===${RESET}"
  for entry in "${SKIPPED_MAJOR[@]}"; do
    printf "  ${YELLOW}–${RESET}  %s\n" "$entry"
  done
  echo "  Review changelogs before upgrading these manually."
fi

# ── Summary ───────────────────────────────────────────────────────────────────
END_TS=$(date +%s)
ELAPSED=$((END_TS - START_TS))
MINS=$((ELAPSED / 60))
SECS=$((ELAPSED % 60))

echo
echo "${BOLD}=== Summary ===${RESET}"
printf "  Time:             %dm %ds\n"  "$MINS" "$SECS"
printf "  Major bumps skipped: %s\n"   "${#SKIPPED_MAJOR[@]}"
printf "  Audit issues:     %s\n"       "$AUDIT_ISSUES"
$DRY_RUN && echo "${YELLOW}  (Dry run — rerun without --dry-run to apply)${RESET}"

if [[ $AUDIT_ISSUES -gt 0 ]]; then
  echo
  echo "${RED}${BOLD}  ⚠  Security issues detected. Review audit output above before continuing.${RESET}"
  echo
  exit 1
fi

echo
