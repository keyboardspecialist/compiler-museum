// 41-doom-mapnav: 40's static map view + a player marker placed at the
// THING type-1 (player1 start) lump, with WASD/arrow controls. Lays
// the camera transform code that the 3D wall renderer will reuse.
//
// Setup: same as 40 — upload a WAD via Assets, Compile & Run.
//
// New vs 40:
//   - Parse THINGS lump (10 bytes per entry).
//   - Spawn at first type-1 (player1 start). Store px, py in world
//     units; pa in our 8192-tick angle space (Doom's degrees → ticks).
//   - WASD / arrows move forward/back along facing, turn left/right.
//   - Player drawn as a small dot with a facing line, projected with
//     the same scale used for the linedefs.
//
// Esc quits.

SECTION "dnav"

GET "libhdr"
GET "sdl"

MANIFEST {
  W       = 960
  H       = 720
  MARGIN  = 32

  HDR_NUMLUMPS_OFS =  4
  HDR_INFOOFS_OFS  =  8
  HDR_SIZE         = 12
  DIR_ENTRY_SIZE   = 16
  DIR_FILEPOS_OFS  =  0
  DIR_SIZE_OFS     =  4
  DIR_NAME_OFS     =  8

  VERTEX_SIZE  = 4
  LINEDEF_SIZE = 14
  THING_SIZE   = 10
  THING_X_OFS    = 0
  THING_Y_OFS    = 2
  THING_ANG_OFS  = 4
  THING_TYPE_OFS = 6

  ANG     = 8192             // ticks per full circle (matches raycasters)
  MOVE    = 16               // world units per frame at full throttle
  TURN    = 64               // ticks per frame at full turn rate

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
  bg_col       = 0
  wall_col     = 0
  twosided_col = 0
  player_col   = 0
  facing_col   = 0

  sin_t = 0
  cos_t = 0

  // Map-projection params, computed once.
  min_x = 0
  min_y = 0
  scale_1024 = 1024
  off_x = 0
  off_y = 0

  // Persisted WAD pointers so the render loop doesn't keep redoing
  // the dir lookup.
  g_base      = 0
  g_vert_byte = 0
  g_line_byte = 0
  g_nverts    = 0
  g_nlines    = 0

  // Player state.
  px = 0
  py = 0
  pa = 0
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

// ---------- trig table ----------

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

// ---------- THINGS parsing ----------

// Scan THINGS for the first player1 start (type = 1). Loads (px, py)
// in world coords and pa in our 8192-tick angle space (Doom stores
// angle in degrees, so tick = deg * ANG / 360). Returns TRUE on hit.
LET find_player_start(base, things_byte, tsize) = VALOF
{ LET n = tsize / THING_SIZE
  FOR i = 0 TO n - 1 DO
  { LET o = things_byte + i * THING_SIZE
    LET tp = rd_u16_le(base, o + THING_TYPE_OFS)
    IF tp = 1 DO
    { LET deg = rd_u16_le(base, o + THING_ANG_OFS)
      px := rd_i16_le(base, o + THING_X_OFS)
      py := rd_i16_le(base, o + THING_Y_OFS)
      pa := (deg * ANG) / 360
      pa := pa & (ANG - 1)
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

// ---------- projection ----------

LET project_x(wx) = ((wx - min_x) * scale_1024) / 1024 + off_x
LET project_y(wy) = H - (((wy - min_y) * scale_1024) / 1024 + off_y)

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
  IF max_x = min_x DO max_x := min_x + 1
  IF max_y = min_y DO max_y := min_y + 1
  sx_1024 := ((W - 2 * MARGIN) * 1024) / (max_x - min_x)
  sy_1024 := ((H - 2 * MARGIN) * 1024) / (max_y - min_y)
  scale_1024 := sx_1024 < sy_1024 -> sx_1024, sy_1024
  off_x := MARGIN + ((W - 2 * MARGIN) - ((max_x - min_x) * scale_1024) / 1024) / 2
  off_y := MARGIN + ((H - 2 * MARGIN) - ((max_y - min_y) * scale_1024) / 1024) / 2
}

// ---------- render ----------

LET drawmap_lines() BE
{ FOR i = 0 TO g_nlines - 1 DO
  { LET le  = g_line_byte + i * LINEDEF_SIZE
    LET v1  = rd_u16_le(g_base, le + 0)
    LET v2  = rd_u16_le(g_base, le + 2)
    LET back = rd_u16_le(g_base, le + 12)
    LET ve1 = g_vert_byte + v1 * VERTEX_SIZE
    LET ve2 = g_vert_byte + v2 * VERTEX_SIZE
    LET x1 = rd_i16_le(g_base, ve1 + 0)
    LET y1 = rd_i16_le(g_base, ve1 + 2)
    LET x2 = rd_i16_le(g_base, ve2 + 0)
    LET y2 = rd_i16_le(g_base, ve2 + 2)
    LET col = back = #xFFFF -> wall_col, twosided_col
    sys(Sys_sdl, sdl_drawline, surf,
        project_x(x1), project_y(y1),
        project_x(x2), project_y(y2),
        col)
  }
}

LET drawplayer() BE
{ LET sx, sy = 0, 0
  LET dx, dy = 0, 0
  LET tipx, tipy = 0, 0
  LET facing_len = 0
  sx := project_x(px)
  sy := project_y(py)
  // Small filled rect for the player position dot. sdl_drawfillrect
  // takes (x1, y1, x2, y2) corners, not (x, y, w, h).
  sys(Sys_sdl, sdl_drawfillrect, surf, sx - 3, sy - 3, sx + 3, sy + 3, player_col)
  // Facing line in world units, scaled to projection units. Length
  // chosen so it's visible at typical scales.
  facing_len := 48
  dx := (cos_t!(pa & (ANG - 1)) * facing_len) / 1024
  dy := (sin_t!(pa & (ANG - 1)) * facing_len) / 1024
  // Doom Y up + canvas Y down -> our project_y already flips, so we
  // subtract a projected delta rather than building world tip first.
  tipx := project_x(px + dx)
  tipy := project_y(py + dy)
  sys(Sys_sdl, sdl_drawline, surf, sx, sy, tipx, tipy, facing_col)
}

LET drawframe() BE
{ sys(Sys_sdl, sdl_drawfillrect, surf, 0, 0, W, H, bg_col)
  drawmap_lines()
  drawplayer()
  sys(Sys_sdl, sdl_flip, surf)
}

// ---------- main ----------

LET start() = VALOF
{ LET info = VEC 3
  LET nbytes = 0
  LET numlumps, dirofs = 0, 0
  LET map_idx = 0
  LET vert_idx, line_idx, thing_idx = 0, 0, 0
  LET things_byte, tsize = 0, 0
  LET vsize, lsize = 0, 0

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
  thing_idx := find_map_lump(g_base, dirofs, map_idx, numlumps, "THINGS")
  IF vert_idx < 0 | line_idx < 0 | thing_idx < 0 DO
  { writef("Missing required map lump (vert=%n line=%n thing=%n).*n",
           vert_idx, line_idx, thing_idx)
    RESULTIS 1
  }

  g_vert_byte := rd_u32_le(g_base, dirofs + vert_idx * DIR_ENTRY_SIZE + DIR_FILEPOS_OFS)
  vsize       := rd_u32_le(g_base, dirofs + vert_idx * DIR_ENTRY_SIZE + DIR_SIZE_OFS)
  g_line_byte := rd_u32_le(g_base, dirofs + line_idx * DIR_ENTRY_SIZE + DIR_FILEPOS_OFS)
  lsize       := rd_u32_le(g_base, dirofs + line_idx * DIR_ENTRY_SIZE + DIR_SIZE_OFS)
  things_byte := rd_u32_le(g_base, dirofs + thing_idx * DIR_ENTRY_SIZE + DIR_FILEPOS_OFS)
  tsize       := rd_u32_le(g_base, dirofs + thing_idx * DIR_ENTRY_SIZE + DIR_SIZE_OFS)
  g_nverts := vsize / VERTEX_SIZE
  g_nlines := lsize / LINEDEF_SIZE

  compute_scale(g_base, g_vert_byte, g_nverts)

  sin_t := getvec(ANG)
  cos_t := getvec(ANG)
  buildtrig()

  UNLESS find_player_start(g_base, things_byte, tsize) DO
  { writef("No player-1 start (THING type 1) in this map.*n")
    // Fall back to bbox centre with default angle.
    px := (min_x + ((W - 2*MARGIN) * 1024 / scale_1024) / 2)
    py := (min_y + ((H - 2*MARGIN) * 1024 / scale_1024) / 2)
    pa := 0
  }
  writef("player start  px=%n py=%n pa=%n (deg=%n)*n",
         px, py, pa, (pa * 360) / ANG)

  sys(Sys_sdl, sdl_init)
  surf := sys(Sys_sdl, sdl_setvideomode, W, H, 0, 0)

  bg_col       := sys(Sys_sdl, sdl_maprgb, 0,  20,  20,  20)
  wall_col     := sys(Sys_sdl, sdl_maprgb, 0, 240, 220, 180)
  twosided_col := sys(Sys_sdl, sdl_maprgb, 0,  90,  90, 110)
  player_col   := sys(Sys_sdl, sdl_maprgb, 0, 255,  64,  64)
  facing_col   := sys(Sys_sdl, sdl_maprgb, 0, 255, 200,  80)

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
    { LET dx = (cos_t!(pa & (ANG - 1)) * MOVE * fwd) / 1024
      LET dy = (sin_t!(pa & (ANG - 1)) * MOVE * fwd) / 1024
      px := px + dx
      py := py + dy
    }
    IF turn ~= 0 DO pa := (pa + turn) & (ANG - 1)

    drawframe()
    delay(16)
  }

  freevec(sin_t); freevec(cos_t); freevec(keys)
  writef("dnav exited*n")
  RESULTIS 0
}
