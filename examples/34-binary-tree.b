// 34-binary-tree: a simple BST in BCPL.
//
// Concepts:
//   - Heap allocation via getvec(n) — returns a 0..n vector.
//   - Nodes are plain vectors; field names are MANIFEST offsets.
//   - 0 doubles as the null pointer (getvec never returns 0).
//   - Recursive insert, lookup, in-order traversal.
//   - freevec releases a node when the demo is done.

SECTION "btree"

GET "libhdr"

// Node layout — getvec(3) gives a 4-word vector.
MANIFEST {
  n_key   = 0
  n_val
  n_left
  n_right
  n_upb
}

LET newnode(k, v) = VALOF
{ LET p = getvec(n_upb)
  p!n_key   := k
  p!n_val   := v
  p!n_left  := 0
  p!n_right := 0
  RESULTIS p
}

// Insert (k, v) into tree rooted at t. Returns the (possibly new)
// root. Duplicate keys overwrite the value.
LET insert(t, k, v) = VALOF
{ IF t = 0 RESULTIS newnode(k, v)
  TEST k < t!n_key
  THEN t!n_left  := insert(t!n_left,  k, v)
  ELSE TEST k > t!n_key
       THEN t!n_right := insert(t!n_right, k, v)
       ELSE t!n_val := v             // key already present
  RESULTIS t
}

// Lookup — returns value if found, else -1. (-1 is fine as a sentinel
// because our test values are all positive.)
LET lookup(t, k) = VALOF
{ UNTIL t = 0 DO
  { TEST k < t!n_key
    THEN t := t!n_left
    ELSE TEST k > t!n_key
         THEN t := t!n_right
         ELSE RESULTIS t!n_val
  }
  RESULTIS -1
}

// In-order traversal: prints "key=value " for each node, sorted by key.
LET inorder(t) BE
  IF t DO
  { inorder(t!n_left)
    writef("%n=%n ", t!n_key, t!n_val)
    inorder(t!n_right)
  }

// Post-order free: drop children before parent so we don't dangle.
LET freetree(t) BE
  IF t DO
  { freetree(t!n_left)
    freetree(t!n_right)
    freevec(t)
  }

LET start() = VALOF
{ LET root = 0

  // Build a tree from an unsorted key list.
  LET keys = TABLE 5, 1, 9, 3, 7, 2, 8, 4, 6
  FOR i = 0 TO 8 DO root := insert(root, keys!i, keys!i * 10)

  writef("in-order: ")
  inorder(root)
  newline()

  // Lookup hits and one miss.
  writef("lookup 7  -> %n*n", lookup(root, 7))
  writef("lookup 1  -> %n*n", lookup(root, 1))
  writef("lookup 42 -> %n  (miss)*n", lookup(root, 42))

  // Overwrite a key and verify.
  root := insert(root, 5, 999)
  writef("after re-insert 5=999, lookup 5 -> %n*n", lookup(root, 5))

  freetree(root)
  RESULTIS 0
}
