#!/usr/bin/env bash
# ----------------------------------------------------
# DivBar Install Verification
# Version 1.0
# EXIT CODE 0 = PASSED
# EXIT CODE 1 = FAILED 1 or MORE TESTS
# ----------------------------------------------------

set -u

if [ "${EUID:-$(id -u)}" -eq 0 ]; then    
    echo "Error: Do NOT run as root." >&2
    echo "This is a user-level tool." >&2
    exit 1
fi

readonly APP_NAME="divbar"
readonly BIN_PATH="$HOME/.local/bin/$APP_NAME"
readonly DATA_DIR="$HOME/.local/share/$APP_NAME"
readonly ASSETS_DIR="$DATA_DIR/assets"
readonly DESKTOP_FILE="$HOME/.local/share/applications/$APP_NAME.desktop"

if [ -t 1 ]; then
    readonly GREEN=$'\e[0;32m'
    readonly RED=$'\e[0;31m'
    readonly BOLD=$'\e[1m'
    readonly RESET=$'\e[0m'
else
    readonly GREEN=""
    readonly RED=""
    readonly BOLD=""
    readonly RESET=""
fi

PASSED=0
FAILED=0

pass() {
    echo " ${GREEN}✓${RESET} $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo " ${RED}x${RESET} $1"
    FAILED=$((FAILED + 1))
}

echo "${BOLD}DivBar - Install Verification${RESET}"
echo ""

if [ -f "$BIN_PATH" ]; then
    if [ -x "$BIN_PATH" ]; then
        pass "Executable installed and runnable ($BIN_PATH)"
    else
        fail "Executable found but not marked executable: $BIN_PATH"
    fi
else
    fail "Executable not found: $BIN_PATH"
fi

if [ -d "$ASSETS_DIR/vertical" ] && [ -d "$ASSETS_DIR/horizontal" ]; then
    V_COUNT=$(find "$ASSETS_DIR/vertical" -type f 2>/dev/null | wc -l)
    H_COUNT=$(find "$ASSETS_DIR/horizontal" -type f 2>/dev/null | wc -l)
    if [ "$V_COUNT" -gt 0 ] && [ "$H_COUNT" -gt 0 ]; then
        pass "Assets installed ($V_COUNT vertical, $H_COUNT horizontal)"
    else
        fail "Asset directories exist but are empty"
    fi
else
    fail "Asset directories missing: $ASSETS_DIR/{vertical,horizontal}"
fi

if [ -f "$DESKTOP_FILE" ]; then
    if grep -q "^Exec=$BIN_PATH$" "$DESKTOP_FILE"; then
        pass "Application menu entry installed"
    else
        fail "Desktop entry exists but Exec path is wrong: $DESKTOP_FILE"
    fi
else
    fail "Desktop entry not found: $DESKTOP_FILE"
fi

if command -v zenity &>/dev/null; then
    pass "zenity available"
elif command -v kdialog &>/dev/null; then
    pass "kdialog available"
else 
    fail "Missing zenity/kdialog"
fi

echo ""
echo "${BOLD}----------------------------------------${RESET}"
echo " Passed: ${GREEN}$PASSED${RESET}"
if [ "$FAILED" -gt 0 ]; then
    echo "FAILED: ${RED}$FAILED${RESET}"
    echo ""
    echo "${RED}${BOLD}Install verification failed.${RESET}"
    exit 1
fi
echo ""
echo "${GREEN}${BOLD}Install verified. Launch DivBar from your application menu.${RESET}"
exit 0


