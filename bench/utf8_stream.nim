# Resumable UTF-8 validator.
#
# Build for speed with:
#   nim c -d:danger --passC:"-march=native" ...

const utf8Block = 61
const lookBehind = 3

type
  Utf8Validator* = object
    buff: array[lookBehind + utf8Block, char]
    pos: uint8
    error: uint8

# Usage:
# var utf8: Utf8Validator
# while stream.readable():
#   let c = stream.read()
#   utf8.push(c)
# echo utf8.isValid()

template isContinuation(b: uint8): uint8 =
  uint8(b >= 0x80'u8) and uint8(b < 0xC0'u8)

template mustBeContinuation(prev1, prev2, prev3: uint8): uint8 =
  template isSecondByte: untyped = uint8(prev1 >= 0xC0'u8)
  template isThirdByte: untyped = uint8(prev2 >= 0xE0'u8)
  template isFourthByte: untyped = uint8(prev3 >= 0xF0'u8)
  isSecondByte or isThirdByte or isFourthByte

template checkMultibyteLengths(isCont, prev1, prev2, prev3: uint8): uint8 =
  mustBeContinuation(prev1, prev2, prev3) xor isCont

template checkSpecialCases(input, prev1, isCont: uint8): uint8 =
  template geA0: untyped = uint8(input >= 0xA0'u8)
  template ge90: untyped = uint8(input >= 0x90'u8)
  template overlong2: untyped = uint8((prev1 and 0xFE'u8) == 0xC0'u8)
  template overlong3: untyped = uint8(prev1 == 0xE0'u8) and (geA0 xor 1'u8)
  template surrogate: untyped = uint8(prev1 == 0xED'u8) and geA0
  template overlong4: untyped = uint8(prev1 == 0xF0'u8) and (ge90 xor 1'u8)
  template tooLarge: untyped = uint8(prev1 == 0xF4'u8) and ge90
  template tooLargeN: untyped = uint8(prev1 >= 0xF5'u8)
  isCont and (overlong2 or overlong3 or surrogate or overlong4 or tooLarge or tooLargeN)

template checkUtf8Bytes(p: openArray[char], i: int): uint8 =
  template input: untyped = uint8(p[i])
  template prev1: untyped = uint8(p[i - 1])
  template prev2: untyped = uint8(p[i - 2])
  template prev3: untyped = uint8(p[i - 3])
  template isCont: untyped = isContinuation(input)
  checkSpecialCases(input, prev1, isCont) or
    checkMultibyteLengths(isCont, prev1, prev2, prev3)

template isIncomplete(prev1, prev2, prev3: uint8): uint8 =
  ## The check past the last byte of the stream. The absent byte is
  ## not a continuation, so `checkUtf8Bytes` reduces to this; ie: it
  ## is an error if the last character is still missing a byte.
  mustBeContinuation(prev1, prev2, prev3)

template isAscii(p: openArray[char], i: int): bool =
  var res = 0'u8
  for j in 0 ..< utf8Block + 3:
    res = res or uint8(p[i - 3 + j])
  res <= 0x7F'u8

when not defined(debug):
  {.push checks: off.}

func validateUtf8(p: openArray[char], first: int): uint8 =
  var error = 0'u8
  let n = p.len
  var i = first
  while i + utf8Block <= n:
    if not isAscii(p, i):
      for j in 0 ..< utf8Block:
        error = error or checkUtf8Bytes(p, i + j)
    i += utf8Block
  while i < n:
    error = error or checkUtf8Bytes(p, i)
    inc i
  error

func flush(v: var Utf8Validator) =
  let n = lookBehind + int(v.pos)
  v.error = v.error or validateUtf8(toOpenArray(v.buff, 0, n - 1), lookBehind)
  for i in 0 ..< lookBehind:
    v.buff[i] = v.buff[n - lookBehind + i]
  v.pos = 0

func push*(v: var Utf8Validator, c: char) {.inline.} =
  v.buff[lookBehind + int(v.pos)] = c
  inc v.pos
  if v.pos == utf8Block:
    v.flush()

func push*(v: var Utf8Validator, s: openArray[char]) =
  for c in s:
    v.push c

func isValid*(v: var Utf8Validator): bool =
  v.flush()
  let incomplete = isIncomplete(
    uint8(v.buff[lookBehind - 1]),
    uint8(v.buff[lookBehind - 2]),
    uint8(v.buff[lookBehind - 3]))
  (v.error or incomplete) == 0'u8

func reset*(v: var Utf8Validator) {.inline.} =
  ## Drop the stream and start over.
  v = Utf8Validator()

when not defined(debug):
  {.pop.}
