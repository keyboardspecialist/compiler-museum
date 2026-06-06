// 35-raycaster: Wolfenstein-style flat-shaded raycaster.
//
// Controls:
//   W / ArrowUp     walk forward
//   S / ArrowDown   walk backward
//   A / ArrowLeft   turn left
//   D / ArrowRight  turn right
//   Esc             quit
//
// Click the canvas first so it has focus, then keys reach the demo.
//
// Concepts:
//   - 8x8 wall grid stored as a TABLE of 0/1.
//   - Player position in 1024-per-cell fixed-point.
//   - Per-column ray cast by marching in 1/32-cell steps until a wall
//     cell is entered.
//   - Wall slice height = projection_constant / hit_distance.
//   - Flat shading by distance (no texture mapping yet).
//   - sin/cos baked at startup into 1024-entry fixed-point tables via
//     a BCPL Taylor implementation.
//   - sdl_pollevent drives a real game loop: events update a key-down
//     bitmap each frame, movement reads that bitmap.
//   - delay() yields to the browser between frames so the canvas
//     repaints.

SECTION "raycast"

GET "libhdr"
GET "sdl"

MANIFEST {
  W        = 320
  H        = 240
  MAP      = 8
  STRIDE   = 2
  ANG      = 1024
  FOV      = 171         // ~60 degrees
  PROJ     = 7000        // height projection
  STEP_DIV = 32          // ray-march granularity per cell

  KEYCAP   = 512         // size of key-state vector

  // Browser keyCode constants the runtime forwards to BCPL.
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
  wmap   = 0
  sin_t  = 0
  cos_t  = 0
  keys   = 0
  surf   = 0
  sky_c  = 0
  floor_c = 0
  running = 1
}

// Taylor sin, |x| <= pi after range reduction.
LET fsin(x) = VALOF
{ LET pi, twopi, x2, t, s = 0, 0, 0, 0, 0
  pi    #:= 3.14159265358979
  twopi #:= 2.0 #* pi
  WHILE x #>  pi DO x #:= x #- twopi
  WHILE x #<  0.0 #- pi DO x #:= x #+ twopi
  x2 #:= x #* x
  t  #:= x
  s  #:= t
  t #:= 0.0 #- (t #* x2) #/ 6.0;   s #:= s #+ t
  t #:= 0.0 #- (t #* x2) #/ 20.0;  s #:= s #+ t
  t #:= 0.0 #- (t #* x2) #/ 42.0;  s #:= s #+ t
  t #:= 0.0 #- (t #* x2) #/ 72.0;  s #:= s #+ t
  RESULTIS s
}

