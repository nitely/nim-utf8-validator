## Differential tests for validateUtf8
##
## Every input is validated by three independent implementations:
## the one under test, the branchy validator derived from the UTF-8
## spec table, and Hoehrmann's DFA. They must always agree.
##
## Run:
##   nim c -r -d:danger --passC:"-march=native" tests/test_validator.nim

import std/[random, strutils]
import ../utf8_validator as nitely
import ../bench/utf8_branchy as branchy
import ../bench/utf8_dfa as dfa

var failures = 0
var checked = 0

proc check(s: openArray[char], tag: string) =
  ## The three validators must return the same verdict.
  let a = nitely.validateUtf8(s)
  let b = branchy.validateUtf8(s)
  let c = dfa.validateUtf8(s)
  inc checked
  if a != b or a != c:
    inc failures
    if failures <= 20:
      var hex = ""
      for ch in s:
        hex.add toHex(uint8(ch), 2)
      echo "MISMATCH [", tag, "] nitely=", a, " branchy=", b, " dfa=", c,
        " len=", s.len, " bytes=", hex

proc expect(s: string, want: bool, tag: string) =
  ## As `check`, and the verdict must be `want`.
  check(s, tag)
  let got = nitely.validateUtf8(s)
  if got != want:
    inc failures
    echo "WRONG VERDICT [", tag, "] got=", got, " want=", want

proc encode(cp: int): string =
  ## Encode a code point, assuming it is not a surrogate.
  if cp < 0x80:
    result = $chr(cp)
  elif cp < 0x800:
    result = $chr(0xC0 or (cp shr 6)) &
             $chr(0x80 or (cp and 0x3F))
  elif cp < 0x10000:
    result = $chr(0xE0 or (cp shr 12)) &
             $chr(0x80 or ((cp shr 6) and 0x3F)) &
             $chr(0x80 or (cp and 0x3F))
  else:
    result = $chr(0xF0 or (cp shr 18)) &
             $chr(0x80 or ((cp shr 12) and 0x3F)) &
             $chr(0x80 or ((cp shr 6) and 0x3F)) &
             $chr(0x80 or (cp and 0x3F))

## Bytes worth trying at every position: the edges of every range in
## the well-formedness table, plus bytes that never start a character.
const alphabet = [
  0x00, 0x41, 0x7F,              # ascii
  0x80, 0x8F, 0x90, 0x9F,        # continuations, F4 and F0 edges
  0xA0, 0xBF,                    # continuations, E0 and ED edges
  0xC0, 0xC1,                    # overlong 2-byte leads
  0xC2, 0xDF,                    # 2-byte leads
  0xE0, 0xE1, 0xEC, 0xED, 0xEE, 0xEF,  # 3-byte leads
  0xF0, 0xF1, 0xF3, 0xF4,        # 4-byte leads
  0xF5, 0xFF                     # beyond U+10FFFF
]

proc namedVectors() =
  expect("", true, "empty")
  expect("hello, world", true, "ascii")
  expect("\x00\x01\x7F", true, "ascii controls")

  expect("\xC2\x80", true, "U+0080, shortest 2-byte")
  expect("\xDF\xBF", true, "U+07FF")
  expect("\xE0\xA0\x80", true, "U+0800, shortest 3-byte")
  expect("\xED\x9F\xBF", true, "U+D7FF, last before surrogates")
  expect("\xEE\x80\x80", true, "U+E000, first after surrogates")
  expect("\xEF\xBF\xBF", true, "U+FFFF")
  expect("\xF0\x90\x80\x80", true, "U+10000, shortest 4-byte")
  expect("\xF4\x8F\xBF\xBF", true, "U+10FFFF, last code point")

  expect("\x80", false, "lone continuation")
  expect("\xBF", false, "lone continuation")
  expect("\xC0\x80", false, "overlong NUL")
  expect("\xC1\xBF", false, "overlong U+007F")
  expect("\xE0\x9F\xBF", false, "overlong 3-byte")
  expect("\xF0\x8F\xBF\xBF", false, "overlong 4-byte")
  expect("\xED\xA0\x80", false, "surrogate U+D800")
  expect("\xED\xBF\xBF", false, "surrogate U+DFFF")
  expect("\xF4\x90\x80\x80", false, "U+110000, too large")
  expect("\xF5\x80\x80\x80", false, "F5 lead")
  expect("\xFF", false, "FF lead")

  expect("\xC2", false, "truncated 2-byte")
  expect("\xE0\xA0", false, "truncated 3-byte")
  expect("\xF0\x90\x80", false, "truncated 4-byte")
  expect("a\xF0\x90\x80", false, "truncated 4-byte after ascii")
  expect("\xC2\x41", false, "2-byte lead, non-continuation")
  expect("\xF0\xC2\x80", false, "4-byte lead, lead in place of continuation")
  expect("\xC2\x80\x80", false, "unrequired continuation")
  echo "named vectors:      ok (", checked, " inputs)"

