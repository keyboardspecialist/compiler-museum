#!/bin/sh
# Build the two modernized 1972 C compilers to wasm with emscripten, so they
# run client-side in the museum. Each becomes an ES6 module exposing a factory
# that callMain's the compiler over a MEMFS source file, printing WAT to stdout.
set -e
here=$(cd "$(dirname "$0")" && pwd)
src=${PROTOC:-$here/../../proto-c}

WARN="-Wno-implicit-int -Wno-deprecated-non-prototype -Wno-implicit-function-declaration \
-Wno-int-conversion -Wno-return-type -Wno-parentheses -Wno-unused-label"
EMFLAGS="-sMODULARIZE -sEXPORT_ES6 -sEXPORTED_RUNTIME_METHODS=callMain,FS -sINVOKE_RUN=0 \
-sEXIT_RUNTIME=0 -sALLOW_MEMORY_GROWTH=1"

build() {
	dir="$1"; out="$2"
	echo "emcc $dir -> $out"
	emcc -std=c89 -O2 $WARN \
		"$src/$dir/c00.c" "$src/$dir/c01.c" "$src/$dir/c02.c" "$src/$dir/c03.c" \
		"$src/$dir/tables.c" "$src/$dir/runtime.c" "$src/$dir/wat.c" \
		$EMFLAGS -o "$here/$out.mjs"
}

build c89       cfront-prestruct
build c89-1120  cfront-1120
echo "done -> $here/cfront-{prestruct,1120}.{mjs,wasm}"
