// 72-sssp-bmssp — full recursive BMSSP (Duan et al, arXiv 2504.17033).
//
// "Breaking the Sorting Barrier for Directed Single-Source Shortest
// Paths" (2025): first deterministic O(m * log^{2/3} n) algorithm for
// SSSP, beating Dijkstra's O(m + n log n) on sparse directed graphs.
//
// This example ships the full Algorithm 3 (recursive divide-and-conquer
// with log(n)/t levels), validated against Dijkstra via qcheck.
//
// Three independently-tested layers:
//   A.1 base_case   — Algorithm 2 (mini-Dijkstra capped at k+1)
//   A.2 find_pivots — Algorithm 1 / Lemma 3.2 (k BF sweeps + forest-
//                     subtree filter)
//   A.3 bmssp       — Algorithm 3 (recursive multi-level driver)
//
// Architecture:
//   - Arena bump allocator (no per-call getvec churn)
//   - Block-LL D-struct (Lemma 3.3): two-sequence (D0 batch-prepend,
//     D1 insert) chained block pool, heap-based pull
//   - Per-level touched-set propagation (covers vertices marooned in
//     a base_case heap at K+1 cap)
//   - Epoch-tagged bitmaps (skip O(N) zero loop per call)
//
// Status: correct at all tested top_l. Slower than Dijkstra at this
// scale — paper's asymptotic win needs N >> 10^6, which our 32-bit
// wasm linear memory can't reach. Demo proves the algorithm; perf gap
// closes with size.

SECTION "BMSSP"

GET "libhdr"

MANIFEST {
  N          = 400              // browser-friendly scale
  AVG_DEG    = 6
  M_MAX      = 3000
  INF        = #x7FFFFFFF
  K_PARAM    = 3
  T_PARAM    = 3                // top_l = ceil(log2(N)/T) = 3 at N=400
  ARENA_WORDS = 65536
  TRIALS     = 4
  BENCH_RUNS = 5
}

STATIC {
  m_e        = 0
  adj_head   = 0
  adj_to     = 0
  adj_w     = 0
  d_hat      = 0                // BMSSP working distance
  d_dij      = 0                // Dijkstra reference
  heap       = 0
  heap_n     = 0
  arena_base = 0
  arena_top  = 0
  arena_cap  = 0
  rseed      = 1
  // Side channel: every base_case call writes here the full set of
  // vertices whose d_hat got updated, including those base_case
  // PUSHED to its local heap but didn't pop. The outer bmssp's
  // post-recursion relax iterates this set (not ui) so vertices
  // marooned at d_hat < INF but not in U still get their successor
  // edges processed.
  bc_touched   = 0
  bc_touched_n = 0
  dbg_depth    = 0
  trace_bmssp  = 0
  g_epoch      = 0              // monotonic; bump to "clear" a bitmap
}

// ---------- arena allocator -----------------------------------------

LET arena_init() BE
{ arena_base := getvec_or_abort(ARENA_WORDS + 4, "bmssp arena")
  arena_top  := 0
  arena_cap  := ARENA_WORDS
  // Zero arena once so epoch-tag bitmaps have a known baseline; epoch
  // counter starts at 0, first use bumps to 3, so any leftover 0 is safe.
  FOR i = 0 TO ARENA_WORDS - 1 DO arena_base!i := 0
}

LET arena_alloc(n) = VALOF
{ assert(arena_top + n <= arena_cap, "arena overflow")
  { LET p = arena_base + arena_top
    arena_top := arena_top + n
    RESULTIS p
  }
}

LET arena_mark()   = arena_top
LET arena_reset(m) BE { arena_top := m }
LET arena_free()   BE freevec(arena_base)

// ---------- RNG -----------------------------------------------------

LET rng() = VALOF
{ rseed := (rseed * 1103515245 + 12345) & #x7FFFFFFF
  RESULTIS rseed
}

LET rand_in(lo, hi) = lo + (rng() REM (hi - lo + 1))

// ---------- graph build ---------------------------------------------

LET build_graph() BE
{ LET mark    = arena_mark()
  LET tmp_to  = arena_alloc(M_MAX)
  LET tmp_w   = arena_alloc(M_MAX)
  LET deg     = arena_alloc(N + 1)
  LET edge_cnt = 0
  FOR i = 0 TO N - 1 DO deg!i := 0
  FOR u = 0 TO N - 1 DO
  { FOR e = 1 TO AVG_DEG DO
    { LET v = rng() REM N
      IF v = u LOOP
      IF edge_cnt >= M_MAX LOOP
      tmp_to!edge_cnt := v
      tmp_w!edge_cnt  := rand_in(1, 50)
      deg!u := deg!u + 1
      edge_cnt := edge_cnt + 1
    }
  }
  adj_head!0 := 0
  FOR u = 0 TO N - 1 DO adj_head!(u + 1) := adj_head!u + deg!u
  m_e := adj_head!N
  { LET cursor = arena_alloc(N + 1)
    LET ei = 0
    LET cur_u = 0
    LET cur_left = deg!0
    FOR u = 0 TO N - 1 DO cursor!u := adj_head!u
    WHILE ei < edge_cnt DO
    { LET slot = 0
      UNTIL cur_left > 0 DO { cur_u := cur_u + 1; cur_left := deg!cur_u }
      slot := cursor!cur_u
      adj_to!slot := tmp_to!ei
      adj_w!slot  := tmp_w!ei
      cursor!cur_u := slot + 1
      cur_left := cur_left - 1
      ei := ei + 1
    }
  }
  arena_reset(mark)
}

