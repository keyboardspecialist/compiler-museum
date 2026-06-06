// 50-doom-sky: 49 + textured sky cylinder.
//
// What's new vs 49:
//   - Composite the SKY1 wall texture out of TEXTURE1 just like any
//     other wall texture, then register it as bg slot 0.
//   - Ceiling bands of sectors whose ceiling flat is "F_SKY1" are
//     filled with Sys_drawskyspan instead of a flat colour: V is
//     anchored to absolute screen Y so the sky doesn't tilt with the
//     view, U scrolls with player angle.
//   - fill_remaining() above the horizon also draws sky if loaded.
//
// Controls: WASD/arrows = move/turn, Esc = quit.

SECTION "dsky"

GET "libhdr"
GET "sdl"

MANIFEST {
  W       = 960
  H       = 720
  HORIZON = 360
  F_X     = 480
  NEAR    = 4
  EYE_H   = 41
  SUBSECTOR_BIT = #x8000

  HDR_NUMLUMPS_OFS =  4
  HDR_INFOOFS_OFS  =  8
  HDR_SIZE         = 12
  DIR_ENTRY_SIZE   = 16
  DIR_FILEPOS_OFS  =  0
  DIR_SIZE_OFS     =  4
  DIR_NAME_OFS     =  8

  VERTEX_SIZE  = 4
  LINEDEF_SIZE = 14
  LINEDEF_FLAGS_OFS =  4
  LINEDEF_FRONT_OFS = 10
  LINEDEF_BACK_OFS  = 12

  ML_DONTPEGTOP    = #x0008
  ML_DONTPEGBOTTOM = #x0010
  SIDEDEF_SIZE        = 30
  SIDEDEF_TEXOFFX_OFS =  0
  SIDEDEF_TEXOFFY_OFS =  2
  SIDEDEF_UPPER_OFS   =  4
  SIDEDEF_LOWER_OFS   = 12
  SIDEDEF_MIDDLE_OFS  = 20
  SIDEDEF_SECTOR_OFS  = 28
  SECTOR_SIZE         = 26
  SECTOR_FLOOR_OFS    = 0
  SECTOR_CEIL_OFS     = 2
  SECTOR_FLOORTEX_OFS = 4         // 8-byte name
  SECTOR_CEILTEX_OFS  = 12        // 8-byte name
  SECTOR_LIGHT_OFS    = 20

  FLAT_BYTES = 4096               // 64x64 palette indices per flat
  MAX_FLATS  = 64

  LIGHT_DROP = 20                 // bigger = slower fade with depth
  LIGHT_FADE_MIN = 32             // never go fully black

  MAX_SPRITES = 64
  Z_INF = #x7FFFFFFF              // sentinel "no wall yet" depth

  STEP_MAX  = 24                  // max step-up height (Doom standard)
  PLAYER_H  = 56                  // physical body height (eye at +41)

  NODE_SIZE    = 28
  NODE_PX_OFS  = 0
  NODE_PY_OFS  = 2
  NODE_DX_OFS  = 4
  NODE_DY_OFS  = 6
  NODE_RC_OFS  = 24
  NODE_LC_OFS  = 26

  SSECTOR_SIZE       = 4
  SSECTOR_NUMSEG_OFS = 0
  SSECTOR_FIRST_OFS  = 2

  SEG_SIZE       = 12
  SEG_V1_OFS     = 0
  SEG_V2_OFS     = 2
  SEG_LINE_OFS   = 6
  SEG_SIDE_OFS   = 8
  SEG_OFFSET_OFS = 10

  THING_SIZE   = 10
  THING_X_OFS    = 0
  THING_Y_OFS    = 2
  THING_ANG_OFS  = 4
  THING_TYPE_OFS = 6

  // PNAMES layout:
  //   0..3  u32 numpatches
  //   4+    array of 8-byte patch names

  // TEXTURE1 layout:
  //   0..3  u32 numtextures
  //   4..   array of u32 offsets (relative to TEXTURE1 start)
  //   per texture def:
  //     0..7   8-byte name
  //     8..11  u32 masked (unused)
  //    12..13  i16 width
  //    14..15  i16 height
  //    16..19  u32 columndirectory (unused)
  //    20..21  i16 numpatches
  //    22+     array of patchdef (10 bytes each):
  //              0..1  i16 originx
  //              2..3  i16 originy
  //              4..5  i16 pname index
  //              6..7  i16 stepdir (unused)
  //              8..9  i16 colormap (unused)

  PATCHDEF_SIZE = 10
  PATCH_HDR_SIZE = 8       // width, height, leftoff, topoff (4 i16)
  POST_END = 255           // 0xFF terminates a column's post list

  MAX_TEX = 128            // cap on unique sidedef textures we composite

  ANG    = 8192
  MOVE   = 16
  TURN   = 64

  KEYCAP   = 512
  K_LEFT   = 37
  K_UP     = 38
  K_RIGHT  = 39
  K_DOWN   = 40
  K_A      = 65
  K_D      = 68
  K_S      = 83
  K_W      = 87
  K_ESC    = 27
}

STATIC {
  surf    = 0
  keys    = 0
  running = 1
  sin_t = 0
  cos_t = 0

  g_base      = 0
  g_dirofs    = 0
  g_numlumps  = 0
  g_vert_byte = 0
  g_line_byte = 0
  g_side_byte = 0
  g_sec_byte  = 0
  g_node_byte = 0
  g_ssec_byte = 0
  g_seg_byte  = 0
  g_root_node = 0

  // Texture pipeline state.
  g_pal       = 0       // VEC 256: pal[i] = packed 0xRRGGBBAA
  g_pnames    = 0       // byte addr of first patch name in PNAMES
  g_npnames   = 0
  g_tex1      = 0       // byte addr of TEXTURE1 lump start
  g_ntex1     = 0

  // Cache of composited textures.  Parallel arrays index by 0..tex_count-1.
  tex_count   = 0
  tex_name    = 0       // VEC MAX_TEX*2 — 8 bytes per name (2 words)
  tex_base    = 0       // VEC MAX_TEX — word addr of composited RGBA
  tex_w_vec   = 0       // VEC MAX_TEX — width
  tex_h_vec   = 0       // VEC MAX_TEX — height

  col_top   = 0
  col_bot   = 0
  cols_open = 0

  sky_col   = 0
  floor_col = 0

  px = 0
  py = 0
  pa = 0
  cam_z = 0

  // Flat texture cache.
  flat_count = 0
  flat_name  = 0     // VEC MAX_FLATS*2 — 8 bytes per name
  flat_base  = 0     // VEC MAX_FLATS — word addr of 64x64 RGBA

  // Frame-constant camera basis (set in drawframe).
  fwd_x = 0
  fwd_y = 0
  right_x = 0
  right_y = 0

  // Per-column z-buffer (nearest cy seen during wall rendering).
  col_z = 0

  // Sprite cache.
  spr_count = 0
  spr_name  = 0     // VEC MAX_SPRITES*2  (8 bytes each)
  spr_base  = 0     // word addr of RGBA buffer
  spr_w     = 0     // patch width
  spr_h     = 0     // patch height
  spr_lofs  = 0     // patch leftoffset
  spr_tofs  = 0     // patch topoffset

  // Where things live (set in main).
  g_things_byte = 0
  g_tsize       = 0
  g_nlines      = 0     // number of LINEDEFS in the current map

  // Sky cylinder (loaded via TEXTURE1 lookup of "SKY1").
  sky_loaded = FALSE
  sky_w      = 0
  sky_h      = 0
  sky_base   = 0
}

// ---------- byte helpers (same as 43) ----------

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

LET rd_u32_le(base, off) = VALOF
{ LET b0 = base % (off + 0)
  LET b1 = base % (off + 1)
  LET b2 = base % (off + 2)
  LET b3 = base % (off + 3)
  RESULTIS b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
}

LET rd_u16_le(base, off) = (base % off) | ((base % (off + 1)) << 8)

LET rd_i16_le(base, off) = VALOF
{ LET v = rd_u16_le(base, off)
  IF v >= #x8000 DO v := v - #x10000
  RESULTIS v
}

LET lump_name_eq(base, dir_byte_off, name) = VALOF
{ LET nlen = name % 0
  IF nlen > 8 RESULTIS FALSE
  FOR i = 0 TO nlen - 1 DO
    UNLESS base % (dir_byte_off + DIR_NAME_OFS + i) = name % (i + 1) RESULTIS FALSE
  FOR i = nlen TO 7 DO
    UNLESS base % (dir_byte_off + DIR_NAME_OFS + i) = 0 RESULTIS FALSE
  RESULTIS TRUE
}

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

LET pr_lump_name(base, dir_byte_off) BE
  FOR i = 0 TO 7 DO
  { LET c = base % (dir_byte_off + DIR_NAME_OFS + i)
    IF c = 0 BREAK
    wrch(c)
  }

