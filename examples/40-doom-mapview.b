// 40-doom-mapview: parse a Doom WAD, find its first ExMy / MAPxx map,
// draw it as a 2D top-down line view (like Doom's automap).
//
// Setup:
//   1. Open the Assets tab; upload any WAD from site/textures/Wads/
//      (Doom1.WAD, doom2.wad, plutonia.wad, tnt.wad — case doesn't
//      matter, picked via Sys_assetlist).
//   2. Compile & Run.
//
// What it does:
//   1. Loads the WAD as a binary asset (Sys_assetload → byte address).
//   2. Walks the lump directory.
//   3. Finds the first lump whose 8-char name matches `ExMy` or
//      `MAPxx`. That's a map marker; the following lumps belong to it.
//   4. From the next ~10 entries grabs VERTEXES and LINEDEFS.
//   5. Computes the vertex bbox, scales to canvas (preserving aspect,
//      Y-flipped to match Doom's coordinate convention).
//   6. Draws each linedef as one Sys_sdl drawline call.
//
// Esc quits.

SECTION "dmap"

GET "libhdr"
GET "sdl"

MANIFEST {
  W       = 960
  H       = 720
  MARGIN  = 32

  // WAD layout
  HDR_SIZE         = 12
  HDR_NUMLUMPS_OFS =  4
  HDR_INFOOFS_OFS  =  8
  DIR_ENTRY_SIZE   = 16
  DIR_FILEPOS_OFS  =  0
  DIR_SIZE_OFS     =  4
  DIR_NAME_OFS     =  8

  // Map sub-lump sizes
  VERTEX_SIZE  = 4    // i16 x, i16 y
  LINEDEF_SIZE = 14   // i16 v1, v2, flags, special, tag, frontSide, backSide

  // Input
  KEYCAP   = 512
  K_ESC    = 27
}

STATIC {
  surf    = 0
  keys    = 0
  running = 1
  bg_col  = 0
  wall_col   = 0
  twosided_col = 0
}

// ---------- byte helpers (lifted from 39-wad-reader.b) ----------

LET lc(c) = c >= 'A' & c <= 'Z' -> c + ('a' - 'A'), c

LET cp_substr(buf, start, end, dest) BE
{ LET n = end - start
  dest % 0 := n
  FOR i = 0 TO n - 1 DO dest % (i + 1) := buf % (start + i)
}

LET ends_with_wad(buf, start, end) = VALOF
{ LET n = end - start
  IF n < 4 RESULTIS FALSE
  RESULTIS lc(buf % (end - 4)) = '.' &
           lc(buf % (end - 3)) = 'w' &
           lc(buf % (end - 2)) = 'a' &
           lc(buf % (end - 1)) = 'd'
}

LET try_load_wad(info) = VALOF
{ LET listbuf = VEC 64
  LET namebuf = VEC 32
  LET totlen, start, end = 0, 0, 0
  sys(Sys_assetlist, listbuf)
  totlen := listbuf % 0
  start := 1; end := 1
  WHILE end <= totlen DO
  { WHILE end <= totlen & listbuf % end ~= ',' DO end := end + 1
    IF ends_with_wad(listbuf, start, end) DO
    { cp_substr(listbuf, start, end, namebuf)
      IF sys(Sys_assetload, namebuf, info) DO
      { writef("loaded WAD: ")
        FOR i = start TO end - 1 DO wrch(listbuf % i)
        newline()
        RESULTIS TRUE
      }
    }
    end := end + 1; start := end
  }
  RESULTIS FALSE
}

// ---------- WAD reading ----------

LET rd_u32_le(base, off) = VALOF
{ LET b0 = base % (off + 0)
  LET b1 = base % (off + 1)
  LET b2 = base % (off + 2)
  LET b3 = base % (off + 3)
  RESULTIS b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
}

LET rd_u16_le(base, off) = (base % off) | ((base % (off + 1)) << 8)

// Signed 16-bit, two's complement. Vertex coords go up to ~8000 and
// down past zero — must sign-extend.
LET rd_i16_le(base, off) = VALOF
{ LET v = rd_u16_le(base, off)
  IF v >= #x8000 DO v := v - #x10000
  RESULTIS v
}

// 8-char lump name comparison. `name` is a BCPL string; remaining
// bytes in the lump-name slot must be NUL.
LET lump_name_eq(base, dir_byte_off, name) = VALOF
{ LET nlen = name % 0
  IF nlen > 8 RESULTIS FALSE
  FOR i = 0 TO nlen - 1 DO
    UNLESS base % (dir_byte_off + DIR_NAME_OFS + i) = name % (i + 1) RESULTIS FALSE
  FOR i = nlen TO 7 DO
    UNLESS base % (dir_byte_off + DIR_NAME_OFS + i) = 0 RESULTIS FALSE
  RESULTIS TRUE
}