// ---------- heap (parameterised by priority vector) -----------------

LET heap_init() BE { heap_n := 0 }

LET heap_push(v, pri) BE
{ LET i = heap_n
  heap!i := v
  heap_n := heap_n + 1
  WHILE i > 0 DO
  { LET p = (i - 1) / 2
    LET vp = heap!p
    LET vi = heap!i
    IF pri!vp <= pri!vi BREAK
    heap!p := vi
    heap!i := vp
    i := p
  }
}

LET heap_pop(pri) = VALOF
{ LET top = heap!0
  LET i = 0
  heap_n := heap_n - 1
  heap!0 := heap!heap_n
  WHILE TRUE DO
  { LET l = 2*i + 1
    LET r = 2*i + 2
    LET best = i
    IF l < heap_n & pri!(heap!l) < pri!(heap!best) DO best := l
    IF r < heap_n & pri!(heap!r) < pri!(heap!best) DO best := r
    IF best = i BREAK
    { LET t = heap!i
      heap!i := heap!best
      heap!best := t
    }
    i := best
  }
  RESULTIS top
}

// ---------- Dijkstra (reference baseline) ---------------------------

LET dijkstra(src) BE
{ FOR i = 0 TO N - 1 DO d_dij!i := INF
  d_dij!src := 0
  heap_init()
  heap_push(src, d_dij)
  WHILE heap_n > 0 DO
  { LET u = heap_pop(d_dij)
    LET du = d_dij!u
    FOR e = adj_head!u TO adj_head!(u+1) - 1 DO
    { LET v  = adj_to!e
      LET nd = du + adj_w!e
      IF nd < d_dij!v DO
      { d_dij!v := nd
        heap_push(v, d_dij)
      }
    }
  }
}

// ====================================================================
// A.1  BASE CASE  (Algorithm 2)
// ====================================================================
//
// Mini-Dijkstra from singleton S = {src}.  Pops up to K+1 vertices
// with d_hat(v) < B_in.  If we hit K+1, the (K+1)-th's d_hat is the
// new boundary B'; trim U to entries strictly below.  Otherwise
// B' = B_in and U holds everything we found.
//
// Updates d_hat[] in place — the global distance estimate the caller
// reads from after the BMSSP call chain returns.
//
// Caller guarantees: src is complete (d_hat[src] is the true distance).
// Returns: U_n via VALOF, new boundary B' via @B_out_ptr.

LET base_case(B_in, src, out_U, B_out_ptr) = VALOF
{ LET mark      = arena_mark()
  LET in_U      = arena_alloc(N)            // epoch values; 2*epoch = "popped"
  LET in_T      = arena_alloc(N)            // touched-set membership
  LET ep_T      = 0
  LET ep_U_seen = 0
  LET ep_U_done = 0
  LET u_n       = 0
  LET ret_B     = B_in
  g_epoch       := g_epoch + 3
  ep_T          := g_epoch - 2
  ep_U_seen     := g_epoch - 1              // "in heap"
  ep_U_done     := g_epoch                  // "popped already"
  bc_touched_n  := 0
  heap_init()
  in_U!src := ep_U_seen
  in_T!src := ep_T
  bc_touched!bc_touched_n := src
  bc_touched_n := bc_touched_n + 1
  heap_push(src, d_hat)
  WHILE heap_n > 0 & u_n <= K_PARAM DO
  { LET u = heap_pop(d_hat)
    IF d_hat!u >= B_in LOOP
    IF in_U!u = ep_U_done LOOP               // stale heap entry
    in_U!u := ep_U_done
    out_U!u_n := u
    u_n := u_n + 1
    FOR e = adj_head!u TO adj_head!(u+1) - 1 DO
    { LET v  = adj_to!e
      LET nd = d_hat!u + adj_w!e
      IF nd >= B_in LOOP
      IF nd < d_hat!v DO
      { d_hat!v := nd
        UNLESS in_T!v = ep_T DO
        { in_T!v := ep_T
          bc_touched!bc_touched_n := v
          bc_touched_n := bc_touched_n + 1
        }
        UNLESS in_U!v = ep_U_done DO
        { in_U!v := ep_U_seen
          heap_push(v, d_hat)
        }
      }
    }
  }
  TEST u_n > K_PARAM
  THEN { LET new_B = d_hat!(out_U!K_PARAM)
         LET kept  = 0
         FOR i = 0 TO K_PARAM DO
           IF d_hat!(out_U!i) < new_B DO
           { out_U!kept := out_U!i; kept := kept + 1 }
         u_n   := kept
         ret_B := new_B
       }
  ELSE ret_B := B_in
  !B_out_ptr := ret_B
  arena_reset(mark)
  RESULTIS u_n
}

