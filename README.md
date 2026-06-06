# Compiler Museum

A web IDE that hosts historical compilers behind one interface — pick a
language by file extension, edit, compile, inspect the emitted WebAssembly, and
run, all client-side. A **downstream** project: it consumes two upstreams and
modifies neither.

- **BCPL distribution** (`../BCPLwasm/cintcode/site`) — Martin Richards' BCPL,
  compiled to wasm, plus the IDE runtime, examples, and shell.
- **1972 C compilers** (`../proto-c`) — Dennis Ritchie's `last1120` and
  `prestruct` compilers, modernized to C89 with a WebAssembly backend.
- **1972 B** (`../proto-c/b72`) — Ken Thompson's B, the typeless ancestor of C,
  on the same WAT backend (`.b72` files; `.b` is BCPL).
- **Waterloo B / 1978** (`../proto-c/b-waterloo`) — the richer Honeywell-era B
  (for/repeat, `+=`, `&&`/`||`, switch ranges, f32 `#`-floats; `.b78` files).
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
src/index.html      forked BCPL IDE shell + the C and B integration
src/lang-c.mjs      C language module: compile (cfront-wasm -> WAT), CRuntime, examples
src/lang-b.mjs      B (1972) module: compile (cfront-b -> WAT), examples (reuses CRuntime)
src/lang-bw.mjs     Waterloo B (1978) module: compile (cfront-bw -> WAT), examples
compilers/build-c.sh emcc proto-c -> site/compilers/cfront-{prestruct,1120,b,bw}.{wasm,mjs}
vendor/wabt.js      self-contained UMD WAT->wasm assembler (window.WabtModule)
vendor/binaryen.mjs self-contained ESM (v129) for the asyncify pass
build.sh            assembles site/ from the upstreams
test/test-museum.mjs playwright E2E
```
`vendor/` is committed so the deployed site is fully self-contained — no CDN.
`build.sh` overlays it onto `site/vendor/` after rsyncing the BCPL assets.
Everything else under `site/` is vendored-from-upstream/built and gitignored.

## Deploy (GitHub Pages)

`site/` is a self-contained static site. It ships to the `gh-pages` branch
(served at `https://keyboardspecialist.github.io/compiler-museum/`):

```
./build.sh && ./deploy.sh     # build, then sync site/ -> gh-pages branch + push
```

Enable once in repo Settings -> Pages -> Branch `gh-pages` / root.

## How a language is chosen

By the **entry file's extension**: `.c` -> the C compiler (dialect picked by the
`C dialect` control), `.b72` -> B (1972), `.b78` -> Waterloo B (1978), anything
else -> BCPL (`.b` is BCPL). `.b`, `.c`, `.b72`, and `.b78` files coexist in the pane;
the centered header indicator names the active language, and the BCPL debugger
gates off for the greenfield languages (C, B) — their own debugging can come
later. Adding a compiler is a `lang-<x>.mjs` plus a small shell hook.

## Reconciling the shell with upstream BCPL

`src/index.html` is a fork of the BCPL IDE's `index.html` (BCPL has no plugin
layer). The C delta is ~136 lines; the bulk of the C surface lives in
`lang-c.mjs`. To pull upstream IDE changes:

```
diff $BCPL/index.html src/index.html      # review; re-apply the C delta
```

Fork base: BCPL `cintcode/site/index.html` as of June 2026.
