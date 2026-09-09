#!/usr/bin/env bash
# Exercise pr-rebase-resolve.sh against synthetic repos.
#
#   .github/scripts/test-pr-rebase-resolve.sh .github/scripts/pr-rebase-resolve.sh
#
# Every case builds a throwaway bare origin plus a clone under a mktemp root and
# asserts it never leaves that tree; nothing here touches a real repository.
# Portable to macOS: no readlink -f, no GNU sed -i.
set -euo pipefail

SCRIPT="$(cd "$(dirname "${1:?path to pr-rebase-resolve.sh is required}")" && pwd)/$(basename "$1")"
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
  git clone -q "$d.origin" "$d" 2>/dev/null
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
}

# NB: call directly, never as "$(use_repo x)" - command substitution runs in a
# subshell and the cd would not move this shell (that bug once ran the suite
# against the real checkout).
use_repo() {
  make_repo "$1" >/dev/null
  guard_cwd
}

# edit in place without GNU sed -i
sub() { perl -pi -e "s/$1/$2/" "$3"; }

# resolve every conflicted file by keeping both sides (stand-in for the agent)
fake_agent() {
  local f
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    perl -0pi -e 's/^<{3,}[^\n]*\n(.*?)^={3,}\n(.*?)^>{3,}[^\n]*\n/$1$2/gms' "$f"
  done <"$1"
}

run() {
  # run <state-dir> <subcommand>
  RESOLVE_STATE_DIR="$1" BASE_REF=master PR_TITLE="test pr" bash "$SCRIPT" "$2" 2>"$1/stderr.log"
}

get() { grep "^$2=" "$1" | tail -1 | cut -d= -f2-; }

# PR branch <name> edits line2 one way, master edits it another -> conflict
diverge_line2() {
  git checkout -q -b "$1"
  sub line2 line2-from-pr app.txt
  git commit -qam "pr edits line2"
  git push -q origin "$1"
  git checkout -q master
  sub line2 line2-from-master app.txt
  git commit -qam "master edits line2"
  git push -q origin master
  git checkout -q "$1"
}

# PR branch <name> deletes other.txt, master edits it -> modify/delete conflict
diverge_delete() {
  git checkout -q -b "$1"
  git rm -q other.txt
  git commit -qm "pr deletes other.txt"
  git push -q origin "$1"
  git checkout -q master
  printf 'master addition\n' >>other.txt
  git commit -qam "master edits other.txt"
  git push -q origin master
  git checkout -q "$1"
}

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
diverge_line2 fix
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
sub line2 line2-from-pr app.txt
git commit -qam "pr edits line2"
printf 'second commit\n' >>notes.txt
git add -A && git commit -qm "pr adds notes"
git push -q origin multi
git checkout -q master
sub line2 line2-from-master app.txt
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
sub line3 line3-from-pr app.txt
git commit -qam "pr edits line3"
git push -q origin merged-branch
git checkout -q master
sub line1 line1-from-master app.txt
git commit -qam "master edits line1"
git push -q origin master
git checkout -q merged-branch
git merge -q --no-ff -m "Merge branch 'master' into merged-branch" origin/master
git push -q origin merged-branch
check "setup has a merge commit" 1 "$(git rev-list --count --min-parents=2 origin/master..HEAD)"
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
diverge_line2 sloppy
S="$ROOT/s6"
mkdir -p "$S"
run "$S" prepare >"$S/prep.out"
# "agent" does nothing at all
if run "$S" finish >"$S/fin.out"; then bad "finish should have failed on leftover markers"
else ok "finish refused the unresolved tree"; fi

# ------------------------------------- case 7: delete/modify conflict resolution
say "case 7: modify/delete conflict resolved by deletion"
use_repo delmod
diverge_delete dropper
S="$ROOT/s7"
mkdir -p "$S"
run "$S" prepare >"$S/prep.out"
check "status" conflict "$(get "$S/prep.out" status)"
rm -f other.txt # agent decides the deletion wins
run "$S" finish >"$S/fin.out"
check "tier" 3 "$(get "$S/fin.out" tier)"
[[ -f other.txt ]] && bad "file came back" || ok "deletion preserved"

