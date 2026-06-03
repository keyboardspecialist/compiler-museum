// Template for a new compiler plugin. Copy to plugins/<id>.mjs, fill in, and
// add `{ id: "<id>", load: () => import("../plugins/<id>.mjs") }` to
// core/registry.mjs. See ADDING-A-COMPILER.md.
//
// The museum runs any compiler that turns source into WAT. You implement
// compile() (source -> WAT text) and hostImports() (the functions your
// compiled programs import). The shared core (core/wat.mjs, core/run.mjs)
// assembles and runs the result.

export default {
	id: "mylang",                    // unique, matches the file name
	name: "My Language",
	year: 1970,
	author: "Someone",
	blurb: "One sentence shown in the About panel.",
	mode: "text",                    // editor highlight hint (advisory)
	entry: "main",                   // export the run harness calls

	// Optional sub-dialects sharing one plugin (omit if none).
	dialects: [{ id: "v1", label: "version 1" }],

	// Examples. `dialect` restricts an example to one dialect; `stdin` seeds
	// the stdin box. Sources can also be fetched in init() if you prefer.
	examples: [
		{ name: "hello", source: `...source...`, stdin: "" },
	],

	docs: `<p>Optional HTML shown under the blurb in the About panel.</p>`,

	// Lazy one-time setup (load your compiler wasm, etc.). Optional.
	async init() {},

	// source -> { wat: string, diagnostics: string }. Run your compiler here.
	// For an emscripten-built compiler: factory({print,printErr}), write the
	// source to MEMFS, callMain([...]), collect stdout (WAT) and stderr.
	async compile(source, opts = {}) {
		return { wat: "(module)", diagnostics: "" };
	},

	// The imports your compiled programs reference. `io` gives you
	// getByte()/putByte(b)/putStr(s) wired to the shell's stdin/stdout.
	hostImports(io) {
		return {
			env: {
				getchar: () => io.getByte(),
				putchar: (c) => { io.putByte(c); return c & 0xff; },
			},
		};
	},
};
