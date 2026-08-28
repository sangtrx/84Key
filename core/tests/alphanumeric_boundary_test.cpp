// Regression gate for alphanumeric tokens in the hardened engine overlay.
//
// Telex/Simple-Telex use letters as modifier keys, so an ASCII digit is a word
// boundary for English detection. VNI is the opposite: digits 1-9 ARE the tone
// and vowel-modifier keys, so the overlay must leave VNI behavior untouched.

#include <cstdio>
#include <string>
#include <cstdint>

#include "../engine/Engine.h"
#include "../engine/EnglishDetect.h"

using namespace std;
extern Uint16 keyCodeToCharacter(const Uint32& keyCode);

int vLanguage = 1, vInputType = 0, vFreeMark = 0, vCodeTable = 0, vSwitchKeyStatus = 0;
int vCheckSpelling = 1, vUseModernOrthography = 1, vQuickTelex = 0, vRestoreIfWrongSpelling = 0;
int vFixRecommendBrowser = 0, vUseMacro = 0, vUseMacroInEnglishMode = 0, vAutoCapsMacro = 0;
int vUseSmartSwitchKey = 0, vUpperCaseFirstChar = 0, vTempOffSpelling = 0, vAllowConsonantZFWJ = 0;
int vQuickStartConsonant = 0, vQuickEndConsonant = 0, vRememberCode = 0, vOtherLanguage = 0;
int vTempOffOpenKey = 0, vAutoDetectEnglish = 1;

static int keyFor(char c) {
    switch (c) {
        case 'a': return KEY_A; case 'b': return KEY_B; case 'c': return KEY_C; case 'd': return KEY_D;
        case 'e': return KEY_E; case 'f': return KEY_F; case 'g': return KEY_G; case 'h': return KEY_H;
        case 'i': return KEY_I; case 'j': return KEY_J; case 'k': return KEY_K; case 'l': return KEY_L;
        case 'm': return KEY_M; case 'n': return KEY_N; case 'o': return KEY_O; case 'p': return KEY_P;
        case 'q': return KEY_Q; case 'r': return KEY_R; case 's': return KEY_S; case 't': return KEY_T;
        case 'u': return KEY_U; case 'v': return KEY_V; case 'w': return KEY_W; case 'x': return KEY_X;
        case 'y': return KEY_Y; case 'z': return KEY_Z;
        case '0': return KEY_0; case '1': return KEY_1; case '2': return KEY_2; case '3': return KEY_3;
        case '4': return KEY_4; case '5': return KEY_5; case '6': return KEY_6; case '7': return KEY_7;
        case '8': return KEY_8; case '9': return KEY_9; case ' ': return KEY_SPACE;
        default: return -1;
    }
}

static void appendUtf8(string& out, uint32_t cp) {
    if (cp < 0x80) out.push_back((char)cp);
    else if (cp < 0x800) {
        out.push_back((char)(0xC0 | (cp >> 6)));
        out.push_back((char)(0x80 | (cp & 0x3F)));
    } else {
        out.push_back((char)(0xE0 | (cp >> 12)));
        out.push_back((char)(0x80 | ((cp >> 6) & 0x3F)));
        out.push_back((char)(0x80 | (cp & 0x3F)));
    }
}

static string type(const string& keys) {
    vKeyHookState* st = (vKeyHookState*)vKeyInit();
    string visible;
    for (char c : keys) {
        int key = keyFor(c);
        if (key < 0) continue;
        vKeyHandleEvent(vKeyEvent::Keyboard, vKeyEventState::KeyDown,
                        (Uint16)key, 0, false);

        if (st->code == vDoNothing) {
            visible.push_back(c);
            continue;
        }
        if (st->code != vWillProcess && st->code != vRestore &&
            st->code != vRestoreAndStartNewSession) {
            continue;
        }

        for (int i = 0; i < st->backspaceCount && !visible.empty(); i++)
            visible.pop_back();
        for (int i = (int)st->newCharCount - 1; i >= 0; i--) {
            Uint32 raw = st->charData[i];
            Uint32 cp = (raw & PURE_CHARACTER_MASK) ? (raw & CHAR_MASK)
                        : (!(raw & CHAR_CODE_MASK) ? keyCodeToCharacter(raw)
                                                   : (raw & CHAR_MASK));
            appendUtf8(visible, cp);
        }
        if (st->code == vRestore || st->code == vRestoreAndStartNewSession)
            visible.push_back(c);

        // Mirror SendNewCharString(): this host action happens after the payload
        // is captured, so it is safe to reset now and is required before another
        // digit in tokens such as sha256/h264.
        if (st->code == vRestoreAndStartNewSession)
            startNewSession();
    }
    return visible;
}

static string slurp(const char* path) {
    FILE* f = fopen(path, "rb");
    if (!f) return {};
    string out; char buf[65536]; size_t n;
    while ((n = fread(buf, 1, sizeof buf, f)) > 0) out.append(buf, n);
    fclose(f);
    return out;
}

static int fails = 0;
static void expect(const char* id, const char* keys, const char* want) {
    string got = type(keys);
    bool ok = got == want;
    printf("  [%s] %-10s %s -> %s (want %s)\n",
           ok ? "PASS" : "FAIL", id, keys, got.c_str(), want);
    if (!ok) fails++;
}

int main() {
    string eng = slurp("../data/english_words.dat");
    string viet = slurp("../data/viet_telex.dat");
    if (eng.empty() || viet.empty()) {
        fprintf(stderr, "dictionary fixture missing\n");
        return 2;
    }
    initEnglishDict((const Byte*)eng.data(), (int)eng.size());
    initVietByTelexDict((const Byte*)viet.data(), (int)viet.size());

    puts("== Telex alphanumeric boundaries ==");
    vInputType = vTelex;
    vAutoDetectEnglish = 1;
    expect("compound1", "dashboard1", "dashboard1");
    expect("sha256",    "sha256",     "sha256");
    expect("utf8",      "utf8",       "utf8");
    expect("h264",      "h264",       "h264");
    expect("gpt5",      "gpt5",       "gpt5");
    expect("viet+digit", "thangs8",   "tháng8");

    puts("== Simple Telex alphanumeric boundary ==");
    vInputType = vSimpleTelex1;
    vAutoDetectEnglish = 1;
    expect("simple1", "dashboard1", "dashboard1");

    puts("== VNI digits remain modifier keys ==");
    vInputType = vVNI;
    vAutoDetectEnglish = 1; // engDetectEnabled() intentionally ignores VNI.
    expect("vni-tone", "a1",  "á");
    expect("vni-hat",  "a6",  "â");
    expect("vni-both", "a61", "ấ");

    printf("%s\n", fails ? "alphanumeric boundary gate FAILED" : "alphanumeric boundary gate PASS");
    return fails ? 1 : 0;
}
