# UTF-8 validator
#
# Build for speed with:
#   nim c -d:danger --passC:"-march=native" ...

# tune as you please
# 64, 128, 256, 512 are good values to try
const utf8Block = 256

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

template checkBytes(input, prev1, prev2, prev3: uint8): uint8 =
  ## as `checkUtf8Bytes`, over bytes the caller already has
  template isCont: untyped = isContinuation(input)
  checkSpecialCases(input, prev1, isCont) or
    checkMultibyteLengths(isCont, prev1, prev2, prev3)

template isIncomplete(p: openArray[char], n: int): uint8 =
  ## The absent byte at `n` is not a continuation, so `checkUtf8Bytes`
  ## keeps only its length test. A byte before the start reads as zero.
  mustBeContinuation(
    (if n >= 1: uint8(p[n - 1]) else: 0'u8),
    (if n >= 2: uint8(p[n - 2]) else: 0'u8),
    (if n >= 3: uint8(p[n - 3]) else: 0'u8))

template isAsciiRange(p: openArray[char], n: int): bool =
  var res = 0'u8
  for j in 0 ..< n:
    res = res or uint8(p[j])
  res <= 0x7F'u8

template isAscii(p: openArray[char], i: int): bool =
  var res = 0'u8
  for j in 0 ..< utf8Block + 3:
    res = res or uint8(p[i - 3 + j])
  res <= 0x7F'u8

when not defined(debug):
  {.push checks: off.}
func validateUtf8*(p: openArray[char]): bool =
  var error = 0'u8
  let n = p.len
  if n < utf8Block + 3 and isAsciiRange(p, n):
    return true
  if n > 0:
    error = error or isContinuation(uint8(p[0]))
  if n > 1:
    error = error or checkBytes(uint8(p[1]), uint8(p[0]), 0'u8, 0'u8)
  if n > 2:
    error = error or checkBytes(uint8(p[2]), uint8(p[1]), uint8(p[0]), 0'u8)
  var i = min(n, 3)
  while i + utf8Block <= n:
    if not isAscii(p, i):
      for j in 0 ..< utf8Block:
        error = error or checkUtf8Bytes(p, i + j)
    i += utf8Block
  while i < n:
    error = error or checkUtf8Bytes(p, i)
    inc i
  error = error or isIncomplete(p, n)
  error == 0'u8
when not defined(debug):
  {.pop.}
