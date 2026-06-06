// 71-websocket — open a real WebSocket from BCPL in the browser.
//
//   Connects to wss://echo.websocket.org (public echo service),
//   sends three messages, prints each reply, then closes.
//
// What's worth knowing:
//   - Sys_ws_open returns a small int handle (NOT a stream/SCB).
//   - Sys_ws_send takes a BCPL word-address + byte length. Bytes
//     ship as a single binary WebSocket frame to the peer.
//   - Sys_ws_recv is NON-BLOCKING: 0 = nothing yet (poll later),
//     positive = bytes copied (one message per call), -1 = peer
//     hung up and queue is drained, -2 = your buffer was too small.
//   - All async work happens on the JS side; we poll because BCPL
//     in the playground runs on a fixed-step "main loop", not on
//     callbacks.
//
// Try it: open the Output pane, click Run. The remote echoes each
// payload back; expect ~50-200 ms round-trip per message.

SECTION "WSCLIENT"

GET "libhdr"

MANIFEST {
  // MANIFEST only takes integer constants in BCPL — string literals
  // (the URL) live inline at the call site below.
  BUF_BYTES = 1024
  POLL_DELAY_MS = 30
  TIMEOUT_TICKS = 200          // ~6 s at 30 ms per tick
  STATE_OPEN   = 1
  STATE_CLOSED = 3
}

// Copy a BCPL string's chars (skipping length byte at slot 0) into
// the byte slots of a vector. Returns the count written.
LET bstr_to_bytes(bstr, dst) = VALOF
{ LET n = bstr%0
  FOR i = 0 TO n - 1 DO dst%i := bstr%(i + 1)
  RESULTIS n
}

// Print n raw bytes from a byte vector, no length prefix needed.
LET print_bytes(buf, n) BE
  FOR i = 0 TO n - 1 DO wrch(buf%i)

// Spin polling ws_status until it leaves "connecting" (0). Returns
// the final state or -1 on timeout.
LET wait_for_open(h) = VALOF
{ FOR i = 1 TO TIMEOUT_TICKS DO
  { LET s = sys(Sys_ws_status, h)
    IF s ~= 0 RESULTIS s
    delay(POLL_DELAY_MS)
  }
  RESULTIS -1
}

// Poll until ws_recv returns either bytes or -1 (closed). Writes
// length into rx_len_ptr. Returns TRUE on bytes received, FALSE
// on close / timeout.
LET wait_for_reply(h, buf, max, rx_len_ptr) = VALOF
{ FOR i = 1 TO TIMEOUT_TICKS DO
  { LET n = sys(Sys_ws_recv, h, buf, max)
    IF n > 0 DO { !rx_len_ptr := n; RESULTIS TRUE }
    IF n = -1 RESULTIS FALSE     // closed, no more data
    IF n = -2 RESULTIS FALSE     // buffer too small (shouldn't happen here)
    delay(POLL_DELAY_MS)
  }
  RESULTIS FALSE                  // ran out of ticks
}

// Send a BCPL string and print whatever the echo server returns.
LET send_and_recv(h, msg) BE
{ LET buf    = getvec(BUF_BYTES / bytesperword + 1)
  LET n_out  = bstr_to_bytes(msg, buf)
  LET n_in   = 0
  writef("send: %s*n", msg)
  IF sys(Sys_ws_send, h, buf, n_out) < 0 DO
  { writes("  send failed*n"); freevec(buf); RETURN }
  TEST wait_for_reply(h, buf, BUF_BYTES, @n_in)
  THEN { writes("recv: ")
         print_bytes(buf, n_in)
         newline()
       }
  ELSE writes("  (no reply / closed)*n")
  freevec(buf)
}

LET start() = VALOF
{ LET h = sys(Sys_ws_open, "wss://echo.websocket.org")
  LET state = 0
  IF h < 0 DO { writes("ws_open failed (no WebSocket support?)*n")
                RESULTIS 1 }

  writef("opened handle %n, waiting for connect...*n", h)
  state := wait_for_open(h)
  TEST state = STATE_OPEN
  THEN writes("connected*n*n")
  ELSE { writef("connect failed (state=%n)*n", state)
         sys(Sys_ws_close, h)
         RESULTIS 1 }

  send_and_recv(h, "hello from bcpl")
  send_and_recv(h, "the meaning is 42")
  send_and_recv(h, "goodbye")

  writes("*nclosing*n")
  sys(Sys_ws_close, h)
  RESULTIS 0
}
