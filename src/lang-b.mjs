// B language support for the museum IDE: Ken Thompson's 1972 B compiled to wasm
// by the b72 front end (downstream of last1120-c; same word-machine WAT ABI).
// compileB() drives cfront-b over a MEMFS source file and returns the emitted
// WAT. B reuses the C runtime (makeCRuntime) unchanged -- identical getchar/
// putchar imports and memory export -- so the shell's doRunC() handles it.

let factory = null;
async function bFactory() {
	if (!factory)
		factory = (await import("./compilers/cfront-b.mjs")).default;
	return factory;
}

// source -> { wat, diagnostics }
export async function compileB(source) {
	const make = await bFactory();
	const out = [], err = [];
	const M = await make({
		print: (s) => out.push(s),
		printErr: (s) => err.push(s),
		noInitialRun: true,
	});
	M.FS.writeFile("/in.b", source);
	try {
		M.callMain(["/in.b"]);
	} catch (e) {
		if (!(e && e.name === "ExitStatus")) err.push(String((e && e.message) || e));
	}
	return { wat: out.join("\n"), diagnostics: err.join("\n") };
}

// Library reference shown in the API tab when B (1972) is active.
export const B_API = [
	{ name: "getchar", sig: "getchar()", desc: "Read one byte from stdin; returns 0 at end of input." },
	{ name: "putchar", sig: "putchar(c)", desc: "Write the low byte of c to output; returns c." },
];

// B example programs. B is typeless and pre-K&R: '*n' is the newline escape,
// '=+' is add-assign, switch falls through (no break), vectors are declared
// with a bare size (`auto v 5`) and indexed word-granularly. putchar/getchar
// are taken as extern library calls (wired by the runtime).
export const B_EXAMPLES = [
	{
		name: "hello",
		source: `/* B has no string-print primitive here, so walk a char vector to an
   EOT sentinel ('*e' = 4) and putchar each one. '*n' is newline. */
main() {
	auto s 8, i, c;
	s[0] = 'H'; s[1] = 'i'; s[2] = '!'; s[3] = '*n'; s[4] = 4;
	i = 0;
	while ((c = s[i]) != 4) {
		putchar(c);
		i = i + 1;
	}
	return(0);
}`,
	},
	{
		name: "fact",
		source: `/* recursion + recursive digit printing */
putn(n) {
	if (n > 9) putn(n / 10);
	putchar(n - n / 10 * 10 + '0');
}
fact(n) {
	if (n < 2) return(1);
	return(n * fact(n - 1));
}
main() {
	putn(fact(5));      /* 120 */
	putchar('*n');
	return(0);
}`,
	},
	{
		name: "vector",
		source: `/* B vectors: 'auto a 5' is a reassignable pointer + 5 words of storage.
   Indexing is word-granular; a vector decays to its pointer in a call. */
putn(n) {
	if (n > 9) putn(n / 10);
	putchar(n - n / 10 * 10 + '0');
}
sum(v, n) {
	auto s, i;
	s = 0; i = 0;
	while (i < n) { s = s + v[i]; i = i + 1; }
	return(s);
}
main() {
	auto a 5, i;
	i = 0;
	while (i < 5) { a[i] = i + 1; i = i + 1; }
	putn(sum(a, 5));    /* 15 */
	putchar('*n');
	return(0);
}`,
	},
	{
		name: "switch",
		source: `/* B switch: no parens, and NO break -> cases fall through (faithful to
   pre-ENDCASE BCPL). classify(n) sums one per matched-or-later case:
   1->3, 2->2, 3->1, other->0. '=+' is the old-form add-assign. */
putn(n) {
	if (n > 9) putn(n / 10);
	putchar(n - n / 10 * 10 + '0');
}
classify(n) {
	auto r;
	r = 0;
	switch n {
	case 1:
		r =+ 1;
	case 2:
		r =+ 1;
	case 3:
		r =+ 1;
	}
	return(r);
}
main() {
	putn(classify(1)); putchar(' ');
	putn(classify(2)); putchar(' ');
	putn(classify(3)); putchar('*n');   /* 3 2 1 */
	return(0);
}`,
	},
];
