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
# look for the unambiguous 7-char start/end markers at line start.
scan_markers() {
  # scan_markers <file>...
  local found=0 f
  for f in "$@"; do
    [[ -f "$f" ]] || continue
    if grep -qE '^(<{7}|>{7})( |$)' -- "$f"; then
      log "conflict markers left in $f"
      found=1
    fi
  done
  return $found
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
}

cmd_prepare() {
  ensure_identity
  git fetch --no-tags --quiet origin "+refs/heads/${BASE_REF}:refs/remotes/origin/${BASE_REF}"

  rebase_in_progress && die "a rebase is already in progress in this checkout"
  merge_in_progress && die "a merge is already in progress in this checkout"
  [[ -z "$(git status --porcelain)" ]] || die "working tree is dirty before we started"

  local old_head merges commits_before
  old_head="$(git rev-parse HEAD)"
  merges="$(git rev-list --min-parents=2 "${BASE}..HEAD")"
  commits_before="$(git rev-list --count "${BASE}..HEAD")"

  save_state "$old_head" old_head
  save_state "$BASE_REF" base_ref
  save_state "$commits_before" commits_before
  : >"$STATE_DIR/conflicted_files.txt"

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
    # shellcheck disable=SC2046
    if ! scan_markers $(git diff --name-only HEAD 2>/dev/null); then
      log "conflict markers survived rerere at stop #$guard"
      git rebase --abort || true
      return 1
    fi
    git add -A
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
  local old_head new_head merge_base_before before after dropped
  old_head="$(read_state old_head)"
  new_head="$(git rev-parse HEAD)"

  rebase_in_progress && die "gate: a rebase is still in progress"
  merge_in_progress && die "gate: a merge is still in progress"
  [[ -z "$(git status --porcelain)" ]] || die "gate: working tree is not clean"
  git merge-base --is-ancestor "$BASE" HEAD || die "gate: HEAD does not contain ${BASE}"
  [[ -z "$(git rev-list --min-parents=2 "${BASE}..HEAD")" ]] ||
    die "gate: branch still contains a merge commit, GitHub cannot rebase-merge it"
  [[ "$(git rev-list --count "${BASE}..HEAD")" -gt 0 ]] || die "gate: branch has no commits over ${BASE}"
  git diff --quiet "${BASE}...HEAD" && die "gate: branch no longer changes anything versus ${BASE}"

  if git diff "${BASE}...HEAD" | grep -qE '^\+(<{7}|>{7})( |$)'; then
    die "gate: conflict markers present in the diff against ${BASE}"
  fi

  # Files the PR used to touch that it no longer touches. Legitimate when the
  # base already absorbed the change, suspicious otherwise - reported, not fatal.
  merge_base_before="$(git merge-base "$BASE" "$old_head")"
  before="$(git diff --name-only "$merge_base_before" "$old_head" | sort)"
  after="$(git diff --name-only "${BASE}...HEAD" | sort)"
  comm -23 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | grep -v '^$' \
    >"$STATE_DIR/dropped_files.txt" || true

  if [[ -x .github/resolve-verify.sh ]]; then
    log "running repository verification hook .github/resolve-verify.sh"
    .github/resolve-verify.sh >"$STATE_DIR/verify.log" 2>&1 ||
      die "gate: .github/resolve-verify.sh failed$(printf '\n')$(tail -40 "$STATE_DIR/verify.log")"
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
      git add -A
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
