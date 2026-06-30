# caveman

Minimalist debugging: add print statements to trace execution, then remove them.

## When to use

- Complex state bugs where the control flow is unclear
- Performance profiling without a profiler available
- Verifying assumptions about what code path actually runs

## Pattern

```python
# before function that might fail
print("[caveman] entering fn, x=" + str(x))

# at the point of suspicion
print("[caveman] val=" + str(val) + " cond=" + str(cond))

# after resolution: remove all [caveman] prints
```

## In Mojo

```mojo
print("[caveman] pos=" + String(inp.pos) + " peek=" + String(inp.peek()))
```

## Cleanup

Search `[caveman]` and remove before commit. Never leave debug prints in committed code.
