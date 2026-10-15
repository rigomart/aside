#!/bin/bash
# Claude Code Stop hook: an agent can't finish its turn with a broken build or failing tests.
# Runs `make check` only when source files changed since the last passing check.
set -u
input=$(cat)
# Already continuing because of this hook: let the agent stop rather than loop.
[ "$(jq -r '.stop_hook_active // false' <<<"$input")" = "true" ] && exit 0
cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}" || exit 0

paths=(App/Sources Packages project.yml Makefile)
fingerprint=$({
    git rev-parse HEAD 2>/dev/null
    git diff HEAD -- "${paths[@]}" 2>/dev/null
    git ls-files -o --exclude-standard -z -- "${paths[@]}" | xargs -0 cat 2>/dev/null
} | shasum | cut -d' ' -f1)
stamp=build/.last-check
[ -f "$stamp" ] && [ "$(cat "$stamp")" = "$fingerprint" ] && exit 0

if output=$(make check 2>&1); then
    mkdir -p build && echo "$fingerprint" >"$stamp"
    exit 0
fi
echo "make check failed. Fix it before finishing:" >&2
tail -n 60 <<<"$output" >&2
exit 2
