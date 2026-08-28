#!/usr/bin/env bash
# Синхронизация configs/ между Sitko163/rr, Sitko163/aviasales, Sitko163/airlineportal.
# Запускается из GitHub Actions после push в main (не [config-sync]).
set -euo pipefail

SOURCE_REPO="${SOURCE_REPO:-${GITHUB_REPOSITORY:-}}"
TOKEN="${CONFIG_SYNC_TOKEN:-}"
WORK_DIR="${WORK_DIR:-$(mktemp -d)}"
SRC_ROOT="${SRC_ROOT:-${GITHUB_WORKSPACE:-$(pwd)}}"

ALL_REPOS=(
  Sitko163/rr
  Sitko163/aviasales
  Sitko163/airlineportal
)

if [[ -z "$SOURCE_REPO" ]]; then
  echo "SOURCE_REPO is required" >&2
  exit 1
fi
if [[ -z "$TOKEN" ]]; then
  echo "CONFIG_SYNC_TOKEN is required" >&2
  exit 1
fi

source_configs_dir() {
  if [[ "$SOURCE_REPO" == Sitko163/airlineportal ]]; then
    echo "$SRC_ROOT/rubikon/configs"
  else
    echo "$SRC_ROOT/configs"
  fi
}

source_releases_file() {
  if [[ "$SOURCE_REPO" == Sitko163/airlineportal ]]; then
    echo "$SRC_ROOT/rubikon/releases.json"
  else
    echo "$SRC_ROOT/releases.json"
  fi
}

target_configs_dir() {
  local target_repo=$1
  if [[ "$target_repo" == Sitko163/airlineportal ]]; then
    echo "$WORK_DIR/$target_repo/rubikon/configs"
  else
    echo "$WORK_DIR/$target_repo/configs"
  fi
}

target_releases_file() {
  local target_repo=$1
  if [[ "$target_repo" == Sitko163/airlineportal ]]; then
    echo "$WORK_DIR/$target_repo/rubikon/releases.json"
  else
    echo "$WORK_DIR/$target_repo/releases.json"
  fi
}

sync_into_repo() {
  local target_repo=$1
  local repo_dir="$WORK_DIR/$target_repo"
  local src_cfg
  src_cfg="$(source_configs_dir)"

  if [[ ! -d "$src_cfg" ]]; then
    echo "Skip $target_repo: source configs dir missing ($src_cfg)" >&2
    return 0
  fi

  echo "==> Sync $SOURCE_REPO -> $target_repo"
  git clone --depth 1 --branch main \
    "https://x-access-token:${TOKEN}@github.com/${target_repo}.git" \
    "$repo_dir"

  local dst_cfg
  dst_cfg="$(target_configs_dir "$target_repo")"
  mkdir -p "$dst_cfg"
  rsync -a --delete --exclude '.DS_Store' "$src_cfg/" "$dst_cfg/"

  local src_rel dst_rel
  src_rel="$(source_releases_file)"
  dst_rel="$(target_releases_file "$target_repo")"
  if [[ -f "$src_rel" ]]; then
    mkdir -p "$(dirname "$dst_rel")"
    cp "$src_rel" "$dst_rel"
  fi

  if [[ "$SOURCE_REPO" != Sitko163/airlineportal && "$target_repo" != Sitko163/airlineportal ]]; then
    if [[ -f "$SRC_ROOT/settings.json" ]]; then
      cp "$SRC_ROOT/settings.json" "$repo_dir/settings.json"
    fi
  fi

  pushd "$repo_dir" >/dev/null
  if git diff --quiet && git diff --cached --quiet; then
    echo "    no changes"
    popd >/dev/null
    return 0
  fi

  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  git add -A
  git commit -m "chore(config-sync): sync from ${SOURCE_REPO}@${GITHUB_SHA:-local} [config-sync]"
  git push origin main
  echo "    pushed"
  popd >/dev/null
}

trap 'rm -rf "$WORK_DIR"' EXIT

for repo in "${ALL_REPOS[@]}"; do
  [[ "$repo" == "$SOURCE_REPO" ]] && continue
  sync_into_repo "$repo"
done

echo "==> Config sync complete"
