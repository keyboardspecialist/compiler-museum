# Adding a compiler

The museum runs any compiler that turns source into **WebAssembly text (WAT)**.
The shared core handles everything below the WAT line — assembling (`core/wat.mjs`
via wabt) and running with stdin/stdout (`core/run.mjs`). A plugin supplies two
things: `compile(source) -> WAT` and `hostImports()` (the functions compiled
programs call).

## Steps

1. **Copy the template:** `plugins/_template.mjs` → `plugins/<id>.mjs`. Fill in
   metadata, `examples`, `compile()`, `hostImports()`.
2. **Register it:** add one line to `core/registry.mjs`:
   ```js
   { id: "<id>", load: () => import("../plugins/<id>.mjs") },
   ```
3. **Ship the compiler.** If it's a native compiler, build it to wasm with
   emscripten (see `compilers/build-c.sh` for the C example) and load its
   factory in `compile()`. If it already runs in JS/wasm, call it directly.
4. **Smoke-test:** add cases to `test/smoke.mjs` and run `npm test`
   (compiles in node, assembles with native `wat2wasm`, asserts output).

## The contract

```js
export default {
  id, name, year, author, blurb,        // About-panel metadata
  mode,                                  // editor highlight hint
  dialects: [{id,label}],                // optional sub-variants
  examples: [{name, source, dialect?, stdin?}],
  docs,                                  // optional HTML
  async init(),                          // optional lazy setup
  async compile(source, {dialect}) -> { wat, diagnostics },
  hostImports(io) -> { env: {...} },     // io: getByte(), putByte(b), putStr(s)
  entry = "main",                        // export run() calls
}
```

## How the C plugin does `compile()`

`plugins/c.mjs` loads an emscripten-built compiler (`compilers/cfront-<dialect>.mjs`),
writes the source to MEMFS, `callMain()`s it, and captures stdout (the emitted
WAT) and stderr (`line: message` diagnostics):

```js
const factory = (await import(`../compilers/cfront-${dialect}.mjs`)).default;
const out = [], err = [];
const M = await factory({ print: s => out.push(s), printErr: s => err.push(s), noInitialRun: true });
M.FS.writeFile("/in.c", source);
try { M.callMain(["/in.c"]); } catch (e) { /* emscripten ExitStatus */ }
return { wat: out.join("\n"), diagnostics: err.join("\n") };
```

Any compiler that emits WAT and names its imports `env.*` drops in the same way.
