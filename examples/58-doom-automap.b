// 58-doom-automap: 57 + classic Doom automap overlay.
//
// What's new vs 57:
//   - Press M to toggle a 2D top-down overlay of the map.
//   - +/- (or PgUp/PgDn) zoom in/out.
//   - Centred on the player; linedefs drawn via Bresenham fb-line
//     (runtime now routes sdl_drawline through the backbuffer too).
//   - Player drawn as a small triangle pointing along facing.
//   - 1-sided walls bright, 2-sided portals dimmer.
//
// Controls: WASD/arrows = move/turn, E or Space = use, F or LCtrl =
//           fire, M = automap, +/- = zoom, Esc = quit.

SECTION "dmap2"

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
  LINEDEF_FLAGS_OFS    =  4
  LINEDEF_SPECIAL_OFS  =  6
  LINEDEF_FRONT_OFS    = 10
  LINEDEF_BACK_OFS     = 12

  USE_RANGE = 64                  // Doom's use distance
  DOOR_SPEED = 4                  // ceiling rises this many units/frame
  DOOR_GAP   = 4                  // final gap below neighbour ceiling

  ANIM_TICKS = 14                 // frames per monster anim step

  WEAPON_SCALE = 3                // 1=native, 2=2x pixels, etc.
  WEAPON_FIRE_TICKS = 4           // frames per fire-cycle step

  HUD_SCALE = 3                   // STBAR native is 320×32; 3× = 960×96

  // STBAR-relative element positions, in native Doom pixels.  Multiply
  // by HUD_SCALE for screen coords.  STBAR top-left maps to (0, H - hud_bar_h).
  ST_AMMOX  = 44
  ST_AMMOY  = 3
  ST_HEALTHX = 90
  ST_HEALTHY = 3
  ST_ARMORX  = 221
  ST_ARMORY  = 3
  ST_FX      = 143
  ST_FY      = 0

  FACE_TICKS = 18                 // frames between idle face cycle steps

  FAKECONTRAST = 16               // Doom's wall-orientation light bias
  SECTOR_SPEC_OFS = 22            // i16 special at byte 22

  STROBE_BRIGHT = 5               // bright duration ticks
  STROBE_DARK_F = 15              // fast strobe dark duration
  STROBE_DARK_S = 35              // slow strobe dark duration
  GLOW_STEP     = 8               // light units per frame in glow
  FLICKER_RAND_MAX = 7            // bigger = rarer flickers

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

  MAX_SPRITES     = 128
  MAX_VIS_SPRITES = 128            // visible per frame
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
  K_E      = 69
  K_SPACE  = 32
  K_F      = 70
  K_LCTRL  = 17
  K_M      = 77
  K_PLUS   = 187    // browser keyCode for '='/'+'
  K_MINUS  = 189    // browser keyCode for '-'/'_'
  K_PGUP   = 33
  K_PGDN   = 34
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
  // Snapshot of (col_top, col_bot) at the moment the column closed.
  // Sprite clipping uses these so sprites visible above/below a
  // closing wall don't paint into the neighbouring sky/floor.
  saved_top = 0
  saved_bot = 0

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

  // Visible-sprite list (per frame).
  vs_count = 0
  vs_x     = 0
  vs_y     = 0
  vs_z     = 0
  vs_cy    = 0
  vs_cidx  = 0

  // Door / dynamic ceiling state.
  num_sectors      = 0
  ceil_h_runtime   = 0   // VEC num_sectors — current ceil per sector
  door_state       = 0   // 0=idle, 1=opening
  door_target      = 0
  use_prev         = 0   // edge-detect for Use key
  g_frame_count    = 0

  // Weapon HUD state.
  wep_cidx_a = -1
  wep_cidx_b = -1
  wep_cidx_c = -1
  wep_cidx_d = -1
  wep_fire_timer = 0    // counts DOWN while firing
  wep_fire_prev  = 0    // edge-detect for fire key
  wep_bob_t      = 0    // walking phase, 0..ANG-1

  // Light animation state.
  sec_light_runtime = 0   // VEC num_sectors — current light per sector
  sec_min_light     = 0   // VEC num_sectors — lowest neighbour light
  sec_special_v     = 0   // VEC num_sectors — cached SECTOR.special
  sec_light_state   = 0   // VEC num_sectors — substate (bright/dark)
  sec_light_timer   = 0   // VEC num_sectors — ticks left in substate
  rand_state        = 1

  hud_cidx     = -1
  hud_bar_h    = 0      // STBAR scaled screen height; weapon anchors above it

  face_cidx    = 0      // VEC 3 — STFST00..02
  digit_cidx   = 0      // VEC 10 — STTNUM0..9

  // Placeholder values (real game state will replace these).
  hud_health = 100
  hud_ammo   = 50
  hud_armor  = 100

  // Automap state.
  automap_on   = FALSE
  automap_scale_q10 = 256   // 1024-scaled "screen px per world unit"; 256 = 0.25
  automap_prev = 0
  am_col_wall  = 0
  am_col_portal = 0
  am_col_player = 0
  am_col_bg    = 0
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

// Static (immutable) ceiling height as recorded in the WAD.
LET sec_ceil_static(idx) =
  rd_i16_le(g_base, g_sec_byte + idx * SECTOR_SIZE + SECTOR_CEIL_OFS)

// Runtime ceiling height; falls back to the WAD value before the
// runtime array is built (during prebuild_textures etc.).
LET sec_ceil(idx) = ceil_h_runtime = 0 -> sec_ceil_static(idx),
                                          ceil_h_runtime!idx

