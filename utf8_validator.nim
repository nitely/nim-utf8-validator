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

template checkBounded(p: openArray[char], n, i: int): uint8 =
  var window: array[4, char]
  for k in 0 .. 3:
    template idx: untyped = i - k
    if idx >= 0 and idx < n:
      window[3 - k] = p[idx]
  checkUtf8Bytes(window, 3)

template isIncomplete(p: openArray[char], n: int): uint8 =
  checkBounded(p, n, n)

template isAscii(p: openArray[char], i: int): bool =
  var res = 0'u8
  for j in 0 ..< utf8Block + 3:
    res = res or uint8(p[i - 3 + j])
  res <= 0x7F'u8

{.push checks: off.}
func validateUtf8*(p: openArray[char]): bool =
  var error = 0'u8
  let n = p.len
  let prefix = min(n, 3)
  for i in 0 ..< prefix:
    error = error or checkBounded(p, n, i)
  var i = prefix
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
{.pop.}
