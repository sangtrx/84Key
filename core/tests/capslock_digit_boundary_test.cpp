// Regression gate for number-row behavior while Caps Lock is enabled.
//
// macOS reports Caps Lock as capsStatus=2. Caps Lock uppercases letters but does
// not shift the number row, so a Telex digit must remain a literal token boundary
// just like capsStatus=0. By contrast, VNI uses number-row keys as modifiers and
// must never take the Telex boundary overlay.

#include <cstdio>
#include <string>

#include "../engine/Engine.h"
#include "../engine/EnglishDetect.h"

using namespace std;

// Host option globals required by the engine.
int vLanguage = 1;
int vInputType = 0;
int vFreeMark = 0;
int vCodeTable = 0;
int vSwitchKeyStatus = 0;
int vCheckSpelling = 1;
int vUseModernOrthography = 1;
int vQuickTelex = 0;
int vRestoreIfWrongSpelling = 0;
int vFixRecommendBrowser = 0;
int vUseMacro = 0;
int vUseMacroInEnglishMode = 0;
int vAutoCapsMacro = 0;
int vUseSmartSwitchKey = 0;
int vUpperCaseFirstChar = 0;
int vTempOffSpelling = 0;
int vAllowConsonantZFWJ = 0;
int vQuickStartConsonant = 0;
int vQuickEndConsonant = 0;
int vRememberCode = 0;
int vOtherLanguage = 1;
int vTempOffOpenKey = 0;
int vAutoDetectEnglish = 0;

static int charToKey(char c) {
    switch (c) {
        case 'a': return KEY_A; case 'b': return KEY_B; case 'c': return KEY_C;
        case 'd': return KEY_D; case 'e': return KEY_E; case 'f': return KEY_F;
        case 'g': return KEY_G; case 'h': return KEY_H; case 'i': return KEY_I;
        case 'j': return KEY_J; case 'k': return KEY_K; case 'l': return KEY_L;
        case 'm': return KEY_M; case 'n': return KEY_N; case 'o': return KEY_O;
        case 'p': return KEY_P; case 'q': return KEY_Q; case 'r': return KEY_R;
        case 's': return KEY_S; case 't': return KEY_T; case 'u': return KEY_U;
        case 'v': return KEY_V; case 'w': return KEY_W; case 'x': return KEY_X;
        case 'y': return KEY_Y; case 'z': return KEY_Z;
        default: return -1;
    }
}

static string readFile(const char* path) {
    string data;
    FILE* f = fopen(path, "rb");
    if (!f) return data;
    char buf[65536];
    size_t n;
    while ((n = fread(buf, 1, sizeof(buf), f)) > 0)
        data.append(buf, n);
    fclose(f);
    return data;
}

static void key(Uint16 code, Uint8 capsStatus) {
    vKeyHandleEvent(vKeyEvent::Keyboard, vKeyEventState::KeyDown,
                    code, capsStatus, false);
}

int main() {
    const string eng = readFile("../data/english_words.dat");
    const string viet = readFile("../data/viet_telex.dat");
    if (eng.empty() || viet.empty()) {
        fprintf(stderr, "FAIL: dictionaries missing\n");
        return 2;
    }
    initEnglishDict((const Byte*)eng.data(), (int)eng.size());
    initVietByTelexDict((const Byte*)viet.data(), (int)viet.size());
    auto* st = (vKeyHookState*)vKeyInit();

    // Telex + English detection: dashboard carries a temporary Telex transform
    // until the token boundary. Caps Lock (2) must not make the following `1`
    // look like an in-word key; the boundary must restore the English compound.
    vInputType = vTelex;
    vAutoDetectEnglish = 1;
    for (char c : string("dashboard"))
        key((Uint16)charToKey(c), 2);
    key(KEY_1, 2);
    bool telexOK = st->code == vRestoreAndStartNewSession &&
                   st->backspaceCount > 0 && st->newCharCount > 0;
    printf("  [%s] Caps Lock + Telex: dashboard1 ends/restores before digit\n",
           telexOK ? "PASS" : "FAIL");

    // VNI must remain untouched by the overlay even with Caps Lock set. `a6`
    // creates â and the following `1` applies sắc; neither numeric key may be
    // reported as a restore-and-start-new-session boundary.
    vKeyInit();
    vInputType = vVNI;
    vAutoDetectEnglish = 1;
    key(KEY_A, 2);
    key(KEY_6, 2);
    bool vniSixOK = st->code != vRestoreAndStartNewSession;
    key(KEY_1, 2);
    bool vniOneOK = st->code != vRestoreAndStartNewSession;
    bool vniOK = vniSixOK && vniOneOK;
    printf("  [%s] Caps Lock + VNI: 6/1 remain numeric modifiers\n",
           vniOK ? "PASS" : "FAIL");

    return (telexOK && vniOK) ? 0 : 1;
}
