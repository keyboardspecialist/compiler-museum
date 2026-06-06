// 02-comments: how to annotate BCPL source.
//
// Concepts:
//   - // starts a comment that runs to end of line.
//   - /* ... */ starts a block comment.
//   - Block comments do NOT nest in BCPL.

SECTION "comments"

GET "libhdr"

/*
   This is a block comment.
   It can span multiple lines.
   Block comments do not nest.
*/

LET start() = VALOF
{ // Line comments are the most common form.
  writef("comments work*n")
  RESULTIS 0
}
