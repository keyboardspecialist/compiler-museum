#!/bin/sh
# Build the two modernized 1972 C compilers to wasm (emscripten). Each becomes
# an ES6 module whose factory callMain's the compiler over a MEMFS source file,
# printing WAT to stdout. Outputs land in ../site/compilers (the built site).
set -e
here=$(cd "$(dirname "$0")" && pwd)
src=${PROTOC:-$here/../../proto-c}
out=${OUTDIR:-$here/../site/compilers}
mkdir -p "$out"

WARN="-Wno-implicit-int -Wno-deprecated-non-prototype -Wno-implicit-function-declaration \
-Wno-int-conversion -Wno-return-type -Wno-parentheses -Wno-unused-label"
EMFLAGS="-sMODULARIZE -sEXPORT_ES6 -sEXPORTED_RUNTIME_METHODS=callMain,FS -sINVOKE_RUN=0 \
-sEXIT_RUNTIME=0 -sALLOW_MEMORY_GROWTH=1"

build() {
	dir="$1"; name="$2"
	echo "emcc $dir -> $name"
	emcc -std=c89 -O2 $WARN \
		"$src/$dir/c00.c" "$src/$dir/c01.c" "$src/$dir/c02.c" "$src/$dir/c03.c" \
		"$src/$dir/tables.c" "$src/$dir/runtime.c" "$src/$dir/wat.c" \
		$EMFLAGS -o "$out/$name.mjs"
}

build c89       cfront-prestruct
build c89-1120  cfront-1120

# B compilers (b00-b03 source names, own backend copies).
echo "emcc b72 -> cfront-b"
emcc -std=c89 -O2 $WARN \
	"$src/b72/b00.c" "$src/b72/b01.c" "$src/b72/b02.c" "$src/b72/b03.c" \
	"$src/b72/tables.c" "$src/b72/runtime.c" "$src/b72/wat.c" \
	$EMFLAGS -o "$out/cfront-b.mjs"

echo "emcc b-waterloo -> cfront-bw"
emcc -std=c89 -O2 $WARN \
	"$src/b-waterloo/b00.c" "$src/b-waterloo/b01.c" "$src/b-waterloo/b02.c" "$src/b-waterloo/b03.c" \
	"$src/b-waterloo/tables.c" "$src/b-waterloo/runtime.c" "$src/b-waterloo/wat.c" \
	$EMFLAGS -o "$out/cfront-bw.mjs"

echo "done -> $out/cfront-{prestruct,1120,b,bw}.{mjs,wasm}"
