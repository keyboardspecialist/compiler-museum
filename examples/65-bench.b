// 65-bench: microbenchmarks for cintcode vs wasm.
//
// Each phase runs a deterministic workload, prints its result, and
// reports wall-clock elapsed milliseconds via datstamp deltas.
// Phases:
//   nfib(28)            — recursive call/return throughput
//   sieve up to N       — vector + branchy loop
//   matmul 64×64        — three nested loops, indexed array
//   acc_sum             — tight integer arithmetic loop
//
// Drop into both cintsys and the wasm playground; the result
// numbers should match. Compare the elapsed times to gauge the
// relative speed of the Cintcode interpreter vs compiled wasm.

SECTION "bench"

GET "libhdr"

LET fib(n) = n < 2 -> n, fib(n - 1) + fib(n - 2)

LET sieve(upb) = VALOF
{ LET v = getvec(upb)
  LET hits = 0
  FOR i = 0 TO upb DO v!i := 1
  v!0, v!1 := 0, 0
  FOR i = 2 TO upb DO
    IF v!i DO
    { LET j = i + i
      WHILE j <= upb DO { v!j := 0; j := j + i }
    }
  FOR i = 2 TO upb DO IF v!i DO hits := hits + 1
  freevec(v)
  RESULTIS hits
}

LET matmul(n) = VALOF
{ LET A = getvec(n * n)
  LET B = getvec(n * n)
  LET C = getvec(n * n)
  LET trace = 0
  FOR i = 0 TO n - 1 DO
    FOR j = 0 TO n - 1 DO
    { A!(i * n + j) := (i + j) MOD 7
      B!(i * n + j) := (i - j) MOD 5 + 7
    }
  FOR i = 0 TO n - 1 DO
    FOR j = 0 TO n - 1 DO
    { LET s = 0
      FOR k = 0 TO n - 1 DO
        s := s + A!(i * n + k) * B!(k * n + j)
      C!(i * n + j) := s
    }
  FOR i = 0 TO n - 1 DO trace := trace + C!(i * n + i)
  freevec(A); freevec(B); freevec(C)
  RESULTIS trace
}

LET acc_sum(iters) = VALOF
{ LET acc = 0
  FOR i = 1 TO iters DO
  { acc := acc + i
    acc := acc XOR (i << 1)
    acc := acc - (i >> 2)
  }
  RESULTIS acc
}

// ms_now() — milliseconds since 1 Jan 1978 epoch. datstamp fills
// (days, ms-of-day, boot-ticks). Combine into a single integer; for
// short-running benchmarks we wrap at 24h which is fine.
LET ms_now() = VALOF
{ LET v = VEC 2
  datstamp(v)
  RESULTIS v!0 * 86400000 + v!1
}

LET run_phase(label, fn, arg) BE
{ LET t0 = ms_now()
  LET result = fn(arg)
  LET t1 = ms_now()
  writef("%s  arg=%n  result=%n  elapsed=%n ms*n",
         label, arg, result, t1 - t0)
}

LET start() = VALOF
{ writes("65-bench starting*n")
  run_phase("nfib",   fib,     32)
  run_phase("sieve",  sieve,   500000)
  run_phase("matmul", matmul,  96)
  run_phase("acc",    acc_sum, 5000000)
  writes("done*n")
  RESULTIS 0
}
