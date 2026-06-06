// 67-actors: an actor pattern built on BCPL coroutines.
//
// An actor = a coroutine with a private mailbox. Other actors (or
// main) deliver messages by appending to the target's mailbox. A
// round-robin scheduler drains every non-empty mailbox by callco'ing
// the owning coroutine with the next message; the actor processes
// it and cowait()s back to receive the next one. Actors send by
// just calling a regular function that appends — no direct callco
// between actors, which keeps the call structure flat and the
// reasoning local (each actor's stack only ever talks to the
// scheduler).
//
// What this demonstrates:
//   - createco gives every actor its own stack
//   - cowait(0) inside an actor body = "block until next message"
//   - The scheduler is just a loop pumping queues
//   - Actors compose via mailbox-passing, not direct calls
//   - Natural termination: an actor RESULTIS to exit; scheduler
//     leaves its queue alone after that
//
// Compare 32-coroutines for the one-coroutine, one-callco baseline.

SECTION "actors"

GET "libhdr"

MANIFEST {
  MBOX_CAP   = 64       // messages per mailbox (ring buffer)
  ACTOR_STK  = 1024     // wasm stack words per actor

  // Mailbox layout — [head, tail, count, cap, ring_0 .. ring_(cap-1)]
  MB_HEAD  = 0
  MB_TAIL  = 1
  MB_COUNT = 2
  MB_CAP   = 3
  MB_RING  = 4
}

// ---------------- mailbox primitives ----------------------------------

LET mbox_create(cap) = VALOF
{ LET m = getvec(MB_RING + cap + 1)
  IF m = 0 RESULTIS 0
  m!MB_HEAD  := 0
  m!MB_TAIL  := 0
  m!MB_COUNT := 0
  m!MB_CAP   := cap
  RESULTIS m
}

LET mbox_free(m) BE freevec(m)

LET mbox_empty(m) = m!MB_COUNT = 0

LET mbox_send(m, val) = VALOF
{ IF m!MB_COUNT >= m!MB_CAP RESULTIS FALSE
  m!(MB_RING + m!MB_TAIL) := val
  m!MB_TAIL := (m!MB_TAIL + 1) REM m!MB_CAP
  m!MB_COUNT := m!MB_COUNT + 1
  RESULTIS TRUE
}

LET mbox_recv(m) = VALOF
{ LET val = m!(MB_RING + m!MB_HEAD)
  m!MB_HEAD := (m!MB_HEAD + 1) REM m!MB_CAP
  m!MB_COUNT := m!MB_COUNT - 1
  RESULTIS val
}

// ---------------- shared actor registry --------------------------------
//
// In this demo the actors are statically known. A real system would
// keep a parallel array of (coroutine, mailbox, alive_flag) tuples
// and look up by handle. Here three slots is plenty.

STATIC {
  ping_co = 0;   ping_mbox = 0;   ping_alive = 0
  pong_co = 0;   pong_mbox = 0;   pong_alive = 0
  log_co  = 0;   log_mbox  = 0;   log_alive  = 0

  // Encode a (kind, value) "message" as a single int. The low 24
  // bits hold the value; the top 8 hold the kind. Real systems
  // pass pointers to richer message structs, but for this demo
  // packed ints keep the moving parts small.
  KIND_SHIFT = 24
}

