// 66-arena: arena (bump) allocation in BCPL.
//
// getvec / freevec are fine for occasional allocations, but they pay
// freelist bookkeeping for every call AND fragment under churn. An
// arena flips the model: one big getvec up front, hand out sub-slices
// via a bump pointer, free everything at once by either resetting the
// pointer or freeing the backing vector.
//
// Layout of an arena vector (returned by arena_create):
//   slot 0  = capacity  (words available for handouts)
//   slot 1  = used      (current bump pointer, 0..capacity)
//   slot 2+ = storage   (handouts come from here)
//
// Typical use:
//   LET a = arena_create(4096)
//   LET v = arena_alloc(a, 32)     ; v is a word pointer, use as v!0..v!31
//   ...allocate more...
//   arena_reset(a)                 ; all pointers from this arena are now invalid
//   arena_free(a)                  ; release the backing vector
//
// Wins:
//   - O(1) allocation: bump + bounds check, no free-list walk.
//   - Bulk free: one freevec for everything at once.
//   - Cache-friendly: handouts are contiguous in memory.
//
// Trade:
//   - You can't free a single handout; reset is the only granularity.
//   - All handouts share the lifetime of the arena.

SECTION "arena"

GET "libhdr"

MANIFEST {
  ARENA_CAP  = 0     // header: capacity in words
  ARENA_USED = 1     // header: current bump pointer
  ARENA_HDR  = 2     // size of header; storage starts at slot 2
}

LET arena_create(capacity) = VALOF
{ LET a = getvec(capacity + ARENA_HDR + 1)
  IF a = 0 RESULTIS 0
  a!ARENA_CAP  := capacity
  a!ARENA_USED := 0
  RESULTIS a
}

LET arena_free(a)  BE freevec(a)
LET arena_reset(a) BE a!ARENA_USED := 0
LET arena_used(a)  = a!ARENA_USED
LET arena_cap(a)   = a!ARENA_CAP

// arena_alloc(a, n) — bump-allocate n words. Returns a word pointer
// you can index with !, or 0 on exhaustion.
LET arena_alloc(a, n) = VALOF
{ LET off = a!ARENA_USED
  IF off + n > a!ARENA_CAP RESULTIS 0
  a!ARENA_USED := off + n
  RESULTIS @(a!(ARENA_HDR + off))
}

LET start() = VALOF
{ LET a = arena_create(1024)
  IF a = 0 DO { writes("arena OOM*n"); RESULTIS 1 }

  // Three handouts from the same arena, then a quick check.
  // BCPL requires all LETs at the head of their block — we nest a
  // new block so we can introduce v1/v2/v3 here without colliding
  // with the outer `a` declaration.
  { LET v1 = arena_alloc(a, 10)
    AND v2 = arena_alloc(a, 20)
    AND v3 = arena_alloc(a, 5)
    FOR i = 0 TO  9 DO v1!i := i * i
    FOR i = 0 TO 19 DO v2!i := 100 + i
    FOR i = 0 TO  4 DO v3!i := -i
    writef("v1!5 = %n  v2!10 = %n  v3!3 = %n*n", v1!5, v2!10, v3!3)
    writef("arena used: %n / %n words*n*n", arena_used(a), arena_cap(a))
  }

  // Reset — v1/v2/v3 are now dangling pointers (don't deref them).
  arena_reset(a)
  writef("after reset: used = %n*n*n", arena_used(a))

  // Build a small LIFO linked list inside the arena. Each node is
  // two words: (value, next-ptr). Walk the list, then drop it all
  // by resetting the arena (zero per-node bookkeeping).
  { LET head = 0
    FOR n = 1 TO 6 DO
    { LET node = arena_alloc(a, 2)
      IF node = 0 BREAK
      node!0 := n * n   // value
      node!1 := head    // next
      head := node
    }
    writes("squares list (LIFO): ")
    { LET p = head
      UNTIL p = 0 DO
      { writen(p!0); wrch(' ')
        p := p!1
      }
    }
    newline()
    writef("arena used: %n / %n words   nodes: 6 x 2 = 12 words*n*n",
           arena_used(a), arena_cap(a))
  }

  // Demonstrate exhaustion + recovery.
  arena_reset(a)
  { LET big = arena_alloc(a, 2000)   // > capacity
    TEST big = 0
    THEN writef("oversize alloc correctly refused (used = %n)*n",
                arena_used(a))
    ELSE writef("unexpected: oversize handout succeeded*n")
  }

  arena_free(a)
  writes("arena freed*n")
  RESULTIS 0
}
