// 43-doom-bsp: Doom BSP-traversed renderer with per-column clip
// windows. Fixes the overdraw + cam_z bugs of 42 by walking
// NODES / SSECTORS / SEGS front-to-back and tracking the visible
// vertical band per screen column.
//
// Setup: upload a Doom WAD via Assets, Compile & Run.
//
// What's new vs 42:
//   - Parse NODES (28 B each), SSECTORS (4 B), SEGS (12 B).
//   - render_node(idx): walks BSP front-to-back relative to player.
//   - Per-column clip windows (col_top[W], col_bot[W]) start fully
//     open and narrow as solid walls / portal steps consume them.
//   - When all columns are closed, traversal returns early.
//   - point_in_subsector(x, y) gives the player's sector → real
//     floor height → eye height = floor + 41.
//   - Open columns left after BSP traversal are filled with sky
//     (above horizon) / floor (below) so the world doesn't have
//     transparent voids.
//
// Still TODO: textures, wall collision, F_SKY1 handling.
//
// Controls: WASD/arrows = move/turn, Esc = quit.

SECTION "dbsp"

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
  LINEDEF_FRONT_OFS = 10
  LINEDEF_BACK_OFS  = 12
  SIDEDEF_SIZE       = 30
  SIDEDEF_SECTOR_OFS = 28
  SECTOR_SIZE        = 26
  SECTOR_FLOOR_OFS   = 0
  SECTOR_CEIL_OFS    = 2
  SECTOR_LIGHT_OFS   = 20

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
  g_node_byte = 0
  g_ssec_byte = 0
  g_seg_byte  = 0
  g_num_nodes = 0
  g_root_node = 0

  col_top   = 0      // VEC W — topmost open row per column
  col_bot   = 0      // VEC W — bottommost open row per column
  cols_open = 0      // count of columns with col_top <= col_bot

  sky_col   = 0
  floor_col = 0

  px = 0
  py = 0
  pa = 0
  cam_z = 0
}

// ---------- byte helpers ----------

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

// ---------- map data accessors ----------

LET sd_sector(idx) =
  rd_i16_le(g_base, g_side_byte + idx * SIDEDEF_SIZE + SIDEDEF_SECTOR_OFS)

LET sec_floor(idx) =
  rd_i16_le(g_base, g_sec_byte + idx * SECTOR_SIZE + SECTOR_FLOOR_OFS)

LET sec_ceil(idx) =
  rd_i16_le(g_base, g_sec_byte + idx * SECTOR_SIZE + SECTOR_CEIL_OFS)

LET sec_light(idx) =
  rd_i16_le(g_base, g_sec_byte + idx * SECTOR_SIZE + SECTOR_LIGHT_OFS)

// Return 0 (front/right side) or 1 (back/left side) of partition.
// Doom's R_PointOnSide convention.
LET point_on_side(x, y, no) = VALOF
{ LET pxn = rd_i16_le(g_base, no + NODE_PX_OFS)
  LET pyn = rd_i16_le(g_base, no + NODE_PY_OFS)
  LET dxn = rd_i16_le(g_base, no + NODE_DX_OFS)
  LET dyn = rd_i16_le(g_base, no + NODE_DY_OFS)
  LET dx = x - pxn
  LET dy = y - pyn
  // left = dyn * dx ; right = dy * dxn
  // back side (1) when right >= left.
  IF dy * dxn < dyn * dx RESULTIS 0
  RESULTIS 1
}

// Recursive descent to find the subsector containing (x, y).
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

// Floor height of sector containing (x, y). Walks any front-side seg
// in the subsector; all segs share the same front sector.
LET floor_at(x, y) = VALOF
{ LET ssidx = point_in_subsector(x, y)
  LET se = g_ssec_byte + ssidx * SSECTOR_SIZE
  LET first_seg = rd_u16_le(g_base, se + SSECTOR_FIRST_OFS)
  LET seg = g_seg_byte + first_seg * SEG_SIZE
  LET ld = rd_u16_le(g_base, seg + SEG_LINE_OFS)
  LET sd = rd_u16_le(g_base, seg + SEG_SIDE_OFS)
  LET le = g_line_byte + ld * LINEDEF_SIZE
  LET sd_idx = sd = 0 -> rd_i16_le(g_base, le + LINEDEF_FRONT_OFS),
                         rd_i16_le(g_base, le + LINEDEF_BACK_OFS)
  IF sd_idx < 0 RESULTIS 0
  RESULTIS sec_floor(sd_sector(sd_idx))
}

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

// ---------- camera transforms ----------

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

// ---------- per-column clip + draw ----------

LET reset_clip() BE
{ FOR i = 0 TO W - 1 DO
  { col_top!i := 0
    col_bot!i := H - 1
  }
  cols_open := W
}

// Draw vertical span at column, clamped to clip window. Optionally
// shrink the window after the draw (used by solid walls and portal
// step closes). Returns nothing.
LET vline_clipped(col, y0, y1, c) BE
{ LET t = col_top!col
  LET b = col_bot!col
  IF y0 > y1 DO { LET tmp = y0; y0 := y1; y1 := tmp }
  IF y0 < t DO y0 := t
  IF y1 > b DO y1 := b
  IF y0 <= y1 DO
    sys(Sys_sdl, sdl_drawvline, surf, col, y0, y1, c)
}

