#!/bin/bash
# update-claude.sh — Detect Claude version and auto-patch after update
#
# Usage:
#   update-claude --patch-only     # auto-detect version, patch all installs (hook mode)
#   update-claude [version]        # npm install specified version + patch

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
DIM='\033[2m'
NC='\033[0m'

sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }

# Detect installed Claude version
# Priority: native symlink (instant), then local npm install, then claude --version.
detect_version() {
  local ver

  # 0. Native: version is in the symlink target filename (e.g. versions/2.1.71)
  local native_link="$HOME/.local/bin/claude"
  if [[ -L "$native_link" ]]; then
    ver=$(basename "$(readlink "$native_link")")
    [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && { echo "$ver"; return 0; }
  fi

  # 1. Local install — trace launcher -> exec path -> package.json
  local launcher="$HOME/.claude/local/claude"
  if [[ -f "$launcher" ]]; then
    local exec_path
    exec_path=$(sed -n 's/^exec "\(.*\)".*/\1/p' "$launcher") || true
    if [[ -n "$exec_path" ]]; then
      local real_bin
      real_bin=$(realpath "$exec_path" 2>/dev/null) || true
      if [[ -n "$real_bin" ]]; then
        local dir=$(dirname "$real_bin")
        for pkg in "$dir/package.json" "$dir/../package.json"; do
          if [[ -f "$pkg" ]]; then
            ver=$(node -e "console.log(require('$pkg').version)" 2>/dev/null) || true
            [[ -n "$ver" ]] && { echo "$ver"; return 0; }
          fi
        done
      fi
    fi
  fi

  # 2. Fallback: claude --version (whichever is first on PATH)
  ver=$(command claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) || true
  [[ -n "$ver" ]] && { echo "$ver"; return 0; }

  return 1
}

# Find all unique cli.js / binary paths (mirrors patch-cli.js findClaudeCli logic)
find_cli_paths() {
  {
    # Method 1: which claude -> realpath -> cli.js in same directory
    local claude_bin real_path cli
    claude_bin=$(command -v claude 2>/dev/null) || true
    if [[ -n "$claude_bin" ]]; then
      real_path=$(realpath "$claude_bin" 2>/dev/null) || true
      if [[ -n "$real_path" ]]; then
        cli="$(dirname "$real_path")/cli.js"
        [[ -f "$cli" ]] && realpath "$cli"
        [[ "$real_path" == *cli.js && -f "$real_path" ]] && echo "$real_path"
      fi
    fi

    # Method 2: common npm global locations
    for loc in "/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js" \
               "/usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js"; do
      [[ -f "$loc" ]] && realpath "$loc"
    done

    # Method 3: ~/.claude/local/ launcher -> exec path
    local launcher="$HOME/.claude/local/claude"
    if [[ -f "$launcher" ]]; then
      local bin_path
      bin_path=$(grep 'exec' "$launcher" 2>/dev/null | head -1 | sed 's/.*exec "\([^"]*\)".*/\1/') || true
      [[ -n "$bin_path" ]] && realpath "$bin_path" 2>/dev/null || true
    fi
  } | sort -u
}

# Find latest existing patch directory (by version sort)
find_latest_patch_dir() {
  ls -d "$REPO_DIR/system-prompt"/[0-9]*.* 2>/dev/null | sort -V | tail -1
}

# Auto-create patch directory for a new version by copying from latest existing one
create_patch_dir() {
  local version="$1"
  local patch_dir="$REPO_DIR/system-prompt/$version"

  local base_dir
  base_dir=$(find_latest_patch_dir)
  if [[ -z "$base_dir" ]]; then
    echo -e "${YELLOW}[create] No existing patch directory found — run /upgrade-patches${NC}"
    return 1
  fi

  local base_version
  base_version=$(basename "$base_dir")
  echo -e "${DIM}[create]${NC} Base: v$base_version"

  cp -r "$base_dir" "$patch_dir"

  # --- Compute hashes for new version ---
  local npm_hash="TODO" native_hash="TODO"

  # npm: find cli.js and hash directly
  local cli_path
  cli_path=$(find_cli_paths | head -1)
  if [[ -n "$cli_path" && -f "$cli_path" ]]; then
    npm_hash=$(sha256 "$cli_path")
  fi

  # native: extract cli.js via native-extract.js, then hash
  local native_bin="$HOME/.local/share/claude/versions/$version"
  if [[ -f "$native_bin" && -f "$patch_dir/native-extract.js" ]]; then
    if node -e "require.resolve('node-lief',{paths:['$patch_dir']})" 2>/dev/null; then
      local tmp_cli="/tmp/native-cli-hash-$$.js"
      if node "$patch_dir/native-extract.js" "$native_bin" "$tmp_cli" 2>/dev/null; then
        native_hash=$(sha256 "$tmp_cli")
      fi
      rm -f "$tmp_cli"
    fi
  fi

  echo -e "${DIM}[create]${NC} Hashes: npm=$npm_hash, native-macos=$native_hash"

  # --- Update version and hashes in copied files ---

  # patch-cli.js: EXPECTED_VERSION and EXPECTED_HASHES
  sed -i '' "s/const EXPECTED_VERSION = '${base_version}'/const EXPECTED_VERSION = '${version}'/" "$patch_dir/patch-cli.js"
  # Only replace hashes if we computed a valid one (64-char hex), otherwise keep base version's hash
  if [[ "$npm_hash" =~ ^[a-f0-9]{64}$ ]]; then
    sed -i '' "s/npm: '[a-f0-9]\{64\}'/npm: '${npm_hash}'/" "$patch_dir/patch-cli.js"
  fi
  if [[ "$native_hash" =~ ^[a-f0-9]{64}$ ]]; then
    sed -i '' "s/'native-macos-arm64': '[a-f0-9]\{64\}'/'native-macos-arm64': '${native_hash}'/" "$patch_dir/patch-cli.js"
  fi

  # backup-cli.sh: EXPECTED_VERSION and EXPECTED_HASH (npm hash)
  sed -i '' "s/EXPECTED_VERSION=\"${base_version}\"/EXPECTED_VERSION=\"${version}\"/" "$patch_dir/backup-cli.sh"
  if [[ "$npm_hash" =~ ^[a-f0-9]{64}$ ]]; then
    sed -i '' "s/EXPECTED_HASH=\"[a-f0-9]\{64\}\"/EXPECTED_HASH=\"${npm_hash}\"/" "$patch_dir/backup-cli.sh"
  fi

  # patch-native.sh: default binary path version (match any version number)
  sed -i '' "s|/versions/[0-9][0-9.]*\"|/versions/${version}\"|" "$patch_dir/patch-native.sh"

  echo -e "${GREEN}[create]${NC} Created system-prompt/$version/"
  return 0
}

# Extract all expected (unpatched original) hashes from patch-cli.js
get_expected_hashes() {
  node -e "
    const c = require('fs').readFileSync(process.argv[1], 'utf8');
    const m = c.match(/EXPECTED_HASHES\s*=\s*\{([\s\S]*?)\}/);
    if (m) for (const h of m[1].matchAll(/'([a-f0-9]{64})'/g)) console.log(h[1]);
  " "$1" 2>/dev/null
}

# Patch a single cli.js / binary
patch_one() {
  local cli_path="$1" version="$2"
  local patch_dir="$REPO_DIR/system-prompt/$version"
  local backup_path="${cli_path}.backup"

  local current_hash expected_hashes
  current_hash=$(sha256 "$cli_path")
  expected_hashes=$(get_expected_hashes "$patch_dir/patch-cli.js")

  # Only patch if hash matches an unpatched original
  if ! echo "$expected_hashes" | grep -qx "$current_hash"; then
    echo -e "  ${DIM}[Skip]${NC} $cli_path (already patched or different build)"
    return 0
  fi

  # Remove stale backup from a previous version
  if [[ -f "$backup_path" ]]; then
    local backup_hash
    backup_hash=$(sha256 "$backup_path")
    if ! echo "$expected_hashes" | grep -qx "$backup_hash"; then
      rm -f "$backup_path"
    fi
  fi

  # Create backup (patch-cli.js requires it)
  if [[ ! -f "$backup_path" ]]; then
    cp "$cli_path" "$backup_path"
  fi

  # Apply patches
  node "$patch_dir/patch-cli.js" "$cli_path"
}

# --- Main ---

mode="full"
target_version=""

for arg in "$@"; do
  case "$arg" in
    --patch-only) mode="patch-only" ;;
    --help|-h)
      echo "Usage:"
      echo "  update-claude --patch-only     # auto-detect & patch (hook mode)"
      echo "  update-claude <version>        # npm install + patch"
      exit 0
      ;;
    *) target_version="$arg" ;;
  esac