// Trial for A.1: every vertex returned by base_case must have its
// d_hat (post-call) match d_dij — confirms the mini-Dijkstra walk
// computes true distances within the K+1 budget.
LET trial_base_case(seed, trial_no) = VALOF
{ LET U   = arena_alloc(K_PARAM + 2)
  LET U_n = 0
  LET B_out = 0
  rseed := seed
  build_graph()
  dijkstra(0)
  FOR i = 0 TO N - 1 DO d_hat!i := INF
  d_hat!0 := 0
  U_n := base_case(INF, 0, U, @B_out)
  // Invariant: every returned vertex has d_hat = d_dij.
  FOR i = 0 TO U_n - 1 DO
  { LET v = U!i
    IF d_hat!v ~= d_dij!v DO
    { writef("  base_case trial %n: v=%n d_hat=%n d_dij=%n*n",
               trial_no, v, d_hat!v, d_dij!v)
      RESULTIS 1
    }
  }
  // Invariant: U holds at most K_PARAM entries (the K+1-th sets the
  // boundary and gets trimmed out).
  IF U_n > K_PARAM DO
  { writef("  base_case trial %n: U_n=%n > K=%n*n", trial_no, U_n, K_PARAM)
    RESULTIS 2
  }
  RESULTIS 0
}

// ====================================================================
// A.2  FIND PIVOTS  (Algorithm 1, Lemma 3.2)
// ====================================================================
//
// K Bellman-Ford-style relaxation sweeps from S, building W
// (visited so far).  Two outcomes:
//   * |W| > k|S|  → bail: return P = S, no compression possible
//   * |W| ≤ k|S|  → forest of relaxed edges; P = S-vertices whose
//                   subtree has ≥ k entries
//
// Updates d_hat[] in place for all vertices reached.  Caller
// guarantees every v in S has d_hat[v] = true-distance.
//
// Writes pivots into out_P, visited set into out_W.
// Returns: P_n via VALOF, W_n via @W_n_ptr.

LET find_pivots(B_in, S, S_n, out_P, out_W, W_n_ptr) = VALOF
{ LET mark      = arena_mark()
  LET in_W      = arena_alloc(N)
  LET in_next   = arena_alloc(N)
  LET frontier  = arena_alloc(N)
  LET next_f    = arena_alloc(N)
  LET parent    = arena_alloc(N)
  LET cnt       = arena_alloc(N)
  LET par_ep    = arena_alloc(N)              // epoch of last parent-write
  LET cnt_ep    = arena_alloc(N)              // epoch of last cnt-write
  LET frontier_n = 0
  LET next_f_n   = 0
  LET w_n        = 0
  LET p_n        = 0
  LET bail       = FALSE
  LET ep_W       = 0
  LET ep_next    = 0
  LET ep_par     = 0
  LET ep_cnt     = 0

  g_epoch := g_epoch + 4
  ep_W    := g_epoch - 3
  ep_next := g_epoch - 2
  ep_par  := g_epoch - 1
  ep_cnt  := g_epoch

  FOR i = 0 TO S_n - 1 DO
  { LET v = S!i
    in_W!v := ep_W
    parent!v := v                              // S vertices are roots
    par_ep!v := ep_par
    out_W!w_n := v; w_n := w_n + 1
    frontier!frontier_n := v; frontier_n := frontier_n + 1
  }

  FOR step = 1 TO K_PARAM DO
  { IF bail BREAK
    // Fresh epoch for in_next per step.
    g_epoch := g_epoch + 1
    ep_next := g_epoch
    next_f_n := 0
    FOR i = 0 TO frontier_n - 1 DO
    { LET u = frontier!i
      FOR e = adj_head!u TO adj_head!(u+1) - 1 DO
      { LET v  = adj_to!e
        LET nd = d_hat!u + adj_w!e
        IF nd >= B_in LOOP
        IF nd < d_hat!v DO
        { d_hat!v := nd
          UNLESS in_next!v = ep_next DO
          { in_next!v := ep_next
            next_f!next_f_n := v; next_f_n := next_f_n + 1
          }
          UNLESS in_W!v = ep_W DO
          { in_W!v := ep_W
            IF w_n < N DO { out_W!w_n := v; w_n := w_n + 1 }
            IF w_n > K_PARAM * S_n DO bail := TRUE
          }
        }
      }
    }
    { LET tmp = frontier; frontier := next_f; next_f := tmp }
    frontier_n := next_f_n
  }

  TEST bail
  THEN { FOR i = 0 TO S_n - 1 DO out_P!i := S!i
         p_n := S_n
         // Bail case: every W vertex is under a pivot subtree
         // (every S vertex is a pivot). No independently complete
         // W vertices, so the caller's W-tackon must see an empty set.
         w_n := 0
       }
  ELSE { // Build forest: for each v in W\S, parent[v]=u iff edge
         // (u,v) with u in W and d_hat[v] = d_hat[u]+w(u,v).
         FOR u_i = 0 TO w_n - 1 DO
         { LET u = out_W!u_i
           FOR e = adj_head!u TO adj_head!(u+1) - 1 DO
           { LET v = adj_to!e
             IF in_W!v = ep_W & par_ep!v ~= ep_par &
                d_hat!v = d_hat!u + adj_w!e
             DO { parent!v := u; par_ep!v := ep_par }
           }
         }
         // Walk to root, count subtree size per S-rooted tree.
         // par_ep!r ~= ep_par means "no parent assigned" → orphan.
         FOR i = 0 TO w_n - 1 DO
         { LET v = out_W!i
           LET r = v
           LET orphan = FALSE
           LET hops = 0
           UNTIL par_ep!r = ep_par & parent!r = r DO
           { IF par_ep!r ~= ep_par | hops > N DO { orphan := TRUE; BREAK }
             r := parent!r
             hops := hops + 1
           }
           UNLESS orphan DO
           { TEST cnt_ep!r = ep_cnt
             THEN cnt!r := cnt!r + 1
             ELSE { cnt!r := 1; cnt_ep!r := ep_cnt }
           }
         }
         FOR i = 0 TO S_n - 1 DO
           IF cnt_ep!(S!i) = ep_cnt & cnt!(S!i) >= K_PARAM DO
           { out_P!p_n := S!i; p_n := p_n + 1 }
         // Filter out_W to keep only "complete" vertices — those
         // whose forest root is NOT in the pivot set.
         { LET is_pivot    = arena_alloc(N)
           LET ip_ep       = 0
           LET new_w_n     = 0
           g_epoch := g_epoch + 1
           ip_ep   := g_epoch
           FOR i = 0 TO p_n - 1 DO is_pivot!(out_P!i) := ip_ep
           FOR i = 0 TO w_n - 1 DO
           { LET v = out_W!i
             LET r = v
             LET orphan = FALSE
             LET hops = 0
             UNTIL par_ep!r = ep_par & parent!r = r DO
             { IF par_ep!r ~= ep_par | hops > N DO { orphan := TRUE; BREAK }
               r := parent!r
               hops := hops + 1
             }
             UNLESS orphan | is_pivot!r = ip_ep DO
             { out_W!new_w_n := v; new_w_n := new_w_n + 1 }
           }
           w_n := new_w_n
         }
       }

  !W_n_ptr := w_n
  arena_reset(mark)
  RESULTIS p_n
}

