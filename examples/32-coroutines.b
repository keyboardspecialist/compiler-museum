// 32-coroutines: BCPL coroutines via Asyncify-backed cowait/callco.
//
// Concepts:
//   - createco(fn, size) allocates a coroutine with its own stack.
//   - callco(c, arg) suspends the caller and resumes c with arg.
//   - cowait(arg) suspends the current coroutine, yielding arg to its
//     parent (whoever last called callco).
//   - The parent's callco then returns whatever the coroutine cowaited.
//   - The coroutine's body fn receives the FIRST callco arg as its
//     parameter; subsequent calls deliver values via cowait's return.

SECTION "co"

GET "libhdr"

LET counter(start) = VALOF
{ LET n = start
  cowait(n)         // first yield delivers initial value
  n := n + 1; cowait(n)
  n := n + 1; cowait(n)
  RESULTIS n + 1
}

LET start() = VALOF
{ LET c = createco(counter, 1024)
  writef("created coroutine, handle=%n*n", c)
  writef("first  callco -> %n*n", callco(c, 100))
  writef("second callco -> %n*n", callco(c, 0))
  writef("third  callco -> %n*n", callco(c, 0))
  writef("fourth callco -> %n  (counter returned)*n", callco(c, 0))
  deleteco(c)
  RESULTIS 0
}
