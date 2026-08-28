// Security regression tests for binary parsers inherited from OpenKey.
//
// The parsers accept serialized data and historically trusted record lengths.
// These cases deliberately truncate every variable-length field. Run under
// ASan/UBSan so any future cursor regression is caught as an OOB access.

#include <cstdio>
#include <string>
#include <vector>

#include "../engine/Engine.h"
#include "../engine/Macro.h"
#include "../engine/SmartSwitchKey.h"

using namespace std;

// Host option globals required by the linked OpenKey engine objects.
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

static int failures = 0;

static void expect(bool condition, const char* name) {
    if (condition) {
        std::printf("  [PASS] %s\n", name);
    } else {
        std::printf("  [FAIL] %s\n", name);
        failures++;
    }
}

static bool macroTableEmpty() {
    vector<vector<Uint32>> keys;
    vector<string> texts;
    vector<string> contents;
    getAllMacro(keys, texts, contents);
    return keys.empty() && texts.empty() && contents.empty();
}

int main() {
    std::printf("== binary parser safety ==\n");

    // Macro record says text is 3 bytes but omits the following Uint16 content
    // length. The old parser memcpy'd two bytes past the allocation here.
    const Byte macroMissingContentLength[] = {1, 0, 3, 'a', 'b', 'c'};
    initMacroMap(macroMissingContentLength, sizeof(macroMissingContentLength));
    expect(macroTableEmpty(), "macro parser rejects missing content length");

    // Macro record declares 16 content bytes but provides none.
    const Byte macroTruncatedContent[] = {1, 0, 1, 'a', 16, 0};
    initMacroMap(macroTruncatedContent, sizeof(macroTruncatedContent));
    expect(macroTableEmpty(), "macro parser rejects truncated content");

    // A declared text field that runs past the input must fail before string
    // construction touches bytes outside the allocation.
    const Byte macroTruncatedName[] = {1, 0, 8, 'a'};
    initMacroMap(macroTruncatedName, sizeof(macroTruncatedName));
    expect(macroTableEmpty(), "macro parser rejects truncated name");

    initMacroMap(nullptr, 0);
    expect(macroTableEmpty(), "macro parser accepts empty input safely");

    // Smart-switch record has a complete bundle id but no trailing value byte.
    // The old parser read pData[cursor++] one byte beyond the allocation.
    const Byte smartMissingValue[] = {1, 0, 3, 'a', 'b', 'c'};
    initSmartSwitchKey(smartMissingValue, sizeof(smartMissingValue));
    expect(getAppInputMethodStatus("abc", 7) == -1,
           "smart-switch parser rejects missing value");

    // Declared bundle id length exceeds the remaining input.
    const Byte smartTruncatedBundle[] = {1, 0, 8, 'a'};
    initSmartSwitchKey(smartTruncatedBundle, sizeof(smartTruncatedBundle));
    expect(getAppInputMethodStatus("a", 7) == -1,
           "smart-switch parser rejects truncated bundle id");

    initSmartSwitchKey(nullptr, 0);
    expect(getAppInputMethodStatus("fresh", 7) == -1,
           "smart-switch parser accepts empty input safely");

    std::printf("\n%d parser-safety failure(s)\n", failures);
    return failures == 0 ? 0 : 1;
}