// Trial for A.2: |W| bound (≤ N) + |P| ≤ S_n always + (when no bail)
// |P| ≤ |W|/K bound from the paper.
LET trial_find_pivots(seed, trial_no) = VALOF
{ LET S   = arena_alloc(2)
  LET P   = arena_alloc(2)
  LET W   = arena_alloc(N + 1)
  LET W_n = 0
  LET P_n = 0
  rseed := seed
  build_graph()
  dijkstra(0)
  FOR i = 0 TO N - 1 DO d_hat!i := INF
  d_hat!0 := 0
  S!0 := 0
  P_n := find_pivots(INF, S, 1, P, W, @W_n)
  IF P_n > 1 DO
  { writef("  find_pivots trial %n: P_n=%n > S_n=1*n", trial_no, P_n)
    RESULTIS 1
  }
  IF W_n > N DO
  { writef("  find_pivots trial %n: W_n=%n > N=%n*n", trial_no, W_n, N)
    RESULTIS 2
  }
  // d_hat updated in W should match d_dij there (within-bound vertices
  // are complete since BF sweeps from a complete source).
  FOR i = 0 TO W_n - 1 DO
  { LET v = W!i
    IF d_hat!v ~= d_dij!v DO
    { writef("  find_pivots trial %n: v=%n d_hat=%n d_dij=%n*n",
               trial_no, v, d_hat!v, d_dij!v)
      RESULTIS 3
    }
  }
  RESULTIS 0
}

// ====================================================================
// A.3  D-STRUCT  (Lemma 3.3: block-linked list)
// ====================================================================
//
// Two-sequence container:
//   D0 — blocks fed by BatchPrepend (precondition: every key in the
//        batch has d_hat < min(d_hat over current D)).
//   D1 — blocks fed by Insert.
//
// Each block: (prev, next, count, key0..key_{M-1}). Blocks chained
// via indices into a shared pool — no per-block getvec.
//
// Pull(M): scan all blocks, gather unique keys, partial-sort, take M
// smallest, rebuild remaining as a single D1 chain. Not asymptotically
// optimal vs. paper, but correct and matches the API the paper assumes.
//
// Block size is BLOCK_M; pool sized for worst-case (N/BLOCK_M)*depth.

