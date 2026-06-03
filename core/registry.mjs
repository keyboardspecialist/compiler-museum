// The compiler registry. Each entry lazy-loads a plugin module (default export
// is the plugin object — see plugins/_template.mjs). Add a compiler by adding
// one line here plus its plugins/<id>.mjs.

export const registry = [
	{ id: "c", load: () => import("../plugins/c.mjs") },
	// { id: "bcpl", load: () => import("../plugins/bcpl.mjs") },  // phase 2
];

const cache = new Map();
export async function loadPlugin(id) {
	if (!cache.has(id)) {
		const entry = registry.find((r) => r.id === id);
		if (!entry) throw new Error(`no plugin '${id}'`);
		cache.set(id, (await entry.load()).default);
	}
	return cache.get(id);
}
