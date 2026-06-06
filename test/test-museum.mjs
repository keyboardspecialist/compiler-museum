// Headless E2E for the museum: BCPL regression + the language switcher
// (top-bar #langSelect re-scopes Files/Examples/API), per-dialect compile/run,
// and syntax highlighting. Needs a static server on :8733 (wabt is vendored).
import { chromium } from "playwright";

const URL = "http://localhost:8733/";
let fails = 0;
const ok = (c, m) => { console.log(`${c ? "ok  " : "FAIL"}  ${m}`); if (!c) fails++; };

const browser = await chromium.launch();
const page = await browser.newPage();
const errs = [];
page.on("pageerror", (e) => errs.push("pageerror: " + e.message));
await page.goto(URL, { waitUntil: "networkidle" });

async function outText() { return (await page.locator("#output").textContent()) || ""; }
async function waitOut(s, ms = 30000) {
	await page.waitForFunction((x) => (document.getElementById("output").textContent || "").includes(x), s, { timeout: ms });
}
async function clearAndRun() {
	await page.evaluate(() => { document.getElementById("output").textContent = ""; });
	await page.click("#compileRun");
}
async function selectLang(lang) {            // top-bar language switcher
	await page.selectOption("#langSelect", lang);
	await page.waitForTimeout(100);
}
async function addExample(name, lang) {      // examples are scoped to the language
	await selectLang(lang);
	await page.click('#leftTabs button[data-tab="examples"]');
	await page.locator("#exampleList li", { hasText: name }).last().getByRole("button").click();
	await page.waitForTimeout(150);
}
async function starFile(fname) {             // file's group is expanded (its lang is active)
	await page.click('#leftTabs button[data-tab="files"]');
	await page.locator("#fileList li", { hasText: fname }).locator(".entry-star").click();
	await page.waitForTimeout(100);
}

// 1. BCPL still works + debug visible; language selector defaults to BCPL
try {
	ok((await page.locator("#langSelect").inputValue()) === "bcpl", "#langSelect defaults to bcpl");
	await clearAndRun();
	await waitOut("hello from self-hosted bcplwasm");
	const dbgVisible = await page.locator("#dbgMode").isVisible();
	const dialectHidden = !(await page.locator("#cDialect").isVisible());
	ok(true, "BCPL default runs (regression)");
	ok(dbgVisible && dialectHidden, "BCPL entry: debug shown, C-dialect hidden");
} catch (e) { ok(false, "BCPL default: " + e.message); }

// 2. C: add maxsub.c (auto-switches to C), star, run
try {
	await addExample("maxsub", "c");
	const inPane = await page.locator("#fileList li", { hasText: "maxsub.c" }).count();
	ok(inPane === 1, "maxsub.c added to files pane");
	await starFile("maxsub.c");
	const dialectShown = await page.locator("#cDialect").isVisible();
	const dbgHidden = !(await page.locator("#dbgMode").isVisible());
	const langC = (await page.locator("#langSelect").inputValue()) === "c";
	ok(dialectShown && dbgHidden && langC, ".c active: C-dialect shown, debug hidden, langSelect=c");
	await clearAndRun();
	await waitOut("6");
	ok(true, "maxsub.c -> 6");
} catch (e) { ok(false, "maxsub.c: " + e.message + " | out=" + JSON.stringify(await outText())); }

// 3. bsem.c: dialect auto-1120 -> 400; flip to prestruct -> Lvalue required
try {
	await addExample("bsem", "c");
	await starFile("bsem.c");
	ok((await page.locator("#cDialect").inputValue()) === "1120", "bsem.c set dialect to 1120");
	await clearAndRun();
	await waitOut("400");
	ok(true, "bsem.c [1120] -> 400");
	await page.selectOption("#cDialect", "prestruct");
	await clearAndRun();
	await waitOut("Lvalue required");
	ok(true, "bsem.c [prestruct] -> Lvalue required");
} catch (e) { ok(false, "bsem.c: " + e.message + " | out=" + JSON.stringify(await outText())); }

// 3b. B 1972 (.b72)
try {
	await addExample("fact", "b");
	await starFile("fact.b72");
	const lang = await page.evaluate(() => document.getElementById("lmLang").textContent);
	const dbgHidden = !(await page.locator("#dbgMode").isVisible());
	const dialectHidden = !(await page.locator("#cDialect").isVisible());
	ok(lang === "B" && dbgHidden && dialectHidden, ".b72 active: B indicator, debug + dialect hidden");
	await clearAndRun();
	await waitOut("120");
	ok(true, "B 1972 fact.b72 -> 120");
	await addExample("switch", "b");
	await starFile("switch.b72");
	await clearAndRun();
	await waitOut("3 2 1");
	ok(true, "B 1972 switch fallthrough (no break) -> 3 2 1");
} catch (e) { ok(false, "B 1972: " + e.message + " | out=" + JSON.stringify(await outText())); }

