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
	const dbgShown = await page.locator("#dbgMode").isVisible();
	const langC = (await page.locator("#langSelect").inputValue()) === "c";
	ok(dialectShown && dbgShown && langC, ".c active: C-dialect + debug shown, langSelect=c");
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
	// dialect-specific examples refilter when #cDialect changes
	await page.click('#leftTabs button[data-tab="examples"]');
	const exPre = await page.evaluate(() => document.getElementById("exampleList").textContent);
	await page.selectOption("#cDialect", "1120");
	await page.waitForTimeout(150);
	const ex1120 = await page.evaluate(() => document.getElementById("exampleList").textContent);
	ok(/struct/.test(exPre) && !/struct/.test(ex1120) && /bsem/.test(ex1120),
		"C examples refilter by dialect (struct=prestruct, bsem=1120)");
} catch (e) { ok(false, "bsem.c: " + e.message + " | out=" + JSON.stringify(await outText())); }

// 3b. B 1972 (.b72)
try {
	await addExample("fact", "b");
	await starFile("fact.b72");
	const lang = await page.evaluate(() => document.getElementById("lmLang").textContent);
	const dbgShown = await page.locator("#dbgMode").isVisible();
	const dialectHidden = !(await page.locator("#cDialect").isVisible());
	ok(lang === "B" && dbgShown && dialectHidden, ".b72 active: B indicator, debug shown, dialect hidden");
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
	await addExample("switch", "bw"); await starFile("switch.b78");
	await clearAndRun(); await waitOut("SDLLCP");
	ok(true, "Waterloo full switch (single/range/relational/default) -> SDLLCP");
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

// 3e. Debugging C: breakpoint pause / step / continue / locals, then a clean
//     non-debug run. Uses maxsub.c; line 9 is `best = a[0]; ...` inside maxsub.
async function dbgIsOn() {
	return (await page.locator("#dbgMode").getAttribute("aria-pressed")) === "true";
}
async function waitPaused(ms = 30000) {
	await page.waitForFunction(() => /paused/.test(document.getElementById("compileStatus")?.textContent || ""), null, { timeout: ms });
}
try {
	await addExample("maxsub", "c");
	await starFile("maxsub.c");
	if (!(await dbgIsOn())) await page.click("#dbgMode");
	// set a breakpoint by clicking the gutter (editor shows maxsub.c)
	await page.locator('#editorGutter .gut-line[data-line="9"]').click();
	await clearAndRun();
	await waitPaused();
	ok(true, "C breakpoint pauses execution");
	const locals = await page.evaluate(() => document.getElementById("localsBox").textContent || "");
	ok(/best/.test(locals) && /cur/.test(locals), "Locals show frame variables (best, cur)");
	await page.click("#stepRun");
	await page.waitForTimeout(400);
	ok(true, "C single-step");
	await page.click("#continueRun");
	await waitOut("6");
	ok(true, "C continue runs to completion -> 6");
	await page.click("#dbgMode");          // debug off
	await clearAndRun();
	await waitOut("6");
	ok(true, "C non-debug run still works (zero-overhead path)");
} catch (e) { ok(false, "C debug: " + e.message + " | status=" + (await page.locator("#compileStatus").textContent().catch(() => ""))); }

// 3f. Debugging Waterloo B: breakpoint pause + continue (covers BWRuntime).
try {
	await addExample("loops", "bw");
	await starFile("loops.b78");
	if (!(await dbgIsOn())) await page.click("#dbgMode");
	await page.locator('#editorGutter .gut-line[data-line="9"]').click();
	await clearAndRun();
	await waitPaused();
	ok(true, "Waterloo B breakpoint pauses execution");
	await page.click("#continueRun");
	await waitOut("37");
	ok(true, "Waterloo B continue runs to completion -> 37");
	await page.click("#dbgMode");          // debug off
} catch (e) { ok(false, "BW debug: " + e.message + " | status=" + (await page.locator("#compileStatus").textContent().catch(() => ""))); }

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

// 4b. Non-BCPL example: clicking the NAME opens a read-only preview (not a
//     new file); the source loads into the editor.
try {
	await selectLang("c");
	await page.click('#leftTabs button[data-tab="examples"]');
	await page.locator("#exampleList li", { hasText: "upper" }).last().locator(".name").click();
	await page.waitForTimeout(300);
	const ed = await page.locator("#userSrc").inputValue();
	ok(/getchar/.test(ed), "C example name click opens a preview (source in editor)");
} catch (e) { ok(false, "example preview: " + e.message); }

// 4c. Closing tabs: previews vanish; a file tab closes but the file stays.
try {
	await selectLang("c");
	await page.click('#leftTabs button[data-tab="examples"]');
	await page.locator("#exampleList li", { hasText: "upper" }).last().locator(".name").click();
	await page.waitForTimeout(200);
	await page.locator('#sourceTabs .tab', { hasText: "preview" }).first().locator(".close").click();
	await page.waitForTimeout(150);
	const noPreview = await page.evaluate(() =>
		![...document.querySelectorAll('#sourceTabs .tab')].some(t => /preview/.test(t.textContent)));
	ok(noPreview, "closing a preview tab removes it");
	await page.click('#leftTabs button[data-tab="files"]');   // Files pane (was on Examples)
	await page.locator("#fileList li", { hasText: "maxsub.c" }).locator(".name").click();
	await page.waitForTimeout(150);
	// click the maxsub.c tab's close (tab strip may be scrolled; click via DOM)
	await page.evaluate(() => {
		const t = [...document.querySelectorAll('#sourceTabs .tab')].find(x => x.textContent.includes("maxsub.c"));
		t.querySelector(".close").click();
	});
	await page.waitForTimeout(150);
	const tabGone = await page.evaluate(() =>
		![...document.querySelectorAll('#sourceTabs .tab')].some(t => t.textContent.includes("maxsub.c")));
	const fileStays = await page.evaluate(() =>
		[...document.querySelectorAll('#fileList li:not(.lang-group) .name')].some(n => n.textContent.includes("maxsub.c")));
	ok(tabGone && fileStays, "closing a file tab keeps the file in the Files list");
} catch (e) { ok(false, "close tabs: " + e.message); }

// 4d. New non-BCPL file gets language-appropriate boilerplate, not BCPL headers.
try {
	await page.click('#leftTabs button[data-tab="files"]');
	page.once("dialog", (d) => d.accept("scratch.b72"));
	await page.click("#addFile");
	await page.waitForTimeout(250);
	const ed = await page.locator("#userSrc").inputValue();
	ok(/main\(\)/.test(ed) && !/SECTION|libhdr|GLOBAL/.test(ed),
		"new .b72 file gets B boilerplate (not BCPL)");
} catch (e) { ok(false, "new B file: " + e.message); }

// 5. Language choice persists across reload
try {
	await selectLang("c");
	await page.goto(URL, { waitUntil: "networkidle" });
	ok((await page.locator("#langSelect").inputValue()) === "c", "active language persists across reload");
} catch (e) { ok(false, "persistence: " + e.message); }

// 6. Hard link: #example=<file.ext> opens the museum example + switches language
try {
	await page.goto("about:blank");   // force a real navigation (hash-only goto won't reload)
	await page.goto(URL + "#example=switch.b78", { waitUntil: "networkidle" });
	await page.waitForTimeout(500);
	const lang = await page.locator("#langSelect").inputValue();
	const ed = await page.locator("#userSrc").inputValue();
	ok(lang === "bw" && /kind/.test(ed), "#example=switch.b78 hard link loads the Waterloo example");
} catch (e) { ok(false, "hard link: " + e.message); }

if (errs.length) console.log("page errors:\n  " + errs.slice(0, 6).join("\n  "));
await browser.close();
console.log(fails ? `\n${fails} FAILED` : "\nall passed");
process.exit(fails ? 1 : 0);
