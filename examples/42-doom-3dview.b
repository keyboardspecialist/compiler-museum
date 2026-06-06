// 42-doom-3dview: first-person Doom wall renderer. No BSP, no
// textures, no per-column z-buffer. Flat-shaded by sector light.
//
// Setup: upload a Doom WAD via Assets (same as 39/40/41). Run.
//
// Pipeline per linedef:
//   1. Resolve front (+ back) sidedef → sector → floor_h, ceil_h, light.
//   2. Transform both vertices to camera space:
//        camY (depth)   =  rx*cos(pa) + ry*sin(pa)
//        camX (lateral) =  rx*sin(pa) - ry*cos(pa)
//   3. Skip 1-sided walls whose front face points away from the camera.
//   4. Near-plane clip (linear interp) so we never divide by tiny z.
//   5. Project screen X using f = W/2 (a 90° horizontal FOV).
//   6. Walk each column: perspective-correct interp of 1/z, project
//      floor_h and ceil_h, draw a vertical line per slot:
//        - solid wall      : floor..ceil between sectors
//        - lower step      : front_floor..back_floor (back higher)
//        - upper step      : back_ceil..front_ceil  (back lower)
//   7. No global occlusion. Draw order = linedef order. Overdraw is
//      visible in cluttered scenes — fixed in the BSP phase.
//
// Controls: WASD/arrows = move/turn, Esc = quit.

SECTION "d3dv"

GET "libhdr"
GET "sdl"

MANIFEST {
  W       = 960
  H       = 720
  HORIZON = 360             // H/2 — eye level on screen
  F_X     = 480             // W/2  → 90° horizontal FOV
  NEAR    = 4               // world units; near-plane for clipping
  EYE_H   = 41              // Doom standard eye height above floor 0

  HDR_NUMLUMPS_OFS =  4
  HDR_INFOOFS_OFS  =  8
  HDR_SIZE         = 12
  DIR_ENTRY_SIZE   = 16
  DIR_FILEPOS_OFS  =  0
  DIR_SIZE_OFS     =  4
  DIR_NAME_OFS     =  8

  VERTEX_SIZE  = 4
  LINEDEF_SIZE = 14
  LINEDEF_FRONT_OFS = 10
  LINEDEF_BACK_OFS  = 12
  SIDEDEF_SIZE       = 30
  SIDEDEF_SECTOR_OFS = 28
  SECTOR_SIZE        = 26
  SECTOR_FLOOR_OFS   = 0
  SECTOR_CEIL_OFS    = 2
  SECTOR_LIGHT_OFS   = 20

  THING_SIZE   = 10
  THING_X_OFS    = 0
  THING_Y_OFS    = 2
  THING_ANG_OFS  = 4
  THING_TYPE_OFS = 6

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
  g_vert_byte = 0
  g_line_byte = 0
  g_side_byte = 0
  g_sec_byte  = 0
  g_nlines    = 0

  // Cached sky/floor colors for the cleared backdrop.
  sky_col   = 0
  floor_col = 0

  px = 0
  py = 0
  pa = 0
  cam_z = 0
}

// ---------- byte helpers (lifted from 41) ----------

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

// ---------- trig + scaling ----------