LET fcos(x) = VALOF
{ LET pi2 = 0
  pi2 #:= 1.5707963267948966
  RESULTIS fsin(x #+ pi2)
}

LET buildtrig() BE
{ LET a, step, sv, cv = 0, 0, 0, 0
  a    #:= 0.0
  step #:= (2.0 #* 3.14159265358979) #/ 1024.0
  FOR i = 0 TO 1023 DO
  { sv #:= fsin(a) #* 1024.0
    cv #:= fcos(a) #* 1024.0
    sin_t!i := FIX sv
    cos_t!i := FIX cv
    a #:= a #+ step
  }
}

LET cast(px, py, angle) = VALOF
{ LET dx = cos_t!(angle & (ANG-1))
  LET dy = sin_t!(angle & (ANG-1))
  LET ix = dx / STEP_DIV
  LET iy = dy / STEP_DIV
  LET x = px
  LET y = py
  FOR step = 1 TO 1024 DO
  { x := x + ix
    y := y + iy
    { LET cx = x / 1024
      LET cy = y / 1024
      IF cx < 0 | cx >= MAP | cy < 0 | cy >= MAP RESULTIS step
      IF wmap!(cy * MAP + cx) RESULTIS step
    }
  }
  RESULTIS 1024
}

LET shade(d) = VALOF
{ LET v = 230 - d
  IF v < 32 DO v := 32
  RESULTIS sys(Sys_sdl, sdl_maprgb, 0, v, v / 2, v / 4)
}

LET drawframe(px, py, pa) BE
{ // sdl_drawfillrect takes two CORNERS (x1, y1, x2, y2, col) in the
  // browser runtime — width/height would be the wrong interpretation
  // and produce zero-area strips.
  sys(Sys_sdl, sdl_drawfillrect, surf, 0,   0,   W, H/2, sky_c)
  sys(Sys_sdl, sdl_drawfillrect, surf, 0, H/2,   W,   H, floor_c)

  FOR col = 0 TO W - 1 BY STRIDE DO
  { // dA = ray offset from player heading. dperp = d * cos(dA) is
    // the perpendicular distance to the wall — projecting that
    // keeps verticals straight in screen space (no fisheye bulge).
    // All LETs must come before commands in a BCPL block, so the
    // assignments interleave instead of using IF-clamp.
    LET dA    = (col - W/2) * FOV / W
    LET rayA  = pa + dA
    LET d     = cast(px, py, rayA)
    LET dperp = (d * cos_t!(dA & (ANG-1))) / 1024
    LET h     = 0
    LET top   = 0
    IF dperp < 1 DO dperp := 1
    h := PROJ / dperp
    IF h > H DO h := H
    top := (H - h) / 2
    sys(Sys_sdl, sdl_drawfillrect,
        surf, col, top, col + STRIDE, top + h, shade(dperp))
  }
  sys(Sys_sdl, sdl_flip, surf)
}

// Drain all queued SDL events, mirroring keydown/up into the keys[]
// bitmap. ESC sets `running` to 0 so the main loop can exit.
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

// Try to advance the player by (mx, my). Refuse if the destination cell
// is a wall. Sliding-along-walls is approximated by trying X and Y
// axes independently, which is the classic Wolfenstein trick.
LET try_move(px_lv, py_lv, mx, my) BE
{ LET nx = !px_lv + mx
  LET cx = nx / 1024
  LET cy = !py_lv / 1024
  UNLESS cx < 0 | cx >= MAP | cy < 0 | cy >= MAP | wmap!(cy*MAP+cx) DO
    !px_lv := nx
  { LET ny = !py_lv + my
    LET cx2 = !px_lv / 1024
    LET cy2 = ny / 1024
    UNLESS cx2 < 0 | cx2 >= MAP | cy2 < 0 | cy2 >= MAP | wmap!(cy2*MAP+cx2) DO
      !py_lv := ny
  }
}

LET start() = VALOF
{ // Map row 5 col 3 is a wall — bug in earlier draft. Cell (1, 1) is
  // open. Coordinates are (cell * 1024 + 512) for cell-centre origin.
  LET px = 1 * 1024 + 512
  LET py = 1 * 1024 + 512
  LET pa = 0

  wmap := TABLE
    1, 1, 1, 1, 1, 1, 1, 1,
    1, 0, 0, 0, 1, 0, 0, 1,
    1, 0, 1, 0, 0, 0, 0, 1,
    1, 0, 1, 1, 1, 1, 0, 1,
    1, 0, 0, 0, 0, 1, 0, 1,
    1, 0, 1, 1, 0, 1, 0, 1,
    1, 0, 1, 0, 0, 0, 0, 1,
    1, 1, 1, 1, 1, 1, 1, 1

  sys(Sys_sdl, sdl_init)
  surf := sys(Sys_sdl, sdl_setvideomode, W, H, 0, 0)

  sky_c   := sys(Sys_sdl, sdl_maprgb, 0,  60, 120, 200)
  floor_c := sys(Sys_sdl, sdl_maprgb, 0,  50,  50,  50)

  sin_t := getvec(ANG)
  cos_t := getvec(ANG)
  keys  := getvec(KEYCAP)
  FOR i = 0 TO KEYCAP DO keys!i := 0
  buildtrig()

  WHILE running DO
  { LET fwd = 0
    LET turn = 0

    poll_events()

    IF key_down(K_W) | key_down(K_UP)    DO fwd  := fwd  + 1
    IF key_down(K_S) | key_down(K_DOWN)  DO fwd  := fwd  - 1
    IF key_down(K_A) | key_down(K_LEFT)  DO turn := turn - 8
    IF key_down(K_D) | key_down(K_RIGHT) DO turn := turn + 8

    IF fwd ~= 0 DO
    { LET dx = (cos_t!(pa & (ANG-1)) * fwd) / 16
      LET dy = (sin_t!(pa & (ANG-1)) * fwd) / 16
      try_move(@px, @py, dx, dy)
    }

    IF turn ~= 0 DO pa := (pa + turn) & (ANG-1)

    drawframe(px, py, pa)
    delay(16)
  }

  freevec(sin_t)
  freevec(cos_t)
  freevec(keys)
  writef("raycaster exited*n")
  RESULTIS 0
}