# ------------------------------------------------ case 8: binary conflict refused
say "case 8: unverifiable binary conflict must be refused before any agent runs"
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
if run "$S" prepare >"$S/prep.out"; then bad "prepare accepted an unverifiable binary conflict"
else ok "prepare refused the binary conflict"; fi
grep -q 'binary/non-text' "$S/error.txt" && ok "reason names the binary" || bad "reason missing"

# ------------------------- case 9: zero-byte side of a binary conflict refused
say "case 9: binary conflict whose PR side is empty must still be refused"
use_repo binaryzero
printf 'base\x00blob\n' >logo.bin
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
if run "$S" prepare >"$S/prep.out"; then bad "prepare accepted a zero-byte binary conflict"
else ok "prepare refused the zero-byte binary conflict"; fi

# ------------- case 10: longer configured conflict-marker size still detected
say "case 10: unresolved markers longer than 7 chars must fail the gate"
use_repo longmarker
printf '* conflict-marker-size=12\n' >.gitattributes
git add -A && git commit -qm "widen conflict markers"
git push -q origin master
diverge_line2 widefix
S="$ROOT/s10"
mkdir -p "$S"
run "$S" prepare >"$S/prep.out"
check "status" conflict "$(get "$S/prep.out" status)"
# "agent" does nothing, leaving 12-char markers behind.
if run "$S" finish >"$S/fin.out"; then bad "finish accepted 12-char conflict markers"
else ok "finish refused the wide markers"; fi

# ---------------- case 11: marker-free symlink conflict refused
say "case 11: divergent symlink retarget must be refused, not force-push a side"
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
if run "$S" prepare >"$S/prep.out"; then bad "prepare accepted a marker-free symlink conflict"
else ok "prepare refused the symlink conflict"; fi

# ------------- case 12: pre-existing untracked files must not ride along
say "case 12: an untracked artifact present before prepare is neither committed nor a gate failure"
use_repo untracked
diverge_line2 strayfix
printf 'build cache\n' >stray-artifact.txt # present before the resolver starts
S="$ROOT/s12"
mkdir -p "$S"
run "$S" prepare >"$S/prep.out"
check "status" conflict "$(get "$S/prep.out" status)"
fake_agent "$S/conflicted_files.txt"
run "$S" finish >"$S/fin.out"
check "tier" 3 "$(get "$S/fin.out" tier)"
git ls-files --error-unmatch stray-artifact.txt >/dev/null 2>&1 &&
  bad "pre-existing untracked file was committed" || ok "pre-existing untracked file left alone"
[[ -f stray-artifact.txt ]] && ok "untracked file still on disk" || bad "untracked file was deleted"

# --------------- case 13: a file the resolution creates must be committed
say "case 13: a rename made by the resolution (new file + deleted old) is committed whole"
use_repo rename
diverge_line2 renamefix
S="$ROOT/s13"
mkdir -p "$S"
run "$S" prepare >"$S/prep.out"
check "status" conflict "$(get "$S/prep.out" status)"
fake_agent "$S/conflicted_files.txt"
git mv -q other.txt other-renamed.txt 2>/dev/null || { mv other.txt other-renamed.txt; }
git reset -q other.txt other-renamed.txt 2>/dev/null || true # leave it as delete + untracked, as an agent would
run "$S" finish >"$S/fin.out"
check "tier" 3 "$(get "$S/fin.out" tier)"
git ls-files --error-unmatch other-renamed.txt >/dev/null 2>&1 &&
  ok "rename destination committed" || bad "rename destination was dropped"
git ls-files --error-unmatch other.txt >/dev/null 2>&1 &&
  bad "old path still tracked" || ok "old path removed"

# ---------------- case 14: markerless modify/delete left untouched -> gate fails
say "case 14: modify/delete left at git's default (agent did nothing) must fail"
use_repo delmodnoop
diverge_delete dropper2
S="$ROOT/s14"
mkdir -p "$S"
run "$S" prepare >"$S/prep.out"
check "status" conflict "$(get "$S/prep.out" status)"
# "agent" does nothing: git left master's edited other.txt in the tree with no
# markers. Staging it would silently drop the PR's deletion.
if run "$S" finish >"$S/fin.out"; then bad "finish accepted an untouched modify/delete"
else ok "finish refused the untouched modify/delete"; fi