LET fsin(x) = VALOF
{ LET pi, twopi, x2, t, s = 0, 0, 0, 0, 0
  pi    #:= 3.14159265358979
  twopi #:= 2.0 #* pi
  WHILE x #>  pi DO x #:= x #- twopi
  WHILE x #<  (0.0 #- pi) DO x #:= x #+ twopi
  x2 #:= x #* x
  t  #:= x
  s  #:= t
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

// ---------- map-data accessors ----------

LET sd_sector(idx) =
  rd_i16_le(g_base, g_side_byte + idx * SIDEDEF_SIZE + SIDEDEF_SECTOR_OFS)

LET sec_floor(idx) =
  rd_i16_le(g_base, g_sec_byte + idx * SECTOR_SIZE + SECTOR_FLOOR_OFS)

LET sec_ceil(idx) =
  rd_i16_le(g_base, g_sec_byte + idx * SECTOR_SIZE + SECTOR_CEIL_OFS)

LET sec_light(idx) =
  rd_i16_le(g_base, g_sec_byte + idx * SECTOR_SIZE + SECTOR_LIGHT_OFS)

// ---------- player ----------

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

LET key_down(k) = k >= 0 & k < KEYCAP -> keys!k, 0

// ---------- 3D rendering ----------

// Camera-space lateral coord, in world units. positive = right of view.
LET cam_x(wx, wy) = VALOF
{ LET rx = wx - px
  LET ry = wy - py
  RESULTIS (rx * sin_t!(pa & (ANG-1)) - ry * cos_t!(pa & (ANG-1))) / 1024
}

// Camera-space depth coord. positive = in front of view.
LET cam_y(wx, wy) = VALOF
{ LET rx = wx - px
  LET ry = wy - py
  RESULTIS (rx * cos_t!(pa & (ANG-1)) + ry * sin_t!(pa & (ANG-1))) / 1024
}

// Front-facing test for 1-sided walls. Skip if camera is behind.
LET front_facing(v1x, v1y, v2x, v2y) = VALOF
{ LET dx = v2x - v1x
  LET dy = v2y - v1y
  RESULTIS (px - v1x) * dy - (py - v1y) * dx > 0
}

// Map sector light (0..255) to packed RGB. Boost the floor of dim
// rooms so they're still legible without textures.
LET light_to_col(light) = VALOF
{ LET v = light
  IF v < 40 DO v := 40
  IF v > 255 DO v := 255
  RESULTIS sys(Sys_sdl, sdl_maprgb, 0, v, v, v)
}

// Draw a single vertical line, clipped to the canvas.
LET vline(col, y0, y1, c) BE
{ IF y0 > y1 DO { LET t = y0; y0 := y1; y1 := t }
  IF y0 < 0 DO y0 := 0
  IF y1 >= H DO y1 := H - 1
  IF y0 <= y1 DO
    sys(Sys_sdl, sdl_drawvline, surf, col, y0, y1, c)
}

// Project a world Z (absolute level) at camera-space depth `cy` to
// the screen Y row. cy must be > 0.
LET project_y(world_z, cy) =
  HORIZON - ((world_z - cam_z) * F_X) / cy

// Render one wall column. world_top / world_bot are the world-space
// Z bounds (ceiling / floor); cy is the camera-space depth at this
// column; col_x is the screen column.
LET draw_band(col_x, cy, world_bot, world_top, c) BE
{ LET y_top = project_y(world_top, cy)
  LET y_bot = project_y(world_bot, cy)
  vline(col_x, y_top, y_bot, c)
}

// Process one linedef.
LET render_linedef(le) BE
{ LET v1, v2 = 0, 0
  LET front_sd, back_sd = 0, 0
  LET front_sec, back_sec = 0, 0
  LET v1x, v1y, v2x, v2y = 0, 0, 0, 0
  LET cx1, cy1, cx2, cy2 = 0, 0, 0, 0
  LET ff, fc, fl, bf, bc = 0, 0, 0, 0, 0
  LET two_sided = FALSE
  LET sx1, sx2 = 0, 0
  LET ix1, ix2 = 0, 0
  LET col_lo, col_hi = 0, 0
  LET inv_z1, inv_z2 = 0, 0
  LET dx_span = 0
  LET wall_col, lower_col, upper_col = 0, 0, 0

  v1 := rd_u16_le(g_base, le + 0)
  v2 := rd_u16_le(g_base, le + 2)
  front_sd := rd_i16_le(g_base, le + LINEDEF_FRONT_OFS)
  back_sd  := rd_i16_le(g_base, le + LINEDEF_BACK_OFS)
  IF front_sd < 0 RETURN

  front_sec := sd_sector(front_sd)
  IF front_sec < 0 RETURN
  ff := sec_floor(front_sec)
  fc := sec_ceil(front_sec)
  fl := sec_light(front_sec)

  two_sided := back_sd >= 0
  IF two_sided DO
  { back_sec := sd_sector(back_sd)
    IF back_sec < 0 DO two_sided := FALSE
    IF two_sided DO
    { bf := sec_floor(back_sec)
      bc := sec_ceil(back_sec)
    }
  }

  // Vertex world coords.
  { LET vo1 = g_vert_byte + v1 * VERTEX_SIZE
    LET vo2 = g_vert_byte + v2 * VERTEX_SIZE
    v1x := rd_i16_le(g_base, vo1 + 0)
    v1y := rd_i16_le(g_base, vo1 + 2)
    v2x := rd_i16_le(g_base, vo2 + 0)
    v2y := rd_i16_le(g_base, vo2 + 2)
  }

  // Backface cull for solid walls (portals always rendered both sides).
  UNLESS two_sided DO
    UNLESS front_facing(v1x, v1y, v2x, v2y) RETURN

  cx1 := cam_x(v1x, v1y)
  cy1 := cam_y(v1x, v1y)
  cx2 := cam_x(v2x, v2y)
  cy2 := cam_y(v2x, v2y)

  // Both endpoints behind near plane → skip.
  IF cy1 < NEAR & cy2 < NEAR RETURN

  // Clip individual endpoints to NEAR. Linear interp along the edge.
  IF cy1 < NEAR DO
  { LET t1024 = ((NEAR - cy1) * 1024) / (cy2 - cy1)
    cx1 := cx1 + ((cx2 - cx1) * t1024) / 1024
    cy1 := NEAR
  }
  IF cy2 < NEAR DO
  { LET t1024 = ((NEAR - cy2) * 1024) / (cy1 - cy2)
    cx2 := cx2 + ((cx1 - cx2) * t1024) / 1024
    cy2 := NEAR
  }

  sx1 := W/2 + (cx1 * F_X) / cy1
  sx2 := W/2 + (cx2 * F_X) / cy2

  // Order left → right.
  IF sx1 > sx2 DO
  { LET tx = sx1; sx1 := sx2; sx2 := tx
    tx := cx1; cx1 := cx2; cx2 := tx
    tx := cy1; cy1 := cy2; cy2 := tx
  }

  // Span = 0 (vertical sliver) → nothing to draw.
  IF sx1 = sx2 RETURN

  // Visible-column range.
  ix1 := sx1
  ix2 := sx2
  IF ix1 < 0 DO ix1 := 0
  IF ix2 >= W DO ix2 := W - 1
  IF ix1 > ix2 RETURN

  // Perspective-correct interp uses 1/z. Scale by 1024 to stay in ints.
  inv_z1 := (1024 * 1024) / cy1
  inv_z2 := (1024 * 1024) / cy2
  dx_span := sx2 - sx1

  wall_col  := light_to_col(fl)
  lower_col := light_to_col(fl - 16)
  upper_col := light_to_col(fl - 32)

  FOR col_x = ix1 TO ix2 DO
  { LET t     = ((col_x - sx1) * 1024) / dx_span
    LET inv_z = inv_z1 + ((inv_z2 - inv_z1) * t) / 1024
    LET cy    = 0
    IF inv_z <= 0 LOOP
    cy := (1024 * 1024) / inv_z
    TEST two_sided
    THEN { IF bf > ff DO draw_band(col_x, cy, ff, bf, lower_col)
           IF bc < fc DO draw_band(col_x, cy, bc, fc, upper_col)
         }
    ELSE draw_band(col_x, cy, ff, fc, wall_col)
  }
}

LET drawframe() BE
{ // Background: top half sky, bottom half floor.
  sys(Sys_sdl, sdl_drawfillrect, surf, 0, 0, W, HORIZON, sky_col)
  sys(Sys_sdl, sdl_drawfillrect, surf, 0, HORIZON, W, H, floor_col)

  FOR i = 0 TO g_nlines - 1 DO
    render_linedef(g_line_byte + i * LINEDEF_SIZE)

  sys(Sys_sdl, sdl_flip, surf)
}

// ---------- main ----------

LET start() = VALOF
{ LET info = VEC 3
  LET nbytes = 0
  LET numlumps, dirofs = 0, 0
  LET map_idx = 0
  LET vert_idx, line_idx, side_idx, sec_idx, thing_idx = 0, 0, 0, 0, 0
  LET things_byte, tsize = 0, 0
  LET lsize = 0

  UNLESS try_load_wad(info) DO
  { writef("No WAD asset. Upload one from site/textures/Wads/*n")
    RESULTIS 1
  }
  nbytes := info!0
  IF info!1 ~= 0 DO { writef("Asset is an image, not a WAD.*n"); RESULTIS 1 }
  g_base := info!2
  IF nbytes < HDR_SIZE DO { writef("Truncated WAD.*n"); RESULTIS 1 }

  numlumps := rd_u32_le(g_base, HDR_NUMLUMPS_OFS)
  dirofs   := rd_u32_le(g_base, HDR_INFOOFS_OFS)

  map_idx := find_first_map(g_base, dirofs, numlumps)
  IF map_idx < 0 DO { writef("No map marker.*n"); RESULTIS 1 }
  writef("map: "); pr_lump_name(g_base, dirofs + map_idx * DIR_ENTRY_SIZE); newline()

  vert_idx  := find_map_lump(g_base, dirofs, map_idx, numlumps, "VERTEXES")
  line_idx  := find_map_lump(g_base, dirofs, map_idx, numlumps, "LINEDEFS")
  side_idx  := find_map_lump(g_base, dirofs, map_idx, numlumps, "SIDEDEFS")
  sec_idx   := find_map_lump(g_base, dirofs, map_idx, numlumps, "SECTORS")
  thing_idx := find_map_lump(g_base, dirofs, map_idx, numlumps, "THINGS")
  IF vert_idx < 0 | line_idx < 0 | side_idx < 0 | sec_idx < 0 | thing_idx < 0 DO
  { writef("Missing map lump (v=%n l=%n s=%n sec=%n t=%n).*n",
           vert_idx, line_idx, side_idx, sec_idx, thing_idx)
    RESULTIS 1
  }

  g_vert_byte := rd_u32_le(g_base, dirofs + vert_idx * DIR_ENTRY_SIZE + DIR_FILEPOS_OFS)
  g_line_byte := rd_u32_le(g_base, dirofs + line_idx * DIR_ENTRY_SIZE + DIR_FILEPOS_OFS)
  lsize       := rd_u32_le(g_base, dirofs + line_idx * DIR_ENTRY_SIZE + DIR_SIZE_OFS)
  g_side_byte := rd_u32_le(g_base, dirofs + side_idx * DIR_ENTRY_SIZE + DIR_FILEPOS_OFS)
  g_sec_byte  := rd_u32_le(g_base, dirofs + sec_idx  * DIR_ENTRY_SIZE + DIR_FILEPOS_OFS)
  things_byte := rd_u32_le(g_base, dirofs + thing_idx * DIR_ENTRY_SIZE + DIR_FILEPOS_OFS)
  tsize       := rd_u32_le(g_base, dirofs + thing_idx * DIR_ENTRY_SIZE + DIR_SIZE_OFS)
  g_nlines := lsize / LINEDEF_SIZE
  writef("linedefs: %n*n", g_nlines)

  sin_t := getvec(ANG)
  cos_t := getvec(ANG)
  buildtrig()

  UNLESS find_player_start(g_base, things_byte, tsize) DO
  { writef("No player1 start; spawning at (0, 0).*n")
    px := 0; py := 0; pa := 0
  }
  writef("player start  px=%n py=%n pa=%n*n", px, py, pa)

  // No BSP yet, so we can't look up the floor of the sector the
  // player is in. Use a fixed eye height above world zero — the
  // common Doom convention puts most maps' starting floor at z=0.
  cam_z := EYE_H

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
      px := px + dx
      py := py + dy
    }
    IF turn ~= 0 DO pa := (pa + turn) & (ANG - 1)

    drawframe()
    delay(16)
  }

  freevec(sin_t); freevec(cos_t); freevec(keys)
  writef("d3dv exited*n")
  RESULTIS 0
}
