// Waterloo B (1978) support for the museum IDE: the b-waterloo front end built
// to wasm. compileBW() drives cfront-bw over a MEMFS source file and returns the
// emitted WAT. Programs run under BWRuntime, which adds the B string library as
// memory-aware wasm imports (char/lchar/putstr/getstr) on top of getchar/putchar.

let factory = null;
async function bwFactory() {
	if (!factory)
		factory = (await import("./compilers/cfront-bw.mjs")).default;
	return factory;
}

// source -> { wat, diagnostics }. `files` (optional) are the other workspace
// files, written to MEMFS so `%filename` inclusion can resolve them.
export async function compileBW(source, files) {
	const make = await bwFactory();
	const out = [], err = [];
	const M = await make({
		print: (s) => out.push(s),
		printErr: (s) => err.push(s),
		noInitialRun: true,
	});
	M.FS.writeFile("/in.b", source);
	if (Array.isArray(files))
		for (const f of files)
			try { M.FS.writeFile("/" + f.name, f.content); } catch (e) { /* skip */ }
	try {
		M.callMain(["/in.b"]);
	} catch (e) {
		if (!(e && e.name === "ExitStatus")) err.push(String((e && e.message) || e));
	}
	return { wat: out.join("\n"), diagnostics: err.join("\n") };
}

// Program runtime for Waterloo B. Like CRuntime (writeOut, input) but the env
// adds the B string library. B strings/vectors are word-index pointers, so the
// byte address of word-pointer `w` is w*4; strings are NUL-terminated, packed
// one char per byte.
export class BWRuntime {
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
		let inst = null;
		const mem = () => new Uint8Array(inst.exports.memory.buffer);
		const byte = (w) => (w >>> 0) * 4;	// word-index pointer -> byte address
		const env = {
			getchar: () => (inpos < enc.length ? enc[inpos++] : 0),
			putchar: (c) => { this.writeOut(String.fromCharCode(c & 0xff)); return c & 0xff; },
			putn: (n) => { this.writeOut(String(n | 0)); return n | 0; },
			// i-th character of the string at word-pointer s
			char: (s, i) => mem()[byte(s) + (i | 0)],
			// store character c as the i-th character of s; returns c
			lchar: (s, i, c) => { mem()[byte(s) + (i | 0)] = c & 0xff; return c & 0xff; },
			// write the NUL-terminated string at s to output
			putstr: (s) => {
				const m = mem(); let a = byte(s), out = "";
				while (m[a] !== 0) out += String.fromCharCode(m[a++]);
				this.writeOut(out); return 0;
			},
			// read one input line into the buffer at s (NUL-terminated); returns s
			getstr: (s) => {
				const m = mem(); let a = byte(s);
				while (inpos < enc.length) {
					const ch = enc[inpos++];
					if (ch === 10) break;
					m[a++] = ch;
				}
				m[a] = 0; return s;
			},
			// printf(fmt, argbuf, argc): the compiler marshals the variadic args
			// into the word-indexed buffer argbuf; walk the format pulling them.
			printf: (fmt, argbuf, argc) => {
				const rdword = (wi) => { const mm = mem(); const a = (wi >>> 0) * 4; return mm[a] | (mm[a + 1] << 8) | (mm[a + 2] << 16) | (mm[a + 3] << 24); };
				const rdstr = (wi) => { const mm = mem(); let a = (wi >>> 0) * 4, s = ""; while (mm[a]) s += String.fromCharCode(mm[a++]); return s; };
				const mm = mem();
				let a = byte(fmt), out = "", ai = 0;
				const nextarg = () => rdword((argbuf >>> 0) + ai++);
				while (mm[a] !== 0) {
					const c = mm[a++];
					if (c === 37 /* % */) {
						const f = mm[a++];
						if (f === 100 /* d */) out += String(nextarg() | 0);
						else if (f === 99 /* c */) out += String.fromCharCode(nextarg() & 0xff);
						else if (f === 111 /* o */) out += (nextarg() >>> 0).toString(8);
						else if (f === 115 /* s */) out += rdstr(nextarg());
						else if (f === 37) out += "%";
						else out += "%" + String.fromCharCode(f);
					} else out += String.fromCharCode(c);
				}
				this.writeOut(out); return 0;
			},
			exit: (code) => { throw { __exit: code | 0 }; },
		};
		const { instance } = await WebAssembly.instantiate(this.bytes, { env });
		inst = instance;
		try {
			if (typeof instance.exports.main === "function") return instance.exports.main() | 0;
		} catch (e) {
			if (e && typeof e.__exit === "number") return e.__exit;
			throw e;
		}
		return 0;
	}
}
export function makeBWRuntime(writeOut, input) { return new BWRuntime(writeOut, input); }

// Library reference shown in the API tab when Waterloo B is active. These are
// provided by BWRuntime as memory-aware host imports.
export const BW_API = [
	{ name: "getchar", sig: "getchar()", desc: "Read one byte from stdin; returns 0 at end of input." },
	{ name: "putchar", sig: "putchar(c)", desc: "Write the low byte of c to output; returns c." },
	{ name: "char", sig: "char(s, i)", desc: "Return the i-th character of the string at word-pointer s." },
	{ name: "lchar", sig: "lchar(s, i, c)", desc: "Store character c as the i-th character of s; returns c." },
	{ name: "putstr", sig: "putstr(s)", desc: "Write the NUL-terminated string at s to output." },
	{ name: "getstr", sig: "getstr(s)", desc: "Read one input line into the buffer at s (NUL-terminated); returns s." },
	{ name: "printf", sig: "printf(fmt, ...)", desc: "Formatted output: %d decimal, %c char, %s string, %o octal." },
];

// Waterloo B examples. The dialect adds for/repeat/next, modern += assignment,
// && / ||, switch with range cases + default, f32 #-operators, and (below) the
// string library.
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
	{
		name: "puts",
		source: `/* the B string library: putstr writes a NUL-terminated string */
main() {
	extrn putstr;
	putstr("hello, museum*n");
	return(0);
}`,
	},
	{
		name: "upcase",
		stdin: "hello, waterloo\n",
		source: `/* char / lchar / getstr / putstr: read a line, upper-case it in place.
   Type into the stdin box. */
main() {
	auto buf 32, i, c;
	extrn getstr, putstr, char, lchar;
	getstr(buf);
	for (i = 0; (c = char(buf, i)) != 0; i += 1)
		if (c >= 'a' && c <= 'z')
			lchar(buf, i, c - 32);
	putstr(buf);
	putchar('*n');
	return(0);
}`,
	},
	{
		name: "printf",
		source: `/* printf: %d %c %s %o. The compiler marshals the variadic args into a
   buffer and the host walks the format string. */
main() {
	extrn printf;
	auto i;
	for (i = 1; i <= 5; i += 1)
		printf("%d squared is %d*n", i, i * i);
	return(0);
}`,
	},
	{
		name: "manifest",
		source: `/* manifest constants: compile-time textual macros (name = text;),
   substituted before parsing. SIZE sets the vector size; SQ nests it. */
SIZE = 5;
SQ = SIZE * SIZE;
main() {
	extrn printf;
	auto v SIZE, i, s;
	for (i = 0; i < SIZE; i += 1) v[i] = i + 1;
	s = 0;
	for (i = 0; i < SIZE; i += 1) s += v[i];
	printf("sum 1..%d = %d (SQ=%d)*n", SIZE, s, SQ);
	return(0);
}`,
	},
];
