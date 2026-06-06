// 36-raycaster-tex: higher-resolution raycaster with the texture-
// mapping pipeline scaffolded in.
//
// Versus 35-raycaster:
//   - STRIDE = 1   (one ray per pixel column)
//   - Cast returns (perpendicular distance, side, wallX) so the
//     renderer knows which wall face was hit AND where along that
//     face the ray landed. Those are the two coordinates a texture
//     sampler needs.
//   - Each column draws as multiple vertical bands instead of one
//     solid fillrect. Each band corresponds to a "row" of texels.
//     For now the texture is procedural (brick + mortar from
//     position), but the loop is the one a real texture sampler
//     will slot into.
//
// Controls: W/A/S/D or arrow keys, ESC quits.

SECTION "raytex"

GET "libhdr"
GET "sdl"

MANIFEST {
  W        = 960
  H        = 600
  MAP      = 8
  STRIDE   = 1
  ANG      = 1024
  FOV      = 171
  PROJ     = 22000
  MARCH_DV = 64           // 1/MARCH_DV cell per ray step
  MAXSTEP  = 2048
  TEX_W    = 64           // virtual texel pitch along wall face
  TEX_H    = 64           // virtual texel pitch up the wall
  N_BANDS  = 48           // texY samples per column

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
  wmap   = 0
  sin_t  = 0
  cos_t  = 0
  keys   = 0
  surf   = 0
  sky_c  = 0
  floor_c = 0
  running = 1
}

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

LET fcos(x) = VALOF
{ LET pi2 = 0
  pi2 #:= 1.5707963267948966
  RESULTIS fsin(x #+ pi2)
}

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

// March until a wall cell is entered. Records:
//   res!0 = step count along the ray (proportional to distance)
//   res!1 = side: 0 if a vertical (E/W) face was crossed last, 1 if
//                 a horizontal (N/S) face. Determines which axis the
//                 wallX coordinate runs along.
//   res!2 = wallX in 0..1023 (position along the hit cell's face).
//
// wallX + side + texture-row index = enough to look up a texel
// once a real texture exists.
LET cast(px, py, angle, res) BE
{ LET dx   = cos_t!(angle & (ANG-1))
  LET dy   = sin_t!(angle & (ANG-1))
  LET ix   = dx / MARCH_DV
  LET iy   = dy / MARCH_DV
  LET x    = px
  LET y    = py
  LET cx   = x / 1024
  LET cy   = y / 1024
  LET pcx  = cx
  LET pcy  = cy
  LET side = 0
  LET wX   = 0
  FOR step = 1 TO MAXSTEP DO
  { pcx := cx
    pcy := cy
    x := x + ix
    y := y + iy
    cx := x / 1024
    cy := y / 1024
    UNLESS cx = pcx & cy = pcy DO
    { // entered a new grid cell — determine which axis crossed
      TEST cx ~= pcx
      THEN side := 0    // vertical face (east/west of last cell)
      ELSE side := 1    // horizontal face (north/south)

      IF cx < 0 | cx >= MAP | cy < 0 | cy >= MAP DO
      { res!0 := step; res!1 := side; res!2 := 0; RETURN }

      IF wmap!(cy*MAP+cx) DO
      { // Position along the hit wall face, in 0..1023 cell units.
        TEST side = 0
        THEN wX := y - cy * 1024
        ELSE wX := x - cx * 1024
        IF wX < 0 DO wX := wX + 1024
        res!0 := step; res!1 := side; res!2 := wX
        RETURN
      }
    }
  }
  res!0 := MAXSTEP; res!1 := 0; res!2 := 0
}

// Procedural "brick" texture sampler. tx, ty in 0..TEX_W-1, 0..TEX_H-1.
// Returns 0 for mortar, 1 for brick. Real texture mapping replaces
// this with an indexed lookup into a texel array.
LET tex_sample(tx, ty) = VALOF
{ LET brickH = 16            // pixels tall per brick row
  LET brickW = 32            // pixels wide per brick
  LET row    = ty / brickH
  LET shift  = (row & 1) * (brickW / 2)
  LET col    = (tx + shift) / brickW
  // Mortar lines: top of each row OR vertical seam between bricks.
  IF (ty REM brickH) = 0 RESULTIS 0
  IF ((tx + shift) REM brickW) = 0 RESULTIS 0
  RESULTIS 1
}

// Pack a colour from base value `v` (0..255 brightness) with side
// dimming and brick/mortar split.
LET wall_color(v, side, is_brick) = VALOF
{ LET r = v
  LET g = v / 2
  LET b = v / 4
  IF side DO { r := r * 3 / 4; g := g * 3 / 4; b := b * 3 / 4 }
  UNLESS is_brick DO { r := r / 3; g := g / 3; b := b / 3 }
  RESULTIS sys(Sys_sdl, sdl_maprgb, 0, r, g, b)
}

LET drawframe(px, py, pa) BE
{ LET res = VEC 3
  // Sky + floor first.
  sys(Sys_sdl, sdl_drawfillrect, surf, 0,   0,   W, H/2, sky_c)
  sys(Sys_sdl, sdl_drawfillrect, surf, 0, H/2,   W,   H, floor_c)

  FOR col = 0 TO W - 1 BY STRIDE DO
  { LET dA, rayA, d, side, wX = 0, 0, 0, 0, 0
    LET dperp, h, top, vbase = 0, 0, 0, 0
    LET texX = 0
    dA   := (col - W/2) * FOV / W
    rayA := pa + dA
    cast(px, py, rayA, res)
    d     := res!0
    side  := res!1
    wX    := res!2
    dperp := (d * cos_t!(dA & (ANG-1))) / 1024
    IF dperp < 1 DO dperp := 1
    h := PROJ / dperp
    IF h > H DO h := H
    top  := (H - h) / 2

    // Texture X coordinate is the wallX along the hit face, mapped
    // into 0..TEX_W-1.
    texX := (wX * TEX_W) / 1024

    // Base brightness — closer wall, brighter.
    vbase := 230 - dperp
    IF vbase < 32 DO vbase := 32

    // Split the wall slice into N_BANDS texY bands. Each band gets
    // its own colour based on tex_sample(texX, texY). One drawfillrect
    // per band — N_BANDS calls per column instead of H pixels.
    FOR band = 0 TO N_BANDS - 1 DO
    { LET texY  = (band * TEX_H) / N_BANDS
      LET y1   = top + (band * h) / N_BANDS
      LET y2   = top + ((band + 1) * h) / N_BANDS
      LET is_brick = tex_sample(texX, texY)
      LET c        = wall_color(vbase, side, is_brick)
      sys(Sys_sdl, sdl_drawfillrect, surf, col, y1, col + STRIDE, y2, c)
    }
  }
  sys(Sys_sdl, sdl_flip, surf)
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
{ LET px = 1 * 1024 + 512
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
  writef("raytex exited*n")
  RESULTIS 0
}
