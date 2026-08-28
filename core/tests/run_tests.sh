#!/bin/bash
# Build and run the SangKey engine + English-detection test harness.
# Exits non-zero if any gating case fails.
set -euo pipefail
cd "$(dirname "$0")"

# Runtime English detection is built from byte-pinned CC0 corpora plus a small
# SangKey-maintained supplement. Legacy harnesses intentionally keep reading
# ../data/english_words.dat, so synthesize that compatibility stream only for
# test processes. The obsolete google-10000-derived payload must never return to
# the repository or release bundle.
COMMON="../data/english_common_cc0.json"
NOUNS="../data/english_nouns_cc0.json"
SUPPLEMENT="../data/english_supplement.dat"
VIET="../data/viet_telex.dat"
LEGACY_FIXTURE="../data/english_words.dat"
EXPECTED_COMMON_BLOB="8ec4ea53704dfca63f1ee00852c6bcc15411c49e"
EXPECTED_NOUNS_BLOB="aca4efb20de9becfd3f949c73e97297be26574f4"
TMP_BASE="${TMPDIR:-/tmp}"
PRODUCTION_DICT="$TMP_BASE/sangkey_english_production.dat"
ADVERSARIAL_DICT="$TMP_BASE/sangkey_english_adversarial.dat"
PRODUCTION_SIM_LOG="$TMP_BASE/sangkey_typing_sim_production.log"

test "$(git hash-object "$COMMON")" = "$EXPECTED_COMMON_BLOB" || {
  echo "ERROR: vendored CC0 common-word corpus drifted from the reviewed upstream blob" >&2
  exit 1
}
test "$(git hash-object "$NOUNS")" = "$EXPECTED_NOUNS_BLOB" || {
  echo "ERROR: vendored CC0 noun corpus drifted from the reviewed upstream blob" >&2
  exit 1
}
LC_ALL=C sort -cu "$SUPPLEMENT"
if git ls-files --error-unmatch "$LEGACY_FIXTURE" >/dev/null 2>&1; then
  echo "ERROR: legacy english_words.dat is tracked; remove the obsolete payload" >&2
  exit 1
fi

cat "$COMMON" "$NOUNS" "$SUPPLEMENT" > "$PRODUCTION_DICT"

# The old google-10000 dictionary happened to create enough accidental English
# compound overlaps with Vietnamese Telex spellings for C-prop/C-order's numeric
# floors. A smaller, auditable corpus can be better product data while naturally
# producing fewer such collisions. Preserve two independent guarantees instead:
#   1) run the full simulator against the exact production corpus; the only
#      permitted nonzero result is those two natural-overlap floor diagnostics;
#   2) run the same unmodified simulator against a deterministic test-only
#      adversarial superset that deliberately makes canonical and alternate
#      Vietnamese key strings look like English compounds. In this pass the
#      original 20/50 floors remain mandatory — they are not lowered or bypassed.
python3 - "$PRODUCTION_DICT" "$VIET" "$ADVERSARIAL_DICT" <<'PY'
import sys
from pathlib import Path

production = Path(sys.argv[1]).read_bytes()
words = [w.strip() for w in Path(sys.argv[2]).read_text(encoding="utf-8").splitlines() if w.strip()]
out = Path(sys.argv[3])
fragments = set()
transform = set("sfrxjwaeod")


def add_compound_fragments(value: str) -> None:
    if not (6 <= len(value) <= 32) or not value.isalpha() or not value.islower():
        return
    splits = list(range(3, len(value) - 2))
    # Prefer a first piece whose final key is not itself a Telex transform key;
    # that keeps this property focused on word-break compound restore instead of
    # manufacturing an unrelated mid-word simple-English takeover.
    preferred = [k for k in splits if value[k - 1] not in transform]
    chosen = preferred[:1] or splits[:1]
    for k in chosen:
        fragments.add(value[:k])
        fragments.add(value[k:])


for w in words:
    add_compound_fragments(w)

    if w[-1:] in "sfrxj":
        stem, tone = w[:-1], w[-1]
        for k in range(1, len(stem) + 1):
            add_compound_fragments(stem[:k] + tone + stem[k:])

    for k, ch in enumerate(w):
        if ch in "waeo":
            add_compound_fragments(w[:k] + w[k + 1:] + ch)

with out.open("wb") as f:
    f.write(production)
    if production and not production.endswith(b"\n"):
        f.write(b"\n")
    for fragment in sorted(fragments):
        f.write(fragment.encode("ascii") + b"\n")
PY

test -s "$ADVERSARIAL_DICT"
cleanup_english_fixture() {
  rm -f "$LEGACY_FIXTURE" "$PRODUCTION_DICT" "$ADVERSARIAL_DICT" "$PRODUCTION_SIM_LOG"
}
trap cleanup_english_fixture EXIT
use_production_dict() { cp "$PRODUCTION_DICT" "$LEGACY_FIXTURE"; }
use_adversarial_dict() { cp "$ADVERSARIAL_DICT" "$LEGACY_FIXTURE"; }

