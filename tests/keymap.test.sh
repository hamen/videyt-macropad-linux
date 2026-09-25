#!/usr/bin/env bash
# tests/keymap.test.sh — check that macropad.yaml puts the macro keys where the
# README says they are.
#
# `ch57x-keyboard-tool validate` only checks that every name is a key it knows, so
# a key moved to the wrong cell, or a row shifted by one, validates fine and then
# types the wrong thing on the pad. The cells are (row, col) of the `buttons` list:
# row = list index, col = element. Physical positions are in the comment block at
# the top of macropad.yaml.
#
# Run:  tests/keymap.test.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$REPO_DIR/macropad.yaml"

fail() { printf '\033[1;31mFAIL\033[0m %s\n' "$*"; exit 1; }
pass() { printf '\033[1;32mok\033[0m   %s\n' "$*"; }

command -v python3 >/dev/null 2>&1 || fail "python3 not found"

# The button rows are flow sequences of double-quoted strings, which is also valid
# JSON, so no YAML library is needed.
cell() { # $1 row, $2 col -> prints the key name
  python3 - "$CONFIG" "$1" "$2" <<'PY'
import json, re, sys
path, row, col = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
rows, inside = [], False
for line in open(path):
    if re.match(r"\s*- buttons:\s*$", line):
        inside = True
        continue
    if inside:
        m = re.match(r"\s*- (\[.*\])\s*$", line)
        if not m:
            break
        rows.append(json.loads(m.group(1)))
print(rows[row][col])
PY
}

check() { # $1 row, $2 col, $3 expected, $4 what it is
  got="$(cell "$1" "$2")" || fail "could not read cell ($1,$2) from macropad.yaml"
  [ "$got" = "$3" ] || fail "cell ($1,$2) — $4 — is '$got', expected '$3'"
  pass "cell ($1,$2) is '$3' — $4"
}

check 0 1 favorites  "physical row 3 col 1, the 'round' key"
check 1 0 calculator "physical row 3 col 2, the '/compact' key"
check 1 4 j          "physical row 3 col 3, the one free key"

printf '\n\033[1;32mAll keymap tests passed.\033[0m\n'
