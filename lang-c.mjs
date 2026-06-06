// C language support for the museum IDE: the two modernized 1972 C compilers
// (prestruct + last1120) built to wasm. compileC() drives the chosen dialect's
// compiler over a MEMFS source file and returns the emitted WAT; makeCRuntime()
// matches the BcplRuntime (writeOut, input) contract so the IDE's doRun() sink
// wiring is reused unchanged.

const factories = {};
async function factoryFor(dialect) {
	if (!factories[dialect])
		factories[dialect] = (await import(`./compilers/cfront-${dialect}.mjs`)).default;
	return factories[dialect];
}

// source -> { wat, diagnostics }
export async function compileC(source, dialect = "1120") {
	const factory = await factoryFor(dialect);
	const out = [], err = [];
	const M = await factory({
		print: (s) => out.push(s),
		printErr: (s) => err.push(s),
		noInitialRun: true,
	});
	M.FS.writeFile("/in.c", source);
	try {
		M.callMain(["/in.c"]);
	} catch (e) {
		if (!(e && e.name === "ExitStatus")) err.push(String((e && e.message) || e));
	}
	return { wat: out.join("\n"), diagnostics: err.join("\n") };
}

// A minimal program runtime mirroring BcplRuntime's (writeOut, input) ctor +
// loadProgramFromBytes/run, so doRun() needs no special casing beyond choosing
// this class. Programs get getchar/putchar wired to stdin/output.
export class CRuntime {
	constructor(writeOut, input) {
		this.writeOut = writeOut || (() => {});
		this.input = input || "";
		this.bytes = null;
	}
	async loadProgramFromBytes(bytes) { this.bytes = bytes; }
	setBreakpoints() {}
	setSdlCanvas() {}
	checkEntryOrdering() { return null; }
	async run() {
		const enc = new TextEncoder().encode(this.input);
		let inpos = 0;
		const env = {
			getchar: () => (inpos < enc.length ? enc[inpos++] : 0),
			putchar: (c) => { this.writeOut(String.fromCharCode(c & 0xff)); return c & 0xff; },
			putn: (n) => { this.writeOut(String(n | 0)); return n; },
			exit: (code) => { throw { __exit: code | 0 }; },
		};
		const { instance } = await WebAssembly.instantiate(this.bytes, { env });
		const ex = instance.exports;
		try {
			if (typeof ex.main === "function") return ex.main() | 0;
		} catch (e) {
			if (e && typeof e.__exit === "number") return e.__exit;
			throw e;
		}
		return 0;
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
