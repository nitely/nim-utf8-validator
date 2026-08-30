## Differential tests for the resumable validator
##
## The streaming validator must agree with the whole-string validator
## on every input, whatever the chunking.
##
## Run:
##   nim c -r -d:danger --passC:"-march=native" tests/test_stream.nim

import std/[random, strutils]
import ../utf8_validator as whole
import ../bench/utf8_stream as stream

var failures = 0
var checked = 0
var rng = initRand(0xC0FFEE)

proc report(s: openArray[char], tag: string, want, got: bool) =
  inc failures
  if failures <= 20:
    var hex = ""
    for ch in s: hex.add toHex(uint8(ch), 2)
    echo "MISMATCH [", tag, "] whole=", want, " stream=", got,
      " len=", s.len, " bytes=", (if hex.len > 200: hex[0..199] & "..." else: hex)

proc check(s: openArray[char], tag: string) =
  let want = whole.validateUtf8(s)
  inc checked
  # the whole-input API, on top of the stream API
  if stream.validateUtf8(s) != want:
    report(s, tag & "/whole", want, stream.validateUtf8(s))
    return
  # one byte at a time
  var v: stream.Utf8Validator
  for c in s:
    v.push c
  if v.isValid() != want:
    report(s, tag & "/byte", want, v.isValid())
    return
  # calling isValid again must not change the verdict
  if v.isValid() != want:
    report(s, tag & "/twice", want, v.isValid())
    return
  # random chunks
  for _ in 0 .. 2:
    var w: stream.Utf8Validator
    var i = 0
    while i < s.len:
      let n = min(rng.rand(1 .. 200), s.len - i)
      w.push toOpenArray(s, i, i + n - 1)
      i += n
    if w.isValid() != want:
      report(s, tag & "/chunk", want, w.isValid())
      return
  # reset must give a clean slate
  var r: stream.Utf8Validator
  r.push "\xF0\x90"
  discard r.isValid()
  r.reset()
  r.push s
  if r.isValid() != want:
    report(s, tag & "/reset", want, r.isValid())

proc exhaustiveShort() =
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

proc boundaries() =
  ## Errors and characters at every offset around the 64 byte blocks.
  const chars = ["\xC2\x80", "\xDF\xBF", "\xE0\xA0\x80", "\xED\x9F\xBF",
                 "\xEE\x80\x80", "\xF0\x90\x80\x80", "\xF4\x8F\xBF\xBF",
                 "\xC2\x41", "\xED\xA0\x80", "\xF0\x8F\xBF\xBF", "\xF5\x80"]
  for n in [64, 65, 67, 68, 127, 128, 129, 130, 131, 192, 200,
            511, 512, 513, 514, 515, 517, 1023, 1024, 1027]:
    for ch in chars:
      for pos in 0 .. n - ch.len:
        var s = repeat('a', n)
        for k in 0 ..< ch.len:
          s[pos + k] = ch[k]
        check(s, "straddle @" & $pos & "/" & $n)
      for cut in 1 ..< ch.len:  # truncated at the end
        check(repeat('a', n) & ch[0 ..< ch.len - cut], "truncated/" & $n)
    for pos in 0 ..< n:
      for bad in [0x80, 0xBF, 0xC0, 0xC1, 0xF5, 0xFF]:
        var s = repeat('a', n)
        s[pos] = chr(bad)
        check(s, "stray @" & $pos & "/" & $n)
  echo "block boundaries:    ok"

proc bigBoundaries() =
  ## Inputs long enough to fill the buffer several times over, so that
  ## a flush, and the lookbehind it carries, happen mid stream. Offsets
  ## are swept in windows around every multiple of 256; whatever the
  ## block and buffer sizes are tuned to, their boundaries land there.
  const chars = ["\xC2\x80", "\xDF\xBF", "\xE0\xA0\x80", "\xF0\x90\x80\x80",
                 "\xC2\x41", "\xED\xA0\x80", "\xF5\x80"]
  for n in [8191, 8192, 8193, 8195, 16384, 16387, 24579]:
    var stops: seq[int] = @[]
    var b = 0
    while b <= n:
      for d in -6 .. 6:
        if b + d >= 0 and b + d <= n:
          stops.add b + d
      b += 256
    for ch in chars:
      for pos in stops:
        if pos > n - ch.len: continue
        var s = repeat('a', n)
        for k in 0 ..< ch.len:
          s[pos + k] = ch[k]
        check(s, "big straddle @" & $pos & "/" & $n)
      check(repeat('a', n) & ch[0 ..< ch.len - 1], "big truncated/" & $n)
  echo "buffer boundaries:   ok"

