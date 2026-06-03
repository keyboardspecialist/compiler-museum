# Compiler Museum

A static, client-side web IDE that hosts historical compilers behind one
interface: pick a language/dialect, edit, compile, inspect the emitted
WebAssembly, and run — all in the browser. New compilers drop in as plugins.

The unifying idea: every compiler here emits **WAT**, so the run pipeline
(`WAT → wabt assemble → wasm → host imports → run`) is shared. A plugin only
turns *source → WAT* and supplies its *host imports*.

## Run it

```
./compilers/build-c.sh          # build the C compilers to wasm (needs emscripten + ../proto-c)
python3 -m http.server 8000     # any static server; ES modules need http(s), not file://
# open http://localhost:8000/
npm test                        # node smoke test of the compile+run pipeline
```

## In the box (Phase 1)

- **1972 C** — the two modernized Ritchie compilers from `../proto-c`, each
  built to wasm with emscripten:
  - **last1120** (1972, older): no structures; an array name is a *reassignable
    pointer* (B/BCPL semantics).
  - **prestruct** (1973, newer): adds structures; array names *decay* to an
    address (modern C).
  - The signature contrast: the `bsem` example (reassigning an array name)
    compiles under last1120 but is "Lvalue required" under prestruct.

## Layout

```
index.html, app.mjs       the shell (pickers, editor, output, WAT, stdin, About)
core/wat.mjs              WAT -> wasm (wabt, in-browser)
core/run.mjs             instantiate + stdin/stdout + call entry
core/registry.mjs        the plugin list
plugins/c.mjs            the C compilers (both dialects)
plugins/_template.mjs    copy this to add a compiler
compilers/build-c.sh     emcc the C compilers -> compilers/*.wasm (gitignored)
test/smoke.mjs           end-to-end node test
ADDING-A-COMPILER.md     the plugin contract + steps
```

## Adding a compiler

See `ADDING-A-COMPILER.md`. In short: one `plugins/<id>.mjs` implementing
`compile()` + `hostImports()`, one line in `core/registry.mjs`. If it emits WAT,
the shared core already runs it.

## Roadmap

- Phase 2: BCPL plugin (wrap the existing `BCPLwasm/cintcode/site` compiler-in-wasm).
- Phase 3: "About" panels with the lineage narrative (BCPL → last1120 →
  prestruct → modern C), a cross-language example gallery.
