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
];
