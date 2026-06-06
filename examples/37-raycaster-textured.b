// 37-raycaster-textured: real texture lookup via the asset registry.
//
// Setup:
//   1. Open the Assets tab (left pane).
//   2. + asset, pick site/textures/brick.png (or stone.png, checker.png).
//   3. Compile & Run this file.
//
// What changed vs 36-raycaster-tex:
//   - sys(Sys_assetload, "brick.png", info) maps the decoded PNG into
//     wasm memory once. info!2 is a word address pointing at packed
//     0xRRGGBBAA texel words — one word per pixel.
//   - tex_sample is now a single indexed load: tbase!(texY*tw + texX).
//     The procedural brick pattern is gone; the texture file is the
//     pattern.
//   - N_BANDS = 64 so each band corresponds to one texture row.
//   - NS-side faces are dimmed via per-channel halving of the texel.
//
// Controls: W/A/S/D or arrows, Esc quits.

SECTION "raytx2"

GET "libhdr"
GET "sdl"

MANIFEST {
  W        = 960
  H        = 600
  MAP      = 8
  STRIDE   = 1
  ANG      = 8192
  FOV      = 1365         // ~60deg in 8192-tick units
  PROJ     = 900000       // tuned for DDA perpDist in /1024 units
  MAXSTEP  = 64           // DDA crosses one grid line per step

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
  wmap    = 0
  sin_t   = 0
  cos_t   = 0
  keys    = 0
  surf    = 0
  sky_c   = 0
  floor_c = 0
  running = 1
  tex_base = 0
  tex_w    = 0
  tex_h    = 0
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

// DDA grid traversal. Every iteration advances to the next grid line
// along whichever axis is closer along the ray. No marching, no
// missed cells, exact face detection.
//
//   res!0 = perpendicular distance (1024 = 1 cell of ray length)
//   res!1 = side hit (0 = vertical face, 1 = horizontal face)
//   res!2 = wallX (0..1023) — fractional position along the wall face
LET cast(px, py, angle, res) BE
{ // BCPL requires all LET declarations at the top of a block.
  LET dx     = cos_t!(angle & (ANG-1))   // dirX * 1024
  LET dy     = sin_t!(angle & (ANG-1))   // dirY * 1024
  LET adx    = ABS dx
  LET ady    = ABS dy
  LET deltaX = 0
  LET deltaY = 0
  LET mapX   = px / 1024
  LET mapY   = py / 1024
  LET stepX  = dx < 0 -> -1, 1
  LET stepY  = dy < 0 -> -1, 1
  LET sideX  = 0
  LET sideY  = 0
  LET side   = 0
  IF adx = 0 DO adx := 1
  IF ady = 0 DO ady := 1
  // deltaX / deltaY = ray length (in /1024 cell units) needed to
  // cross one full cell along the corresponding axis.
  deltaX := (1024 * 1024) / adx
  deltaY := (1024 * 1024) / ady
  // Distance from current position to the first grid line along
  // each axis, scaled by deltaX/deltaY to give "ray length".
  TEST dx < 0
  THEN sideX := ((px - mapX * 1024) * deltaX) / 1024
  ELSE sideX := ((mapX * 1024 + 1024 - px) * deltaX) / 1024
  TEST dy < 0
  THEN sideY := ((py - mapY * 1024) * deltaY) / 1024
  ELSE sideY := ((mapY * 1024 + 1024 - py) * deltaY) / 1024
  FOR step = 1 TO MAXSTEP DO
  { TEST sideX < sideY
    THEN { sideX := sideX + deltaX; mapX := mapX + stepX; side := 0 }
    ELSE { sideY := sideY + deltaY; mapY := mapY + stepY; side := 1 }
    IF mapX < 0 | mapX >= MAP | mapY < 0 | mapY >= MAP DO
    { res!0 := 1024 * MAP; res!1 := side; res!2 := 0; RETURN }
    IF wmap!(mapY * MAP + mapX) DO
    { LET perp = side = 0 -> sideX - deltaX, sideY - deltaY
      LET wallX = 0
      // Compute fractional hit position on the wall face.
      TEST side = 0
      THEN { LET rayY = py + (perp * dy) / 1024
             wallX := rayY - (rayY / 1024) * 1024
           }
      ELSE { LET rayX = px + (perp * dx) / 1024
             wallX := rayX - (rayX / 1024) * 1024
           }
      IF wallX < 0 DO wallX := wallX + 1024
      res!0 := perp
      res!1 := side
      res!2 := wallX
      // Stash ray direction signs in result slots 3 & 4 so the caller
      // can flip texX correctly for back-facing wall faces.
      res!3 := dx
      res!4 := dy
      RETURN
    }
  }
  res!0 := 1024 * MAP; res!1 := 0; res!2 := 0
}

LET drawframe(px, py, pa) BE
{ LET res = VEC 5
  sys(Sys_sdl, sdl_drawfillrect, surf, 0,   0,   W, H/2, sky_c)
  sys(Sys_sdl, sdl_drawfillrect, surf, 0, H/2,   W,   H, floor_c)

  FOR col = 0 TO W - 1 BY STRIDE DO
  { LET dA, rayA, perp, side, wX = 0, 0, 0, 0, 0
    LET dperp, h, top = 0, 0, 0
    LET texX, rdx, rdy = 0, 0, 0
    dA   := (col - W/2) * FOV / W
    rayA := pa + dA
    cast(px, py, rayA, res)
    perp := res!0
    side := res!1
    wX   := res!2
    rdx  := res!3
    rdy  := res!4
    // Fisheye correction: perp is Euclidean ray length; multiply by
    // cos(angle delta) to get camera-perpendicular distance.
    dperp := (perp * cos_t!(dA & (ANG-1))) / 1024
    IF dperp < 1 DO dperp := 1
    // No clamp on h. The runtime clips drawing to the canvas, but the
    // texY mapping inside Sys_drawtexcol uses the UNCLAMPED h so the
    // texture stays at correct scale even when the wall is so close
    // it would span far more than H pixels.
    h := PROJ / dperp
    top := (H - h) / 2
    texX := (wX * tex_w) / 1024
    // Mirror texX on back-facing wall sides so the texture orientation
    // is consistent around a room.
    TEST side = 0
    THEN IF rdx > 0 DO texX := tex_w - 1 - texX
    ELSE IF rdy < 0 DO texX := tex_w - 1 - texX
    sys(Sys_drawtexcol, col, top, h, texX, tex_base, tex_w, tex_h, side)
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
  LET info = VEC 3

  wmap := TABLE
    1, 1, 1, 1, 1, 1, 1, 1,
    1, 0, 0, 0, 1, 0, 0, 1,
    1, 0, 1, 0, 0, 0, 0, 1,
    1, 0, 1, 1, 1, 1, 0, 1,
    1, 0, 0, 0, 0, 1, 0, 1,
    1, 0, 1, 1, 0, 1, 0, 1,
    1, 0, 1, 0, 0, 0, 0, 1,
    1, 1, 1, 1, 1, 1, 1, 1

  // Try each known sample texture; first hit wins. Upload via the
  // Assets tab before running. With no asset present, fall back to
  // a flat orange so the user sees rendering still works.
  UNLESS sys(Sys_assetload, "brick.png", info) DO
    UNLESS sys(Sys_assetload, "stone.png", info) DO
      UNLESS sys(Sys_assetload, "checker.png", info) DO
      { writef("No texture asset uploaded. Add one via the Assets tab.*n")
        info!0 := 1; info!1 := 1; info!2 := 0
      }

  tex_w    := info!0
  tex_h    := info!1
  tex_base := info!2

  sys(Sys_sdl, sdl_init)
  surf := sys(Sys_sdl, sdl_setvideomode, W, H, 0, 0)

  sky_c   := sys(Sys_sdl, sdl_maprgb, 0,  60, 120, 200)
  floor_c := sys(Sys_sdl, sdl_maprgb, 0,  50,  50,  50)

  sin_t := getvec(ANG)
  cos_t := getvec(ANG)
  keys  := getvec(KEYCAP)
  FOR i = 0 TO KEYCAP DO keys!i := 0
  buildtrig()

  writef("texture %nx%n at base %n*n", tex_w, tex_h, tex_base)

  WHILE running DO
  { LET fwd = 0
    LET turn = 0

    poll_events()

    IF key_down(K_W) | key_down(K_UP)    DO fwd  := fwd  + 1
    IF key_down(K_S) | key_down(K_DOWN)  DO fwd  := fwd  - 1
    IF key_down(K_A) | key_down(K_LEFT)  DO turn := turn - 64
    IF key_down(K_D) | key_down(K_RIGHT) DO turn := turn + 64

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
  writef("raytex2 exited*n")
  RESULTIS 0
}
