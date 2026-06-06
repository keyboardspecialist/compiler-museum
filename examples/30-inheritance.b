// 30-inheritance: derive class ShoutCounter from Counter.
//
// Concepts:
//   - A derived class has its own methods vector, at least as large as
//     the parent's.
//   - Override methods by writing the new function into the derived slot.
//   - To invoke the parent's version, keep a private back-pointer slot.
//   - No runtime machinery is needed — everything is vectors of pointers.

SECTION "inher"

GET "libhdr"

MANIFEST {
  // Base Counter methods
  Cm_init    = 0
  Cm_destroy = 1
  Cm_inc     = 2
  Cm_show    = 3
  Cm_upb     = 3

  // Derived ShoutCounter adds a back-pointer to the parent 'show'
  // and a new method 'reset'.
  Sm_prev_show = 4
  Sm_reset     = 5
  Sm_upb       = 5

  // Fields (both classes share the same layout; derived may extend)
  Cf_count = 1
  Cf_name  = 2
  Cf_upb   = 2
}

// Base implementations reused from lesson 29.
LET initCounter(self, argvec) BE
{ self!Cf_count := 0
  self!Cf_name  := argvec!0
}
AND destroyCounter(self) BE freevec(self)
AND incCounter(self) BE self!Cf_count := self!Cf_count + 1
AND showCounter(self) BE
  writef("%s = %n*n", self!Cf_name, self!Cf_count)

// Derived override: shout in capitals using writef's %s then a '!'.
AND showShout(self) BE
{ writef("%s == %n !!!*n", self!Cf_name, self!Cf_count)
  // Call the parent method via the saved back-pointer:
  Sm_prev_show#(self)
}

AND resetShout(self) BE self!Cf_count := 0

AND mkfns_Counter() = VALOF
{ LET fns = getvec(Cm_upb)
  fns!Cm_init    := initCounter
  fns!Cm_destroy := destroyCounter
  fns!Cm_inc     := incCounter
  fns!Cm_show    := showCounter
  RESULTIS fns
}

AND mkfns_Shout(pfns) = VALOF
{ LET fns = getvec(Sm_upb)
  // Copy parent methods first.
  FOR i = 0 TO Cm_upb DO fns!i := pfns!i
  // Override 'show' with our louder version, keep parent's in a slot.
  fns!Cm_show     := showShout
  fns!Sm_prev_show := pfns!Cm_show
  fns!Sm_reset    := resetShout
  RESULTIS fns
}

AND mkobj(upb, fns, a) = VALOF
{ LET obj = getvec(upb)
  UNLESS obj RESULTIS 0
  obj!0 := fns
  Cm_init#(obj, @a)
  RESULTIS obj
}

LET start() = VALOF
{ LET base_fns  = mkfns_Counter()
  LET shout_fns = mkfns_Shout(base_fns)

  LET plain = mkobj(Cf_upb, base_fns,  "plain")
  LET loud  = mkobj(Cf_upb, shout_fns, "loud")

  Cm_inc#(plain); Cm_inc#(plain)
  Cm_inc#(loud);  Cm_inc#(loud); Cm_inc#(loud)

  Cm_show#(plain)
  Cm_show#(loud)   // calls showShout, which chains to showCounter via prev

  Sm_reset#(loud)
  Cm_show#(loud)

  Cm_destroy#(plain)
  Cm_destroy#(loud)
  freevec(base_fns)
  freevec(shout_fns)
  RESULTIS 0
}