// 3c. Waterloo B 1978 (.b78): range switch, f32 floats, string lib, printf, manifests
try {
	await addExample("grade", "bw");
	await starFile("grade.b78");
	const attrib = await page.evaluate(() => document.getElementById("lmAttrib").textContent);
	const lang = await page.evaluate(() => document.getElementById("lmLang").textContent);
	ok(lang === "B" && /Waterloo/.test(attrib), ".b78 active: B / Waterloo indicator");
	await clearAndRun();
	await waitOut("F D C B A A");
	ok(true, "Waterloo switch range cases -> F D C B A A");
	await addExample("float", "bw"); await starFile("float.b78");
	await clearAndRun(); await waitOut("YY");
	ok(true, "Waterloo f32 #-operators -> YY");
	await addExample("puts", "bw"); await starFile("puts.b78");
	await clearAndRun(); await waitOut("hello, museum");
	ok(true, "Waterloo string library: putstr -> hello, museum");
	await addExample("upcase", "bw"); await starFile("upcase.b78");
	await clearAndRun(); await waitOut("HELLO, WATERLOO");
	ok(true, "Waterloo string library: getstr/char/lchar -> HELLO, WATERLOO");
	await addExample("printf", "bw"); await starFile("printf.b78");
	await clearAndRun(); await waitOut("5 squared is 25");
	ok(true, "Waterloo printf (varargs marshalling) -> 5 squared is 25");
	await addExample("manifest", "bw"); await starFile("manifest.b78");
	await clearAndRun(); await waitOut("sum 1..5 = 15 (SQ=25)");
	ok(true, "Waterloo manifest constants -> sum 1..5 = 15 (SQ=25)");
} catch (e) { ok(false, "Waterloo B: " + e.message + " | out=" + JSON.stringify(await outText())); }

// 3d. Language switcher re-scopes the UI + per-dialect highlighting
try {
	await selectLang("c");
	// Files pane: BCPL group is collapsed (header only) -> main.b row not rendered
	const mainVisibleInC = await page.evaluate(() =>
		[...document.querySelectorAll("#fileList li:not(.lang-group)")].some(li => li.textContent.includes("main.b")));
	ok(!mainVisibleInC, "switch to C collapses the BCPL group (main.b row hidden)");
	// Examples pane scoped to C (a C example present, no BCPL tutorial 'Start')
	await page.click('#leftTabs button[data-tab="examples"]');
	const exC = await page.evaluate(() => document.getElementById("exampleList").textContent);
	ok(exC.includes("maxsub") && !exC.includes("Start tutorial"), "Examples scoped to C");
	// API pane scoped to C library
	await page.click('#leftTabs button[data-tab="api"]');
	const apiC = await page.evaluate(() => document.getElementById("apiList").textContent);
	ok(apiC.includes("putchar") && !apiC.includes("Sys_"), "API scoped to C library");
	// indicator follows the dropdown
	ok((await page.evaluate(() => document.getElementById("lmLang").textContent)) === "C", "#lmLang follows langSelect");
	// highlighting: open a C file, expect C keyword spans
	await page.click('#leftTabs button[data-tab="files"]');
	await page.locator("#fileList li", { hasText: "maxsub.c" }).locator(".name").click();
	await page.waitForTimeout(150);
	const hlC = await page.evaluate(() => document.getElementById("editorHl").innerHTML);
	ok(/tok-kw/.test(hlC), "C file highlighted (tok-kw spans present)");
	// Waterloo: a #-operator highlights as tok-op
	await selectLang("bw");
	await page.locator("#fileList li", { hasText: "float.b78" }).locator(".name").click();
	await page.waitForTimeout(150);
	const hlBW = await page.evaluate(() => document.getElementById("editorHl").innerHTML);
	ok(/tok-op/.test(hlBW), "Waterloo file highlighted (#-op as tok-op)");
} catch (e) { ok(false, "switcher/highlight: " + e.message); }

// 4. Switch back to BCPL; debug returns; main.b visible again
try {
	await selectLang("bcpl");
	await starFile("main.b");
	const dbgVisible = await page.locator("#dbgMode").isVisible();
	const dialectHidden = !(await page.locator("#cDialect").isVisible());
	ok(dbgVisible && dialectHidden, "back to BCPL: debug shown, C-dialect hidden");
	await clearAndRun();
	await waitOut("hello from self-hosted bcplwasm");
	ok(true, "BCPL runs again after round-trip");
	const mainOK = await page.evaluate(() =>
		[...document.querySelectorAll("#fileList li")].some(li => li.textContent.includes("main.b")));
	ok(mainOK, "main.b present in expanded BCPL group");
} catch (e) { ok(false, "back-to-BCPL: " + e.message); }

// 5. Language choice persists across reload
try {
	await selectLang("c");
	await page.goto(URL, { waitUntil: "networkidle" });
	ok((await page.locator("#langSelect").inputValue()) === "c", "active language persists across reload");
} catch (e) { ok(false, "persistence: " + e.message); }

if (errs.length) console.log("page errors:\n  " + errs.slice(0, 6).join("\n  "));
await browser.close();
console.log(fails ? `\n${fails} FAILED` : "\nall passed");
process.exit(fails ? 1 : 0);
