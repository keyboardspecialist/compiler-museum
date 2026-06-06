# BCPL → WebAssembly Playground

Static site that runs BCPL programs compiled to WebAssembly by the
new `bcplwasm` backend (`com/bcplcgwasm.b`). The compiler emits
WebAssembly Text Format (`.wat`); `wat2wasm` assembles to `.wasm`;
`runtime.js` loads the module with a host-provided BCPL stdlib and
executes.

## Layout

```
site/
  index.html       — UI: example dropdown, source/output panes,
                     collapsible WAT pane, stdin textarea
  runtime.js       — BcplRuntime class: stdlib imports, memory access,
                     string/vec helpers, loader
  build.sh         — recompile each examples/*.b via cintsys + wat2wasm
  examples/
    hello.b        — writef
    fact.b         — recursion, FOR
    nested.b       — nested function definitions (hoisted)
    valof.b        — VALOF/RESULTIS nesting
    bitfield.b     — SLCT / OF field load and store
    cgoto.b        — computed GOTO via LF of local label
    fmod.b         — FLT (#MOD, #:=), %f format
    shifts.b       — logical >>, <<, hex format
    vec.b          — getvec / freevec
    echo.b         — rdch, reads from stdin pane
    match.b        — MATCH expression (MCPL pattern matching)
    every.b        — EVERY expression (sum of all matching arms)
    stdlib.b       — muldiv, randno, capitalch, compch, compstring, %z
    streams.b      — findoutput/findinput round-trip via localStorage
    *.wat, *.wasm  — built artifacts
```

## Running locally

Any static web server works. Example:

```bash
cd site
python3 -m http.server 8000
# open http://localhost:8000/
```

ES module imports mean you need a real server — opening `index.html`
as `file://` will not work.

## Rebuilding examples

Requires `cintsys` with `bcplwasm` compiled into `cin/`, and
`wat2wasm` from the [WABT](https://github.com/WebAssembly/wabt) tools
on `PATH` (or set `WAT2WASM=/path/to/wat2wasm`).

```bash
./build.sh
```

Each `examples/<name>.b` yields `<name>.wat` and `<name>.wasm`.

## Bootstrap from a fresh clone

The `cin/` directory is gitignored (Cintcode is a build artifact).
One-time steps after cloning:

```bash
cd cintcode
make                                               # builds bin/cintsys
export BCPLROOT=$PWD  BCPLPATH=$PWD/cin \
       BCPLHDRS=$PWD/g  BCPLSCRIPTS=$PWD/s
export PATH=$PATH:$PWD/bin
echo "bcpl com/bcplwasm.b to cin/bcplwasm" | bin/cintsys   # build the backend
./site/build.sh                                     # build all examples
```

Then `./bcpl2wasm.sh my.b` compiles a single file end-to-end.

## Adding an example

1. Drop `foo.b` in `examples/`.
2. Add `<option value="foo">foo</option>` to the `<select>` in
   `index.html`.
3. Re-run `./build.sh`.

## Runtime API

`runtime.js` exports one class:

```js
import { BcplRuntime } from "./runtime.js";

const rt = new BcplRuntime(
  (s) => process.stdout.write(s),   // writeOut — receives all output
  "input text\n"                     // stdin — consumed by rdch()
);
await rt.load("examples/hello.wasm");
rt.run();                            // calls fn_L10 (the start function)
```

### Host-imported stdlib

| Global | Function | Notes |
|--------|----------|-------|
|  2 | `stop(n)`       | halts, throws `BcplHalt` |
|  5 | `muldiv(a,b,c)` | `(a*b)/c` with 64-bit intermediate |
| 25 | `getvec(n)`     | n+1 word block, 0 on OOM |
| 27 | `freevec(p)`    | links block to free list |
| 28 | `abort(n)`      | halts with `BcplHalt.isAbort = true` |
| 34 | `randno(n)`     | random int in `[1..n]` |
| 38 | `rdch()`        | next stdin char, −1 at EOF |
| 41 | `wrch(c)`       | write one char |
| 84 | `newline()`     | write `\n` |
| 86 | `writen(n)`     | signed decimal |
| 89 | `writes(s)`     | BCPL string |
| 94 | `writef(fmt, a, b, c, d)` | formatted write |
| 96 | `capitalch(c)`  | uppercase a-z |
| 97 | `compch(a,b)`   | case-insensitive compare, −1/0/+1 |
| 98 | `compstring(s1,s2)` | BCPL string compare, −1/0/+1 |
| 48 | `findinput(name)`   | open named read stream (browser storage) |
| 49 | `findoutput(name)`  | open named write stream |
| 56 | `selectinput(h)`    | switch current input stream, returns previous |
| 57 | `selectoutput(h)`   | switch current output stream, returns previous |
| 60 | `endread()`         | close current input stream |
| 61 | `endwrite()`        | close current output stream (commits to storage) |
| 62 | `endstream(h)`      | close a specific stream handle |

Named streams are backed by `localStorage` under keys `bcpl:<name>`. They persist across page reloads. In Node (tests), an in-memory `Map` is used instead.

`writef` format codes: `%n`, `%d`, `%i`, `%u`, `%c`, `%s`, `%x`, `%o`, `%b`, `%z` (zero-padded decimal), `%t` (string, left-justified), `%f`, `%e`, `%g`. BCPL's two width conventions both work: `%i4`/`%X8` (single-char width after code) and `%5.2f`/`%8.3e` (width.precision before code).

## Calling convention

See `../CLAUDE.md` (section "WebAssembly Backend") for the full memory
layout, calling convention, and function-table layout. Short version:

- All expression-stack slots and memory are `i32`. Float ops use
  `i32.reinterpret_f32` / `f32.reinterpret_i32` bit casts.
- Callers store args at `P!(k+3..)`, save `(old_P, 0, fn_idx)` at
  `P!(k..k+2)`, advance `$P` by `k`, `call_indirect`.
- Callee reads args at `P!3..`, restores `$P` from `P!0` on return.
- Every function body is one `(loop $__dispatch (if …) …)` dispatched
  on `$__lab`.

## Deploying to GitHub Pages

The `site/` directory is self-contained — push it to a repo, enable
GitHub Pages pointing at that directory, done. The committed
`.wat`/`.wasm` artifacts are loaded directly; no build step runs in
CI.