// Static light from WAD.
LET sec_light_static(idx) =
  rd_i16_le(g_base, g_sec_byte + idx * SECTOR_SIZE + SECTOR_LIGHT_OFS)

LET sec_special(idx) =
  rd_i16_le(g_base, g_sec_byte + idx * SECTOR_SIZE + SECTOR_SPEC_OFS)

// Runtime light (animation-aware). Falls back to static before the
// runtime array is allocated.
LET sec_light(idx) = VALOF
{ IF sec_light_runtime = 0 RESULTIS sec_light_static(idx)
  RESULTIS sec_light_runtime!idx
}

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

// ---------- light animation ----------

// xorshift 32-bit PRNG.
LET next_rand() = VALOF
{ LET x = rand_state
  x := x XOR (x << 13)
  x := x XOR ((x >> 17) & #x7FFF)
  x := x XOR (x << 5)
  rand_state := x
  RESULTIS x
}

// Lowest light among sectors connected to `sect` via any linedef.
LET lowest_neighbor_light(sect) = VALOF
{ LET best = sec_light_static(sect)
  LET first = TRUE
  FOR i = 0 TO g_nlines - 1 DO
  { LET le  = g_line_byte + i * LINEDEF_SIZE
    LET front_sd = rd_i16_le(g_base, le + LINEDEF_FRONT_OFS)
    LET back_sd  = rd_i16_le(g_base, le + LINEDEF_BACK_OFS)
    LET front_sec, back_sec, other = 0, 0, -1
    IF front_sd < 0 LOOP
    IF back_sd  < 0 LOOP
    front_sec := sd_sector(front_sd)
    back_sec  := sd_sector(back_sd)
    IF front_sec = sect DO other := back_sec
    IF back_sec  = sect DO other := front_sec
    IF other < 0 LOOP
    { LET l = sec_light_static(other)
      TEST first
      THEN { best := l; first := FALSE }
      ELSE IF l < best DO best := l
    }
  }
  RESULTIS best
}

// Step one sector's light per frame based on its special type.
LET tick_one_light(s) BE
{ LET spec = sec_special_v!s
  LET base = sec_light_static(s)
  LET dark = sec_min_light!s
  LET st = sec_light_state!s
  LET t  = sec_light_timer!s
  SWITCHON spec INTO
  { CASE 1:           // random flicker — usually bright, occasional dip
    CASE 17:
    { IF t > 0 DO { sec_light_timer!s := t - 1; ENDCASE }
      TEST st = 0
      THEN { // bright; maybe go dark
             IF (next_rand() & FLICKER_RAND_MAX) = 0 DO
             { sec_light_state!s := 1
               sec_light_timer!s := 1 + (next_rand() & 7)
               sec_light_runtime!s := dark
               ENDCASE
             }
             sec_light_runtime!s := base
           }
      ELSE { // dark; return to bright
             sec_light_state!s := 0
             sec_light_runtime!s := base
             sec_light_timer!s := 1 + (next_rand() & 31)
           }
      ENDCASE
    }
    CASE 2: CASE 13:    // fast strobe
    CASE 3: CASE 12:    // slow strobe
    { LET dark_dur = (spec = 3 | spec = 12) -> STROBE_DARK_S, STROBE_DARK_F
      IF t > 0 DO { sec_light_timer!s := t - 1; ENDCASE }
      TEST st = 0
      THEN { sec_light_state!s := 1
             sec_light_timer!s := dark_dur
             sec_light_runtime!s := dark
           }
      ELSE { sec_light_state!s := 0
             sec_light_timer!s := STROBE_BRIGHT
             sec_light_runtime!s := base
           }
      ENDCASE
    }
    CASE 8:             // glow — ramp between base and dark
    { LET cur = sec_light_runtime!s
      TEST st = 0
      THEN { cur := cur - GLOW_STEP
             IF cur <= dark DO { cur := dark; sec_light_state!s := 1 }
           }
      ELSE { cur := cur + GLOW_STEP
             IF cur >= base DO { cur := base; sec_light_state!s := 0 }
           }
      sec_light_runtime!s := cur
      ENDCASE
    }
    DEFAULT: ENDCASE     // no animation
  }
}

LET tick_lights() BE
{ FOR s = 0 TO num_sectors - 1 DO tick_one_light(s)
}

// Lowest static ceiling among sectors connected to `sect` via any
// linedef (excluding `sect` itself). Used as the door's open target.
LET lowest_neighbor_ceil(sect) = VALOF
{ LET best = sec_ceil_static(sect)   // start with own
  LET first = TRUE
  FOR i = 0 TO g_nlines - 1 DO
  { LET le  = g_line_byte + i * LINEDEF_SIZE
    LET front_sd = rd_i16_le(g_base, le + LINEDEF_FRONT_OFS)
    LET back_sd  = rd_i16_le(g_base, le + LINEDEF_BACK_OFS)
    LET front_sec, back_sec, other = 0, 0, -1
    IF front_sd < 0 LOOP
    IF back_sd  < 0 LOOP
    front_sec := sd_sector(front_sd)
    back_sec  := sd_sector(back_sd)
    IF front_sec = sect DO other := back_sec
    IF back_sec  = sect DO other := front_sec
    IF other < 0 LOOP
    { LET ch = sec_ceil_static(other)
      TEST first
      THEN { best := ch; first := FALSE }
      ELSE IF ch < best DO best := ch
    }
  }
  RESULTIS best
}

// Pick the linedef the player is most plausibly "using": closest in
// front of facing direction, within USE_RANGE of midpoint.
LET pick_use_line() = VALOF
{ LET dx = cos_t!(pa & (ANG - 1))
  LET dy = sin_t!(pa & (ANG - 1))
  LET best_d = USE_RANGE * USE_RANGE
  LET best_i = -1
  FOR i = 0 TO g_nlines - 1 DO
  { LET le  = g_line_byte + i * LINEDEF_SIZE
    LET v1 = rd_u16_le(g_base, le + 0)
    LET v2 = rd_u16_le(g_base, le + 2)
    LET vo1 = g_vert_byte + v1 * VERTEX_SIZE
    LET vo2 = g_vert_byte + v2 * VERTEX_SIZE
    LET ax = rd_i16_le(g_base, vo1 + 0)
    LET ay = rd_i16_le(g_base, vo1 + 2)
    LET bx = rd_i16_le(g_base, vo2 + 0)
    LET by = rd_i16_le(g_base, vo2 + 2)
    LET mx = (ax + bx) / 2
    LET my = (ay + by) / 2
    LET rx = mx - px
    LET ry = my - py
    LET dot_fwd = (rx * dx + ry * dy) / 1024
    LET d2 = 0
    IF dot_fwd <= 0 LOOP
    d2 := rx * rx + ry * ry
    IF d2 > best_d LOOP
    best_d := d2
    best_i := i
  }
  RESULTIS best_i
}

// True if linedef.special triggers a door-open on Use.
LET is_use_door_special(spec) = VALOF
{ IF spec = 1   RESULTIS TRUE   // DR — open/close
  IF spec = 31  RESULTIS TRUE   // D1 — open
  IF spec = 117 RESULTIS TRUE   // DR fast
  IF spec = 118 RESULTIS TRUE   // D1 fast
  RESULTIS FALSE
}

LET use_action() BE
{ LET li = pick_use_line()
  LET le, special, back_sd, back_sec = 0, 0, 0, 0
  LET target = 0
  IF li < 0 RETURN
  le := g_line_byte + li * LINEDEF_SIZE
  special := rd_i16_le(g_base, le + LINEDEF_SPECIAL_OFS)
  UNLESS is_use_door_special(special) RETURN
  back_sd := rd_i16_le(g_base, le + LINEDEF_BACK_OFS)
  IF back_sd < 0 RETURN
  back_sec := sd_sector(back_sd)
  IF back_sec < 0 RETURN
  // Already opening? Ignore.
  IF door_state!back_sec ~= 0 RETURN
  target := lowest_neighbor_ceil(back_sec) - DOOR_GAP
  IF target <= ceil_h_runtime!back_sec RETURN   // nothing to open
  door_state!back_sec  := 1
  door_target!back_sec := target
}

// Advance all opening sectors one tick.
LET tick_doors() BE
{ FOR s = 0 TO num_sectors - 1 DO
    IF door_state!s = 1 DO
    { ceil_h_runtime!s := ceil_h_runtime!s + DOOR_SPEED
      IF ceil_h_runtime!s >= door_target!s DO
      { ceil_h_runtime!s := door_target!s
        door_state!s := 2   // open, stay
      }
    }
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

// Non-monster pickups: full 6-char sprite name (frame A, rotation 0).
LET pickup_name(thing_type) = VALOF
{ SWITCHON thing_type INTO
  { CASE 2035: RESULTIS "BAR1A0"
    CASE 2011: RESULTIS "STIMA0"
    CASE 2012: RESULTIS "MEDIA0"
    CASE 2014: RESULTIS "BON1A0"
    CASE 2015: RESULTIS "BON2A0"
    CASE 2018: RESULTIS "ARM1A0"
    CASE 2019: RESULTIS "ARM2A0"
    CASE 2008: RESULTIS "CLIPA0"
    CASE 2048: RESULTIS "AMMOA0"
    CASE 2046: RESULTIS "BROKA0"
    CASE 2047: RESULTIS "CELLA0"
    CASE 17:   RESULTIS "CELPA0"
    CASE 2001: RESULTIS "SHOTA0"
    CASE 2002: RESULTIS "MGUNA0"
    CASE 2003: RESULTIS "LAUNA0"
    CASE 2005: RESULTIS "CSAWA0"
    CASE 2006: RESULTIS "PLASA0"
    CASE 5:    RESULTIS "BKEYA0"
    CASE 13:   RESULTIS "RKEYA0"
    CASE 6:    RESULTIS "YKEYA0"
    CASE 2025: RESULTIS "SUITA0"
    CASE 2024: RESULTIS "PINSA0"
    CASE 2022: RESULTIS "PINVA0"
    CASE 8:    RESULTIS "BPAKA0"
    CASE 2007: RESULTIS "AMMOA0"
    DEFAULT: RESULTIS 0
  }
}

// Monsters: 4-char sprite base (frame 'A' assumed). Sprite name is
// base + 'A' + rotation digit (1..8).
LET monster_base(thing_type) = VALOF
{ SWITCHON thing_type INTO
  { CASE 3001: RESULTIS "TROO"
    CASE 3002: RESULTIS "SARG"
    CASE 3004: RESULTIS "POSS"
    CASE 9:    RESULTIS "SPOS"
    CASE 3005: RESULTIS "HEAD"
    CASE 3006: RESULTIS "SKUL"
    DEFAULT: RESULTIS 0
  }
}

// 0..7 octant of viewer in thing's local frame.  0=front,
// 1=front-right, 2=right, 3=back-right, 4=back, 5=back-left,
// 6=left, 7=front-left. Used to pick rotation digit (octant + 1).
LET viewer_octant(tx, ty, tang) = VALOF
{ LET dx = px - tx
  LET dy = py - ty
  LET cosa = cos_t!(tang & (ANG - 1))
  LET sina = sin_t!(tang & (ANG - 1))
  LET ldx = (dx * cosa + dy * sina) / 1024
  LET ldy = ((0 - dx) * sina + dy * cosa) / 1024
  LET ax = ABS ldx
  LET ay = ABS ldy
  IF ldx >= 0 & ax >= 2 * ay RESULTIS 0
  IF ldx <  0 & ax >= 2 * ay RESULTIS 4
  IF ldy >= 0 & ay >= 2 * ax RESULTIS 2
  IF ldy <  0 & ay >= 2 * ax RESULTIS 6
  IF ldx >= 0 & ldy >= 0 RESULTIS 1
  IF ldx <  0 & ldy >= 0 RESULTIS 3
  IF ldx <  0 & ldy <  0 RESULTIS 5
  RESULTIS 7
}

// Build a BCPL string `name` = base[1..4] + letter + digit(1..8) + NUL.
// `buf` is a word vector with at least 8 bytes of room.
LET build_monster_name(base, octant, letter, buf) BE
{ buf % 0 := 6
  buf % 1 := base % 1
  buf % 2 := base % 2
  buf % 3 := base % 3
  buf % 4 := base % 4
  buf % 5 := letter
  buf % 6 := '1' + octant
}

LET current_anim_letter() = (g_frame_count / ANIM_TICKS) REM 2 = 0 -> 'A', 'B'

// Report a sidedef slot whose texture name is non-trivial ("-" / NUL
// → no texture, legitimate) but failed to composite.  Useful for
// tracking down "missing texture" stripes in outdoor / secret areas.
LET pr_missing_tex(sd_idx, tex_slot_offset, slot_label) BE
{ LET name_byte = g_side_byte + sd_idx * SIDEDEF_SIZE + tex_slot_offset
  LET first_c = g_base % name_byte
  IF first_c = 0 RETURN
  IF first_c = '-' & g_base % (name_byte + 1) = 0 RETURN
  writef("  sd %n %s: ", sd_idx, slot_label)
  FOR i = 0 TO 7 DO
  { LET c = g_base % (name_byte + i)
    IF c = 0 BREAK
    wrch(c)
  }
  newline()
}

LET prebuild_textures(num_sidedefs) BE
{ LET miss = 0
  FOR sd = 0 TO num_sidedefs - 1 DO
  { IF ensure_sidedef_tex(sd, SIDEDEF_UPPER_OFS)  < 0 DO
    { miss := miss + 1; pr_missing_tex(sd, SIDEDEF_UPPER_OFS, "U") }
    IF ensure_sidedef_tex(sd, SIDEDEF_LOWER_OFS)  < 0 DO
    { miss := miss + 1; pr_missing_tex(sd, SIDEDEF_LOWER_OFS, "L") }
    IF ensure_sidedef_tex(sd, SIDEDEF_MIDDLE_OFS) < 0 DO
    { miss := miss + 1; pr_missing_tex(sd, SIDEDEF_MIDDLE_OFS, "M") }
  }
  writef("composited %n unique textures (%n sidedef slots missing)*n",
         tex_count, miss)
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
{ FOR i = 0 TO W - 1 DO
  { col_top!i := 0
    col_bot!i := H - 1
    saved_top!i := 0
    saved_bot!i := H - 1
  }
  cols_open := W
}

LET close_column(col, cy) BE
{ IF col_top!col <= col_bot!col DO
  { saved_top!col := col_top!col
    saved_bot!col := col_bot!col
    cols_open := cols_open - 1
  }
  col_top!col := H
  col_bot!col := -1
  // Whatever sealed the column at this depth becomes the sprite
  // occluder for it.
  IF cy < col_z!col DO col_z!col := cy
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
  THEN vline_clipped(col_x, clip_top, clip_bot,
                     sys(Sys_sdl, sdl_maprgb, 0, 255, 0, 255))
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
         { sys(Sys_setdepth, cy)
           sys(Sys_drawwallcol, col_x, y0, y1, y_anchor, v_step_q16,
               texX, tb, pkd)
         }
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
  { sys(Sys_setdepth, cy)
    sys(Sys_drawwallcol, col_x, y0, y1, y_anchor, 0 - v_step_q16,
        texX, tb, pkd)
  }
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

  // Fake contrast: walls running mostly N–S get a bonus, mostly E–W
  // get a penalty.  Doom's classic "lit from above" feel.
  { LET ddx = ABS (v2x - v1x)
    LET ddy = ABS (v2y - v1y)
    IF ddy > ddx DO fl := fl + FAKECONTRAST
    IF ddx > ddy DO fl := fl - FAKECONTRAST
    IF fl < 0 DO fl := 0
    IF fl > 255 DO fl := 255
  }

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
    IF col_top!col_x > col_bot!col_x DO { close_column(col_x, cy); LOOP }

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
             IF col_top!col_x > col_bot!col_x DO close_column(col_x, cy)
           }
           IF bf > ff DO
           { draw_textured_band(col_x, y_bf, y_cc, y_anchor_low, cy,
                                texU, low_cidx, lower_c)
             IF y_bf - 1 < col_bot!col_x DO col_bot!col_x := y_bf - 1
             IF col_top!col_x > col_bot!col_x DO close_column(col_x, cy)
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
           close_column(col_x, cy)
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
  LET sec_y_top, sec_y_bot = 0, 0

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

  // Sprite-sector wall band projected to screen at this depth. Acts
  // as a "sprite never extends past its own floor/ceiling" clip,
  // independent of which walls happen to have rendered at each col.
  sec_y_top := project_y(ceil_at(wx, wy), cay)
  sec_y_bot := project_y(wz, cay)

  // Sprites use full brightness for now (no fade).
  sys(Sys_setlight, 255)
  // Sprite depth is constant across all its columns. Per-pixel
  // z-test inside drawwallcol skips pixels behind a closer wall.
  sys(Sys_setdepth, cay)

  // Iterate visible columns.
  { LET cx0 = sx_left
    LET cx1 = sx_right
    IF cx0 < 0 DO cx0 := 0
    IF cx1 >= W DO cx1 := W - 1
    FOR sx = cx0 TO cx1 DO
    { LET texX = ((sx - sx_left) * pw) / sw
      LET cy0 = y_top
      LET cy1 = y_bot
      LET t = sec_y_top
      LET b = sec_y_bot
      IF texX < 0 LOOP
      IF texX >= pw LOOP
      IF cay >= col_z!sx LOOP        // occluded by a closer solid wall
      // Base clip = sprite's own sector wall band. If the column is
      // still open (a portal opening at this col), intersect with it
      // so portal frames clip the sprite too.
      IF col_top!sx <= col_bot!sx DO
      { IF col_top!sx > t DO t := col_top!sx
        IF col_bot!sx < b DO b := col_bot!sx
      }
      IF cy0 < t DO cy0 := t
      IF cy1 > b DO cy1 := b
      IF cy0 > cy1 LOOP
      sys(Sys_drawwallcol, sx, cy0, cy1, y_top, 0 - v_step_q16,
          texX, tb, pkd)
    }
  }
}

// Insertion-sort vs_* arrays by cay descending (farthest first).
LET sort_visible() BE
{ FOR i = 1 TO vs_count - 1 DO
  { LET j = i
    WHILE j > 0 DO
    { IF vs_cy!(j - 1) >= vs_cy!j BREAK
      { LET t = vs_x!j;    vs_x!j    := vs_x!(j-1);    vs_x!(j-1)    := t }
      { LET t = vs_y!j;    vs_y!j    := vs_y!(j-1);    vs_y!(j-1)    := t }
      { LET t = vs_z!j;    vs_z!j    := vs_z!(j-1);    vs_z!(j-1)    := t }
      { LET t = vs_cy!j;   vs_cy!j   := vs_cy!(j-1);   vs_cy!(j-1)   := t }
      { LET t = vs_cidx!j; vs_cidx!j := vs_cidx!(j-1); vs_cidx!(j-1) := t }
      j := j - 1
    }
  }
}

LET draw_sprites() BE
{ LET n = g_tsize / THING_SIZE
  vs_count := 0
  FOR i = 0 TO n - 1 DO
  { LET o    = g_things_byte + i * THING_SIZE
    LET wx   = rd_i16_le(g_base, o + THING_X_OFS)
    LET wy   = rd_i16_le(g_base, o + THING_Y_OFS)
    LET tang = rd_u16_le(g_base, o + THING_ANG_OFS)   // Doom degrees
    LET tp   = rd_u16_le(g_base, o + THING_TYPE_OFS)
    LET name_buf  = VEC 2
    LET cidx = -1
    LET rx, ry, cay = 0, 0, 0
    LET base = 0
    LET pn = 0

    rx := wx - px
    ry := wy - py
    cay := (rx * cos_t!(pa & (ANG-1)) + ry * sin_t!(pa & (ANG-1))) / 1024
    IF cay < NEAR LOOP

    base := monster_base(tp)
    TEST base ~= 0
    THEN { LET tang_t = (tang * ANG) / 360
           LET oct = viewer_octant(wx, wy, tang_t)
           LET letter = current_anim_letter()
           build_monster_name(base, oct, letter, name_buf)
           cidx := ensure_sprite(name_buf)
           // If frame B isn't in the WAD for this monster, fall back
           // to A so it doesn't disappear every other anim tick.
           IF cidx < 0 & letter = 'B' DO
           { build_monster_name(base, oct, 'A', name_buf)
             cidx := ensure_sprite(name_buf)
           }
         }
    ELSE { pn := pickup_name(tp)
           IF pn = 0 LOOP
           cidx := ensure_sprite(pn)
         }
    IF cidx < 0 LOOP
    IF vs_count >= MAX_VIS_SPRITES LOOP

    vs_x!vs_count    := wx
    vs_y!vs_count    := wy
    vs_z!vs_count    := floor_at(wx, wy)
    vs_cy!vs_count   := cay
    vs_cidx!vs_count := cidx
    vs_count := vs_count + 1
  }
  sort_visible()
  FOR i = 0 TO vs_count - 1 DO
    draw_sprite(vs_x!i, vs_y!i, vs_z!i, vs_cidx!i)
}

// Pick the current weapon frame's cache index based on fire timer.
LET current_weapon_cidx() = VALOF
{ LET t = wep_fire_timer
  IF t <= 0 RESULTIS wep_cidx_a
  // Fire cycle: each WEAPON_FIRE_TICKS frames advances B → C → D.
  { LET phase = (3 * WEAPON_FIRE_TICKS - t) / WEAPON_FIRE_TICKS
    IF phase = 0 RESULTIS wep_cidx_b
    IF phase = 1 RESULTIS wep_cidx_c
    RESULTIS wep_cidx_d
  }
}

LET draw_weapon() BE
{ LET cidx = current_weapon_cidx()
  LET pw, ph, tb = 0, 0, 0
  LET sw, sh = 0, 0
  LET sx0, sy0, sx1, sy1 = 0, 0, 0, 0
  LET bob_x, bob_y = 0, 0
  LET pkd, v_step_q16 = 0, 0
  IF cidx < 0 RETURN
  pw := spr_w!cidx
  ph := spr_h!cidx
  tb := spr_base!cidx
  sw := pw * WEAPON_SCALE
  sh := ph * WEAPON_SCALE
  // Walk-cycle bob: cos for horizontal sway, sin for vertical bounce.
  // Quartered so even idle gets a subtle drift.
  bob_x := (cos_t!(wep_bob_t & (ANG-1)) * 12) / 1024
  bob_y := (sin_t!(wep_bob_t & (ANG-1)) *  8) / 1024
  IF bob_y < 0 DO bob_y := 0 - bob_y     // sin gives ±; bounce is upward only
  sx0 := W / 2 - sw / 2 + bob_x
  sy0 := H - hud_bar_h - sh + bob_y
  sx1 := sx0 + sw - 1
  sy1 := sy0 + sh - 1
  v_step_q16 := (ph * 65536) / sh        // tex_h pixels over sh screen pixels
  pkd := (pw & #xFFFF) | (ph << 16)
  // Always-on-top: depth 0 beats every wall/flat (z_buf cleared to MAX).
  sys(Sys_setlight, 255)
  sys(Sys_setdepth, 0)
  { LET cx0 = sx0
    LET cx1 = sx1
    IF cx0 < 0 DO cx0 := 0
    IF cx1 >= W DO cx1 := W - 1
    FOR sx = cx0 TO cx1 DO
    { LET texX = ((sx - sx0) * pw) / sw
      IF texX < 0 LOOP
      IF texX >= pw LOOP
      sys(Sys_drawwallcol, sx, sy0, sy1, sy0, 0 - v_step_q16,
          texX, tb, pkd)
    }
  }
}

// Scale-blit any cached patch at screen (sx_top, sy_top) at `scale`.
// Goes through drawwallcol with transparency so palette-0 pixels stay
// see-through. Depth is set by the caller (typically 0 for HUD).
LET draw_patch_at(cidx, sx_top, sy_top, scale) BE
{ LET pw, ph, tb = 0, 0, 0
  LET sw, sh = 0, 0
  LET sy_bot = 0
  LET pkd, v_step_q16 = 0, 0
  IF cidx < 0 RETURN
  pw := spr_w!cidx
  ph := spr_h!cidx
  tb := spr_base!cidx
  sw := pw * scale
  sh := ph * scale
  sy_bot := sy_top + sh - 1
  v_step_q16 := (ph * 65536) / sh
  pkd := (pw & #xFFFF) | (ph << 16)
  { LET cx0 = sx_top
    LET cx1 = sx_top + sw - 1
    IF cx0 < 0 DO cx0 := 0
    IF cx1 >= W DO cx1 := W - 1
    FOR sx = cx0 TO cx1 DO
    { LET texX = ((sx - sx_top) * pw) / sw
      IF texX < 0 LOOP
      IF texX >= pw LOOP
      sys(Sys_drawwallcol, sx, sy_top, sy_bot, sy_top, 0 - v_step_q16,
          texX, tb, pkd)
    }
  }
}

// Right-align an integer at (right_x_native, y_native) using STTNUM
// digits. Coords are STBAR-native pixels (pre-scale).
LET draw_number(n, max_digits, right_x_native, y_native, hud_origin_x, hud_origin_y) BE
{ LET v = n
  LET digs = VEC 4
  IF v < 0 DO v := 0
  // Extract digits (rightmost first).
  FOR i = 0 TO max_digits - 1 DO
  { digs!i := v REM 10
    v := v / 10
  }
  // Find leading non-zero so we don't render leading-zero digits.
  { LET shown = 1
    FOR i = max_digits - 1 TO 0 BY -1 DO
      IF digs!i ~= 0 DO { shown := i + 1; BREAK }
    // Always show at least one digit even when n = 0.
    IF n = 0 DO shown := 1
    // Render right-to-left.  Each digit occupies its own native width;
    // STTNUM glyphs are all 14 wide so we use that.
    { LET native_w = 14
      FOR i = 0 TO shown - 1 DO
      { LET d  = digs!i
        LET nx = right_x_native - (i + 1) * native_w
        draw_patch_at(digit_cidx!d,
                      hud_origin_x + nx * HUD_SCALE,
                      hud_origin_y + y_native * HUD_SCALE,
                      HUD_SCALE)
      }
    }
  }
}

LET draw_hud() BE
{ LET hud_origin_x = 0
  LET hud_origin_y = 0
  LET face_idx = 0
  IF hud_cidx < 0 RETURN
  hud_origin_x := W / 2 - (spr_w!hud_cidx * HUD_SCALE) / 2
  hud_origin_y := H - spr_h!hud_cidx * HUD_SCALE
  sys(Sys_setlight, 255)
  sys(Sys_setdepth, 0)
  // 1) Status bar art.
  draw_patch_at(hud_cidx, hud_origin_x, hud_origin_y, HUD_SCALE)
  // 2) Numbers.
  draw_number(hud_ammo,   3, ST_AMMOX,   ST_AMMOY,   hud_origin_x, hud_origin_y)
  draw_number(hud_health, 3, ST_HEALTHX, ST_HEALTHY, hud_origin_x, hud_origin_y)
  draw_number(hud_armor,  3, ST_ARMORX,  ST_ARMORY,  hud_origin_x, hud_origin_y)
  // 3) Idle face cycle (3 frames).
  face_idx := (g_frame_count / FACE_TICKS) REM 3
  draw_patch_at(face_cidx!face_idx,
                hud_origin_x + ST_FX * HUD_SCALE,
                hud_origin_y + ST_FY * HUD_SCALE,
                HUD_SCALE)
}

// Project a world point to automap screen coords. Centre = (W/2, am_cy).
LET am_proj_x(wx) = W / 2 + ((wx - px) * automap_scale_q10) / 1024
LET am_proj_y(wy) = (H - hud_bar_h) / 2 - ((wy - py) * automap_scale_q10) / 1024

LET draw_automap() BE
{ LET cx, cy = 0, 0
  // Dim background fill across the play area (above hud_bar_h).
  sys(Sys_sdl, sdl_drawfillrect, surf, 0, 0, W, H - hud_bar_h, am_col_bg)
  FOR i = 0 TO g_nlines - 1 DO
  { LET le  = g_line_byte + i * LINEDEF_SIZE
    LET v1 = rd_u16_le(g_base, le + 0)
    LET v2 = rd_u16_le(g_base, le + 2)
    LET back_sd = rd_i16_le(g_base, le + LINEDEF_BACK_OFS)
    LET vo1 = g_vert_byte + v1 * VERTEX_SIZE
    LET vo2 = g_vert_byte + v2 * VERTEX_SIZE
    LET ax = rd_i16_le(g_base, vo1 + 0)
    LET ay = rd_i16_le(g_base, vo1 + 2)
    LET bx = rd_i16_le(g_base, vo2 + 0)
    LET by = rd_i16_le(g_base, vo2 + 2)
    LET col = back_sd < 0 -> am_col_wall, am_col_portal
    sys(Sys_sdl, sdl_drawline, surf,
        am_proj_x(ax), am_proj_y(ay),
        am_proj_x(bx), am_proj_y(by),
        col)
  }
  // Player marker — small triangle pointing along facing.
  cx := W / 2
  cy := (H - hud_bar_h) / 2
  { LET dx = cos_t!(pa & (ANG - 1))
    LET dy = sin_t!(pa & (ANG - 1))
    LET nlen = (automap_scale_q10 * 16) / 1024
    LET tipx = cx + (dx * nlen) / 1024
    LET tipy = cy - (dy * nlen) / 1024
    LET basel = (automap_scale_q10 * 10) / 1024
    LET blx = cx - (dy * basel) / 1024
    LET bly = cy - (dx * basel) / 1024
    LET brx = cx + (dy * basel) / 1024
    LET bry = cy + (dx * basel) / 1024
    sys(Sys_sdl, sdl_drawline, surf, tipx, tipy, blx, bly, am_col_player)
    sys(Sys_sdl, sdl_drawline, surf, tipx, tipy, brx, bry, am_col_player)
    sys(Sys_sdl, sdl_drawline, surf, blx, bly, brx, bry, am_col_player)
  }
}

LET drawframe() BE
{ reset_clip()
  // Per-pixel z-buffer is the source of truth; col_z is kept as a
  // fast first-pass occluder used by sprite cull.
  sys(Sys_clearzbuf)
  // Pre-fill the canvas with a sky / floor split so any column the
  // walls and flats don't subsequently touch still shows the correct
  // backdrop. Walls/flats and the panoramic sky overpaint as normal.
  sys(Sys_sdl, sdl_drawfillrect, surf, 0, 0,       W, HORIZON, sky_col)
  sys(Sys_sdl, sdl_drawfillrect, surf, 0, HORIZON, W, H,       floor_col)
  FOR i = 0 TO W - 1 DO col_z!i := Z_INF
  cam_z := floor_at(px, py) + EYE_H
  fwd_x   := cos_t!(pa & (ANG - 1))
  fwd_y   := sin_t!(pa & (ANG - 1))
  right_x := fwd_y
  right_y := 0 - fwd_x
  TEST automap_on
  THEN { draw_automap() }
  ELSE { render_node(g_root_node)
         fill_remaining()
         draw_sprites()
         draw_weapon()
       }
  draw_hud()
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
  saved_top := getvec(W)
  saved_bot := getvec(W)
  vs_x      := getvec(MAX_VIS_SPRITES)
  vs_y      := getvec(MAX_VIS_SPRITES)
  vs_z      := getvec(MAX_VIS_SPRITES)
  vs_cy     := getvec(MAX_VIS_SPRITES)
  vs_cidx   := getvec(MAX_VIS_SPRITES)

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
  // Held-weapon HUD frames. Falls back gracefully if a frame is
  // missing in the WAD (only the idle frame is strictly required).
  wep_cidx_a := ensure_sprite("PISGA0")
  wep_cidx_b := ensure_sprite("PISGB0")
  wep_cidx_c := ensure_sprite("PISGC0")
  wep_cidx_d := ensure_sprite("PISGD0")
  hud_cidx   := ensure_sprite("STBAR")
  IF hud_cidx >= 0 DO hud_bar_h := spr_h!hud_cidx * HUD_SCALE
  face_cidx  := getvec(3)
  face_cidx!0 := ensure_sprite("STFST00")
  face_cidx!1 := ensure_sprite("STFST01")
  face_cidx!2 := ensure_sprite("STFST02")
  digit_cidx := getvec(10)
  digit_cidx!0 := ensure_sprite("STTNUM0")
  digit_cidx!1 := ensure_sprite("STTNUM1")
  digit_cidx!2 := ensure_sprite("STTNUM2")
  digit_cidx!3 := ensure_sprite("STTNUM3")
  digit_cidx!4 := ensure_sprite("STTNUM4")
  digit_cidx!5 := ensure_sprite("STTNUM5")
  digit_cidx!6 := ensure_sprite("STTNUM6")
  digit_cidx!7 := ensure_sprite("STTNUM7")
  digit_cidx!8 := ensure_sprite("STTNUM8")
  digit_cidx!9 := ensure_sprite("STTNUM9")
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
    num_sectors := sec_sz / SECTOR_SIZE
    prebuild_flats(num_sectors)
  }
  // Build dynamic-ceiling arrays now that we know the sector count.
  ceil_h_runtime := getvec(num_sectors)
  door_state     := getvec(num_sectors)
  door_target    := getvec(num_sectors)
  sec_light_runtime := getvec(num_sectors)
  sec_min_light     := getvec(num_sectors)
  sec_special_v     := getvec(num_sectors)
  sec_light_state   := getvec(num_sectors)
  sec_light_timer   := getvec(num_sectors)
  FOR s = 0 TO num_sectors - 1 DO
  { ceil_h_runtime!s := sec_ceil_static(s)
    door_state!s     := 0
    door_target!s    := 0
    sec_light_runtime!s := sec_light_static(s)
    sec_min_light!s     := lowest_neighbor_light(s)
    sec_special_v!s     := sec_special(s)
    sec_light_state!s   := 0
    sec_light_timer!s   := next_rand() & 15   // stagger phases
  }

  sys(Sys_sdl, sdl_init)
  surf := sys(Sys_sdl, sdl_setvideomode, W, H, 0, 0)

  sky_col   := sys(Sys_sdl, sdl_maprgb, 0,  60, 110, 180)
  floor_col := sys(Sys_sdl, sdl_maprgb, 0,  40,  40,  40)
  am_col_bg     := sys(Sys_sdl, sdl_maprgb, 0,  16,  16,  16)
  am_col_wall   := sys(Sys_sdl, sdl_maprgb, 0, 220, 100, 100)
  am_col_portal := sys(Sys_sdl, sdl_maprgb, 0, 110,  90, 110)
  am_col_player := sys(Sys_sdl, sdl_maprgb, 0, 100, 220, 100)

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

    // Use action — edge-trigger on E or Space press.
    { LET use_now = key_down(K_E) | key_down(K_SPACE)
      IF use_now ~= 0 & use_prev = 0 DO use_action()
      use_prev := use_now
    }

    // Automap toggle — edge-trigger on M.
    { LET m_now = key_down(K_M)
      IF m_now ~= 0 & automap_prev = 0 DO
        automap_on := automap_on -> FALSE, TRUE
      automap_prev := m_now
    }
    // Automap zoom — held keys; clamp to sane range.
    IF automap_on DO
    { IF key_down(K_PLUS) | key_down(K_PGUP) DO
        automap_scale_q10 := automap_scale_q10 + 16
      IF key_down(K_MINUS) | key_down(K_PGDN) DO
        automap_scale_q10 := automap_scale_q10 - 16
      IF automap_scale_q10 < 32 DO automap_scale_q10 := 32
      IF automap_scale_q10 > 2048 DO automap_scale_q10 := 2048
    }

    // Fire action — edge-trigger on F or LCtrl; resets fire timer.
    { LET fire_now = key_down(K_F) | key_down(K_LCTRL)
      IF fire_now ~= 0 & wep_fire_prev = 0 DO
        wep_fire_timer := 3 * WEAPON_FIRE_TICKS
      wep_fire_prev := fire_now
    }
    IF wep_fire_timer > 0 DO wep_fire_timer := wep_fire_timer - 1

    IF fwd ~= 0 DO
    { LET dx = (cos_t!(pa & (ANG-1)) * MOVE * fwd) / 1024
      LET dy = (sin_t!(pa & (ANG-1)) * MOVE * fwd) / 1024
      try_move(dx, dy)
    }
    IF turn ~= 0 DO pa := (pa + turn) & (ANG - 1)

    // Advance bob phase faster when moving, slowly while idle.
    TEST fwd ~= 0 | turn ~= 0
    THEN wep_bob_t := (wep_bob_t + 96) & (ANG - 1)
    ELSE wep_bob_t := (wep_bob_t + 16) & (ANG - 1)

    tick_doors()
    tick_lights()
    g_frame_count := g_frame_count + 1

    drawframe()
    delay(16)
  }

  freevec(sin_t); freevec(cos_t); freevec(keys)
  freevec(col_top); freevec(col_bot)
  writef("dwlt exited*n")
  RESULTIS 0
}
