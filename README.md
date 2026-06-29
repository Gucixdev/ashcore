# ash

Mojo libraries — fast, low-level, zero-dependency.

## Libraries

| Library | Description |
|---------|-------------|
| [ashcore](ashcore/) | Arena allocator, thread pool, DAG job system, sync primitives |
| [ashparser](ashparser/) | Parser combinator library with stateful parsing support |

## Requirements

- [Mojo / MAX](https://docs.modular.com/mojo/) via [pixi](https://prefix.dev/)

Each library has its own `pixi.toml` and is self-contained.

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
├── README.md          ← this file
├── LICENSE
├── .gitignore
├── .gitattributes
├── ashcore/           ← arena, threadpool, DAG, sync
│   ├── README.md
│   ├── pixi.toml
│   ├── src/ashcore/
│   ├── benchmarks/
│   ├── tests/
│   ├── example/
│   ├── bench          ← ./bench [arena|pool|sync|reduce|sweep]
│   ├── compare        ← ./compare (Mojo vs C vs Python)
│   ├── stresstest     ← ./stresstest
│   └── test           ← ./test (all phases)
└── ashparser/         ← parser combinators
    ├── README.md
    ├── pixi.toml
    ├── src/ashparser/
    ├── benchmarks/
    ├── tests/
    ├── example/
    ├── bench          ← ./bench
    ├── compare        ← ./compare [csv|json|int]
    ├── stresstest     ← ./stresstest
    └── test           ← ./test
```
