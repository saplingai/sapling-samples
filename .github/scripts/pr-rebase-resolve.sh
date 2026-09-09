#!/usr/bin/env bash
# Make the checked-out PR branch rebase-mergeable onto its base branch.
#
# Used by .github/workflows/resolve-pr-conflicts.yml, but standalone and
# testable: it never talks to the GitHub API and never pushes.
#
# Subcommands
#   prepare  Try a plain rebase. If that conflicts (or the branch carries merge
#            commits, which GitHub's rebase-merge cannot replay), start a merge
#            of the base and stop with the conflicts left in the working tree
#            for an agent to resolve.
#   finish   Turn the resolved tree into a linear branch on top of the base and
#            run the safety gates.
#
# Environment
#   BASE_REF                 base branch name, e.g. master            (required)
#   PR_TITLE                 subject line used when commits are squashed
#   RESOLVE_PRESERVE_COMMITS 1 (default) tries to keep per-commit history
#   RESOLVE_STATE_DIR        where prepare/finish exchange state
#
# Outputs are appended to $GITHUB_OUTPUT when set, and echoed either way.

set -euo pipefail

BASE_REF="${BASE_REF:?BASE_REF is required}"
BASE="origin/${BASE_REF}"
STATE_DIR="${RESOLVE_STATE_DIR:-${RUNNER_TEMP:-/tmp}/pr-resolve}"
mkdir -p "$STATE_DIR"

log() { printf '%s\n' "$*" >&2; }

out() {
  # out <key> <value>
  printf '%s=%s\n' "$1" "$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s=%s\n' "$1" "$2" >>"$GITHUB_OUTPUT"
  fi
}

die() {
  log "ERROR: $*"
  printf '%s\n' "$*" >"$STATE_DIR/error.txt"
  exit 1
}

rebase_in_progress() {
  [[ -d "$(git rev-parse --git-path rebase-merge)" || -d "$(git rev-parse --git-path rebase-apply)" ]]
}

merge_in_progress() {
  [[ -f "$(git rev-parse --git-path MERGE_HEAD)" ]]
}

# Conflict markers only: "=======" alone is legitimate in Markdown/RST, so we
# look for the unambiguous start/end markers at line start. Git's default marker
# length is 7, but a .gitattributes conflict-marker-size can make it longer, so
# match seven-or-more marker characters rather than exactly seven.
scan_markers() {
  # scan_markers <file>...
  local found=0 f
  for f in "$@"; do
    [[ -f "$f" ]] || continue
    if grep -qE '^(<{7,}|>{7,})( |$)' -- "$f"; then
      log "conflict markers left in $f"
      found=1
    fi
  done
  return $found
}

# Text conflicts announce themselves with markers scan_markers can verify. A
# binary (or otherwise non-text) conflict carries no markers: git just leaves
# one side's blob in the working tree, so a later `git add -A` would silently
# adopt whichever side that was. We cannot confirm such a pick was deliberate -
# even the agent doing nothing looks identical to "keep ours" - so refuse it.
#
# Inspect the unmerged index stages (1=base, 2=ours, 3=theirs) rather than the
# working-tree file: the tree only holds one side, and if that side is empty (a
# PR that replaced a binary with a zero-byte file, say) a worktree-only check
# would wave it through. If any stage's blob is non-empty and binary, we cannot
# verify a resolution, so refuse. Empty blobs are text; a fully deleted side has
# no stage at all, so delete/modify resolved by removal stays allowed. Symlink
# and submodule conflicts carry no markers and store only a short ASCII
# target/hash per stage, so we reject them by their mode rather than by content.
refuse_binary_conflicts() {
  local path stage blob tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/resolve-blob.XXXXXX")"
  # -z gives NUL-terminated raw pathnames, so a name containing a tab, newline or
  # non-ASCII byte reaches git rev-parse verbatim. Reading the quoted form would
  # make every stage lookup miss and let the conflict slip through unverified.
  while IFS= read -r -d '' path; do
    [[ -n "$path" ]] || continue
    # A path whose merge attribute is unset (the `binary` macro, or an explicit
    # `-merge` in .gitattributes) gets no textual three-way merge: git keeps one
    # side's blob in the working tree and emits no conflict markers, so
    # scan_markers has nothing to verify. This holds even when both sides are
    # pure ASCII, so the blob-byte check below cannot catch it. We cannot confirm
    # such a path was actually reconciled, so refuse it outright.
    if [[ "$(git check-attr merge -- "$path" 2>/dev/null | sed 's/.*: merge: //')" == "unset" ]]; then
      rm -f "$tmp"
      die "conflict at '$path' has merge=unset (binary/-merge attribute) and carries no markers to verify; resolve it by hand"
    fi
    # A non-regular unmerged mode - a symlink (120000) or a submodule/gitlink
    # (160000) - never gets a textual three-way merge either: git leaves one
    # side in the working tree without markers, and each index stage is only a
    # short ASCII target/hash so the blob-byte check below classifies it as text
    # and waves it through. Refuse any such mode outright.
    while IFS=' ' read -r mode _; do
      case "$mode" in
        120000 | 160000)
          rm -f "$tmp"
          die "non-regular ($mode) conflict at '$path' carries no markers to verify; resolve it by hand"
          ;;
      esac
    done < <(git ls-files -u -- "$path")
    for stage in 1 2 3; do
      blob="$(git rev-parse -q --verify ":${stage}:${path}" 2>/dev/null)" || continue
      git cat-file -p "$blob" >"$tmp"
      if [[ -s "$tmp" ]] && ! grep -Iq . -- "$tmp"; then
        rm -f "$tmp"
        die "binary/non-text conflict at '$path' cannot be verified automatically; resolve it by hand"
      fi
    done
  done < <(git diff --name-only -z --diff-filter=U)
  rm -f "$tmp"
}