done

if [[ "$mode" == "patch-only" ]]; then
  echo -e "\n${DIM}[auto-patch]${NC} Detecting Claude version..."

  version=$(detect_version 2>/dev/null) || {
    echo -e "${YELLOW}[auto-patch] Could not detect version, skipping${NC}"
    exit 0
  }
  echo -e "${DIM}[auto-patch]${NC} Version: $version"

  patch_dir="$REPO_DIR/system-prompt/$version"
  if [[ ! -f "$patch_dir/patch-cli.js" ]]; then
    create_patch_dir "$version" || {
      echo -e "${YELLOW}[auto-patch] No patches for v$version — run /upgrade-patches to create them${NC}"
      exit 0
    }
  fi

  patched=0

  # Patch npm installations (cli.js files)
  while IFS= read -r cli_path; do
    [[ -n "$cli_path" ]] && patch_one "$cli_path" "$version" && patched=1
  done < <(find_cli_paths)

  # Patch native binary if present
  native_bin="$HOME/.local/share/claude/versions/$version"
  if [[ -f "$native_bin" && -f "$patch_dir/patch-native.sh" ]]; then
    # Skip if already patched (different file size than backup = already modified)
    native_backup="${native_bin}.backup"
    if [[ -f "$native_backup" ]] && [[ "$(wc -c < "$native_bin")" != "$(wc -c < "$native_backup")" ]]; then
      echo -e "  ${DIM}[Skip]${NC} $native_bin (already patched)"
    elif node -e "require.resolve('node-lief',{paths:['$patch_dir']})" 2>/dev/null; then
      echo -e "  ${DIM}[native]${NC} Patching $native_bin"
      bash "$patch_dir/patch-native.sh" "$native_bin" && patched=1
    else
      echo -e "  ${YELLOW}[native] Skipped — run 'npm install node-lief' in $patch_dir${NC}"
    fi
  fi

  # Write stamp (coordinates with session-start-patch.js — must use same mtimeMs format)
  cli_local="$HOME/.claude/local/node_modules/@anthropic-ai/claude-code/cli.js"
  if [[ -f "$cli_local" ]]; then
    node -e "console.log(Math.floor(require('fs').statSync('$cli_local').mtimeMs))" \
      > "$HOME/.claude/.patch-stamp" 2>/dev/null || true
  fi
  if [[ -f "$native_bin" ]]; then
    node -e "console.log(Math.floor(require('fs').statSync('$native_bin').mtimeMs))" \
      > "$HOME/.claude/.patch-stamp" 2>/dev/null || true
  fi

  echo -e "${DIM}[auto-patch]${NC} Done\n"

else
  if [[ -z "$target_version" ]]; then
    echo "Usage:"
    echo "  update-claude --patch-only     # auto-detect & patch (hook mode)"
    echo "  update-claude <version>        # npm install + patch"
    exit 1
  fi

  echo "Installing @anthropic-ai/claude-code@$target_version..."
  npm install -g "@anthropic-ai/claude-code@$target_version"

  echo ""
  exec "$0" --patch-only
fi
