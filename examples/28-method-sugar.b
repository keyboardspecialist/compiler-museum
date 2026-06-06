// 28-method-sugar: BCPL's OOP call syntax.
//
// Concepts:
//   - E#(E1, E2, ...)  is sugar for  (E1!0!E)(E1, E2, ...)
//   - E1 is the object; E1!0 is a pointer to its methods vector.
//   - E is the index of the method in that vector.
//   - The parser desugars this at compile time (see bcplsyn.b s_mthap).
//     The backend never sees a distinct "method-call" opcode.

SECTION "mthsug"

GET "libhdr"

MANIFEST { M_greet = 0; M_shout = 1 }

LET greet(obj, name) BE writef("hello, %s (obj at %n)*n", name, obj)
AND shout(obj, what) BE writef("%s!!!*n", what)

LET start() = VALOF
{ // Build a tiny methods vector and an object pointing at it.
  LET fns = VEC 2
  LET obj = VEC 1

  fns!M_greet := greet
  fns!M_shout := shout
  obj!0 := fns

  // Method-call sugar:
  M_greet#(obj, "world")
  M_shout#(obj, "hi")

  // Equivalent desugared form (compiles to the same code):
  ((!obj)!M_greet)(obj, "world (desugared)")
  RESULTIS 0
}
