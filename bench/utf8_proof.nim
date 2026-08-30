{.push checks: off.}
func validateUtf8*(p: openArray[char]): bool =
  const utf8Block = 256

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
