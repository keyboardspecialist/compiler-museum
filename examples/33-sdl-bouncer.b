// 33-sdl-bouncer: animated SDL graphics demo.
//
// Concepts:
//   - sys(Sys_sdl, sdl_init) opens the canvas pane.
//   - sys(Sys_sdl, sdl_setvideomode, w, h, 0, 0) returns a surface
//     handle (use 1).
//   - sys(Sys_sdl, sdl_maprgb, 0, r, g, b) packs a colour int.
//   - delay(ms) is a real yield: Asyncify suspends, the JS scheduler
//     awaits the timer, then resumes — letting the canvas repaint
//     between frames so you see motion (without it the loop is
//     synchronous and only the final frame appears).

SECTION "sdlb"

GET "libhdr"
GET "sdl"

LET start() = VALOF
{ LET surf = ?
  LET black = ?
  LET red   = ?
  LET green = ?
  LET x = 40
  LET y = 30
  LET dx = 3
  LET dy = 2
  LET W = 320
  LET H = 240
  LET frames = 250

  sys(Sys_sdl, sdl_init)
  surf  := sys(Sys_sdl, sdl_setvideomode, W, H, 0, 0)
  black := sys(Sys_sdl, sdl_maprgb, 0,   0,   0,   0)
  red   := sys(Sys_sdl, sdl_maprgb, 0, 240,  60,  60)
  green := sys(Sys_sdl, sdl_maprgb, 0,  80, 220, 120)

  FOR i = 1 TO frames DO
  { sys(Sys_sdl, sdl_fillsurf, surf, black)
    sys(Sys_sdl, sdl_drawfillcircle, surf, x, y, 12, red)
    sys(Sys_sdl, sdl_drawrect, surf, 0, 0, W-1, H-1, green)
    sys(Sys_sdl, sdl_flip, surf)
    delay(16)        // ~60 fps yield to browser
    x := x + dx
    y := y + dy
    IF x < 12  | x > W - 12 DO dx := -dx
    IF y < 12  | y > H - 12 DO dy := -dy
  }

  writef("done %n frames*n", frames)
  RESULTIS 0
}
