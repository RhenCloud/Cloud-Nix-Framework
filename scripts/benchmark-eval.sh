#!/usr/bin/env bash
set -euo pipefail

flake_ref=${1:-path:.}
attribute=${2:-checks.x86_64-linux.newfeatures.drvPath}
runs=${RUNS:-3}

if ! [[ $runs =~ ^[1-9][0-9]*$ ]]; then
  echo "RUNS 必须是正整数" >&2
  exit 2
fi

printf 'flake: %s\nattribute: %s\nruns: %s\n\n' "$flake_ref" "$attribute" "$runs"

for run in $(seq 1 "$runs"); do
  stats_file=$(mktemp)
  time_file=$(mktemp)
  trap 'rm -f "$stats_file" "$time_file"' EXIT

  "$(type -P time)" -f '{"elapsedSeconds":%e,"maxResidentKiB":%M}' -o "$time_file" \
    env NIX_SHOW_STATS=1 nix eval \
      --offline \
      --no-eval-cache \
      --raw \
      "${flake_ref}#${attribute}" \
      >/dev/null \
      2>"$stats_file"

  evaluator=$(sed -n '/^{/,$p' "$stats_file" | tr -d '\n')
  if [ -z "$evaluator" ]; then
    echo "未从 nix eval 获得 evaluator 统计信息" >&2
    cat "$stats_file" >&2
    exit 1
  fi

  printf '{"run":%d,"wall":%s,"evaluator":%s}\n' \
    "$run" \
    "$(cat "$time_file")" \
    "$evaluator"

  rm -f "$stats_file" "$time_file"
  trap - EXIT
done
