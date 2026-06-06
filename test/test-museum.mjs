// Headless E2E for the extension-driven museum: BCPL regression + C files (.c,
// dialect flip) + B files (.b72, fall-through switch). Add as a file, star the
// entry, compile/run. Needs a static server on :8733 (wabt is vendored).
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
async function addCExample(name) {
	await page.click('#leftTabs button[data-tab="examples"]');
	await page.locator("#exampleList li", { hasText: name }).last().getByRole("button").click();
	await page.waitForTimeout(150);
}
async function starFile(fname) {
	await page.click('#leftTabs button[data-tab="files"]');
	await page.locator("#fileList li", { hasText: fname }).locator(".entry-star").click();
	await page.waitForTimeout(100);
}

// 1. BCPL still works + debug visible
try {
	await clearAndRun();
	await waitOut("hello from self-hosted bcplwasm");
	const dbgVisible = await page.locator("#dbgMode").isVisible();
	const dialectHidden = !(await page.locator("#cDialect").isVisible());
	ok(true, "BCPL default runs (regression)");
	ok(dbgVisible && dialectHidden, "BCPL entry: debug shown, C-dialect hidden");
} catch (e) { ok(false, "BCPL default: " + e.message); }

// 2. Add maxsub.c, star it entry, run
try {
	await addCExample("maxsub");
	const inPane = await page.locator("#fileList li", { hasText: "maxsub.c" }).count();
	ok(inPane === 1, "maxsub.c added to files pane");
	await starFile("maxsub.c");
	const dialectShown = await page.locator("#cDialect").isVisible();
	const dbgHidden = !(await page.locator("#dbgMode").isVisible());
	ok(dialectShown && dbgHidden, ".c entry: C-dialect shown, debug hidden");
	await clearAndRun();
	await waitOut("6");
	ok(true, "maxsub.c -> 6");
} catch (e) { ok(false, "maxsub.c: " + e.message + " | out=" + JSON.stringify(await outText())); }

// 3. bsem.c: dialect auto-1120 -> 400; flip to prestruct -> Lvalue required
try {
	await addCExample("bsem");
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

// 3b. B 1972 (.b72): use b72-unique example names ("fact", "switch") since
//     addCExample('name').last() picks the LAST matching row, and "hello" also
//     exists in the Waterloo section appended below.
try {
	await addCExample("fact");
	await starFile("fact.b72");
	const lang = await page.evaluate(() => document.getElementById("lmLang").textContent);
	const dbgHidden = !(await page.locator("#dbgMode").isVisible());
	const dialectHidden = !(await page.locator("#cDialect").isVisible());
	ok(lang === "B" && dbgHidden && dialectHidden, ".b72 entry: B indicator, debug + dialect hidden");
	await clearAndRun();
	await waitOut("120");
	ok(true, "B 1972 fact.b72 -> 120");
	await addCExample("switch");
	await starFile("switch.b72");
	await clearAndRun();
	await waitOut("3 2 1");
	ok(true, "B 1972 switch fallthrough (no break) -> 3 2 1");
} catch (e) { ok(false, "B 1972: " + e.message + " | out=" + JSON.stringify(await outText())); }

// 3c. Waterloo B 1978 (.b78): range-case switch + f32 #-floats.
try {
	await addCExample("grade");
	await starFile("grade.b78");
	const attrib = await page.evaluate(() => document.getElementById("lmAttrib").textContent);
	const lang = await page.evaluate(() => document.getElementById("lmLang").textContent);
	ok(lang === "B" && /Waterloo/.test(attrib), ".b78 entry: B / Waterloo indicator");
	await clearAndRun();
	await waitOut("F D C B A A");
	ok(true, "Waterloo switch range cases -> F D C B A A");
	await addCExample("float");
	await starFile("float.b78");
	await clearAndRun();
	await waitOut("YY");
	ok(true, "Waterloo f32 #-operators -> YY");
	await addCExample("puts");
	await starFile("puts.b78");
	await clearAndRun();
	await waitOut("hello, museum");
	ok(true, "Waterloo string library: putstr -> hello, museum");
	await addCExample("upcase");
	await starFile("upcase.b78");
	await clearAndRun();
	await waitOut("HELLO, WATERLOO");
	ok(true, "Waterloo string library: getstr/char/lchar -> HELLO, WATERLOO");
} catch (e) { ok(false, "Waterloo B: " + e.message + " | out=" + JSON.stringify(await outText())); }

// 4. Switch entry back to BCPL; debug returns; main.b intact
try {
	await starFile("main.b");
	const dbgVisible = await page.locator("#dbgMode").isVisible();
	const dialectHidden = !(await page.locator("#cDialect").isVisible());
	ok(dbgVisible && dialectHidden, "back to .b entry: debug shown, C-dialect hidden");
	await clearAndRun();
	await waitOut("hello from self-hosted bcplwasm");
	ok(true, "BCPL runs again after C round-trip");
	const mainOK = await page.evaluate(() => {
		const li = [...document.querySelectorAll("#fileList li")].find((x) => x.textContent.includes("main.b"));
		return !!li;
	});
	ok(mainOK, "main.b still present (mixed pane: main.b + maxsub.c + bsem.c)");
} catch (e) { ok(false, "back-to-BCPL: " + e.message); }

if (errs.length) console.log("page errors:\n  " + errs.slice(0, 6).join("\n  "));
await browser.close();
console.log(fails ? `\n${fails} FAILED` : "\nall passed");
process.exit(fails ? 1 : 0);
