#!/usr/bin/env bash
# Exercise pr-rebase-resolve.sh against synthetic repos.
#
#   .github/scripts/test-pr-rebase-resolve.sh .github/scripts/pr-rebase-resolve.sh
#
# Every case builds a throwaway bare origin plus a clone under a mktemp root and
# asserts it never leaves that tree; nothing here touches a real repository.
set -euo pipefail

SCRIPT="$(readlink -f "$1")"
ROOT="$(mktemp -d)"
trap 'cd / && rm -rf "$ROOT"' EXIT
cd "$ROOT" || exit 1
PASS=0
FAIL=0

say() { printf '\n=== %s ===\n' "$*"; }
ok() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$*"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

guard_cwd() {
  # every case re-asserts it is inside the scratch tree
  [[ "$(git rev-parse --show-toplevel 2>/dev/null)" == "$ROOT"/* ]] || { echo "FATAL: escaped the scratch tree" >&2; exit 1; }
}

check() {
  # check <label> <expected> <actual>
  guard_cwd
  if [[ "$2" == "$3" ]]; then ok "$1 ($3)"; else bad "$1: expected '$2' got '$3'"; fi
}

# origin repo + a clone whose HEAD is the PR branch
make_repo() {
  local d="$ROOT/$1"
  rm -rf "$d" "$d.origin"
  mkdir -p "$d.origin"
  git init -q --bare "$d.origin"
  git --git-dir="$d.origin" symbolic-ref HEAD refs/heads/master
  git clone -q "$d.origin" "$d"
  cd "$d" || { echo "FATAL: cannot enter scratch repo $d" >&2; exit 1; }
  # Hard guard: never operate on anything but the scratch clone.
  [[ "$(git rev-parse --show-toplevel)" == "$d" ]] || { echo "FATAL: not in scratch repo" >&2; exit 1; }
  [[ "$(git remote get-url origin)" == "$ROOT"/* ]] || { echo "FATAL: origin is not a scratch remote" >&2; exit 1; }
  git config user.email t@t.t
  git config user.name t
  printf 'line1\nline2\nline3\n' >app.txt
  printf 'shared\n' >other.txt
  git add -A
  git commit -qm "initial"
  git push -q origin master
  echo "$d"
}

# NB: call directly, never as "$(use_repo x)" - command substitution runs in a
# subshell and the cd would not move this shell (that bug once ran the suite
# against the real checkout).
use_repo() {
  make_repo "$1" >/dev/null
  guard_cwd
}

# resolve every conflicted file by keeping both sides (stand-in for the agent)
fake_agent() {
  local f
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    perl -0pi -e 's/^<{7}[^\n]*\n(.*?)^={7}\n(.*?)^>{7}[^\n]*\n/$1$2/gms' "$f"
  done <"$1"
}

run() {
  # run <state-dir> <subcommand>
  RESOLVE_STATE_DIR="$1" BASE_REF=master PR_TITLE="test pr" bash "$SCRIPT" "$2" 2>"$1/stderr.log"
}

get() { grep "^$2=" "$1" | tail -1 | cut -d= -f2-; }

# ---------------------------------------------------------------- case 1: clean
say "case 1: branch behind base, no conflicts -> tier 1 (history preserved)"
use_repo clean
git checkout -q -b feature
printf 'feature line\n' >>feature.txt
git add -A && git commit -qm "add feature file"
printf 'more feature\n' >>feature.txt
git add -A && git commit -qm "extend feature file"
git push -q origin feature
git checkout -q master
printf 'base change\n' >>other.txt
git commit -qam "base moves on"
git push -q origin master
git checkout -q feature
S="$ROOT/s1"
mkdir -p "$S"
run "$S" prepare >"$S/prep.out"
run "$S" finish >"$S/fin.out"
check "tier" 1 "$(get "$S/fin.out" tier)"
check "commits_after" 2 "$(get "$S/fin.out" commits_after)"
check "linear" "" "$(git rev-list --min-parents=2 origin/master..HEAD)"
git merge-base --is-ancestor origin/master HEAD && ok "contains base" || bad "missing base"

# ------------------------------------------------- case 2: conflict, one commit
say "case 2: conflicting single-commit branch -> tier 3 (squash onto base)"
use_repo conflict1
git checkout -q -b fix
sed -i 's/line2/line2-from-pr/' app.txt
git commit -qam "pr edits line2"
git push -q origin fix
git checkout -q master
sed -i 's/line2/line2-from-master/' app.txt
git commit -qam "master edits line2"
git push -q origin master
git checkout -q fix
S="$ROOT/s2"
mkdir -p "$S"
run "$S" prepare >"$S/prep.out"
check "status" conflict "$(get "$S/prep.out" status)"
check "conflicted file" "app.txt" "$(cat "$S/conflicted_files.txt")"
fake_agent "$S/conflicted_files.txt"
run "$S" finish >"$S/fin.out"
check "tier" 3 "$(get "$S/fin.out" tier)"
check "commits_after" 1 "$(get "$S/fin.out" commits_after)"
grep -q 'line2-from-master' app.txt && grep -q 'line2-from-pr' app.txt &&
  ok "both sides kept" || bad "resolution lost a side"
grep -qE '^(<{7}|>{7})' app.txt && bad "markers left" || ok "no markers"

# ----------------------------------------- case 3: conflict, multi-commit branch
say "case 3: conflicting multi-commit branch -> tier 2 (rerere replay keeps commits)"
use_repo conflict2
git checkout -q -b multi
sed -i 's/line2/line2-from-pr/' app.txt
git commit -qam "pr edits line2"
printf 'second commit\n' >>notes.txt
git add -A && git commit -qm "pr adds notes"
git push -q origin multi
git checkout -q master
sed -i 's/line2/line2-from-master/' app.txt
git commit -qam "master edits line2"
git push -q origin master
git checkout -q multi
S="$ROOT/s3"
mkdir -p "$S"
run "$S" prepare >"$S/prep.out"
check "status" conflict "$(get "$S/prep.out" status)"
fake_agent "$S/conflicted_files.txt"
run "$S" finish >"$S/fin.out"
tier3="$(get "$S/fin.out" tier)"
if [[ "$tier3" == "2" ]]; then ok "tier 2 (kept $(get "$S/fin.out" commits_after) commits)"
else bad "tier: expected 2 got $tier3 (see $S/stderr.log)"; fi
grep -q 'line2-from-master' app.txt && grep -q 'line2-from-pr' app.txt &&
  ok "both sides kept" || bad "resolution lost a side"

# --------------------------------------------- case 4: branch with merge commit
say "case 4: branch already carrying a merge commit -> flattened, canBeRebased-safe"
use_repo merged
git checkout -q -b merged-branch
sed -i 's/line3/line3-from-pr/' app.txt
git commit -qam "pr edits line3"
git push -q origin merged-branch
git checkout -q master
sed -i 's/line1/line1-from-master/' app.txt
git commit -qam "master edits line1"
git push -q origin master
git checkout -q merged-branch
git merge -q --no-ff -m "Merge branch 'master' into merged-branch" origin/master
git push -q origin merged-branch
before_merges="$(git rev-list --count --min-parents=2 origin/master..HEAD)"
check "setup has a merge commit" 1 "$before_merges"
S="$ROOT/s4"
mkdir -p "$S"
run "$S" prepare >"$S/prep.out"
check "status" merged-clean "$(get "$S/prep.out" status)"
run "$S" finish >"$S/fin.out"
check "tier" 3 "$(get "$S/fin.out" tier)"
check "no merge commits left" "" "$(git rev-list --min-parents=2 origin/master..HEAD)"
grep -q 'line3-from-pr' app.txt && grep -q 'line1-from-master' app.txt &&
  ok "content from both sides survived the flatten" || bad "flatten lost content"

# ------------------------------------------------------------ case 5: nothing to do
say "case 5: branch already rebase-mergeable -> up-to-date, no rewrite"
use_repo uptodate
git checkout -q -b tidy
printf 'tidy\n' >>tidy.txt
git add -A && git commit -qm "tidy"
git push -q origin tidy
head_before="$(git rev-parse HEAD)"
S="$ROOT/s5"
mkdir -p "$S"
run "$S" prepare >"$S/prep.out"
check "status" up-to-date "$(get "$S/prep.out" status)"
run "$S" finish >"$S/fin.out"
check "tier" 0 "$(get "$S/fin.out" tier)"
check "head untouched" "$head_before" "$(git rev-parse HEAD)"

# -------------------------------------------- case 6: agent leaves markers -> gate
say "case 6: unresolved markers must fail the gate, not push"
use_repo markers
git checkout -q -b sloppy
sed -i 's/line2/line2-from-pr/' app.txt
git commit -qam "pr edits line2"
git push -q origin sloppy
git checkout -q master
sed -i 's/line2/line2-from-master/' app.txt
git commit -qam "master edits line2"
git push -q origin master
git checkout -q sloppy
S="$ROOT/s6"
mkdir -p "$S"
run "$S" prepare >"$S/prep.out"
# "agent" does nothing at all
if run "$S" finish >"$S/fin.out" || false; then bad "finish should have failed on leftover markers"
else ok "finish refused the unresolved tree"; fi

# ------------------------------------- case 7: delete/modify conflict resolution
say "case 7: delete/modify conflict resolved by deletion"
use_repo delmod
git checkout -q -b dropper
git rm -q other.txt
git commit -qm "pr deletes other.txt"
git push -q origin dropper
git checkout -q master
printf 'master addition\n' >>other.txt
git commit -qam "master edits other.txt"
git push -q origin master
git checkout -q dropper
S="$ROOT/s7"
mkdir -p "$S"
run "$S" prepare >"$S/prep.out"
check "status" conflict "$(get "$S/prep.out" status)"
rm -f other.txt # agent decides the deletion wins
run "$S" finish >"$S/fin.out"
check "tier" 3 "$(get "$S/fin.out" tier)"
[[ -f other.txt ]] && bad "file came back" || ok "deletion preserved"

# ------------------------------------------ case 8: binary conflict -> gate fails
say "case 8: unverifiable binary conflict must fail the gate, not force-push a side"
use_repo binary
printf 'base\x00blob\n' >logo.bin # shared ancestor version, contains a NUL -> binary
git add -A && git commit -qm "add binary asset"
git push -q origin master
git checkout -q -b binmod
printf 'pr\x00blob\n' >logo.bin
git commit -qam "pr changes binary"
git push -q origin binmod
git checkout -q master
printf 'master\x00blob\n' >logo.bin
git commit -qam "master changes binary"
git push -q origin master
git checkout -q binmod
S="$ROOT/s8"
mkdir -p "$S"
run "$S" prepare >"$S/prep.out"
check "status" conflict "$(get "$S/prep.out" status)"
# The agent does nothing; git left one side's blob in the tree. finish must not
# silently stage and force-push it.
if run "$S" finish >"$S/fin.out"; then bad "finish accepted an unverifiable binary conflict"
else ok "finish refused the binary conflict"; fi

# ------------------------- case 9: zero-byte side of a binary conflict -> gate fails
say "case 9: binary conflict whose PR side is empty must still fail the gate"
use_repo binaryzero
printf 'base\x00blob\n' >logo.bin # shared ancestor, binary
git add -A && git commit -qm "add binary asset"
git push -q origin master
git checkout -q -b binzero
: >logo.bin # PR replaces the binary with a zero-byte file
git commit -qam "pr empties binary"
git push -q origin binzero
git checkout -q master
printf 'master\x00blob\n' >logo.bin
git commit -qam "master changes binary"
git push -q origin master
git checkout -q binzero
S="$ROOT/s9"
mkdir -p "$S"
run "$S" prepare >"$S/prep.out"
check "status" conflict "$(get "$S/prep.out" status)"
# The agent does nothing; git left the empty PR blob in the tree. A worktree-only
# check would wave the zero-byte file through, so finish must inspect the stages.
if run "$S" finish >"$S/fin.out"; then bad "finish accepted a zero-byte binary conflict"
else ok "finish refused the zero-byte binary conflict"; fi

# ------------- case 10: longer configured conflict-marker size still detected
say "case 10: unresolved markers longer than 7 chars must fail the gate"
use_repo longmarker
printf '* conflict-marker-size=12\n' >.gitattributes
git add -A && git commit -qm "widen conflict markers"
git push -q origin master
git checkout -q -b widefix
sed -i 's/line2/line2-from-pr/' app.txt
git commit -qam "pr edits line2"
git push -q origin widefix
git checkout -q master
sed -i 's/line2/line2-from-master/' app.txt
git commit -qam "master edits line2"
git push -q origin master
git checkout -q widefix
S="$ROOT/s10"
mkdir -p "$S"
run "$S" prepare >"$S/prep.out"
check "status" conflict "$(get "$S/prep.out" status)"
# "agent" does nothing, leaving 12-char markers behind.
if run "$S" finish >"$S/fin.out"; then bad "finish accepted 12-char conflict markers"
else ok "finish refused the wide markers"; fi

# ---------------- case 11: marker-free symlink conflict -> gate fails
say "case 11: divergent symlink retarget must fail the gate, not force-push a side"
use_repo symlink
ln -s target-base link
git add -A && git commit -qm "add symlink"
git push -q origin master
git checkout -q -b symfix
ln -sf target-pr link
git commit -qam "pr retargets symlink"
git push -q origin symfix
git checkout -q master
ln -sf target-master link
git commit -qam "master retargets symlink"
git push -q origin master
git checkout -q symfix
S="$ROOT/s11"
mkdir -p "$S"
run "$S" prepare >"$S/prep.out"
check "status" conflict "$(get "$S/prep.out" status)"
# "agent" does nothing; git left the PR's symlink target in the tree with no
# markers. finish must reject the non-regular conflict instead of staging it.
if run "$S" finish >"$S/fin.out"; then bad "finish accepted a marker-free symlink conflict"
else ok "finish refused the symlink conflict"; fi

# ------------- case 12: untracked files in the tree must not ride along
say "case 12: an untracked file left by tooling must not be committed or block the gates"
use_repo untracked
git checkout -q -b strayfix
sed -i 's/line2/line2-from-pr/' app.txt
git commit -qam "pr edits line2"
git push -q origin strayfix
git checkout -q master
sed -i 's/line2/line2-from-master/' app.txt
git commit -qam "master edits line2"
git push -q origin master
git checkout -q strayfix
S="$ROOT/s12"
mkdir -p "$S"
run "$S" prepare >"$S/prep.out"
check "status" conflict "$(get "$S/prep.out" status)"
fake_agent "$S/conflicted_files.txt"
printf 'agent transcript\n' >codex-resolution.md # what an agent action leaves behind
run "$S" finish >"$S/fin.out"
check "tier" 3 "$(get "$S/fin.out" tier)"
git ls-files --error-unmatch codex-resolution.md >/dev/null 2>&1 &&
  bad "untracked tooling file was committed into the branch" || ok "untracked file left alone"
[[ -f codex-resolution.md ]] && ok "untracked file still on disk" || bad "untracked file was deleted"

printf '\n---- %d passed, %d failed ----\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
