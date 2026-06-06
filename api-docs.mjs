// Curated help text for the Runtime API tab. Keyed by BCPL function
// name (matches stdlib-manifest.mjs + g/libhdr.h). If a runtime slot
// exists without an entry here, the UI shows "(no help available)".

export const API_DOCS = {
  // ---- I/O ----
  writef: {
    sig: "writef(fmt, a0..a10)",
    cat: "I/O",
    desc: "Formatted write. Format codes: %n %d %i %u %c %s %x %o %b %z %t %f %e %g. " +
          "Width: '%i4' or '%5.2f'.",
  },
  writes:    { sig: "writes(s)",      cat: "I/O", desc: "Write BCPL string to current output." },
  writen:    { sig: "writen(n)",      cat: "I/O", desc: "Write signed decimal." },
  writed:    { sig: "writed(n, d)",   cat: "I/O", desc: "Signed decimal, space-padded to d chars." },
  writeu:    { sig: "writeu(n, d)",   cat: "I/O", desc: "Unsigned decimal, space-padded." },
  writet:    { sig: "writet(s, d)",   cat: "I/O", desc: "BCPL string padded right with spaces to width d." },
  writez:    { sig: "writez(n, d)",   cat: "I/O", desc: "Signed decimal, zero-padded to d chars." },
  writehex:  { sig: "writehex(n, d)", cat: "I/O", desc: "Unsigned hex, zero-padded to d digits (uppercase)." },
  writeoct:  { sig: "writeoct(n, d)", cat: "I/O", desc: "Unsigned octal, zero-padded." },
  writebin:  { sig: "writebin(n, d)", cat: "I/O", desc: "Unsigned binary, zero-padded to d digits. BLIB-local helper in upstream cintsys; playground exposes it as a public global. Same logic as writef(\"%b\")." },
  writeflt:  { sig: "writeflt(x, w, p)", cat: "I/O", desc: "Float x (f32 bits) as fixed-point, width w, p decimals." },
  writee:    { sig: "writee(x, w, p)",   cat: "I/O", desc: "Float x as exponential, width w, p decimals." },
  newline:   { sig: "newline()",      cat: "I/O", desc: "Write LF (ASCII 10)." },
  newpage:   { sig: "newpage()",      cat: "I/O", desc: "Write form-feed (ASCII 12)." },
  wrch:      { sig: "wrch(ch)",       cat: "I/O", desc: "Write one char to current output stream." },
  binwrch:   { sig: "binwrch(ch)",    cat: "I/O", desc: "Alias of wrch (playground has no binary-mode distinction)." },
  sawrch:    { sig: "sawrch(ch)",     cat: "I/O", desc: "Direct-screen char write. Alias of wrch in playground." },
  codewrch:  { sig: "codewrch(code)", cat: "I/O", desc: "Write Unicode codepoint (UTF-8 in playground)." },
  errwrch:   { sig: "errwrch(ch)",    cat: "I/O", desc: "Write char to stderr (same sink as stdout in playground)." },
  errwritef: { sig: "errwritef(fmt, …)", cat: "I/O", desc: "writef to stderr; delegates to writef in playground." },
  sawritef:  { sig: "sawritef(fmt, …)",  cat: "I/O", desc: "writef bypassing output-stream selection. Alias of writef." },

  // ---- Char input ----
  rdch:     { sig: "rdch()",    cat: "input", desc: "Read next char from current input. -1 at EOF." },
  binrdch:  { sig: "binrdch()", cat: "input", desc: "Alias of rdch." },
  sardch:   { sig: "sardch()",  cat: "input", desc: "Direct-keyboard read. Alias of rdch." },
  unrdch:   { sig: "unrdch()",  cat: "input", desc: "Push last-read char back onto the input stream." },

  // ---- Stream management ----
  findinput:     { sig: "findinput(name) → h",  cat: "streams", desc: "Open named stream for reading (via storageBackend). Returns handle or 0." },
  findoutput:    { sig: "findoutput(name) → h", cat: "streams", desc: "Open named stream for writing. Handle or 0." },
  findinoutput:  { sig: "findinoutput(name) → h", cat: "streams", desc: "Open read+write stream." },
  pathfindinput: { sig: "pathfindinput(name, paths) → h", cat: "streams", desc: "Find file by search path. Playground uses storage lookup." },
  selectinput:   { sig: "selectinput(h) → prev", cat: "streams", desc: "Switch current input stream. Returns previous handle." },
  selectoutput:  { sig: "selectoutput(h) → prev", cat: "streams", desc: "Switch current output stream. Returns previous handle." },
  input:         { sig: "input() → h",  cat: "streams", desc: "Return current input handle (cis)." },
  output:        { sig: "output() → h", cat: "streams", desc: "Return current output handle (cos)." },
  endstream:     { sig: "endstream(h)", cat: "streams", desc: "Close stream. Writes commit to storage." },
  endread:       { sig: "endread()",    cat: "streams", desc: "Close current input stream, reset to stdin." },
  endwrite:      { sig: "endwrite()",   cat: "streams", desc: "Close current output stream, reset to stdout." },
  rewindstream:  { sig: "rewindstream(h)", cat: "streams", desc: "Reset stream position to start." },
  findappend:    { sig: "findappend(name) → h", cat: "streams", desc: "Open named stream so all subsequent writes append past any existing content. Creates an empty file if it doesn't exist. CIN:y." },
  appendstream:  { sig: "appendstream(h) → -1/0", cat: "streams", desc: "Move an open stream's write position to its end. Returns -1 on success, 0 on bad handle. CIN:y." },
  deletefile:    { sig: "deletefile(name) → -1/0", cat: "streams", desc: "Remove named entry from storage. -1 on success, 0 if missing. CIN:y." },
  renamefile:    { sig: "renamefile(old, new) → -1/0", cat: "streams", desc: "Atomic rename in storage. -1 on success, 0 if old missing or new already exists. CIN:y." },
  point:         { sig: "point(scb, posv) → -1/0", cat: "streams", desc: "Set stream pos from posv = (block, offset). pos = block * blockSize + offset. blockSize defaults to the stream's current length. -1 on success." },
  note:          { sig: "note(scb, posv) → -1/0", cat: "streams", desc: "Read current stream pos into posv (posv!0 = block, posv!1 = offset). Inverse of point." },
  setrecordlength: { sig: "setrecordlength(scb, length) → prev", cat: "streams", desc: "Record-mode: declare reclen (bytes) for subsequent get_record / put_record / recordpoint calls. Returns previous reclen. Length stored in SCB struct slot 15." },
  recordpoint:   { sig: "recordpoint(scb, recno) → -1/0", cat: "streams", desc: "Seek to byte recno*reclen so the next get_record / put_record hits record `recno`. -1 on success, 0 if no reclen or bad scb." },
  recordnote:    { sig: "recordnote(scb) → recno", cat: "streams", desc: "Current record number = floor(pos / reclen). -1 if reclen unset." },
  get_record:    { sig: "get_record(vector, recno, scb) → TRUE/FALSE", cat: "streams", desc: "Read reclen bytes of record `recno` into vector%0..vector%(reclen-1). FALSE on EOF, bad scb, or no reclen." },
  put_record:    { sig: "put_record(vector, recno, scb) → TRUE/FALSE", cat: "streams", desc: "Write reclen bytes from vector%0..vector%(reclen-1) into record `recno`. Extends stream if recno is past current end. Stream must be in write or read+write mode." },

  // ---- Memory / bits ----
  getvec:     { sig: "getvec(n) → v",           cat: "memory", desc: "Allocate n+1 words. Returns pointer or 0 on OOM." },
  freevec:    { sig: "freevec(v)",              cat: "memory", desc: "Return vector to free list." },
  copystring: { sig: "copystring(from, to)",    cat: "memory", desc: "Byte-copy BCPL string (including length byte)." },
  copy_words: { sig: "copy_words(from, to, n)", cat: "memory", desc: "Copy n words." },
  clear_words:{ sig: "clear_words(v, n)",       cat: "memory", desc: "Zero-fill n words." },
  copy_bytes: { sig: "copy_bytes(fromlen, from, fillch, tolen, to) → rem", cat: "memory", desc: "MOVC5 byte copy with fill padding." },
  packstring: { sig: "packstring(v, s) → size", cat: "memory", desc: "Pack byte-per-word vec v into byte-packed BCPL string s." },
  unpackstring:{ sig: "unpackstring(s, v)",     cat: "memory", desc: "Unpack string into byte-per-word vec." },
  getword:    { sig: "getword(v, i)",           cat: "memory", desc: "Fetch little-endian 16-bit word at byte offset i*2 of v." },
  putword:    { sig: "putword(v, i, w)",        cat: "memory", desc: "Store low 16 bits of w into i'th LE word slot." },
  setbit:     { sig: "setbit(bitno, bitvec, state) → old", cat: "memory", desc: "Set/clear bit, return previous value." },
  testbit:    { sig: "testbit(bitno, bitvec)",  cat: "memory", desc: "Returns nonzero if bit is set." },
  setvec:     { sig: "setvec(v, n, a0..a15)",   cat: "memory", desc: "Copy up to 16 vararg values into v!0..v!n-1." },

  // ---- Parsing / conversion ----
  readn:            { sig: "readn() → n",             cat: "parse", desc: "Read signed decimal from current input. result2=-1 if no digits." },
  readflt:          { sig: "readflt() → bits",        cat: "parse", desc: "Read float from input. Returns f32 bit pattern." },
  rditem:           { sig: "rditem(v, upb) → type",   cat: "parse", desc: "Read token: 0=EOF 1=word 2=quoted 3=NL 4=';' 5='='." },
  str2numb:         { sig: "str2numb(s) → n",         cat: "parse", desc: "Simple string→int (deprecated but supported)." },
  string_to_number: { sig: "string_to_number(s) → ok", cat: "parse", desc: "Full parser: signs, #O/#X/#B bases, 'A' char literal, underscores. Value in result2." },
  findarg:          { sig: "findarg(keys, w) → idx",  cat: "parse", desc: "Find matching keyword in rdargs key-spec. -1 if not found." },
  rdargs:           { sig: "rdargs(keys, argv, upb)", cat: "parse", desc: "Parse command-line args per key-spec. Fills argv." },
  capitalch:        { sig: "capitalch(ch)",           cat: "parse", desc: "Uppercase a..z; others unchanged." },
  compch:           { sig: "compch(a, b)",            cat: "parse", desc: "Case-insensitive char compare: -1/0/+1." },
  compstring:       { sig: "compstring(s1, s2)",      cat: "parse", desc: "Case-insensitive string compare: -1/0/+1." },

  // ---- Math ----
  muldiv: { sig: "muldiv(a, b, c) → (a*b)/c", cat: "math", desc: "64-bit intermediate. Remainder in result2." },
  randno: { sig: "randno(upb) → n",           cat: "math", desc: "Random int in [1..upb]. Uses randseed (G!127)." },
  setseed:{ sig: "setseed(v) → old",          cat: "math", desc: "Replace randseed; return old value." },
  abs:    { sig: "ABS(x)",                    cat: "math", desc: "Absolute value (language keyword)." },

  // ---- Diagnostic / system ----
  memoryfree: { sig: "memoryfree(x) → free", cat: "system", desc: "Free heap words. Total in result2." },
  stackfree:  { sig: "stackfree(hwm) → free", cat: "system", desc: "Free stack words (heuristic). Size in result2." },
  intflag:    { sig: "intflag() → bool",      cat: "system", desc: "Always FALSE in playground (no interrupt source)." },
  abort:      { sig: "abort(code)",           cat: "system", desc: "Halt with error flag set." },
  stop:       { sig: "stop(code)",            cat: "system", desc: "Halt program cleanly." },
  level:      { sig: "level() → P",           cat: "system", desc: "Capture current stack frame pointer. Use with longjump." },
  longjump:   { sig: "longjump(p, l)",        cat: "system", desc: "Non-local jump. In playground, halts." },

  // ---- Diagnostic helpers (BLIB additions). Cheap safety nets that
  // catch common BCPL bugs at their source instead of via a downstream
  // SIGSEGV. All abort with code 901 and a labelled message.
  assert: {
    sig: "assert(cond, msg)",
    cat: "debug",
    desc: "Aborts (code 901) if cond is FALSE, printing `ASSERT FAIL: <msg>`. " +
          "msg is a BCPL string. Use to nail invariants at the failing line " +
          "instead of chasing a downstream crash."
  },
  getvec_or_abort: {
    sig: "getvec_or_abort(n, msg) → ptr",
    cat: "debug",
    desc: "Like getvec(n) but aborts with `GETVEC OOM: <msg> (requested N words)` " +
          "instead of returning 0 silently. Eliminates the `IF p=0 ...` " +
          "boilerplate every caller forgets."
  },
  vsafe_get: {
    sig: "vsafe_get(v, i, msg) → v!i",
    cat: "debug",
    desc: "Bounds-checked v!i. Reads the size header BLIB stores with " +
          "every getvec allocation; aborts with `VSAFE OOB: <msg> " +
          "(i=N upb=N)` on out-of-range index instead of silently reading " +
          "adjacent memory. NULL pointer also aborts cleanly."
  },

  // ---- Coroutines (Asyncify-backed) ----
  createco: {
    sig: "createco(fn, size) → handle",
    cat: "coroutines",
    desc: "Allocate a coroutine: 6-word header + size-word stack + asyncify state buffer. " +
          "Returns a handle (BCPL pointer). The first callco delivers its arg as fn's parameter; " +
          "subsequent activations resume the body at its last cowait.",
  },
  callco: {
    sig: "callco(c, arg) → val",
    cat: "coroutines",
    desc: "Suspend the caller, resume coroutine c with arg. Returns whatever the coroutine " +
          "next cowait's (or its final return value if it completes). Sets c's parent link " +
          "to the caller.",
  },
  cowait: {
    sig: "cowait(arg) → val",
    cat: "coroutines",
    desc: "Yield arg to the parent coroutine and suspend. The corresponding callco in the " +
          "parent receives arg as its return value. When the parent next callco's this " +
          "coroutine, cowait returns the parent's new arg.",
  },
  resumeco: {
    sig: "resumeco(c, arg) → val",
    cat: "coroutines",
    desc: "Like callco but reparents c so the original parent isn't on the chain. " +
          "Currently aliased to callco in the playground.",
  },
  deleteco: {
    sig: "deleteco(c)",
    cat: "coroutines",
    desc: "Remove a coroutine from the runtime registry. Heap reclaim is bump-allocator only — " +
          "deleteco does NOT actually free the slab. Acceptable for demos.",
  },
  initco: {
    sig: "initco(fn, size, a..k) → handle",
    cat: "coroutines",
    desc: "createco + seed first cowait return with a (BCPL libhdr pattern). Up to 11 args.",
  },
  changeco: {
    sig: "changeco(val, c) → val",
    cat: "coroutines",
    desc: "Low-level context swap: suspend caller, resume c with val. Currently aliased to callco.",
  },

  // ---- Animation timing ----
  delay: {
    sig: "delay(ms)",
    cat: "system",
    desc: "Suspend for ms milliseconds. Asyncify-backed: yields one requestAnimationFrame " +
          "(canvas paints), then setTimeout for any remainder past 16ms. Use between frames " +
          "in animation loops; without it, render code runs synchronously and only the final " +
          "frame is visible.",
  },
  delayuntil: {
    sig: "delayuntil(days, msecs)",
    cat: "system",
    desc: "Sleep until wall clock reaches (days since 1 Jan 1978, msecs since midnight). " +
          "Reuses the asyncify delay path; returns immediately if the target is already past. CIN:y.",
  },
  datstamp: {
    sig: "datstamp(v)",
    cat: "system",
    desc: "Fill v[0..2] with the current date/time: v!0 = days since 1 Jan 1978, " +
          "v!1 = milliseconds since midnight (UTC), v!2 = ticks since boot (ms). " +
          "Returns v. CIN:y.",
  },

  // ---- SDL graphics (sys(Sys_sdl, op, ...)) ----
  // The playground does not ship sdl.b BCPL wrappers — call via sys() directly.
  // Header sdl.h (auto-seeded) declares all sdl_* manifest constants.
  // Each sdl_* sub-op below has its own entry; click for signature + notes.
  Sys_sdl: {
    sig: "sys(Sys_sdl, op, …)",
    cat: "graphics",
    desc: "SDL dispatcher. Browse the sdl_* entries (filter the list with " +
          "\"sdl\") for individual sub-op signatures and behavior. Programs " +
          "include the sdl.h header (auto-seeded) for the sdl_* manifest " +
          "constants, then call sys(Sys_sdl, sdl_xxx, args…). The first " +
          "sdl_init reveals the canvas pane; sdl_setvideomode(w,h,0,0) " +
          "returns the surface handle (use 1).",
  },
  sdl_init:           { sig: "sys(Sys_sdl, sdl_init)", cat: "graphics", desc: "Reveal the canvas pane and start the timer (sdl_getticks epoch)." },
  sdl_setvideomode:   { sig: "sys(Sys_sdl, sdl_setvideomode, w, h, bpp, flags) → surf", cat: "graphics", desc: "Set canvas size. Returns a surface handle (use 1)." },
  sdl_quit:           { sig: "sys(Sys_sdl, sdl_quit)", cat: "graphics", desc: "No-op in playground; left for source compatibility with cintsys SDL." },
  sdl_maprgb:         { sig: "sys(Sys_sdl, sdl_maprgb, fmt, r, g, b) → col", cat: "graphics", desc: "Pack r,g,b (0..255) into a colour int the draw ops accept." },
  sdl_drawline:       { sig: "sys(Sys_sdl, sdl_drawline, surf, x1, y1, x2, y2, col)", cat: "graphics", desc: "Stroke a line." },
  sdl_drawhline:      { sig: "sys(Sys_sdl, sdl_drawhline, surf, x1, x2, y, col)", cat: "graphics", desc: "Stroke a horizontal line." },
  sdl_drawvline:      { sig: "sys(Sys_sdl, sdl_drawvline, surf, x, y1, y2, col)", cat: "graphics", desc: "Stroke a vertical line." },
  sdl_drawpixel:      { sig: "sys(Sys_sdl, sdl_drawpixel, surf, x, y, col)", cat: "graphics", desc: "Set a single pixel." },
  sdl_drawrect:       { sig: "sys(Sys_sdl, sdl_drawrect, surf, x1, y1, x2, y2, col)", cat: "graphics", desc: "Stroke rect outline." },
  sdl_drawfillrect:   { sig: "sys(Sys_sdl, sdl_drawfillrect, surf, x1, y1, x2, y2, col)", cat: "graphics", desc: "Fill rect." },
  sdl_fillrect:       { sig: "sys(Sys_sdl, sdl_fillrect, surf, x1, y1, x2, y2, col)", cat: "graphics", desc: "Same as drawfillrect." },
  sdl_drawcircle:     { sig: "sys(Sys_sdl, sdl_drawcircle, surf, cx, cy, r, col)", cat: "graphics", desc: "Stroke circle outline." },
  sdl_drawfillcircle: { sig: "sys(Sys_sdl, sdl_drawfillcircle, surf, cx, cy, r, col)", cat: "graphics", desc: "Filled disk." },
  sdl_drawellipse:    { sig: "sys(Sys_sdl, sdl_drawellipse, surf, cx, cy, rx, ry, col)", cat: "graphics", desc: "Stroke ellipse outline." },
  sdl_drawfillellipse:{ sig: "sys(Sys_sdl, sdl_drawfillellipse, surf, cx, cy, rx, ry, col)", cat: "graphics", desc: "Filled ellipse." },
  sdl_fillsurf:       { sig: "sys(Sys_sdl, sdl_fillsurf, surf, col)", cat: "graphics", desc: "Clear (or fill) the entire surface with col." },
  sdl_flip:           { sig: "sys(Sys_sdl, sdl_flip, surf)", cat: "graphics", desc: "No-op on canvas — paints happen automatically when JS yields (use delay)." },
  sdl_pollevent:      { sig: "sys(Sys_sdl, sdl_pollevent, v) → bool", cat: "graphics", desc: "Pop next event into v[0..2]. v[0]=type (sdle_*), v[1]/v[2]=args. Returns -1 if any, 0 if none." },
  sdl_waitevent:      { sig: "sys(Sys_sdl, sdl_waitevent, v) → bool", cat: "graphics", desc: "Same as pollevent in playground (does NOT actually block — use delay+pollevent in a loop)." },
  sdl_getmousestate:  { sig: "sys(Sys_sdl, sdl_getmousestate, v) → buttons", cat: "graphics", desc: "v[0],v[1] := mouse x,y. Returns button-bits mask." },
  sdl_getticks:       { sig: "sys(Sys_sdl, sdl_getticks) → ms", cat: "graphics", desc: "Milliseconds since sdl_init." },
  sdl_wm_setcaption:  { sig: "sys(Sys_sdl, sdl_wm_setcaption, str, ?)", cat: "graphics", desc: "Update the document title." },

  // ---- Raw syscall ----
  sys: {
    sig: "sys(op, …)",
    cat: "syscall",
    desc: "Low-level dispatcher. Each Sys_* below has its own entry — " +
          "filter the list with \"Sys_\" to browse. Most BCPL programs " +
          "use the wired stdlib functions (writef, getvec, etc.) which " +
          "internally route through sys() in the cintsys reference impl; " +
          "in the playground those calls go directly to host imports.",
  },

  // ---- Sys_* sub-op entries (documentation pseudo-keys) ----
  // These aren't BCPL globals; they're constants you pass to sys(op, …).
  // Listed individually so the API tab can document each.
  Sys_quit: {
    sig: "sys(Sys_quit, code)",
    cat: "syscall",
    desc: "Hard halt; throws BcplHalt(code). Equivalent to abort(code).",
  },
  Sys_sardch: { sig: "sys(Sys_sardch) → ch",     cat: "syscall", desc: "Direct keyboard read; alias of rdch in playground." },
  Sys_sawrch: { sig: "sys(Sys_sawrch, ch)",      cat: "syscall", desc: "Direct screen write; alias of wrch in playground." },
  Sys_read:   { sig: "sys(Sys_read, fd) → ch",   cat: "syscall", desc: "Read one byte from the given stream handle (or current if 0)." },
  Sys_write:  { sig: "sys(Sys_write, fd, ch)",   cat: "syscall", desc: "Write one byte to the given stream handle (or current if 0)." },
  Sys_openread:      { sig: "sys(Sys_openread, name) → h",    cat: "syscall", desc: "Open named storage entry for reading. Handle or 0." },
  Sys_openwrite:     { sig: "sys(Sys_openwrite, name) → h",   cat: "syscall", desc: "Open named storage entry for writing. Handle or 0." },
  Sys_openappend:    { sig: "sys(Sys_openappend, name) → h",  cat: "syscall", desc: "Open for append (existing data preserved)." },
  Sys_openreadwrite: { sig: "sys(Sys_openreadwrite, name)→h", cat: "syscall", desc: "Open read+write." },
  Sys_close:  { sig: "sys(Sys_close, h)",        cat: "syscall", desc: "Close stream; commits write streams to storage." },
  Sys_deletefile: { sig: "sys(Sys_deletefile, name) → ok",   cat: "syscall", desc: "Remove a stored entry. -1 on success." },
  Sys_renamefile: { sig: "sys(Sys_renamefile, old, new) → ok", cat: "syscall", desc: "Rename. -1 on success." },
  Sys_getvec: { sig: "sys(Sys_getvec, n) → v",   cat: "syscall", desc: "No-op in playground; use getvec()." },
  Sys_freevec:{ sig: "sys(Sys_freevec, v)",      cat: "syscall", desc: "No-op in playground; use freevec()." },
  Sys_muldiv: { sig: "sys(Sys_muldiv, a, b, c)", cat: "syscall", desc: "(a*b)/c with 64-bit intermediate; remainder in result2." },
  Sys_intflag:{ sig: "sys(Sys_intflag) → 0",     cat: "syscall", desc: "Always FALSE — no interrupt source in playground." },
  Sys_cputime:{ sig: "sys(Sys_cputime) → 0",     cat: "syscall", desc: "Stub returning 0; use Sys_getticks for wall-clock ms." },
  Sys_setprefix: { sig: "sys(Sys_setprefix, str)", cat: "syscall", desc: "Update G!14 currentdir from a BCPL string." },
  Sys_getprefix: { sig: "sys(Sys_getprefix) → ptr", cat: "syscall", desc: "Return G!14 currentdir pointer." },
  Sys_seek:   { sig: "sys(Sys_seek, h, pos, whence)", cat: "syscall", desc: "Stream seek. whence: 0=set, 1=cur, 2=end." },
  Sys_tell:   { sig: "sys(Sys_tell, h) → pos",   cat: "syscall", desc: "Current stream byte position." },
  Sys_datstamp:{ sig: "sys(Sys_datstamp, v) → v", cat: "syscall", desc: "Fill v[0]=days, v[1]=ms-of-day, v[2]=-1 from Date.now()." },
  Sys_filesize:{ sig: "sys(Sys_filesize, name) → bytes", cat: "syscall", desc: "Length of stored entry; -1 if missing." },
  Sys_getsysval:{ sig: "sys(Sys_getsysval, key) → val", cat: "syscall", desc: "Map-backed kv lookup keyed by integer." },
  Sys_putsysval:{ sig: "sys(Sys_putsysval, key, val)",  cat: "syscall", desc: "Map-backed kv store." },
  Sys_getpid: { sig: "sys(Sys_getpid) → 1",      cat: "syscall", desc: "Always returns 1." },
  Sys_inc:    { sig: "sys(Sys_inc, addr) → new", cat: "syscall", desc: "Atomic-ish increment at word address (single-threaded)." },
  Sys_flt: {
    sig: "sys(Sys_flt, sub, a, b)",
    cat: "syscall",
    desc: "Float dispatcher. sub-ops:\n" +
          "  1 fl_mk(m,e)→bits     2 fl_unmk(bits)→i   3 fl_float(i)→bits\n" +
          "  4 fl_fix(bits)→i      5 fl_abs(bits)\n" +
          "  6 fl_mul(a,b)         7 fl_div(a,b)        8 fl_mod(a,b)\n" +
          "  9 fl_add(a,b)        10 fl_sub(a,b)       11 fl_pos(a)\n" +
          " 12 fl_neg(a)\n" +
          " 13 fl_eq(a,b)→bool   14 fl_ne   15 fl_ls   16 fl_gr\n" +
          " 17 fl_le             18 fl_ge\n" +
          "All values are f32 bit patterns. Most user code uses the BCPL\n" +
          "FLT operators (#:= #+ #- etc) which compile to these calls.",
  },
  Sys_pollsardch: { sig: "sys(Sys_pollsardch) → ch", cat: "syscall", desc: "Non-blocking char read; -3 if none available." },

  // Low-level trace / profiling primitives. Cintsys hooks several of
  // these into the interpreter loop; the playground runs compiled wasm
  // directly so per-instruction hooks (tracing / watch / tally) stay
  // NOOPs. The trace-buffer trio (trpush / settrcount / gettrval) is
  // pure data and works as documented in the BCPL manual.
  Sys_tracing: {
    sig: "sys(Sys_tracing, val) → 0",
    cat: "debug",
    desc: "Cintsys: toggle per-Cintcode-instruction trace output. NOOP in playground — no per-instruction hook exists in compiled wasm. Use the Debugger toggle + breakpoints + Step for per-statement tracing.",
  },
  Sys_watch: {
    sig: "sys(Sys_watch, addr) → 0",
    cat: "debug",
    desc: "Cintsys: trap when the word at addr changes. NOOP in playground — no per-instruction hook. Closest substitute: bp on the statement that writes the value, then inspect the Memory tab.",
  },
  Sys_tally: {
    sig: "sys(Sys_tally, val) → 0",
    cat: "debug",
    desc: "Cintsys: enable/clear the Cintcode frequency-count vector. NOOP in playground — no per-instruction hook.",
  },
  Sys_trpush: {
    sig: "sys(Sys_trpush, val) → 0",
    cat: "debug",
    desc: "Push val into the 4096-slot circular trace buffer at position (trcount MOD 4096), increment trcount. Disabled while trcount < 0 (set via Sys_settrcount). Implemented natively.",
  },
  Sys_settrcount: {
    sig: "sys(Sys_settrcount, count) → prev",
    cat: "debug",
    desc: "Replace the private trcount cursor; returns the previous value. A negative value disables Sys_trpush. Implemented natively.",
  },
  Sys_gettrval: {
    sig: "sys(Sys_gettrval, count) → val",
    cat: "debug",
    desc: "Read the trace buffer at position (count MOD 4096). Usually called with tracing disabled (negative trcount). Implemented natively.",
  },
  Sys_incdcount: {
    sig: "sys(Sys_incdcount, n) → 0",
    cat: "debug",
    desc: "Bump debug counter slot n. Counters live in an internal Map (keyed by n) — Cintsys puts them in rootnode!rtn_dcountv. Inspect via JS console or a custom diagnostic print.",
  },
  Sys_dumpmem: {
    sig: "sys(Sys_dumpmem, context) → 0",
    cat: "debug",
    desc: "Cintsys writes the whole Cintcode memory image to DUMP.mem. Currently a NOOP in playground — use the Memory tab + crashSnapshot for live inspection.",
  },
  Sys_memmovewords:{ sig: "sys(Sys_memmovewords, dst, src, n)", cat: "syscall", desc: "memmove n words; handles overlap correctly." },
  Sys_memmovebytes:{ sig: "sys(Sys_memmovebytes, dst, src, n)", cat: "syscall", desc: "memmove n bytes (byte-addressed); handles overlap." },
  Sys_errwrch: { sig: "sys(Sys_errwrch, ch)", cat: "syscall", desc: "Same sink as wrch in playground." },

  // ---- Asset access (playground-specific) ----
  Sys_assetlist: {
    sig: "sys(Sys_assetlist, buf) → totlen",
    cat: "syscall",
    desc: "Write comma-separated list of uploaded asset names into BCPL string buf. " +
          "buf%0 is set to the total length. Iterate to find images / .wad / .sf2 / .ogg.",
  },
  Sys_assetload: {
    sig: "sys(Sys_assetload, name_str, info) → ok",
    cat: "syscall",
    desc: "Materialise the named asset into wasm memory. info gets filled: " +
          "info!0 = total byte length, info!1 = 0 for binary asset OR (w<<16)|h for image, " +
          "info!2 = byte address of the bytes (binary) or packed RGBA (image). Returns TRUE on hit.",
  },

  // ---- Rendering syscalls (used by raycaster / Doom engine) ----
  Sys_setbgtex: {
    sig: "sys(Sys_setbgtex, slot, base, w, h)",
    cat: "graphics",
    desc: "Cache a background texture (sky / floor cylinder) at slot 0..3 for later drawskyspan ops.",
  },
  Sys_drawcols: {
    sig: "sys(Sys_drawcols, col, y0, y1, top_col, bot_col)",
    cat: "graphics",
    desc: "Paint one screen column as a vertical gradient strip (split sky/floor fill).",
  },
  Sys_drawtex: {
    sig: "sys(Sys_drawtex, col, y0, y1, tex_base, u, v_step, pkd)",
    cat: "graphics",
    desc: "Textured single-column wall slice. pkd = (w<<16)|h. Bilinear sampling off.",
  },
  Sys_drawtexcol: {
    sig: "sys(Sys_drawtexcol, col, top, h, tex_base, pkd, tex_x)",
    cat: "graphics",
    desc: "Vertical-strip wall column. h-pixel scaled to fill from (top, top+h).",
  },
  Sys_drawwallcol: {
    sig: "sys(Sys_drawwallcol, col, y0, y1, y_anchor, v_step_q16, texX, tex_base, pkd)",
    cat: "graphics",
    desc: "Doom-style wall column. v_step_raw < 0 enables transparency. tex_base is word addr of packed RGBA.",
  },
  Sys_drawflatspan: {
    sig: "sys(Sys_drawflatspan, col, y0, y1, cam_above, px, py, raydxy_pkd, flat_base)",
    cat: "graphics",
    desc: "Textured floor/ceiling span for one column. cam_above > 0 → floor, < 0 → ceiling.",
  },
  Sys_drawskyspan: {
    sig: "sys(Sys_drawskyspan, col, y0, y1, ray_ang)",
    cat: "graphics",
    desc: "Panoramic-sky span from the bg-tex cached at slot 0 (set via Sys_setbgtex).",
  },
  Sys_setlight: {
    sig: "sys(Sys_setlight, light_0_255)",
    cat: "graphics",
    desc: "Cache the light scale for the NEXT drawwallcol / drawflatspan call. " +
          "256 = full bright (multiply identity for 255-mapped channels).",
  },
  Sys_setdepth: {
    sig: "sys(Sys_setdepth, cy)",
    cat: "graphics",
    desc: "Cache the per-column depth (world units) the next opaque drawwallcol / drawflatspan " +
          "writes into the z-buffer (and that sprite-mode drawwallcol tests against).",
  },
  Sys_clearzbuf: {
    sig: "sys(Sys_clearzbuf)",
    cat: "graphics",
    desc: "Reset the z-buffer to +infinity and wipe the back framebuffer. Call once per frame " +
          "before drawing walls/flats; any column not subsequently touched shows black instead " +
          "of last frame's pixels.",
  },

  // ---- Audio (Sys_playmusic / Sys_playmus / Sys_loadsf2) ----
  Sys_playmusic: {
    sig: "sys(Sys_playmusic, name_str, loop_flag)",
    cat: "audio",
    desc: "Play a binary audio asset (.ogg / .mp3 / .wav / .flac) via HTMLAudio. " +
          "loop_flag = 1 loops forever. Replaces any current track.",
  },
  Sys_stopmusic: {
    sig: "sys(Sys_stopmusic)",
    cat: "audio",
    desc: "Silence the current music track (HTMLAudio + MUS oscillator + SF2 sequencer).",
  },
  Sys_playmus: {
    sig: "sys(Sys_playmus, word_base, byte_off, byte_size, loop)",
    cat: "audio",
    desc: "Play a Doom MUS-format lump straight out of wasm memory (no asset upload). " +
          "Routes through spessasynth if a SoundFont was loaded via Sys_loadsf2, otherwise falls " +
          "back to the built-in oscillator synth (drum channel 15 = noise bursts).",
  },
  Sys_loadsf2: {
    sig: "sys(Sys_loadsf2, name_str) → ok",
    cat: "audio",
    desc: "Load a binary asset (.sf2) as the active SoundFont for Sys_playmus. " +
          "First call lazily boots the AudioWorklet (async). Returns 1 if the asset existed " +
          "and was queued for loading, 0 otherwise.",
  },

  // ---- Debug-mode helpers (set by codegen, not by user) ----
  bcpl_break: {
    sig: "(call $__break)  -- emitted automatically at every statement",
    cat: "debug",
    desc: "Host-imported debug hook. In normal (non-Debugger) runs this is a near-free no-op. " +
          "When the user has armed at least one breakpoint AND the program was assembled with " +
          "asyncify (Debug mode), imp_break suspends execution; the host's Continue / Step " +
          "buttons drive resumption.",
  },

  // ---- Manifest constants (from libhdr) ----
  bytesperword: {
    sig: "bytesperword",
    cat: "constants",
    desc: "Bytes in a BCPL word. 4 on the wasm target (T32). Used for byte ↔ word address conversions.",
  },
  bitsperbyte: {
    sig: "bitsperbyte = 8",
    cat: "constants",
    desc: "Always 8.",
  },
  bitsperword: {
    sig: "bitsperword",
    cat: "constants",
    desc: "bitsperbyte * bytesperword. 32 on the wasm target.",
  },
  BITSPERBCPLWORD: {
    sig: "BITSPERBCPLWORD",
    cat: "constants",
    desc: "Language-level constant (a keyword) equal to bitsperword. Resolved at compile time.",
  },
  mcaddrinc: {
    sig: "mcaddrinc",
    cat: "constants",
    desc: "Machine-address increment per pointer step = bytesperword.",
  },
  minint: {
    sig: "minint",
    cat: "constants",
    desc: "Most-negative signed integer (1<<(bitsperword-1)). −2147483648 on T32.",
  },
  maxint: {
    sig: "maxint",
    cat: "constants",
    desc: "Most-positive signed integer (minint − 1). 2147483647 on T32.",
  },
  endstreamch: {
    sig: "endstreamch = -1",
    cat: "constants",
    desc: "Character value rdch returns at end-of-stream.",
  },
  timeoutch: {
    sig: "timeoutch = -2",
    cat: "constants",
    desc: "rdch return value when a polled read timed out (kbd / serial drivers; unused in the playground).",
  },
  pollingch: {
    sig: "pollingch = -3",
    cat: "constants",
    desc: "rdch / Sys_pollsardch return value when no char is currently available.",
  },
  TRUE: {
    sig: "TRUE",
    cat: "constants",
    desc: "BCPL boolean true. Equal to −1 (all-ones); the language uses bitwise truthiness.",
  },
  FALSE: {
    sig: "FALSE",
    cat: "constants",
    desc: "BCPL boolean false. Equal to 0.",
  },
  tg: {
    sig: "tg = 200",
    cat: "constants",
    desc: "First user-reserved global slot that survives between CLI commands. Library authors " +
          "pick slot numbers ≥ tg to avoid stomping on stdlib globals (G!1..G!130-ish).",
  },
  ug: {
    sig: "ug = 210",
    cat: "constants",
    desc: "First user global the CLI resets on every command. Use ug+ for short-lived state.",
  },
  g_globsize: {
    sig: "g_globsize = 0",
    cat: "constants",
    desc: "G!0 — total size of the global vector. Reserved by the runtime; not user-writable.",
  },
  g_sys: {
    sig: "g_sys = 3",
    cat: "constants",
    desc: "G!3 — table index of the sys() function. Used internally by FNAP dispatch.",
  },
  g_currco: {
    sig: "g_currco = 7",
    cat: "constants",
    desc: "G!7 — currently-active coroutine handle, or 0 for the root context.",
  },
  g_colist: {
    sig: "g_colist = 8",
    cat: "constants",
    desc: "G!8 — head of the active coroutine list. Reserved.",
  },
  g_rootnode: {
    sig: "g_rootnode = 9",
    cat: "constants",
    desc: "G!9 — pointer to the system rootnode struct (Cintpos compat). Unused in playground but reserved.",
  },
  g_result2: {
    sig: "g_result2 = 10",
    cat: "constants",
    desc: "G!10 — secondary return slot. Many stdlib functions (muldiv, string_to_number, …) " +
          "stash extra info here, accessed via the BCPL `result2` global name.",
  },
  g_memsize: {
    sig: "g_memsize = 14",
    cat: "constants",
    desc: "G!14 — currentdir pointer (BCPL string). Set / read by Sys_setprefix / Sys_getprefix.",
  },
  g_keyboard: {
    sig: "g_keyboard = 20",
    cat: "constants",
    desc: "G!20 — keyboard stream handle (= stdin in playground).",
  },
  g_screen: {
    sig: "g_screen = 21",
    cat: "constants",
    desc: "G!21 — screen stream handle (= stdout in playground).",
  },
  co_pptr: {
    sig: "co_pptr = 0",
    cat: "constants",
    desc: "Coroutine struct slot 0: parent-frame pointer.",
  },
  co_parent: {
    sig: "co_parent",
    cat: "constants",
    desc: "Coroutine struct slot: parent coroutine handle.",
  },
  co_list: {
    sig: "co_list",
    cat: "constants",
    desc: "Coroutine struct slot: link to next coroutine in the global list.",
  },
  co_fn: {
    sig: "co_fn",
    cat: "constants",
    desc: "Coroutine struct slot: body function pointer (G!N indirection).",
  },
  co_size: {
    sig: "co_size",
    cat: "constants",
    desc: "Coroutine struct slot: stack size in words.",
  },
  co_c: {
    sig: "co_c",
    cat: "constants",
    desc: "Coroutine struct slot: self-pointer (handle).",
  },
  InitObj: {
    sig: "InitObj = 0",
    cat: "constants",
    desc: "Object-method-vector index reserved for the initialiser. Used by the OO demo idiom.",
  },
  CloseObj: {
    sig: "CloseObj = 1",
    cat: "constants",
    desc: "Object-method-vector index reserved for the finaliser.",
  },
  rootnodeaddr: {
    sig: "rootnodeaddr = 100",
    cat: "constants",
    desc: "Legacy Cintpos compat — byte address of the rootnode in cintsys. Unused on wasm.",
  },
  t_hunk:    { sig: "t_hunk = 1000",  cat: "constants", desc: "Object-module hunk type: code in ASCII hex (32-bit Cintcode)." },
  t_reloc:   { sig: "t_reloc = 1001", cat: "constants", desc: "Object-module reloc-table type." },
  t_end:     { sig: "t_end = 1002",   cat: "constants", desc: "Object-module end-marker." },
  t_hunk64:  { sig: "t_hunk64 = 2000",  cat: "constants", desc: "64-bit Cintcode hunk type." },
  t_reloc64: { sig: "t_reloc64 = 2001", cat: "constants", desc: "64-bit reloc table." },
  t_end64:   { sig: "t_end64 = 2002",   cat: "constants", desc: "64-bit end marker." },
  t_bhunk:   { sig: "t_bhunk = 3000",   cat: "constants", desc: "Binary 32-bit hunk type." },
  t_bhunk64: { sig: "t_bhunk64 = 4000", cat: "constants", desc: "Binary 64-bit hunk type." },
  globword:  { sig: "globword",  cat: "constants", desc: "Magic stamp written at the top of the global vector for sanity checks." },
  stackword: { sig: "stackword", cat: "constants", desc: "Magic stamp written into freshly-allocated stack frames." },
  deadcode:  { sig: "deadcode",  cat: "constants", desc: "Magic value 0xDEADC0DE used to fill uninitialised regions for debugging." },
  sectword:  { sig: "sectword",  cat: "constants", desc: "Magic 0xFDDF — marks a SECTION boundary in object hunks." },
  entryword: { sig: "entryword", cat: "constants", desc: "Magic 0xDFDF — marks a function entry point in object hunks." },

  sdle_active:         { sig: "sdle_active = 1",          cat: "constants", desc: "sdl_pollevent event type: window focus change." },
  sdle_keydown:        { sig: "sdle_keydown = 2",         cat: "constants", desc: "sdl_pollevent event type: key pressed. v[1]=mod, v[2]=keyCode." },
  sdle_keyup:          { sig: "sdle_keyup = 3",           cat: "constants", desc: "sdl_pollevent event type: key released." },
  sdle_mousemotion:    { sig: "sdle_mousemotion = 4",     cat: "constants", desc: "sdl_pollevent event type: mouse moved. v[1]=x, v[2]=y." },
  sdle_mousebuttondown:{ sig: "sdle_mousebuttondown = 5", cat: "constants", desc: "sdl_pollevent event type: mouse button pressed. v[1]=button bits." },
  sdle_mousebuttonup:  { sig: "sdle_mousebuttonup = 6",   cat: "constants", desc: "sdl_pollevent event type: mouse button released." },
  sdle_quit:           { sig: "sdle_quit = 12",           cat: "constants", desc: "sdl_pollevent event type: window close requested." },
};
