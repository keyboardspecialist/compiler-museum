# Compiler Museum

A web IDE that hosts historical compilers behind one interface — pick a
language by file extension, edit, compile, inspect the emitted WebAssembly, and
run, all client-side. A **downstream** project: it consumes two upstreams and
modifies neither.

- **BCPL distribution** (`../BCPLwasm/cintcode/site`) — Martin Richards' BCPL,
  compiled to wasm, plus the IDE runtime, examples, and shell.
- **1972 C compilers** (`../proto-c`) — Dennis Ritchie's `last1120` and
  `prestruct` compilers, modernized to C89 with a WebAssembly backend.
- (future languages drop in the same way.)

## Build & run

```
./build.sh            # vendor BCPL core + build the C compilers -> site/
./build.sh --full     # also include the heavy DOOM/textures demos
cd site && python3 -m http.server 8000   # open http://localhost:8000/
npm test              # playwright E2E (BCPL regression + C)
```

`build.sh` rsyncs the BCPL site assets and emscripten-builds the C compilers
into `site/` (gitignored, deployable). Override locations with `BCPL=` /
`PROTOC=`.

## What's museum-owned vs vendored

Tracked (museum-owned):
```
src/index.html      forked BCPL IDE shell + the C integration
src/lang-c.mjs      C language module: compile (cfront-wasm -> WAT), CRuntime, examples
compilers/build-c.sh emcc proto-c -> site/compilers/cfront-{prestruct,1120}.{wasm,mjs}
build.sh            assembles site/ from the upstreams
test/test-museum.mjs playwright E2E
```
Everything else under `site/` is vendored/built and gitignored.

## How a language is chosen

By the **entry file's extension**: `.c` -> the C compiler (dialect picked by the
`C dialect` control), anything else -> BCPL. `.b` and `.c` files coexist in the
files pane; the BCPL debugger gates off when the entry is `.c` (C is greenfield —
its own debugging can come later). Adding a compiler is a `lang-<x>.mjs` plus a
small shell hook.

## Reconciling the shell with upstream BCPL

`src/index.html` is a fork of the BCPL IDE's `index.html` (BCPL has no plugin
layer). The C delta is ~136 lines; the bulk of the C surface lives in
`lang-c.mjs`. To pull upstream IDE changes:

```
diff $BCPL/index.html src/index.html      # review; re-apply the C delta
```

Fork base: BCPL `cintcode/site/index.html` as of June 2026.
