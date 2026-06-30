# Layer 1 — Tools
# Re-exports all tools from sys/, code/, web/ subpackages.
# Import as: from tools import shell_run, search_symbol, fetch_url ...

from tools.sys import (
    ShellResult, shell_run, shell_ok,
    file_exists, read_text, write_text, list_dir,
    show_tree, file_info, system_info, scan_log,
    git_branch_current, git_status, git_diff_staged, git_log, git_is_clean,
)
from tools.code import (
    search_symbol, search_pattern, search_files, codemap,
    diff_staged, diff_unstaged, diff_files, diff_branch, diff_stat,
)
from tools.web import (
    FetchResult, fetch_url, fetch_json,
)
