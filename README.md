# UTF8-validator

A very fast UTF-8 validator in pure Nim.

## Bench

Run:

```
cd bench
nim c -r -d:danger --passC:"-march=native" bench.nim
```

Results on my machine:

```text
data/ascii.txt  --  0.57 MiB, 0.00% non-ascii
  validator      verdict   best GB/s   median   best ms
  -----------------------------------------------------
  nitely           valid       82.91    81.09     0.007
  branchy          valid        2.04     1.94     0.294
  dfa              valid        0.57     0.57     1.049

data/jp_random.txt  --  0.02 MiB, 98.36% non-ascii
  validator      verdict   best GB/s   median   best ms
  -----------------------------------------------------
  nitely           valid        9.85     9.71     0.003
  branchy          valid        1.97     1.94     0.013
  dfa              valid        0.55     0.54     0.048

data/hongkong.html  --  1.72 MiB, 8.37% non-ascii
  validator      verdict   best GB/s   median   best ms
  -----------------------------------------------------
  nitely           valid       17.35    17.08     0.104
  branchy          valid        1.88     1.79     0.962
  dfa              valid        0.57     0.54     3.171

data/twitter.json  --  0.60 MiB, 15.11% non-ascii
  validator      verdict   best GB/s   median   best ms
  -----------------------------------------------------
  nitely           valid       21.12    20.11     0.030
  branchy          valid        1.89     1.87     0.335
  dfa              valid        0.57     0.57     1.107
```

## License

MIT
