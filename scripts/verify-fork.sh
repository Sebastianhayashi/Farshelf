#!/bin/bash
# Verifies the D0 fork invariants: independent identity, no upstream update channel, preserved notices,
# unchanged fixtures and cross-platform sources, and a defaults domain the upstream app never sees.
#   scripts/verify-fork.sh            checks the repo and, when built, the packaged app
# Exits 0 and prints VERIFY FORK PASS when every check holds.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "VERIFY FORK FAIL: $*" >&2; exit 1; }

BASE=$(git merge-base HEAD dc2651a 2>/dev/null || echo dc2651a)

contains() { grep -q -- "$1" "$2" || fail "$2 lacks $1"; }
lacks() { ! grep -q -- "$1" "$2" || fail "$2 still has $1"; }

# The whole diff against the upstream base stays inside D0's file set.
while IFS= read -r file; do
  case "$file" in
    docs/digup-atlas-plan.md|README.md|Resources/Info.plist|Resources/Acknowledgements.txt|\
build.sh|Package.swift|.gitignore|Package.resolved|\
scripts/appcast.py|scripts/dev-run.sh|scripts/release.sh|scripts/ui/drive.sh|scripts/verify-fork.sh|\
Sources/DigUpApp/*|Sources/DigUpKit/Platform/Portable.swift|\
Tests/DigUpKitTests/ForkIdentityTests.swift) ;;
    *) fail "unexpected change outside D0 scope: $file" ;;
  esac
done < <(git diff --name-only "$BASE" HEAD)

# Notices the fork must not have touched. Acknowledgements.txt is deliberately
# edited by D0 to drop the Sparkle notice, so its required contents are checked
# below instead of asserting the file is unchanged.
git diff --quiet "$BASE" HEAD -- LICENSE || fail "LICENSE changed"
git diff --quiet "$BASE" HEAD -- Tests/DigUpKitTests/Pictures Tests/DigUpKitTests/Videos \
  Tests/LlamaRuntimeTests/Reference || fail "a checked-in fixture changed"

# Cross-platform sources stay intact. The one exception is the fork-identity
# path table, which D0 must edit so the fork never writes to upstream locations.
git diff --quiet "$BASE" HEAD -- Sources/DigUpKit Sources/digup Sources/LlamaRuntime \
  Sources/CLlama Sources/CLlamaShared Sources/CLlamaWindows Sources/CPDFium \
  ':(exclude)Sources/DigUpKit/Platform/Portable.swift' || fail "cross-platform source changed"

PLIST=Resources/Info.plist
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")" == "org.digupatlas.app" ]] \
  || fail "bundle identifier is not org.digupatlas.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$PLIST")" == "DigUp Atlas" ]] \
  || fail "display name is not DigUp Atlas"
/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$PLIST" >/dev/null 2>&1 && fail "SUFeedURL still set"
/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$PLIST" >/dev/null 2>&1 && fail "SUPublicEDKey still set"
! /usr/libexec/PlistBuddy -c 'Print :SUEnableAutomaticChecks' "$PLIST" >/dev/null 2>&1 || fail "SUEnableAutomaticChecks still set"

contains "MIT License" LICENSE
contains "Copyright (c) 2026 Abdur Rahim" LICENSE
contains "llama.cpp" Resources/Acknowledgements.txt
[[ ! -e Sources/DigUpApp/Updates.swift ]] || fail "Updates.swift still exists"
! grep -rl "import Sparkle" Sources --include='*.swift' | grep -q . || fail "a source file still imports Sparkle"
lacks "sparkle-project" Package.swift
lacks "Sparkle" build.sh

# The packaged app, when built, carries the notices and the same identity, with no updater framework.
APP=build.noindex/DigUpAtlas.app
if [[ -d "$APP" ]]; then
  [[ -f "$APP/Contents/Resources/LICENSE" ]] || fail "the packaged app lacks LICENSE"
  [[ -f "$APP/Contents/Resources/Acknowledgements.txt" ]] || fail "the packaged app lacks Acknowledgements.txt"
  [[ ! -d "$APP/Contents/Frameworks" ]] || fail "the packaged app still embeds frameworks"
  PAPP="$APP/Contents/Info.plist"
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PAPP")" == "org.digupatlas.app" ]] \
    || fail "packaged bundle identifier is not org.digupatlas.app"
  ! /usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$PAPP" >/dev/null 2>&1 || fail "packaged SUFeedURL still set"
fi

# A short run with its own defaults suite must not touch the upstream domain. Read-only on it: export before
# and after and compare.
UPSTREAM=com.abdurrahim.DigUp
BEFORE=$(defaults export "$UPSTREAM" - 2>/dev/null || true)
if [[ -d "$APP" ]]; then
  SCRATCH=$(mktemp -d)
  EXE="$(cd "$APP" && pwd -P)/Contents/MacOS/DigUpAtlas"
  pkill -f "$EXE" 2>/dev/null || true
  open -n "$APP" --args -roots "$SCRATCH/fixture" -indexDir "$SCRATCH/index" -modelsDir "$SCRATCH/models" \
    -defaultsSuite org.digupatlas.app.verify -debugQuitAfter 5
  sleep 9
  [[ -f "$SCRATCH/index/app.log" ]] || fail "the app did not run"
  rm -rf "$SCRATCH"
else
  echo "note: $APP not built; skipping the defaults-isolation run"
fi
AFTER=$(defaults export "$UPSTREAM" - 2>/dev/null || true)
[[ "$BEFORE" == "$AFTER" ]] || fail "the upstream defaults domain changed"

echo "VERIFY FORK PASS"
