proc validateUtf8*(p: openArray[char]): bool =
  let n = p.len
  var i = 0
  template rng(x: uint8, lo, hi: uint8): bool = x >= lo and x <= hi
  while i < n:
    let b = uint8(p[i])
    if b <= 0x7F'u8: i += 1
    elif rng(b, 0xC2, 0xDF):
      if i+1 >= n or not rng(uint8(p[i+1]), 0x80, 0xBF): return false
      i += 2
    elif b == 0xE0'u8:
      if i+2 >= n or not rng(uint8(p[i+1]), 0xA0, 0xBF) or
                     not rng(uint8(p[i+2]), 0x80, 0xBF): return false
      i += 3
    elif rng(b, 0xE1, 0xEC) or b == 0xEE'u8 or b == 0xEF'u8:
      if i+2 >= n or not rng(uint8(p[i+1]), 0x80, 0xBF) or
                     not rng(uint8(p[i+2]), 0x80, 0xBF): return false
      i += 3
    elif b == 0xED'u8:
      if i+2 >= n or not rng(uint8(p[i+1]), 0x80, 0x9F) or
                     not rng(uint8(p[i+2]), 0x80, 0xBF): return false
      i += 3
    elif b == 0xF0'u8:
      if i+3 >= n or not rng(uint8(p[i+1]), 0x90, 0xBF) or
                     not rng(uint8(p[i+2]), 0x80, 0xBF) or
                     not rng(uint8(p[i+3]), 0x80, 0xBF): return false
      i += 4
    elif rng(b, 0xF1, 0xF3):
      if i+3 >= n or not rng(uint8(p[i+1]), 0x80, 0xBF) or
                     not rng(uint8(p[i+2]), 0x80, 0xBF) or
                     not rng(uint8(p[i+3]), 0x80, 0xBF): return false
      i += 4
    elif b == 0xF4'u8:
      if i+3 >= n or not rng(uint8(p[i+1]), 0x80, 0x8F) or
                     not rng(uint8(p[i+2]), 0x80, 0xBF) or
                     not rng(uint8(p[i+3]), 0x80, 0xBF): return false
      i += 4
    else: return false
  true