LET close_column(col) BE
{ IF col_top!col <= col_bot!col DO cols_open := cols_open - 1
  col_top!col := H
  col_bot!col := -1
}

LET project_y(world_z, cy) =
  HORIZON - ((world_z - cam_z) * F_X) / cy

// ---------- seg rendering ----------

LET render_seg(seg_byte) BE
{ LET v1, v2 = 0, 0
  LET ld_idx, seg_side = 0, 0
  LET le, front_sd, back_sd = 0, 0, 0
  LET front_sec, back_sec = 0, 0
  LET v1x, v1y, v2x, v2y = 0, 0, 0, 0
  LET cx1, cy1, cx2, cy2 = 0, 0, 0, 0
  LET ff, fc, fl, bf, bc = 0, 0, 0, 0, 0
  LET two_sided = FALSE
  LET sx1, sx2, ix1, ix2 = 0, 0, 0, 0
  LET inv_z1, inv_z2, dx_span = 0, 0, 0
  LET wall_c, lower_c, upper_c = 0, 0, 0

  v1       := rd_u16_le(g_base, seg_byte + SEG_V1_OFS)
  v2       := rd_u16_le(g_base, seg_byte + SEG_V2_OFS)
  ld_idx   := rd_u16_le(g_base, seg_byte + SEG_LINE_OFS)
  seg_side := rd_u16_le(g_base, seg_byte + SEG_SIDE_OFS)
  le       := g_line_byte + ld_idx * LINEDEF_SIZE
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

  cx1 := cam_x(v1x, v1y); cy1 := cam_y(v1x, v1y)
  cx2 := cam_x(v2x, v2y); cy2 := cam_y(v2x, v2y)
  IF cy1 < NEAR & cy2 < NEAR RETURN

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

  IF sx1 > sx2 DO
  { LET tmp = sx1; sx1 := sx2; sx2 := tmp
    tmp := cx1; cx1 := cx2; cx2 := tmp
    tmp := cy1; cy1 := cy2; cy2 := tmp
  }
  IF sx1 = sx2 RETURN

  ix1 := sx1; ix2 := sx2
  IF ix1 < 0 DO ix1 := 0
  IF ix2 >= W DO ix2 := W - 1
  IF ix1 > ix2 RETURN

  inv_z1 := (1024 * 1024) / cy1
  inv_z2 := (1024 * 1024) / cy2
  dx_span := sx2 - sx1

  wall_c  := light_to_col(fl)
  lower_c := light_to_col(fl - 16)
  upper_c := light_to_col(fl - 32)

  FOR col_x = ix1 TO ix2 DO
  { LET t     = ((col_x - sx1) * 1024) / dx_span
    LET inv_z = inv_z1 + ((inv_z2 - inv_z1) * t) / 1024
    LET cy    = 0
    LET y_fc, y_cc, y_bf, y_bc = 0, 0, 0, 0
    IF inv_z <= 0 LOOP
    cy := (1024 * 1024) / inv_z

    y_fc := project_y(fc, cy)
    y_cc := project_y(ff, cy)

    // Ceiling band above front ceiling — anything in the current open
    // window above y_fc is "looking past" the wall top and shows the
    // ceiling flat (sky_col for the basic renderer). Without this the
    // top of every solid wall would leave HOM streaks.
    { LET top = col_top!col_x
      LET bot = col_bot!col_x
      IF top < y_fc DO
      { LET y1 = y_fc - 1
        IF y1 > bot DO y1 := bot
        IF top <= y1 DO
          sys(Sys_sdl, sdl_drawvline, surf, col_x, top, y1, sky_col)
        col_top!col_x := y_fc
      }
    }
    // Floor band below front floor — same idea below the wall.
    { LET top = col_top!col_x
      LET bot = col_bot!col_x
      IF bot > y_cc DO
      { LET y0 = y_cc + 1
        IF y0 < top DO y0 := top
        IF y0 <= bot DO
          sys(Sys_sdl, sdl_drawvline, surf, col_x, y0, bot, floor_col)
        col_bot!col_x := y_cc
      }
    }
    IF col_top!col_x > col_bot!col_x DO { close_column(col_x); LOOP }

    TEST two_sided
    THEN { y_bc := project_y(bc, cy)
           y_bf := project_y(bf, cy)
           IF bc < fc DO
           { vline_clipped(col_x, y_fc, y_bc, upper_c)
             IF y_bc + 1 > col_top!col_x DO col_top!col_x := y_bc + 1
             IF col_top!col_x > col_bot!col_x DO close_column(col_x)
           }
           IF bf > ff DO
           { vline_clipped(col_x, y_bf, y_cc, lower_c)
             IF y_bf - 1 < col_bot!col_x DO col_bot!col_x := y_bf - 1
             IF col_top!col_x > col_bot!col_x DO close_column(col_x)
           }
         }
    ELSE { vline_clipped(col_x, y_fc, y_cc, wall_c)
           close_column(col_x)
         }
  }
}

