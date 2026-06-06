// BCPL-wasm runtime: host-provided stdlib + loader.
//
// Each generated .wasm module imports a small fixed stdlib from "env"
// (see bcplcgwasm.b emit_mod_header). All imports share the type
// (func (result i32)) — no parameters. Callers pass arguments through
// BCPL's stack-frame memory following the same convention as
// generated code:
//   - before call_indirect: store args at P!(k+3..), save (old_P, 0,
//     tidx) at P!(k..k+2), advance P by k.
//   - callee: read args at P!3.., compute, restore P from P!0,
//     return result as i32.
//
// Host stdlib follows the same convention: read args from memory
// relative to the current P, restore P, return result.

// Browser storage shim. Uses localStorage when available (browser),
// otherwise an in-memory Map (Node tests). Keys namespaced under
// "bcpl:" so other app data isn't touched.
// Keys starting with this prefix are compiler intermediates (WAT/OBJ
// scratch).  They can be huge (800KB+) on big Doom examples, so we
// always route them to an in-memory map even when localStorage is
// available — otherwise a few compiles in a row will blow the ~5MB
// localStorage quota.
const SCRATCH_PREFIX = "__out_";
export const storageBackend = (() => {
  const mem = new Map();
  const isScratch = (k) => typeof k === "string" && k.startsWith(SCRATCH_PREFIX);
  let local = null;
  try {
    if (typeof localStorage !== "undefined") local = localStorage;
  } catch { /* fallthrough */ }
  // Sweep any stale scratch blobs that landed in localStorage from
  // previous builds (before scratch routing existed).  Frees quota
  // for actual persistent files.
  if (local) {
    try {
      const stale = [];
      for (let i = 0; i < local.length; i++) {
        const k = local.key(i);
        if (k && k.startsWith("bcpl:" + SCRATCH_PREFIX)) stale.push(k);
      }
      for (const k of stale) local.removeItem(k);
    } catch { /* ignore */ }
  }
  return {
    get: (k) => {
      if (isScratch(k) || !local) return mem.has(k) ? mem.get(k) : null;
      return local.getItem("bcpl:" + k);
    },
    set: (k, v) => {
      if (isScratch(k) || !local) { mem.set(k, v); return; }
      try { local.setItem("bcpl:" + k, v); }
      catch { mem.set(k, v); }   // quota / SecurityError fallback
    },
    del: (k) => {
      if (isScratch(k) || !local) { mem.delete(k); return; }
      local.removeItem("bcpl:" + k);
    },
  };
})();

// Convert a Doom MUS lump to a standard SMF type-0 MIDI buffer.
// MUS event types map onto MIDI status nibbles 8x/9x/Bx/Cx/Ex; channel
// 15 in MUS is the percussion channel (MIDI channel 9, 0-indexed). MUS
// runs at 140 ticks/sec; we emit a tempo meta-event so SMF division of
// 70 ticks/quarter yields 500000 us/quarter (= 120 BPM, 140 Hz frames).
// Returns Uint8Array of MIDI bytes, or null on parse failure.
export function mus2mid(bytes) {
  if (!bytes || bytes.length < 16) return null;
  if (bytes[0] !== 0x4D || bytes[1] !== 0x55 ||
      bytes[2] !== 0x53 || bytes[3] !== 0x1A) return null;
  const dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const scoreStart = dv.getUint16(6, true);

  // Mapping MUS channel -> MIDI channel. MUS reserves channel 15 for
  // percussion; MIDI uses 9. We assign MIDI channels lazily so the
  // first MUS channel we see becomes MIDI 0, etc., skipping 9 which
  // is always percussion.
  const chanMap = new Array(16).fill(-1);
  chanMap[15] = 9;
  let nextMidi = 0;
  const getMidiCh = (musCh) => {
    if (chanMap[musCh] !== -1) return chanMap[musCh];
    while (nextMidi === 9) nextMidi++;
    if (nextMidi > 15) nextMidi = 15;
    chanMap[musCh] = nextMidi++;
    return chanMap[musCh];
  };

  // MUS controller index -> MIDI CC number.
  const ctrlMap = [0, 0, 1, 7, 10, 11, 91, 93, 64, 67, 120, 123, 126, 127, 121];

  // Track: pairs of [delta-ticks, eventBytes...].
  const track = [];
  const lastVel = new Array(16).fill(64);
  let p = scoreStart;
  let delta = 0;
  let done = false;
  while (p < bytes.length && !done) {
    const ctrl = bytes[p++];
    const last = ctrl & 0x80;
    const type = (ctrl >> 4) & 0x07;
    const ch = ctrl & 0x0F;
    let evt = null;
    switch (type) {
      case 0: {              // note off
        const n = bytes[p++] & 0x7F;
        const mc = getMidiCh(ch);
        evt = [0x80 | mc, n, 0];
        break;
      }
      case 1: {              // note on (+ optional velocity)
        const nb = bytes[p++];
        const note = nb & 0x7F;
        if (nb & 0x80) lastVel[ch] = bytes[p++] & 0x7F;
        const mc = getMidiCh(ch);
        evt = [0x90 | mc, note, lastVel[ch]];
        break;
      }
      case 2: {              // pitch wheel: MUS 0..255 -> MIDI 14-bit
        const pw = bytes[p++];
        const v = pw * 64;   // 128 = center -> 8192
        const mc = getMidiCh(ch);
        evt = [0xE0 | mc, v & 0x7F, (v >> 7) & 0x7F];
        break;
      }
      case 3: {              // system event (controller number, no value)
        const cn = bytes[p++];
        if (cn >= 10 && cn <= 14) {
          const mc = getMidiCh(ch);
          evt = [0xB0 | mc, ctrlMap[cn], 0];
        }
        break;
      }
      case 4: {              // controller change
        const cn = bytes[p++];
        const val = bytes[p++] & 0x7F;
        const mc = getMidiCh(ch);
        if (cn === 0) {
          evt = [0xC0 | mc, val];   // program change
        } else if (cn < ctrlMap.length) {
          evt = [0xB0 | mc, ctrlMap[cn], val];
        }
        break;
      }
      case 6: done = true; break;
      default: /* 5,7 ignored */ break;
    }

    if (evt) {
      track.push({ delta, bytes: evt });
      delta = 0;
    }

    if (last && !done) {
      let d = 0;
      while (p < bytes.length) {
        const b = bytes[p++];
        d = (d << 7) | (b & 0x7F);
        if (!(b & 0x80)) break;
      }
      delta += d;
    }
  }

  // Emit SMF.
  const writeVlq = (out, v) => {
    const stack = [v & 0x7F];
    v >>= 7;
    while (v > 0) { stack.push((v & 0x7F) | 0x80); v >>= 7; }
    for (let i = stack.length - 1; i >= 0; i--) out.push(stack[i]);
  };
  const body = [];
  // Tempo meta (500000 us per quarter = 120 BPM).
  body.push(0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20);
  for (const ev of track) {
    writeVlq(body, ev.delta);
    for (const b of ev.bytes) body.push(b);
  }
  // End of track meta.
  body.push(0x00, 0xFF, 0x2F, 0x00);

  const trkLen = body.length;
  const out = new Uint8Array(14 + 8 + trkLen);
  let i = 0;
  // MThd
  out.set([0x4D, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 0, 0, 1, 0, 70], 0); i = 14;
  out.set([0x4D, 0x54, 0x72, 0x6B,
           (trkLen >> 24) & 0xFF, (trkLen >> 16) & 0xFF,
           (trkLen >> 8) & 0xFF, trkLen & 0xFF], i); i += 8;
  for (let j = 0; j < trkLen; j++) out[i + j] = body[j];
  return out;
}

// Spessasynth wrapper: lazy-init the AudioWorklet + WorkletSynthesizer
// + Sequencer on first SF2 load. Subsequent Sys_playmus calls route
// through here instead of the oscillator fallback. The class only
// pulls vendor/spessasynth.js when actually needed — avoids loading
// ~1MB of JS for examples that never touch SF2.
class SF2MusPlayer {
  constructor(audioCtx) {
    this.ctx = audioCtx;
    this.ready = false;
    this.synth = null;
    this.seq = null;
    this.SequencerCtor = null;
    this.pending = null;     // {midi, loop} queued during load
  }
  async init() {
    if (this.ready) return true;
    const mod = await import("./vendor/spessasynth.js");
    await this.ctx.audioWorklet.addModule("./vendor/spessasynth_processor.min.js");
    this.synth = new mod.WorkletSynthesizer(this.ctx);
    await this.synth.isReady;
    this.synth.connect(this.ctx.destination);
    this.SequencerCtor = mod.Sequencer;
    return true;
  }
  async loadSF2(buffer) {
    await this.init();
    await this.synth.soundBankManager.addSoundBank(buffer, "main");
    this.ready = true;
    if (this.pending) {
      const { midi, loop } = this.pending;
      this.pending = null;
      this._playNow(midi, loop);
    }
    return true;
  }
  // Caller may invoke before loadSF2 has resolved; we stash and run
  // automatically once the worklet + soundbank are live.
  playMidi(midiBytes, loop) {
    if (!this.ready) {
      this.pending = { midi: midiBytes, loop };
      return true;     // accepted (queued)
    }
    this._playNow(midiBytes, loop);
    return true;
  }
  _playNow(midiBytes, loop) {
    if (!this.seq) this.seq = new this.SequencerCtor(this.synth);
    this.seq.loopCount = loop ? -1 : 0;
    const buf = midiBytes.buffer.slice(midiBytes.byteOffset,
                                       midiBytes.byteOffset + midiBytes.byteLength);
    this.seq.loadNewSongList([{ binary: buf, fileName: "song.mid" }]);
    this.seq.play();
  }
  // True once usable for fresh play() calls. Distinct from .ready
  // (which means SF2 is loaded); .loading means loadSF2 is in flight
  // and we should defer to it rather than start the oscillator.
  get loading() {
    return this.pending !== null || this._loadInflight;
  }
  stop() {
    this.pending = null;
    if (this.seq) {
      try { this.seq.pause(); } catch {}
    }
  }
}

// Minimal Doom MUS-format player. Reads an in-memory MUS lump and
// drives a tiny oscillator-based polyphonic synth on Web Audio — no
// SoundFont needed, so it's self-contained. Note: this only renders
// pitched tones and a noise-burst on channel 15 for percussion. Real
// instrument patches are ignored.
class MusPlayer {
  constructor(audioCtx, bytes, loop = true) {
    this.ctx    = audioCtx;
    this.events = this.parseMus(bytes);
    this.loop   = loop;
    this.channels = new Array(16).fill(null).map(() => ({
      vol: 0.6, oscs: new Map(),
    }));
    this.playing = false;
    this.timer   = null;
    this.startTime = 0;
    this.eventIdx  = 0;
    this.songTicks = 0;
    if (this.events.length) {
      this.songTicks = this.events[this.events.length - 1].t + 35;
    }
  }

  parseMus(bytes) {
    if (!bytes || bytes.length < 16) return [];
    if (bytes[0] !== 0x4D || bytes[1] !== 0x55 ||
        bytes[2] !== 0x53 || bytes[3] !== 0x1A) return [];
    const dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    const scoreStart = dv.getUint16(6, true);
    const events = [];
    let p = scoreStart, t = 0;
    while (p < bytes.length) {
      const ctrl = bytes[p++];
      const last = ctrl & 0x80;
      const type = (ctrl >> 4) & 0x07;
      const ch   = ctrl & 0x0F;
      switch (type) {
        case 0: { // release
          const n = bytes[p++] & 0x7F;
          events.push({ t, type: 'off', ch, note: n });
          break;
        }
        case 1: { // play
          const nb = bytes[p++];
          const note = nb & 0x7F;
          let vel = 100;
          if (nb & 0x80) vel = bytes[p++] & 0x7F;
          events.push({ t, type: 'on', ch, note, vel });
          break;
        }
        case 2: p++; break;   // pitch wheel (ignored)
        case 3: p++; break;   // system event (ignored)
        case 4: {             // controller
          const cn = bytes[p++];
          const val = bytes[p++];
          if (cn === 3) events.push({ t, type: 'vol', ch, val });
          break;
        }
        case 6: return events; // end
        case 7: break;
      }
      if (last) {
        let d = 0;
        while (p < bytes.length) {
          const b = bytes[p++];
          d = (d << 7) | (b & 0x7F);
          if (!(b & 0x80)) break;
        }
        t += d;
      }
    }
    return events;
  }

  play() {
    if (!this.events.length) return;
    this.stop();
    this.playing = true;
    this.startTime = this.ctx.currentTime + 0.05;
    this.eventIdx = 0;
    this._tick();
  }

  _tick() {
    if (!this.playing) return;
    const tickSec = 1 / 140;
    const horizon = this.ctx.currentTime + 0.4;
    while (this.eventIdx < this.events.length) {
      const ev = this.events[this.eventIdx];
      const evTime = this.startTime + ev.t * tickSec;
      if (evTime > horizon) break;
      this._handle(ev, Math.max(evTime, this.ctx.currentTime));
      this.eventIdx++;
    }
    if (this.eventIdx >= this.events.length) {
      if (this.loop && this.songTicks > 0) {
        this.startTime += this.songTicks * tickSec;
        this.eventIdx = 0;
      } else {
        this.playing = false;
        return;
      }
    }
    this.timer = setTimeout(() => this._tick(), 180);
  }

  _handle(ev, time) {
    const ch = this.channels[ev.ch];
    if (ev.type === 'on') {
      // Drum channel (15) gets a short noise burst instead of a pitch.
      if (ev.ch === 15) {
        const dur = 0.08;
        const bufLen = Math.max(1, Math.floor(this.ctx.sampleRate * dur));
        const buf = this.ctx.createBuffer(1, bufLen, this.ctx.sampleRate);
        const d = buf.getChannelData(0);
        for (let i = 0; i < bufLen; i++) {
          d[i] = (Math.random() * 2 - 1) * (1 - i / bufLen);
        }
        const src = this.ctx.createBufferSource();
        const gain = this.ctx.createGain();
        src.buffer = buf;
        gain.gain.value = (ev.vel / 127) * ch.vol * 0.18;
        src.connect(gain).connect(this.ctx.destination);
        src.start(time);
        return;
      }
      const freq = 440 * Math.pow(2, (ev.note - 69) / 12);
      const osc  = this.ctx.createOscillator();
      const gain = this.ctx.createGain();
      osc.type = 'triangle';
      osc.frequency.value = freq;
      const vol = (ev.vel / 127) * ch.vol * 0.08;
      gain.gain.setValueAtTime(0, time);
      gain.gain.linearRampToValueAtTime(vol, time + 0.012);
      osc.connect(gain).connect(this.ctx.destination);
      osc.start(time);
      // Replace any in-flight note of same pitch on this channel.
      const prev = ch.oscs.get(ev.note);
      if (prev) {
        try { prev.gain.gain.setTargetAtTime(0, time, 0.01); prev.osc.stop(time + 0.05); } catch {}
      }
      ch.oscs.set(ev.note, { osc, gain });
    } else if (ev.type === 'off') {
      const e = ch.oscs.get(ev.note);
      if (e) {
        try {
          e.gain.gain.setTargetAtTime(0, time, 0.02);
          e.osc.stop(time + 0.2);
        } catch {}
        ch.oscs.delete(ev.note);
      }
    } else if (ev.type === 'vol') {
      ch.vol = ev.val / 127;
    }
  }

  stop() {
    this.playing = false;
    if (this.timer) { clearTimeout(this.timer); this.timer = null; }
    for (const ch of this.channels) {
      for (const e of ch.oscs.values()) {
        try { e.osc.stop(); } catch {}
      }
      ch.oscs.clear();
    }
  }
}

// Binary asset registry (textures etc.). In-memory only — bundles are
// the persistence path. Two record shapes:
//   image:  { w, h, rgba: Uint8Array(w*h*4) }    — RGBA byte order
//   binary: { bytes: Uint8Array }                — arbitrary blob (WADs, etc.)
// Sys_assetload returns image data as packed words; binary as raw
// bytes (info!0 = byte length, info!1 = 0).
export const assetBackend = (() => {
  const mem = new Map();
  const toB64 = (u8) => {
    let bin = "";
    for (let i = 0; i < u8.length; i++) bin += String.fromCharCode(u8[i]);
    return btoa(bin);
  };
  const fromB64 = (s) => {
    const bin = atob(s);
    const u8 = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i);
    return u8;
  };
  return {
    list: () => Array.from(mem.keys()),
    get: (name) => mem.get(name) ?? null,
    set: (name, rec) => mem.set(name, rec),
    del: (name) => mem.delete(name),
    clear: () => mem.clear(),
    serialise: () => {
      const out = {};
      for (const [k, v] of mem) {
        if (v.bytes) {
          out[k] = { kind: "binary", bytes_b64: toB64(v.bytes) };
        } else {
          out[k] = { w: v.w, h: v.h, rgba_b64: toB64(v.rgba) };
        }
      }
      return out;
    },
    deserialise: (obj) => {
      mem.clear();
      for (const [k, v] of Object.entries(obj)) {
        if (v.kind === "binary" || v.bytes_b64) {
          mem.set(k, { bytes: fromB64(v.bytes_b64) });
        } else {
          mem.set(k, { w: v.w, h: v.h, rgba: fromB64(v.rgba_b64) });
        }
      }
    },
  };
})();

// Decode an image File/Blob to { w, h, rgba } via OffscreenCanvas.
// Caller awaits — used by the Assets UI on upload.
export async function decodeImageToAsset(blob) {
  const bitmap = await createImageBitmap(blob);
  const oc = (typeof OffscreenCanvas === "function")
    ? new OffscreenCanvas(bitmap.width, bitmap.height)
    : Object.assign(document.createElement("canvas"),
                    { width: bitmap.width, height: bitmap.height });
  const ctx = oc.getContext("2d");
  ctx.drawImage(bitmap, 0, 0);
  const img = ctx.getImageData(0, 0, bitmap.width, bitmap.height);
  return { w: bitmap.width, h: bitmap.height, rgba: new Uint8Array(img.data.buffer) };
}

export class BcplRuntime {
  constructor(writeOut, input = "") {
    this.writeOut = writeOut;   // (string) => void — UI sink for stdout
    this.input = input;         // stdin buffer — consumed by rdch
    this.inputIdx = 0;
    this.instance = null;
    this.mem = null;
    this.memView = null;
    this.finished = false;
    // Heap grows downward from top of linear memory.
    this.heapTop = 0;
    this.freeList = 0;
    // Side table for getvec block sizes. Was stored at memory word
    // (p+1), but that's INSIDE the user-allocated range — programs that
    // write to vec!1 (very common) corrupted the size header, which
    // broke freelist scans after the second getvec/freevec cycle.
    // Side-table keeps user memory pristine.
    this.vecSizes = new Map();
    // Streams. Handles passed back to BCPL are POINTERS to SCB
    // structs allocated in linear memory (so user code can read
    // s!scb_pos / s!scb_end / s!scb_id directly, matching cintsys
    // semantics from g/libhdr.h).
    //
    //   _scbToStream: Map<scbPtr → record>
    //   record       = { kind, mode, name, data, pos, scbPtr }
    //   curIn/curOut = scbPtrs of stdin/stdout (allocated in initMaster)
    this._scbToStream = new Map();
    this.curOut = 0;             // populated in initMaster
    this.curIn  = 0;
    // SDL / canvas state. setSdlCanvas(canvasEl, onShow) wires it up
    // before run(). sdlCtx is the 2D context; sdlSurfaces maps surface
    // handle → { ctx, w, h, kind } records.
    this.sdlCanvas = null;
    this.sdlCtx    = null;
    this.sdlEvents = [];        // queued events (each = { type, args... })
    this.sdlMouse  = { x: 0, y: 0, buttons: 0 };
    this.sdlKeys   = new Set();
    this.sdlStartTime = 0;
    this.sdlOnShow = null;      // callback: () => void  (toggles visible)
    this.sdlCurrentColor = 0xFFFFFFFF; // packed RGBA
    this.aborted = false;       // set true by abort(); checked between yields
  }

  // Request the running program to stop. Effective at the next
  // asyncify yield point (delay, cowait, etc.) — the run() loop sees
  // the flag during its resume cycle and throws BcplHalt to unwind.
  // Synchronous tight loops without yield points cannot be aborted
  // (JS is single-threaded; the wasm call has to return on its own).
  abort() {
    this.aborted = true;
    // If currently paused at a breakpoint, unblock the run loop so
    // it can see the aborted flag and exit cleanly. Without this,
    // Stop-while-paused leaves the run loop awaiting forever.
    if (this._pauseResolve) {
      const r = this._pauseResolve;
      this._pauseResolve = null;
      this._pausePromise = null;
      this._pausedLine = 0;
      r();
    }
    // Silence any in-flight audio. MusPlayer + SF2MusPlayer schedule
    // notes on AudioContext that keep playing after the wasm program
    // halts; without this, Stop leaves background music running until
    // the page reloads.
    try {
      if (this._musicAudio) {
        this._musicAudio.pause();
        this._musicAudio = null;
      }
      if (this._musicURL) {
        URL.revokeObjectURL(this._musicURL);
        this._musicURL = null;
      }
      if (this._musPlayer) {
        this._musPlayer.stop();
        this._musPlayer = null;
      }
      if (this._sf2Player) this._sf2Player.stop();
    } catch { /* swallow */ }
  }

  // Read an arbitrary slice of linear memory as i32 words. Used by
  // the host's Memory tab to render hex dumps without exposing the
  // raw memView (which is a typed array over a SharedArrayBuffer-ish
  // surface that can detach on memory.grow).
  readWords(startWord, countWords) {
    const out = new Int32Array(Math.max(0, countWords | 0));
    if (!this.memView) return out;
    // memView is a DataView — read i32s via getInt32, not array
    // indexing. byteLength bounds the safe range.
    const maxWord = (this.memView.byteLength / 4) | 0;
    for (let i = 0; i < out.length; i++) {
      const w = (startWord | 0) + i;
      if (w < 0 || w >= maxWord) break;
      out[i] = this.memView.getInt32(w * 4, true);
    }
    return out;
  }

  // Live state snapshot for the Memory tab. Cheaper than
  // crashSnapshot — just the region indices needed to drive the UI,
  // no per-region word copies. Caller pulls actual words via
  // readWords() so it can paginate without copying multi-MB blobs.
  memLayout() {
    return {
      P: this.P | 0,
      G: 1,                              // global vec base (word addr)
      gLen: 1000,
      staticBase: 1001,
      staticTop: this.nextStaticWord | 0,
      heapTop: this.heapTop | 0,
      freeList: this.freeList | 0,
      memBytes: this.mem?.buffer?.byteLength | 0,
      line: this.currentLine(),
    };
  }