// Check if dir entry's lump name matches a Doom map marker:
//   ExMy   (E + digit + M + digit, byte 4 is NUL)
//   MAPxx  (M A P + 2 digits, byte 5 is NUL)
LET is_map_marker(base, dir_byte_off) = VALOF
{ LET o = dir_byte_off + DIR_NAME_OFS
  LET c0 = base % (o + 0)
  LET c1 = base % (o + 1)
  LET c2 = base % (o + 2)
  LET c3 = base % (o + 3)
  LET c4 = base % (o + 4)
  IF c0 = 'E' & c1 >= '0' & c1 <= '9' &
     c2 = 'M' & c3 >= '0' & c3 <= '9' & c4 = 0 RESULTIS TRUE
  IF c0 = 'M' & c1 = 'A' & c2 = 'P' &
     c3 >= '0' & c3 <= '9' & c4 >= '0' & c4 <= '9' RESULTIS TRUE
  RESULTIS FALSE
}

// Print 8-char lump name (NUL-terminated).
LET pr_lump_name(base, dir_byte_off) BE
  FOR i = 0 TO 7 DO
  { LET c = base % (dir_byte_off + DIR_NAME_OFS + i)
    IF c = 0 BREAK
    wrch(c)
  }

// Find map marker; return its directory index, or -1 if none.
LET find_first_map(base, dirofs, numlumps) = VALOF
{ FOR i = 0 TO numlumps - 1 DO
  { LET e = dirofs + i * DIR_ENTRY_SIZE
    IF is_map_marker(base, e) RESULTIS i
  }
  RESULTIS -1
}

// Within the next 12 entries after `map_idx`, look for a lump with
// `name`. (Doom maps reliably keep sub-lumps in slots map+1..map+10.)
LET find_map_lump(base, dirofs, map_idx, numlumps, name) = VALOF
{ LET limit = map_idx + 12
  IF limit > numlumps DO limit := numlumps
  FOR i = map_idx + 1 TO limit - 1 DO
  { LET e = dirofs + i * DIR_ENTRY_SIZE
    IF lump_name_eq(base, e, name) RESULTIS i
  }
  RESULTIS -1
}

// ---------- input ----------

LET poll_events() BE
{ LET ev = VEC 7
  WHILE sys(Sys_sdl, sdl_pollevent, ev) DO
  { LET et = ev!0
    LET ch = ev!2
    TEST et = sdle_keydown
    THEN { IF ch >= 0 & ch < KEYCAP DO keys!ch := 1
           IF ch = K_ESC DO running := 0
         }
    ELSE IF et = sdle_keyup DO
         IF ch >= 0 & ch < KEYCAP DO keys!ch := 0
    IF et = sdle_quit DO running := 0
  }
}

// ---------- render ----------

// Scale + offset: world (x,y) -> screen (sx,sy). Computed once, stored
// in statics so drawframe stays cheap.
STATIC {
  min_x = 0
  min_y = 0
  scale_1024 = 1024
  off_x = 0
  off_y = 0
}

LET project_x(wx) = ((wx - min_x) * scale_1024) / 1024 + off_x

// Doom Y axis points up; canvas Y points down. Flip.
LET project_y(wy) = H - (((wy - min_y) * scale_1024) / 1024 + off_y)

LET drawmap(base, vert_byte, line_byte, nverts, nlines) BE
{ // Background.
  sys(Sys_sdl, sdl_drawfillrect, surf, 0, 0, W, H, bg_col)

  FOR i = 0 TO nlines - 1 DO
  { LET le  = line_byte + i * LINEDEF_SIZE
    LET v1  = rd_u16_le(base, le + 0)
    LET v2  = rd_u16_le(base, le + 2)
    LET back = rd_u16_le(base, le + 12)   // backSidedef; #xFFFF if 1-sided
    LET ve1 = vert_byte + v1 * VERTEX_SIZE
    LET ve2 = vert_byte + v2 * VERTEX_SIZE
    LET x1 = rd_i16_le(base, ve1 + 0)
    LET y1 = rd_i16_le(base, ve1 + 2)
    LET x2 = rd_i16_le(base, ve2 + 0)
    LET y2 = rd_i16_le(base, ve2 + 2)
    LET col = back = #xFFFF -> wall_col, twosided_col
    sys(Sys_sdl, sdl_drawline, surf,
        project_x(x1), project_y(y1),
        project_x(x2), project_y(y2),
        col)
  }
  sys(Sys_sdl, sdl_flip, surf)
}

// ---------- main ----------