proc encode(cp: int): string =
  if cp < 0x80: $chr(cp)
  elif cp < 0x800: $chr(0xC0 or (cp shr 6)) & $chr(0x80 or (cp and 0x3F))
  elif cp < 0x10000: $chr(0xE0 or (cp shr 12)) & $chr(0x80 or ((cp shr 6) and 0x3F)) &
                     $chr(0x80 or (cp and 0x3F))
  else: $chr(0xF0 or (cp shr 18)) & $chr(0x80 or ((cp shr 12) and 0x3F)) &
        $chr(0x80 or ((cp shr 6) and 0x3F)) & $chr(0x80 or (cp and 0x3F))

proc fuzz() =
  for trial in 0 ..< 3000:
    var s = ""
    let target = rng.rand(0 .. 20000)
    while s.len < target:
      let r = rng.rand(100)
      var cp =
        if r < 70: rng.rand(0x20 .. 0x7E)
        elif r < 82: rng.rand(0x80 .. 0x7FF)
        elif r < 94: rng.rand(0x800 .. 0xFFFF)
        else: rng.rand(0x10000 .. 0x10FFFF)
      if cp in 0xD800 .. 0xDFFF: cp = 0xFFFD
      s.add encode(cp)
    check(s, "valid text")
    if s.len == 0: continue
    var corrupt = s
    for _ in 0 ..< rng.rand(1 .. 3):
      corrupt[rng.rand(0 ..< corrupt.len)] = chr(rng.rand(0 .. 255))
    check(corrupt, "corrupted")
    check(s[0 ..< rng.rand(0 ..< s.len)], "truncated")
  for trial in 0 ..< 2000:
    let n = rng.rand(0 .. 20000)
    var s = newString(n)
    for i in 0 ..< n:
      s[i] = if rng.rand(100) < 85: chr(rng.rand(0x00 .. 0x7F))
             else: chr(rng.rand(0x00 .. 0xFF))
    check(s, "random bytes")
  echo "fuzz:                ok"

proc resumable() =
  ## A stream that ends mid character is invalid, but a later push
  ## may still complete it; the verdict must not be sticky.
  var v: stream.Utf8Validator
  v.push '\xF0'
  doAssert not v.isValid()
  v.push '\x90'
  doAssert not v.isValid()
  v.push '\x80'
  doAssert not v.isValid()
  v.push '\x80'
  doAssert v.isValid()
  v.push 'a'
  doAssert v.isValid()
  # an error, on the other hand, is sticky
  v.push '\xC0'
  v.push '\x80'
  doAssert not v.isValid()
  v.push 'a'
  doAssert not v.isValid()
  # incomplete right on a block boundary
  for n in [63, 64, 65, 66, 67, 127, 128,
            509, 510, 511, 512, 513, 514, 1022, 1024, 1026]:
    var w: stream.Utf8Validator
    w.push repeat('a', n)
    doAssert w.isValid()
    w.push '\xE0'
    doAssert not w.isValid()
    w.push '\xA0'
    doAssert not w.isValid()
    w.push '\x80'
    doAssert w.isValid(), $n
  echo "resumable:           ok"

when isMainModule:
  when not defined(danger):
    echo "note: build with -d:danger, the exhaustive sweep is slow otherwise"
  resumable()
  boundaries()
  bigBoundaries()
  fuzz()
  exhaustiveShort()
  echo ""
  echo checked, " inputs checked, ", failures, " failures"
  if failures > 0: quit(1)
