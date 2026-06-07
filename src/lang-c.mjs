// C language support for the museum IDE: the two modernized 1972 C compilers
// (prestruct + last1120) built to wasm. compileC() drives the chosen dialect's
// compiler over a MEMFS source file and returns the emitted WAT; makeCRuntime()
// matches the BcplRuntime (writeOut, input) contract so the IDE's doRun() sink
// wiring is reused unchanged.

// Cache-bust the compiler module + its wasm per session, so a redeploy's fresh
// cfront-*.{mjs,wasm} aren't served stale from the browser cache.
export const V = Date.now();
const factories = {};
async function factoryFor(dialect) {
	if (!factories[dialect])
		factories[dialect] = (await import(`./compilers/cfront-${dialect}.mjs?v=${V}`)).default;
	return factories[dialect];
}
// emscripten Module options that version the .wasm fetch. locateFile gets
// (path, scriptDir); keep scriptDir (the /compilers/ prefix) and append a
// cache-bust so a redeploy's fresh .wasm isn't served stale.
export const wasmOpts = { locateFile: (p, d) => (/\.wasm$/.test(p) ? `${d}${p}?v=${V}` : `${d}${p}`) };

// Strip the compiler's `;;#dbg {json}` lines (emitted under -g) out of the WAT
// and parse them into a per-function frame-variable map for the debugger.
export function extractDbgMap(wat) {
	const map = {};
	const kept = [];
	for (const line of wat.split("\n")) {
		const m = line.match(/^;;#dbg\s+(.*)$/);
		if (m) {
			try { const d = JSON.parse(m[1]); map[d.fn] = { ln: d.ln, vars: d.vars }; }
			catch (e) { /* ignore a malformed map line */ }
		} else {
			kept.push(line);
		}
	}
	return { wat: kept.join("\n"), dbgMap: map };
}

// source -> { wat, diagnostics, dbgMap }. Pass dbg=true to compile with -g
// (per-statement breakpoint hooks + the frame-variable map).
export async function compileC(source, dialect = "1120", dbg = false) {
	const factory = await factoryFor(dialect);
	const out = [], err = [];
	const M = await factory({
		print: (s) => out.push(s),
		printErr: (s) => err.push(s),
		noInitialRun: true,
		...wasmOpts,
	});
	M.FS.writeFile("/in.c", source);
	try {
		M.callMain(dbg ? ["-g", "/in.c"] : ["/in.c"]);
	} catch (e) {
		if (!(e && e.name === "ExitStatus")) err.push(String((e && e.message) || e));
	}
	const { wat, dbgMap } = extractDbgMap(out.join("\n"));
	return { wat, diagnostics: err.join("\n"), dbgMap };
}

// A program runtime mirroring BcplRuntime's (writeOut, input) ctor +
// loadProgramFromBytes/run/setBreakpoints/resume/step/etc., so the IDE's
// debugger UI drives C/B exactly like BCPL. Programs get getchar/putchar wired
// to stdin/output. When the module is a debug build (asyncified, with a
// $__break import), run() drives an asyncify unwind/rewind loop to pause at
// breakpoints; otherwise main() runs straight through.
export class CRuntime {
	constructor(writeOut, input) {
		this.writeOut = writeOut || (() => {});
		this.input = input || "";
		this.bytes = null;
		this.instance = null;
		this._breakpoints = new Set();
		this._stepMode = false;
		this._stepOverLine = 0;
		this._asyncifyMode = "normal";	// normal | unwinding | rewinding
		this._asyncData = 0;
		this._pausePromise = null;
		this._pauseResolve = null;
		this._pausedLine = 0;
		this._curFp = 0;
		this.aborted = false;
		this.onPause = null;
		this.onResume = null;
		this.dbgMap = null;		// { fnName: {ln, vars:[{n,o,t,s}]} } from compile
	}
	async loadProgramFromBytes(bytes) { this.bytes = bytes; }
	setSdlCanvas() {}
	checkEntryOrdering() { return null; }

	// Subclasses add their own imports (e.g. the Waterloo string library).
	_extraEnv(env, mem) { /* overridden by BWRuntime */ }

	async run() {
		this._inEnc = new TextEncoder().encode(this.input);
		this._inPos = 0;
		const self = this;
		const env = {
			getchar: () => (self._inPos < self._inEnc.length ? self._inEnc[self._inPos++] : 0),
			putchar: (c) => { self.writeOut(String.fromCharCode(c & 0xff)); return c & 0xff; },
			putn: (n) => { self.writeOut(String(n | 0)); return n | 0; },
			exit: (code) => { throw { __exit: code | 0 }; },
			__break: (line, fp) => self._impBreak(line, fp),
		};
		this._extraEnv(env, () => this._mem());
		const { instance } = await WebAssembly.instantiate(this.bytes, { env });
		this.instance = instance;
		const ex = instance.exports;
		// Debug build? Reserve a fresh page for the asyncify unwind stack.
		if (typeof ex.asyncify_start_unwind === "function") {
			if (ex.memory.buffer.byteLength <= 131072) ex.memory.grow(1);
			this._asyncData = 131072;	// the grown page (shadow stack descends from here)
			this._resetAsyncify();
			this._syncBpArmed();
		}
		try {
			if (typeof ex.main !== "function") return 0;
			let r = ex.main() | 0;
			while (this._asyncifyMode === "unwinding") {
				ex.asyncify_stop_unwind();
				this._asyncifyMode = "normal";
				if (this._pausePromise) await this._pausePromise;
				if (this.aborted) return 0;
				ex.asyncify_start_rewind(this._asyncData);
				this._asyncifyMode = "rewinding";
				r = ex.main() | 0;	// rewinds to the paused $__break, continues
			}
			return r;
		} catch (e) {
			if (e && typeof e.__exit === "number") return e.__exit;
			throw e;
		}
	}

	// --- asyncify state buffer (8-byte header {data_start, data_end} + spill) ---
	_resetAsyncify() {
		const words = 256, base = this._asyncData;
		const dv = this._mem();
		dv.setUint32(base, base + 8, true);
		dv.setUint32(base + 4, base + words * 4, true);
	}
	_mem() { return new DataView(this.instance.exports.memory.buffer); }

	// The $__break hook: pause on an armed breakpoint or while stepping.
	_impBreak(line, fp) {
		const ex = this.instance.exports;
		if (this._asyncifyMode === "rewinding") {	// replaying to the pause point
			ex.asyncify_stop_rewind();
			this._asyncifyMode = "normal";
			return;
		}
		const haveBps = this._breakpoints.size > 0;
		if (!haveBps && !this._stepMode) return;
		if (!line) return;
		if (this._stepOverLine === line) return;
		const inBp = haveBps && this._breakpoints.has(line);
		if (!this._stepMode && !inBp) return;
		if (this._stepMode) { this._stepMode = false; this._syncBpArmed(); }
		this._curFp = fp | 0;
		this._resetAsyncify();
		this._pausedLine = line;
		this._pausePromise = new Promise((r) => { this._pauseResolve = r; });
		ex.asyncify_start_unwind(this._asyncData);
		this._asyncifyMode = "unwinding";
		if (this.onPause) this.onPause(line);
	}

	resume({ stepOver = false } = {}) {
		if (!this._pauseResolve) return false;
		this._stepOverLine = stepOver ? this._pausedLine : 0;
		const r = this._pauseResolve;
		this._pauseResolve = null; this._pausePromise = null; this._pausedLine = 0;
		if (this.onResume) this.onResume();
		r();
		return true;
	}
	step() {
		if (!this._pauseResolve) return false;
		this._stepMode = true;
		this._stepOverLine = this._pausedLine;
		this._syncBpArmed();
		const r = this._pauseResolve;
		this._pauseResolve = null; this._pausePromise = null; this._pausedLine = 0;
		if (this.onResume) this.onResume();
		r();
		return true;
	}
	setBreakpoints(lines) {
		this._breakpoints = new Set();
		for (const n of (lines || [])) this._breakpoints.add(n | 0);
		this._stepOverLine = 0;
		this._syncBpArmed();
	}
	_syncBpArmed() {
		const g = this.instance && this.instance.exports.__bp_armed;
		if (!g) return;
		g.value = (this._breakpoints.size > 0 || this._stepMode) ? 1 : 0;
	}
	isPaused() { return this._pausePromise != null; }
	pausedLine() { return this._pausedLine | 0; }
	currentLine() {
		const g = this.instance && this.instance.exports.__line;
		return g ? (g.value | 0) : 0;
	}
	abort() {
		this.aborted = true;
		if (this._pauseResolve) { const r = this._pauseResolve; this._pauseResolve = null; this._pausePromise = null; r(); }
	}

	// --- memory inspection (memory pane + Locals view) ---
	readWords(startWord, count) {
		const dv = this._mem(), out = [];
		for (let i = 0; i < count; i++) out.push(dv.getInt32((startWord + i) * 4, true));
		return out;
	}
	memLayout() {
		const buf = this.instance ? this.instance.exports.memory.buffer : null;
		return { fp: this._curFp | 0, line: this.currentLine(),
			memBytes: buf ? buf.byteLength : 0, globalsBase: 16, shadowStackBase: 131072 };
	}
	// Locals at the paused frame: pick the function whose entry line is the
	// greatest <= the paused line, read each var at fp+offset.
	localsAt(line) {
		if (!this.dbgMap || !this._curFp) return [];
		let best = null;
		for (const fn of Object.values(this.dbgMap))
			if (fn.ln <= line && (!best || fn.ln > best.ln)) best = fn;
		if (!best) return [];
		const dv = this._mem();
		return best.vars.map((v) => ({
			name: v.n,
			value: dv.getInt32(((this._curFp + v.o) >> 2) * 4, true),
			off: v.o, type: v.t,
		}));
	}
}
export function makeCRuntime(writeOut, input) { return new CRuntime(writeOut, input); }

// C example programs (period-correct dialect). `dialect` restricts an example;
// `stdin` seeds the stdin box.
export const C_EXAMPLES = [
	{
		name: "hello",
		source: `/* write a string, char by char */
puts(s) char s[]; {
	auto c;
	while (c = *s++)
		putchar(c);
}
main() {
	puts("hello, museum");
	putchar('\\n');
	return(0);
}`,
	},
	{
		name: "maxsub",
		source: `/* Maximum Subarray (Kadane). Build a sample, print the answer. */
putn(n) {
	if (n < 0) { putchar('-'); n = -n; }
	if (n > 9) putn(n / 10);
	putchar(n - n / 10 * 10 + '0');
}
maxsub(a, n) int a[]; {
	auto best, cur, i, x;
	best = a[0]; cur = a[0]; i = 1;
	while (i < n) {
		x = a[i];
		cur =+ x;
		if (cur < x) cur = x;
		if (cur > best) best = cur;
		i =+ 1;
	}
	return(best);
}
main() {
	int v[9];
	v[0]=-2; v[1]=1; v[2]=-3; v[3]=4; v[4]=-1; v[5]=2; v[6]=1; v[7]=-5; v[8]=4;
	putn(maxsub(&v[0], 9));   /* -> 6 */
	putchar('\\n');
	return(0);
}`,
	},
	{
		name: "upper (reads stdin)",
		stdin: "Hello, Museum!\n",
		source: `/* read stdin, echo upper-cased, until EOF. type into the stdin box. */
main() {
	auto c;
	while ((c = getchar()) > 0) {
		if (c >= 'a') if (c <= 'z') c =- 32;
		putchar(c);
	}
	return(0);
}`,
	},
	{
		name: "bsem (reassignable array)",
		dialect: "1120",
		source: `/* B/BCPL: an array name is a reassignable pointer.
   Compiles under last1120; "Lvalue required" under prestruct. */
putn(n) { if (n > 9) putn(n / 10); putchar(n - n / 10 * 10 + '0'); }
bsem() {
	int z[3];
	int save[];
	int moved;
	save = z;
	z[0] = 100; z[1] = 200; z[2] = 300;
	z = z + 2;          /* reassign the array name */
	moved = z[0];       /* original z[2] = 300 */
	z = save;
	return(moved + z[0]);   /* 300 + 100 = 400 */
}
main() { putn(bsem()); putchar('\\n'); return(0); }`,
	},
	{
		name: "struct",
		dialect: "prestruct",
		source: `/* structures (prestruct only): members at fixed offsets */
putn(n) { if (n > 9) putn(n / 10); putchar(n - n / 10 * 10 + '0'); }
struct pt ( int x; int y; );
main() {
	struct pt p;
	p.x = 5;
	p.y = 7;
	putn(p.x + p.y);    /* 12 */
	putchar('\\n');
	return(0);
}`,
	},
];

// Library reference shown in the API tab when C is the active language. The C
// programs call getchar/putchar as host imports (wired by CRuntime).
export const C_API = [
	{ name: "getchar", sig: "getchar()", desc: "Read one byte from stdin; returns 0 at end of input." },
	{ name: "putchar", sig: "putchar(c)", desc: "Write the low byte of c to output; returns c." },
];

export function cExamplesFor(dialect) {
	return C_EXAMPLES.filter((e) => !e.dialect || e.dialect === dialect);
}