save_state() {
  printf '%s\n' "$1" >"$STATE_DIR/$2"
}

read_state() {
  cat "$STATE_DIR/$1" 2>/dev/null || true
}

ensure_identity() {
  git config user.name >/dev/null 2>&1 || git config user.name "github-actions[bot]"
  git config user.email >/dev/null 2>&1 ||
    git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  # Emit raw pathnames in every `git diff --name-only` below (the marker scan and
  # conflicted-file bookkeeping read them line-by-line); quoted non-ASCII names
  # would otherwise miss the file they name.
  git config core.quotePath false
}

cmd_prepare() {
  ensure_identity
  # actions/checkout defaults to a shallow clone (fetch-depth: 1); the rebase and
  # merge-base lookups below need real history. Unshallow first when we're shallow
  # (the guard makes it a no-op on a complete clone, where --unshallow errors).
  if [[ -f "$(git rev-parse --git-path shallow)" ]]; then
    log "repository is shallow; fetching full history so merge-base can be found"
    git fetch --unshallow --no-tags --quiet origin || true
  fi
  git fetch --no-tags --quiet origin "+refs/heads/${BASE_REF}:refs/remotes/origin/${BASE_REF}"

  rebase_in_progress && die "a rebase is already in progress in this checkout"
  merge_in_progress && die "a merge is already in progress in this checkout"
  # -uno: untracked files (CI caches, build artifacts) don't block a rebase; only
  # dirty tracked changes mean a genuinely unclean starting state.
  [[ -z "$(git status --porcelain -uno)" ]] || die "working tree is dirty before we started"

  local old_head merges commits_before
  old_head="$(git rev-parse HEAD)"
  merges="$(git rev-list --min-parents=2 "${BASE}..HEAD")"
  commits_before="$(git rev-list --count "${BASE}..HEAD")"

  save_state "$old_head" old_head
  save_state "$BASE_REF" base_ref
  save_state "$commits_before" commits_before
  : >"$STATE_DIR/conflicted_files.txt"

  # Surface the base tip we are resolving against so the pushing step can detect
  # the base moving under a long resolution and refuse to push a stale rebase.
  out base_sha "$(git rev-parse "$BASE")"

  if [[ -z "$merges" ]] && git merge-base --is-ancestor "$BASE" HEAD; then
    save_state 0 had_merges
    save_state up-to-date status
    out status up-to-date
    out tier 0
    out old_head "$old_head"
    log "branch is already linear and contains ${BASE}; nothing to do"
    return 0
  fi

  if [[ -n "$merges" ]]; then
    save_state 1 had_merges
    log "branch carries $(wc -l <<<"$merges") merge commit(s); rebase-merge cannot replay those, going straight to merge+flatten"
  else
    save_state 0 had_merges
    log "attempting a plain rebase onto ${BASE}"
    if git rebase "$BASE" >"$STATE_DIR/rebase.log" 2>&1; then
      save_state clean status
      save_state 1 tier
      out status clean
      out tier 1
      out old_head "$old_head"
      log "clean rebase; per-commit history preserved"
      return 0
    fi
    log "rebase conflicted, falling back to a single merge resolution"
    git rebase --abort || true
    git reset --hard "$old_head" --quiet
  fi

  # Record resolutions so the same fix can be replayed commit-by-commit later.
  git config rerere.enabled true
  git config rerere.autoupdate true

  if git merge --no-ff -m "merge ${BASE_REF} (conflict resolution scratch commit)" "$BASE" \
    >"$STATE_DIR/merge.log" 2>&1; then
    save_state merged-clean status
    out status merged-clean
    out tier ""
    out old_head "$old_head"
    log "merge applied without conflicts; no agent needed"
    return 0
  fi

  merge_in_progress || {
    cat "$STATE_DIR/merge.log" >&2
    die "merge failed without leaving conflicts to resolve"
  }

  git diff --name-only --diff-filter=U >"$STATE_DIR/conflicted_files.txt"
  [[ -s "$STATE_DIR/conflicted_files.txt" ]] || die "merge stopped but reported no conflicted files"

  save_state conflict status
  out status conflict
  out old_head "$old_head"
  out conflicted_count "$(wc -l <"$STATE_DIR/conflicted_files.txt" | tr -d ' ')"
  log "conflicted files:"
  cat "$STATE_DIR/conflicted_files.txt" >&2
  return 0
}