# ---------------- case 15: modify/delete reconciled by editing the file -> ok
say "case 15: modify/delete resolved by editing the surviving file is accepted"
use_repo delmodedit
diverge_delete dropper3
S="$ROOT/s15"
mkdir -p "$S"
run "$S" prepare >"$S/prep.out"
check "status" conflict "$(get "$S/prep.out" status)"
printf 'reconciled\n' >other.txt # agent makes a visible decision to keep and edit
run "$S" finish >"$S/fin.out"
check "tier" 3 "$(get "$S/fin.out" tier)"
[[ -f other.txt ]] && ok "reconciled file kept" || bad "reconciled file vanished"

# ------------- case 16: shorter configured conflict-marker size still detected
say "case 16: unresolved markers shorter than 7 chars must fail the gate"
use_repo shortmarker
printf '* conflict-marker-size=3\n' >.gitattributes
git add -A && git commit -qm "narrow conflict markers"
git push -q origin master
diverge_line2 narrowfix
S="$ROOT/s16"
mkdir -p "$S"
run "$S" prepare >"$S/prep.out"
check "status" conflict "$(get "$S/prep.out" status)"
# "agent" does nothing, leaving 3-char markers behind.
if run "$S" finish >"$S/fin.out"; then bad "finish accepted 3-char conflict markers"
else ok "finish refused the short markers"; fi

# --------- case 17: a newline-only text stage must not be misflagged as binary
say "case 17: a conflict whose PR side is only newlines must resolve as text"
use_repo newline
printf 'keep\n' >blank.txt
git add -A && git commit -qm "add blank.txt"
git push -q origin master
git checkout -q -b nlfix
printf '\n\n' >blank.txt # PR reduces the file to blank lines - still text
git commit -qam "pr blanks the file"
git push -q origin nlfix
git checkout -q master
printf 'master edit\n' >blank.txt
git commit -qam "master edits blank.txt"
git push -q origin master
git checkout -q nlfix
S="$ROOT/s17"
mkdir -p "$S"
run "$S" prepare >"$S/prep.out"
check "status" conflict "$(get "$S/prep.out" status)"
fake_agent "$S/conflicted_files.txt"
run "$S" finish >"$S/fin.out"
check "tier" 3 "$(get "$S/fin.out" tier)"
grep -q 'master edit' blank.txt &&
  ok "newline-only stage accepted as text" || bad "resolution refused or dropped a side"

# --- case 18: a conflicted path git would C-quote must be refused, not mis-scanned
say "case 18: a conflicted path containing a control character is refused up front"
use_repo ctrlpath
fname=$'weird\tname.txt' # a literal tab; git C-quotes this in --name-only output
printf 'base\n' >"$fname"
git add -A && git commit -qm "add control-character path"
git push -q origin master
git checkout -q -b ctrlfix
printf 'pr\n' >"$fname"
git commit -qam "pr edits it"
git push -q origin ctrlfix
git checkout -q master
printf 'master\n' >"$fname"
git commit -qam "master edits it"
git push -q origin master
git checkout -q ctrlfix
S="$ROOT/s18"
mkdir -p "$S"
if run "$S" prepare >"$S/prep.out"; then bad "prepare accepted a control-character path"
else ok "prepare refused the control-character path"; fi

# ------------------ case 19: a present-but-unrunnable verify hook is a failure
say "case 19: a verification hook that exists but is not executable fails the gate"
use_repo hook
mkdir -p .github
printf '#!/bin/sh\nexit 0\n' >.github/resolve-verify.sh # deliberately not chmod +x
git add -A && git commit -qm "add hook without exec bit"
git push -q origin master
git checkout -q -b hookfix
printf 'x\n' >>app.txt
git commit -qam "pr edit"
git push -q origin hookfix
git checkout -q master
printf 'y\n' >>other.txt
git commit -qam "master edit"
git push -q origin master
git checkout -q hookfix
S="$ROOT/s19"
mkdir -p "$S"
run "$S" prepare >"$S/prep.out"
check "status" clean "$(get "$S/prep.out" status)"
if run "$S" finish >"$S/fin.out"; then bad "finish skipped a non-executable hook silently"
else ok "finish refused the non-executable hook"; fi

printf '\n---- %d passed, %d failed ----\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
