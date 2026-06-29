"""
Guard-fire test: calls dbg_assert(False, ...) intentionally.
Expected outcome: process aborts (SIGABRT / exit != 0) when DEBUG=True.
Run by stresstest debug-guards — never in release mode.
"""
from ashcore.debug import dbg_assert

def main() raises:
    dbg_assert(False, "intentional guard-fire test — this abort is expected")
    print("FAIL: process should have aborted before reaching this line")
