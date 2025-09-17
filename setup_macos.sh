#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────────────────────
# macOS (Apple Silicon) dotfiles bootstrap using Brewfile
# - Requires: Brewfile containing stow, ghostty, zen, font-jetbrains-mono-nerd-font
# - Installs Xcode CLT, Homebrew (/opt/homebrew)
# - Taps fonts cask repo and runs brew bundle
# - Stows: base + macos -> $HOME
# Usage: ./scripts/setup_macos_arm.sh
# ────────────────────────────────────────────────────────────────────────────────

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BREWFILE="${REPO_ROOT}/Brewfile"
TARGET_DIR="${HOME}"
STOW_PACKAGES=(base macos)

info()  { printf "\033[1;34m[i]\033[0m %s\n" "$*"; }
ok()    { printf "\033[1;32m[✓]\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err()   { printf "\033[1;31m[x]\033[0m %s\n" "$*\n" >&2; }

require_arm_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || { err "This script is for macOS."; exit 1; }
  [[ "$(uname -m)" == "arm64"   ]] || { err "Apple Silicon (arm64) only."; exit 1; }
}

ensure_xcode_clt() {
  if xcode-select -p &>/dev/null; then
    ok "Xcode Command Line Tools present."
  else
    info "Installing Xcode Command Line Tools… (system dialog will appear)"
    xcode-select --install || true
    until xcode-select -p &>/dev/null; do sleep 5; done
    ok "Xcode CLT installed."
  fi
}

ensure_homebrew() {
  if command -v /opt/homebrew/bin/brew &>/dev/null; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    ok "Homebrew present."
    return
  fi

  info "Installing Homebrew to /opt/homebrew…"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"

  # Persist for zsh sessions
  if ! grep -q 'brew shellenv' "${HOME}/.zprofile" 2>/dev/null; then
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "${HOME}/.zprofile"
  fi
  ok "Homebrew installed."
}

brew_prepare_and_bundle() {
  brew update

  if [[ -f "$BREWFILE" ]]; then
    info "Running brew bundle using ${BREWFILE}…"
    brew bundle --file="$BREWFILE" || warn "brew bundle reported issues (continuing)."
  else
    warn "No Brewfile at ${BREWFILE}. Skipping bundle."
  fi

  # Make sure stow exists even if not in Brewfile
  command -v stow &>/dev/null || brew install stow
  ok "Homebrew packages ensured."
}

backup_conflicts() {
  local backup_dir="${HOME}/.dotfiles_backup_$(date +%Y%m%d_%H%M%S)"
  local conflicts=()

  info "Scanning for Stow conflicts…"
  for pkg in "${STOW_PACKAGES[@]}"; do
    local pkg_dir="${REPO_ROOT}/${pkg}"
    [[ -d "$pkg_dir" ]] || continue
    while IFS= read -r -d '' file; do
      local rel="${file#$pkg_dir/}"
      local dest="${TARGET_DIR}/${rel}"
      if [[ -e "$dest" && ! -L "$dest" ]]; then
        conflicts+=("$dest")
      fi
    done < <(find "$pkg_dir" -type f -print0)
  done

  if ((${#conflicts[@]})); then
    info "Backing up ${#conflicts[@]} files to ${backup_dir}…"
    for path in "${conflicts[@]}"; do
      mkdir -p "${backup_dir}$(dirname "${path}")"
      mv "$path" "${backup_dir}${path}"
    done
    warn "Backup at: ${backup_dir}"
  else
    ok "No conflicts."
  fi
}

run_stow() {
  info "Stowing: ${STOW_PACKAGES[*]} → ${TARGET_DIR}"
  mkdir -p "${TARGET_DIR}/.config"
  (cd "$REPO_ROOT" && stow -v -S -t "$TARGET_DIR" "${STOW_PACKAGES[@]}")
  ok "Stow complete."
}

main() {
  require_arm_macos
  info "Repo: ${REPO_ROOT}"
  ensure_xcode_clt
  ensure_homebrew
  brew_prepare_and_bundle
  backup_conflicts
  run_stow
  ok "All done. In Ghostty, pick: JetBrainsMonoNL Nerd Font Mono."
}

main "$@"