# Replay the branch commit-by-commit, letting git rerere apply the resolution we
# just recorded. Returns non-zero (with the rebase aborted) if anything stops it.
replay_with_rerere() {
  local rc=0 guard=0
  GIT_EDITOR=true git -c rerere.enabled=true rebase "$BASE" >"$STATE_DIR/replay.log" 2>&1 || rc=$?
  while [[ $rc -ne 0 ]] && rebase_in_progress; do
    guard=$((guard + 1))
    if [[ $guard -gt 100 ]]; then
      log "replay exceeded 100 stops; giving up"
      git rebase --abort || true
      return 1
    fi
    if [[ -n "$(git ls-files -u)" ]]; then
      log "rerere could not resolve every hunk at stop #$guard"
      git rebase --abort || true
      return 1
    fi
    local changed_files
    mapfile -t changed_files < <(git diff --name-only HEAD 2>/dev/null)
    if ! scan_markers "${changed_files[@]}"; then
      log "conflict markers survived rerere at stop #$guard"
      git rebase --abort || true
      return 1
    fi
    # -u only: stage the tracked files rerere just resolved, never untracked
    # artifacts CI or the agent may have left in the tree.
    git add -u
    rc=0
    if git diff --cached --quiet; then
      GIT_EDITOR=true git rebase --skip >>"$STATE_DIR/replay.log" 2>&1 || rc=$?
    else
      GIT_EDITOR=true git rebase --continue >>"$STATE_DIR/replay.log" 2>&1 || rc=$?
    fi
  done
  if [[ $rc -ne 0 ]]; then
    rebase_in_progress && git rebase --abort || true
    return 1
  fi
  return 0
}

flatten_onto_base() {
  # flatten_onto_base <resolved-merge-sha>
  local ref="$1" subject body
  subject="${PR_TITLE:-}"
  [[ -n "$subject" ]] || subject="$(git log -1 --format=%s "$ref^1" 2>/dev/null || echo "changes")"
  git reset --hard "$ref" --quiet
  git reset --soft "$BASE" --quiet
  body="Squashed and rebased onto ${BASE_REF} to make this branch rebase-mergeable.

Previous head: $(read_state old_head)"
  git commit --quiet -m "$subject" -m "$body"
}

