## Benchmarks
##
## Build:
##   nim c -d:danger --passC:"-march=native" bench.nim
## Run:
##   ./bench [input-file ...]      # default: everything in ./data

import std/[monotimes, times, os, strformat, strutils, algorithm]
import ../utf8_validator
import ./utf8_branchy
import ./utf8_dfa
import ./utf8_proof
import ./utf8_stream

var sink {.volatile.} = 0'u64

type Validator = proc (data: string): bool {.nimcall.}

const validators: seq[(string, Validator)] = @[
  ("nitely", Validator(proc (data: string): bool = utf8_validator.validateUtf8(data))),
  ("branchy", Validator(proc (data: string): bool = utf8_branchy.validateUtf8(data))),
  ("dfa",     Validator(proc (data: string): bool = utf8_dfa.validateUtf8(data))),
  ("proof",     Validator(proc (data: string): bool = utf8_proof.validateUtf8(data))),
  ("stream",    Validator(proc (data: string): bool = utf8_stream.validateUtf8(data))),
]

proc measure(validator: Validator, data: string): (float, float) =
  ## Nanoseconds per pass over `data`: best and median of 15 rounds, with the
  ## pass count calibrated so a round takes about 50ms.
  const targetRound = 0.05
  var iters = 1

  while true:
    let t0 = getMonoTime()
    for _ in 0 ..< iters:
      sink += uint64(ord(validator(data)))
    let elapsed = (getMonoTime() - t0).inNanoseconds.float / 1e9
    if elapsed >= targetRound or iters >= 1 shl 20:
      break
    let growth = if elapsed > 0: targetRound / elapsed else: 8.0
    iters = max(iters + 1, int(iters.float * min(growth * 1.2, 8.0)))

  var perPass: seq[float] = @[]
  for _ in 0 ..< 15:
    let t0 = getMonoTime()
    for _ in 0 ..< iters:
      sink += uint64(ord(validator(data)))
    perPass.add((getMonoTime() - t0).inNanoseconds.float / iters.float)

  perPass.sort()
  (perPass[0], perPass[perPass.len div 2])

proc gbps(nsPerPass: float, n: int): float = n.float / nsPerPass

proc dataFiles(): seq[string] =
  for path in walkFiles("data" / "*"):
    if path.splitFile().ext != ".md":
      result.add path
  result.sort()

when isMainModule:
  var paths = commandLineParams()
  if paths.len == 0:
    paths = dataFiles()
  if paths.len == 0:
    quit("no input files: pass paths explicitly, or put a corpus in ./data")

  when defined(danger):
    echo "build : -d:danger (bounds checks off)"
  else:
    echo "build : checked -- expect this to be several times slower"

  for path in paths:
    let data = readFile(path)
    echo ""
    if data.len == 0:
      echo path & "  (empty, skipped)"
      continue

    var nonAscii = 0
    for c in data:
      if uint8(c) >= 0x80'u8: inc nonAscii

    var verdicts: seq[bool] = @[]
    for (_, validator) in validators:
      verdicts.add validator(data)

    echo &"{path}  --  {data.len.float / 1048576.0:.2f} MiB, " &
         &"{100.0 * nonAscii.float / data.len.float:.2f}% non-ascii"
    if false in verdicts:
      echo "  rejected input: GB/s is nominal where a validator exits early, " &
           "compare \"best ms\""
    echo &"""  {"validator":<12}{"verdict":>10}{"best GB/s":>12}{"median":>9}{"best ms":>10}"""
    echo "  " & repeat('-', 53)

    for i, (name, validator) in validators:
      let verdict = if verdicts[i]: "valid" else: "INVALID"
      let (best, median) = measure(validator, data)
      echo &"  {name:<12}{verdict:>10}{gbps(best, data.len):>12.2f}" &
           &"{gbps(median, data.len):>9.2f}{best / 1e6:>10.3f}"
