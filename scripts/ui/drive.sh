#!/bin/bash
# Drives the packaged Farshelf app like a user: launches it against a fixture folder, types a query into the
# real search field through Accessibility, waits for results, and captures the window with screencapture.
#   scripts/ui/drive.sh
# Env overrides:
#   APP     the bundle (default build.noindex/Farshelf.app)
#   FIXTURE the folder the app searches (default verification/D0/fixture, created with known content if absent)
#   QUERY   what to search for (default football)
#   OUT     where the screenshot and logs go (default verification/D0)
#   MODELS  the model folder (default $OUT/models; seeded from the Hugging Face cache when it has the pinned files)
#   SUITE   the defaults suite (default org.digupatlas.app.drive, never the app's real settings)
#   TIMEOUT seconds to wait for results on a cold index (default 1800; re-runs reuse the index and are fast)
# Prints DRIVE PASS with the screenshot path and exits 0. Exits 1 with the app log's tail on any failure.
set -euo pipefail
cd "$(dirname "$0")/../.."

APP="${APP:-build.noindex/Farshelf.app}"
FIXTURE="${FIXTURE:-verification/D0/fixture}"
QUERY="${QUERY:-football}"
OUT="${OUT:-verification/D0}"
MODELS="${MODELS:-$OUT/models}"
SUITE="${SUITE:-org.digupatlas.app.drive}"
TIMEOUT="${TIMEOUT:-1800}"

fail() { echo "DRIVE FAIL: $*" >&2; [[ -f "$OUT/index/app.log" ]] && tail -20 "$OUT/index/app.log" >&2; exit 1; }

[[ -d "$APP" ]] || fail "$APP does not exist; run ./build.sh first"
mkdir -p "$OUT"

# Accessibility and screencapture see nothing on a locked console: the app would look broken when it is not.
LOCKED=$(swift -e 'import CoreGraphics
let d = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
print(d["CGSSessionScreenIsLocked"] as? Bool == true ? "yes" : "no")' 2>/dev/null)
[[ "$LOCKED" == "no" ]] || fail "the console is locked; unlock it and run again"

# The fixture: two small documents the query separates. Never written after this.
if [[ ! -d "$FIXTURE" ]]; then
  mkdir -p "$FIXTURE"
  printf 'Football is the most popular sport in the world. The football match on Saturday drew a huge crowd.\n' \
    > "$FIXTURE/football.txt"
  printf 'A recipe for sourdough bread with flour, water and salt.\n' > "$FIXTURE/bread.txt"
fi
BEFORE=$(find "$FIXTURE" -type f -exec shasum -a 256 {} + | sort)

SNAPSHOT="$HOME/.cache/huggingface/hub/models--ggml-org--embeddinggemma-2-GGUF/snapshots/bfcd298762cc34d0357ece5ebdd31791a3a374d8"
if [[ ! -f "$MODELS/embeddinggemma-2-Q8_0.gguf" && -f "$SNAPSHOT/embeddinggemma-2-Q8_0.gguf" ]]; then
  mkdir -p "$MODELS"
  for file in embeddinggemma-2-Q8_0.gguf mmproj-embeddinggemma-2-Q8_0.gguf; do
    [[ -f "$MODELS/$file" || ! -e "$SNAPSHOT/$file" ]] || cp -cL "$SNAPSHOT/$file" "$MODELS/$file"
  done
fi

EXE="$(cd "$APP" && pwd -P)/Contents/MacOS/Farshelf"
pkill -f "$EXE" 2>/dev/null || true
sleep 1

echo "launching $APP (roots $FIXTURE, query \"$QUERY\")"
T0=$(date +%s)
open -n "$APP" --args -roots "$(cd "$FIXTURE" && pwd)" -indexDir "$(pwd)/$OUT/index" \
  -modelsDir "$(pwd)/$MODELS" -defaultsSuite "$SUITE" -uiDriver YES

AX='tell application "System Events" to tell process "Farshelf"'
deadline=$((SECONDS + 120))
while true; do
  W=$(osascript -e "$AX"' to get {count of windows, value of attribute "AXIdentifier" of window 1}' 2>/dev/null) || true
  [[ "$W" == "1, digupatlas.searchWindow" ]] && break
  [[ $SECONDS -lt $deadline ]] || fail "the search window never appeared (last probe: ${W:-none})"
  sleep 0.5
done
T_WINDOW=$(date +%s)
echo "window digupatlas.searchWindow at $((T_WINDOW - T0)) s"

set_field() {
  osascript - "$QUERY" <<'APPLESCRIPT' 2>&1
on findById(elements, target)
  repeat with e in elements
    try
      if (value of attribute "AXIdentifier" of e) is target then return e
    end try
    try
      set sub to UI elements of e
      if (count of sub) > 0 then
        set hit to my findById(sub, target)
        if hit is not missing value then return hit
      end if
    end try
  end repeat
  return missing value
end findById

on run argv
  tell application "System Events"
    tell process "Farshelf"
      set field to my findById(UI elements of window 1, "digupatlas.searchField")
      if field is missing value then error "digupatlas.searchField not found"
      set focused of field to true
      set value of field to item 1 of argv
    end tell
  end tell
end run
APPLESCRIPT
}
set_field || fail "could not type the query (Accessibility permission for the caller?)"

deadline=$((SECONDS + TIMEOUT))
COUNT=""
while true; do
  COUNT=$(osascript <<'APPLESCRIPT' 2>/dev/null || true
on findById(elements, target)
  repeat with e in elements
    try
      if (value of attribute "AXIdentifier" of e) is target then return e
    end try
    try
      set sub to UI elements of e
      if (count of sub) > 0 then
        set hit to my findById(sub, target)
        if hit is not missing value then return hit
      end if
    end try
  end repeat
  return missing value
end findById

on run
  tell application "System Events"
    tell process "Farshelf"
      set t to my findById(UI elements of window 1, "digupatlas.resultCount")
      if t is missing value then return ""
      return value of t as text
    end tell
  end tell
end run
APPLESCRIPT
)
  case "$COUNT" in
    [1-9]*result*) break ;;
  esac
  [[ $SECONDS -lt $deadline ]] || fail "no results within $TIMEOUT s (last count: ${COUNT:-none})"
  sleep 2
done
T_RESULTS=$(date +%s)
echo "results at $((T_RESULTS - T0)) s: $COUNT"

sleep 1
read -r X Y W H <<<"$(osascript -e "$AX"' to get {item 1 of (position of window 1), item 2 of (position of window 1), item 1 of (size of window 1), item 2 of (size of window 1)}' | tr ',' ' ')"
SHOT="$OUT/fork-driver.png"
screencapture -R "$X,$Y,$W,$H" -x "$SHOT"
BYTES=$(stat -f %z "$SHOT")
[[ "$BYTES" -gt 20000 ]] || fail "screenshot too small (${BYTES} B): the capture was probably refused"
sips -g pixelWidth -g pixelHeight "$SHOT" | tail -2

AFTER=$(find "$FIXTURE" -type f -exec shasum -a 256 {} + | sort)
[[ "$BEFORE" == "$AFTER" ]] || fail "the fixture changed during the run"

osascript -e 'tell application id "org.digupatlas.app" to quit' || true
for _ in $(seq 1 20); do pgrep -f "$EXE" >/dev/null || break; sleep 0.5; done

echo "DRIVE PASS: $SHOT ($BYTES bytes, window at $((T_WINDOW - T0)) s, results at $((T_RESULTS - T0)) s)"