  // Most-recent BCPL source line touched by the running program.
  // Backend emits `(global.set $__line (i32.const N))` at every
  // statement boundary; the host reads it whenever the program is
  // suspended or crashes so the UI can highlight where execution is.
  // Returns 0 before any statement runs (also when the program has
  // no s_line markers — e.g. older pre-debug builds).
  currentLine() {
    const g = this.master?.exports?.__line;
    return g ? (g.value | 0) : 0;
  }

  // Build a structured post-mortem of the runtime's current state.
  // Called by the harness after a non-BcplHalt throw escapes run() so
  // the UI can render a Crash tab. Pure read of in-memory state — no
  // side effects, safe to call after a trap.
  //
  // Frame walk: BCPL's calling convention saves the previous P at
  // mem[P*4 + 0]. We follow that pointer until we hit 0, walk off the
  // stack, or hit MAX_DEPTH. mem[P*4 + 2] holds the callee's table
  // index; we record it so the UI can name-resolve later if a map
  // becomes available.
  crashSnapshot(err) {
    const snap = {
      message: err?.message ?? String(err),
      stack:   err?.stack ?? null,
      aborted: !!this.aborted,
      P:       this.P | 0,
      line:    this.currentLine(),
      heapTop: this.heapTop | 0,
      freeList: this.freeList | 0,
      lastSysOp: this._lastSysOp ?? null,
      sysOpHistory: (this._sysOpHistory ?? []).slice(),
      frames: [],
      globals: [],
      stackTop: [],
    };
    if (!this.memView) return snap;
    // memView is a DataView — use getInt32 for word reads. byteLength
    // bounds the safe range. memView[idx] returns undefined.
    const memWords = (this.memView.byteLength / 4) | 0;
    const rd = (w) => this.memView.getInt32(w * 4, true);

    // Walk P-chain. Each frame: { P, prevP, retLab, fnIdx, args[] }
    const MAX_DEPTH = 32;
    let p = this.P | 0;
    const seen = new Set();
    for (let depth = 0; depth < MAX_DEPTH; depth++) {
      if (p <= 0 || p >= memWords || seen.has(p)) break;
      seen.add(p);
      const prevP  = rd(p + 0);
      const retLab = rd(p + 1);
      const fnIdx  = rd(p + 2);
      // Sample first 6 word slots after the saved-P/ret-addr/fn-idx
      // triple — these are the callee's args.
      const args = [];
      for (let i = 0; i < 6; i++) {
        const a = p + 3 + i;
        if (a >= memWords) break;
        args.push(rd(a));
      }
      snap.frames.push({ P: p, prevP, retLab, fnIdx, args });
      p = prevP;
    }

    // Globals: G!1..G!100. G lives at word 1.
    for (let g = 0; g < 100; g++) {
      const w = 1 + g;
      if (w >= memWords) break;
      snap.globals.push({ g, val: rd(w) });
    }

    // Top of stack: 16 words at and around current P.
    const top = Math.max(0, this.P - 4);
    for (let i = 0; i < 16; i++) {
      const w = top + i;
      if (w >= memWords) break;
      snap.stackTop.push({ w, val: rd(w), isP: w === this.P });
    }
    return snap;
  }

  // Wire up the canvas + a callback to flip its container visible.
  // Browser code calls this before run() if a canvas is available.
  setSdlCanvas(canvasEl, onShow) {
    this.sdlCanvas = canvasEl;
    this.sdlCtx    = canvasEl ? canvasEl.getContext("2d") : null;
    this.sdlOnShow = onShow ?? null;
    if (canvasEl) this._installSdlInputHandlers();
  }

  _installSdlInputHandlers() {
    const c = this.sdlCanvas;
    if (!c) return;
    // Always re-point the singleton window key handler at this runtime
    // so a fresh Compile & Run wires events into the new instance.
    if (typeof window !== "undefined") window.__bcplKeysWired = this;
    if (c.__bcplWired) return;
    c.__bcplWired = true;
    c.tabIndex = 0;
    c.addEventListener("mousemove", (e) => {
      const r = c.getBoundingClientRect();
      this.sdlMouse.x = (e.clientX - r.left) | 0;
      this.sdlMouse.y = (e.clientY - r.top)  | 0;
      this.sdlEvents.push({ type: 4, x: this.sdlMouse.x, y: this.sdlMouse.y });
    });
    c.addEventListener("mousedown", (e) => {
      this.sdlMouse.buttons |= (1 << e.button);
      this.sdlEvents.push({ type: 5, b: 1 << e.button, x: this.sdlMouse.x, y: this.sdlMouse.y });
    });
    c.addEventListener("mouseup", (e) => {
      this.sdlMouse.buttons &= ~(1 << e.button);
      this.sdlEvents.push({ type: 6, b: 1 << e.button, x: this.sdlMouse.x, y: this.sdlMouse.y });
    });

    // Key handlers live on the window so the canvas does not have to
    // hold focus. Without this, clicking Stop or anywhere outside the
    // canvas swallows subsequent keystrokes, including Esc — so the
    // running BCPL program "rarely" sees the quit key.
    //
    // Skip events targeted at form fields so typing into stdin /
    // editor textareas does not flood the SDL queue.
    if (typeof window !== "undefined" && !window.__bcplKeysListenersAttached) {
      window.__bcplKeysListenersAttached = true;
      const editable = (t) => t && (
        t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.isContentEditable
      );
      window.addEventListener("keydown", (e) => {
        const rt = window.__bcplKeysWired;
        if (!rt || !rt.sdlCanvas) return;
        if (editable(e.target)) return;
        const code = e.keyCode || e.which || (e.key && e.key.charCodeAt(0)) || 0;
        rt.sdlKeys.add(code);
        rt.sdlEvents.push({ type: 2, mod: 0, ch: code });
        // Stop arrows / space from scrolling the page while playing.
        if (code >= 32 && code <= 40) e.preventDefault();
        if (code === 27) e.preventDefault();
      }, true);
      window.addEventListener("keyup", (e) => {
        const rt = window.__bcplKeysWired;
        if (!rt || !rt.sdlCanvas) return;
        if (editable(e.target)) return;
        const code = e.keyCode || e.which || (e.key && e.key.charCodeAt(0)) || 0;
        rt.sdlKeys.delete(code);
        rt.sdlEvents.push({ type: 3, mod: 0, ch: code });
      }, true);
    }
  }

  // Decode a packed BCPL "colour" (any int) into rgba components.
  // Default packing: 0xRRGGBBAA (high byte R, low byte A). Fallback A=0xFF.
  _sdlPackedToRgba(c) {
    const u = c >>> 0;
    let r = (u >>> 24) & 0xFF;
    let g = (u >>> 16) & 0xFF;
    let b = (u >>>  8) & 0xFF;
    let a = u & 0xFF;
    // If alpha is 0, treat as opaque (BCPL maprgb returns RGB only).
    if (a === 0 && (r | g | b) !== 0) a = 0xFF;
    return [r, g, b, a];
  }
  _sdlSetStroke(c) {
    const [r, g, b, a] = this._sdlPackedToRgba(c);
    this.sdlCtx.strokeStyle = `rgba(${r},${g},${b},${a/255})`;
  }
  _sdlSetFill(c) {
    const [r, g, b, a] = this._sdlPackedToRgba(c);
    this.sdlCtx.fillStyle = `rgba(${r},${g},${b},${a/255})`;
  }

  // ------------------ Stream Control Blocks ------------------
  //
  // Layout matches g/libhdr.h scb_* manifests so BCPL code can read
  // scb fields directly via the returned handle (which is the SCB's
  // word address). Only the fields user code typically inspects are
  // kept in sync (id, type, pos, end, buf, bufend, name).
  static SCB = {
    id: 0, type: 1, task: 2, buf: 3, pos: 4, end: 5,
    rdfn: 6, wrfn: 7, endfn: 8, block: 9, write: 10, bufend: 11,
    lblock: 12, ldata: 13, blength: 14, reclen: 15,
    fd: 16, fd1: 17, timeout: 18, timeoutact: 19, encoding: 20,
    name: 21, SIZE: 29,
  };
  // id_* constants
  static SCB_ID_IN     = 0x81;
  static SCB_ID_OUT    = 0x82;
  static SCB_ID_INOUT  = 0x83;
  static SCB_ID_APPEND = 0x84;
  // scbt_* constants
  static SCB_T_RAM     =  0;
  static SCB_T_FILE    =  1;
  static SCB_T_CONSOLE = -1;

  _allocScbPtr() {
    // Reserve an SCB-sized slab (29 words) from the heap.
    this.heapTop -= BcplRuntime.SCB.SIZE;
    return this.heapTop;
  }

  _initScbFields(scbPtr, { idCode, typeCode, name }) {
    const S = BcplRuntime.SCB;
    // Zero everything first.
    for (let i = 0; i < S.SIZE; i++) this.storeWord(scbPtr + i, 0);
    this.storeWord(scbPtr + S.id,   idCode | 0);
    this.storeWord(scbPtr + S.type, typeCode | 0);
    this.storeWord(scbPtr + S.pos,  0);
    this.storeWord(scbPtr + S.end,  0);
    this.storeWord(scbPtr + S.buf,  0);
    this.storeWord(scbPtr + S.bufend, 0);
    this.storeWord(scbPtr + S.encoding, -1);  // UTF8 by default
    // Copy up to 31 bytes of name into scb_name region.
    if (name) {
      const base = (scbPtr + S.name) * 4;
      const len = Math.min(name.length, 31);
      this.memView.setUint8(base, len);
      for (let i = 0; i < len; i++) {
        this.memView.setUint8(base + 1 + i, name.charCodeAt(i) & 0xFF);
      }
    }
  }

  _syncScb(rec) {
    if (!rec || !rec.scbPtr) return;
    const S = BcplRuntime.SCB;
    this.storeWord(rec.scbPtr + S.pos, rec.pos | 0);
    const len = (rec.data?.length ?? 0) | 0;
    this.storeWord(rec.scbPtr + S.end,    len);
    this.storeWord(rec.scbPtr + S.bufend, len);
  }

  // Return the stream record for a handle (scbPtr) or null.
  _stream(scbPtr) {
    if (!scbPtr) return null;
    return this._scbToStream.get(scbPtr) ?? null;
  }

  // Byte view; refresh after every memory.grow.
  refresh() {
    this.memView = new DataView(this.mem.buffer);
    // Init heap pointer once on first refresh after load.
    if (this.heapTop === 0) {
      this.heapTop = (this.mem.buffer.byteLength >> 2);  // total words
    }
  }

  // Unpack a packed BCPL colour word (0xRRGGBBAA → individual bytes).
  _fbUnpack(c) {
    return [
      (c >>> 24) & 0xFF,
      (c >>> 16) & 0xFF,
      (c >>>  8) & 0xFF,
      (c & 0xFF) || 0xFF,
    ];
  }

  // Write a vertical line into the back buffer (no canvas hit).
  // Used by sdl_drawvline and the sky/floor fill paths so we can
  // flip the whole frame in one putImageData.
  _fbVline(x, y0, y1, color) {
    const fb = this._fb;
    if (!fb) return;
    const W = this._fbW, H = this._fbH;
    if (x < 0 || x >= W) return;
    if (y0 > y1) { const t = y0; y0 = y1; y1 = t; }
    if (y0 < 0) y0 = 0;
    if (y1 >= H) y1 = H - 1;
    if (y0 > y1) return;
    const r = (color >>> 24) & 0xFF;
    const g = (color >>> 16) & 0xFF;
    const b = (color >>>  8) & 0xFF;
    const a = (color & 0xFF) || 0xFF;
    let p = (y0 * W + x) * 4;
    const stride = W * 4;
    for (let y = y0; y <= y1; y++) {
      fb[p]     = r;
      fb[p + 1] = g;
      fb[p + 2] = b;
      fb[p + 3] = a;
      p += stride;
    }
  }

  // Bresenham line (x0, y0) → (x1, y1) into the backbuffer.
  _fbLine(x0, y0, x1, y1, color) {
    const fb = this._fb;
    if (!fb) return;
    const W = this._fbW, H = this._fbH;
    const r = (color >>> 24) & 0xFF;
    const g = (color >>> 16) & 0xFF;
    const b = (color >>>  8) & 0xFF;
    const a = (color & 0xFF) || 0xFF;
    const dx = Math.abs(x1 - x0), sx = x0 < x1 ? 1 : -1;
    const dy = -Math.abs(y1 - y0), sy = y0 < y1 ? 1 : -1;
    let err = dx + dy;
    let x = x0 | 0, y = y0 | 0;
    while (true) {
      if (x >= 0 && x < W && y >= 0 && y < H) {
        const p = (y * W + x) * 4;
        fb[p]     = r;
        fb[p + 1] = g;
        fb[p + 2] = b;
        fb[p + 3] = a;
      }
      if (x === x1 && y === y1) break;
      const e2 = 2 * err;
      if (e2 >= dy) { err += dy; x += sx; }
      if (e2 <= dx) { err += dx; y += sy; }
    }
  }

