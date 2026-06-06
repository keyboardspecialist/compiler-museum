// 31-mkobj-helper: a reusable mkobj pattern.
//
// Concepts:
//   - libhdr.h declares mkobj, but it lives in blib (not wired here),
//     so we define a small one locally.
//   - Interface: mkobj(upb, fns, a)
//       upb  = highest field index (getvec allocates upb+1 words).
//       fns  = methods vector (becomes obj!0).
//       a    = address-passable first init argument.
//   - mkobj sends InitObj#(obj, @a) so the class's init method runs.
//   - Convention: every class reserves slot 0 of its methods vector
//     for InitObj (its init function).

SECTION "mkhelp"

GET "libhdr"

MANIFEST {
  InitObj  = 0   // standard method-slot index for init
  CloseObj = 1   // standard method-slot index for destroy
}

// Generic mkobj. Works for any class whose methods vector follows the
// InitObj-at-slot-0 convention.
LET mkobj(upb, fns, a) = VALOF
{ LET obj = getvec(upb)
  UNLESS obj RESULTIS 0
  obj!0 := fns
  InitObj#(obj, @a)
  RESULTIS obj
}

// A trivial class to exercise mkobj.
MANIFEST {
  Gf_val = 1       // Greeter.val
  Gf_upb = 1
  Gm_init    = InitObj
  Gm_destroy = CloseObj
  Gm_say     = 2
  Gm_upb     = 2
}

LET initGreeter(self, argv) BE self!Gf_val := argv!0
AND destroyGreeter(self) BE freevec(self)
AND sayGreeter(self) BE writef("hello from %s*n", self!Gf_val)

AND mkfns_Greeter() = VALOF
{ LET fns = getvec(Gm_upb)
  fns!Gm_init    := initGreeter
  fns!Gm_destroy := destroyGreeter
  fns!Gm_say     := sayGreeter
  RESULTIS fns
}

LET start() = VALOF
{ LET fns = mkfns_Greeter()
  LET alice = mkobj(Gf_upb, fns, "alice")
  LET bob   = mkobj(Gf_upb, fns, "bob")

  Gm_say#(alice)
  Gm_say#(bob)

  Gm_destroy#(alice)
  Gm_destroy#(bob)
  freevec(fns)
  RESULTIS 0
}
