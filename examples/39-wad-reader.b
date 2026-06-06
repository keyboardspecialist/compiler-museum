// 39-wad-reader: parse a Doom WAD file header and lump directory.
//
// Setup:
//   1. Open the Assets tab.
//   2. + asset, pick any WAD in site/textures/Wads/
//      (Doom1.WAD, doom2.wad, plutonia.wad, tnt.wad, etc.). Filename
//      casing does not matter — the example walks Sys_assetlist and
//      picks the first name ending in .wad (case-insensitive).
//      Non-image extensions are stored as a binary blob.
//   3. Compile & Run.
//
// What it does:
//   - Sys_assetload returns info!0 = byte length, info!1 = 0, info!2 =
//     word address of the raw bytes. BCPL reads bytes via `base % i`.
//   - Parses the 12-byte WAD header (magic + lump count + dir offset).
//   - Walks the directory, printing each lump's file offset, size and
//     8-byte ASCII name.
//
// WAD format (little-endian throughout):
//   header  [12 bytes]
//     0..3   magic     "IWAD" / "PWAD"
//     4..7   numlumps  i32
//     8..11  infotabs  i32   (byte offset of directory)
//   dir entry [16 bytes, repeated numlumps times]
//     0..3   filepos   i32
//     4..7   size      i32
//     8..15  name      8 ASCII bytes (NUL-padded)

SECTION "wadrd"

GET "libhdr"

MANIFEST {
  HDR_SIZE         = 12
  HDR_NUMLUMPS_OFS =  4
  HDR_INFOOFS_OFS  =  8
  DIR_ENTRY_SIZE   = 16
  DIR_FILEPOS_OFS  =  0
  DIR_SIZE_OFS     =  4
  DIR_NAME_OFS     =  8
  NAME_LEN         =  8
  MAX_PRINT        = 32
}

// Little-endian i32 read at byte offset `off` from word base `base`.
// BCPL's `%` operator does a byte fetch: (base % off) reads the byte
// at byte address (base*4 + off).
LET rd_u32_le(base, off) = VALOF
{ LET b0 = base % (off + 0)
  LET b1 = base % (off + 1)
  LET b2 = base % (off + 2)
  LET b3 = base % (off + 3)
  RESULTIS b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
}

// Print 4 ASCII bytes starting at byte offset.
LET pr_ascii4(base, off) BE
  FOR i = 0 TO 3 DO wrch(base % (off + i))

// Print up to NAME_LEN ASCII bytes; stops at first NUL.
LET pr_lumpname(base, off) BE
{ LET n = 0
  FOR i = 0 TO NAME_LEN - 1 DO
  { LET c = base % (off + i)
    IF c = 0 BREAK
    wrch(c)
    n := n + 1
  }
  // Pad with spaces so the trailing columns line up.
  FOR i = n TO NAME_LEN - 1 DO wrch('*s')
}

// ASCII lowercase helper.
LET lc(c) = c >= 'A' & c <= 'Z' -> c + ('a' - 'A'), c

// TRUE if buf[start..end-1] ends in ".wad" (case-insensitive).
LET ends_with_wad(buf, start, end) = VALOF
{ LET n = end - start
  IF n < 4 RESULTIS FALSE
  RESULTIS lc(buf % (end - 4)) = '.' &
           lc(buf % (end - 3)) = 'w' &
           lc(buf % (end - 2)) = 'a' &
           lc(buf % (end - 1)) = 'd'
}

// Copy buf[start..end-1] into dest as a BCPL string (length byte +
// chars). dest must have room for n+1 bytes.
LET cp_substr(buf, start, end, dest) BE
{ LET n = end - start
  dest % 0 := n
  FOR i = 0 TO n - 1 DO dest % (i + 1) := buf % (start + i)
}

// Walk the comma-separated asset list. For the first name ending in
// .wad / .WAD, load it and return TRUE. Case-insensitive, so
// "Doom1.WAD", "doom1.wad", "plutonia.wad" — all match.
LET try_load(info) = VALOF
{ LET listbuf = VEC 64       // 256 bytes — fits up to 255-char list
  LET namebuf = VEC 32       // 128 bytes — plenty for any asset name
  LET totlen, start, end = 0, 0, 0

  sys(Sys_assetlist, listbuf)
  totlen := listbuf % 0
  start  := 1
  end    := 1
  WHILE end <= totlen DO
  { WHILE end <= totlen & listbuf % end ~= ',' DO end := end + 1
    IF ends_with_wad(listbuf, start, end) DO
    { cp_substr(listbuf, start, end, namebuf)
      IF sys(Sys_assetload, namebuf, info) DO
      { writef("loaded asset: ")
        FOR i = start TO end - 1 DO wrch(listbuf % i)
        newline()
        RESULTIS TRUE
      }
    }
    end   := end + 1
    start := end
  }
  RESULTIS FALSE
}

LET start() = VALOF
{ LET info  = VEC 3
  LET base  = 0
  LET nbytes = 0
  LET numlumps, dirofs = 0, 0

  UNLESS try_load(info) DO
  { writef("No WAD asset uploaded. Open the Assets tab and add e.g.*n")
    writef("  doom1.wad, plutonia.wad, tnt.wad from site/textures/Wads/*n")
    RESULTIS 1
  }

  nbytes := info!0
  // info!1 = 0 for binary; sanity-check.
  IF info!1 ~= 0 DO
  { writef("Asset is an image, not a WAD.*n")
    RESULTIS 1
  }
  base := info!2

  IF nbytes < HDR_SIZE DO
  { writef("Too short to be a WAD (%n bytes).*n", nbytes)
    RESULTIS 1
  }

  writef("magic     = "); pr_ascii4(base, 0); newline()
  numlumps := rd_u32_le(base, HDR_NUMLUMPS_OFS)
  dirofs   := rd_u32_le(base, HDR_INFOOFS_OFS)
  writef("numlumps  = %n*n", numlumps)
  writef("dir ofs   = %n  (0x%x8)*n", dirofs, dirofs)
  writef("size      = %n bytes*n*n", nbytes)

  // Bounds-check directory.
  TEST dirofs + numlumps * DIR_ENTRY_SIZE > nbytes
  THEN { writef("Directory extends past EOF — file truncated?*n")
         RESULTIS 1
       }
  ELSE { LET printcap = numlumps
         IF printcap > MAX_PRINT DO printcap := MAX_PRINT
         writef("first %n of %n lumps:*n", printcap, numlumps)
         writef("  idx  filepos    size  name*n")
         writef("  ---  -------    ----  --------*n")
         FOR i = 0 TO printcap - 1 DO
         { LET e = dirofs + i * DIR_ENTRY_SIZE
           LET fp = rd_u32_le(base, e + DIR_FILEPOS_OFS)
           LET sz = rd_u32_le(base, e + DIR_SIZE_OFS)
           writef("  %i3  %i7  %i6  ", i, fp, sz)
           pr_lumpname(base, e + DIR_NAME_OFS)
           newline()
         }
         IF numlumps > MAX_PRINT DO
           writef("  ... (%n more)*n", numlumps - MAX_PRINT)
       }

  newline()
  writef("wadrd done.*n")
  RESULTIS 0
}
