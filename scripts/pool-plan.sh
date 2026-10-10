#!/usr/bin/env bash
# Lists fingerprints without a pool release as a JSON array of ids.
# Needs GH_TOKEN and GITHUB_REPOSITORY (set in GitHub Actions).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

ids=()

for file in "$REPO_DIR"/fingerprints/*.txt
do
  [[ -f "$file" ]] || continue

  id="$("$REPO_DIR/scripts/fingerprint.sh" "$file")"
  [[ "$(basename "$file" .txt)" == "$id" ]] ||
    { echo "File name of $file does not match its id $id" >&2; exit 1; }

  if gh release view "fp-$id" --repo "$GITHUB_REPOSITORY" > /dev/null 2>&1
  then
    echo "fp-$id already published" >&2
  else
    echo "fp-$id needs a build" >&2
    ids+=("$id")
  fi
done

printf '%s\n' "${ids[@]}" | jq -R 'select(length > 0)' | jq -cs .
