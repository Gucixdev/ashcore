# ashparser

Zero-dependency parser combinator library for Mojo.  
Parsers compose at compile time via `@parameter def`.

## Quick start

```bash
magic run mojo run -I src example/csv.mojo
magic run mojo run -I src example/json.mojo
./test
```

## What's inside

```
src/ashparser/
  input.mojo      — zero-copy Input (address + pos, no allocation)
  result.mojo     — ParseResult[T]
  prim.mojo       — primitives: satisfy, byte, tag, take_while, digits, ident,
                    one_of, none_of, line_ending, rest_of_line,
                    hex_digit/hex_digits, parse_uint, parse_int, quoted_string
  comb.mojo       — combinators: opt, many, many1, map, choice, seq,
                    skip_left, skip_right, between, sep_by, sep_by1,
                    peek, not_followed_by, verify, skip_many, skip_many1,
                    count, recognize
  state.mojo      — Ctx[S] + CtxResult[T,S] for stateful parsing
  statecomb.mojo  — stateful combinators: slift, sget, smodify, smap,
                    schoice, smany, smany1, sskip_left, sskip_right,
                    ssep_by, ssep_by1
```

## Examples

`example/` shows each feature in ~50–80 lines:

| File | Demonstrates |
|------|--------------|
| `csv.mojo` | `sep_by`, `take_while` |
| `calc.mojo` | `parse_uint`, operator folding |
| `json.mojo` | `choice`, `quoted_string`, `sep_by` |
| `toml.mojo` | `rest_of_line`, `parse_int`, `quoted_string` |
| `xml.mojo` | `between`, `none_of`, attributes |
| `yaml.mojo` | `rest_of_line`, `one_of` |

## Performance vs Python

| Task | Mojo | Python | Ratio |
|------|------|--------|-------|
| CSV 200k rows (sep_by) | ~74 ms | ~56 ms (str.split) | 0.7× |
| JSON 50k arrays | ~52 ms | ~53 ms (json.loads) | **1.0×** |
| parse_int 1M calls | 48 ns/call | 114 ns/call | **2.3×** |
| hex_digits 1M calls | 39 ns/call | 118 ns/call | **3.0×** |

## Stateful parsing

When parsing needs to thread context (indent level, nesting depth, counters):

```mojo
from ashparser.state     import Ctx, CtxResult
from ashparser.statecomb import slift, sget, smodify, smany

@parameter
def inc(n: Int) -> Int: return n + 1

@parameter
def digit_and_count(ctx: Ctx[Int]) -> CtxResult[UInt8, Int]:
    var r = digit(ctx.input)
    if not r.ok:
        return CtxResult[UInt8, Int].failure(ctx, r.msg)^
    return CtxResult[UInt8, Int].success(r.get(), Ctx[Int](r.rest, ctx.state + 1))^

var ctx = Ctx[Int](Input.from_string(String("123abc")), 0)
var r = smany[UInt8, Int, digit_and_count](ctx)
# r.rest.state == 3  (counted 3 digits)
```

## Scripts

```bash
./run          # unit tests (73+ test cases)
./bench        # best-of-3 benchmarks (csv, json, prim)
./compare      # Mojo vs Python (csv, json, int/hex)
./stresstest   # 3 extreme scenarios
./test         # all of the above
```

## Mojo 1.0.0b2 constraints

- All parsers passed as combinator arguments must be `@parameter def`
- No tuple return types → use `Pair[A,B]` or `ParseResult[Pair[A,B]]`
- No `s[0:n]` string slicing → use `inp.slice_str(start, end)`
- No lambda → write named `@parameter def`
