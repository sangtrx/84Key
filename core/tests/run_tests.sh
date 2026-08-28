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
# host-decode bugs the engine harness cannot).
SIM="${TMPDIR:-/tmp}/key84_typing_sim"
c++ -std=c++14 -O2 -o "$SIM" typing_sim_test.cpp $ENGINE_SRC
"$SIM"

# Security regression coverage for serialized OpenKey parsers. Sanitizers are
# intentional here: malformed length fields used to produce reads past the end
# of attacker-controlled buffers before the macOS UI even exposed import paths.
PARSER="${TMPDIR:-/tmp}/key84_parser_safety_test"
c++ -std=c++14 -O1 -g -fno-omit-frame-pointer \
    -fsanitize=address,undefined \
    -o "$PARSER" parser_safety_test.cpp $ENGINE_SRC
ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=halt_on_error=1 "$PARSER"

# Invariants of the macOS send layer (source-level — nothing here can call
# CGEvent, and the properties they guard only fail under load in a real app).
bash ../../platform/macos/tests/send_invariants_test.sh

# Privacy / supply-chain invariants that can be checked on Linux as source.
bash ../../platform/macos/tests/security_invariants_test.sh