  // Filled rect (x..x+w-1, y..y+h-1).
  _fbRect(x, y, w, h, color) {
    const fb = this._fb;
    if (!fb) return;
    const W = this._fbW, H = this._fbH;
    let x0 = x, y0 = y, x1 = x + w, y1 = y + h;
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 > W) x1 = W;
    if (y1 > H) y1 = H;
    if (x0 >= x1 || y0 >= y1) return;
    const r = (color >>> 24) & 0xFF;
    const g = (color >>> 16) & 0xFF;
    const b = (color >>>  8) & 0xFF;
    const a = (color & 0xFF) || 0xFF;
    for (let yy = y0; yy < y1; yy++) {
      let p = (yy * W + x0) * 4;
      for (let xx = x0; xx < x1; xx++) {
        fb[p]     = r;
        fb[p + 1] = g;
        fb[p + 2] = b;
        fb[p + 3] = a;
        p += 4;
      }
    }
  }

  // Grow wasm memory by enough pages to cover `needWords` words above
  // the current heap top, then slide heapTop up so subsequent
  // descending allocations land in the new region. Returns true on
  // success, false if the engine refused to grow.
  //
  // Memory layout reminder: stack/statics grow up from low addresses;
  // heap descends from the top. Growing extends the high end, so we
  // can safely treat the freshly-allocated pages as a new descending
  // heap window — existing allocations below the old top stay put.
  growHeapForWords(needWords) {
    const PAGE_WORDS = 65536 / 4;
    const pages = Math.ceil(needWords / PAGE_WORDS) + 1;  // +1 slack
    const before = this.mem.grow(pages);
    if (before === -1) return false;
    // before = page count before grow. New top in words:
    const newTopWords = ((before + pages) * 65536) >> 2;
    this.heapTop = newTopWords;
    this.refresh();
    return true;
  }

  loadWord(wordAddr) {
    return this.memView.getInt32(wordAddr * 4, true);
  }
  storeWord(wordAddr, v) {
    this.memView.setInt32(wordAddr * 4, v | 0, true);
  }
  loadByte(byteAddr) {
    return this.memView.getUint8(byteAddr);
  }
  storeByte(byteAddr, v) {
    this.memView.setUint8(byteAddr, v & 0xFF);
  }

  get P() { return this.master.exports.P.value; }
  set P(v) { this.master.exports.P.value = v | 0; }

  // BCPL string at wordAddr: byte 0 = length, bytes 1..len = chars.
  readBcplString(wordAddr) {
    const baseByte = wordAddr * 4;
    const len = this.loadByte(baseByte);
    let s = "";
    for (let i = 0; i < len; i++) {
      s += String.fromCharCode(this.loadByte(baseByte + 1 + i));
    }
    return s;
  }

  // Args of the currently-executing BCPL function: P!3, P!4, ...
  arg(i) { return this.loadWord(this.P + 3 + i); }

  // Restore P from P!0 (the standard FNRN/RTRN epilogue). Every
  // stdlib entry must call this before returning.
  restoreP() { this.P = this.loadWord(this.P); }

  // Route one char to the current output stream. stdout → UI. NIL
  // streams discard. RAM/file streams buffer in-memory; file streams
  // commit on endstream; RAM streams stay in-memory only.
  _writeChar(ch) {
    const s = this._stream(this.curOut);
    if (!s) return;
    if (s.kind === "stdout") {
      this.writeOut(String.fromCharCode(ch & 0xFF));
      return;
    }
    if (s.kind === "nil") return;
    s.data = (s.data || "") + String.fromCharCode(ch & 0xFF);
    s.pos = s.data.length;
    this._syncScb(s);
  }

  _writeString(str) {
    const s = this._stream(this.curOut);
    if (!s) return;
    if (s.kind === "stdout") { this.writeOut(str); return; }
    if (s.kind === "nil") return;
    s.data = (s.data || "") + str;
    s.pos = s.data.length;
    this._syncScb(s);
  }

  // Read one char from current input stream, or -1 at EOF.
  _readChar() {
    const s = this._stream(this.curIn);
    if (!s) return -1;
    if (s.kind === "stdin") {
      if (this.inputIdx >= this.input.length) return -1;
      return this.input.charCodeAt(this.inputIdx++);
    }
    if (s.kind === "nil") return -1;
    if (s.pos >= s.data.length) return -1;
    const ch = s.data.charCodeAt(s.pos++);
    this._syncScb(s);
    return ch;
  }

  // ------------------ stdlib implementations ------------------

  imp_stop() {
    this.finished = true;
    // BCPL's stop takes one arg (exit code) but we just halt.
    throw new BcplHalt(this.arg(0));
  }

  imp_rdch() {
    this.restoreP();
    return this._readChar();
  }

  imp_wrch() {
    const ch = this.arg(0);
    this._writeChar(ch);
    this.restoreP();
    return 0;
  }

  imp_newline() {
    this._writeChar(10);
    this.restoreP();
    return 0;
  }

  imp_writen() {
    this._writeString(String(this.arg(0)));
    this.restoreP();
    return 0;
  }

  imp_writes() {
    this._writeString(this.readBcplString(this.arg(0)));
    this.restoreP();
    return 0;
  }

  imp_writef() {
    // writef(fmt, a0..a10) — classic BCPL format codes. Standard blib
    // supports 11 value args after the format string.
    const fmt = this.readBcplString(this.arg(0));
    const args = [];
    for (let k = 0; k < 11; k++) args.push(this.arg(1 + k));
    let ai = 0, out = "";
    const f32buf = new ArrayBuffer(4);
    const f32i = new Int32Array(f32buf);
    const f32f = new Float32Array(f32buf);
    for (let i = 0; i < fmt.length; i++) {
      const c = fmt[i];
      if (c !== "%") { out += c; continue; }
      i++;
      if (i >= fmt.length) break;
      // BCPL writef format (per sysb/blib.b write_format):
      //   %N[.P]<code>   explicit width.precision before code (%5.2f)
      //   %<code>[W]     single-char width after code (%i4, %X8) —
      //                  for codes I/D/X/O/U/Z/B only. W is digit or
      //                  letter A–F (=10..15). Codes S/C/N/#/T take
      //                  no width.
      let widthgiven = false, width = 0, precision = -1;
      if (/[0-9.]/.test(fmt[i] ?? "")) {
        widthgiven = true;
        while (/[0-9]/.test(fmt[i] ?? "")) {
          width = width * 10 + (fmt.charCodeAt(i) - 48);
          i++;
        }
        if (fmt[i] === ".") {
          i++;
          precision = 0;
          while (/[0-9]/.test(fmt[i] ?? "")) {
            precision = precision * 10 + (fmt.charCodeAt(i) - 48);
            i++;
          }
        }
      }
      const code = (fmt[i] ?? "").toLowerCase();
      if (!widthgiven && "idxouzbt".includes(code)) {
        const wc = fmt[i + 1] ?? "";
        if (/[0-9]/.test(wc))       { width = wc.charCodeAt(0) - 48;                            i++; }
        else if (/[a-f]/i.test(wc)) { width = 10 + (wc.toLowerCase().charCodeAt(0) - 97);       i++; }
      }
      switch (code) {
        case "n": out += String(args[ai++] | 0); break;
        case "d": {
          // Canonical BCPL: %n.mD is fixed-point — divide arg by 10^m,
          // write int part in width (n-1-m), then `.`, then fractional
          // part zero-padded to m digits. Without precision, %D == %I.
          const v = args[ai++] | 0;
          if (widthgiven && precision >= 0) {
            const scale = Math.pow(10, precision);
            const sign = v < 0 ? "-" : "";
            const av = Math.abs(v);
            const intpart = String(Math.trunc(av / scale))
              .padStart(width - 1 - precision - (v < 0 ? 1 : 0), " ");
            const frac = String(av % scale).padStart(precision, "0");
            out += sign + intpart + "." + frac;
          } else {
            out += String(v).padStart(width, " ");
          }
          break;
        }
        case "i": out += String(args[ai++] | 0).padStart(width, " "); break;
        case "u": out += String(args[ai++] >>> 0).padStart(width, " "); break;
        case "c": out += String.fromCharCode(args[ai++] & 0xFF); break;
        case "s": out += this.readBcplString(args[ai++]); break;
        case "x": out += ((args[ai++] >>> 0).toString(16).padStart(width, "0")); break;
        case "o": out += ((args[ai++] >>> 0).toString(8).padStart(width, "0")); break;
        case "b": out += ((args[ai++] >>> 0).toString(2).padStart(width, "0")); break;
        case "z": {  // zero-padded signed decimal
          const v = args[ai++] | 0;
          const s = String(Math.abs(v)).padStart(width - (v < 0 ? 1 : 0), "0");
          out += (v < 0 ? "-" : "") + s;
          break;
        }
        case "t": out += this.readBcplString(args[ai++]).padEnd(width, " "); break;
        case "f": case "e": case "g": {
          f32i[0] = args[ai++] | 0;
          let s = (code === "e")
            ? f32f[0].toExponential(precision >= 0 ? precision : 6)
            : f32f[0].toFixed(precision >= 0 ? precision : 6);
          out += s.padStart(width, " ");
          break;
        }
        case "$": case "+": ai++; break;   // skip arg, no output
        case "-": ai--; break;             // back up arg pointer
        case "#": {
          // codewrch(code) — UTF-8 / GB2312 char emitter. We map it to
          // a plain JS character; high-bit selector codes are honoured
          // by the dedicated imp_codewrch but in writef context the
          // simple cast is what BLIB compiles to.
          const ch = args[ai++] & 0xFFFFFF;
          out += String.fromCodePoint(ch);
          break;
        }
        default: out += "%" + (fmt[i] ?? ""); break;
      }
    }
    this._writeString(out);
    this.restoreP();
    return 0;
  }

  // getvec(n) — allocate n+1 words. Prefer free list (first-fit),
  // else bump-allocate from top of memory. Returns BCPL word address
  // (pointer such that p!0..p!n span the allocation), or 0 on OOM.
  imp_getvec() {
    const n = this.arg(0);
    const size = n + 1;   // BCPL vectors are 0..n inclusive
    // Best-fit on free list. Sizes live in vecSizes side-table — user
    // memory isn't safe to use as a header (user code writes to vec!1
    // routinely and would clobber it).
    let prev = 0, cur = this.freeList;
    let bestPrev = 0, best = 0, bestSize = 0x7fffffff;
    while (cur !== 0) {
      const blockSize = this.vecSizes.get(cur) | 0;
      const next = this.loadWord(cur);
      if (blockSize >= size && blockSize < bestSize) {
        bestPrev = prev; best = cur; bestSize = blockSize;
        if (blockSize === size) break;
      }
      prev = cur; cur = next;
    }
    if (best !== 0) {
      const next = this.loadWord(best);
      if (bestPrev === 0) this.freeList = next;
      else this.storeWord(bestPrev, next);
      this.restoreP();
      return best;
    }
    // Bump.
    this.heapTop -= size;
    if (this.heapTop <= 0) {
      this.restoreP();
      return 0;
    }
    const p = this.heapTop;
    this.vecSizes.set(p, size);
    this.restoreP();
    return p;
  }

  imp_freevec() {
    const p = this.arg(0);
    if (p === 0) { this.restoreP(); return 0; }
    // Prepend block to free list. Link goes in user word 0 (which the
    // user has now relinquished). Size persists in vecSizes side-table.
    this.storeWord(p, this.freeList);
    this.freeList = p;
    this.restoreP();
    return 0;
  }

  // muldiv(a, b, c) = (a*b) / c with 64-bit intermediate to avoid
  // overflow, truncated to i32 on return. BCPL's classic way to
  // rescale integers without losing precision.
  imp_muldiv() {
    const a = BigInt(this.arg(0));
    const b = BigInt(this.arg(1));
    const c = BigInt(this.arg(2));
    this.restoreP();
    if (c === 0n) return 0;
    return Number((a * b) / c) | 0;
  }

  // abort(n) — same semantics as stop but flagged as an error halt.
  imp_abort() {
    this.finished = true;
    throw new BcplHalt(this.arg(0), /*isAbort*/ true);
  }

  // randno(n) — return pseudo-random integer in [1..n] inclusive.
  // n <= 0 returns 0 (matches BLIB behaviour).
  imp_randno() {
    const n = this.arg(0);
    this.restoreP();
    if (n <= 0) return 0;
    return 1 + (Math.random() * n) | 0;  // 1..n
  }

  // capitalch(ch) — uppercase a-z, leave others alone.
  imp_capitalch() {
    const ch = this.arg(0) & 0xFF;
    this.restoreP();
    if (ch >= 0x61 && ch <= 0x7A) return ch - 0x20;
    return ch;
  }

  // compch(a, b) — case-insensitive char compare. -1, 0, +1.
  imp_compch() {
    const up = (c) => (c >= 0x61 && c <= 0x7A) ? c - 0x20 : c;
    const a = up(this.arg(0) & 0xFF);
    const b = up(this.arg(1) & 0xFF);
    this.restoreP();
    if (a < b) return -1;
    if (a > b) return 1;
    return 0;
  }

  // compstring(s1, s2) — case-sensitive BCPL string compare. -1/0/+1.
  imp_compstring() {
    const s1 = this.readBcplString(this.arg(0));
    const s2 = this.readBcplString(this.arg(1));
    this.restoreP();
    if (s1 < s2) return -1;
    if (s1 > s2) return 1;
    return 0;
  }

  // output() / input() — return handle of current stream.
  imp_output() { this.restoreP(); return this.curOut; }
  imp_input()  { this.restoreP(); return this.curIn;  }

  // unrdch(ch) — push back one char into the current input stream.
  imp_unrdch() {
    const s = this._stream(this.curIn);
    this.restoreP();
    if (!s) return -1;
    if (s.kind === "stdin") {
      if (this.inputIdx > 0) this.inputIdx--;
      return 0;
    }
    if (s.pos > 0) s.pos--;
    this._syncScb(s);
    return 0;
  }

  // rewindstream(scbPtr) — reset stream position to 0.
  imp_rewindstream() {
    const h = this.arg(0);
    this.restoreP();
    const s = this._stream(h);
    if (!s) return 0;
    if (s.kind === "stdin") { this.inputIdx = 0; return 0; }
    if (s.kind === "stdout") return 0;
    s.pos = 0;
    this._syncScb(s);
    return 0;
  }

  // Recognise the special device prefixes BCPL uses, mirroring the
  // dispatcher in sysb/dlibsys.b:
  //   "NIL:..."   — null device. Read = EOF, write = discard.
  //   "RAM:..."   — read/write in-memory scratch buffer; not committed
  //                  to persistent storage.
  // Anything else is a regular storageBackend-backed file stream.
  _streamSpec(name) {
    if (!name) return { kind: "file" };
    const i = name.indexOf(":");
    if (i < 0) return { kind: "file" };
    const prefix = name.slice(0, i);
    if (prefix === "NIL") return { kind: "nil" };
    if (prefix === "RAM") return { kind: "ram" };
    return { kind: "file" };
  }

  // findinoutput(name) — open bidirectional stream.
  imp_findinoutput() {
    const name = this.readBcplString(this.arg(0));
    this.restoreP();
    const spec = this._streamSpec(name);
    if (spec.kind === "nil") {
      return this._allocStream({ kind: "nil", mode: "rw", name, data: "", pos: 0 });
    }
    if (spec.kind === "ram") {
      return this._allocStream({ kind: "ram", mode: "rw", name, data: "", pos: 0 });
    }
    const data = storageBackend.get(name) ?? "";
    return this._allocStream({ kind: "file", mode: "rw", name, data, pos: 0 });
  }

  // errwrch(ch) — write char to stderr. Routed to writeOut callback
  // with an [err] prefix so it isn't silently swallowed.
  imp_errwrch() {
    const ch = this.arg(0) & 0xFF;
    this.restoreP();
    this.writeOut(String.fromCharCode(ch));
    return 0;
  }

  // sawritef — same as writef for our purposes (writes directly to
  // the underlying output rather than via selectoutput).
  imp_sawritef() { return this.imp_writef(); }

  // sys(op, a, b, c, ...) — BCPL low-level dispatcher.
  //
  // Covers opcodes defined in g/libhdr.h under "Sys_*". Ones marked
  // NOOP return 0 silently; out-of-scope ones (graphics/audio, Cintpos
  // IRQ, segment loader, native bridge) also return 0. See
  // CLAUDE.md "WebAssembly Backend" for scope rules.
  imp_sys() {
    const op = this.arg(0);
    // Capture up to 8 extra args BEFORE restoreP since it rewrites P.
    const a1 = this.arg(1), a2 = this.arg(2), a3 = this.arg(3);
    const a4 = this.arg(4), a5 = this.arg(5), a6 = this.arg(6);
    const a7 = this.arg(7), a8 = this.arg(8);
    // Post-mortem trail: remember the most recent few sys() calls so
    // crashSnapshot() can show what user code was doing when it
    // trapped. Cheap — small ring buffer in JS, never touched by
    // wasm. _sysOpHistory is allocated lazily.
    if (!this._sysOpHistory) this._sysOpHistory = [];
    const sysRec = { op, args: [a1, a2, a3, a4, a5, a6, a7, a8], t: Date.now() };
    this._lastSysOp = sysRec;
    this._sysOpHistory.push(sysRec);
    if (this._sysOpHistory.length > 16) this._sysOpHistory.shift();
    this.restoreP();

    switch (op) {
      // ---- process lifecycle ----
      case -1: return 0;                                // Sys_setcount NOOP
      case  0: throw new BcplHalt(a1 | 0, /*isAbort*/ true);  // Sys_quit
      case  1: case  2: case  3: return 0;              // Sys_rti/saveregs/setst NOOP
      // These three poke the Cintcode INTERPRETER's per-instruction
      // hook (instruction-level trace, memory watch, frequency tally).
      // The playground runs compiled wasm directly — there's no
      // per-instruction hook to wire them into — so they stay NOOPs.
      // Use the Debugger toggle + breakpoints for per-statement step.
      case  4: return 0;                                // Sys_tracing(val)
      case  5: return 0;                                // Sys_watch(addr)
      case  6: return 0;                                // Sys_tally(val)
      case  7: return 0;                                // Sys_interpret NOOP

      // ---- direct-screen char I/O ----
      case 10: return this._readChar();                 // Sys_sardch
      case 11: this._writeChar(a1); return 0;           // Sys_sawrch(ch)

      // ---- byte-granular stream read/write ----
      case 12: { // Sys_read(fd) — next byte (or -1)
        const prevIn = this.curIn;
        this.curIn = a1 || this.curIn;
        const ch = this._readChar();
        this.curIn = prevIn;
        return ch;
      }
      case 13: { // Sys_write(fd, ch)
        const prevOut = this.curOut;
        this.curOut = a1 || this.curOut;
        this._writeChar(a2);
        this.curOut = prevOut;
        return 0;
      }

      // ---- file open/close (delegate to stream imp_* helpers) ----
      case 14: { // Sys_openread(name)
        const name = this.readBcplString(a1);
        if (!name) return 0;
        const data = storageBackend.get(name);
        if (data === null) return 0;
        return this._allocStream({ kind: "file", mode: "r", name, data, pos: 0 });
      }
      case 15: { // Sys_openwrite(name)
        const name = this.readBcplString(a1);
        if (!name) return 0;
        return this._allocStream({ kind: "file", mode: "w", name, data: "", pos: 0 });
      }
      case 16: { // Sys_close(scbPtr)
        const h = a1;
        const s = this._stream(h);
        if (!s) return 0;
        if (s.kind === "file" && s.mode === "w") storageBackend.set(s.name, s.data);
        this._freeStream(h);
        if (this.curOut === h) { this.curOut = this.stdoutScb; this.storeWord(1 + 13, this.stdoutScb); }
        if (this.curIn  === h) { this.curIn  = this.stdinScb;  this.storeWord(1 + 12, this.stdinScb);  }
        return 0;
      }
      case 19: { // Sys_openappend(name)
        const name = this.readBcplString(a1);
        if (!name) return 0;
        const existing = storageBackend.get(name) ?? "";
        return this._allocStream({ kind: "file", mode: "w", name, data: existing, pos: existing.length });
      }
      case 47: { // Sys_openreadwrite(name)
        const name = this.readBcplString(a1);
        if (!name) return 0;
        const data = storageBackend.get(name) ?? "";
        return this._allocStream({ kind: "file", mode: "rw", name, data, pos: 0 });
      }

      // ---- file ops on storageBackend ----
      case 17: { // Sys_deletefile(name) → TRUE/FALSE
        const name = this.readBcplString(a1);
        if (!name || storageBackend.get(name) === null) return 0;
        storageBackend.del?.(name);
        return -1;
      }
      case 18: { // Sys_renamefile(old, new) → TRUE/FALSE
        const oldName = this.readBcplString(a1);
        const newName = this.readBcplString(a2);
        const data = storageBackend.get(oldName);
        if (data === null) return 0;
        storageBackend.set(newName, data);
        storageBackend.del?.(oldName);
        return -1;
      }
      case 46: { // Sys_filesize(name) → bytes, or -1 if missing
        const name = this.readBcplString(a1);
        const data = storageBackend.get(name);
        return data === null ? -1 : data.length;
      }

      // ---- memory ----
      case 21: return 0;  // Sys_getvec NOOP (delegate via imp_getvec at G!25)
      case 22: return 0;  // Sys_freevec NOOP
      case 24: return 0;  // Sys_globin NOOP (no seg loader)

      // ---- loader / native bridge (out of scope) ----
      case 23: case 25: return 0;                       // loadseg/unloadseg
      case 53: case 59: return 0;                       // callnative/callc

      // ---- muldiv ----
      case 26: { // Sys_muldiv(a, b, c)
        const a = BigInt.asIntN(64, BigInt(a1));
        const b = BigInt.asIntN(64, BigInt(a2));
        const c = BigInt.asIntN(64, BigInt(a3));
        if (c === 0n) { this._setResult2(0); return 0; }
        const q = (a * b) / c;
        const r = (a * b) - q * c;
        this._setResult2(Number(BigInt.asIntN(32, r)));
        return Number(BigInt.asIntN(32, q));
      }
      case 28: return 0;                                // Sys_intflag FALSE
      case 29: return 0;                                // Sys_setraster NOOP
      case 30:                                          // Sys_cputime: high-res ms (i32)
        return (typeof performance !== "undefined")
          ? (performance.now() | 0)
          : ((Date.now() & 0x7fffffff));
      case 31: return 0;                                // Sys_filemodtime NOOP

      // ---- prefix (currentdir) ----
      case 32: {  // Sys_setprefix(s) — copy s to currentdir
        const name = this.readBcplString(a1);
        // Rewrite the currentdir string in place.
        const cd = this.loadWord(1 + 14);    // G!14 = currentdir word-addr
        if (!cd) return 0;
        const base = cd * 4;
        this.memView.setUint8(base, name.length & 0xFF);
        for (let i = 0; i < name.length; i++)
          this.memView.setUint8(base + 1 + i, name.charCodeAt(i) & 0xFF);
        return 0;
      }
      case 33: return this.loadWord(1 + 14);            // Sys_getprefix → G!14

      // ---- graphics placeholders ----
      case 34: return 0;                                // Sys_graphics NOOP

      // ---- stream seek / tell ----
      case 38: { // Sys_seek(scbPtr, pos, whence)
        const pos = a2 | 0, whence = a3 | 0;
        const s = this._stream(a1);
        if (!s || s.kind !== "file") return 0;
        let newPos = pos;
        if (whence === 1) newPos = (s.pos | 0) + pos;
        else if (whence === 2) newPos = (s.data?.length ?? 0) + pos;
        s.pos = Math.max(0, newPos);
        this._syncScb(s);
        return -1;
      }
      case 39: { // Sys_tell(scbPtr)
        const s = this._stream(a1);
        if (!s || s.kind !== "file") return -1;
        return s.pos | 0;
      }

      // ---- IRQ / device (Cintpos — out of scope) ----
      case 40: case 41: case 42: case 43: return 0;

      // ---- datstamp(v) — fill v!0..v!2 with date info ----
      case 44: {
        const v = a1;
        if (!v) return 0;
        const now = new Date();
        const epochMs = now.getTime();
        const days = Math.floor(epochMs / 86400000);
        const msOfDay = epochMs - days * 86400000;
        this.storeWord(v + 0, days);
        this.storeWord(v + 1, msOfDay | 0);
        this.storeWord(v + 2, -1);
        return v;
      }

      // ---- sysvals (simple Map-backed kv store) ----
      case 48: {  // Sys_getsysval(key)
        this._sysvals ??= new Map();
        return this._sysvals.get(a1 | 0) | 0;
      }
      case 49: {  // Sys_putsysval(key, val)
        this._sysvals ??= new Map();
        this._sysvals.set(a1 | 0, a2 | 0);
        return 0;
      }

      case 50: return 0;                                // Sys_shellcom NOOP
      case 51: return 1;                                // Sys_getpid constant
      case 52: return 0;                                // Sys_dumpmem NOOP
      case 54: return 0;                                // Sys_platform generic
      case 55: {  // Sys_inc(addr) — *addr += 1, return new value
        const v = this.loadWord(a1) + 1;
        this.storeWord(a1, v);
        return v;
      }
      case 56: return 0;                                // Sys_buttons NOOP

      // ---- delay (no-op in Node, actual sleep would need async) ----
      case 57: return 0;                                // Sys_delay NOOP
      case 58: return 0;                                // Sys_sound NOOP (out of scope)

      // ---- low-level trace buffer ----
      // Cintsys ships a 4096-slot circular trace buffer + a "trcount"
      // cursor. trpush stores at (trcount MOD 4096) and bumps trcount.
      // settrcount replaces the cursor (returning the old value);
      // negative values disable tracing. gettrval reads slot
      // (trcount MOD 4096) — typically called with tracing disabled.
      case 60: {                                        // Sys_trpush(val)
        if (this._trcount < 0) return 0;
        if (!this._traceBuf) this._traceBuf = new Int32Array(4096);
        this._traceBuf[(this._trcount >>> 0) & 4095] = a1 | 0;
        this._trcount = (this._trcount | 0) + 1;
        return 0;
      }
      case 61: {                                        // Sys_settrcount(c) → prev
        const prev = this._trcount | 0;
        this._trcount = a1 | 0;
        return prev;
      }
      case 62: {                                        // Sys_gettrval(c) → val
        if (!this._traceBuf) return 0;
        return this._traceBuf[(a1 >>> 0) & 4095] | 0;
      }

      // ---- float (subop dispatch) ----
      case 63: {
        const sub = a1;
        const f = new Float32Array(1);
        const i = new Int32Array(f.buffer);
        const toF = (bits) => { i[0] = bits; return f[0]; };
        const toI = (val) => { f[0] = val;  return i[0]; };
        switch (sub) {
          case 1:  return toI(a2 * Math.pow(10, a3 | 0));  // fl_mk
          case 2:  return (toF(a2) | 0);                    // fl_unmk
          case 3:  return toI(a2 | 0);                      // fl_float
          case 4:  return (toF(a2) | 0);                    // fl_fix
          case 5:  return toI(Math.abs(toF(a2)));           // fl_abs
          case 6:  return toI(toF(a2) * toF(a3));           // fl_mul
          case 7:  return toI(toF(a2) / toF(a3));           // fl_div
          case 8:  return toI(toF(a2) % toF(a3));           // fl_mod
          case 9:  return toI(toF(a2) + toF(a3));           // fl_add
          case 10: return toI(toF(a2) - toF(a3));           // fl_sub
          case 11: return a2;                               // fl_pos
          case 12: return toI(-toF(a2));                    // fl_neg
          case 13: return toF(a2) === toF(a3) ? -1 : 0;     // fl_eq
          case 14: return toF(a2) !== toF(a3) ? -1 : 0;     // fl_ne
          case 15: return toF(a2) <  toF(a3) ? -1 : 0;      // fl_ls
          case 16: return toF(a2) >  toF(a3) ? -1 : 0;      // fl_gr
          case 17: return toF(a2) <= toF(a3) ? -1 : 0;      // fl_le
          case 18: return toF(a2) >= toF(a3) ? -1 : 0;      // fl_ge
          default: return 0;
        }
      }

      case 64: { // Sys_pollsardch — next char or -3 if none
        const s = this._stream(this.curIn);
        if (!s) return -3;
        if (s.kind === "stdin") {
          if (this.inputIdx >= this.input.length) return -3;
          return this.input.charCodeAt(this.inputIdx++);
        }
        if ((s.pos | 0) >= (s.data?.length | 0)) return -3;
        const ch = s.data.charCodeAt(s.pos++);
        this._syncScb(s);
        return ch;
      }
      // Sys_incdcount(n) — bump counter slot n in an internal map.
      // Cintsys stores these in rootnode!rtn_dcountv; here it's a
      // plain Map keyed by n. Inspect via the Memory tab or via
      // diagnostic prints — not exposed back through libhdr.
      case 65: {
        if (!this._dcount) this._dcount = new Map();
        const k = a1 | 0;
        this._dcount.set(k, (this._dcount.get(k) | 0) + 1);
        return 0;
      }

      // ---- SDL: route to dedicated dispatcher ----
      case 66: return this._sdlDispatch(a1, a2, a3, a4, a5, a6, a7);
      // ---- audio / joystick / extension / GL still out of scope ----
      case 67: case 68: case 69: case 72: return 0;

      case 70: return 0;                                // Sys_settracing NOOP
      case 71: return 0;                                // Sys_getbuildno stub

      // ---- block moves ----
      case 73: { // Sys_memmovewords(dest, src, n)
        const dest = a1, src = a2, n = a3 | 0;
        if (dest === src || n <= 0) return 0;
        if (dest < src) {
          for (let i = 0; i < n; i++) this.storeWord(dest + i, this.loadWord(src + i));
        } else {
          for (let i = n - 1; i >= 0; i--) this.storeWord(dest + i, this.loadWord(src + i));
        }
        return 0;
      }
      case 74: { // Sys_memmovebytes(dest, src, n) — byte addresses
        const dest = a1, src = a2, n = a3 | 0;
        if (dest === src || n <= 0) return 0;
        if (dest < src) {
          for (let i = 0; i < n; i++) this.memView.setUint8(dest + i, this.memView.getUint8(src + i));
        } else {
          for (let i = n - 1; i >= 0; i--) this.memView.setUint8(dest + i, this.memView.getUint8(src + i));
        }
        return 0;
      }
      case 75: { // Sys_errwrch(ch) — just write to stdout sink
        this.writeOut(String.fromCharCode(a1 & 0xFF));
        return 0;
      }

      // ---- Asset access ------------------------------------------
      // BCPL: sys(Sys_assetload, name_str, info_vec)
      //   name_str   — BCPL string with the asset's registered name.
      //   info_vec   — caller-supplied VEC 2. On success:
      //                  info_vec!0 = width
      //                  info_vec!1 = height
      //                  info_vec!2 = word address of pixel data
      //                              (packed RGBA, one word per texel
      //                               in 0xAABBGGRR order — same layout
      //                               sdl_maprgb produces).
      // Returns 0 on miss, -1 on hit.
      case 80: {
        const name = this.readBcplString(a1);
        const infoPtr = a2;
        const rec = assetBackend.get(name);
        if (!rec) return 0;
        this._assetMap ??= new Map();
        let dataWordAddr = this._assetMap.get(name);
        // ----- Binary asset path -----
        // Layout: raw bytes copied into wasm memory starting at the
        // byte address dataWordAddr * 4. BCPL reads them via the
        // byte-fetch operator (`base % i`).
        // info!0 = byte length, info!1 = 0, info!2 = word address.
        if (rec.bytes) {
          if (dataWordAddr === undefined) {
            const byteLen = rec.bytes.length;
            const wordsNeeded = (byteLen + 3) >> 2;
            if (this.heapTop - wordsNeeded <= 0) {
              if (!this.growHeapForWords(wordsNeeded)) return 0;
            }
            this.heapTop -= wordsNeeded;
            dataWordAddr = this.heapTop;
            const dstByteAddr = dataWordAddr * 4;
            new Uint8Array(this.mem.buffer, dstByteAddr, byteLen).set(rec.bytes);
            this._assetMap.set(name, dataWordAddr);
          }
          this.storeWord(infoPtr + 0, rec.bytes.length | 0);
          this.storeWord(infoPtr + 1, 0);
          this.storeWord(infoPtr + 2, dataWordAddr | 0);
          return -1;
        }
        // ----- Image asset path -----
        if (dataWordAddr === undefined) {
          const wordsNeeded = rec.w * rec.h;
          if (this.heapTop - wordsNeeded <= 0) {
            if (!this.growHeapForWords(wordsNeeded)) return 0;
          }
          this.heapTop -= wordsNeeded;
          dataWordAddr = this.heapTop;
          // RGBA byte-stream -> packed-RGB int per texel. Runtime
          // colour packing (sdl_maprgb) puts r in high byte:
          //   (r<<24)|(g<<16)|(b<<8)|a  → 0xRRGGBBAA
          for (let i = 0; i < wordsNeeded; i++) {
            const off = i * 4;
            const r = rec.rgba[off    ] | 0;
            const g = rec.rgba[off + 1] | 0;
            const b = rec.rgba[off + 2] | 0;
            const a = rec.rgba[off + 3] | 0;
            const packed = ((r & 0xFF) << 24) | ((g & 0xFF) << 16) |
                           ((b & 0xFF) << 8)  |  (a & 0xFF);
            this.storeWord(dataWordAddr + i, packed);
          }
          this._assetMap.set(name, dataWordAddr);
        }
        this.storeWord(infoPtr + 0, rec.w | 0);
        this.storeWord(infoPtr + 1, rec.h | 0);
        this.storeWord(infoPtr + 2, dataWordAddr | 0);
        return -1;
      }

      // sys(Sys_drawtexcol, col, top, h, texX, tex_base, tex_w, tex_h, dim)
      // One textured column. Per-pixel texY = (y-top)*tex_h / h so the
      // texture stretches/shrinks to fit the wall slice height. `dim`
      // is 0 (full bright) or 1 (halve each channel, for NS faces).
      // Drawn straight into an ImageData strip and pushed onto the
      // canvas with one putImageData — no fillRect-per-band overhead.
      case 82: {
        const col   = a1 | 0;
        const top   = a2 | 0;
        const h     = a3 | 0;
        const texX  = a4 | 0;
        const tBase = a5 | 0;
        const tw    = a6 | 0;
        const th    = a7 | 0;
        const dim   = a8 | 0;
        const fb    = this._fb;
        if (!fb || h <= 0 || tw <= 0 || th <= 0) return 0;
        const W = this._fbW, H = this._fbH;
        let y0 = top, y1 = top + h;
        if (col < 0 || col >= W) return 0;
        if (y0 < 0) y0 = 0;
        if (y1 > H) y1 = H;
        const drawH = y1 - y0;
        if (drawH <= 0) return 0;
        const mv = this.memView;
        const tx = ((texX % tw) + tw) % tw;
        const stride = W * 4;
        let fbIdx = (y0 * W + col) * 4;
        for (let i = 0; i < drawH; i++) {
          const screenY = y0 + i;
          const tY = Math.floor((screenY - top) * th / h);
          const ty = tY >= 0 ? (tY < th ? tY : th - 1) : 0;
          const word = mv.getInt32((tBase + ty * tw + tx) * 4, true);
          let r = (word >>> 24) & 0xFF;
          let g = (word >>> 16) & 0xFF;
          let b = (word >>>  8) & 0xFF;
          const a = word & 0xFF;
          if (dim) { r >>= 1; g >>= 1; b >>= 1; }
          fb[fbIdx]     = r;
          fb[fbIdx + 1] = g;
          fb[fbIdx + 2] = b;
          fb[fbIdx + 3] = a || 0xFF;
          fbIdx += stride;
        }
        return 0;
      }

      // sys(Sys_setbgtex, slot, base, w, h) — cache a background tex.
      // slot 0=sky, 1=floor, 2=ceiling. Subsequent drawskycol /
      // drawfloorcol read from these slots. base is a word address
      // (info!2 from Sys_assetload).
      case 83: {
        const slot = a1 | 0;
        const base = a2 | 0;
        const w    = a3 | 0;
        const h    = a4 | 0;
        const bg = this._bgTex ??= [null, null, null];
        if (slot >= 0 && slot < 3) bg[slot] = { base, w, h };
        return 0;
      }

      // sys(Sys_drawskycol, col, h_top, u) — panorama sky column.
      // Fills y=0..h_top-1 from cached sky tex at column u (wrapped),
      // V scaled by y / (canvas.height/2) * sky_h so the horizon line
      // sits at canvas mid-height regardless of where the wall starts.
      case 84: {
        const col   = a1 | 0;
        const h_top = a2 | 0;
        const u     = a3 | 0;
        const bg = this._bgTex;
        const fb = this._fb;
        if (!fb || !bg || !bg[0] || h_top <= 0) return 0;
        const tex = bg[0];
        const W = this._fbW, H = this._fbH;
        if (col < 0 || col >= W) return 0;
        let drawH = h_top;
        if (drawH > H) drawH = H;
        const horizon = H >> 1;
        const mv = this.memView;
        const tw = tex.w, th = tex.h;
        const tx = ((u % tw) + tw) % tw;
        const stride = W * 4;
        let fbIdx = col * 4;
        for (let y = 0; y < drawH; y++) {
          let tY = Math.floor(y * th / horizon);
          if (tY < 0) tY = 0; else if (tY >= th) tY = th - 1;
          const word = mv.getInt32((tex.base + tY * tw + tx) * 4, true);
          fb[fbIdx]     = (word >>> 24) & 0xFF;
          fb[fbIdx + 1] = (word >>> 16) & 0xFF;
          fb[fbIdx + 2] = (word >>>  8) & 0xFF;
          fb[fbIdx + 3] = (word & 0xFF) || 0xFF;
          fbIdx += stride;
        }
        return 0;
      }

      // sys(Sys_drawfloorcol, col, horizon, px, py, dx, dy) — per-pixel
      // floor + ceiling cast for one column. Both halves share rowDist
      // (camera-perp distance to the floor/ceiling point at screen y).
      // px/py: player pos, 1024-scaled cell coords. dx/dy: ray dir for
      // this column, cos/sin*1024. Floor uses slot 1, ceiling slot 2;
      // either may be null and that half is then skipped.
      //
      //   rowDist = (horizon * 1024) / (y - horizon)        (1024-scaled cells)
      //   worldX  = px + (rowDist * dx) / 1024
      //   worldY  = py + (rowDist * dy) / 1024
      //   tx      = ((worldX mod 1024) * tex_w) / 1024
      //   ty      = ((worldY mod 1024) * tex_h) / 1024
      case 85: {
        const col     = a1 | 0;
        const horizon = a2 | 0;
        const px      = a3 | 0;
        const py      = a4 | 0;
        const dx      = a5 | 0;
        const dy      = a6 | 0;
        const bg = this._bgTex;
        const fb = this._fb;
        if (!fb || !bg) return 0;
        const floor = bg[1], ceil = bg[2];
        if (!floor && !ceil) return 0;
        const W = this._fbW, H = this._fbH;
        if (col < 0 || col >= W) return 0;
        const stride = W * 4;
        const mv = this.memView;
        for (let y = horizon + 1; y < H; y++) {
          const denom = y - horizon;
          const rowDist = ((horizon * 1024) / denom) | 0;
          const worldX = px + ((rowDist * dx) / 1024 | 0);
          const worldY = py + ((rowDist * dy) / 1024 | 0);
          const fx = ((worldX % 1024) + 1024) % 1024;
          const fy = ((worldY % 1024) + 1024) % 1024;
          if (floor) {
            const tw = floor.w, th = floor.h;
            const tx = (fx * tw / 1024) | 0;
            const ty = (fy * th / 1024) | 0;
            const word = mv.getInt32((floor.base + ty * tw + tx) * 4, true);
            const fbIdx = (y * W + col) * 4;
            fb[fbIdx]     = (word >>> 24) & 0xFF;
            fb[fbIdx + 1] = (word >>> 16) & 0xFF;
            fb[fbIdx + 2] = (word >>>  8) & 0xFF;
            fb[fbIdx + 3] = (word & 0xFF) || 0xFF;
          }
          if (ceil) {
            const my = horizon - denom;
            if (my >= 0 && my < horizon) {
              const tw = ceil.w, th = ceil.h;
              const tx = (fx * tw / 1024) | 0;
              const ty = (fy * th / 1024) | 0;
              const word = mv.getInt32((ceil.base + ty * tw + tx) * 4, true);
              const fbIdx = (my * W + col) * 4;
              fb[fbIdx]     = (word >>> 24) & 0xFF;
              fb[fbIdx + 1] = (word >>> 16) & 0xFF;
              fb[fbIdx + 2] = (word >>>  8) & 0xFF;
              fb[fbIdx + 3] = (word & 0xFF) || 0xFF;
            }
          }
        }
        return 0;
      }

      // sys(Sys_drawwallcol, col, y0, y1, y_anchor, v_step_q16, texX,
      //                       tex_base, pkd_wh)
      // Doom-style textured wall column. Per-pixel V is computed as
      //   V = ((y - y_anchor) * v_step_q16) >> 16
      // wrapped modulo tex_h so tall walls tile vertically rather than
      // stretching. pkd_wh = (tex_w & 0xFFFF) | (tex_h << 16).
      // sys(Sys_drawskyspan, col, y0, y1, u) — sky cylinder span.
      // Reads from cached sky tex (Sys_setbgtex slot 0). V is mapped
      // by absolute screen y, so sky doesn't tilt as camera rises.
      case 89: {
        const col = a1 | 0;
        const y0  = a2 | 0;
        const y1  = a3 | 0;
        const u   = a4 | 0;
        const fb  = this._fb;
        const bg  = this._bgTex;
        if (!fb || !bg || !bg[0]) return 0;
        const tex = bg[0];
        const W = this._fbW, H = this._fbH;
        if (col < 0 || col >= W) return 0;
        let yy0 = y0, yy1 = y1;
        if (yy0 < 0) yy0 = 0;
        if (yy1 >= H) yy1 = H - 1;
        if (yy0 > yy1) return 0;
        const horizon = H >> 1;
        const tw = tex.w, th = tex.h;
        const tx = ((u % tw) + tw) % tw;
        const stride = W * 4;
        const mv = this.memView;
        let fbIdx = (yy0 * W + col) * 4;
        for (let y = yy0; y <= yy1; y++) {
          let tY = Math.floor(y * th / horizon);
          if (tY < 0) tY = 0; else if (tY >= th) tY = th - 1;
          const word = mv.getInt32((tex.base + tY * tw + tx) * 4, true);
          fb[fbIdx]     = (word >>> 24) & 0xFF;
          fb[fbIdx + 1] = (word >>> 16) & 0xFF;
          fb[fbIdx + 2] = (word >>>  8) & 0xFF;
          fb[fbIdx + 3] = (word & 0xFF) || 0xFF;
          fbIdx += stride;
        }
        return 0;
      }

      // sys(Sys_setdepth, cy) — cache the per-column depth value the
      // next opaque draw will write into the z-buffer, and the depth
      // sprites compare against. World units.
      case 90: {
        this._zVal = a1 | 0;
        return 0;
      }
      // sys(Sys_clearzbuf) — reset the z-buffer to "infinity" so a
      // new frame starts fresh. Also wipes the back framebuffer so
      // any column the renderer doesn't subsequently touch shows
      // black instead of stale pixels from the previous frame.
      case 91: {
        if (this._zBuf) this._zBuf.fill(0x7FFFFFFF);
        if (this._fb)   this._fb.fill(0);
        return 0;
      }
      // sys(Sys_playmusic, name_str, loop_flag) — start an HTMLAudio
      // element on the named binary asset (.ogg / .mp3 / .wav). Stops
      // any previous track. loop_flag=1 → continuous play.
      case 92: {
        const name = this.readBcplString(a1);
        const loop = !!(a2 | 0);
        const rec = assetBackend.get(name);
        if (!rec || !rec.bytes) return 0;
        try {
          if (this._musicAudio) {
            this._musicAudio.pause();
            if (this._musicURL) URL.revokeObjectURL(this._musicURL);
          }
          const lower = name.toLowerCase();
          const mime = lower.endsWith(".ogg")  ? "audio/ogg"
                     : lower.endsWith(".mp3")  ? "audio/mpeg"
                     : lower.endsWith(".wav")  ? "audio/wav"
                     : lower.endsWith(".flac") ? "audio/flac"
                     :                            "audio/mpeg";
          const blob = new Blob([rec.bytes], { type: mime });
          const url  = URL.createObjectURL(blob);
          const aud  = new Audio(url);
          aud.loop  = loop;
          aud.volume = 0.55;
          aud.play().catch(() => { /* user-gesture gate — caller can retry */ });
          this._musicAudio = aud;
          this._musicURL   = url;
        } catch { /* swallow */ }
        return 0;
      }
      // sys(Sys_playmus, word_base, byte_offset, byte_size, loop) —
      // play a MUS lump straight out of wasm memory (no asset upload
      // needed). word_base*4 + byte_offset is the byte address of
      // the lump's first byte; byte_size is the lump length. If a
      // SoundFont has been loaded via Sys_loadsf2, the MUS is
      // converted to MIDI and routed through spessasynth; otherwise
      // the built-in oscillator player handles it.
      case 94: {
        const wbase = a1 | 0;
        const off   = a2 | 0;
        const size  = a3 | 0;
        const loop  = !!(a4 | 0);
        if (size <= 0) return 0;
        const startByte = wbase * 4 + off;
        const bytes = new Uint8Array(
          this.mem.buffer.slice(startByte, startByte + size));
        try {
          const Ctor = (typeof window !== "undefined") ? (window.AudioContext || window.webkitAudioContext) : null;
          if (!Ctor) return 0;
          if (!this._audioCtx) this._audioCtx = new Ctor();
          if (this._sf2Player && (this._sf2Player.ready || this._sf2Player.loading)) {
            const midi = mus2mid(bytes);
            if (midi) {
              if (this._musPlayer) { this._musPlayer.stop(); this._musPlayer = null; }
              this._sf2Player.playMidi(midi, loop);
              return 0;
            }
          }
          if (this._musPlayer) this._musPlayer.stop();
          this._musPlayer = new MusPlayer(this._audioCtx, bytes, loop);
          this._musPlayer.play();
        } catch { /* swallow */ }
        return 0;
      }

      // sys(Sys_loadsf2, name_str) — load a binary asset (.sf2) as
      // the active SoundFont for Sys_playmus. Returns 1 on success,
      // 0 if asset missing or spessasynth init fails. First call
      // lazily boots the AudioWorklet (async; user code that wants
      // music on the very first beat should call this near start()
      // and accept a few hundred ms before notes begin sounding).
      case 95: {
        const name = this.readBcplString(a1);
        const rec = assetBackend.get(name);
        if (!rec || !rec.bytes) return 0;
        try {
          const Ctor = (typeof window !== "undefined") ? (window.AudioContext || window.webkitAudioContext) : null;
          if (!Ctor) return 0;
          if (!this._audioCtx) this._audioCtx = new Ctor();
          if (!this._sf2Player) this._sf2Player = new SF2MusPlayer(this._audioCtx);
          const buf = rec.bytes.buffer.slice(rec.bytes.byteOffset,
                                             rec.bytes.byteOffset + rec.bytes.byteLength);
          this._sf2Player._loadInflight = true;
          this._sf2Player.loadSF2(buf)
            .then(() => { this._sf2Player._loadInflight = false; })
            .catch(() => { this._sf2Player._loadInflight = false; });
          return 1;
        } catch { return 0; }
      }
      // sys(Sys_stopmusic) — pause + free the current music track.
      case 93: {
        if (this._musicAudio) {
          this._musicAudio.pause();
          this._musicAudio = null;
        }
        if (this._musicURL) {
          URL.revokeObjectURL(this._musicURL);
          this._musicURL = null;
        }
        if (this._musPlayer) {
          this._musPlayer.stop();
          this._musPlayer = null;
        }
        if (this._sf2Player) this._sf2Player.stop();
        return 0;
      }

      // ---- WebSocket client (browser only) -----------------------------
      // BCPL pattern: open returns an integer handle; send/recv/close
      // take that handle. recv is non-blocking — returns 0 when the
      // queue is empty so user code can poll inside its game loop.
      // Underlying transport is the browser WebSocket; async events
      // pump bytes into a per-handle queue we drain on demand.

      // sys(Sys_ws_open, url_bstr) → handle, or -1 on failure
      case 96: {
        if (typeof WebSocket === "undefined") return -1;
        const url = this.readBcplString(a1);
        if (!this._wsMap) { this._wsMap = new Map(); this._wsNext = 1; }
        let ws;
        try { ws = new WebSocket(url); }
        catch { return -1; }
        ws.binaryType = "arraybuffer";
        const h = this._wsNext++;
        const rec = { ws, queue: [], state: 0, closed: false };
        ws.onopen    = () => { rec.state = 1; };
        ws.onclose   = () => { rec.state = 3; rec.closed = true; };
        ws.onerror   = () => { rec.state = 3; rec.closed = true; };
        ws.onmessage = (ev) => {
          if (typeof ev.data === "string") {
            rec.queue.push(new TextEncoder().encode(ev.data));
          } else if (ev.data instanceof ArrayBuffer) {
            rec.queue.push(new Uint8Array(ev.data));
          }
        };
        this._wsMap.set(h, rec);
        return h;
      }

      // sys(Sys_ws_send, h, buf_word, byte_len) → 0 ok, -1 fail
      case 97: {
        const rec = this._wsMap?.get(a1);
        if (!rec || rec.state !== 1) return -1;
        // Read len bytes starting at the buffer's byte address.
        const byteOff = (a2 | 0) * 4;
        const bytes = new Uint8Array(this.mem.buffer, byteOff, a3 | 0).slice();
        try { rec.ws.send(bytes); } catch { return -1; }
        return 0;
      }

      // sys(Sys_ws_recv, h, buf_word, max_bytes)
      //   → n bytes copied, 0 if queue empty, -1 if closed AND empty
      case 98: {
        const rec = this._wsMap?.get(a1);
        if (!rec) return -1;
        if (rec.queue.length === 0) return rec.closed ? -1 : 0;
        const msg = rec.queue[0];
        const max = a3 | 0;
        if (msg.length > max) return -2;        // caller's buffer too small
        const byteOff = (a2 | 0) * 4;
        new Uint8Array(this.mem.buffer, byteOff, msg.length).set(msg);
        rec.queue.shift();
        return msg.length;
      }

      // sys(Sys_ws_status, h)
      //   → 0=connecting, 1=open, 2=closing, 3=closed, -1=bad handle
      case 99: {
        const rec = this._wsMap?.get(a1);
        if (!rec) return -1;
        return rec.state;
      }

      // sys(Sys_ws_close, h) → 0
      case 100: {
        const rec = this._wsMap?.get(a1);
        if (rec) {
          try { rec.ws.close(); } catch {}
          this._wsMap.delete(a1);
        }
        return 0;
      }

      // sys(Sys_setlight, light_0_255) — cache light scale for the
      // subsequent drawwallcol / drawflatspan calls. Stored as 0..256
      // (256 = full bright, used as `(channel * scale) >> 8`).
      case 88: {
        let l = a1 | 0;
        if (l < 0) l = 0; else if (l > 255) l = 255;
        // Map 255 → 256 so the common full-bright case is multiply-shift
        // identity (255*256 >> 8 = 255 still).
        this._lightScale = l === 255 ? 256 : l;
        return 0;
      }

      // sys(Sys_drawflatspan, col, y0, y1, cam_above, px, py, raydxy_pkd, flat_base)
      // Doom-style textured floor / ceiling span for one screen column.
      // cam_above > 0 → floor (camera above floor plane);
      // cam_above < 0 → ceiling (camera below ceiling plane).
      // Flat texture is 64×64 packed RGBA at flat_base (word addr).
      case 87: {
        const col      = a1 | 0;
        const y_top    = a2 | 0;
        const y_bot    = a3 | 0;
        const cam_above = a4 | 0;
        const px       = a5 | 0;
        const py       = a6 | 0;
        const raydxy   = a7 | 0;
        const flat_base = a8 | 0;
        const fb = this._fb;
        if (!fb || cam_above === 0 || !flat_base) return 0;
        const W = this._fbW, H = this._fbH;
        if (col < 0 || col >= W) return 0;
        let y0 = y_top, y1 = y_bot;
        if (y0 < 0) y0 = 0;
        if (y1 >= H) y1 = H - 1;
        if (y0 > y1) return 0;
        // Sign-extend dx (low 16) and dy (high 16) from raydxy.
        const ray_dx = (raydxy << 16) >> 16;
        const ray_dy = raydxy >> 16;
        const horizon = H >> 1;
        const F_X = W >> 1;
        const cam_abs = Math.abs(cam_above);
        const is_ceil = cam_above < 0;
        const mv = this.memView;
        const stride = W * 4;
        const ls = this._lightScale ?? 256;
        const zBuf = this._zBuf;
        let fbIdx = (y0 * W + col) * 4;
        let zIdx  = y0 * W + col;
        for (let y = y0; y <= y1; y++) {
          const delta_y = is_ceil ? (horizon - y) : (y - horizon);
          if (delta_y > 0) {
            const rowDist = (cam_abs * F_X / delta_y) | 0;
            const worldX = px + ((rowDist * ray_dx) / 1024 | 0);
            const worldY = py + ((rowDist * ray_dy) / 1024 | 0);
            const tx = ((worldX % 64) + 64) & 63;
            const ty = ((worldY % 64) + 64) & 63;
            const word = mv.getInt32((flat_base + ty * 64 + tx) * 4, true);
            if (ls >= 256) {
              fb[fbIdx]     = (word >>> 24) & 0xFF;
              fb[fbIdx + 1] = (word >>> 16) & 0xFF;
              fb[fbIdx + 2] = (word >>>  8) & 0xFF;
            } else {
              fb[fbIdx]     = (((word >>> 24) & 0xFF) * ls) >> 8;
              fb[fbIdx + 1] = (((word >>> 16) & 0xFF) * ls) >> 8;
              fb[fbIdx + 2] = (((word >>>  8) & 0xFF) * ls) >> 8;
            }
            fb[fbIdx + 3] = (word & 0xFF) || 0xFF;
            if (zBuf) zBuf[zIdx] = rowDist;
          }
          fbIdx += stride;
          zIdx += W;
        }
        return 0;
      }

      case 86: {
        const col_x     = a1 | 0;
        const y_top     = a2 | 0;
        const y_bot     = a3 | 0;
        const y_anchor  = a4 | 0;
        const v_step_raw = a5 | 0;        // Q16.16; negative = transparency mode
        const transparent = v_step_raw < 0;
        const v_step    = transparent ? -v_step_raw : v_step_raw;
        const texX      = a6 | 0;
        const tex_base  = a7 | 0;
        const pkd       = a8 | 0;
        const tex_w     = pkd & 0xFFFF;
        const tex_h     = (pkd >>> 16) & 0xFFFF;
        const fb        = this._fb;
        if (!fb || tex_w <= 0 || tex_h <= 0) return 0;
        if (y_top > y_bot) return 0;
        const W = this._fbW, H = this._fbH;
        if (col_x < 0 || col_x >= W) return 0;
        let y0 = y_top, y1 = y_bot;
        if (y0 < 0) y0 = 0;
        if (y1 >= H) y1 = H - 1;
        if (y0 > y1) return 0;
        const mv = this.memView;
        const tx = ((texX % tex_w) + tex_w) % tex_w;
        const texColBase = tex_base + tx;
        let vQ = (y0 - y_anchor) * v_step;
        const stride = W * 4;
        let fbIdx = (y0 * W + col_x) * 4;
        const ls = this._lightScale ?? 256;
        const bright = ls >= 256;
        const z = this._zVal | 0;
        const zBuf = this._zBuf;
        // Walls are opaque → write z + colour.
        // Sprites use `transparent` (negated v_step) → z-TEST: only
        // paint when this depth beats whatever's already there.
        let zIdx = y0 * W + col_x;
        for (let y = y0; y <= y1; y++) {
          let vRaw = vQ >> 16;
          let v = vRaw % tex_h;
          if (v < 0) v += tex_h;
          const word = mv.getInt32((texColBase + v * tex_w) * 4, true);
          let drawPixel = true;
          if (transparent) {
            drawPixel = word !== 0 && (zBuf ? z < zBuf[zIdx] : true);
          }
          if (drawPixel) {
            if (bright) {
              fb[fbIdx]     = (word >>> 24) & 0xFF;
              fb[fbIdx + 1] = (word >>> 16) & 0xFF;
              fb[fbIdx + 2] = (word >>>  8) & 0xFF;
            } else {
              fb[fbIdx]     = (((word >>> 24) & 0xFF) * ls) >> 8;
              fb[fbIdx + 1] = (((word >>> 16) & 0xFF) * ls) >> 8;
              fb[fbIdx + 2] = (((word >>>  8) & 0xFF) * ls) >> 8;
            }
            fb[fbIdx + 3] = (word & 0xFF) || 0xFF;
            if (!transparent && zBuf) zBuf[zIdx] = z;
          }
          fbIdx += stride;
          zIdx += W;
          vQ   += v_step;
        }
        return 0;
      }

      // sys(Sys_assetlist, dest_str) — copy a comma-separated list of
      // asset names into dest_str (BCPL string layout). Useful for
      // discovery. Returns count.
      case 81: {
        const names = assetBackend.list();
        const joined = names.join(",");
        const dest = a1;
        const len = Math.min(joined.length, 255);
        this.memView.setUint8(dest * 4, len);
        for (let i = 0; i < len; i++) {
          this.memView.setUint8(dest * 4 + 1 + i, joined.charCodeAt(i) & 0xFF);
        }
        return names.length;
      }

      default:
        // Unknown syscall — return 0 rather than trap.
        return 0;
    }
  }

  // level() — BCPL captures current stack frame pointer for later
  // longjump. We return the current $P (a word address) as a
  // "level" handle. longjump restores $P to that value.
  imp_level() {
    this.restoreP();
    return this.P;
  }

  // longjump(p, l) — non-local transfer. For simplicity, we treat
  // this as a hard halt with the given label code.
  imp_longjump() {
    const p = this.arg(0);
    const l = this.arg(1);
    this.restoreP();
    throw new BcplHalt(l, /*isAbort*/ true);
  }

  // pathfindinput(name, path) — try to open `name` via a search path.
  // Fallback to plain findinput.
  imp_pathfindinput() {
    const nameArg = this.arg(0);
    this.restoreP();
    if (!nameArg) return 0;
    const name = this.readBcplString(nameArg);
    const data = storageBackend.get(name);
    if (data === null) return 0;
    return this._allocStream({ kind: "file", mode: "r", name, data, pos: 0 });
  }

  // stop(n) — explicit halt with exit code. Alias of imp_stop but
  // kept distinct in the table so we can tell an intentional
  // stop(n) apart from a call into slot 0 (unassigned global).
  imp_stop_fn() {
    this.finished = true;
    throw new BcplHalt(this.arg(0));
  }

  // rdargs(argform, argv, argvsize) — parse command-line style input
  // (one line from stdin) against a BCPL argform spec. Supports /A
  // (required positional), /K (keyword with value), /S (switch), /N
  // (numeric). Writes BCPL-string pointers (or -1 for set switches,
  // or raw integers for /N) into argv slots in declaration order.
  //
  // argform example: "FROM/A,TO/K,ERR/K,SIZE/K/N,NONAMES/S,..."
  imp_rdargs() {
    const argform = this.readBcplString(this.arg(0));
    const argvWord = this.arg(1);
    const argvSize = this.arg(2);
    this.restoreP();

    // Read one stdin line as the command string.
    let line = "";
    let ch = this._readChar();
    while (ch !== -1 && ch !== 10) {
      line += String.fromCharCode(ch);
      ch = this._readChar();
    }
    const tokens = line.trim().split(/\s+/).filter(Boolean);

    // Parse argform into slots: [{name, flags:Set('A'|'K'|'S'|'N')}, ...]
    const slots = argform.split(",").map((spec) => {
      const parts = spec.trim().split("/");
      return { name: parts[0].toUpperCase(), flags: new Set(parts.slice(1).map(p => p.toUpperCase())) };
    });
    const values = new Array(slots.length).fill(null);

    const writeBcplString = (s) => {
      const total = s.length + 1;
      const words = Math.ceil(total / 4);
      this.heapTop -= words;
      const base = this.heapTop;
      const baseByte = base * 4;
      this.memView.setUint8(baseByte, s.length & 0xFF);
      for (let i = 0; i < s.length; i++) {
        this.memView.setUint8(baseByte + 1 + i, s.charCodeAt(i) & 0xFF);
      }
      for (let i = total; i < words * 4; i++) {
        this.memView.setUint8(baseByte + i, 0);
      }
      return base;
    };

    // Find slot by keyword name (case-insensitive).
    const findSlot = (nm) => slots.findIndex(s => s.name === nm.toUpperCase());

    let nextPositional = 0;
    const advancePositional = () => {
      while (nextPositional < slots.length
             && (slots[nextPositional].flags.has("S")
                 || (slots[nextPositional].flags.has("K") && !slots[nextPositional].flags.has("A"))
                 || values[nextPositional] !== null)) {
        nextPositional++;
      }
      return nextPositional < slots.length ? nextPositional++ : -1;
    };

    for (let i = 0; i < tokens.length; i++) {
      const tok = tokens[i];
      const keyIdx = findSlot(tok);
      if (keyIdx >= 0) {
        const slot = slots[keyIdx];
        if (slot.flags.has("S")) { values[keyIdx] = -1; continue; }
        // /K or /K/N or /A takes a following value.
        if (i + 1 >= tokens.length) break;
        const val = tokens[++i];
        values[keyIdx] = slot.flags.has("N") ? (parseInt(val, 10) | 0) : val;
        continue;
      }
      const pi = advancePositional();
      if (pi < 0) break;
      const slot = slots[pi];
      values[pi] = slot.flags.has("N") ? (parseInt(tok, 10) | 0) : tok;
    }

    // Write into argv. /N slots: allocate a word, write int there,
    // store pointer (BCPL rdargs convention: argv!i -> int cell).
    const writeIntCell = (n) => {
      this.heapTop -= 1;
      this.storeWord(this.heapTop, n | 0);
      return this.heapTop;
    };
    for (let i = 0; i < argvSize; i++) this.storeWord(argvWord + i, 0);
    for (let i = 0; i < slots.length && i < argvSize; i++) {
      const v = values[i];
      if (v === null) { this.storeWord(argvWord + i, 0); continue; }
      if (typeof v === "number") {
        if (v === -1) { this.storeWord(argvWord + i, -1); continue; }  // /S switch
        this.storeWord(argvWord + i, writeIntCell(v));
        continue;
      }
      this.storeWord(argvWord + i, writeBcplString(v));
    }
    // /A fields must be filled or rdargs fails.
    for (let i = 0; i < slots.length; i++) {
      if (slots[i].flags.has("A") && values[i] === null) return 0;
    }
    return argvWord || 1;  // non-zero = success
  }

  // Allocate a new stream record, attach an SCB struct in linear
  // memory, register in the scbPtr→record map, and return the scbPtr
  // (BCPL handle). The handle IS the word address of the SCB so user
  // code can read s!scb_pos, s!scb_end, s!scb_id directly.
  _allocStream(rec) {
    const scbPtr = this._allocScbPtr();
    rec.scbPtr = scbPtr;
    const idCode = this._scbIdForMode(rec.mode);
    const typeCode = this._scbTypeForKind(rec.kind);
    this._initScbFields(scbPtr, { idCode, typeCode, name: rec.name });
    this._scbToStream.set(scbPtr, rec);
    this._syncScb(rec);
    return scbPtr;
  }

  _scbIdForMode(mode) {
    switch (mode) {
      case "r":  return BcplRuntime.SCB_ID_IN;
      case "w":  return BcplRuntime.SCB_ID_OUT;
      case "rw": return BcplRuntime.SCB_ID_INOUT;
      case "a":  return BcplRuntime.SCB_ID_APPEND;
      default:   return BcplRuntime.SCB_ID_IN;
    }
  }
  _scbTypeForKind(kind) {
    switch (kind) {
      case "stdin": case "stdout": return BcplRuntime.SCB_T_CONSOLE;
      case "ram": case "nil":      return BcplRuntime.SCB_T_RAM;
      case "file":                 return BcplRuntime.SCB_T_FILE;
      default:                     return BcplRuntime.SCB_T_RAM;
    }
  }

  _freeStream(scbPtr) {
    if (!scbPtr) return;
    this._scbToStream.delete(scbPtr);
    // SCB slab leaks (heap is bump-only). Acceptable for playground.
  }

  // findoutput(name) — open a new write stream backed by storage.
  // Truncates any prior contents. Returns a stream handle, or 0 on
  // failure.
  imp_findoutput() {
    const name = this.readBcplString(this.arg(0));
    this.restoreP();
    if (!name) return 0;
    const spec = this._streamSpec(name);
    if (spec.kind === "nil") {
      return this._allocStream({ kind: "nil", mode: "w", name, data: "", pos: 0 });
    }
    if (spec.kind === "ram") {
      return this._allocStream({ kind: "ram", mode: "w", name, data: "", pos: 0 });
    }
    return this._allocStream({ kind: "file", mode: "w", name, data: "", pos: 0 });
  }

  // findinput(name) — open a stream for reading.
  // RAM:/NIL: return an empty stream. For real files, returns 0 if
  // no entry under that name exists in storage.
  imp_findinput() {
    const name = this.readBcplString(this.arg(0));
    this.restoreP();
    if (!name) return 0;
    const spec = this._streamSpec(name);
    if (spec.kind === "nil") {
      return this._allocStream({ kind: "nil", mode: "r", name, data: "", pos: 0 });
    }
    if (spec.kind === "ram") {
      return this._allocStream({ kind: "ram", mode: "r", name, data: "", pos: 0 });
    }
    const data = storageBackend.get(name);
    if (data === null) return 0;
    return this._allocStream({ kind: "file", mode: "r", name, data, pos: 0 });
  }

  // findappend(name) — open a stream that appends to the end of an
  // existing file. If the file doesn't exist, creates an empty one.
  // CIN:y in the BCPL manual; not implemented previously.
  imp_findappend() {
    const name = this.readBcplString(this.arg(0));
    this.restoreP();
    if (!name) return 0;
    const spec = this._streamSpec(name);
    if (spec.kind === "nil") {
      return this._allocStream({ kind: "nil", mode: "w", name, data: "", pos: 0 });
    }
    if (spec.kind === "ram") {
      // RAM: streams have no on-disk backing — start fresh.
      return this._allocStream({ kind: "ram", mode: "w", name, data: "", pos: 0 });
    }
    const existing = storageBackend.get(name) ?? "";
    // pos is where the next write goes — past the existing content.
    return this._allocStream({
      kind: "file", mode: "w", name, data: existing, pos: existing.length,
    });
  }

  // appendstream(scb) — move a currently-open stream's write
  // position to its end so subsequent writes append. Returns -1
  // on success, 0 if the handle is bad.
  imp_appendstream() {
    const h = this.arg(0);
    this.restoreP();
    const s = this._stream(h);
    if (!s) return 0;
    s.pos = (s.data || "").length;
    return -1;
  }

  // deletefile(name) — remove the named entry from storage. Returns
  // -1 on success, 0 if it wasn't there.
  imp_deletefile() {
    const name = this.readBcplString(this.arg(0));
    this.restoreP();
    if (!name) return 0;
    if (storageBackend.get(name) === null) return 0;
    storageBackend.del?.(name);
    return -1;
  }

  // renamefile(old, new) — atomic rename in storage. Returns -1 on
  // success, 0 on failure (old missing OR new already exists).
  imp_renamefile() {
    const oldName = this.readBcplString(this.arg(0));
    const newName = this.readBcplString(this.arg(1));
    this.restoreP();
    if (!oldName || !newName) return 0;
    const data = storageBackend.get(oldName);
    if (data === null) return 0;
    if (storageBackend.get(newName) !== null) return 0;
    storageBackend.set(newName, data);
    storageBackend.del?.(oldName);
    return -1;
  }

  // datstamp(v) — fill v[0..2] with the current date/time:
  //   v!0 = days since 1 Jan 1978 (BCPL epoch)
  //   v!1 = ms since midnight (UTC)
  //   v!2 = ticks since system boot (ms here)
  // Same payload Sys_datstamp delivers; this is the high-level wrapper.
  imp_datstamp() {
    const v = this.arg(0);
    this.restoreP();
    const ms = Date.now();
    const EPOCH_1978 = Date.UTC(1978, 0, 1);
    const days = Math.floor((ms - EPOCH_1978) / 86400000);
    const dayMs = ms - EPOCH_1978 - days * 86400000;
    this.storeWord(v + 0, days | 0);
    this.storeWord(v + 1, dayMs | 0);
    this.storeWord(v + 2, (performance.now() | 0));
    return v;
  }

  // -------- byte-position primitives (point / note) --------
  //
  // BCPL streams use a (block, byteOffset) pair for random-access
  // positioning; recordpoint / recordnote compose on top of these.
  // The playground's stream model is a flat byte buffer (s.data + s.pos);
  // we encode positions with a virtual block size = the buffer's
  // current end (s.data.length, never zero). That keeps muldiv math
  // identical to cintsys / blib while staying single-buffer.
  _streamBlockSize(s) {
    const n = (s.data || "").length;
    return n > 0 ? n : 1;
  }

  // point(scb, posv) — set the stream's read/write position from a
  // (block, offset) vector. Returns -1 on success, 0 if scb invalid.
  imp_point() {
    const h    = this.arg(0);
    const posv = this.arg(1);
    this.restoreP();
    const s = this._stream(h);
    if (!s) return 0;
    const block  = this.loadWord(posv + 0);
    const offset = this.loadWord(posv + 1);
    const bs = this._streamBlockSize(s);
    const newPos = (block * bs) + offset;
    s.pos = newPos | 0;
    this.storeWord(h + BcplRuntime.SCB.pos, s.pos);
    return -1;
  }

  // note(scb, posv) — read the stream's current position into posv:
  //   posv!0 = block, posv!1 = byte offset within block. Returns -1.
  imp_note() {
    const h    = this.arg(0);
    const posv = this.arg(1);
    this.restoreP();
    const s = this._stream(h);
    if (!s) return 0;
    const bs = this._streamBlockSize(s);
    const block  = Math.floor(s.pos / bs) | 0;
    const offset = (s.pos - block * bs) | 0;
    this.storeWord(posv + 0, block);
    this.storeWord(posv + 1, offset);
    return -1;
  }

  // -------- record-mode (fixed-size records) --------
  //
  // setrecordlength stashes the byte-length on the SCB struct (slot 15
  // matches BcplRuntime.SCB.reclen). recordpoint seeks to a record by
  // number; recordnote returns the current record number; get_record /
  // put_record copy reclen bytes into / out of a BCPL byte vector.

  // setrecordlength(scb, length) → previous length. length in bytes.
  imp_setrecordlength() {
    const h   = this.arg(0);
    const len = this.arg(1) | 0;
    this.restoreP();
    if (!this._stream(h)) return 0;
    const slot = h + BcplRuntime.SCB.reclen;
    const old = this.loadWord(slot);
    this.storeWord(slot, len);
    return old | 0;
  }

  // recordpoint(scb, recno) — seek so the next get_record/put_record
  // hits record `recno`. Returns -1 on success, 0 on bad reclen / scb.
  imp_recordpoint() {
    const h     = this.arg(0);
    const recno = this.arg(1) | 0;
    this.restoreP();
    const s = this._stream(h);
    if (!s) return 0;
    const reclen = this.loadWord(h + BcplRuntime.SCB.reclen) | 0;
    if (reclen <= 0 || recno < 0) return 0;
    s.pos = (recno * reclen) | 0;
    this.storeWord(h + BcplRuntime.SCB.pos, s.pos);
    return -1;
  }

  // recordnote(scb) → current record number. Returns -1 if no reclen.
  imp_recordnote() {
    const h = this.arg(0);
    this.restoreP();
    const s = this._stream(h);
    if (!s) return -1;
    const reclen = this.loadWord(h + BcplRuntime.SCB.reclen) | 0;
    if (reclen <= 0) return -1;
    return (s.pos / reclen) | 0;
  }

  // get_record(vector, recno, scb) — read reclen bytes of record
  // `recno` into the byte vector (vector%0..vector%(reclen-1)).
  // Returns TRUE on success, FALSE on EOF / bad scb / no reclen.
  imp_get_record() {
    const vec   = this.arg(0);
    const recno = this.arg(1) | 0;
    const h     = this.arg(2);
    this.restoreP();
    const s = this._stream(h);
    if (!s) return 0;
    const reclen = this.loadWord(h + BcplRuntime.SCB.reclen) | 0;
    if (reclen <= 0) return 0;
    const start = recno * reclen;
    const data = s.data || "";
    if (start + reclen > data.length) return 0;
    for (let i = 0; i < reclen; i++) {
      this.storeByte(vec * 4 + i, data.charCodeAt(start + i) & 0xFF);
    }
    s.pos = (start + reclen) | 0;
    this.storeWord(h + BcplRuntime.SCB.pos, s.pos);
    return -1;   // TRUE
  }

  // put_record(vector, recno, scb) — write reclen bytes from the
  // byte vector into record `recno` of the stream. Extends data if
  // recno is past the current end. Returns TRUE on success, FALSE
  // on bad scb / no reclen / wrong mode.
  imp_put_record() {
    const vec   = this.arg(0);
    const recno = this.arg(1) | 0;
    const h     = this.arg(2);
    this.restoreP();
    const s = this._stream(h);
    if (!s) return 0;
    if (s.mode !== "w" && s.mode !== "rw") return 0;
    const reclen = this.loadWord(h + BcplRuntime.SCB.reclen) | 0;
    if (reclen <= 0 || recno < 0) return 0;
    const start = recno * reclen;
    let data = s.data || "";
    if (start > data.length) data = data + " ".repeat(start - data.length);
    let bytes = "";
    for (let i = 0; i < reclen; i++) {
      bytes += String.fromCharCode(this.loadByte(vec * 4 + i) & 0xFF);
    }
    s.data = data.slice(0, start) + bytes + data.slice(start + reclen);
    s.pos = (start + reclen) | 0;
    this.storeWord(h + BcplRuntime.SCB.pos, s.pos);
    const newEnd = s.data.length;
    this.storeWord(h + BcplRuntime.SCB.end,    newEnd);
    this.storeWord(h + BcplRuntime.SCB.bufend, newEnd);
    return -1;   // TRUE
  }

  // writebin(n, d) — write n as an unsigned binary integer in a
  // d-character field, zero-padded. blib's writef("%b", n) routes
  // through the same logic; exposing this as a standalone global so
  // user code can call it without going through writef.
  imp_writebin() {
    const n = this.arg(0) | 0;
    const d = this.arg(1) | 0;
    this.restoreP();
    let s = (n >>> 0).toString(2);
    if (d > s.length) s = "0".repeat(d - s.length) + s;
    this.writeOut(s);
    return 0;
  }

  // ---- diagnostic helpers (mirror of sysb/blib.b additions) --------
  //
  // BcplHalt thrown with `isAbort: true` reaches the playground crash
  // handler the same way a Sys_quit abort does — user gets the message
  // in the Output pane and the Diag tab gets the assert site.

  // assert(cond, msg_bstr) — cond=FALSE → abort with the BCPL string.
  imp_assert() {
    const cond = this.arg(0);
    const msgPtr = this.arg(1);
    this.restoreP();
    if (cond) return 0;
    const msg = this.readBcplString(msgPtr);
    this.writeOut("\nASSERT FAIL: " + msg + "\n");
    throw new BcplHalt(901, /*isAbort*/ true);
  }

  // getvec_or_abort(n, msg_bstr) — getvec with a labelled OOM abort.
  // Wraps the existing getvec path. Caller still gets a BCPL word
  // address on success; failure throws instead of silently returning 0.
  imp_getvec_or_abort() {
    const n = this.arg(0) | 0;
    const msgPtr = this.arg(1);
    const size = n + 1;
    let prev = 0, cur = this.freeList;
    let bestPrev = 0, best = 0, bestSize = 0x7fffffff;
    while (cur !== 0) {
      const blockSize = this.vecSizes.get(cur) | 0;
      const next = this.loadWord(cur);
      if (blockSize >= size && blockSize < bestSize) {
        bestPrev = prev; best = cur; bestSize = blockSize;
        if (blockSize === size) break;
      }
      prev = cur; cur = next;
    }
    if (best !== 0) {
      const next = this.loadWord(best);
      if (bestPrev === 0) this.freeList = next;
      else this.storeWord(bestPrev, next);
      this.restoreP();
      return best;
    }
    this.heapTop -= size;
    if (this.heapTop <= 0) {
      this.restoreP();
      const msg = this.readBcplString(msgPtr);
      this.writeOut("\nGETVEC OOM: " + msg + " (requested " + n + " words)\n");
      throw new BcplHalt(901, /*isAbort*/ true);
    }
    const p = this.heapTop;
    this.vecSizes.set(p, size);
    this.restoreP();
    return p;
  }

  // vsafe_get(v, i, msg_bstr) — v!i with bounds check.
  //
  // Playground getvec stores its size header at v!+1 (see
  // imp_getvec line ~1204) rather than cintsys's v!-1 convention,
  // so the read site differs from the BLIB BCPL impl.  Both runtimes
  // present the same `vsafe_get(v, i, msg)` user-facing API.
  //
  // size header = N+1 (allocation includes the header word). Valid
  // user indices: 0..N-1 = 0..(size-2). Allow up to size-2 inclusive.
  imp_vsafe_get() {
    const v = this.arg(0) | 0;
    const i = this.arg(1) | 0;
    const msgPtr = this.arg(2);
    this.restoreP();
    if (v === 0) {
      const msg = this.readBcplString(msgPtr);
      this.writeOut("\nVSAFE OOB: " + msg + " (v=NULL)\n");
      throw new BcplHalt(901, /*isAbort*/ true);
    }
    const sizeHdr = this.vecSizes.get(v) | 0;  // side-table lookup
    const upb     = sizeHdr - 1;                // size = n+1, upb = n
    if (sizeHdr === 0 || i < 0 || i > upb) {
      const msg = this.readBcplString(msgPtr);
      this.writeOut("\nVSAFE OOB: " + msg + " (i=" + i + " upb=" + upb + ")\n");
      throw new BcplHalt(901, /*isAbort*/ true);
    }
    return this.loadWord(v + i);
  }

  // delayuntil(days, msecs) — sleep until the wall clock reaches the
  // given (days since 1 Jan 1978, ms since midnight) point. Computes
  // the wait in ms and reuses the asyncify-based delay path. If the
  // target is already past, returns immediately.
  imp_delayuntil() {
    const days = this.arg(0) | 0;
    const dayMs = this.arg(1) | 0;
    const exp = this._coroutineExportsRequired();
    if (!exp) { this.restoreP(); return 0; }
    if (this._asyncifyMode === "rewinding") {
      this._asyncifyAllStopRewind();
      this._asyncifyMode = "normal";
      this.restoreP();
      return 0;
    }
    const EPOCH_1978 = Date.UTC(1978, 0, 1);
    const target = EPOCH_1978 + days * 86400000 + dayMs;
    const wait = Math.max(0, target - Date.now());
    this.restoreP();
    const co = this._currentCo ?? this._rootCo;
    if (!co) return 0;
    this._resetAsyncifyBuffer(co.asyncifyData, co.asyncifyWords ?? 256);
    co.savedP = this.P;
    co.status = "suspended";
    this._delayMs = wait;
    this._scheduleResume = co.handle;
    this._asyncifyAllStartUnwind(co.asyncifyData);
    this._asyncifyMode = "unwinding";
    return 0;
  }

  // selectoutput(scbPtr) — make scbPtr the current output stream.
  // Returns previous handle. Mirrors to G!13 (cos) so BCPL code
  // reading the global directly sees the current handle.
  imp_selectoutput() {
    const h = this.arg(0);
    this.restoreP();
    if (!this._stream(h)) return 0;
    const prev = this.curOut;
    this.curOut = h;
    this.storeWord(1 + 13, h);  // G!13 = cos
    return prev;
  }

  imp_selectinput() {
    const h = this.arg(0);
    this.restoreP();
    if (!this._stream(h)) return 0;
    const prev = this.curIn;
    this.curIn = h;
    this.storeWord(1 + 12, h);  // G!12 = cis
    return prev;
  }

  // endstream(scbPtr) — close stream. If it was a write stream,
  // commit data to storage. If it was the current in/out stream,
  // reset to the stdin/stdout defaults.
  imp_endstream() {
    const h = this.arg(0);
    this.restoreP();
    const s = this._stream(h);
    if (!s) return 0;
    if (h === this.stdinScb || h === this.stdoutScb) return 0;
    if (s.kind === "file" && s.mode === "w") {
      storageBackend.set(s.name, s.data);
    }
    this._freeStream(h);
    if (this.curOut === h) { this.curOut = this.stdoutScb; this.storeWord(1 + 13, this.stdoutScb); }
    if (this.curIn  === h) { this.curIn  = this.stdinScb;  this.storeWord(1 + 12, this.stdinScb);  }
    return 0;
  }

  // endread / endwrite — close the currently selected input/output
  // stream (whatever its handle).
  imp_endread() {
    const h = this.curIn;
    this.restoreP();
    if (h && h !== this.stdinScb && this._stream(h)) {
      this._freeStream(h);
    }
    this.curIn = this.stdinScb;
    this.storeWord(1 + 12, this.stdinScb);  // G!12 = cis
    return 0;
  }
  imp_endwrite() {
    const h = this.curOut;
    this.restoreP();
    if (h && h !== this.stdoutScb) {
      const s = this._stream(h);
      if (s) {
        if (s.kind === "file" && s.mode === "w") storageBackend.set(s.name, s.data);
        this._freeStream(h);
      }
    }
    this.curOut = this.stdoutScb;
    this.storeWord(1 + 13, this.stdoutScb);  // G!13 = cos
    return 0;
  }

  // ------------------ Tier-A memory + bit ops ------------------

  // copystring(from, to) — byte-copy BCPL string `from` to `to`
  // (including length byte at index 0).
  imp_copystring() {
    const from = this.arg(0) * 4;
    const to   = this.arg(1) * 4;
    this.restoreP();
    const len = this.memView.getUint8(from);
    for (let i = 0; i <= len; i++) {
      this.memView.setUint8(to + i, this.memView.getUint8(from + i));
    }
    return 0;
  }

  // copy_words(from, to, n) — word-copy n words.
  imp_copy_words() {
    const from = this.arg(0);
    const to   = this.arg(1);
    const n    = this.arg(2);
    this.restoreP();
    for (let i = 0; i < n; i++) this.storeWord(to + i, this.loadWord(from + i));
    return 0;
  }

  // clear_words(v, n) — zero-fill n words.
  imp_clear_words() {
    const v = this.arg(0);
    const n = this.arg(1);
    this.restoreP();
    for (let i = 0; i < n; i++) this.storeWord(v + i, 0);
    return 0;
  }

  // copy_bytes(fromlen, from, fillch, tolen, to) — MOVC5 semantics.
  // `from` and `to` are BYTE addresses (not word). Copy up to min(fromlen,
  // tolen) bytes, fill remainder of tolen with fillch. Returns
  // fromlen - copied.
  imp_copy_bytes() {
    const fromlen = this.arg(0);
    const from    = this.arg(1);
    const fillch  = this.arg(2);
    const tolen   = this.arg(3);
    const to      = this.arg(4);
    this.restoreP();
    const n = Math.min(fromlen, tolen);
    for (let i = 0; i < n; i++)
      this.memView.setUint8(to + i, this.memView.getUint8(from + i));
    for (let i = n; i < tolen; i++)
      this.memView.setUint8(to + i, fillch & 0xFF);
    return fromlen - n;
  }

  // packstring(v, s) — pack byte-per-word vector v into byte-packed
  // BCPL string s. Returns size = len/bytesperword.
  imp_packstring() {
    const v = this.arg(0);       // word addr of byte-per-word vec
    const s = this.arg(1) * 4;   // byte addr of dest string
    this.restoreP();
    const n = this.loadWord(v) & 0xFF;
    const bytesperword = 4;
    const size = (n / bytesperword) | 0;
    for (let i = 0; i <= n; i++) {
      this.memView.setUint8(s + i, this.loadWord(v + i) & 0xFF);
    }
    // Pad remainder of (size+1) words with zeros.
    for (let i = n + 1; i < (size + 1) * bytesperword; i++) {
      this.memView.setUint8(s + i, 0);
    }
    return size;
  }

  // unpackstring(s, v) — expand byte-packed string s into byte-per-word
  // vector v (v!0 = length, v!1 = byte 1, …).
  imp_unpackstring() {
    const s = this.arg(0) * 4;   // byte addr of source string
    const v = this.arg(1);       // word addr of dest vec
    this.restoreP();
    const len = this.memView.getUint8(s);
    for (let i = len; i >= 0; i--) {
      this.storeWord(v + i, this.memView.getUint8(s + i));
    }
    return 0;
  }

  // getword(v, i) — fetch i'th 16-bit little-endian word from byte-
  // indexed vector v (word-address). j = i*2.
  imp_getword() {
    const v = this.arg(0) * 4;   // byte addr
    const i = this.arg(1);
    this.restoreP();
    const j = v + i * 2;
    return this.memView.getUint8(j) | (this.memView.getUint8(j + 1) << 8);
  }

  // putword(v, i, w) — store low 16 bits of w into i'th 16-bit slot
  // of byte vector v, little-endian.
  imp_putword() {
    const v = this.arg(0) * 4;
    const i = this.arg(1);
    const w = this.arg(2);
    this.restoreP();
    const j = v + i * 2;
    this.memView.setUint8(j,     w         & 0xFF);
    this.memView.setUint8(j + 1, (w >>> 8) & 0xFF);
    return 0;
  }

  // setbit(bitno, bitvec, state) — set/clear bit, return previous.
  imp_setbit() {
    const bitno = this.arg(0);
    const bitvec = this.arg(1);
    const state  = this.arg(2);
    this.restoreP();
    const i = (bitno / 32) | 0;
    const s = bitno % 32;
    const mask = (1 << s) >>> 0;
    const word = this.loadWord(bitvec + i);
    const old  = word & mask;
    const next = state ? (word | mask) : (word & ~mask);
    this.storeWord(bitvec + i, next);
    return old;
  }

  // testbit(bitno, bitvec) — return nonzero if bit set.
  imp_testbit() {
    const bitno = this.arg(0);
    const bitvec = this.arg(1);
    this.restoreP();
    const i = (bitno / 32) | 0;
    const s = bitno % 32;
    return this.loadWord(bitvec + i) & ((1 << s) >>> 0);
  }

  // setvec(v, n, a0..a15) — copy up to 16 args into v!0..v!n-1.
  // BCPL signature has 16 named args after n; we read P!3..P!19 and
  // copy n of them. Excess args beyond available are zero.
  imp_setvec() {
    const v = this.arg(0);
    const n = this.arg(1);
    // Snapshot args before restoreP — P moves away after restore.
    const vals = [];
    for (let i = 0; i < 16; i++) vals.push(this.arg(2 + i));
    this.restoreP();
    for (let i = 0; i < n; i++) this.storeWord(v + i, vals[i] ?? 0);
    return 0;
  }

  // ------------------ Tier-A format group ------------------

  // writed(n, d) — signed decimal, d = min field width (space-pad).
  imp_writed() {
    const n = this.arg(0) | 0;
    const d = this.arg(1) | 0;
    this.restoreP();
    this._writeString(String(n).padStart(d, " "));
    return 0;
  }

  // writeu(n, d) — unsigned decimal, d = min field width.
  imp_writeu() {
    const n = this.arg(0) >>> 0;
    const d = this.arg(1) | 0;
    this.restoreP();
    this._writeString(String(n).padStart(d, " "));
    return 0;
  }

  // writet(s, d) — BCPL string, pad with trailing spaces to width d.
  imp_writet() {
    const s   = this.readBcplString(this.arg(0));
    const d   = this.arg(1) | 0;
    this.restoreP();
    this._writeString(s);
    const pad = d - s.length;
    if (pad > 0) this._writeString(" ".repeat(pad));
    return 0;
  }

  // writez(n, d) — signed decimal, d = field width, zero-pad.
  imp_writez() {
    const n = this.arg(0) | 0;
    const d = this.arg(1) | 0;
    this.restoreP();
    const neg = n < 0;
    const body = String(neg ? -n : n);
    const w = neg ? d - 1 : d;
    const padded = body.padStart(Math.max(w, body.length), "0");
    this._writeString((neg ? "-" : "") + padded);
    return 0;
  }

  // writehex(n, d) — unsigned hex, zero-pad to d digits (uppercase).
  imp_writehex() {
    const n = this.arg(0) >>> 0;
    const d = this.arg(1) | 0;
    this.restoreP();
    this._writeString(n.toString(16).toUpperCase().padStart(d, "0"));
    return 0;
  }

  // writeoct(n, d) — unsigned octal, zero-pad to d digits.
  imp_writeoct() {
    const n = this.arg(0) >>> 0;
    const d = this.arg(1) | 0;
    this.restoreP();
    this._writeString(n.toString(8).padStart(d, "0"));
    return 0;
  }

  // writeflt(x, w, p) — BCPL f32 bits x as fixed-point, width w,
  // p digits after the decimal point.
  imp_writeflt() {
    const xi = this.arg(0) | 0;
    const w  = this.arg(1) | 0;
    const p  = Math.max(0, this.arg(2) | 0);
    this.restoreP();
    const buf = new ArrayBuffer(4);
    new Int32Array(buf)[0] = xi;
    const x = new Float32Array(buf)[0];
    this._writeString(x.toFixed(p).padStart(w, " "));
    return 0;
  }

  // writee(x, w, p) — BCPL f32 bits x as exponential form, width w,
  // p digits after the decimal point.
  imp_writee() {
    const xi = this.arg(0) | 0;
    const w  = this.arg(1) | 0;
    const p  = Math.max(0, this.arg(2) | 0);
    this.restoreP();
    const buf = new ArrayBuffer(4);
    new Int32Array(buf)[0] = xi;
    const x = new Float32Array(buf)[0];
    this._writeString(x.toExponential(p).padStart(w, " "));
    return 0;
  }

  // newpage() — write form-feed (ASCII 12).
  imp_newpage() {
    this._writeChar(12);
    this.restoreP();
    return 0;
  }

  // codewrch(code) — encode Unicode codepoint as UTF-8 bytes.
  // BCPL blib supports GB2312 too; browser playground sticks to UTF-8.
  imp_codewrch() {
    const code = this.arg(0) >>> 0;
    this.restoreP();
    // Emit as JS string so the UI callback handles encoding.
    const s = String.fromCodePoint(code & 0x10FFFF);
    this._writeString(s);
    return 0;
  }

  // errwritef(fmt, ...) — writef to stderr. In the browser playground
  // we have one sink (writeOut); errwrch already routes there, so
  // errwritef delegates to writef for identical output behavior.
  imp_errwritef() { return this.imp_writef(); }

  // ------------------ Tier-A parse group ------------------

  // Push a char back onto the current input stream (blib unrdch).
  _unreadChar(ch) {
    const s = this._stream(this.curIn);
    if (!s) return;
    if (s.kind === "stdin") {
      if (this.inputIdx > 0) this.inputIdx--;
      return;
    }
    if (s.pos > 0) { s.pos--; this._syncScb(s); }
  }

  // Write result2 (G!10) — secondary return value used by several
  // parse funcs for status/extra result.
  _setResult2(v) { this.storeWord(1 + 10, v | 0); }

  // ------------------ Sys_sdl (op 66) sub-dispatch -----------------
  // Maps the bcplprogs SDL ops onto Canvas 2D. Subset focused on the
  // common drawing primitives, events, and timing — enough for simple
  // demos. Surfaces beyond the primary screen are stubbed.
  _sdlDispatch(sub, a, b, c, d, e, f) {
    if (!this.sdlCtx) return 0;
    const ctx = this.sdlCtx;
    const can = this.sdlCanvas;
    switch (sub) {
      case 0: return -1;                              // sdl_avail
      case 1: {                                       // sdl_init
        this.sdlStartTime = performance.now();
        if (this.sdlOnShow) this.sdlOnShow();
        return 0;
      }
      case 2: {                                       // sdl_setvideomode w,h,bpp,flags
        can.width = a; can.height = b;
        ctx.imageSmoothingEnabled = false;
        // Allocate full-frame backbuffer so heavy draw ops (vline,
        // drawwallcol, etc.) can accumulate into typed-array memory
        // and flip once per frame instead of hitting the canvas API
        // per primitive.
        this._fb   = new Uint8ClampedArray(a * b * 4);
        this._fbW  = a;
        this._fbH  = b;
        // Per-pixel depth buffer (i32, world units). Walls and flats
        // write their cy as they paint; sprites test it before
        // writing so they get occluded by any closer surface, not
        // just the single-depth col_z heuristic in BCPL.
        this._zBuf = new Int32Array(a * b);
        this._zVal = 0x7FFFFFFF;
        return 1;                                     // surfptr (any non-zero)
      }
      case 3: return 0;                               // sdl_quit
      case 4: case 5: return 0;                       // lock/unlock surface (noop)
      case 27: {                                      // sdl_drawline x1,y1,x2,y2,color  OR  surfptr,x1,y1,x2,y2,color (varies)
        const colour = (f !== undefined) ? f : (e !== undefined ? e : this.sdlCurrentColor);
        let x1, y1, x2, y2;
        if (a === 1 && f !== undefined) { x1 = b; y1 = c; x2 = d; y2 = e; }
        else                            { x1 = a; y1 = b; x2 = c; y2 = d; }
        if (this._fb) { this._fbLine(x1, y1, x2, y2, colour); return 0; }
        this._sdlSetStroke(colour);
        ctx.beginPath();
        ctx.moveTo(x1 + 0.5, y1 + 0.5);
        ctx.lineTo(x2 + 0.5, y2 + 0.5);
        ctx.stroke();
        return 0;
      }
      case 28: case 29: {                             // drawhline/drawvline: (surf,x1,x2,y,col) / (surf,x,y1,y2,col)
        const colour = e ?? d;
        if (this._fb) {
          if (sub === 28) {
            // hline: span (b..c, y=d)
            this._fbRect(Math.min(b, c), d, Math.abs(c - b) + 1, 1, colour);
          } else {
            // vline: x=b, span (c..d)
            this._fbVline(b, c, d, colour);
          }
          return 0;
        }
        this._sdlSetStroke(colour);
        ctx.beginPath();
        if (sub === 28) { ctx.moveTo(b + 0.5, d + 0.5); ctx.lineTo(c + 0.5, d + 0.5); }
        else            { ctx.moveTo(b + 0.5, c + 0.5); ctx.lineTo(b + 0.5, d + 0.5); }
        ctx.stroke();
        return 0;
      }
      case 30: {                                      // drawcircle (surf, cx, cy, r, col)
        this._sdlSetStroke(e);
        ctx.beginPath();
        ctx.arc(b, c, d, 0, Math.PI * 2);
        ctx.stroke();
        return 0;
      }
      case 31: {                                      // drawrect (surf, x1, y1, x2, y2, col)
        this._sdlSetStroke(f);
        ctx.strokeRect(b + 0.5, c + 0.5, d - b, e - c);
        return 0;
      }
      case 32: {                                      // drawpixel (surf, x, y, col)
        this._sdlSetFill(d);
        ctx.fillRect(b, c, 1, 1);
        return 0;
      }
      case 33: {                                      // drawellipse (surf, cx, cy, rx, ry, col)
        this._sdlSetStroke(f);
        ctx.beginPath();
        ctx.ellipse(b, c, d, e, 0, 0, Math.PI * 2);
        ctx.stroke();
        return 0;
      }
      case 34: {                                      // drawfillellipse
        this._sdlSetFill(f);
        ctx.beginPath();
        ctx.ellipse(b, c, d, e, 0, 0, Math.PI * 2);
        ctx.fill();
        return 0;
      }
      case 37: {                                      // drawfillcircle (surf, cx, cy, r, col)
        this._sdlSetFill(e);
        ctx.beginPath();
        ctx.arc(b, c, d, 0, Math.PI * 2);
        ctx.fill();
        return 0;
      }
      case 38: case 39: {                             // drawfillrect / fillrect (surf, x1, y1, x2, y2, col)
        if (this._fb) { this._fbRect(b, c, d - b, e - c, f); return 0; }
        this._sdlSetFill(f);
        ctx.fillRect(b, c, d - b, e - c);
        return 0;
      }
      case 40: {                                      // fillsurf (surf, col)
        if (this._fb) { this._fbRect(0, 0, this._fbW, this._fbH, b); return 0; }
        this._sdlSetFill(b);
        ctx.fillRect(0, 0, can.width, can.height);
        return 0;
      }
      // Op numbers below MUST match site/headers/sdl.h. The playground
      // ships its own minimal sdl.h with hand-picked op constants —
      // NOT the same as cintsys g/sdl.h, which uses MANIFEST auto-
      // increment from sdl_avail=0 and lands these elsewhere.
      case 15: {                                      // sdl_flip — push backbuffer to canvas (one putImageData).
        if (this._fb) {
          this.sdlCtx.putImageData(new ImageData(this._fb, this._fbW, this._fbH), 0, 0);
        }
        return 0;
      }
      case 17: case 18: {                             // waitevent / pollevent
        const v = a;                                  // BCPL pointer to event slot vector
        if (this.sdlEvents.length === 0) {
          this.storeWord(v + 0, 0);                   // type=0 (none)
          return 0;
        }
        const ev = this.sdlEvents.shift();
        this.storeWord(v + 0, ev.type | 0);
        this.storeWord(v + 1, ev.mod   ?? ev.b ?? ev.x ?? 0);
        this.storeWord(v + 2, ev.ch    ?? ev.y ?? 0);
        return -1;
      }
      case 19: {                                      // getmousestate (v -> [x,y]); returns button bits
        this.storeWord(a + 0, this.sdlMouse.x | 0);
        this.storeWord(a + 1, this.sdlMouse.y | 0);
        return this.sdlMouse.buttons | 0;
      }
      case 22: {                                      // wm_setcaption (str, ?)
        const name = this.readBcplString(a);
        if (typeof document !== "undefined") document.title = name;
        return 0;
      }
      case 24: {                                      // sdl_maprgb (fmtptr, r, g, b)
        return ((b & 0xFF) << 24) | ((c & 0xFF) << 16) | ((d & 0xFF) << 8) | 0xFF;
      }
      case 50: return (performance.now() - this.sdlStartTime) | 0;  // getticks
      case 14: {                                      // sdl_delay (ms)
        // No-op here; the asyncify yield is driven by the dedicated
        // bcpl_delay import (G!128), not this SDL sub-op.
        return 0;
      }
      case 51: return 0;                              // showcursor
      case 52: return 0;                              // hidecursor
      default:
        return 0;
    }
  }

  // readn() — skip leading whitespace + optional sign, parse signed
  // decimal, un-read terminator. result2 = 0 on success, -1 on
  // no-digits EOF-ish case.
  imp_readn() {
    this.restoreP();
    let ch, neg = false;
    // Skip whitespace + parse sign.
    for (;;) {
      ch = this._readChar();
      if (ch >= 48 && ch <= 57) break;                 // '0'..'9'
      if (ch === 32 || ch === 9 || ch === 10) continue;  // ws
      if (ch === 45) { neg = true; ch = this._readChar(); break; }  // '-'
      if (ch === 43) {              ch = this._readChar(); break; }  // '+'
      // No digit sighted — push back, signal error via result2.
      this._unreadChar(ch);
      this._setResult2(-1);
      return 0;
    }
    let sum = 0;
    while (ch >= 48 && ch <= 57) {
      sum = sum * 10 + (ch - 48);
      ch = this._readChar();
    }
    this._unreadChar(ch);
    this._setResult2(0);
    return (neg ? -sum : sum) | 0;
  }

  // readflt() — parse floating-point number, return f32 bit pattern.
  // result2 = 0 on success, -1 on failure.
  imp_readflt() {
    this.restoreP();
    let ch, str = "";
    // Skip whitespace.
    do { ch = this._readChar(); }
    while (ch === 32 || ch === 9 || ch === 10);
    // Optional sign.
    if (ch === 45 || ch === 43) { str += String.fromCharCode(ch); ch = this._readChar(); }
    let gotDigit = false;
    while (ch >= 48 && ch <= 57) { str += String.fromCharCode(ch); gotDigit = true; ch = this._readChar(); }
    if (ch === 46) {  // '.'
      str += "."; ch = this._readChar();
      while (ch >= 48 && ch <= 57) { str += String.fromCharCode(ch); gotDigit = true; ch = this._readChar(); }
    }
    if (ch === 69 || ch === 101) {  // 'E' 'e'
      str += "e"; ch = this._readChar();
      if (ch === 45 || ch === 43) { str += String.fromCharCode(ch); ch = this._readChar(); }
      while (ch >= 48 && ch <= 57) { str += String.fromCharCode(ch); ch = this._readChar(); }
    }
    this._unreadChar(ch);
    if (!gotDigit) { this._setResult2(-1); return 0; }
    const x = Number(str);
    this._setResult2(0);
    const buf = new ArrayBuffer(4);
    new Float32Array(buf)[0] = Number.isFinite(x) ? x : 0;
    return new Int32Array(buf)[0];
  }

  // rditem(v, upb) — read next item (word, quoted string, separator)
  // into v. Returns item type: 0=EOF, 1=unquoted, 2=quoted, 3='\n',
  // 4=';', 5='=', -1=error.
  imp_rditem() {
    const v   = this.arg(0);
    const upb = this.arg(1);
    this.restoreP();
    const pmax = (upb + 1) * 4 - 1;
    // Zero-fill v[0..upb].
    for (let i = 0; i <= upb; i++) this.storeWord(v + i, 0);
    const vByte = v * 4;
    const putByte = (p, ch) => this.memView.setUint8(vByte + p, ch & 0xFF);

    let ch = this._readChar();
    // Skip horizontal whitespace + CR.
    while (ch === 32 || ch === 9 || ch === 13) ch = this._readChar();

    if (ch === -1)  return 0;   // EOF
    if (ch === 10)  return 3;   // newline
    if (ch === 59)  return 4;   // ';'
    if (ch === 61)  return 5;   // '='

    let p = 0;
    if (ch === 34) {            // '"' quoted
      for (;;) {
        ch = this._readChar();
        if (ch === 13) continue;
        if (ch === 10 || ch === -1) return -1;
        if (ch === 34) return 2;
        if (ch === 42) {        // '*' escape
          const next = this._readChar();
          const cap = (next >= 97 && next <= 122) ? next - 32 : next;
          if (cap === 78) ch = 10;         // '*n'
          else if (cap === 34) ch = 34;    // '*"'
          else ch = next;
        }
        p++;
        if (p > pmax) return -1;
        putByte(0, p);
        putByte(p, ch);
      }
    }

    // Unquoted item.
    while (!(ch === 10 || ch === 32 || ch === 9 || ch === 59 || ch === 61 || ch === -1)) {
      p++;
      if (p > pmax) return -1;
      putByte(0, p);
      putByte(p, ch);
      do { ch = this._readChar(); } while (ch === 13);
    }
    if (ch !== -1) this._unreadChar(ch);
    return 1;
  }

  // str2numb(s) — simple BCPL-string-to-integer (deprecated but still
  // used in old code). Accepts optional leading '-' then digits.
  // Returns integer (no result2 contract).
  imp_str2numb() {
    const sByte = this.arg(0) * 4;
    this.restoreP();
    const len = this.memView.getUint8(sByte);
    let n = 0, neg = false, i = 1;
    if (len >= 1 && this.memView.getUint8(sByte + 1) === 45) { neg = true; i = 2; }
    for (; i <= len; i++) {
      const d = this.memView.getUint8(sByte + i) - 48;
      if (d < 0 || d > 9) break;
      n = n * 10 + d;
    }
    return (neg ? -n : n) | 0;
  }

  // string_to_number(s) — returns TRUE on success, FALSE on failure.
  // Success puts the parsed value in result2 (G!10). Supports
  // 'A' char literals, #O/#X/#B bases, underscores in digits, sign.
  imp_string_to_number() {
    const sByte = this.arg(0) * 4;
    this.restoreP();
    this._setResult2(0);
    const len = this.memView.getUint8(sByte);
    if (len === 0) return 0;
    const at = (k) => this.memView.getUint8(sByte + k);
    const cap = (c) => (c >= 97 && c <= 122) ? c - 32 : c;

    let p = 1, neg = false, radix = 10;
    let ch = cap(at(p));
    // Char literal 'A' (3-byte string: 'X').
    if (len === 3 && at(1) === 39 && at(3) === 39) {
      this._setResult2(at(2));
      return -1;
    }
    if (ch === 43 || ch === 45) {
      neg = ch === 45;
      if (p === len) return -1;
      p++;
      ch = cap(at(p));
    }
    if (ch === 35) {              // '#'
      radix = 8;
      if (p === len) return -1;
      p++;
      ch = cap(at(p));
      if (ch === 79 || ch === 88 || ch === 66) {
        if (ch === 88) radix = 16;
        else if (ch === 66) radix = 2;
        if (p === len) return -1;
        p++;
        ch = cap(at(p));
      }
    }
    let acc = 0;
    for (;;) {
      const d = (ch >= 48 && ch <= 57) ? ch - 48
              : (ch >= 65 && ch <= 90) ? ch - 65 + 10
              : ch === 95 ? -1
              : 1000;
      if (d < radix) {
        if (d >= 0) acc = (acc * radix + d) | 0;
      } else {
        return 0;  // bad digit → FALSE
      }
      p++;
      if (p > len) break;
      ch = cap(at(p));
    }
    this._setResult2((neg ? -acc : acc) | 0);
    return -1;
  }

  // ------------------ Tier-A diagnostic + aliases ------------------

  // memoryfree(x) — return number of free words on the heap.
  // result2 = total Cintcode memory size (words).
  // x param ignored (blib uses it for check-chain mode).
  imp_memoryfree() {
    this.restoreP();
    const totalWords = this.mem.buffer.byteLength >> 2;
    // heapTop is the lowest used heap address (grows downward).
    // Everything between static_base and heapTop is "free".
    const free = Math.max(0, this.heapTop - this.nextStaticWord);
    this._setResult2(totalWords);
    return free;
  }

  // stackfree(hwm) — return free stack words. For browser playground
  // the BCPL stack lives in a fixed slab; report a large constant
  // minus the distance P has advanced since stack base.
  imp_stackfree() {
    this.restoreP();
    // Heuristic: delta from initial static-past boundary. Programs
    // typically just log this; exact accuracy not essential.
    const stackBase = ((this.nextStaticWord + 3) & ~3);
    const free = Math.max(0, 100000 - (this.P - stackBase));
    this._setResult2(100000);
    return free;
  }

  // intflag() — TRUE if user pressed interrupt. Browser playground
  // has no such signal; always FALSE.
  imp_intflag() {
    this.restoreP();
    return 0;
  }

  // setseed(newseed) — replace randseed at G!127, return old.
  imp_setseed() {
    const newseed = this.arg(0) | 0;
    this.restoreP();
    const old = this.loadWord(1 + 127);
    this.storeWord(1 + 127, newseed);
    return old;
  }

  // ------------------ Coroutines (Asyncify-based) ------------------
  //
  // Each coroutine has its own BCPL stack slab + its own asyncify-state
  // buffer. cowait/callco/resumeco suspend the running wasm via
  // asyncify_start_unwind, and the JS scheduler resumes whichever
  // coroutine should run next via asyncify_start_rewind.
  //
  // Asyncify exports come from the user program after wasm-opt --asyncify
  // ran on it. If a program imports cowait/callco/resumeco/changeco/delay
  // but the asyncify pass wasn't applied (e.g. wasm-opt missing), the
  // imp_* methods fall back to single-shot semantics that won't actually
  // suspend; the program will still run but coroutine yields are no-ops.

  // Coroutine control block layout (mirrors blib.b's convention):
  //   c!0  co_pptr   — saved P (BCPL byte addr = stack << B2Wsh)
  //   c!1  co_parent — parent coroutine handle (0 if root)
  //   c!2  co_list   — next link in colist (we mirror G!8)
  //   c!3  co_fn     — body function
  //   c!4  co_size   — user stack size in words (excl. 6-word header)
  //   c!5  co_c      — self-pointer
  //   c!6+ stack space

  // Probe that returns ONE asyncify-instrumented module's exports
  // (or null) silently. Used by run() for the asyncify-aware path
  // probe. Note: in multi-module programs (library + consumer, etc.)
  // each instrumented module has its OWN asyncify state globals. To
  // unwind a call stack that spans modules, asyncify_start_unwind /
  // stop_unwind / start_rewind / stop_rewind must be applied to ALL
  // of them — see _allAsyncifyExports + _asyncifyAll* below.
  // Returns the asyncify exports of the LAST loaded instrumented
  // module. Programs are loaded libs-first / entry-last, so the
  // last-loaded module is the consumer / entry — that's where the
  // suspending call (delay, cowait, bcpl_break) usually originates,
  // so its asyncify state is the one that actually needs flipping
  // to drive the unwind on the live call stack.
  //
  // Earlier this returned the FIRST module (the library) — which
  // worked for single-module programs but in lib+consumer setups it
  // set state on a module whose code wasn't on the stack, leaving
  // consumer code running past the suspend point and trapping.
  //
  // Setting state on EVERY instrumented module is also wrong: the
  // rewind path would restore frames from the asyncify buffer into
  // modules that never contributed frames, corrupting their locals.
  _coroutineExports() {
    let last = null;
    for (const p of this.programs) {
      if (p.instance.exports.asyncify_start_unwind) last = p.instance.exports;
    }
    return last;
  }
  _asyncifyAllStartUnwind(buf) {
    const exp = this._coroutineExports();
    if (exp) exp.asyncify_start_unwind(buf);
  }
  _asyncifyAllStopUnwind() {
    const exp = this._coroutineExports();
    if (exp) exp.asyncify_stop_unwind();
  }
  _asyncifyAllStartRewind(buf) {
    const exp = this._coroutineExports();
    if (exp) exp.asyncify_start_rewind(buf);
  }
  _asyncifyAllStopRewind() {
    const exp = this._coroutineExports();
    if (exp) exp.asyncify_stop_rewind();
  }
  // Same probe but warns if the caller (a coroutine import) needs
  // asyncify and it's not present.
  _coroutineExportsRequired() {
    const exp = this._coroutineExports();
    if (exp) return exp;
    if (!this._asyncifyMissingWarned) {
      this._asyncifyMissingWarned = true;
      console.warn(
        "[bcpl-runtime] coroutine call but no asyncify-instrumented " +
        "wasm module found. Live-compile in browser must run the " +
        "asyncify pass on the assembled wasm. Without it, cowait/callco " +
        "are no-ops returning 0.");
    }
    return null;
  }

  _allocCoroutine(fnTidx, sizeWords) {
    // Reserve a slab near the top of memory (heap grows downward).
    const totalWords = sizeWords + 6;
    const memWords = this.mem.buffer.byteLength >>> 2;
    if (this.heapTop <= 0 || this.heapTop > memWords) {
      // Defensive: re-anchor heapTop to top of memory if it was lost
      // (can happen when memory grew or wasn't initialised yet).
      this.heapTop = memWords;
    }
    const base = this.heapTop - totalWords;
    if (base < 0 || base > memWords) {
      throw new Error(`createco: heap exhausted (heapTop=${this.heapTop}, ` +
        `requested=${totalWords} words, memWords=${memWords})`);
    }
    this.heapTop = base;
    // Reserve an asyncify state buffer (1024 bytes = 256 words).
    const asyncifyWords = 256;
    const asyncifyBase = this.heapTop - asyncifyWords;
    this.heapTop = asyncifyBase;

    // Header.
    this.storeWord(base + 0, base << 2);          // co_pptr (byte addr)
    this.storeWord(base + 1, 0);                  // co_parent
    this.storeWord(base + 2, this.loadWord(1 + 8)); // co_list = old colist
    this.storeWord(base + 3, fnTidx);             // co_fn
    this.storeWord(base + 4, sizeWords);          // co_size
    this.storeWord(base + 5, base);               // co_c (self)
    // Fill stack with the BCPL stackword marker.
    for (let i = 6; i < totalWords; i++) {
      this.storeWord(base + i, 0xABCD1234 | 0);
    }
    // Asyncify state buffer: [0]=current sp (byte), [1]=end (byte).
    const asyncByteBase = asyncifyBase * 4;
    this.memView.setUint32(asyncByteBase,     asyncByteBase + 8, true);
    this.memView.setUint32(asyncByteBase + 4, asyncByteBase + asyncifyWords * 4, true);

    return {
      handle: base,                       // BCPL "coroutine pointer" (word addr of CB)
      bodyTidx: fnTidx,                   // body fn table index
      asyncifyData: asyncByteBase,        // byte addr of state struct
      asyncifyWords,                      // size for reset
      savedP: base + 6,                   // user stack starts after 6-word header
      status: "new",                      // "new" | "running" | "suspended" | "done"
      yieldedValue: 0,
      resumeArg: 0,
      parentHandle: null,
      isRoot: false,
    };
  }

  // createco(fn, size) — allocate a coroutine, return handle (=word
  // address of the control block). On first invocation the body fn
  // will see arg0 = the initial cowait return value (which our
  // scheduler delivers when first resumed).
  imp_createco() {
    const fn   = this.arg(0);
    const size = this.arg(1) | 0;
    this.restoreP();
    const sizeWords = Math.max(64, size);
    const co = this._allocCoroutine(fn, sizeWords);
    this._coroutines ??= new Map();
    this._coroutines.set(co.handle, co);
    // Insert at head of colist (G!8).
    this.storeWord(1 + 8, co.handle);
    return co.handle;
  }

  // deleteco(c) — free a coroutine. Refuse if it has children.
  imp_deleteco() {
    const c = this.arg(0);
    this.restoreP();
    if (!this._coroutines || !this._coroutines.has(c)) return 0;
    const co = this._coroutines.get(c);
    if (co.status === "running") return 0;
    this._coroutines.delete(c);
    // Note: we don't actually reclaim the heap slab here — the bump
    // allocator doesn't support arbitrary frees. Programs that delete
    // many short-lived coroutines will leak. Acceptable for demos.
    return 0;
  }

  // cowait(arg) — suspend the running coroutine, yield arg to the parent.
  // Implementation: triggers asyncify unwind; the JS scheduler picks
  // up the parent and rewinds it.
  imp_cowait() {
    const arg = this.arg(0);
    const exp = this._coroutineExportsRequired();
    if (!exp || !this._currentCo) { this.restoreP(); return arg; }
    const co = this._currentCo;
    if (this._asyncifyMode === "rewinding") {
      this._asyncifyAllStopRewind();
      this._asyncifyMode = "normal";
      this.restoreP();
      return co.resumeArg;
    }
    co.yieldedValue = arg;
    const parent = (co.parentHandle && this._coroutines.has(co.parentHandle))
      ? this._coroutines.get(co.parentHandle)
      : this._rootCo;
    if (parent) parent.resumeArg = arg;
    this._resetAsyncifyBuffer(co.asyncifyData, co.asyncifyWords ?? 256);
    co.savedP = this.P;            // callee frame P, for replay on rewind
    this._asyncifyAllStartUnwind(co.asyncifyData);
    this._asyncifyMode = "unwinding";
    this._scheduleResume = parent ? parent.handle : 0;
    return 0;
  }

  // callco(c, arg) — suspend caller, resume c with arg as the cowait
  // return value. blib aborts(110) if c already has a parent.
  imp_callco() {
    // IMPORTANT: read args BEFORE restoreP since restoreP changes $P.
    // Also, $P must stay at the CALLEE frame across asyncify_start_unwind
    // so that on rewind the imp_* sees the same args at P!3/P!4. We
    // restoreP only on the rewind path (just before returning to BCPL).
    const cHandle = this.arg(0);
    const arg     = this.arg(1);
    const exp = this._coroutineExportsRequired();
    if (this._asyncifyMode === "rewinding") {
      this._asyncifyAllStopRewind();
      this._asyncifyMode = "normal";
      this.restoreP();
      return this._currentCo?.resumeArg ?? 0;
    }
    const target = this._coroutines?.get(cHandle);
    if (!exp || !target) { this.restoreP(); return 0; }
    target.parentHandle = this._currentCo?.handle ?? 0;
    target.resumeArg    = arg;
    this.storeWord(target.handle + 1, this._currentCo?.handle ?? 0);
    if (this._currentCo) {
      this._resetAsyncifyBuffer(
        this._currentCo.asyncifyData,
        this._currentCo.asyncifyWords ?? 256);
      // Capture the callee-frame P so on rewind asyncify-replay sees
      // the same args at P!3/P!4.
      this._currentCo.savedP = this.P;
      this._asyncifyAllStartUnwind(this._currentCo.asyncifyData);
      this._asyncifyMode = "unwinding";
    }
    this._scheduleResume = cHandle;
    return 0;
  }

  // resumeco(c, arg) — same as callco but reparents (used for tail-call
  // style coroutine chains). Minimal v1: alias to callco.
  imp_resumeco() { return this.imp_callco(); }

  // changeco(val, c) — low-level swap. Treat as callco for v1.
  imp_changeco() {
    const val     = this.arg(0);
    const cHandle = this.arg(1);
    this.restoreP();
    // Reorder args to match callco's expectation.
    // Callers should rarely use changeco directly.
    const exp = this._coroutineExportsRequired();
    if (!exp) return 0;
    const target = this._coroutines?.get(cHandle);
    if (!target) return 0;
    if (this._asyncifyMode === "rewinding") {
      this._asyncifyAllStopRewind();
      this._asyncifyMode = "normal";
      return this._currentCo?.resumeArg ?? 0;
    }
    target.resumeArg = val;
    if (this._currentCo) {
      this._currentCo.status = "ready";
      this._asyncifyAllStartUnwind(this._currentCo.asyncifyData);
      this._asyncifyMode = "unwinding";
    }
    this._scheduleResume = cHandle;
    return 0;
  }

  // delay(ms) — suspend execution for ms milliseconds.
  // Asyncify-backed: triggers an unwind, JS scheduler awaits a real
  // timer, then asyncify-rewinds to resume. Lets the browser repaint
  // between frames in animation loops.
  // Per-statement debug hook. Called by codegen-emitted
  // (call $__break) after each $__line update. Fast path returns
  // immediately; only triggers asyncify-suspend when:
  //   (1) caller has armed at least one breakpoint via setBreakpoints,
  //   (2) the current $__line is in the bp set, AND
  //   (3) the program was compiled with asyncify (debugger mode).
  // Synchronous no-debug builds skip even the suspend path because
  // _coroutineExportsRequired() returns null when no asyncify exports
  // exist — the call then becomes a near-free no-op.
  //
  // NOTE: this import is NOT a BCPL-convention function call. It does
  // not touch P, does not call restoreP — the codegen emits a direct
  // (call $__break) from the middle of a function body. Treat like
  // a void-returning helper.
  imp_break() {
    // Rewind side of an earlier suspend: stop the unwind and continue
    // where the breakpoint paused.
    if (this._asyncifyMode === "rewinding") {
      const exp = this._coroutineExports();
      if (exp) {
        this._asyncifyAllStopRewind();
        this._asyncifyMode = "normal";
      }
      return;
    }
    // Fast-path: when no breakpoints are armed and we're not in
    // step mode, every (call $__break) returns immediately.
    const haveBps = this._breakpoints && this._breakpoints.size > 0;
    if (!haveBps && !this._stepMode) return;
    const line = this.currentLine();
    if (line === 0) return;
    if (this._stepOverLine === line) return;
    const inBp = haveBps && this._breakpoints.has(line);
    if (!this._stepMode && !inBp) return;
    if (this._stepMode) { this._stepMode = false; this._syncBpArmed(); }

    const exp = this._coroutineExports();
    if (!exp) return;                  // not a debug build — give up

    const co = this._currentCo ?? this._rootCo;
    if (!co) return;
    this._resetAsyncifyBuffer(co.asyncifyData, co.asyncifyWords ?? 256);
    co.savedP = this.P;
    co.status = "suspended";
    this._scheduleResume = co.handle;
    // The run loop awaits this promise instead of a delay-style
    // setTimeout; UI.resume() resolves it.
    this._pausedLine = line;
    this._pausePromise = new Promise((r) => { this._pauseResolve = r; });
    this._asyncifyAllStartUnwind(co.asyncifyData);
    this._asyncifyMode = "unwinding";
    if (this.onPause) this.onPause(line);
  }

  // UI-initiated continue from a breakpoint pause. Resolves the
  // pause promise so the run loop re-enters the suspended ctx.
  // stepOver=true mutes the just-hit bp once so we don't re-trigger
  // on the same line before any other statement runs.
  resume({ stepOver = false } = {}) {
    if (!this._pauseResolve) return false;
    if (stepOver) this._stepOverLine = this._pausedLine;
    else          this._stepOverLine = 0;
    const r = this._pauseResolve;
    this._pauseResolve = null;
    this._pausePromise = null;
    this._pausedLine = 0;
    if (this.onResume) this.onResume();
    r();
    return true;
  }

  // Single-step: resume execution and arm a one-shot break on the
  // very next statement boundary (irrespective of the bp set). The
  // current line is muted so we don't re-trigger on the line we're
  // leaving. imp_break clears _stepMode the moment it fires.
  step() {
    if (!this._pauseResolve) return false;
    this._stepMode = true;
    this._stepOverLine = this._pausedLine;
    this._syncBpArmed();
    const r = this._pauseResolve;
    this._pauseResolve = null;
    this._pausePromise = null;
    this._pausedLine = 0;
    if (this.onResume) this.onResume();
    r();
    return true;
  }

  // Update the set of source lines that should trigger imp_break.
  // Pass an iterable of line numbers (numbers, not strings).
  // Side-effect: flips the master's $__bp_armed global so the
  // codegen-emitted (if armed (call __break)) gate trips. With no
  // bps armed, wasm never crosses the JS boundary for the per-
  // statement hook — ~20× speedup on tight loops vs the unconditional
  // call form.
  setBreakpoints(lines) {
    this._breakpoints = new Set();
    for (const n of lines) this._breakpoints.add(n | 0);
    this._stepOverLine = 0;
    this._syncBpArmed();
  }
  _syncBpArmed() {
    const g = this.master?.exports?.__bp_armed;
    if (!g) return;
    const armed = (this._breakpoints && this._breakpoints.size > 0) || this._stepMode;
    g.value = armed ? 1 : 0;
  }

  isPaused() { return this._pausePromise !== null && this._pausePromise !== undefined; }
  pausedLine() { return this._pausedLine | 0; }

  imp_delay() {
    const ms = this.arg(0) | 0;
    const exp = this._coroutineExportsRequired();
    if (!exp) {
      this.restoreP();
      return 0;
    }
    if (this._asyncifyMode === "rewinding") {
      this._asyncifyAllStopRewind();
      this._asyncifyMode = "normal";
      this.restoreP();
      return 0;
    }
    // Suspend: same machinery as cowait, but the JS scheduler awaits a
    // timer instead of a peer coroutine. Stash the requested ms; the
    // run loop reads it after stop_unwind.
    const co = this._currentCo ?? this._rootCo;
    if (!co) { this.restoreP(); return 0; }
    this._resetAsyncifyBuffer(co.asyncifyData, co.asyncifyWords ?? 256);
    co.savedP = this.P;
    co.status = "suspended";
    this._delayMs = Math.max(0, ms);
    this._scheduleResume = co.handle;          // resume self after timer
    this._asyncifyAllStartUnwind(co.asyncifyData);
    this._asyncifyMode = "unwinding";
    return 0;
  }

  // initco(fn, size, a..k) — wrapper that creates a coroutine and
  // delivers its initial args via the cowait return path. v1: just
  // create and let body see the first cowait arg.
  imp_initco() {
    const fn   = this.arg(0);
    const size = this.arg(1) | 0;
    // Args 2..12 are seed values; capture for the first cowait return.
    const seed = this.arg(2);
    this.restoreP();
    this._coroutines ??= new Map();
    const co = this._allocCoroutine(fn, Math.max(64, size));
    co.resumeArg = seed;
    this._coroutines.set(co.handle, co);
    this.storeWord(1 + 8, co.handle);
    return co.handle;
  }

  // findarg(keys, w) — search the rdargs key-spec string for an arg
  // matching BCPL string w. Returns arg index (0-based), or -1.
  imp_findarg() {
    const keysByte = this.arg(0) * 4;
    const wByte    = this.arg(1) * 4;
    this.restoreP();
    const klen = this.memView.getUint8(keysByte);
    const wlen = this.memView.getUint8(wByte);
    const capcmp = (a, b) => {
      const ca = (a >= 97 && a <= 122) ? a - 32 : a;
      const cb = (b >= 97 && b <= 122) ? b - 32 : b;
      return ca - cb;
    };
    let state = 0;  // 0=matching, 1=skipping
    let wp = 0, argno = 0;
    for (let i = 1; i <= klen; i++) {
      const kch = this.memView.getUint8(keysByte + i);
      if (state === 0) {
        if ((kch === 61 || kch === 47 || kch === 44) && wp === wlen) return argno;
        wp++;
        if (wp <= wlen && capcmp(kch, this.memView.getUint8(wByte + wp)) !== 0) state = 1;
      }
      if (kch === 44 || kch === 61) { state = 0; wp = 0; }
      if (kch === 44) argno++;
    }
    if (state === 0 && wp === wlen) return argno;
    return -1;
  }

  // ------------------ loader ------------------

  imports() {
    return {
      env: {
        bcpl_stop:    () => this.imp_stop(),
        bcpl_rdch:    () => this.imp_rdch(),
        bcpl_wrch:    () => this.imp_wrch(),
        bcpl_newline: () => this.imp_newline(),
        bcpl_writen:  () => this.imp_writen(),
        bcpl_writes:  () => this.imp_writes(),
        bcpl_writef:  () => this.imp_writef(),
        bcpl_getvec:  () => this.imp_getvec(),
        bcpl_freevec: () => this.imp_freevec(),
        bcpl_muldiv:  () => this.imp_muldiv(),
        bcpl_abort:   () => this.imp_abort(),
        bcpl_randno:  () => this.imp_randno(),
        bcpl_capitalch:  () => this.imp_capitalch(),
        bcpl_compch:     () => this.imp_compch(),
        bcpl_compstring: () => this.imp_compstring(),
        bcpl_findoutput:   () => this.imp_findoutput(),
        bcpl_findinput:    () => this.imp_findinput(),
        bcpl_selectoutput: () => this.imp_selectoutput(),
        bcpl_selectinput:  () => this.imp_selectinput(),
        bcpl_endstream:    () => this.imp_endstream(),
        bcpl_endread:      () => this.imp_endread(),
        bcpl_endwrite:     () => this.imp_endwrite(),
        bcpl_output:       () => this.imp_output(),
        bcpl_input:        () => this.imp_input(),
        bcpl_rdargs:       () => this.imp_rdargs(),
        bcpl_unrdch:       () => this.imp_unrdch(),
        bcpl_rewindstream: () => this.imp_rewindstream(),
        bcpl_findinoutput: () => this.imp_findinoutput(),
        bcpl_errwrch:      () => this.imp_errwrch(),
        bcpl_sawritef:     () => this.imp_sawritef(),
        bcpl_sys:          () => this.imp_sys(),
        bcpl_level:        () => this.imp_level(),
        bcpl_longjump:     () => this.imp_longjump(),
        bcpl_pathfindinput:() => this.imp_pathfindinput(),
        bcpl_stop_fn:      () => this.imp_stop_fn(),
        bcpl_copystring:   () => this.imp_copystring(),
        bcpl_copy_words:   () => this.imp_copy_words(),
        bcpl_clear_words:  () => this.imp_clear_words(),
        bcpl_copy_bytes:   () => this.imp_copy_bytes(),
        bcpl_packstring:   () => this.imp_packstring(),
        bcpl_unpackstring: () => this.imp_unpackstring(),
        bcpl_getword:      () => this.imp_getword(),
        bcpl_putword:      () => this.imp_putword(),
        bcpl_setbit:       () => this.imp_setbit(),
        bcpl_testbit:      () => this.imp_testbit(),
        bcpl_setvec:       () => this.imp_setvec(),
        bcpl_writed:       () => this.imp_writed(),
        bcpl_writeu:       () => this.imp_writeu(),
        bcpl_writet:       () => this.imp_writet(),
        bcpl_writez:       () => this.imp_writez(),
        bcpl_writehex:     () => this.imp_writehex(),
        bcpl_writeoct:     () => this.imp_writeoct(),
        bcpl_writee:       () => this.imp_writee(),
        bcpl_writeflt:     () => this.imp_writeflt(),
        bcpl_newpage:      () => this.imp_newpage(),
        bcpl_codewrch:     () => this.imp_codewrch(),
        bcpl_errwritef:    () => this.imp_errwritef(),
        bcpl_readn:           () => this.imp_readn(),
        bcpl_readflt:         () => this.imp_readflt(),
        bcpl_rditem:          () => this.imp_rditem(),
        bcpl_str2numb:        () => this.imp_str2numb(),
        bcpl_string_to_number:() => this.imp_string_to_number(),
        bcpl_findarg:         () => this.imp_findarg(),
        bcpl_memoryfree:      () => this.imp_memoryfree(),
        bcpl_stackfree:       () => this.imp_stackfree(),
        bcpl_intflag:         () => this.imp_intflag(),
        bcpl_setseed:         () => this.imp_setseed(),
        bcpl_createco:        () => this.imp_createco(),
        bcpl_callco:          () => this.imp_callco(),
        bcpl_cowait:          () => this.imp_cowait(),
        bcpl_resumeco:        () => this.imp_resumeco(),
        bcpl_deleteco:        () => this.imp_deleteco(),
        bcpl_initco:          () => this.imp_initco(),
        bcpl_changeco:        () => this.imp_changeco(),
        bcpl_delay:           () => this.imp_delay(),
        bcpl_findappend:      () => this.imp_findappend(),
        bcpl_appendstream:    () => this.imp_appendstream(),
        bcpl_deletefile:      () => this.imp_deletefile(),
        bcpl_renamefile:      () => this.imp_renamefile(),
        bcpl_datstamp:        () => this.imp_datstamp(),
        bcpl_delayuntil:      () => this.imp_delayuntil(),
        bcpl_writebin:        () => this.imp_writebin(),
        bcpl_note:            () => this.imp_note(),
        bcpl_point:           () => this.imp_point(),
        bcpl_setrecordlength: () => this.imp_setrecordlength(),
        bcpl_recordpoint:     () => this.imp_recordpoint(),
        bcpl_recordnote:      () => this.imp_recordnote(),
        bcpl_get_record:      () => this.imp_get_record(),
        bcpl_assert:          () => this.imp_assert(),
        bcpl_getvec_or_abort: () => this.imp_getvec_or_abort(),
        bcpl_vsafe_get:       () => this.imp_vsafe_get(),
        bcpl_put_record:      () => this.imp_put_record(),
        // Debug-mode breakpoint hook. Always present so wasm with
        // (call $__break) instantiates either way; behavior depends
        // on whether asyncify is in the build (debugger mode).
        bcpl_break:           () => this.imp_break(),
      }
    };
  }

  // -------- linker-mode loader ----------------------------------
  // master.wasm owns shared memory + funcref table + P/G globals and
  // places stdlib imports at fixed table slots 0..21. Program wasms
  // compiled in linker mode import those plus $SB/$TB (static_base,
  // table_base) and export register()/stat_words()/fn_count(). The
  // loader two-pass-instantiates each program: probe sizes, bump-
  // allocate bases, then real instantiate + register.
  static STDLIB_TABLE_SLOTS = 92;
  static STATIC_WORD_BASE   = 1001;  // first word past G

  async loadMaster(url = "master.wasm") {
    if (this.master) return this.master;
    const bytes = await (await fetch(url)).arrayBuffer();
    const { instance } = await WebAssembly.instantiate(bytes, this.imports());
    this.master = instance;
    this.mem = instance.exports.mem;
    this.refresh();
    this.nextStaticWord = BcplRuntime.STATIC_WORD_BASE;
    this.nextTableSlot  = BcplRuntime.STDLIB_TABLE_SLOTS;
    this.programs = [];
    return instance;
  }

  _envFor(sbGlobal, tbGlobal) {
    const m = this.master.exports;
    return {
      mem: m.mem, ftable: m.ftable, P: m.P, G: m.G,
      __line: m.__line, __bp_armed: m.__bp_armed,
      static_base: sbGlobal, table_base: tbGlobal,
      ...this.imports().env,
    };
  }

  async loadProgramFromBytes(bytes) {
    if (!this.master) await this.loadMaster();
    const module = await WebAssembly.compile(bytes);
    // Probe pass with dummy bases — we need the instance to call
    // stat_words()/fn_count() before we know how much to bump.
    const zero = () => new WebAssembly.Global({ value: "i32" }, 0);
    const probe = await WebAssembly.instantiate(module, { env: this._envFor(zero(), zero()) });
    const stat_words = probe.exports.stat_words();
    const fn_count   = probe.exports.fn_count();
    // Real pass with allocated bases.
    const sb = this.nextStaticWord;
    const tb = this.nextTableSlot;
    this.nextStaticWord += stat_words;
    this.nextTableSlot  += fn_count;
    const real = await WebAssembly.instantiate(module, {
      env: this._envFor(
        new WebAssembly.Global({ value: "i32" }, sb),
        new WebAssembly.Global({ value: "i32" }, tb))
    });
    real.exports.register();
    this.programs.push({ instance: real, sb, tb, stat_words, fn_count });
    this.finished = false;
    return real;
  }

  async loadProgram(url) {
    const bytes = await (await fetch(url)).arrayBuffer();
    return this.loadProgramFromBytes(bytes);
  }

  // Load several program modules sharing one master (multi-section
  // BCPL, or a main program + libraries).
  //
  // IMPORTANT ordering rule: every program's register() writes G!1
  // (start tidx) if its source declares a `start` function. The LAST
  // loaded program wins. Pass library modules first and the entry
  // program last. run() prints a console warning if G!1 doesn't
  // resolve into the most-recently-loaded program's table slice.
  async loadProgramSet(urls) {
    if (!this.master) await this.loadMaster();
    for (const u of urls) await this.loadProgram(u);
  }

  initMaster(stackBaseWord) {
    const base = stackBaseWord ?? ((this.nextStaticWord + 3) & ~3);
    this.master.exports.init(base);

    // Allocate persistent stdin/stdout SCBs in the heap. Their
    // scbPtrs become the default cis/cos handles. They never get
    // freed — endread/endwrite reset back to these.
    this.stdoutScb = this._allocStream({ kind: "stdout", mode: "w", name: "**", data: "", pos: 0 });
    this.stdinScb  = this._allocStream({ kind: "stdin",  mode: "r", name: "**", data: "", pos: 0 });
    this.curOut = this.stdoutScb;
    this.curIn  = this.stdinScb;

    // Phase 4: seed state globals libhdr reserves as read-only values
    // programs can inspect directly (not function pointers).
    //   G!12  cis         = default input  handle (stdin scbPtr)
    //   G!13  cos         = default output handle (stdout scbPtr)
    //   G!127 randseed    = PRNG seed
    //   G!14  currentdir  = pointer to BCPL string "/"
    // G!9 (rootnode), G!190 (current_language), G!7/8 (coroutine state)
    // stay at 0 — unused by current feature set.
    this.storeWord(1 + 12, this.curIn);   // cis
    this.storeWord(1 + 13, this.curOut);  // cos
    this.storeWord(1 + 127, (Date.now() | 1) >>> 0);  // randseed

    // Allocate BCPL string "/" in heap and point G!14 at it.
    const slashWord = this.heapTop - 1;
    this.heapTop = slashWord;
    this.memView.setUint8(slashWord * 4,     1);   // length byte
    this.memView.setUint8(slashWord * 4 + 1, 47);  // '/'
    this.storeWord(1 + 14, slashWord);    // currentdir
  }

  async load(url) {
    await this.loadMaster();
    await this.loadProgram(url);
    this.initMaster();
    return this.programs.at(-1).instance;
  }

  // Multi-program loading rule: libraries first, entry program LAST.
  // Each program's register() writes G!1 if it exports start, so the
  // last loader wins. Callers must order loadProgram() accordingly.
  //
  // NOTE: for a multi-section source (one logical program split on
  // `.` separators into multiple modules), the start function lives
  // in only ONE module — usually the first section. That's normal;
  // not an ordering bug. Use checkEntryOrdering() explicitly when
  // you know each loaded program is a separate source.
  // Allocate an asyncify state buffer for the given execution context.
  // Returns the byte address of the buffer (state struct lives at
  // [bufStart, bufStart+8); rest is scratch).
  _allocAsyncifyBuffer(words = 256) {
    const base = this.heapTop - words;
    this.heapTop = base;
    const byteBase = base * 4;
    this.memView.setUint32(byteBase,     byteBase + 8, true);
    this.memView.setUint32(byteBase + 4, byteBase + words * 4, true);
    return byteBase;
  }

  // Reset an asyncify state buffer's stack-pointer header so a new
  // unwind starts fresh. Required before re-suspending into the same
  // buffer after a full unwind/rewind/finish cycle.
  _resetAsyncifyBuffer(byteBase, words = 256) {
    this.memView.setUint32(byteBase,     byteBase + 8, true);
    this.memView.setUint32(byteBase + 4, byteBase + words * 4, true);
  }

  // Coroutine-aware run loop. If the program never imports the
  // coroutine suspend points, this degenerates to the simple "call
  // start once" path.
  //
  // ASYNC: returns a Promise so callers can `await rt.run()`. The
  // promise resolves when the program completes. Animation loops use
  // delay() to yield between frames; this run loop awaits a setTimeout
  // for the requested duration before re-entering the suspended ctx.
  // Synchronous callers (existing examples) still work — non-async
  // programs never suspend, so the loop completes in one tick and
  // the awaited Promise resolves immediately.
  async run() {
    this.aborted = false;
    const tidx = this.loadWord(2);
    const startFn = this.master.exports.ftable.get(tidx);
    if (!startFn) throw new Error(`start (G!1 tidx=${tidx}) not in table`);

    const exp = this._coroutineExports();
    if (!exp) {
      // No asyncify support — plain entry.
      try { return startFn(); }
      catch (e) {
        if (e instanceof BcplHalt) return e.code;
        throw e;
      }
    }

    // Set up root execution context.
    this._coroutines ??= new Map();
    this._asyncifyMode = "normal";
    const rootBuf = this._allocAsyncifyBuffer();
    const root = {
      isRoot: true,
      handle: 0,
      asyncifyData: rootBuf,
      asyncifyWords: 256,
      bodyTidx: tidx,
      savedP: this.P,
      status: "new",
      resumeArg: 0,
      yieldedValue: 0,
      parentHandle: null,
    };
    this._rootCo = root;          // imp_* methods reach the root via this
    this._currentCo = root;
    this._scheduleResume = null;
    let lastReturn = 0;

    // Execute the entry context, then drive the cooperative loop until
    // every context is done or the root finishes.
    let ctx = root;
    while (ctx) {
      if (this.aborted) return 0;
      this.P = ctx.savedP;
      this._currentCo = ctx;
      // Mirror currco (G!7) for BCPL code that reads it directly.
      this.storeWord(1 + 7, ctx.isRoot ? 0 : ctx.handle);
      const isFirst = (ctx.status === "new");
      const isResume = (ctx.status === "suspended");

      if (isFirst && !ctx.isRoot) {
        // BCPL convention: body fn called with first cowait arg as its
        // single parameter. Stage it at P!3 before entry.
        this.storeWord(this.P + 0, 0);                    // saved P
        this.storeWord(this.P + 1, 0);                    // ret addr placeholder
        this.storeWord(this.P + 2, ctx.bodyTidx);         // entry fn_idx
        this.storeWord(this.P + 3, ctx.resumeArg | 0);    // arg
      }
      if (isResume) {
        this._asyncifyAllStartRewind(ctx.asyncifyData);
        this._asyncifyMode = "rewinding";
      } else {
        ctx.status = "running";
      }

      const fn = this.master.exports.ftable.get(ctx.bodyTidx);
      if (!fn) throw new Error(`coroutine body tidx=${ctx.bodyTidx} not in table`);
      try { lastReturn = fn(); }
      catch (e) {
        if (e instanceof BcplHalt) return e.code;
        throw e;
      }

      if (this._asyncifyMode === "unwinding") {
        this._asyncifyAllStopUnwind();
        this._asyncifyMode = "normal";
        ctx.savedP = this.P;
        ctx.status = "suspended";
        const nextHandle = this._scheduleResume;
        this._scheduleResume = null;
        // Animation pause: imp_delay set this. Yield to the browser
        // event loop for the requested duration so canvas can repaint.
        if (this._delayMs !== undefined && this._delayMs !== null) {
          const ms = this._delayMs;
          this._delayMs = null;
          // Always yield via requestAnimationFrame so the browser
          // composites + paints between frames. setTimeout alone is
          // not enough — short setTimeouts often coalesce away the
          // paint cycle. For longer waits (>16ms), follow the rAF
          // with a setTimeout for the remainder.
          const haveRaf = typeof requestAnimationFrame === "function";
          await new Promise((resolve) => {
            if (haveRaf) requestAnimationFrame(() => resolve());
            else setTimeout(resolve, 0);
          });
          if (ms > 16) {
            await new Promise((resolve) => setTimeout(resolve, ms - 16));
          }
        }
        // Breakpoint pause: imp_break set this. Wait indefinitely
        // until UI's resume() fires (or abort()). The host's
        // _pauseResolve is bound to the awaited promise.
        if (this._pausePromise) {
          await this._pausePromise;
        }
        if (this.aborted) return 0;
        if (nextHandle === null || nextHandle === 0) {
          ctx = this._coroutines.get(ctx.parentHandle) ?? root;
        } else {
          ctx = (nextHandle === root.handle) ? root : (this._coroutines.get(nextHandle) ?? root);
        }
      } else {
        ctx.status = "done";
        if (ctx.isRoot) return lastReturn;
        const parent = this._coroutines.get(ctx.parentHandle) ?? root;
        parent.resumeArg = lastReturn;
        ctx = parent;
      }
    }
    return lastReturn;
  }

  // Caller-invoked load-order check. Returns null if OK, else a
  // diagnostic string describing the mismatch. Use in multi-file UIs
  // where each program corresponds to a separate source file and the
  // entry is expected to be the last-loaded item.
  //
  //   const warn = rt.checkEntryOrdering(programsPerSource);
  //
  // `programsPerSource` (optional) is an array of how many loaded
  // programs each source compiled to. If omitted, treats every
  // loaded program as its own source.
  checkEntryOrdering(programsPerSource = null) {
    if (this.programs.length < 2) return null;
    const tidx = this.loadWord(2);
    let lastSourceStart = this.programs.length - 1;
    if (programsPerSource && programsPerSource.length) {
      const total = programsPerSource.reduce((a, b) => a + b, 0);
      if (total === this.programs.length) {
        lastSourceStart = this.programs.length - programsPerSource.at(-1);
      }
    }
    const lastSource = this.programs.slice(lastSourceStart);
    const inLast = lastSource.some(p =>
      tidx >= p.tb && tidx < p.tb + p.fn_count);
    if (inLast) return null;
    const owner = this.programs.find(p =>
      tidx >= p.tb && tidx < p.tb + p.fn_count);
    const idx = owner ? this.programs.indexOf(owner) : -1;
    return `G!1 (start) resolves into program #${idx}, not the ` +
      `last-loaded source. Load the entry program last so its ` +
      `register() wins the G!1 assignment.`;
  }

  // P/G accessors now route through master's exported globals.
  get P() { return this.master.exports.P.value; }
  set P(v) { this.master.exports.P.value = v | 0; }
}

export class BcplHalt {
  constructor(code, isAbort = false) {
    this.code = code;
    this.isAbort = isAbort;
  }
}
