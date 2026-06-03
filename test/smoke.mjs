// Smoke test: drive the C plugin (compile in-wasm) + run harness end-to-end in
// node. Assembles WAT with the native wat2wasm (the browser uses core/wat.mjs).
import cPlugin from "../plugins/c.mjs";
import { run } from "../core/run.mjs";
import { execFileSync } from "child_process";
import { writeFileSync, readFileSync } from "fs";

const WAT2WASM = process.env.WAT2WASM || `${process.env.HOME}/tools/wabt-1.0.36/bin/wat2wasm`;
function assembleNative(wat) {
	writeFileSync("/tmp/m.wat", wat);
	execFileSync(WAT2WASM, ["/tmp/m.wat", "-o", "/tmp/m.wasm"]);
	return readFileSync("/tmp/m.wasm");
}

let fails = 0;
const ok = (c, m) => { console.log(`${c ? "ok  " : "FAIL"}  ${m}`); if (!c) fails++; };

async function expectRun(name, dialect, src, stdin, want) {
	try {
		const { wat, diagnostics } = await cPlugin.compile(src, { dialect });
		if (diagnostics) { ok(false, `${name} [${dialect}] compile clean (got: ${diagnostics.split("\n")[0]})`); return; }
		const { stdout } = await run(assembleNative(wat), { plugin: cPlugin, stdin });
		ok(stdout === want, `${name} [${dialect}] -> ${JSON.stringify(stdout)} (want ${JSON.stringify(want)})`);
	} catch (e) { ok(false, `${name} [${dialect}] threw: ${e.message}`); }
}

async function expectReject(name, dialect, src, re) {
	const { diagnostics } = await cPlugin.compile(src, { dialect });
	ok(re.test(diagnostics), `${name} [${dialect}] rejected by ${re} (got: ${diagnostics.split("\n")[0] || "none"})`);
}

const byName = Object.fromEntries(cPlugin.examples.map((e) => [e.name.split(" ")[0], e]));

await expectRun("hello", "1120", byName.hello.source, "", "hello, museum\n");
await expectRun("hello", "prestruct", byName.hello.source, "", "hello, museum\n");
await expectRun("maxsub", "1120", byName.maxsub.source, "", "6\n");
await expectRun("maxsub", "prestruct", byName.maxsub.source, "", "6\n");
await expectRun("upper", "1120", byName.upper.source, "Hello, Museum!\n", "HELLO, MUSEUM!\n");
await expectRun("bsem", "1120", byName.bsem.source, "", "400\n");
await expectRun("struct", "prestruct", byName.struct.source, "", "12\n");
// the signature contrast: B-style array reassignment is rejected by prestruct
await expectReject("bsem", "prestruct", byName.bsem.source, /Lvalue required/);

console.log(fails ? `\n${fails} FAILED` : "\nall passed");
process.exit(fails ? 1 : 0);
