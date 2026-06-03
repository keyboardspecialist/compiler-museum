// Language-agnostic run harness: instantiate a wasm module with the plugin's
// host imports, feed stdin, capture stdout, call the entry export. Works in
// both the browser and node.

export async function run(wasmBytes, { plugin, entry, stdin = "" } = {}) {
	const inBytes =
		typeof stdin === "string" ? new TextEncoder().encode(stdin) : (stdin || new Uint8Array());
	let inpos = 0;
	const out = [];

	// io primitives every plugin's hostImports() builds on
	const io = {
		getByte: () => (inpos < inBytes.length ? inBytes[inpos++] : 0),
		putByte: (b) => out.push(b & 0xff),
		putStr: (s) => { for (const ch of s) out.push(ch.charCodeAt(0) & 0xff); },
	};

	const imports = plugin && plugin.hostImports ? plugin.hostImports(io) : { env: {} };
	const { instance } = await WebAssembly.instantiate(wasmBytes, imports);
	const ex = instance.exports;

	const fn = entry || (plugin && plugin.entry) || "main";
	let rc = 0;
	if (typeof ex[fn] !== "function") throw new Error(`no export '${fn}' to run`);
	try {
		rc = ex[fn]() | 0;
	} catch (e) {
		if (e && typeof e.__exit === "number") rc = e.__exit;   // program called exit()
		else throw e;
	}

	return {
		stdout: new TextDecoder().decode(new Uint8Array(out)),
		exit: rc & 0xff,
		exports: ex,
	};
}