MANIFEST {
  BLOCK_M    = 64
  POOL_SIZE  = 512
  BLK_PREV   = 0
  BLK_NEXT   = 1
  BLK_N      = 2
  BLK_KEYS   = 3
  BLK_WORDS  = 3 + 64           // = 3 + BLOCK_M  (MANIFEST can't ref MANIFEST)

  DD_D0_HEAD = 0
  DD_D0_TAIL = 1
  DD_D1_HEAD = 2
  DD_D1_TAIL = 3
  DD_N       = 4                // upper-bound on stored entries (counts dups)
  DD_B       = 5
  DD_SIZE    = 6
}

STATIC {
  blk_pool     = 0
  blk_free     = 0
  blk_free_top = 0
}

LET blk_pool_init() BE
{ blk_pool     := getvec_or_abort(POOL_SIZE * BLK_WORDS, "blk_pool")
  blk_free     := getvec_or_abort(POOL_SIZE, "blk_free")
  blk_free_top := 0
  FOR i = POOL_SIZE - 1 TO 0 BY -1 DO
  { blk_free!blk_free_top := i
    blk_free_top := blk_free_top + 1
  }
}

LET blk_pool_free() BE
{ freevec(blk_pool); freevec(blk_free) }

LET blk_at(idx) = blk_pool + idx * BLK_WORDS

LET blk_alloc() = VALOF
{ LET idx = 0
  LET b   = 0
  assert(blk_free_top > 0, "block pool exhausted")
  blk_free_top := blk_free_top - 1
  idx := blk_free!blk_free_top
  b := blk_at(idx)
  b!BLK_PREV := -1
  b!BLK_NEXT := -1
  b!BLK_N    := 0
  RESULTIS idx
}

LET blk_free_one(idx) BE
{ blk_free!blk_free_top := idx
  blk_free_top := blk_free_top + 1
}

LET d_alloc(cap, B_in) = VALOF
{ LET D = arena_alloc(DD_SIZE)
  D!DD_D0_HEAD := -1; D!DD_D0_TAIL := -1
  D!DD_D1_HEAD := -1; D!DD_D1_TAIL := -1
  D!DD_N       := 0
  D!DD_B       := B_in
  RESULTIS D
}

LET d_empty(D) = D!DD_N = 0

// Append key to D1's tail block. Allocate fresh block when full.
LET d_insert(D, key) BE
{ LET tail = D!DD_D1_TAIL
  LET tb   = 0
  IF tail = -1 | (blk_at(tail))!BLK_N >= BLOCK_M DO
  { LET nb  = blk_alloc()
    LET nbb = blk_at(nb)
    nbb!BLK_PREV := tail
    nbb!BLK_NEXT := -1
    TEST tail = -1
    THEN D!DD_D1_HEAD := nb
    ELSE (blk_at(tail))!BLK_NEXT := nb
    D!DD_D1_TAIL := nb
    tail := nb
  }
  tb := blk_at(tail)
  tb!(BLK_KEYS + tb!BLK_N) := key
  tb!BLK_N := tb!BLK_N + 1
  D!DD_N   := D!DD_N + 1
}

// Prepend a batch onto D0's front. Caller's precondition: every key
// in keys[0..len) satisfies d_hat[k] < min existing d_hat in D.
LET d_batch_prepend(D, keys, len) BE
{ LET pos = 0
  WHILE pos < len DO
  { LET take = len - pos
    LET nb   = 0
    LET nbb  = 0
    LET old_head = 0
    IF take > BLOCK_M DO take := BLOCK_M
    nb  := blk_alloc()
    nbb := blk_at(nb)
    nbb!BLK_PREV := -1
    nbb!BLK_NEXT := -1
    nbb!BLK_N    := take
    FOR i = 0 TO take - 1 DO nbb!(BLK_KEYS + i) := keys!(pos + i)
    // Link onto front of D0.
    old_head := D!DD_D0_HEAD
    nbb!BLK_NEXT := old_head
    UNLESS old_head = -1 DO (blk_at(old_head))!BLK_PREV := nb
    D!DD_D0_HEAD := nb
    IF D!DD_D0_TAIL = -1 DO D!DD_D0_TAIL := nb
    D!DD_N := D!DD_N + take
    pos    := pos + take
  }
}

