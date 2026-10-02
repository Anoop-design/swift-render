#!/usr/bin/env bash
# Report Swift expressions and functions that are slow to type-check — the same
# spots older compilers (CI's Swift 6.1) reject with "unable to type-check this
# expression in reasonable time". Report-only unless STRICT=1.
#
#   scripts/typecheck-budget.sh            # expressions > 200ms, functions > 600ms
#   scripts/typecheck-budget.sh 150 400    # tighter budget
#   STRICT=1 scripts/typecheck-budget.sh   # exit 1 when anything is over budget
set -uo pipefail
EXPR=${1:-200}
FUNC=${2:-600}
cd "$(dirname "$0")/.."
ROOT=$(pwd)

# Fresh scratch dir: warnings are only emitted when files actually recompile.
rm -rf .build/typecheck
out=$(swift build --scratch-path .build/typecheck \
  -Xswiftc -Xfrontend -Xswiftc "-warn-long-expression-type-checking=$EXPR" \
  -Xswiftc -Xfrontend -Xswiftc "-warn-long-function-bodies=$FUNC" 2>&1)
hits=$(printf '%s\n' "$out" | grep -E "^/.*: warning: .*took [0-9]+ms to type-check" | sed "s|$ROOT/||" | sort -u)

if [ -z "$hits" ]; then
  echo "type-check budget OK (expressions < ${EXPR}ms, functions < ${FUNC}ms)"
  exit 0
fi
printf '%s\n' "$hits"
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  printf '%s\n' "$hits" | while IFS= read -r l; do
    file=${l%%:*}; rest=${l#*:}; line=${rest%%:*}
    echo "::warning file=$file,line=$line::${l#*warning: }"
  done
fi
echo "$(printf '%s\n' "$hits" | wc -l | tr -d ' ') slow spot(s) — split them into smaller expressions/functions"
[ "${STRICT:-0}" = "1" ] && exit 1
exit 0
