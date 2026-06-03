// C plugin: the two modernized 1972 C compilers (prestruct + last1120), each
// compiled to wasm and run client-side. compile() drives the chosen dialect's
// compiler over a MEMFS source file and captures the emitted WAT.

const factories = {};            // dialect -> emscripten module factory (cached)
async function factoryFor(dialect) {
	if (!factories[dialect])
		factories[dialect] = (await import(`../compilers/cfront-${dialect}.mjs`)).default;
	return factories[dialect];
}

const EX = {
	hello: `/* write a string, char by char */
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

	maxsub: `/* Maximum Subarray (Kadane). Build a sample, print the answer. */
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

	upper: `/* read stdin, echo upper-cased, until EOF. type into the stdin box. */
main() {
	auto c;
	while ((c = getchar()) > 0) {
		if (c >= 'a') if (c <= 'z') c =- 32;
		putchar(c);
	}
	return(0);
}`,

	// B/BCPL reassignable array pointer -- compiles under 1120, "Lvalue
	// required" under prestruct. The museum's signature contrast.
	bsem: `/* an array name is a reassignable pointer (B/BCPL semantics) */
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

	struct: `/* structures (prestruct only): members at fixed offsets */
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
};

export default {
	id: "c",
	name: "1972 C",
	year: 1972,
	author: "D. M. Ritchie",
	blurb: "The C compiler in two states: last1120 (older, B/BCPL array semantics) and prestruct (just before structures). Modernized to portable C89, emitting WebAssembly.",
	mode: "c",
	entry: "main",

	dialects: [
		{ id: "1120", label: "last1120 · 1972 (older)" },
		{ id: "prestruct", label: "prestruct · 1973 (newer)" },
	],

	examples: [
		{ name: "hello", source: EX.hello },
		{ name: "maxsub (Kadane)", source: EX.maxsub },
		{ name: "upper (reads stdin)", source: EX.upper, stdin: "Hello, Museum!\n" },
		{ name: "bsem (reassignable array)", source: EX.bsem, dialect: "1120" },
		{ name: "struct", source: EX.struct, dialect: "prestruct" },
	],

	docs: `<p><b>last1120</b> is the last PDP-11/20 C compiler — no structures,
		and an array name is a <i>reassignable pointer</i> to its storage (B/BCPL
		semantics). <b>prestruct</b> came just after: it added structures, which
		required switching array names to <i>inline storage that decays to an
		address</i> (modern C). So <code>z = z + 2</code> on an array compiles
		under 1120 but is "Lvalue required" under prestruct — try the
		<i>bsem</i> example in both dialects.</p>
		<p>Both were ported to portable C89 and given a WebAssembly backend
		(structured control, linear-memory frames). Undefined functions like
		<code>getchar</code>/<code>putchar</code> become wasm imports the host
		supplies.</p>`,

	async compile(source, opts = {}) {
		const dialect = opts.dialect || "1120";
		const factory = await factoryFor(dialect);
		const out = [], err = [];
		const M = await factory({ print: (s) => out.push(s), printErr: (s) => err.push(s), noInitialRun: true });
		M.FS.writeFile("/in.c", source);
		try {
			M.callMain(["/in.c"]);
		} catch (e) {
			if (!(e && e.name === "ExitStatus")) err.push(String(e && e.message || e));
		}
		return { wat: out.join("\n"), diagnostics: err.join("\n") };
	},

	hostImports(io) {
		return {
			env: {
				getchar: () => io.getByte(),
				putchar: (c) => { io.putByte(c); return c & 0xff; },
				putn: (n) => { io.putStr(String(n | 0)); return n; },
				exit: (code) => { throw { __exit: code | 0 }; },
			},
		};
	},
};