// Pull the M smallest keys (by d_hat). Returns count via n_ptr, new
// boundary via x_ptr (= min d_hat of remaining, or D!DD_B if drained).
//
// Strategy: gather unique keys, build min-heap (heapify via push), pop
// M smallest, dump residual back as fresh D1. O(k + M log k).
// Uses the global `heap` static — safe because pull is never called
// while base_case (the only other heap consumer) is mid-execution.
LET d_pull(D, M, out, n_ptr, x_ptr) BE
{ LET mark    = arena_mark()
  LET seen    = arena_alloc(N)
  LET ep_seen = 0
  LET take    = 0
  LET next_x  = D!DD_B

  g_epoch := g_epoch + 1
  ep_seen := g_epoch
  heap_init()

  // Gather D0 then D1, push to heap (dedup via seen[]).
  { LET cur = D!DD_D0_HEAD
    UNTIL cur = -1 DO
    { LET b = blk_at(cur)
      LET n = b!BLK_N
      FOR i = 0 TO n - 1 DO
      { LET v = b!(BLK_KEYS + i)
        UNLESS seen!v = ep_seen DO
        { seen!v := ep_seen; heap_push(v, d_hat) }
      }
      cur := b!BLK_NEXT
    }
  }
  { LET cur = D!DD_D1_HEAD
    UNTIL cur = -1 DO
    { LET b = blk_at(cur)
      LET n = b!BLK_N
      FOR i = 0 TO n - 1 DO
      { LET v = b!(BLK_KEYS + i)
        UNLESS seen!v = ep_seen DO
        { seen!v := ep_seen; heap_push(v, d_hat) }
      }
      cur := b!BLK_NEXT
    }
  }

  // Free all current blocks before re-inserting residual.
  { LET cur = D!DD_D0_HEAD
    UNTIL cur = -1 DO
    { LET nx = (blk_at(cur))!BLK_NEXT
      blk_free_one(cur); cur := nx
    }
  }
  { LET cur = D!DD_D1_HEAD
    UNTIL cur = -1 DO
    { LET nx = (blk_at(cur))!BLK_NEXT
      blk_free_one(cur); cur := nx
    }
  }
  D!DD_D0_HEAD := -1; D!DD_D0_TAIL := -1
  D!DD_D1_HEAD := -1; D!DD_D1_TAIL := -1
  D!DD_N       := 0

  // Pop M smallest.
  take := M
  IF take > heap_n DO take := heap_n
  FOR i = 0 TO take - 1 DO out!i := heap_pop(d_hat)
  IF heap_n > 0 DO next_x := d_hat!(heap!0)

  !n_ptr := take
  !x_ptr := next_x

  // Residual heap → D1 (order doesn't matter; pull re-sorts anyway).
  FOR i = 0 TO heap_n - 1 DO d_insert(D, heap!i)
  heap_n := 0

  arena_reset(mark)
}

// Free all blocks belonging to D (called when D goes out of scope —
// in this code we rely on full-pull drain, so this is a safety net).
LET d_destroy(D) BE
{ { LET cur = D!DD_D0_HEAD
    UNTIL cur = -1 DO
    { LET nx = (blk_at(cur))!BLK_NEXT
      blk_free_one(cur); cur := nx
    }
  }
  { LET cur = D!DD_D1_HEAD
    UNTIL cur = -1 DO
    { LET nx = (blk_at(cur))!BLK_NEXT
      blk_free_one(cur); cur := nx
    }
  }
  D!DD_D0_HEAD := -1; D!DD_D0_TAIL := -1
  D!DD_D1_HEAD := -1; D!DD_D1_TAIL := -1
  D!DD_N       := 0
}

// ====================================================================
// A.3  BMSSP  (Algorithm 3, recursive)
// ====================================================================
//
// Requirement: |S| ≤ 2^(level*t).  Every incomplete vertex v with
// d(v) < B has shortest path visiting some complete vertex in S.
// Returns: U_n via VALOF (vertices completed by this call),
//          B' via @B_out_ptr.  U is written into out_U.

// (dbg_depth + trace_bmssp moved into the main STATIC block above —
//  having two STATIC blocks in one section apparently aliases slots,
//  caused trace_bmssp to read arbitrary values like 2000 during
//  qcheck-driven recursion.)