LET find_first_map(base, dirofs, numlumps) = VALOF
{ FOR i = 0 TO numlumps - 1 DO
  { LET e = dirofs + i * DIR_ENTRY_SIZE
    IF is_map_marker(base, e) RESULTIS i
  }
  RESULTIS -1
}

LET find_map_lump(base, dirofs, map_idx, numlumps, name) = VALOF
{ LET limit = map_idx + 12
  IF limit > numlumps DO limit := numlumps
  FOR i = map_idx + 1 TO limit - 1 DO
  { LET e = dirofs + i * DIR_ENTRY_SIZE
    IF lump_name_eq(base, e, name) RESULTIS i
  }
  RESULTIS -1
}

// Compare two 8-byte raw name buffers (byte addresses). NULs treated
// as terminators on either side.
LET name8_eq(base_a, off_a, base_b, off_b) = VALOF
{ FOR i = 0 TO 7 DO
  { LET ca = base_a % (off_a + i)
    LET cb = base_b % (off_b + i)
    IF ca = 0 & cb = 0 RESULTIS TRUE
    UNLESS ca = cb RESULTIS FALSE
  }
  RESULTIS TRUE
}

// Find a lump anywhere in the WAD by matching its 8-char dir name
// against the 8 bytes at (name_base, name_off). Returns dir index or -1.
LET find_lump_global(name_base, name_off) = VALOF
{ FOR i = 0 TO g_numlumps - 1 DO
  { LET e = g_dirofs + i * DIR_ENTRY_SIZE + DIR_NAME_OFS
    IF name8_eq(g_base, e, name_base, name_off) RESULTIS i
  }
  RESULTIS -1
}

// ---------- trig ----------

LET fsin(x) = VALOF
{ LET pi, twopi, x2, t, s = 0, 0, 0, 0, 0
  pi    #:= 3.14159265358979
  twopi #:= 2.0 #* pi
  WHILE x #>  pi DO x #:= x #- twopi
  WHILE x #<  (0.0 #- pi) DO x #:= x #+ twopi
  x2 #:= x #* x
  t  #:= x;  s  #:= t
  t #:= 0.0 #- (t #* x2) #/ 6.0;   s #:= s #+ t
  t #:= 0.0 #- (t #* x2) #/ 20.0;  s #:= s #+ t
  t #:= 0.0 #- (t #* x2) #/ 42.0;  s #:= s #+ t
  t #:= 0.0 #- (t #* x2) #/ 72.0;  s #:= s #+ t
  RESULTIS s
}

