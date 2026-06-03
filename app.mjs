// Museum shell: wires the language/dialect/example pickers to a plugin's
// compile() and the shared assemble()+run() pipeline.
import { registry, loadPlugin } from "./core/registry.mjs";
import { assemble } from "./core/wat.mjs";
import { run } from "./core/run.mjs";

const $ = (id) => document.getElementById(id);
const els = {
	lang: $("lang"), dialect: $("dialect"), example: $("example"), run: $("run"),
	status: $("status"), src: $("src"), stdin: $("stdin"), out: $("out"),
	wat: $("wat"), diag: $("diag"), about: $("about"), theme: $("theme"),
};

let plugin = null;
let dialect = null;

function setStatus(msg, cls = "") { els.status.textContent = msg; els.status.className = "status " + cls; }

async function selectLang(id) {
	plugin = await loadPlugin(id);
	// dialects
	els.dialect.innerHTML = "";
	const ds = plugin.dialects || [{ id: "", label: plugin.name }];
	for (const d of ds) els.dialect.add(new Option(d.label, d.id));
	els.dialect.style.display = plugin.dialects ? "" : "none";
	dialect = ds[0].id;
	els.about.innerHTML = `<b>${plugin.name}</b> &middot; ${plugin.year} &middot; ${plugin.author} &mdash; ${plugin.blurb} ${plugin.docs || ""}`;
	refreshExamples();
}

function applicableExamples() {
	return (plugin.examples || []).filter((e) => !e.dialect || e.dialect === dialect);
}
function refreshExamples() {
	els.example.innerHTML = "";
	const ex = applicableExamples();
	for (const e of ex) els.example.add(new Option(e.name, e.name));
	if (ex.length) loadExample(ex[0]);
}
function loadExample(e) {
	els.src.value = e.source;
	els.stdin.value = e.stdin || "";
	els.out.textContent = ""; els.wat.textContent = ""; els.diag.textContent = "";
	setStatus("");
}

async function doRun() {
	els.run.disabled = true;
	els.diag.textContent = ""; els.out.className = "";
	setStatus("compiling…");
	try {
		const { wat, diagnostics } = await plugin.compile(els.src.value, { dialect });
		els.wat.textContent = wat || "";
		if (diagnostics) els.diag.textContent = diagnostics;
		if (!wat || !wat.includes("(func")) {
			els.out.textContent = "(no code emitted)";
			els.out.className = "err";
			setStatus("compile errors", "bad");
			return;
		}
		setStatus("assembling…");
		const bytes = await assemble(wat);
		setStatus("running…");
		const { stdout, exit } = await run(bytes, { plugin, stdin: els.stdin.value });
		els.out.textContent = stdout || "(no output)";
		els.out.className = "";
		setStatus(diagnostics ? `ran (exit ${exit}, with warnings)` : `ran (exit ${exit})`,
			diagnostics ? "bad" : "ok");
	} catch (e) {
		els.out.textContent = String(e && e.message || e);
		els.out.className = "err";
		setStatus("error", "bad");
	} finally {
		els.run.disabled = false;
	}
}

// wire events
els.run.onclick = doRun;
els.lang.onchange = () => selectLang(els.lang.value);
els.dialect.onchange = () => { dialect = els.dialect.value; refreshExamples(); };
els.example.onchange = () => {
	const e = applicableExamples().find((x) => x.name === els.example.value);
	if (e) loadExample(e);
};
els.theme.onclick = () => {
	const r = document.documentElement;
	r.dataset.theme = r.dataset.theme === "dark" ? "light" : "dark";
};
els.src.addEventListener("keydown", (e) => {           // tab inserts a tab
	if (e.key === "Tab") {
		e.preventDefault();
		const s = els.src.selectionStart, t = els.src;
		t.value = t.value.slice(0, s) + "\t" + t.value.slice(t.selectionEnd);
		t.selectionStart = t.selectionEnd = s + 1;
	}
});

// boot
for (const r of registry) els.lang.add(new Option(r.id, r.id));
await selectLang(registry[0].id);
