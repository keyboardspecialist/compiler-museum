// 62-doom-engine: consume the doomengine library.
//
// This file is the "game" — input poll, movement decisions, main loop
// pacing. All renderer / WAD parsing / BSP / sprites / HUD / automap /
// music is delegated to doomengine.b via the small API in
// g/doomengine.h.
//
// Drop a Doom1.WAD (and optionally a .sf2 SoundFont) into the Assets
// pane before running.
//
// Controls: WASD / arrows = move + turn, Q/E = strafe, Space or
//           Enter = use, F or LCtrl = fire, M = automap toggle,
//           +/- (or PageUp/PageDown) = automap zoom, Esc = quit.

SECTION "game"

GET "libhdr"
GET "sdl"
GET "doomengine"

// Edge-state for keys that trigger on press, not while held.
STATIC {
  use_prev      = 0
  fire_prev     = 0
  automap_prev  = 0
  music_started = FALSE
}

LET start() = VALOF
{ UNLESS engine_init() RESULTIS 1
  UNLESS engine_load_wad_from_assets() RESULTIS 2
  // Pass 0 to engine_load_map for "first map in the WAD".
  UNLESS engine_load_map(0) RESULTIS 3
  writef("consumer: about to load sprites*n")
  engine_load_default_sprites()
  writef("consumer: sprites returned*n")

  WHILE engine_poll_events() DO
  { LET fwd  = 0
    LET turn = 0
    LET side = 0

    // First user gesture also kicks off music + queues the SF2 load.
    // Browsers block audio start until a key/click happens.
    UNLESS music_started DO
    { LET any = FALSE
      FOR k = 0 TO 255 DO IF engine_key_down(k) DO { any := TRUE; BREAK }
      IF any DO
      { engine_load_sf2_from_assets()
        engine_start_music()
        music_started := TRUE
      }
    }

    IF engine_key_down(K_W) | engine_key_down(K_UP)    DO fwd  := fwd  + 1
    IF engine_key_down(K_S) | engine_key_down(K_DOWN)  DO fwd  := fwd  - 1
    IF engine_key_down(K_A) | engine_key_down(K_LEFT)  DO turn := turn - ENGINE_TURN
    IF engine_key_down(K_D) | engine_key_down(K_RIGHT) DO turn := turn + ENGINE_TURN
    IF engine_key_down(K_Q)                            DO side := side - 1
    IF engine_key_down(K_E)                            DO side := side + 1

    // Use: edge-trigger on Space or Enter.
    { LET now = engine_key_down(K_SPACE) | engine_key_down(K_RETURN)
      IF now ~= 0 & use_prev = 0 DO engine_use()
      use_prev := now
    }

    // Fire: edge-trigger on F or LCtrl.
    { LET now = engine_key_down(K_F) | engine_key_down(K_LCTRL)
      IF now ~= 0 & fire_prev = 0 DO engine_fire()
      fire_prev := now
    }

    // Automap toggle on M; zoom while shown.
    { LET now = engine_key_down(K_M)
      IF now ~= 0 & automap_prev = 0 DO engine_toggle_automap()
      automap_prev := now
    }
    IF engine_key_down(K_PLUS)  | engine_key_down(K_PGUP) DO engine_automap_zoom( 1)
    IF engine_key_down(K_MINUS) | engine_key_down(K_PGDN) DO engine_automap_zoom(-1)

    IF fwd  ~= 0 DO engine_walk(fwd)
    IF side ~= 0 DO engine_strafe(side)
    IF turn ~= 0 DO engine_turn(turn)

    engine_tick()
    engine_draw_frame()
    delay(16)
  }
  engine_stop_music()
  RESULTIS 0
}
