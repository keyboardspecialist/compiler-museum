// Shared WAT -> wasm assembler. Every compiler in the museum emits WAT, so this
// is the one place the text becomes a runnable module. Uses wabt in-browser
// (same lib the BCPL IDE loads). In node (smoke tests) WebAssembly can't parse
// WAT, so a caller may pass pre-assembled bytes instead.

let wabtPromise = null;
function getWabt() {
	if (!wabtPromise)
		wabtPromise = import("https://esm.sh/wabt@1.0.36").then(m => m.default());
	return wabtPromise;
}

// assemble(watText) -> Uint8Array wasm bytes. Throws on a wat syntax error.
export async function assemble(watText) {
	const wabt = await getWabt();
	const mod = wabt.parseWat("module.wat", watText, {
		mutable_globals: true,
		bulk_memory: true,
		sign_extension: true,
	});
	try {
		mod.resolveNames();
		mod.validate();
		const { buffer } = mod.toBinary({ write_debug_names: false });
		return buffer;
	} finally {
		mod.destroy();
	}
}