LET msg(kind, val) = (kind << KIND_SHIFT) | (val & #xFFFFFF)
LET msg_kind(m)    = (m >> KIND_SHIFT) & #xFF
LET msg_val(m)     =  m & #xFFFFFF

MANIFEST {
  MSG_PING = 1
  MSG_PONG = 2
  MSG_LOG  = 3
  MSG_STOP = 4
}

// ---------------- actor bodies -----------------------------------------
//
// Each actor's first parameter is the initial callco arg, which we
// ignore (we use 0 to mean "you've been spawned, now block for real
// messages"). The first real message arrives via `cowait(0)`. After
// that, the body just loops: receive, process, cowait, repeat. A
// natural RESULTIS exits the actor; further mailbox-empty checks
// in the scheduler keep it from being re-callco'd.

LET ping_body(seed_unused) = VALOF
{ WHILE TRUE DO
  { LET m = cowait(0)
    LET k = msg_kind(m)
    LET v = msg_val(m)
    IF k = MSG_STOP RESULTIS 0
    IF k = MSG_PING DO
    { mbox_send(log_mbox,  msg(MSG_LOG, v))
      mbox_send(pong_mbox, msg(MSG_PONG, v + 1))
    }
  }
}

LET pong_body(seed_unused) = VALOF
{ WHILE TRUE DO
  { LET m = cowait(0)
    LET k = msg_kind(m)
    LET v = msg_val(m)
    IF k = MSG_STOP RESULTIS 0
    IF k = MSG_PONG DO
    { mbox_send(log_mbox, msg(MSG_LOG, v))
      // Bounded play: stop after value 10. Tell every actor
      // (including ourselves) to shut down so the scheduler marks
      // each dead and the next pass finds all mailboxes empty.
      TEST v >= 10
      THEN { mbox_send(ping_mbox, msg(MSG_STOP, 0))
             mbox_send(pong_mbox, msg(MSG_STOP, 0))
             mbox_send(log_mbox,  msg(MSG_STOP, 0)) }
      ELSE   mbox_send(ping_mbox, msg(MSG_PING, v + 1))
    }
  }
}

LET log_body(seed_unused) = VALOF
{ WHILE TRUE DO
  { LET m = cowait(0)
    LET k = msg_kind(m)
    LET v = msg_val(m)
    IF k = MSG_STOP RESULTIS 0
    IF k = MSG_LOG DO writef("  [log] saw %n*n", v)
  }
}

// ---------------- scheduler --------------------------------------------
//
// One pass = visit each actor whose mailbox is non-empty and deliver
// ONE message. We loop until every mailbox is empty for a full pass.
// More elaborate schedulers might prefer fairness, message priority
// or backpressure — the structure here is the smallest thing that
// still demonstrates the pattern.

// Deliver one queued message to an actor and update its alive flag.
// We use the message KIND to detect end-of-life rather than the
// coroutine return value: cowait(0) and "RESULTIS 0" both return 0,
// so the return value alone can't tell them apart. Instead the
// scheduler watches for MSG_STOP dispatches and marks the target
// dead after delivery — subsequent callco's would be undefined on
// a returned coroutine.
LET pump_actor(co, alive_ptr, mb) BE
{ IF !alive_ptr = 0 RETURN
  IF mbox_empty(mb) RETURN
  { LET m = mbox_recv(mb)
    callco(co, m)
    IF msg_kind(m) = MSG_STOP DO !alive_ptr := 0
  }
}

LET schedule() BE
{ LET delivered = TRUE
  WHILE delivered DO
  { delivered := FALSE
    UNLESS mbox_empty(ping_mbox) DO { pump_actor(ping_co, @ping_alive, ping_mbox); delivered := TRUE }
    UNLESS mbox_empty(pong_mbox) DO { pump_actor(pong_co, @pong_alive, pong_mbox); delivered := TRUE }
    UNLESS mbox_empty(log_mbox)  DO { pump_actor(log_co,  @log_alive,  log_mbox);  delivered := TRUE }
  }
}

// ---------------- main -------------------------------------------------

LET start() = VALOF
{ ping_mbox := mbox_create(MBOX_CAP)
  pong_mbox := mbox_create(MBOX_CAP)
  log_mbox  := mbox_create(MBOX_CAP)
  IF ping_mbox = 0 | pong_mbox = 0 | log_mbox = 0 DO
  { writes("mbox alloc failed*n"); RESULTIS 1 }

  ping_co := createco(ping_body, ACTOR_STK)
  pong_co := createco(pong_body, ACTOR_STK)
  log_co  := createco(log_body,  ACTOR_STK)
  ping_alive := 1; pong_alive := 1; log_alive := 1

  // Prime each actor with the initial callco. The bodies ignore the
  // seed (use 0) and immediately cowait for their first real msg.
  callco(ping_co, 0)
  callco(pong_co, 0)
  callco(log_co,  0)

  writes("actors ready. kicking off with ping=1...*n")
  mbox_send(ping_mbox, msg(MSG_PING, 1))

  schedule()

  writes("scheduler drained. alive: ")
  writef("ping=%n pong=%n log=%n*n", ping_alive, pong_alive, log_alive)

  IF ping_alive ~= 0 DO deleteco(ping_co)
  IF pong_alive ~= 0 DO deleteco(pong_co)
  IF log_alive  ~= 0 DO deleteco(log_co)
  mbox_free(ping_mbox); mbox_free(pong_mbox); mbox_free(log_mbox)
  RESULTIS 0
}
