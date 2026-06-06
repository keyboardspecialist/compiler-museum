// Waterloo B (1978) support for the museum IDE: the b-waterloo front end built
// to wasm. compileBW() drives cfront-bw over a MEMFS source file and returns the
// emitted WAT. Like b72 it reuses the C runtime (makeCRuntime) -- same getchar/
// putchar/memory ABI -- so the shell's doRunC() runs it unchanged.

let factory = null;
async function bwFactory() {
	if (!factory)
		factory = (await import("./compilers/cfront-bw.mjs")).default;
	return factory;
}

// source -> { wat, diagnostics }
export async function compileBW(source) {
	const make = await bwFactory();
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

// Waterloo B examples. The dialect adds for/repeat/next, modern += assignment,
// && / ||, switch with range cases + default, and f32 #-operators.
export const BW_EXAMPLES = [
	{
		name: "hello",
		source: `/* for loop over a NUL-terminated char vector */
main() {
	auto s 8, i, c;
	s[0] = 'H'; s[1] = 'i'; s[2] = '!'; s[3] = '*n'; s[4] = 0;
	for (i = 0; (c = s[i]) != 0; i += 1)
		putchar(c);
	return(0);
}`,
	},
	{
		name: "loops",
		source: `/* for + += + next(continue): sum 1..10 skipping multiples of 3 */
putn(n) {
	if (n > 9) putn(n / 10);
	putchar(n - n / 10 * 10 + '0');
}
main() {
	auto i, s;
	s = 0;
	for (i = 1; i <= 10; i += 1) {
		if (i % 3 == 0) next;
		s += i;
	}
	putn(s);            /* 1+2+4+5+7+8+10 = 37 */
	putchar('*n');
	return(0);
}`,
	},
	{
		name: "grade",
		source: `/* switch with RANGE cases + default (Waterloo): case lo :: hi : */
grade(n) {
	switch n {
	case 0 :: 59 :  return('F');
	case 60 :: 69 : return('D');
	case 70 :: 79 : return('C');
	case 80 :: 89 : return('B');
	default:        return('A');
	}
}
main() {
	auto i;
	for (i = 50; i <= 100; i += 10) {
		putchar(grade(i));
		putchar(' ');
	}
	putchar('*n');      /* F D C B A A */
	return(0);
}`,
	},
	{
		name: "float",
		source: `/* f32 floats via #-operators (no float type -- a word holds f32 bits) */
main() {
	auto a, b, m;
	a = 3.5;
	b = 6.0;
	m = (a #+ b) #/ 2.0;        /* mean = 4.75 */
	if (m #> 4.5) putchar('Y'); else putchar('N');
	if (m #< 5.0) putchar('Y'); else putchar('N');
	putchar('*n');             /* YY */
	return(0);
}`,
	},
];