LET fcos(x) = fsin(x #+ 1.5707963267948966)

LET buildtrig() BE
{ LET a, step, sv, cv = 0, 0, 0, 0
  LET fANG = 0
  fANG #:= FLOAT ANG
  a    #:= 0.0
  step #:= (2.0 #* 3.14159265358979) #/ fANG
  FOR i = 0 TO ANG-1 DO
  { sv #:= fsin(a) #* 1024.0
    cv #:= fcos(a) #* 1024.0
    sin_t!i := FIX sv
    cos_t!i := FIX cv
    a #:= a #+ step
  }
}

// Integer sqrt (Newton). Used for wall length in U computation.
LET isqrt(n) = VALOF
{ LET x = 0
  LET y = 0
  IF n <= 0 RESULTIS 0
  x := n; y := 1
  WHILE x > y DO
  { x := (x + y) / 2
    y := n / x
  }
  RESULTIS x
}

// ---------- map data accessors ----------

LET sd_sector(idx) =
  rd_i16_le(g_base, g_side_byte + idx * SIDEDEF_SIZE + SIDEDEF_SECTOR_OFS)

LET sd_texoffx(idx) =
  rd_i16_le(g_base, g_side_byte + idx * SIDEDEF_SIZE + SIDEDEF_TEXOFFX_OFS)

LET sd_texoffy(idx) =
  rd_i16_le(g_base, g_side_byte + idx * SIDEDEF_SIZE + SIDEDEF_TEXOFFY_OFS)

LET sec_floor(idx) =
  rd_i16_le(g_base, g_sec_byte + idx * SECTOR_SIZE + SECTOR_FLOOR_OFS)

LET sec_ceil(idx) =
  rd_i16_le(g_base, g_sec_byte + idx * SECTOR_SIZE + SECTOR_CEIL_OFS)

LET sec_light(idx) =
  rd_i16_le(g_base, g_sec_byte + idx * SECTOR_SIZE + SECTOR_LIGHT_OFS)

LET sec_floortex_byte(idx) =
  g_sec_byte + idx * SECTOR_SIZE + SECTOR_FLOORTEX_OFS

LET sec_ceiltex_byte(idx) =
  g_sec_byte + idx * SECTOR_SIZE + SECTOR_CEILTEX_OFS

// ---------- flat cache ----------

LET name8_is_sky(name_base, name_off) = VALOF
{ // "F_SKY1" with trailing NUL.
  IF name_base % (name_off + 0) ~= 'F' RESULTIS FALSE
  IF name_base % (name_off + 1) ~= '_' RESULTIS FALSE
  IF name_base % (name_off + 2) ~= 'S' RESULTIS FALSE
  IF name_base % (name_off + 3) ~= 'K' RESULTIS FALSE
  IF name_base % (name_off + 4) ~= 'Y' RESULTIS FALSE
  IF name_base % (name_off + 5) ~= '1' RESULTIS FALSE
  RESULTIS TRUE
}

// TRUE if sector `s` has the F_SKY1 ceiling marker.
LET sector_ceil_is_sky(s) = VALOF
{ IF s < 0 RESULTIS FALSE
  RESULTIS name8_is_sky(g_base, sec_ceiltex_byte(s))
}

LET flat_cache_lookup(name_base, name_off) = VALOF
{ FOR i = 0 TO flat_count - 1 DO
    IF name8_eq(flat_name + i * 2, 0, name_base, name_off) RESULTIS i
  RESULTIS -1
}

// Decode the flat lump for `name` and cache it. Returns cache idx, or
// -1 if the lump is missing or the slot is "-" / "F_SKY1".
LET load_flat(name_base, name_off) = VALOF
{ LET first_c = name_base % name_off
  LET lump_idx = 0
  LET le, fp, fsize, buf = 0, 0, 0, 0
  IF first_c = 0 RESULTIS -1
  IF first_c = '-' RESULTIS -1
  IF name8_is_sky(name_base, name_off) RESULTIS -1
  IF flat_count >= MAX_FLATS RESULTIS -1

  lump_idx := find_lump_global(name_base, name_off)
  IF lump_idx < 0 RESULTIS -1
  le := g_dirofs + lump_idx * DIR_ENTRY_SIZE
  fp := rd_u32_le(g_base, le + DIR_FILEPOS_OFS)
  fsize := rd_u32_le(g_base, le + DIR_SIZE_OFS)
  IF fsize < FLAT_BYTES RESULTIS -1

  buf := getvec(FLAT_BYTES)
  IF buf = 0 RESULTIS -1
  FOR i = 0 TO FLAT_BYTES - 1 DO
  { LET pal_idx = g_base % (fp + i)
    buf!i := g_pal!pal_idx
  }
  // Stash name.
  FOR i = 0 TO 7 DO
    flat_name % (flat_count * 8 + i) := name_base % (name_off + i)
  flat_base!flat_count := buf
  flat_count := flat_count + 1
  RESULTIS flat_count - 1
}

LET ensure_flat(name_base, name_off) = VALOF
{ LET idx = flat_cache_lookup(name_base, name_off)
  IF idx >= 0 RESULTIS idx
  RESULTIS load_flat(name_base, name_off)
}

LET prebuild_flats(num_sectors) BE
{ FOR s = 0 TO num_sectors - 1 DO
  { ensure_flat(g_base, sec_floortex_byte(s))
    ensure_flat(g_base, sec_ceiltex_byte(s))
  }
  writef("cached %n unique flats*n", flat_count)
}

LET point_on_side(x, y, no) = VALOF
{ LET pxn = rd_i16_le(g_base, no + NODE_PX_OFS)
  LET pyn = rd_i16_le(g_base, no + NODE_PY_OFS)
  LET dxn = rd_i16_le(g_base, no + NODE_DX_OFS)
  LET dyn = rd_i16_le(g_base, no + NODE_DY_OFS)
  LET dx = x - pxn
  LET dy = y - pyn
  IF dy * dxn < dyn * dx RESULTIS 0
  RESULTIS 1
}

LET point_in_subsector(x, y) = VALOF
{ LET n = g_root_node
  WHILE (n & SUBSECTOR_BIT) = 0 DO
  { LET no = g_node_byte + n * NODE_SIZE
    LET side = point_on_side(x, y, no)
    TEST side = 0
    THEN n := rd_u16_le(g_base, no + NODE_RC_OFS)
    ELSE n := rd_u16_le(g_base, no + NODE_LC_OFS)
  }
  RESULTIS n & ~SUBSECTOR_BIT
}

// Sector index containing world (x, y).  -1 if degenerate.
LET sector_at(x, y) = VALOF
{ LET ssidx = point_in_subsector(x, y)
  LET se = g_ssec_byte + ssidx * SSECTOR_SIZE
  LET first_seg = rd_u16_le(g_base, se + SSECTOR_FIRST_OFS)
  LET seg = g_seg_byte + first_seg * SEG_SIZE
  LET ld = rd_u16_le(g_base, seg + SEG_LINE_OFS)
  LET sd = rd_u16_le(g_base, seg + SEG_SIDE_OFS)
  LET le = g_line_byte + ld * LINEDEF_SIZE
  LET sd_idx = sd = 0 -> rd_i16_le(g_base, le + LINEDEF_FRONT_OFS),
                         rd_i16_le(g_base, le + LINEDEF_BACK_OFS)
  IF sd_idx < 0 RESULTIS -1
  RESULTIS sd_sector(sd_idx)
}

LET floor_at(x, y) = VALOF
{ LET s = sector_at(x, y)
  IF s < 0 RESULTIS 0
  RESULTIS sec_floor(s)
}

LET ceil_at(x, y) = VALOF
{ LET s = sector_at(x, y)
  IF s < 0 RESULTIS 0
  RESULTIS sec_ceil(s)
}

// True if the line segment (p1..p2) crosses any blocking linedef.
// A linedef blocks when it's 1-sided OR the two-sided opening on the
// other side is too small for the player (step too high / ceiling
// too low).  This is the real wall test — checking the destination
// sector's floor/ceiling alone is not enough since the BSP covers
// the whole plane and outside-map points still resolve to some valid
// sector.
LET line_blocks_move(p1x, p1y, p2x, p2y) = VALOF
{ LET cur_floor = floor_at(p1x, p1y)
  FOR i = 0 TO g_nlines - 1 DO
  { LET le      = g_line_byte + i * LINEDEF_SIZE
    LET v1      = rd_u16_le(g_base, le + 0)
    LET v2      = rd_u16_le(g_base, le + 2)
    LET front_sd = rd_i16_le(g_base, le + LINEDEF_FRONT_OFS)
    LET back_sd  = rd_i16_le(g_base, le + LINEDEF_BACK_OFS)
    LET vo1     = g_vert_byte + v1 * VERTEX_SIZE
    LET vo2     = g_vert_byte + v2 * VERTEX_SIZE
    LET ax = rd_i16_le(g_base, vo1 + 0)
    LET ay = rd_i16_le(g_base, vo1 + 2)
    LET bx = rd_i16_le(g_base, vo2 + 0)
    LET by = rd_i16_le(g_base, vo2 + 2)
    // Segment cross-product side tests.
    LET d1 = (bx - ax) * (p1y - ay) - (by - ay) * (p1x - ax)
    LET d2 = (bx - ax) * (p2y - ay) - (by - ay) * (p2x - ax)
    LET d3 = (p2x - p1x) * (ay - p1y) - (p2y - p1y) * (ax - p1x)
    LET d4 = (p2x - p1x) * (by - p1y) - (p2y - p1y) * (bx - p1x)
    UNLESS ((d1 > 0) ~= (d2 > 0)) & ((d3 > 0) ~= (d4 > 0)) LOOP
    // Linedef IS crossed; decide if blocking.
    IF back_sd < 0 RESULTIS TRUE
    IF front_sd < 0 RESULTIS TRUE
    { LET front_sec = sd_sector(front_sd)
      LET back_sec  = sd_sector(back_sd)
      LET ff = sec_floor(front_sec)
      LET fc = sec_ceil(front_sec)
      LET bf = sec_floor(back_sec)
      LET bc = sec_ceil(back_sec)
      LET higher_floor = bf > ff -> bf, ff
      LET lower_ceil   = bc < fc -> bc, fc
      IF higher_floor - cur_floor > STEP_MAX RESULTIS TRUE
      IF lower_ceil - higher_floor < PLAYER_H RESULTIS TRUE
    }
  }
  RESULTIS FALSE
}

LET try_move(dx, dy) BE
{ LET nx = px + dx
  LET ny = py + dy
  TEST line_blocks_move(px, py, nx, ny) = FALSE
  THEN { px := nx;  py := ny }
  ELSE { IF line_blocks_move(px, py, nx, py) = FALSE DO px := nx
         IF line_blocks_move(px, py, px, ny) = FALSE DO py := ny
       }
}

// ---------- player + input ----------

LET find_player_start(base, things_byte, tsize) = VALOF
{ LET n = tsize / THING_SIZE
  FOR i = 0 TO n - 1 DO
  { LET o = things_byte + i * THING_SIZE
    LET tp = rd_u16_le(base, o + THING_TYPE_OFS)
    IF tp = 1 DO
    { LET deg = rd_u16_le(base, o + THING_ANG_OFS)
      px := rd_i16_le(base, o + THING_X_OFS)
      py := rd_i16_le(base, o + THING_Y_OFS)
      pa := ((deg * ANG) / 360) & (ANG - 1)
      RESULTIS TRUE
    }
  }
  RESULTIS FALSE
}

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

LET key_down(k) = k >= 0 & k < KEYCAP -> keys!k, 0

// ---------- texture pipeline ----------

// Load PLAYPAL[0] into g_pal as 256 packed RGBA words.
LET load_palette(playpal_byte) BE
{ FOR i = 0 TO 255 DO
  { LET o = playpal_byte + i * 3
    LET r = g_base % (o + 0)
    LET g = g_base % (o + 1)
    LET b = g_base % (o + 2)
    g_pal!i := ((r & #xFF) << 24) | ((g & #xFF) << 16) |
               ((b & #xFF) << 8)  | #xFF
  }
}

// Find a texture def in TEXTURE1 by 8-char name. `name_base, name_off`
// point at the 8-byte name. Returns byte offset into the WAD of the
// texture def, or 0 if not found.
LET find_tex1_def(name_base, name_off) = VALOF
{ FOR i = 0 TO g_ntex1 - 1 DO
  { LET ofs_to_def = rd_u32_le(g_base, g_tex1 + 4 + i * 4)
    LET def_byte = g_tex1 + ofs_to_def
    IF name8_eq(g_base, def_byte, name_base, name_off) RESULTIS def_byte
  }
  RESULTIS 0
}

// Look up cache entry by 8-byte name. Returns index or -1.
LET tex_cache_lookup(name_base, name_off) = VALOF
{ FOR i = 0 TO tex_count - 1 DO
  { LET cache_name_byte = (tex_name + i * 2) << 2     // word*4 = byte addr
    IF name8_eq(tex_name + i * 2, 0, name_base, name_off) RESULTIS i
  }
  RESULTIS -1
}

// Write one composited pixel.  Split out so the codegen has fewer
// live temps in the hot stamp loop (the 32-slot temp budget overflows
// otherwise).
LET tex_put(tex_buf, x, y, tex_w, color) BE
{ LET idx = y * tex_w + x
  tex_buf!idx := color
}

// Composite a patch column into the texture buffer.
LET stamp_patch_column(patch_byte, patch_col, tex_buf, tex_w, tex_h,
                       origin_x, origin_y) BE
{ LET col_ofs_table = patch_byte + PATCH_HDR_SIZE
  LET col_data_ofs = rd_u32_le(g_base, col_ofs_table + patch_col * 4)
  LET col_data = patch_byte + col_data_ofs
  LET dest_x = origin_x + patch_col
  LET cursor = 0
  LET yofs = 0
  IF dest_x < 0 | dest_x >= tex_w RETURN
  yofs := g_base % (col_data + cursor)
  WHILE yofs ~= POST_END DO
  { LET nbytes = g_base % (col_data + cursor + 1)
    FOR i = 0 TO nbytes - 1 DO
    { LET pal_idx = g_base % (col_data + cursor + 3 + i)
      LET dest_y  = origin_y + yofs + i
      IF dest_y >= 0 & dest_y < tex_h DO
        tex_put(tex_buf, dest_x, dest_y, tex_w, g_pal!pal_idx)
    }
    cursor := cursor + nbytes + 4
    yofs := g_base % (col_data + cursor)
  }
}

// Composite a texture: allocate buffer, stamp every patch, register in
// cache. Returns cache index, or -1 if def not found.
LET composite_texture(name_base, name_off) = VALOF
{ LET def_byte = find_tex1_def(name_base, name_off)
  LET tex_w = 0
  LET tex_h = 0
  LET npatches = 0
  LET tex_buf = 0
  LET cache_name_byte = 0

  IF def_byte = 0 RESULTIS -1
  IF tex_count >= MAX_TEX RESULTIS -1

  tex_w    := rd_i16_le(g_base, def_byte + 12)
  tex_h    := rd_i16_le(g_base, def_byte + 14)
  npatches := rd_i16_le(g_base, def_byte + 20)
  IF tex_w <= 0 | tex_h <= 0 RESULTIS -1

  tex_buf := getvec(tex_w * tex_h)
  IF tex_buf = 0 RESULTIS -1
  // Initialise to transparent black.
  FOR i = 0 TO tex_w * tex_h - 1 DO tex_buf!i := 0

  FOR p = 0 TO npatches - 1 DO
  { LET pd = def_byte + 22 + p * PATCHDEF_SIZE
    LET origin_x = rd_i16_le(g_base, pd + 0)
    LET origin_y = rd_i16_le(g_base, pd + 2)
    LET pname_idx = rd_i16_le(g_base, pd + 4)
    LET pname_byte = g_pnames + pname_idx * 8
    LET lump_idx = find_lump_global(g_base, pname_byte - g_base * 0)
    LET patch_byte = 0
    LET patch_w = 0
    LET le = 0
    UNLESS lump_idx >= 0 LOOP
    le := g_dirofs + lump_idx * DIR_ENTRY_SIZE
    patch_byte := rd_u32_le(g_base, le + DIR_FILEPOS_OFS)
    patch_w := rd_i16_le(g_base, patch_byte + 0)
    FOR pc = 0 TO patch_w - 1 DO
      stamp_patch_column(patch_byte, pc, tex_buf, tex_w, tex_h,
                         origin_x, origin_y)
  }

  // Register in cache.  Copy the 8-byte name into our name vec.
  cache_name_byte := (tex_name + tex_count * 2) * 4    // byte addr of slot
  FOR i = 0 TO 7 DO
    tex_name % (tex_count * 8 + i) := name_base % (name_off + i)
  tex_base!tex_count  := tex_buf
  tex_w_vec!tex_count := tex_w
  tex_h_vec!tex_count := tex_h
  tex_count := tex_count + 1
  RESULTIS tex_count - 1
}

// Make sure a sidedef texture is composited. `tex_slot_offset` is
// SIDEDEF_UPPER_OFS / LOWER_OFS / MIDDLE_OFS.  Returns cache index, or
// -1 if the slot is "-" (no texture).
LET ensure_sidedef_tex(sd_idx, tex_slot_offset) = VALOF
{ LET name_byte = g_side_byte + sd_idx * SIDEDEF_SIZE + tex_slot_offset
  LET first_c = g_base % name_byte
  LET idx = 0
  // "-" (one byte) means no texture. Byte 1 is then NUL.
  IF first_c = '-' & g_base % (name_byte + 1) = 0 RESULTIS -1
  IF first_c = 0 RESULTIS -1
  idx := tex_cache_lookup(g_base, name_byte)
  IF idx >= 0 RESULTIS idx
  RESULTIS composite_texture(g_base, name_byte)
}

// Walk every sidedef and pre-composite each unique texture once.
// ---------- sprite cache (must come after stamp_patch_column) ----------

LET spr_cache_lookup(name_bcpl) = VALOF
{ LET nlen = name_bcpl % 0
  FOR i = 0 TO spr_count - 1 DO
  { LET match = TRUE
    LET cache_off = i * 8
    FOR k = 0 TO 7 DO
    { LET ca = spr_name % (cache_off + k)
      LET cb = k < nlen -> name_bcpl % (k + 1), 0
      UNLESS ca = cb DO { match := FALSE; BREAK }
    }
    IF match RESULTIS i
  }
  RESULTIS -1
}

LET find_lump_bcpl(name_bcpl) = VALOF
{ LET nlen = name_bcpl % 0
  FOR i = 0 TO g_numlumps - 1 DO
  { LET e = g_dirofs + i * DIR_ENTRY_SIZE + DIR_NAME_OFS
    LET match = TRUE
    FOR k = 0 TO 7 DO
    { LET wad_c = g_base % (e + k)
      LET want  = k < nlen -> name_bcpl % (k + 1), 0
      UNLESS wad_c = want DO { match := FALSE; BREAK }
    }
    IF match RESULTIS i
  }
  RESULTIS -1
}

LET load_sprite(name_bcpl) = VALOF
{ LET lump_idx = 0
  LET le, fp = 0, 0
  LET pw, ph, lo, to = 0, 0, 0, 0
  LET buf = 0
  LET nlen = name_bcpl % 0

  IF spr_count >= MAX_SPRITES RESULTIS -1
  lump_idx := find_lump_bcpl(name_bcpl)
  IF lump_idx < 0 RESULTIS -1
  le := g_dirofs + lump_idx * DIR_ENTRY_SIZE
  fp := rd_u32_le(g_base, le + DIR_FILEPOS_OFS)
  pw := rd_i16_le(g_base, fp + 0)
  ph := rd_i16_le(g_base, fp + 2)
  lo := rd_i16_le(g_base, fp + 4)
  to := rd_i16_le(g_base, fp + 6)
  IF pw <= 0 | ph <= 0 RESULTIS -1

  buf := getvec(pw * ph)
  IF buf = 0 RESULTIS -1
  FOR i = 0 TO pw * ph - 1 DO buf!i := 0

  FOR pc = 0 TO pw - 1 DO
    stamp_patch_column(fp, pc, buf, pw, ph, 0, 0)

  FOR k = 0 TO 7 DO
    spr_name % (spr_count * 8 + k) := k < nlen -> name_bcpl % (k + 1), 0
  spr_base!spr_count := buf
  spr_w!spr_count    := pw
  spr_h!spr_count    := ph
  spr_lofs!spr_count := lo
  spr_tofs!spr_count := to
  spr_count := spr_count + 1
  RESULTIS spr_count - 1
}

LET ensure_sprite(name_bcpl) = VALOF
{ LET idx = spr_cache_lookup(name_bcpl)
  IF idx >= 0 RESULTIS idx
  RESULTIS load_sprite(name_bcpl)
}

LET thing_sprite_name(thing_type) = VALOF
{ SWITCHON thing_type INTO
  { CASE 2035: RESULTIS "BAR1A0"      // explosive barrel
    CASE 2011: RESULTIS "STIMA0"      // stimpack
    CASE 2012: RESULTIS "MEDIA0"      // medikit
    CASE 2014: RESULTIS "BON1A0"      // health bonus
    CASE 2015: RESULTIS "BON2A0"      // armor bonus
    CASE 2018: RESULTIS "ARM1A0"      // green armor
    CASE 2019: RESULTIS "ARM2A0"      // blue armor
    CASE 2008: RESULTIS "CLIPA0"      // bullet clip
    CASE 2048: RESULTIS "AMMOA0"      // bullet box
    CASE 2046: RESULTIS "BROKA0"      // rocket box
    CASE 2047: RESULTIS "CELLA0"      // cell charge
    CASE 17:   RESULTIS "CELPA0"      // cell pack
    CASE 2001: RESULTIS "SHOTA0"      // shotgun
    CASE 2002: RESULTIS "MGUNA0"      // chaingun
    CASE 2003: RESULTIS "LAUNA0"      // rocket launcher
    CASE 2005: RESULTIS "CSAWA0"      // chainsaw
    CASE 2006: RESULTIS "PLASA0"      // plasma rifle
    CASE 5:    RESULTIS "BKEYA0"      // blue key
    CASE 13:   RESULTIS "RKEYA0"      // red key
    CASE 6:    RESULTIS "YKEYA0"      // yellow key
    CASE 2025: RESULTIS "SUITA0"      // rad suit
    CASE 2024: RESULTIS "PINSA0"      // blursphere
    CASE 2022: RESULTIS "PINVA0"      // invuln
    CASE 8:    RESULTIS "BPAKA0"      // backpack
    CASE 2007: RESULTIS "AMMOA0"
    CASE 3001: RESULTIS "TROOA1"      // imp
    CASE 3002: RESULTIS "SARGA1"      // demon
    CASE 3004: RESULTIS "POSSA1"      // zombieman
    CASE 9:    RESULTIS "SPOSA1"      // shotgun guy
    CASE 3005: RESULTIS "HEADA1"      // cacodemon
    CASE 3006: RESULTIS "SKULA1"      // lost soul
    DEFAULT: RESULTIS 0
  }
}

LET prebuild_textures(num_sidedefs) BE
{ FOR sd = 0 TO num_sidedefs - 1 DO
  { ensure_sidedef_tex(sd, SIDEDEF_UPPER_OFS)
    ensure_sidedef_tex(sd, SIDEDEF_LOWER_OFS)
    ensure_sidedef_tex(sd, SIDEDEF_MIDDLE_OFS)
  }
  writef("composited %n unique textures*n", tex_count)
}

// ---------- camera ----------

LET cam_x(wx, wy) = VALOF
{ LET rx = wx - px
  LET ry = wy - py
  RESULTIS (rx * sin_t!(pa & (ANG-1)) - ry * cos_t!(pa & (ANG-1))) / 1024
}

LET cam_y(wx, wy) = VALOF
{ LET rx = wx - px
  LET ry = wy - py
  RESULTIS (rx * cos_t!(pa & (ANG-1)) + ry * sin_t!(pa & (ANG-1))) / 1024
}

LET front_facing(v1x, v1y, v2x, v2y) = VALOF
{ LET dx = v2x - v1x
  LET dy = v2y - v1y
  RESULTIS (px - v1x) * dy - (py - v1y) * dx > 0
}

LET light_to_col(light) = VALOF
{ LET v = light
  IF v < 40 DO v := 40
  IF v > 255 DO v := 255
  RESULTIS sys(Sys_sdl, sdl_maprgb, 0, v, v, v)
}

// Combine sector light with distance fade. Result is 0..255 suitable
// for Sys_setlight; higher cy → darker.
LET light_at_depth(sector_light, cy) = VALOF
{ LET fade = cy / LIGHT_DROP
  LET l    = sector_light - fade
  IF l < LIGHT_FADE_MIN DO l := LIGHT_FADE_MIN
  IF l > 255 DO l := 255
  RESULTIS l
}

LET reset_clip() BE
{ FOR i = 0 TO W - 1 DO { col_top!i := 0; col_bot!i := H - 1 }
  cols_open := W
}

LET close_column(col) BE
{ IF col_top!col <= col_bot!col DO cols_open := cols_open - 1
  col_top!col := H
  col_bot!col := -1
}

LET vline_clipped(col, y0, y1, c) BE
{ LET t = col_top!col
  LET b = col_bot!col
  IF y0 > y1 DO { LET tmp = y0; y0 := y1; y1 := tmp }
  IF y0 < t DO y0 := t
  IF y1 > b DO y1 := b
  IF y0 <= y1 DO
    sys(Sys_sdl, sdl_drawvline, surf, col, y0, y1, c)
}

LET project_y(world_z, cy) =
  HORIZON - ((world_z - cam_z) * F_X) / cy

LET draw_textured_band(col_x, clip_top, clip_bot, y_anchor, cy,
                       texU, cidx, flat_c) BE
{ TEST cidx < 0
  THEN vline_clipped(col_x, clip_top, clip_bot, flat_c)
  ELSE { LET tw = tex_w_vec!cidx
         LET th = tex_h_vec!cidx
         LET tb = tex_base!cidx
         LET v_step_q16 = (cy * 65536) / F_X
         LET texX = ((texU REM tw) + tw) REM tw
         LET pkd  = (tw & #xFFFF) | (th << 16)
         LET y0 = clip_top
         LET y1 = clip_bot
         IF y0 < col_top!col_x DO y0 := col_top!col_x
         IF y1 > col_bot!col_x DO y1 := col_bot!col_x
         IF y0 <= y1 DO
           sys(Sys_drawwallcol, col_x, y0, y1, y_anchor, v_step_q16,
               texX, tb, pkd)
       }
}

// Same as draw_textured_band but signals transparency to the runtime
// by negating v_step_q16. Used for portal mid-textures so word == 0
// pixels skip the fb write (alpha-test).  Doesn't fall back to flat
// (no flat colour makes sense for a transparent mid-tex).
LET draw_textured_band_trans(col_x, clip_top, clip_bot, y_anchor, cy,
                             texU, cidx) BE
{ LET tw, th, tb = 0, 0, 0
  LET v_step_q16 = 0
  LET texX = 0
  LET pkd  = 0
  LET y0 = clip_top
  LET y1 = clip_bot
  IF cidx < 0 RETURN
  tw := tex_w_vec!cidx
  th := tex_h_vec!cidx
  tb := tex_base!cidx
  v_step_q16 := (cy * 65536) / F_X
  texX := ((texU REM tw) + tw) REM tw
  pkd  := (tw & #xFFFF) | (th << 16)
  IF y0 < col_top!col_x DO y0 := col_top!col_x
  IF y1 > col_bot!col_x DO y1 := col_bot!col_x
  IF y0 <= y1 DO
    sys(Sys_drawwallcol, col_x, y0, y1, y_anchor, 0 - v_step_q16,
        texX, tb, pkd)
}

// ---------- seg + BSP rendering ----------

LET render_seg(seg_byte) BE
{ LET v1, v2 = 0, 0
  LET ld_idx, seg_side, seg_offset = 0, 0, 0
  LET le, front_sd, back_sd, ld_flags = 0, 0, 0, 0
  LET front_sec, back_sec = 0, 0
  LET v1x, v1y, v2x, v2y = 0, 0, 0, 0
  LET cx1, cy1, cx2, cy2 = 0, 0, 0, 0
  LET ff, fc, fl, bf, bc = 0, 0, 0, 0, 0
  LET two_sided = FALSE
  LET sx1, sx2, ix1, ix2 = 0, 0, 0, 0
  LET inv_z1, inv_z2, dx_span = 0, 0, 0
  LET wall_c, lower_c, upper_c = 0, 0, 0
  LET wall_len = 0
  LET u_left, u_right = 0, 0
  LET u_iz_left, u_iz_right, u_iz_step = 0, 0, 0
  LET tex_off, tex_off_y = 0, 0
  LET mid_cidx, low_cidx, up_cidx = -1, -1, -1
  LET floor_flat_base, ceil_flat_base = 0, 0
  LET peg_top, peg_bot = FALSE, FALSE

  v1         := rd_u16_le(g_base, seg_byte + SEG_V1_OFS)
  v2         := rd_u16_le(g_base, seg_byte + SEG_V2_OFS)
  ld_idx     := rd_u16_le(g_base, seg_byte + SEG_LINE_OFS)
  seg_side   := rd_u16_le(g_base, seg_byte + SEG_SIDE_OFS)
  seg_offset := rd_i16_le(g_base, seg_byte + SEG_OFFSET_OFS)
  le         := g_line_byte + ld_idx * LINEDEF_SIZE
  ld_flags   := rd_u16_le(g_base, le + LINEDEF_FLAGS_OFS)
  peg_top    := (ld_flags & ML_DONTPEGTOP)    ~= 0
  peg_bot    := (ld_flags & ML_DONTPEGBOTTOM) ~= 0
  TEST seg_side = 0
  THEN { front_sd := rd_i16_le(g_base, le + LINEDEF_FRONT_OFS)
         back_sd  := rd_i16_le(g_base, le + LINEDEF_BACK_OFS) }
  ELSE { front_sd := rd_i16_le(g_base, le + LINEDEF_BACK_OFS)
         back_sd  := rd_i16_le(g_base, le + LINEDEF_FRONT_OFS) }
  IF front_sd < 0 RETURN

  front_sec := sd_sector(front_sd)
  IF front_sec < 0 RETURN
  ff := sec_floor(front_sec)
  fc := sec_ceil(front_sec)
  fl := sec_light(front_sec)
  tex_off   := sd_texoffx(front_sd) + seg_offset
  tex_off_y := sd_texoffy(front_sd)

  two_sided := back_sd >= 0
  IF two_sided DO
  { back_sec := sd_sector(back_sd)
    IF back_sec < 0 DO two_sided := FALSE
    IF two_sided DO
    { bf := sec_floor(back_sec)
      bc := sec_ceil(back_sec)
    }
  }

  { LET vo1 = g_vert_byte + v1 * VERTEX_SIZE
    LET vo2 = g_vert_byte + v2 * VERTEX_SIZE
    v1x := rd_i16_le(g_base, vo1 + 0)
    v1y := rd_i16_le(g_base, vo1 + 2)
    v2x := rd_i16_le(g_base, vo2 + 0)
    v2y := rd_i16_le(g_base, vo2 + 2)
  }

  UNLESS two_sided DO
    UNLESS front_facing(v1x, v1y, v2x, v2y) RETURN

  // World wall length, for U computation.
  { LET dxw = v2x - v1x
    LET dyw = v2y - v1y
    wall_len := isqrt(dxw * dxw + dyw * dyw)
  }
  u_left  := 0
  u_right := wall_len

  cx1 := cam_x(v1x, v1y); cy1 := cam_y(v1x, v1y)
  cx2 := cam_x(v2x, v2y); cy2 := cam_y(v2x, v2y)
  IF cy1 < NEAR & cy2 < NEAR RETURN

  IF cy1 < NEAR DO
  { LET t1024 = ((NEAR - cy1) * 1024) / (cy2 - cy1)
    cx1     := cx1     + ((cx2 - cx1)         * t1024) / 1024
    u_left  := u_left  + ((u_right - u_left)  * t1024) / 1024
    cy1     := NEAR
  }
  IF cy2 < NEAR DO
  { LET t1024 = ((NEAR - cy2) * 1024) / (cy1 - cy2)
    cx2     := cx2     + ((cx1 - cx2)         * t1024) / 1024
    u_right := u_right + ((u_left - u_right)  * t1024) / 1024
    cy2     := NEAR
  }

  sx1 := W/2 + (cx1 * F_X) / cy1
  sx2 := W/2 + (cx2 * F_X) / cy2

  IF sx1 > sx2 DO
  { LET tmp = sx1; sx1 := sx2; sx2 := tmp
    tmp := cx1; cx1 := cx2; cx2 := tmp
    tmp := cy1; cy1 := cy2; cy2 := tmp
    tmp := u_left; u_left := u_right; u_right := tmp
  }
  IF sx1 = sx2 RETURN

  ix1 := sx1; ix2 := sx2
  IF ix1 < 0 DO ix1 := 0
  IF ix2 >= W DO ix2 := W - 1
  IF ix1 > ix2 RETURN

  inv_z1 := (1024 * 1024) / cy1
  inv_z2 := (1024 * 1024) / cy2
  dx_span := sx2 - sx1

  // Precompute u*inv_z at each endpoint.  These can be large (up to
  // wall_len * inv_z2 ~ 3000 * 262144 ~ 8e8), so divide by dx_span
  // before multiplying by per-column offset to keep things in int32.
  u_iz_left  := u_left  * inv_z1
  u_iz_right := u_right * inv_z2
  u_iz_step  := (u_iz_right - u_iz_left) / dx_span

  wall_c  := light_to_col(fl)
  lower_c := light_to_col(fl - 16)
  upper_c := light_to_col(fl - 32)

  mid_cidx := ensure_sidedef_tex(front_sd, SIDEDEF_MIDDLE_OFS)
  low_cidx := ensure_sidedef_tex(front_sd, SIDEDEF_LOWER_OFS)
  up_cidx  := ensure_sidedef_tex(front_sd, SIDEDEF_UPPER_OFS)
  // Front sector's floor / ceiling flats (one per seg — same for the
  // whole span). Cache idx, or -1 if F_SKY1 / missing.
  { LET fl_idx = ensure_flat(g_base, sec_floortex_byte(front_sec))
    LET cl_idx = ensure_flat(g_base, sec_ceiltex_byte(front_sec))
    floor_flat_base := fl_idx >= 0 -> flat_base!fl_idx, 0
    ceil_flat_base  := cl_idx >= 0 -> flat_base!cl_idx, 0
  }

  FOR col_x = ix1 TO ix2 DO
  { LET t     = ((col_x - sx1) * 1024) / dx_span
    LET inv_z = inv_z1 + ((inv_z2 - inv_z1) * t) / 1024
    LET cy    = 0
    LET y_fc, y_cc, y_bf, y_bc = 0, 0, 0, 0
    LET u_iz_col, u_world, texU = 0, 0, 0
    IF inv_z <= 0 LOOP
    cy := (1024 * 1024) / inv_z

    y_fc := project_y(fc, cy)
    y_cc := project_y(ff, cy)

    // Per-column ray direction (1024-scaled).  Used by flat sampling.
    { LET offset  = col_x - W/2
      LET ray_dx  = fwd_x + (offset * right_x) / F_X
      LET ray_dy  = fwd_y + (offset * right_y) / F_X
      LET raydxy  = (ray_dx & #xFFFF) | ((ray_dy & #xFFFF) << 16)
      LET col_lt  = light_at_depth(fl, cy)
      sys(Sys_setlight, col_lt)

      // Ceiling band (above front ceil) — flat tex, or sky cylinder
      // if the sector's ceiling is F_SKY1.
      { LET top = col_top!col_x
        LET bot = col_bot!col_x
        IF top < y_fc DO
        { LET y1 = y_fc - 1
          LET use_sky = sky_loaded & sector_ceil_is_sky(front_sec)
          IF y1 > bot DO y1 := bot
          IF top <= y1 DO
          { TEST use_sky
            THEN { LET u = ((pa * sky_w) / (ANG / 4) + (col_x * sky_w) / W) REM sky_w
                   IF u < 0 DO u := u + sky_w
                   sys(Sys_setlight, 255)
                   sys(Sys_drawskyspan, col_x, top, y1, u)
                 }
            ELSE TEST ceil_flat_base ~= 0
                 THEN sys(Sys_drawflatspan, col_x, top, y1,
                          cam_z - fc, px, py, raydxy, ceil_flat_base)
                 ELSE sys(Sys_sdl, sdl_drawvline, surf, col_x, top, y1, sky_col)
          }
          col_top!col_x := y_fc
        }
      }
      // Floor band (below front floor) — flat texture if available.
      { LET top = col_top!col_x
        LET bot = col_bot!col_x
        IF bot > y_cc DO
        { LET y0 = y_cc + 1
          IF y0 < top DO y0 := top
          IF y0 <= bot DO
            TEST floor_flat_base ~= 0
            THEN sys(Sys_drawflatspan, col_x, y0, bot,
                     cam_z - ff, px, py, raydxy, floor_flat_base)
            ELSE sys(Sys_sdl, sdl_drawvline, surf, col_x, y0, bot, floor_col)
          col_bot!col_x := y_cc
        }
      }
    }
    IF col_top!col_x > col_bot!col_x DO { close_column(col_x); LOOP }

    // Track per-column nearest wall depth for sprite occlusion.
    IF cy < col_z!col_x DO col_z!col_x := cy

    // Perspective-correct U for this column.
    u_iz_col := u_iz_left + u_iz_step * (col_x - sx1)
    u_world  := u_iz_col / inv_z
    texU     := u_world + tex_off

    TEST two_sided
    THEN { LET y_anchor_up   = 0
           LET y_anchor_low  = 0
           LET y_anchor_mid  = 0
           LET up_tex_h, low_tex_h, mid_tex_h = 0, 0, 0
           y_bc := project_y(bc, cy)
           y_bf := project_y(bf, cy)
           IF up_cidx >= 0 DO up_tex_h := tex_h_vec!up_cidx
           IF low_cidx >= 0 DO low_tex_h := tex_h_vec!low_cidx
           IF mid_cidx >= 0 DO mid_tex_h := tex_h_vec!mid_cidx
           // Upper step: default anchors at back_ceil + tex_h
           // (texture sits with its bottom row on back_ceil).
           // ML_DONTPEGTOP overrides to anchor at front_ceil.
           TEST peg_top
           THEN y_anchor_up := project_y(fc - tex_off_y, cy)
           ELSE y_anchor_up := project_y(bc + up_tex_h - tex_off_y, cy)
           // Lower step: default anchors at front_ceil. ML_DONTPEGBOTTOM
           // moves anchor down to back_floor + tex_h so the texture's
           // BOTTOM row sits on back_floor.
           TEST peg_bot
           THEN y_anchor_low := project_y(bf + low_tex_h - tex_off_y, cy)
           ELSE y_anchor_low := project_y(fc - tex_off_y, cy)
           // Portal mid-tex: default anchor = back_ceil; ML_DONTPEGBOTTOM
           // anchors so bottom row sits on back_floor.
           TEST peg_bot
           THEN y_anchor_mid := project_y(bf + mid_tex_h - tex_off_y, cy)
           ELSE y_anchor_mid := project_y(bc - tex_off_y, cy)

           IF bc < fc DO
           { draw_textured_band(col_x, y_fc, y_bc, y_anchor_up, cy,
                                texU, up_cidx, upper_c)
             IF y_bc + 1 > col_top!col_x DO col_top!col_x := y_bc + 1
             IF col_top!col_x > col_bot!col_x DO close_column(col_x)
           }
           IF bf > ff DO
           { draw_textured_band(col_x, y_bf, y_cc, y_anchor_low, cy,
                                texU, low_cidx, lower_c)
             IF y_bf - 1 < col_bot!col_x DO col_bot!col_x := y_bf - 1
             IF col_top!col_x > col_bot!col_x DO close_column(col_x)
           }
           // Portal mid-texture (railing / fence). Drawn with alpha
           // transparency; clipped to the current open band and to
           // the mid-tex's projected band. Doesn't close the column.
           IF mid_cidx >= 0 DO
           { LET m_top_z = 0
             LET m_bot_z = 0
             LET y_m_top = 0
             LET y_m_bot = 0
             LET clip_t  = col_top!col_x
             LET clip_b  = col_bot!col_x
             TEST peg_bot
             THEN m_top_z := bf + mid_tex_h - tex_off_y
             ELSE m_top_z := bc - tex_off_y
             m_bot_z := m_top_z - mid_tex_h
             y_m_top := project_y(m_top_z, cy)
             y_m_bot := project_y(m_bot_z, cy)
             IF y_m_top > clip_t DO clip_t := y_m_top
             IF y_m_bot < clip_b DO clip_b := y_m_bot
             IF clip_t <= clip_b DO
               draw_textured_band_trans(col_x, clip_t, clip_b,
                                        y_anchor_mid, cy, texU, mid_cidx)
           }
         }
    ELSE { // Solid wall (1-sided).  Default anchor = front_ceil.
           // ML_DONTPEGBOTTOM anchors at front_floor + tex_h so the
           // tex bottom row sits on the floor.
           LET sw_tex_h = 0
           LET y_anchor_solid = 0
           IF mid_cidx >= 0 DO sw_tex_h := tex_h_vec!mid_cidx
           TEST peg_bot
           THEN y_anchor_solid := project_y(ff + sw_tex_h - tex_off_y, cy)
           ELSE y_anchor_solid := project_y(fc - tex_off_y, cy)
           draw_textured_band(col_x, y_fc, y_cc, y_anchor_solid, cy,
                              texU, mid_cidx, wall_c)
           close_column(col_x)
         }
  }
}

LET render_subsector(ssidx) BE
{ LET se = g_ssec_byte + ssidx * SSECTOR_SIZE
  LET nsegs = rd_u16_le(g_base, se + SSECTOR_NUMSEG_OFS)
  LET first = rd_u16_le(g_base, se + SSECTOR_FIRST_OFS)
  FOR i = 0 TO nsegs - 1 DO
  { IF cols_open <= 0 RETURN
    render_seg(g_seg_byte + (first + i) * SEG_SIZE)
  }
}

LET render_node(node_idx) BE
{ IF cols_open <= 0 RETURN
  IF (node_idx & SUBSECTOR_BIT) ~= 0 DO
  { render_subsector(node_idx & ~SUBSECTOR_BIT)
    RETURN
  }
  { LET no = g_node_byte + node_idx * NODE_SIZE
    LET side = point_on_side(px, py, no)
    LET rc = rd_u16_le(g_base, no + NODE_RC_OFS)
    LET lc = rd_u16_le(g_base, no + NODE_LC_OFS)
    TEST side = 0
    THEN { render_node(rc); render_node(lc) }
    ELSE { render_node(lc); render_node(rc) }
  }
}

LET fill_remaining() BE
{ FOR col_x = 0 TO W - 1 DO
  { LET t = col_top!col_x
    LET b = col_bot!col_x
    IF t > b LOOP
    IF t < HORIZON DO
    { LET y1 = b
      IF y1 >= HORIZON DO y1 := HORIZON - 1
      TEST sky_loaded
      THEN { LET u = ((pa * sky_w) / (ANG / 4) + (col_x * sky_w) / W) REM sky_w
             IF u < 0 DO u := u + sky_w
             sys(Sys_setlight, 255)
             sys(Sys_drawskyspan, col_x, t, y1, u)
           }
      ELSE sys(Sys_sdl, sdl_drawvline, surf, col_x, t, y1, sky_col)
    }
    IF b >= HORIZON DO
    { LET y0 = t
      IF y0 < HORIZON DO y0 := HORIZON
      sys(Sys_sdl, sdl_drawvline, surf, col_x, y0, b, floor_col)
    }
  }
}

// Render a single sprite at world (wx, wy), bottom at world z = wz,
// using sprite cache entry `cidx`. Honors per-column z-buffer for
// wall occlusion. Skips silently if behind the camera.
LET draw_sprite(wx, wy, wz, cidx) BE
{ LET rx, ry = 0, 0
  LET cax, cay = 0, 0
  LET pw, ph, lo, to = 0, 0, 0, 0
  LET tb = 0
  LET scale_q10 = 0          // 1024 * (F_X / cay)
  LET sw, sh = 0, 0          // screen width / height
  LET sx_center, sx_left, sx_right = 0, 0, 0
  LET top_z, bot_z = 0, 0
  LET y_top, y_bot = 0, 0
  LET v_step_q16 = 0
  LET pkd = 0

  IF cidx < 0 RETURN
  rx := wx - px;  ry := wy - py
  cax := (rx * sin_t!(pa & (ANG-1)) - ry * cos_t!(pa & (ANG-1))) / 1024
  cay := (rx * cos_t!(pa & (ANG-1)) + ry * sin_t!(pa & (ANG-1))) / 1024
  IF cay < NEAR RETURN

  pw := spr_w!cidx;  ph := spr_h!cidx
  lo := spr_lofs!cidx;  to := spr_tofs!cidx
  tb := spr_base!cidx

  // 1024-scaled scale factor.
  scale_q10 := (F_X * 1024) / cay
  sw := (pw * scale_q10) / 1024
  sh := (ph * scale_q10) / 1024
  IF sw <= 0 | sh <= 0 RETURN

  sx_center := W/2 + (cax * F_X) / cay
  // leftofs measured from left edge to origin; sprite's left in
  // screen space = center - leftofs * scale.
  sx_left  := sx_center - (lo * scale_q10) / 1024
  sx_right := sx_left + sw - 1
  IF sx_right < 0 | sx_left >= W RETURN

  // World z: bottom at wz, top at wz + ph (in world units).
  // topofs typically equals ph for floor-anchored sprites; this
  // simple placement puts the patch's bottom at wz.
  bot_z := wz
  top_z := wz + ph
  y_top := project_y(top_z, cay)
  y_bot := project_y(bot_z, cay)
  // Note: sh should match (y_bot - y_top) up to rounding; recompute
  // for V mapping.
  IF y_bot <= y_top RETURN

  // V step over the span. drawwallcol's V = (y - anchor) * v_step >> 16.
  // anchor = y_top so V(y_top) = 0, V(y_bot) = ph - 1.
  v_step_q16 := ((ph - 1) * 65536) / (y_bot - y_top)
  pkd := (pw & #xFFFF) | (ph << 16)

  // Sprites use full brightness for now (no fade).
  sys(Sys_setlight, 255)

  // Iterate visible columns.
  { LET cx0 = sx_left
    LET cx1 = sx_right
    IF cx0 < 0 DO cx0 := 0
    IF cx1 >= W DO cx1 := W - 1
    FOR sx = cx0 TO cx1 DO
    { LET texX = ((sx - sx_left) * pw) / sw
      IF texX < 0 LOOP
      IF texX >= pw LOOP
      IF cay >= col_z!sx LOOP    // occluded by a closer wall
      // Negate v_step → drawwallcol skips transparent pixels.
      sys(Sys_drawwallcol, sx, y_top, y_bot, y_top, 0 - v_step_q16,
          texX, tb, pkd)
    }
  }
}

LET draw_sprites() BE
{ LET n = g_tsize / THING_SIZE
  LET name_buf = 0
  LET cidx = 0
  LET wz = 0
  FOR i = 0 TO n - 1 DO
  { LET o    = g_things_byte + i * THING_SIZE
    LET wx  = rd_i16_le(g_base, o + THING_X_OFS)
    LET wy  = rd_i16_le(g_base, o + THING_Y_OFS)
    LET tp  = rd_u16_le(g_base, o + THING_TYPE_OFS)
    name_buf := thing_sprite_name(tp)
    IF name_buf = 0 LOOP
    cidx := ensure_sprite(name_buf)
    IF cidx < 0 LOOP
    wz := floor_at(wx, wy)
    draw_sprite(wx, wy, wz, cidx)
  }
}

LET drawframe() BE
{ reset_clip()
  // Reset per-column z-buffer.
  FOR i = 0 TO W - 1 DO col_z!i := Z_INF
  cam_z := floor_at(px, py) + EYE_H
  fwd_x   := cos_t!(pa & (ANG - 1))
  fwd_y   := sin_t!(pa & (ANG - 1))
  right_x := fwd_y
  right_y := 0 - fwd_x
  render_node(g_root_node)
  fill_remaining()
  draw_sprites()
  sys(Sys_sdl, sdl_flip, surf)
}

// ---------- main ----------

LET start() = VALOF
{ LET info = VEC 3
  LET nbytes = 0
  LET map_idx = 0
  LET vert_idx, line_idx, side_idx, sec_idx = 0, 0, 0, 0
  LET node_idx, ssec_idx, seg_idx, thing_idx = 0, 0, 0, 0
  LET playpal_idx, pnames_idx, tex1_idx = 0, 0, 0
  LET things_byte, tsize = 0, 0
  LET lsize, side_sz, num_sides = 0, 0, 0
  LET playpal_byte, pnames_byte = 0, 0

  UNLESS try_load_wad(info) DO
  { writef("No WAD asset uploaded.*n")
    RESULTIS 1
  }
  nbytes := info!0
  IF info!1 ~= 0 DO { writef("Asset is an image.*n"); RESULTIS 1 }
  g_base := info!2

  g_numlumps := rd_u32_le(g_base, HDR_NUMLUMPS_OFS)
  g_dirofs   := rd_u32_le(g_base, HDR_INFOOFS_OFS)

  map_idx := find_first_map(g_base, g_dirofs, g_numlumps)
  IF map_idx < 0 DO { writef("No map marker.*n"); RESULTIS 1 }
  writef("map: "); pr_lump_name(g_base, g_dirofs + map_idx * DIR_ENTRY_SIZE); newline()

  vert_idx  := find_map_lump(g_base, g_dirofs, map_idx, g_numlumps, "VERTEXES")
  line_idx  := find_map_lump(g_base, g_dirofs, map_idx, g_numlumps, "LINEDEFS")
  side_idx  := find_map_lump(g_base, g_dirofs, map_idx, g_numlumps, "SIDEDEFS")
  sec_idx   := find_map_lump(g_base, g_dirofs, map_idx, g_numlumps, "SECTORS")
  node_idx  := find_map_lump(g_base, g_dirofs, map_idx, g_numlumps, "NODES")
  ssec_idx  := find_map_lump(g_base, g_dirofs, map_idx, g_numlumps, "SSECTORS")
  seg_idx   := find_map_lump(g_base, g_dirofs, map_idx, g_numlumps, "SEGS")
  thing_idx := find_map_lump(g_base, g_dirofs, map_idx, g_numlumps, "THINGS")
  IF vert_idx<0 | line_idx<0 | side_idx<0 | sec_idx<0 |
     node_idx<0 | ssec_idx<0 | seg_idx<0 | thing_idx<0 DO
  { writef("Missing map lump.*n"); RESULTIS 1 }

  g_vert_byte := rd_u32_le(g_base, g_dirofs + vert_idx * DIR_ENTRY_SIZE + DIR_FILEPOS_OFS)
  g_line_byte := rd_u32_le(g_base, g_dirofs + line_idx * DIR_ENTRY_SIZE + DIR_FILEPOS_OFS)
  { LET ln_sz = rd_u32_le(g_base, g_dirofs + line_idx * DIR_ENTRY_SIZE + DIR_SIZE_OFS)
    g_nlines := ln_sz / LINEDEF_SIZE
  }
  g_side_byte := rd_u32_le(g_base, g_dirofs + side_idx * DIR_ENTRY_SIZE + DIR_FILEPOS_OFS)
  side_sz     := rd_u32_le(g_base, g_dirofs + side_idx * DIR_ENTRY_SIZE + DIR_SIZE_OFS)
  num_sides   := side_sz / SIDEDEF_SIZE
  g_sec_byte  := rd_u32_le(g_base, g_dirofs + sec_idx  * DIR_ENTRY_SIZE + DIR_FILEPOS_OFS)
  g_node_byte := rd_u32_le(g_base, g_dirofs + node_idx * DIR_ENTRY_SIZE + DIR_FILEPOS_OFS)
  g_ssec_byte := rd_u32_le(g_base, g_dirofs + ssec_idx * DIR_ENTRY_SIZE + DIR_FILEPOS_OFS)
  g_seg_byte  := rd_u32_le(g_base, g_dirofs + seg_idx  * DIR_ENTRY_SIZE + DIR_FILEPOS_OFS)
  things_byte := rd_u32_le(g_base, g_dirofs + thing_idx * DIR_ENTRY_SIZE + DIR_FILEPOS_OFS)
  tsize       := rd_u32_le(g_base, g_dirofs + thing_idx * DIR_ENTRY_SIZE + DIR_SIZE_OFS)
  g_things_byte := things_byte
  g_tsize       := tsize
  g_root_node := (rd_u32_le(g_base, g_dirofs + node_idx * DIR_ENTRY_SIZE + DIR_SIZE_OFS) / NODE_SIZE) - 1

  // Texture pipeline lumps.
  playpal_idx := find_lump_global(g_base, 0) // dummy
  // Use lump_name_eq for these (allow short names).
  FOR i = 0 TO g_numlumps - 1 DO
  { LET e = g_dirofs + i * DIR_ENTRY_SIZE
    IF lump_name_eq(g_base, e, "PLAYPAL") DO playpal_idx := i
    IF lump_name_eq(g_base, e, "PNAMES")  DO pnames_idx  := i
    IF lump_name_eq(g_base, e, "TEXTURE1") DO tex1_idx   := i
  }
  IF playpal_idx < 0 | pnames_idx = 0 | tex1_idx = 0 DO
  { writef("Missing PLAYPAL / PNAMES / TEXTURE1.*n"); RESULTIS 1 }

  playpal_byte := rd_u32_le(g_base, g_dirofs + playpal_idx * DIR_ENTRY_SIZE + DIR_FILEPOS_OFS)
  pnames_byte  := rd_u32_le(g_base, g_dirofs + pnames_idx  * DIR_ENTRY_SIZE + DIR_FILEPOS_OFS)
  g_tex1       := rd_u32_le(g_base, g_dirofs + tex1_idx    * DIR_ENTRY_SIZE + DIR_FILEPOS_OFS)
  g_npnames    := rd_u32_le(g_base, pnames_byte + 0)
  g_pnames     := pnames_byte + 4
  g_ntex1      := rd_u32_le(g_base, g_tex1 + 0)
  writef("PLAYPAL @%n  PNAMES @%n (%n)  TEXTURE1 @%n (%n)*n",
         playpal_byte, pnames_byte, g_npnames, g_tex1, g_ntex1)

  g_pal     := getvec(256)
  tex_name  := getvec(MAX_TEX * 2)
  tex_base  := getvec(MAX_TEX)
  tex_w_vec := getvec(MAX_TEX)
  tex_h_vec := getvec(MAX_TEX)
  flat_name := getvec(MAX_FLATS * 2)
  flat_base := getvec(MAX_FLATS)
  spr_name  := getvec(MAX_SPRITES * 2)
  spr_base  := getvec(MAX_SPRITES)
  spr_w     := getvec(MAX_SPRITES)
  spr_h     := getvec(MAX_SPRITES)
  spr_lofs  := getvec(MAX_SPRITES)
  spr_tofs  := getvec(MAX_SPRITES)
  col_z     := getvec(W)

  load_palette(playpal_byte)

  sin_t := getvec(ANG)
  cos_t := getvec(ANG)
  buildtrig()

  col_top := getvec(W)
  col_bot := getvec(W)

  UNLESS find_player_start(g_base, things_byte, tsize) DO
  { writef("No player1 start.*n"); px := 0; py := 0; pa := 0 }
  writef("player start  px=%n py=%n pa=%n*n", px, py, pa)

  prebuild_textures(num_sides)
  // Composite SKY1 like any wall texture; register as bg slot 0 so
  // Sys_drawskyspan finds it.  Falls back gracefully if missing.
  { LET sky_name = VEC 2
    LET sky_cidx = 0
    FOR i = 0 TO 7 DO sky_name % i := 0
    sky_name % 0 := 'S'
    sky_name % 1 := 'K'
    sky_name % 2 := 'Y'
    sky_name % 3 := '1'
    sky_cidx := composite_texture(sky_name, 0)
    IF sky_cidx >= 0 DO
    { sky_loaded := TRUE
      sky_w     := tex_w_vec!sky_cidx
      sky_h     := tex_h_vec!sky_cidx
      sky_base  := tex_base!sky_cidx
      sys(Sys_setbgtex, 0, sky_base, sky_w, sky_h)
      writef("sky:    %nx%n at base %n*n", sky_w, sky_h, sky_base)
    }
  }
  { LET sec_sz = rd_u32_le(g_base, g_dirofs + sec_idx * DIR_ENTRY_SIZE + DIR_SIZE_OFS)
    LET num_sectors = sec_sz / SECTOR_SIZE
    prebuild_flats(num_sectors)
  }

  sys(Sys_sdl, sdl_init)
  surf := sys(Sys_sdl, sdl_setvideomode, W, H, 0, 0)

  sky_col   := sys(Sys_sdl, sdl_maprgb, 0,  60, 110, 180)
  floor_col := sys(Sys_sdl, sdl_maprgb, 0,  40,  40,  40)

  keys := getvec(KEYCAP)
  FOR i = 0 TO KEYCAP DO keys!i := 0

  WHILE running DO
  { LET fwd  = 0
    LET turn = 0
    poll_events()
    IF key_down(K_W) | key_down(K_UP)    DO fwd  := fwd  + 1
    IF key_down(K_S) | key_down(K_DOWN)  DO fwd  := fwd  - 1
    IF key_down(K_A) | key_down(K_LEFT)  DO turn := turn - TURN
    IF key_down(K_D) | key_down(K_RIGHT) DO turn := turn + TURN

    IF fwd ~= 0 DO
    { LET dx = (cos_t!(pa & (ANG-1)) * MOVE * fwd) / 1024
      LET dy = (sin_t!(pa & (ANG-1)) * MOVE * fwd) / 1024
      try_move(dx, dy)
    }
    IF turn ~= 0 DO pa := (pa + turn) & (ANG - 1)

    drawframe()
    delay(16)
  }

  freevec(sin_t); freevec(cos_t); freevec(keys)
  freevec(col_top); freevec(col_bot)
  writef("dwlt exited*n")
  RESULTIS 0
}
