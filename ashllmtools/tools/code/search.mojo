"""tools.code.search — code search: symbol lookup, pattern grep, file listing."""

from tools.sys.shell import shell_run


def search_symbol(symbol: String, root: String = ".") -> String:
    """Grep for a symbol (whole-word) across .mojo files.
    Returns file:line matches or empty string."""
    var r = shell_run(
        "grep -rn --include='*.mojo' '\\b" + symbol + "\\b' " + root + " 2>/dev/null"
    )
    return r.stdout if r.ok else String("")


def search_pattern(pattern: String, glob: String = "*.mojo", root: String = ".") -> String:
    """Grep for a regex pattern across files matching glob."""
    var r = shell_run(
        "grep -rn --include='" + glob + "' -E '"
        + pattern + "' " + root + " 2>/dev/null"
    )
    return r.stdout if r.ok else String("")


def search_files(name_pattern: String, root: String = ".") -> String:
    """Find files by name pattern. Returns newline-separated paths."""
    var r = shell_run(
        "find " + root + " -name '" + name_pattern + "' 2>/dev/null | sort"
    )
    return r.stdout if r.ok else String("")


def codemap(root: String = ".", max_depth: Int = 3) -> String:
    """Return directory tree + top-level symbol listing for .mojo files.
    Gives the LLM a structural overview of the codebase."""
    var tree_r = shell_run(
        "find " + root + " -maxdepth " + String(max_depth)
        + " -name '*.mojo' 2>/dev/null | sort"
    )
    var tree = tree_r.stdout if tree_r.ok else String("")

    var sym_r = shell_run(
        "grep -rn --include='*.mojo' -E '^(def |struct |alias |comptime )' "
        + root + " 2>/dev/null"
    )
    var syms = sym_r.stdout if sym_r.ok else String("")

    if tree == "" and syms == "":
        return "codemap: nothing found under " + root
    return "=== files ===\n" + tree + "\n=== symbols ===\n" + syms
