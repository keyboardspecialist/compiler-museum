// doomengine — minimal Doom-style 3D engine library.
//
// Consumer pattern:
//
//   GET "libhdr"
//   GET "sdl"
//   GET "doomengine"
//
//   LET start() = VALOF
//   { UNLESS engine_init()                RESULTIS 1
//     UNLESS engine_load_wad_from_assets() RESULTIS 2
//     UNLESS engine_load_map("E1M1")      RESULTIS 3
//     engine_load_default_sprites()
//     engine_load_sf2_from_assets()
//
//     WHILE engine_poll_events() DO
//     { LET fwd = 0, turn = 0
//       IF engine_key_down(K_W) DO fwd := 1
//       IF engine_key_down(K_S) DO fwd := -1
//       IF engine_key_down(K_A) DO turn := -ENGINE_TURN
//       IF engine_key_down(K_D) DO turn := ENGINE_TURN
//       IF fwd ~= 0 DO engine_walk(fwd)
//       IF turn ~= 0 DO engine_turn(turn)
//       engine_tick()
//       engine_draw_frame()
//       delay(16)
//     }
//     engine_stop_music()
//     RESULTIS 0
//   }
//
// The engine owns all renderer state — palette, BSP, sectors, sprites,
// textures, sky, doors, lights, sprites animations, weapon HUD, automap,
// music. The consumer drives input + main loop only.
//
// Resolution is fixed at compile time (see ENGINE_W / ENGINE_H below).

MANIFEST {
  ENGINE_W       = 960
  ENGINE_H       = 720
  ENGINE_HORIZON = 360
  ENGINE_NEAR    = 4
  ENGINE_EYE_H   = 41
  ENGINE_TURN    = 64     // ANG units per turn-key press (engine ANG=8192)
  ENGINE_MOVE    = 16     // world units per walk step

  // Browser keyCode constants — match the engine's internal map.
  // Consumers use these names with engine_key_down().
  K_LEFT   = 37
  K_UP     = 38
  K_RIGHT  = 39
  K_DOWN   = 40
  K_A      = 65
  K_D      = 68
  K_S      = 83
  K_W      = 87
  K_E      = 69
  K_F      = 70
  K_M      = 77
  K_Q      = 81
  K_ESC    = 27
  K_SPACE  = 32
  K_RETURN = 13
  K_LCTRL  = 17
  K_PLUS   = 187   // '='/'+'
  K_MINUS  = 189   // '-'/'_'
  K_PGUP   = 33
  K_PGDN   = 34
}

GLOBAL {
  // --- lifecycle ----------------------------------------------------
  engine_init                  : 300   // () = TRUE/FALSE — alloc buffers, build trig tables
  engine_load_wad_from_assets  : 301   // () = TRUE/FALSE — load first .wad asset
  engine_load_map              : 302   // (map_name_bcpl_str) = TRUE/FALSE
  engine_load_default_sprites  : 303   // () BE — load BAR1A0..POSSA1..etc
  engine_load_sf2_from_assets  : 304   // () = TRUE/FALSE
  engine_start_music           : 305   // () BE — kick off WAD MUS for current map
  engine_stop_music            : 306   // () BE

  // --- input + main-loop driver ------------------------------------
  engine_poll_events           : 310   // () = running_flag (FALSE on Esc)
  engine_key_down              : 311   // (k) = bool

  // --- player state -------------------------------------------------
  engine_player_x              : 320   // () = px
  engine_player_y              : 321   // () = py
  engine_player_a              : 322   // () = pa (0..2047, ANG=2048)

  // --- per-frame actions --------------------------------------------
  engine_walk                  : 330   // (fwd) BE  — fwd = +1 forward, -1 back
  engine_strafe                : 331   // (side) BE — side = +1 right, -1 left
  engine_turn                  : 332   // (da) BE   — ANG-fraction
  engine_use                   : 333   // () BE     — open door at gaze
  engine_fire                  : 334   // () BE     — trigger weapon fire animation
  engine_tick                  : 335   // () BE     — advance doors/lights/anim 1 frame
  engine_draw_frame            : 336   // () BE     — paint the canvas

  // --- UI -----------------------------------------------------------
  engine_toggle_automap        : 340   // () BE
  engine_automap_zoom          : 341   // (delta) BE — +ve = in, -ve = out
  engine_set_hud               : 342   // (health, ammo, armor) BE
}