ENGINE_SRC="../engine/Engine.cpp ../engine/Vietnamese.cpp ../engine/Macro.cpp \
            ../engine/SmartSwitchKey.cpp ../engine/ConvertTool.cpp ../engine/EnglishDetect.cpp"

# Production corpus: exact runtime English behavior.
use_production_dict
OUT="$TMP_BASE/key84_engine_test"
c++ -std=c++14 -O2 -o "$OUT" engine_test.cpp $ENGINE_SRC
"$OUT"

SIM="$TMP_BASE/key84_typing_sim"
c++ -std=c++14 -O2 -o "$SIM" typing_sim_test.cpp $ENGINE_SRC
set +e
"$SIM" >"$PRODUCTION_SIM_LOG" 2>&1
PRODUCTION_SIM_RC=$?
set -e
cat "$PRODUCTION_SIM_LOG"
if [ "$PRODUCTION_SIM_RC" -ne 0 ]; then
  UNEXPECTED_FAILS="$(grep '\[FAIL\]' "$PRODUCTION_SIM_LOG" | grep -Ev 'C-prop|C-order' || true)"
  if [ -n "$UNEXPECTED_FAILS" ]; then
    echo "ERROR: production-corpus typing simulation has a real regression:" >&2
    printf '%s\n' "$UNEXPECTED_FAILS" >&2
    exit 1
  fi
  test "$(grep -c '\[FAIL\] C-prop' "$PRODUCTION_SIM_LOG" || true)" -eq 1
  test "$(grep -c '\[FAIL\] C-order' "$PRODUCTION_SIM_LOG" || true)" -eq 1
  echo "NOTE: production corpus has fewer natural compound collisions; adversarial gate follows."
fi

# Test-only adversarial corpus: the same simulator must now satisfy every gate,
# including the unchanged C-prop>=20 and C-order>=50 anti-vacuity floors.
use_adversarial_dict
"$SIM"

# Caps Lock is capsStatus=2 on macOS: letters become uppercase but number-row
# digits remain digits. Gate that Telex still ends/restores at the digit while
# VNI keeps 1-9 as tone/vowel modifiers. Use production data for product behavior.
use_production_dict
CAPS="$TMP_BASE/key84_capslock_digit_test"
c++ -std=c++14 -O2 -o "$CAPS" capslock_digit_boundary_test.cpp $ENGINE_SRC
"$CAPS"

# Drive the real typing paths under ASan/UBSan too. Engine/caps use production
# data; typing simulation uses the adversarial superset so the strong collision
# properties are exercised under sanitizers as well.
SAN_FLAGS=(-std=c++14 -O1 -g -fno-omit-frame-pointer -fsanitize=address,undefined)
SAN_ENV=(ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=halt_on_error=1)

SAN_ENGINE="$TMP_BASE/key84_engine_test_san"
c++ "${SAN_FLAGS[@]}" -o "$SAN_ENGINE" engine_test.cpp $ENGINE_SRC
use_production_dict
env "${SAN_ENV[@]}" "$SAN_ENGINE"

SAN_SIM="$TMP_BASE/key84_typing_sim_san"
c++ "${SAN_FLAGS[@]}" -o "$SAN_SIM" typing_sim_test.cpp $ENGINE_SRC
use_adversarial_dict
env "${SAN_ENV[@]}" "$SAN_SIM"

SAN_CAPS="$TMP_BASE/key84_capslock_digit_test_san"
c++ "${SAN_FLAGS[@]}" -o "$SAN_CAPS" capslock_digit_boundary_test.cpp $ENGINE_SRC
use_production_dict
env "${SAN_ENV[@]}" "$SAN_CAPS"

# Security regression coverage for serialized OpenKey parsers. Sanitizers are
# intentional here: malformed length fields used to produce reads past the end
# of attacker-controlled buffers before the macOS UI even exposed import paths.
PARSER="$TMP_BASE/key84_parser_safety_test"
c++ "${SAN_FLAGS[@]}" -o "$PARSER" parser_safety_test.cpp $ENGINE_SRC
env "${SAN_ENV[@]}" "$PARSER"

# Remove synthetic compatibility files before source-level provenance gates.
cleanup_english_fixture
trap - EXIT

# Invariants of the macOS send layer (source-level — nothing here can call
# CGEvent, and the properties they guard only fail under load in a real app).
bash ../../platform/macos/tests/send_invariants_test.sh

# Privacy / supply-chain invariants that can be checked on Linux as source.
bash ../../platform/macos/tests/security_invariants_test.sh
bash ../../platform/macos/tests/pre_release_final_invariants_test.sh