LET compute_scale(base, vert_byte, nverts) BE
{ LET max_x, max_y = 0, 0
  LET first = TRUE
  LET sx_1024, sy_1024 = 0, 0
  FOR i = 0 TO nverts - 1 DO
  { LET vo = vert_byte + i * VERTEX_SIZE
    LET x = rd_i16_le(base, vo + 0)
    LET y = rd_i16_le(base, vo + 2)
    TEST first
    THEN { min_x := x; max_x := x; min_y := y; max_y := y; first := FALSE }
    ELSE { IF x < min_x DO min_x := x
           IF x > max_x DO max_x := x
           IF y < min_y DO min_y := y
           IF y > max_y DO max_y := y
         }
  }
  // Avoid divide-by-zero on degenerate maps.
  IF max_x = min_x DO max_x := min_x + 1
  IF max_y = min_y DO max_y := min_y + 1
  sx_1024 := ((W - 2 * MARGIN) * 1024) / (max_x - min_x)
  sy_1024 := ((H - 2 * MARGIN) * 1024) / (max_y - min_y)
  scale_1024 := sx_1024 < sy_1024 -> sx_1024, sy_1024
  // Centre within the canvas.
  off_x := MARGIN + ((W - 2 * MARGIN) - ((max_x - min_x) * scale_1024) / 1024) / 2
  off_y := MARGIN + ((H - 2 * MARGIN) - ((max_y - min_y) * scale_1024) / 1024) / 2
  writef("bbox  x: %n..%n   y: %n..%n*n", min_x, max_x, min_y, max_y)
  writef("scale 1024ths = %n  offset %n,%n*n", scale_1024, off_x, off_y)
}

LET start() = VALOF
{ LET info = VEC 3
  LET base, nbytes = 0, 0
  LET numlumps, dirofs = 0, 0
  LET map_idx = 0
  LET vert_idx, line_idx = 0, 0
  LET vert_byte, line_byte = 0, 0
  LET vsize, lsize = 0, 0
  LET nverts, nlines = 0, 0

  UNLESS try_load_wad(info) DO
  { writef("No WAD asset. Upload one from site/textures/Wads/*n")
    RESULTIS 1
  }

  nbytes := info!0
  IF info!1 ~= 0 DO { writef("Asset is an image, not a WAD.*n"); RESULTIS 1 }
  base := info!2
  IF nbytes < HDR_SIZE DO { writef("Truncated WAD.*n"); RESULTIS 1 }

  numlumps := rd_u32_le(base, HDR_NUMLUMPS_OFS)
  dirofs   := rd_u32_le(base, HDR_INFOOFS_OFS)
  writef("WAD: %n lumps, dir at %n, size %n bytes*n", numlumps, dirofs, nbytes)

  map_idx := find_first_map(base, dirofs, numlumps)
  IF map_idx < 0 DO
  { writef("No ExMy / MAPxx marker in this WAD.*n")
    RESULTIS 1
  }
  writef("map: "); pr_lump_name(base, dirofs + map_idx * DIR_ENTRY_SIZE); newline()

  vert_idx := find_map_lump(base, dirofs, map_idx, numlumps, "VERTEXES")
  line_idx := find_map_lump(base, dirofs, map_idx, numlumps, "LINEDEFS")
  IF vert_idx < 0 | line_idx < 0 DO
  { writef("Map missing VERTEXES or LINEDEFS lump.*n")
    RESULTIS 1
  }

  vert_byte := rd_u32_le(base, dirofs + vert_idx * DIR_ENTRY_SIZE + DIR_FILEPOS_OFS)
  vsize     := rd_u32_le(base, dirofs + vert_idx * DIR_ENTRY_SIZE + DIR_SIZE_OFS)
  line_byte := rd_u32_le(base, dirofs + line_idx * DIR_ENTRY_SIZE + DIR_FILEPOS_OFS)
  lsize     := rd_u32_le(base, dirofs + line_idx * DIR_ENTRY_SIZE + DIR_SIZE_OFS)
  nverts := vsize / VERTEX_SIZE
  nlines := lsize / LINEDEF_SIZE
  writef("verts: %n  linedefs: %n*n", nverts, nlines)

  compute_scale(base, vert_byte, nverts)

  sys(Sys_sdl, sdl_init)
  surf := sys(Sys_sdl, sdl_setvideomode, W, H, 0, 0)

  bg_col       := sys(Sys_sdl, sdl_maprgb, 0,  20,  20,  20)
  wall_col     := sys(Sys_sdl, sdl_maprgb, 0, 240, 220, 180)
  twosided_col := sys(Sys_sdl, sdl_maprgb, 0,  90,  90, 110)

  keys  := getvec(KEYCAP)
  FOR i = 0 TO KEYCAP DO keys!i := 0

  drawmap(base, vert_byte, line_byte, nverts, nlines)

  WHILE running DO
  { poll_events()
    delay(16)
  }

  freevec(keys)
  writef("dmap exited*n")
  RESULTIS 0
}
