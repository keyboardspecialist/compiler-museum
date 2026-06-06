// Minimal sdl.h for the BCPL-wasm playground. Only manifests the
// Sys_sdl sub-opcodes implemented by site/runtime.js. Programs use
//   sys(Sys_sdl, sdl_drawline, surf, x1, y1, x2, y2, col)
// directly. The full cintsys g/sdl.h ships its own BCPL wrappers
// (mkscreen, setcolour, draw, ...) — to keep the playground bundle
// small, that layer is omitted; users wrap helpers themselves.

MANIFEST {
  // Sys_sdl is already defined in libhdr.h (= 66).

  // Lifecycle.
  sdl_avail            = 0
  sdl_init             = 1
  sdl_setvideomode     = 2
  sdl_quit             = 3

  // Surface management (locks are no-ops in canvas; surfaces beyond
  // the primary screen are stubbed).
  sdl_locksurface      = 4
  sdl_unlocksurface    = 5

  // Display + events.
  sdl_delay            = 14
  sdl_flip             = 15
  sdl_waitevent        = 17
  sdl_pollevent        = 18
  sdl_getmousestate    = 19
  sdl_wm_setcaption    = 22

  // Colours: pack r,g,b into an int the draw ops accept.
  sdl_maprgb           = 24

  // Drawing primitives. Each takes a surface ptr first argument; pass
  // 1 (or whatever surf handle setvideomode returned).
  sdl_drawline         = 27
  sdl_drawhline        = 28
  sdl_drawvline        = 29
  sdl_drawcircle       = 30
  sdl_drawrect         = 31
  sdl_drawpixel        = 32
  sdl_drawellipse      = 33
  sdl_drawfillellipse  = 34
  sdl_drawfillcircle   = 37
  sdl_drawfillrect     = 38
  sdl_fillrect         = 39
  sdl_fillsurf         = 40

  // Timing.
  sdl_getticks         = 50

  // Cursor.
  sdl_showcursor       = 51
  sdl_hidecursor       = 52

  // Event types delivered via sdl_pollevent's vector slot 0.
  sdle_active          = 1
  sdle_keydown         = 2
  sdle_keyup           = 3
  sdle_mousemotion     = 4
  sdle_mousebuttondown = 5
  sdle_mousebuttonup   = 6
  sdle_quit            = 12
}
