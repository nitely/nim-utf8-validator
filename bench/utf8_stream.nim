# Resumable UTF-8 validator.
#
# Build for speed with:
#   nim c -d:danger --passC:"-march=native" ...

const utf8Block = 256
const buffSize = 4 * 1024
const lookBehind = 3

static: doAssert buffSize <= int(high(uint16))
static: doAssert buffSize mod utf8Block == 0

type
  Utf8Validator* = object
    buff: array[lookBehind + buffSize, char]
    pos: uint16
    error: uint8

proc `=copy`*(dst: var Utf8Validator, src: Utf8Validator) {.error.}

# Usage:
# var utf8: Utf8Validator
# while stream.readable():
#   let c = stream.read()
#   utf8.push(c)
# echo utf8.isValid()

template isContinuation(b: uint8): uint8 =
  uint8(b >= 0x80'u8) and uint8(b < 0xC0'u8)

template mustBeContinuation(prev1, prev2, prev3: uint8): uint8 =
  uint8(prev1 >= 0xC0'u8) or uint8(prev2 >= 0xE0'u8) or uint8(prev3 >= 0xF0'u8)

template checkMultibyteLengths(input, prev1, prev2, prev3: uint8): uint8 =
  mustBeContinuation(prev1, prev2, prev3) xor isContinuation(input)

template checkSpecialCases(input, prev1: uint8): uint8 =
  isContinuation(input) and (
    uint8((prev1 and 0xFE'u8) == 0xC0'u8) or
    uint8(prev1 == 0xE0'u8) and (uint8(input >= 0xA0'u8) xor 1'u8) or
    uint8(prev1 == 0xED'u8) and uint8(input >= 0xA0'u8) or
    uint8(prev1 == 0xF0'u8) and (uint8(input >= 0x90'u8) xor 1'u8) or
    uint8(prev1 == 0xF4'u8) and uint8(input >= 0x90'u8) or
    uint8(prev1 >= 0xF5'u8)
  )

template checkUtf8Bytes(p: openArray[char], i: int): uint8 =
  template input: uint8 = uint8(p[i])
  template prev1: uint8 = uint8(p[i - 1])
  template prev2: uint8 = uint8(p[i - 2])
  template prev3: uint8 = uint8(p[i - 3])
  checkSpecialCases(input, prev1) or
    checkMultibyteLengths(input, prev1, prev2, prev3)

template isIncomplete(prev1, prev2, prev3: uint8): uint8 =
  mustBeContinuation(prev1, prev2, prev3)

template isAscii(p: openArray[char], i: int): bool =
  var res = 0'u8
  for j in 0 ..< utf8Block + 3:
    res = res or uint8(p[i - 3 + j])
  res <= 0x7F'u8

when not defined(debug):
  {.push checks: off.}

func validateBlock(p: openArray[char], first: int): uint8 =
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
  v.error = v.error or validateBlock(toOpenArray(v.buff, 0, n - 1), lookBehind)
  for i in 0 ..< lookBehind:
    v.buff[i] = v.buff[n - lookBehind + i]
  v.pos = 0

func push*(v: var Utf8Validator, c: char) =
  v.buff[lookBehind + int(v.pos)] = c
  inc v.pos
  if v.pos == buffSize:
    v.flush()

func push*(v: var Utf8Validator, s: openArray[char]) =
  var i = 0
  while i < s.len:
    let n = min(buffSize - int(v.pos), s.len - i)
    for k in 0 ..< n:
      v.buff[lookBehind + int(v.pos) + k] = s[i + k]
    v.pos += uint16(n)
    if v.pos == buffSize:
      v.flush()
    i += n

func isValid*(v: var Utf8Validator): bool =
  v.flush()
  let incomplete = isIncomplete(
    uint8(v.buff[lookBehind - 1]),
    uint8(v.buff[lookBehind - 2]),
    uint8(v.buff[lookBehind - 3]))
  (v.error or incomplete) == 0'u8

func validateUtf8*(p: openArray[char]): bool =
  ## Validate a whole input in one go, through the stream API.
  var v = Utf8Validator()
  v.push p
  v.isValid()

when not defined(debug):
  {.pop.}
