# ash

Mojo libraries — fast, low-level, zero-dependency.

## Libraries

| Library | Description |
|---------|-------------|
| [ashcore](ashcore/) | Arena allocator, thread pool, DAG schedulers, sync primitives, lock-free queues |
| [ashparser](ashparser/) | Parser combinator library with stateful parsing and source-map error reporting |

## Requirements

- [Mojo / MAX](https://docs.modular.com/mojo/) ≥ 26.4 via [Magic](https://docs.modular.com/magic/)
- linux-64

## Install

```bash
git clone https://github.com/Gucixdev/ash.git
cd ash/ashcore && magic install   # or cd ash/ashparser
```

## Getting started

```bash
# ashcore
cd ashcore && ./test

# ashparser
cd ashparser && ./test
```

## Structure

```
ash/
├── README.md
├── CHANGELOG.md
├── LICENSE
├── ashcore/
│   ├── README.md
│   ├── pixi.toml
│   ├── conda.recipe/
│   ├── ashcore/          ← source package
│   │   ├── arena.mojo
│   │   ├── shared_arena.mojo
│   │   ├── sync.mojo
│   │   ├── threadpool.mojo
│   │   ├── taskgraph.mojo
│   │   ├── reactivegraph.mojo
│   │   ├── parallel.mojo
│   │   ├── queue.mojo
│   │   ├── debug.mojo
│   │   └── gpu.mojo
│   ├── benchmarks/
│   ├── tests/
│   ├── example/
│   ├── bench
│   ├── compare
│   ├── stresstest
│   └── test
└── ashparser/
    ├── README.md
    ├── pixi.toml
    ├── conda.recipe/
    ├── ashparser/        ← source package
    │   ├── input.mojo
    │   ├── result.mojo
    │   ├── sourcemap.mojo
    │   ├── prim.mojo
    │   ├── comb.mojo
    │   ├── state.mojo
    │   └── statecomb.mojo
    ├── benchmarks/
    ├── tests/
    ├── example/
    ├── bench
    ├── compare
    ├── stresstest
    └── test
```

## License

[MIT](LICENSE)
