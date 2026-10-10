#!/usr/bin/env bash
# Lists fingerprints without a pool release as a JSON array of ids.
#
# Usage: scripts/pool-plan.sh <fingerprint directory>...
#
# Invalid files (e.g. in the repository of reported fingerprints) are
# skipped with a warning. At most POOL_MAX_BUILDS ids (default 5) are
# listed per run. Needs GH_TOKEN and GITHUB_REPOSITORY (set in GitHub
# Actions).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MAX_BUILDS="${POOL_MAX_BUILDS:-5}"

ids=()

for dir in "$@"
do
  for file in "$dir"/*.txt
  do
    [[ -f "$file" ]] || continue

    if ! id="$("$REPO_DIR/scripts/fingerprint.sh" "$file" 2>&1)"
    then
      echo "::warning::Skipped $file: $id" >&2
      continue
    fi

    if [[ "$(basename "$file" .txt)" != "$id" ]]
    then
      echo "::warning::Skipped $file: file name does not match its id $id" >&2
      continue
    fi

    [[ " ${ids[*]} " != *" $id "* ]] || continue

    if gh release view "fp-$id" --repo "$GITHUB_REPOSITORY" > /dev/null 2>&1
    then
      echo "fp-$id already published" >&2
    elif (( ${#ids[@]} >= MAX_BUILDS ))
    then
      echo "fp-$id needs a build, deferred to the next run" >&2
    else
      echo "fp-$id needs a build" >&2
      ids+=("$id")
    fi
  done
done

printf '%s\n' "${ids[@]}" | jq -R 'select(length > 0)' | jq -cs .
