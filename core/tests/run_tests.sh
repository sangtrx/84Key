#!/bin/bash
# Build and run the 84Key engine + English-detection test harness.
# Exits non-zero if any case fails.
set -euo pipefail
cd "$(dirname "$0")"

ENGINE_SRC="../engine/Engine.cpp ../engine/Vietnamese.cpp ../engine/Macro.cpp \
            ../engine/SmartSwitchKey.cpp ../engine/ConvertTool.cpp ../engine/EnglishDetect.cpp"

OUT="${TMPDIR:-/tmp}/key84_engine_test"
c++ -std=c++14 -O2 -o "$OUT" engine_test.cpp $ENGINE_SRC
"$OUT"

# Keystroke-level simulation of the macOS host's typing pipeline (catches
# host-decode bugs the engine harness cannot). Its gating fixture includes the
# Telex/Simple-Telex alphanumeric boundary regressions; this same simulator runs
# again under sanitizers below, so no second/approximate host decoder is needed.
SIM="${TMPDIR:-/tmp}/key84_typing_sim"
c++ -std=c++14 -O2 -o "$SIM" typing_sim_test.cpp $ENGINE_SRC
"$SIM"

# Caps Lock is capsStatus=2 on macOS: letters become uppercase but number-row
# digits remain digits. Gate that Telex still ends/restores at the digit while
# VNI keeps 1-9 as tone/vowel modifiers.
CAPS="${TMPDIR:-/tmp}/key84_capslock_digit_test"
c++ -std=c++14 -O2 -o "$CAPS" capslock_digit_boundary_test.cpp $ENGINE_SRC
"$CAPS"

# Drive the real typing paths under ASan/UBSan too. Parser-only sanitization is
# not enough for a legacy input engine: normal typing exercises state-history,
# alternate-spelling and restore paths that malformed-file tests never touch.
SAN_FLAGS=(-std=c++14 -O1 -g -fno-omit-frame-pointer -fsanitize=address,undefined)
SAN_ENV=(ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=halt_on_error=1)

SAN_ENGINE="${TMPDIR:-/tmp}/key84_engine_test_san"
c++ "${SAN_FLAGS[@]}" -o "$SAN_ENGINE" engine_test.cpp $ENGINE_SRC
env "${SAN_ENV[@]}" "$SAN_ENGINE"

SAN_SIM="${TMPDIR:-/tmp}/key84_typing_sim_san"
c++ "${SAN_FLAGS[@]}" -o "$SAN_SIM" typing_sim_test.cpp $ENGINE_SRC
env "${SAN_ENV[@]}" "$SAN_SIM"

SAN_CAPS="${TMPDIR:-/tmp}/key84_capslock_digit_test_san"
c++ "${SAN_FLAGS[@]}" -o "$SAN_CAPS" capslock_digit_boundary_test.cpp $ENGINE_SRC
env "${SAN_ENV[@]}" "$SAN_CAPS"

# Security regression coverage for serialized OpenKey parsers. Sanitizers are
# intentional here: malformed length fields used to produce reads past the end
# of attacker-controlled buffers before the macOS UI even exposed import paths.
PARSER="${TMPDIR:-/tmp}/key84_parser_safety_test"
c++ "${SAN_FLAGS[@]}" -o "$PARSER" parser_safety_test.cpp $ENGINE_SRC
env "${SAN_ENV[@]}" "$PARSER"

# Invariants of the macOS send layer (source-level — nothing here can call
# CGEvent, and the properties they guard only fail under load in a real app).
bash ../../platform/macos/tests/send_invariants_test.sh

# Privacy / supply-chain invariants that can be checked on Linux as source.
bash ../../platform/macos/tests/security_invariants_test.sh
bash ../../platform/macos/tests/pre_release_final_invariants_test.sh