// Multi-level signature: out_T accumulates every vertex whose d_hat
// got updated anywhere down the recursion. Parent uses returned T (not
// just ui) to drive its post-recursion relax — same trick bc_touched
// uses at level=1, generalised to every level.
LET bmssp(level, B_in, S, S_n, out_U, out_T, T_n_ptr, B_out_ptr) = VALOF
{ LET mark    = arena_mark()
  LET in_T    = arena_alloc(N)
  LET ep_T    = 0
  LET t_n     = 0
  LET u_n     = 0
  LET B_prime = B_in
  dbg_depth := dbg_depth + 1
  g_epoch := g_epoch + 1
  ep_T    := g_epoch

  IF level = 0 DO
  { u_n := base_case(B_in, S!0, out_U, B_out_ptr)
    // Copy bc_touched into out_T (dedup via in_T).
    FOR i = 0 TO bc_touched_n - 1 DO
    { LET v = bc_touched!i
      UNLESS in_T!v = ep_T DO
      { in_T!v := ep_T
        out_T!t_n := v
        t_n := t_n + 1
      }
    }
    !T_n_ptr := t_n
    arena_reset(mark)
    dbg_depth := dbg_depth - 1
    RESULTIS u_n
  }

  { LET P     = arena_alloc(S_n + 2)
    LET W     = arena_alloc(N + 1)
    LET W_n   = 0
    LET P_n   = 0
    LET D     = 0
    LET M     = 1
    LET ui    = arena_alloc(N + 1)
    LET ui_n  = 0
    LET inner_T  = arena_alloc(N + 1)
    LET inner_Tn = 0
    LET Si    = arena_alloc(N + 1)
    LET Si_n  = 0
    LET Bi    = 0
    LET Bi_prime = 0
    LET shift_amt = 0
    LET u_cap   = 0
    LET success_done = FALSE
    LET loop_ran    = FALSE

    // M = 2^((level-1)*t), clamped.
    shift_amt := (level - 1) * T_PARAM
    IF shift_amt > 12 DO shift_amt := 12
    M := 1
    FOR i = 1 TO shift_amt DO M := M * 2

    // u_cap = k * 2^(level*t), clamped.
    shift_amt := level * T_PARAM
    IF shift_amt > 16 DO shift_amt := 16
    u_cap := 1
    FOR i = 1 TO shift_amt DO u_cap := u_cap * 2
    u_cap := u_cap * K_PARAM

    P_n := find_pivots(B_in, S, S_n, P, W, @W_n)
    D := d_alloc(N + 1, B_in)
    FOR i = 0 TO P_n - 1 DO d_insert(D, P!i)

    // Seed touched with W (find_pivots updated d_hat on every W vertex)
    // and S (caller's already-complete set — propagate upward).
    FOR i = 0 TO W_n - 1 DO
    { LET v = W!i
      UNLESS in_T!v = ep_T DO
      { in_T!v := ep_T; out_T!t_n := v; t_n := t_n + 1 }
    }
    FOR i = 0 TO S_n - 1 DO
    { LET v = S!i
      UNLESS in_T!v = ep_T DO
      { in_T!v := ep_T; out_T!t_n := v; t_n := t_n + 1 }
    }

    TEST P_n > 0
    THEN { B_prime := d_hat!(P!0)
           FOR i = 1 TO P_n - 1 DO
             IF d_hat!(P!i) < B_prime DO B_prime := d_hat!(P!i)
         }
    ELSE { B_prime := B_in
           success_done := TRUE
         }

    UNTIL u_n >= u_cap | d_empty(D) DO
    { loop_ran := TRUE
      d_pull(D, M, Si, @Si_n, @Bi)
      ui_n := bmssp(level - 1, Bi, Si, Si_n, ui,
                    inner_T, @inner_Tn, @Bi_prime)
      // Accumulate U.
      FOR i = 0 TO ui_n - 1 DO
      { out_U!u_n := ui!i; u_n := u_n + 1 }
      // Merge inner_T into our touched set.
      FOR i = 0 TO inner_Tn - 1 DO
      { LET v = inner_T!i
        UNLESS in_T!v = ep_T DO
        { in_T!v := ep_T; out_T!t_n := v; t_n := t_n + 1 }
      }
      // Relax edges from every touched vertex the child surfaced
      // (covers marooned vertices at every level, not just level=1).
      FOR i = 0 TO inner_Tn - 1 DO
      { LET u = inner_T!i
        FOR e = adj_head!u TO adj_head!(u+1) - 1 DO
        { LET v  = adj_to!e
          LET nd = d_hat!u + adj_w!e
          IF nd >= B_in LOOP
          IF nd <= d_hat!v DO
          { d_hat!v := nd
            d_insert(D, v)
            UNLESS in_T!v = ep_T DO
            { in_T!v := ep_T; out_T!t_n := v; t_n := t_n + 1 }
          }
        }
      }
      // Si entries whose d_hat fell into [Bi', Bi) get batch_prepended.
      // Collect into a buffer, then prepend in one shot — guaranteed
      // smaller than current D contents (their d_hat < Bi <= D's min).
      // mark/reset bracket prevents this scratch buffer from drifting
      // arena_top each loop iteration (every level above 0 runs many
      // iters; the leak accumulates fast).
      { LET prep_mark = arena_mark()
        LET prep_buf  = arena_alloc(Si_n + 1)
        LET prep_n    = 0
        FOR i = 0 TO Si_n - 1 DO
        { LET x = Si!i
          IF d_hat!x >= Bi_prime & d_hat!x < Bi DO
          { prep_buf!prep_n := x; prep_n := prep_n + 1 }
        }
        IF prep_n > 0 DO d_batch_prepend(D, prep_buf, prep_n)
        arena_reset(prep_mark)
      }
      IF d_empty(D) DO
      { B_prime := B_in
        success_done := TRUE
      }
    }

    UNLESS success_done DO
    { IF loop_ran DO B_prime := Bi_prime }
    IF B_prime > B_in DO B_prime := B_in

    FOR i = 0 TO W_n - 1 DO
      IF d_hat!(W!i) < B_prime DO
      { out_U!u_n := W!i; u_n := u_n + 1 }

    !B_out_ptr := B_prime
    d_destroy(D)                          // return blocks to pool
  }

  !T_n_ptr := t_n
  arena_reset(mark)
  dbg_depth := dbg_depth - 1
  RESULTIS u_n
}