proc exhaustiveShort() =
  ## Every input of length 1, 2 and 3. This covers all overlongs, all
  ## surrogates and every truncation of a 2- or 3-byte character.
  var s = newString(3)
  for a in 0 .. 255:
    s[0] = chr(a)
    check(s.toOpenArray(0, 0), "len1")
    for b in 0 .. 255:
      s[1] = chr(b)
      check(s.toOpenArray(0, 1), "len2")
      for c in 0 .. 255:
        s[2] = chr(c)
        check(s.toOpenArray(0, 2), "len3")
  echo "exhaustive len 1..3: ok"

proc sweepAlphabet() =
  ## Every input of length 4 and 5 drawn from the boundary alphabet.
  var s = newString(5)
  for a in alphabet:
    s[0] = chr(a)
    for b in alphabet:
      s[1] = chr(b)
      for c in alphabet:
        s[2] = chr(c)
        for d in alphabet:
          s[3] = chr(d)
          check(s.toOpenArray(0, 3), "len4")
          for e in alphabet:
            s[4] = chr(e)
            check(s.toOpenArray(0, 4), "len5")
  echo "alphabet len 4..5:   ok"

proc blockBoundaries() =
  ## The ascii fast path skips a block only when the block and the
  ## three bytes before it are ascii. These inputs put leads,
  ## continuations and errors at every offset around a boundary.

  # The case the three-byte lookbehind margin exists for: a lead in the
  # tail of one block, its missing continuation in the next. Without the
  # margin the second block scans as pure ascii and the error is skipped.
  for n in [300, 600, 1200]:
    for pos in 0 ..< n - 1:
      var s = repeat('a', n)
      s[pos] = '\xC2'
      s[pos + 1] = 'A'
      expect(s, false, "lead then non-continuation @" & $pos)

  # A single byte that can never appear on its own.
  for n in [259, 260, 300, 515, 516, 700, 1024]:
    for pos in 0 ..< n:
      for bad in [0x80, 0xBF, 0xC0, 0xC1, 0xF5, 0xFF]:
        var s = repeat('a', n)
        s[pos] = chr(bad)
        expect(s, false, "stray " & toHex(uint8(bad), 2) & " @" & $pos)

  # Valid characters straddling every offset, and every truncation of
  # one at the end of the buffer.
  const chars = ["\xC2\x80", "\xDF\xBF", "\xE0\xA0\x80", "\xED\x9F\xBF",
                 "\xEE\x80\x80", "\xF0\x90\x80\x80", "\xF4\x8F\xBF\xBF"]
  for ch in chars:
    for pos in 0 .. 700 - ch.len:
      var s = repeat('a', 700)
      for k in 0 ..< ch.len:
        s[pos + k] = ch[k]
      expect(s, true, "straddling character @" & $pos)
      for cut in 1 ..< ch.len:
        expect(repeat('a', pos) & ch[0 ..< ch.len - cut], false,
          "truncated character @" & $pos)
  echo "block boundaries:    ok"

proc fuzz() =
  ## Long inputs: valid text, the same text corrupted, and the same
  ## text truncated at a random point.
  var rng = initRand(0x5EED)
  for trial in 0 ..< 4000:
    var s = ""
    let target = rng.rand(0 .. 3000)
    while s.len < target:
      let r = rng.rand(100)
      var cp =
        if r < 70: rng.rand(0x20 .. 0x7E)
        elif r < 82: rng.rand(0x80 .. 0x7FF)
        elif r < 94: rng.rand(0x800 .. 0xFFFF)
        else: rng.rand(0x10000 .. 0x10FFFF)
      if cp in 0xD800 .. 0xDFFF: cp = 0xFFFD
      s.add encode(cp)
    expect(s, true, "valid text")
    if s.len == 0: continue
    var corrupt = s
    for _ in 0 ..< rng.rand(1 .. 3):
      corrupt[rng.rand(0 ..< corrupt.len)] = chr(rng.rand(0 .. 255))
    check(corrupt, "corrupted text")
    check(s[0 ..< rng.rand(0 ..< s.len)], "truncated text")

  # Uniformly random bytes: mostly invalid, but it reaches shapes the
  # generator above never produces.
  for trial in 0 ..< 2000:
    let n = rng.rand(0 .. 1200)
    var s = newString(n)
    for i in 0 ..< n:
      s[i] = if rng.rand(100) < 85: chr(rng.rand(0x00 .. 0x7F))
             else: chr(rng.rand(0x00 .. 0xFF))
    check(s, "random bytes")
  echo "fuzz:                ok"

when isMainModule:
  when not defined(danger):
    echo "note: build with -d:danger, the exhaustive sweeps are slow otherwise"
  namedVectors()
  exhaustiveShort()
  sweepAlphabet()
  blockBoundaries()
  fuzz()
  echo ""
  echo checked, " inputs checked, ", failures, " failures"
  if failures > 0:
    quit(1)
