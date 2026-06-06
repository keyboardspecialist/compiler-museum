// 29-first-class: define a class with fields, methods, and init/destroy.
//
// Concepts:
//   - Class A = methods vector + fields vector.
//   - Slot 0 of each instance holds the methods vector pointer.
//   - Slots 0 and 1 of the methods vector are conventionally InitObj and
//     CloseObj. Slots 2+ are user methods.
//   - mkfns_A builds the methods table once, shared across instances.

SECTION "firstcl"

GET "libhdr"

// Method-slot indexes and field-slot indexes for class Counter.
MANIFEST {
  // Methods vector layout
  Cm_init    = 0
  Cm_destroy = 1
  Cm_inc     = 2
  Cm_show    = 3
  Cm_upb     = 3

  // Fields vector layout (slot 0 always holds methods ptr)
  Cf_count   = 1
  Cf_name    = 2
  Cf_upb     = 2
}

LET initCounter(self, argvec) BE
{ // argvec!0 is the 'a' slot per mkobj convention; we take a name string.
  self!Cf_count := 0
  self!Cf_name  := argvec!0
}

AND destroyCounter(self) BE freevec(self)

AND incCounter(self) BE self!Cf_count := self!Cf_count + 1

AND showCounter(self) BE
  writef("%s = %n*n", self!Cf_name, self!Cf_count)

AND mkfns_Counter() = VALOF
{ LET fns = getvec(Cm_upb)
  fns!Cm_init    := initCounter
  fns!Cm_destroy := destroyCounter
  fns!Cm_inc     := incCounter
  fns!Cm_show    := showCounter
  RESULTIS fns
}

// Tiny local mkobj — libhdr's version isn't wired in the playground.
// upb+1 words allocated, slot 0 set to fns, then InitObj#(obj, args).
AND mkobj(upb, fns, a) = VALOF
{ LET obj = getvec(upb)
  UNLESS obj RESULTIS 0
  obj!0 := fns
  Cm_init#(obj, @a)
  RESULTIS obj
}

LET start() = VALOF
{ LET fns = mkfns_Counter()
  LET c1  = mkobj(Cf_upb, fns, "clicks")
  LET c2  = mkobj(Cf_upb, fns, "pings")

  Cm_inc#(c1); Cm_inc#(c1); Cm_inc#(c1)
  Cm_inc#(c2)

  Cm_show#(c1)
  Cm_show#(c2)

  Cm_destroy#(c1)
  Cm_destroy#(c2)
  freevec(fns)
  RESULTIS 0
}
