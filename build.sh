#!/usr/bin/env bash
# Re-compile each example to .wat (via bcplwasm inside cintsys) and
# assemble to .wasm (via wat2wasm).
#
# Requires: BCPLROOT, BCPLPATH env set; wat2wasm on PATH.

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
cd "$ROOT"

WAT2WASM="${WAT2WASM:-wat2wasm}"
WASM_OPT="${WASM_OPT:-wasm-opt}"
ASYNC_IMPORTS="env.bcpl_cowait,env.bcpl_callco,env.bcpl_resumeco,env.bcpl_changeco,env.bcpl_delay"

# Validate master.wat vs libhdr.h + stdlib-manifest.mjs before
# building examples. Fails fast if any drift.
node site/test-globals.mjs
# Scan all g/*.h headers for collisions in the Cintcode stdlib range.
node site/test-headers.mjs

# Run wasm-opt --asyncify on a built .wasm if the source is a coroutine
# example (file name starts with one of the coroutine-track slugs OR
# the BCPL source contains a call to one of the suspend imports).
needs_asyncify() {
  local src="$1"
  grep -qE '\b(cowait|callco|resumeco|changeco|createco|delay)\b' "$src"
}

for src in site/examples/*.b; do
  base="${src%.b}"
  name="$(basename "$base")"
  echo ">> $name"
  echo "bcplwasm $src to ${base}.wat" | bin/cintsys >/dev/null
  "$WAT2WASM" "${base}.wat" -o "${base}.wasm"
  if needs_asyncify "$src" && command -v "$WASM_OPT" >/dev/null 2>&1; then
    "$WASM_OPT" --asyncify --enable-bulk-memory --enable-reference-types \
      --pass-arg=asyncify-imports@"$ASYNC_IMPORTS" \
      "${base}.wasm" -o "${base}.wasm"
  fi
  # Post-pass optimizer: binaryen -O2 inlines, peephole-folds, dead-
  # code-eliminates, sinks loads. Cheap ~10–35% speed win on top of
  # the playground's straight-line emit. Skip if WASM_OPT missing.
  if command -v "$WASM_OPT" >/dev/null 2>&1; then
    "$WASM_OPT" -O2 --enable-bulk-memory --enable-reference-types \
      "${base}.wasm" -o "${base}.wasm"
  fi
done
echo "built: $(ls site/examples/*.wasm | wc -l) modules"