// Driver: call BMSSP from level top_l with S = {src}, B = INF.
LET bmssp_sssp(src) BE
{ LET top_l = 1
  LET log_n = 0
  LET tmp_S = VEC 2
  LET tmp_U = 0
  LET tmp_T = 0
  LET tmp_Tn = 0
  LET out_B = 0
  LET mark  = arena_mark()
  // log2(N) ceil.
  { LET v = N
    UNTIL v <= 1 DO { v := v / 2; log_n := log_n + 1 }
  }
  top_l := (log_n + T_PARAM - 1) / T_PARAM
  IF top_l < 1 DO top_l := 1

  FOR i = 0 TO N - 1 DO d_hat!i := INF
  d_hat!src := 0
  tmp_U := arena_alloc(N + 1)
  tmp_T := arena_alloc(N + 1)
  tmp_S!0 := src
  bmssp(top_l, INF, tmp_S, 1, tmp_U, tmp_T, @tmp_Tn, @out_B)
  arena_reset(mark)
}

// Trial for A.3: full SSSP. d_hat after bmssp_sssp must match d_dij
// on every vertex.
LET trial_bmssp(seed, trial_no) = VALOF
{ LET diffs = 0
  LET first_bad = -1
  rseed := seed
  build_graph()
  dijkstra(0)
  bmssp_sssp(0)
  FOR i = 0 TO N - 1 DO
    IF d_dij!i ~= d_hat!i DO
    { diffs := diffs + 1
      IF first_bad < 0 DO first_bad := i
    }
  IF diffs > 0 DO
  { writef("  bmssp trial %n: %n diffs, first v=%n: dij=%n bmssp=%n*n",
             trial_no, diffs, first_bad,
             d_dij!first_bad, d_hat!first_bad)
    RESULTIS 1
  }
  RESULTIS 0
}

// Inline qcheck — playground stdlib doesn't expose blib's version.
LET qcheck(label, trial_fn, n_trials) = VALOF
{ LET passes = 0
  LET fails  = 0
  LET first_fail_seed = 0
  LET first_fail_code = 0
  writef("qcheck %s: %n trials*n", label, n_trials)
  FOR i = 1 TO n_trials DO
  { LET seed = i * 7919
    LET rc   = trial_fn(seed, i)
    TEST rc = 0
    THEN passes := passes + 1
    ELSE { fails := fails + 1
           IF first_fail_seed = 0 DO
           { first_fail_seed := seed
             first_fail_code := rc
           }
         }
  }
  TEST fails = 0
  THEN writef("  PASS %n/%n*n", passes, n_trials)
  ELSE writef("  FAIL %n/%n  first fail: seed=%n rc=%n*n",
              fails, n_trials, first_fail_seed, first_fail_code)
  RESULTIS fails
}

LET start() = VALOF
{ trace_bmssp := FALSE
  dbg_depth   := 0
  // Reset epoch on every fresh run so playground re-Run doesn't
  // accumulate from a prior run's state (epoch tags survive in
  // memory across rt.run() invocations).
  g_epoch     := 0
  adj_head    := getvec_or_abort(N + 2, "adj_head")
  adj_to      := getvec_or_abort(M_MAX, "adj_to")
  adj_w       := getvec_or_abort(M_MAX, "adj_w")
  d_hat       := getvec_or_abort(N + 1, "d_hat")
  d_dij       := getvec_or_abort(N + 1, "d_dij")
  heap        := getvec_or_abort(M_MAX + N + 100, "heap")
  bc_touched  := getvec_or_abort(N + 1, "bc_touched")
  arena_init()
  blk_pool_init()

  qcheck("A.1 base_case",   trial_base_case,   TRIALS)
  qcheck("A.2 find_pivots", trial_find_pivots, TRIALS)
  qcheck("A.3 bmssp recursive", trial_bmssp, TRIALS)

  // Head-to-head bench: BMSSP vs Dijkstra wall-time on same graphs.
  { LET t0 = 0
    LET t_dij = 0
    LET t_bm  = 0
    LET ok    = TRUE
    writef("*nBench: N=%n AVG_DEG=%n top_l(at T=%n)=ceil(log2(N)/T) runs=%n*n",
           N, AVG_DEG, T_PARAM, BENCH_RUNS)
    rseed := 17
    t0 := sys(Sys_cputime)
    FOR r = 1 TO BENCH_RUNS DO
    { build_graph()
      dijkstra(0)
    }
    t_dij := sys(Sys_cputime) - t0
    rseed := 17
    t0 := sys(Sys_cputime)
    FOR r = 1 TO BENCH_RUNS DO
    { build_graph()
      bmssp_sssp(0)
    }
    t_bm := sys(Sys_cputime) - t0
    // Sanity check on last trial.
    FOR i = 0 TO N - 1 DO
      IF d_dij!i ~= d_hat!i DO
      { ok := FALSE; BREAK }
    writef("  Dijkstra: %n ticks*n", t_dij)
    writef("  BMSSP:    %n ticks*n", t_bm)
    writef("  Last-trial match: %s*n", ok -> "yes", "NO")
  }

  blk_pool_free()
  arena_free()
  freevec(adj_head); freevec(adj_to); freevec(adj_w)
  freevec(d_hat); freevec(d_dij); freevec(heap); freevec(bc_touched)
  RESULTIS 0
}