// ---------- BSP traversal ----------

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
  // BCPL's `&` inside an IF condition is a short-circuit logical AND
  // (the jumpcond optimisation in bcpltrn.b treats s_logand specially:
  // it tests each operand for truthiness independently rather than
  // evaluating the bitwise AND of the two values). So `IF n & FLAG DO`
  // fires whenever both n and FLAG are nonzero, regardless of the
  // actual bitwise overlap. Wrap in a compare-to-0 to force a real
  // bitwise evaluation.
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

// ---------- backdrop fill for leftover columns ----------

LET fill_remaining() BE
{ // For every still-open column, fill its sky band above HORIZON and
  // floor band below. Two single-vline calls per open column.
  FOR col_x = 0 TO W - 1 DO
  { LET t = col_top!col_x
    LET b = col_bot!col_x
    IF t > b LOOP
    IF t < HORIZON DO
    { LET y1 = b
      IF y1 >= HORIZON DO y1 := HORIZON - 1
      sys(Sys_sdl, sdl_drawvline, surf, col_x, t, y1, sky_col)
    }
    IF b >= HORIZON DO
    { LET y0 = t
      IF y0 < HORIZON DO y0 := HORIZON
      sys(Sys_sdl, sdl_drawvline, surf, col_x, y0, b, floor_col)
    }
  }
}

LET drawframe() BE
{ reset_clip()
  cam_z := floor_at(px, py) + EYE_H
  render_node(g_root_node)
  fill_remaining()
  sys(Sys_sdl, sdl_flip, surf)
}

// ---------- main ----------

LET start() = VALOF
{ LET info = VEC 3
  LET nbytes = 0
  LET numlumps, dirofs = 0, 0
  LET map_idx = 0
  LET vert_idx, line_idx, side_idx, sec_idx = 0, 0, 0, 0
  LET node_idx, ssec_idx, seg_idx, thing_idx = 0, 0, 0, 0
  LET things_byte, tsize, nsize = 0, 0, 0

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
  node_idx  := find_map_lump(g_base, dirofs, map_idx, numlumps, "NODES")
  ssec_idx  := find_map_lump(g_base, dirofs, map_idx, numlumps, "SSECTORS")
  seg_idx   := find_map_lump(g_base, dirofs, map_idx, numlumps, "SEGS")
  thing_idx := find_map_lump(g_base, dirofs, map_idx, numlumps, "THINGS")
  IF vert_idx<0 | line_idx<0 | side_idx<0 | sec_idx<0 |
     node_idx<0 | ssec_idx<0 | seg_idx<0 | thing_idx<0 DO
  { writef("Missing map lump.*n"); RESULTIS 1 }

  g_vert_byte := rd_u32_le(g_base, dirofs + vert_idx * DIR_ENTRY_SIZE + DIR_FILEPOS_OFS)
  g_line_byte := rd_u32_le(g_base, dirofs + line_idx * DIR_ENTRY_SIZE + DIR_FILEPOS_OFS)
  g_side_byte := rd_u32_le(g_base, dirofs + side_idx * DIR_ENTRY_SIZE + DIR_FILEPOS_OFS)
  g_sec_byte  := rd_u32_le(g_base, dirofs + sec_idx  * DIR_ENTRY_SIZE + DIR_FILEPOS_OFS)
  g_node_byte := rd_u32_le(g_base, dirofs + node_idx * DIR_ENTRY_SIZE + DIR_FILEPOS_OFS)
  nsize       := rd_u32_le(g_base, dirofs + node_idx * DIR_ENTRY_SIZE + DIR_SIZE_OFS)
  g_ssec_byte := rd_u32_le(g_base, dirofs + ssec_idx * DIR_ENTRY_SIZE + DIR_FILEPOS_OFS)
  g_seg_byte  := rd_u32_le(g_base, dirofs + seg_idx  * DIR_ENTRY_SIZE + DIR_FILEPOS_OFS)
  things_byte := rd_u32_le(g_base, dirofs + thing_idx * DIR_ENTRY_SIZE + DIR_FILEPOS_OFS)
  tsize       := rd_u32_le(g_base, dirofs + thing_idx * DIR_ENTRY_SIZE + DIR_SIZE_OFS)

  g_num_nodes := nsize / NODE_SIZE
  g_root_node := g_num_nodes - 1
  writef("nodes: %n  root=%n*n", g_num_nodes, g_root_node)

  sin_t := getvec(ANG)
  cos_t := getvec(ANG)
  buildtrig()

  col_top := getvec(W)
  col_bot := getvec(W)

  UNLESS find_player_start(g_base, things_byte, tsize) DO
  { writef("No player1 start; spawning at (0, 0).*n")
    px := 0; py := 0; pa := 0
  }
  writef("player start  px=%n py=%n pa=%n*n", px, py, pa)

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
  freevec(col_top); freevec(col_bot)
  writef("dbsp exited*n")
  RESULTIS 0
}