run_gates() {
  local old_head new_head merge_base_before
  old_head="$(read_state old_head)"
  new_head="$(git rev-parse HEAD)"

  rebase_in_progress && die "gate: a rebase is still in progress"
  merge_in_progress && die "gate: a merge is still in progress"
  [[ -z "$(git status --porcelain -uno)" ]] || die "gate: working tree is not clean"
  git merge-base --is-ancestor "$BASE" HEAD || die "gate: HEAD does not contain ${BASE}"
  [[ -z "$(git rev-list --min-parents=2 "${BASE}..HEAD")" ]] ||
    die "gate: branch still contains a merge commit, GitHub cannot rebase-merge it"
  [[ "$(git rev-list --count "${BASE}..HEAD")" -gt 0 ]] || die "gate: branch has no commits over ${BASE}"
  git diff --quiet "${BASE}...HEAD" && die "gate: branch no longer changes anything versus ${BASE}"

  # Materialize the diff before scanning: `git diff | grep -q` lets grep exit on
  # the first marker, and the resulting SIGPIPE turns the git side non-zero under
  # `pipefail`, which would flip this test to the no-marker branch and wave a
  # conflicted tree through.
  git diff "${BASE}...HEAD" >"$STATE_DIR/base_diff.txt"
  if grep -qE '^\+(<{7,}|>{7,})( |$)' "$STATE_DIR/base_diff.txt"; then
    die "gate: conflict markers present in the diff against ${BASE}"
  fi

  # Files the PR used to touch that it no longer touches. Legitimate when the
  # base already absorbed the change, suspicious otherwise - reported, not fatal.
  merge_base_before="$(git merge-base "$BASE" "$old_head")"
  comm -23 \
    <(git diff --name-only "$merge_base_before" "$old_head" | sort) \
    <(git diff --name-only "${BASE}...HEAD" | sort) \
    >"$STATE_DIR/dropped_files.txt" || true

  # The hook runs with the push credential, so it must come from a trusted
  # revision, never the PR's own tree. The workflow sets RESOLVE_VERIFY_HOOK to
  # a copy taken from the default branch (empty when none is trusted). Only the
  # standalone/test path, which leaves the variable unset, falls back to the
  # in-tree hook.
  local verify_hook="${RESOLVE_VERIFY_HOOK-.github/resolve-verify.sh}"
  if [[ -n "$verify_hook" && -x "$verify_hook" ]]; then
    log "running repository verification hook $verify_hook"
    "$verify_hook" >"$STATE_DIR/verify.log" 2>&1 ||
      die "gate: $verify_hook failed$(printf '\n')$(tail -40 "$STATE_DIR/verify.log")"
  fi

  out old_head "$old_head"
  out new_head "$new_head"
  out commits_before "$(read_state commits_before)"
  out commits_after "$(git rev-list --count "${BASE}..HEAD")"
  out changed_files "$(git diff --name-only "${BASE}...HEAD" | wc -l | tr -d ' ')"
  out dropped_count "$(grep -c . <"$STATE_DIR/dropped_files.txt" || true)"
  if [[ -s "$STATE_DIR/dropped_files.txt" ]]; then
    log "files no longer touched by this PR: $(tr '\n' ' ' <"$STATE_DIR/dropped_files.txt")"
  fi
}

cmd_finish() {
  ensure_identity
  local status had_merges old_head ref tier commits_before
  status="$(read_state status)"
  had_merges="$(read_state had_merges)"
  old_head="$(read_state old_head)"
  commits_before="$(read_state commits_before)"
  [[ -n "$old_head" ]] || die "no saved state from prepare"

  case "$status" in
    up-to-date)
      out status up-to-date
      out tier 0
      return 0
      ;;
    clean)
      tier=1
      ;;
    conflict)
      merge_in_progress || die "expected a merge in progress to finish"
      mapfile -t conflicted <"$STATE_DIR/conflicted_files.txt"
      scan_markers "${conflicted[@]}" || die "conflict markers are still present in the resolved files"
      [[ -z "$(git diff --name-only --diff-filter=U 2>/dev/null | grep -v -F -x -f "$STATE_DIR/conflicted_files.txt" || true)" ]] ||
        die "new unmerged paths appeared during resolution"
      refuse_binary_conflicts
      # -u only: stage the agent's resolution of tracked files (incl. any clean
      # tracked edits it needed), never stray untracked artifacts from CI/tooling.
      git add -u
      [[ -z "$(git ls-files -u)" ]] || die "unmerged paths remain after staging the resolution"
      git commit --quiet --no-edit
      tier=""
      ;;
    merged-clean)
      tier=""
      ;;
    *)
      die "unknown prepare status '$status'"
      ;;
  esac

  if [[ "$tier" != "1" ]]; then
    ref="$(git rev-parse HEAD)" # resolved merge commit: the content we must preserve
    if [[ "$had_merges" == "0" && "${commits_before:-1}" -gt 1 && "${RESOLVE_PRESERVE_COMMITS:-1}" == "1" ]]; then
      log "trying to replay ${commits_before} commits onto ${BASE} with the recorded resolution"
      git reset --hard "$old_head" --quiet
      if replay_with_rerere && git diff --quiet "$ref" HEAD; then
        tier=2
      else
        log "commit-by-commit replay did not reproduce the resolved tree; squashing instead"
        tier=""
      fi
    fi
    if [[ -z "$tier" ]]; then
      flatten_onto_base "$ref"
      git diff --quiet "$ref" HEAD ||
        die "gate: squashed branch does not match the resolved merge tree"
      tier=3
    fi
  fi

  run_gates
  out status resolved
  out tier "$tier"
}

case "${1:-}" in
  prepare) cmd_prepare ;;
  finish) cmd_finish ;;
  *)
    echo "usage: $0 {prepare|finish}" >&2
    exit 64
    ;;
esac
