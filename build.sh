#!/bin/sh
# Assemble the museum site/ from its two upstreams:
#   - the BCPL distribution  ($BCPL): IDE runtime, compiler-in-wasm, examples
#   - the 1972 C compilers   ($PROTOC): built to wasm with emscripten
# plus the museum-owned shell (src/index.html, src/lang-c.mjs). The result,
# site/, is a self-contained static site. Neither upstream is modified.
#
#   ./build.sh            core BCPL + C   (skips the heavy DOOM/textures demos)
#   ./build.sh --full     also vendor DOOM/ and textures/
set -e
here=$(cd "$(dirname "$0")" && pwd)
BCPL=${BCPL:-$here/../BCPLwasm/cintcode/site}
PROTOC=${PROTOC:-$here/../proto-c}
out=$here/site

[ -d "$BCPL" ] || { echo "build.sh: BCPL site not found at $BCPL (set BCPL=)" >&2; exit 1; }

heavy="--exclude DOOM/ --exclude textures/"
[ "$1" = "--full" ] && heavy=""

echo "vendoring BCPL assets from $BCPL"
mkdir -p "$out"
rsync -a --delete \
	--exclude index.html --exclude node_modules --exclude 'package*.json' \
	--exclude 'test-*.mjs' --exclude '*.wat' --exclude .DS_Store \
	--exclude lang-c.mjs --exclude compilers/ --exclude site/ \
	$heavy \
	"$BCPL"/ "$out"/

echo "overlaying museum shell"
cp "$here/src/index.html" "$here/src/lang-c.mjs" "$here/src/lang-b.mjs" "$out"/

echo "overlaying museum-owned vendor (wabt, binaryen)"
mkdir -p "$out/vendor"
cp "$here"/vendor/* "$out/vendor"/

echo "building C compilers from $PROTOC"
PROTOC="$PROTOC" OUTDIR="$out/compilers" "$here/compilers/build-c.sh"

echo "done -> $out  (serve with: cd site && python3 -m http.server)"
