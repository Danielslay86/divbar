#!/usr/bin/env bash
# -----------------------------------------------------------
#                  TEST SUITE FOR DIVBAR
# - REQUIREMENTS:
# -- divbar.sh, install.sh, verify.sh in the same directory
# - USAGES:
# -- bash test_suite.sh      [Run all tests]
# -- bash test_suite.sh -v   [Verbose Output]
# -----------------------------------------------------------
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

VERBOSE=false
[[ "${1:-}" = "-v" ]] && VERBOSE=true

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
TOTAL_COUNT=0
FAILED_TESTS=()

assert() {
    local description="$1"
    local condition="$2"
    ((TOTAL_COUNT++))

    if eval "$condition"; then
        ((PASS_COUNT++))
        if $VERBOSE; then
            echo -e "${GREEN}✓${RESET} $description"
        fi
    else
        ((FAIL_COUNT++))
        FAILED_TESTS+=("$CURRENT_SECTION > $description")
        echo -e "${RED}x FAIL:${RESET} $description"
        if $VERBOSE; then
            echo -e "${RED}Condition: $condition${RESET}"
        fi
    fi
}

assert_file_exists()        { assert "$1" "[ -f '$2' ]"; }
assert_file_missing()       { assert "$1" "[ ! -f '$2' ]"; }
assert_dir_exists()         { assert "$1" "[ -d '$2' ]"; }
assert_dir_missing()        { assert "$1" "[ ! -d '$2' ]"; }
assert_file_contains()      { assert "$1" "grep -q '$3' '$2'"; }
assert_file_not_contains()  { assert "$1" "! grep -q '$3' '$2'"; }
assert_executable()         { assert "$1 is executable" "[ -x '$2' ]"; }
assert_equals() {
    local desc="$1" expected="$2" actual="$3"
    assert "$desc" "[ '$actual' = '$expected' ]"
}

skip_test() {
    ((TOTAL_COUNT++))
    ((SKIP_COUNT++))
    echo -e "${YELLOW}⊘ SKIP:${RESET} $1"
}

CURRENT_SECTION=""
section() {
    CURRENT_SECTION="$1"
    echo ""
    echo -e "${CYAN}${BOLD}--- $1 ---${RESET}"
}

SANDBOX="$(mktemp -d /tmp/divbar-test.XXXXXX)"
FAKE_HOME="$SANDBOX/fakehome"
PROJECT_DIR="$SANDBOX/project"
MOCK_BIN="$SANDBOX/mock-bin"
REAL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="divbar"

setup_sandbox() {
    rm -rf "$SANDBOX"
    mkdir -p "$FAKE_HOME/.local/bin"
    mkdir -p "$FAKE_HOME/.local/share/applications"
    mkdir -p "$FAKE_HOME/.local/share/icons/hicolor/128x128/apps"
    mkdir -p "$PROJECT_DIR/assets/vertical"
    mkdir -p "$PROJECT_DIR/assets/horizontal"
    mkdir -p "$MOCK_BIN"

    echo "PNG_FAKE_DATA" > "$PROJECT_DIR/assets/vertical/white.png"
    echo "PNG_FAKE_DATA" > "$PROJECT_DIR/assets/vertical/black.png"
    echo "SVG_FAKE_DATA" > "$PROJECT_DIR/assets/vertical/blue.svg"
    echo "PNG_FAKE_DATA" > "$PROJECT_DIR/assets/horizontal/white.png"
    echo "PNG_FAKE_DATA" > "$PROJECT_DIR/assets/horizontal/red.png"

    cp "$REAL_SCRIPT_DIR/install.sh" "$PROJECT_DIR/install.sh"
    cp "$REAL_SCRIPT_DIR/divbar.sh" "$PROJECT_DIR/divbar.sh"
    cp "$REAL_SCRIPT_DIR/verify.sh" "$PROJECT_DIR/verify.sh" 2>/dev/null || true

    cat > "$MOCK_BIN/kbuildsycoca5" <<'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_BIN/kbuildsycoca5"
    cp "$MOCK_BIN/kbuildsycoca5" "$MOCK_BIN/kbuildsycoca6"

    cat > "$MOCK_BIN/notify-send" <<'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_BIN/notify-send"

    cat > "$MOCK_BIN/zenity" <<'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$MOCK_BIN/zenity"

    cat > "$MOCK_BIN/kdialog" <<'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$MOCK_BIN/kdialog"
}

cleanup_sandbox() { rm -rf "$SANDBOX"; }

create_dialog_mock() {
    local binary="$1"
    shift

    local response_file="$SANDBOX/${binary}_responses"
    local counter_file="$SANDBOX/${binary}_counter"
    local log_file="$SANDBOX/${binary}_log"

    echo "0" > "$counter_file"
    : > "$log_file"
    : > "$response_file"

    for resp in "$@"; do
        echo "$resp" >> "$response_file"
    done

    cat > "$MOCK_BIN/$binary" <<'MOCK'
#!/bin/bash
TOOL_NAME="$(basename "$0")"
SANDBOX_DIR="$(dirname "$(dirname "$0")")"
COUNTER_FILE="$SANDBOX_DIR/${TOOL_NAME}_counter"
RESPONSE_FILE="$SANDBOX_DIR/${TOOL_NAME}_responses"
LOG_FILE="$SANDBOX_DIR/${TOOL_NAME}_log"

echo "$*" >> "$LOG_FILE"

IDX=$(cat "$COUNTER_FILE")
echo $((IDX+1)) > "$COUNTER_FILE"

RESPONSE=$(sed -n "$((IDX+1))p" "$RESPONSE_FILE")

if [ "$RESPONSE" = "__CANCEL__" ] || [ "$RESPONSE" = "__NO__" ]; then
    exit 1
elif [ "$RESPONSE" = "__YES__" ]; then
    exit 0
elif [ -z "$RESPONSE" ]; then
    exit 1
else
    echo "$RESPONSE" | sed 's/__NL__/\n/g'
    exit 0
fi
MOCK
    chmod +x "$MOCK_BIN/$binary"
}

create_zenity_mock() { create_dialog_mock "zenity" "$@"; }
create_kdialog_mock() { create_dialog_mock "kdialog" "$@"; }

patch_root_guard() {
    local file="$1"
    if grep -q 'EUID:-\$(id -u)' "$file" 2>/dev/null; then
        sed -i 's|\${EUID:-\$(id -u)}|1000|g' "$file"
    fi
}

run_installer() {
    (
        export HOME="$FAKE_HOME"
        export PATH="$MOCK_BIN:/usr/bin:/bin:$PATH"
        unset KDE_FULL_SESSION 2>/dev/null || true
        export XDG_CURRENT_DESKTOP="GNOME"
        patch_root_guard "$PROJECT_DIR/install.sh"
        cd "$PROJECT_DIR"
        bash install.sh "$@" 2>&1
    )
}

run_installer_kde() {
    (
        export HOME="$FAKE_HOME"
        export PATH="$MOCK_BIN:/usr/bin:/bin:$PATH"
        export KDE_FULL_SESSION="true"
        export XDG_CURRENT_DESKTOP="KDE"
        patch_root_guard "$PROJECT_DIR/install.sh"
        cd "$PROJECT_DIR"
        bash install.sh "$@" 2>&1
    )
}

run_manager() {
    (
        export HOME="$FAKE_HOME"
        export PATH="$MOCK_BIN:/usr/bin:/bin:$PATH"
        unset KDE_FULL_SESSION 2>/dev/null || true
        export XDG_CURRENT_DESKTOP="GNOME"
        bash "$FAKE_HOME/.local/bin/$APP_NAME" "$@" 2>&1
    )
}

run_manager_kde() {
    (
        export HOME="$FAKE_HOME"
        export PATH="$MOCK_BIN:/usr/bin:/bin:$PATH"
        export KDE_FULL_SESSION="true"
        export XDG_CURRENT_DESKTOP="KDE"
        bash "$FAKE_HOME/.local/bin/$APP_NAME" "$@" 2>&1
    )
}

# run_manager_de: used by section 10b for multi-DE integration testing.
# Only tests DEs where the requested backend matches what detect_backend
# will choose naturally — avoids needing hermetic mock isolation.
run_manager_de() {
    local de="$1"
    (
        export HOME="$FAKE_HOME"
        export PATH="$MOCK_BIN:/usr/bin:/bin:$PATH"
        if [ "$de" = "__unset__" ]; then
            unset XDG_CURRENT_DESKTOP 2>/dev/null || true
        else
            export XDG_CURRENT_DESKTOP="$de"
        fi
        unset KDE_FULL_SESSION 2>/dev/null || true
        bash "$FAKE_HOME/.local/bin/$APP_NAME" "$@" 2>&1
    )
}

run_verify() {
    (
        export HOME="$FAKE_HOME"
        export PATH="$MOCK_BIN:/usr/bin:/bin:$PATH"
        bash "$PROJECT_DIR/verify.sh" 2>&1
    )
}

extract_detect_backend() {
    awk '/^detect_backend\(\)/,/^}/' "$REAL_SCRIPT_DIR/divbar.sh" \
        > "$SANDBOX/detect_backend_extracted.sh"
}

test_detect_backend() {
    local xdg="$1" kde_session="$2" has_zenity="$3" has_kdialog="$4"
    local expected="$5" description="$6"

    setup_sandbox
    extract_detect_backend

    local result
    result=$(
        export PATH="$MOCK_BIN:/usr/bin:/bin"
        if [ "$xdg" = "__unset__" ]; then
            unset XDG_CURRENT_DESKTOP 2>/dev/null || true
        else
            export XDG_CURRENT_DESKTOP="$xdg"
        fi

        if [ "$kde_session" = "true" ]; then
            export KDE_FULL_SESSION="true"
        else
            unset KDE_FULL_SESSION 2>/dev/null || true
        fi

        [ "$has_zenity" = "no" ] && rm -f "$MOCK_BIN/zenity"
        [ "$has_kdialog" = "no" ] && rm -f "$MOCK_BIN/kdialog"

        export PATH="$MOCK_BIN"
        
        source "$SANDBOX/detect_backend_extracted.sh"
        detect_backend
    )

    assert_equals "$description" "$expected" "$result"
}

extract_sanitize_name() {
    awk '/^sanitize_name\(\)/,/^}/' "$REAL_SCRIPT_DIR/divbar.sh" \
        > "$SANDBOX/sanitize_extracted.sh"
}

test_sanitize_name() {
    local input="$1" expected="$2" description="$3"
    extract_sanitize_name
    local result
    result=$(source "$SANDBOX/sanitize_extracted.sh"; sanitize_name "$input")

    assert_equals "$description" "$expected" "$result"
}

trap cleanup_sandbox EXIT

section "1. Syntax & Static Analysis"

setup_sandbox

assert "install.sh passes bash -n" "bash -n '$PROJECT_DIR/install.sh'"
assert "divbar.sh passes bash -n" "bash -n '$PROJECT_DIR/divbar.sh'"

if [ -f "$PROJECT_DIR/verify.sh" ]; then
    assert "verify.sh passes bash -n" "bash -n '$PROJECT_DIR/verify.sh'"
fi

assert "install.sh has correct shebang" \
    "head -1 '$PROJECT_DIR/install.sh' | grep -q '^#!/usr/bin/env bash\$'"
assert "divbar.sh has correct shebang" \
    "head -1 '$PROJECT_DIR/divbar.sh' | grep -q '^#!/usr/bin/env bash\$'"
assert "install.sh uses set -euo pipefail" \
    "grep -q 'set -euo pipefail' '$PROJECT_DIR/install.sh'"
assert "divbar.sh uses set -u" \
    "grep -q 'set -u' '$PROJECT_DIR/divbar.sh'"
assert "divbar.sh does NOT use set -e" \
    "! grep -qE '^set -[eu]*e' '$PROJECT_DIR/divbar.sh'"
assert "divbar.sh contains __INSTALLER_PATCH__ marker" \
    "grep -q '# __INSTALLER_PATCH__' '$PROJECT_DIR/divbar.sh'"
assert "install.sh references __INSTALLER_PATCH__" \
    "grep -q '__INSTALLER_PATCH__' '$PROJECT_DIR/install.sh'"
assert "divbar.sh uses POSIX = not ==" \
    "! grep -qE '\\[ \"\\\$[A-Z_]+\" == ' '$PROJECT_DIR/divbar.sh'"
assert "No KDE-specific references in .desktop Name" \
    "! grep -qi 'name=.*kde' '$PROJECT_DIR/install.sh'"

section "2. Security"

setup_sandbox

assert "install.sh root guard present" \
    "grep -q 'EUID.*-eq.*0\\|EUID.*==.*0\\|\\[ \"\\\$EUID\" = \"0\"' '$PROJECT_DIR/install.sh'"

assert "verify.sh root guard present" \
    "grep -q 'EUID.*-eq.*0\\|EUID.*==.*0\\|\\[ \"\\\$EUID\" = \"0\"' '$PROJECT_DIR/verify.sh'"

assert "divbar.sh root guard present" \
    "grep -q 'EUID.*-eq.*0\\|EUID.*==.*0\\|\\[ \"\\\$EUID\" = \"0\"' '$PROJECT_DIR/divbar.sh'"

assert "Root guard error mentions root" \
    "grep -qi 'root' '$PROJECT_DIR/install.sh'"
assert "install.sh validates DATA_DIR path" \
    "grep -q 'DATA_DIR.*HOME/.local/share' '$PROJECT_DIR/install.sh'"

RMCOUNT="$(grep -c 'rm -rf' "$PROJECT_DIR/install.sh")"
assert "install.sh has exactly one rm -rf" "[ '$RMCOUNT' -eq 1 ]"

assert "divbar validates file extensions" \
    "grep -q 'png|svg|jpg|jpeg|ico' '$PROJECT_DIR/divbar.sh'"
assert "divbar has sanitize_name function" \
    "grep -q 'sanitize_name()' '$PROJECT_DIR/divbar.sh'"
assert "No eval usage in installer" \
    "! grep -qE '^\\s*eval ' '$PROJECT_DIR/install.sh'"
assert "No eval usage in divbar" \
    "! grep -qE '^\\s*eval ' '$PROJECT_DIR/divbar.sh'"
assert "Generated .desktop uses safe /usr/bin/true" \
    "grep -q 'Exec=/usr/bin/true' '$PROJECT_DIR/divbar.sh'"
assert "Icon files get 644 permissions" \
    "grep -q 'chmod 644' '$PROJECT_DIR/divbar.sh'"
assert "No hardcoded /tmp paths in installer" \
    "! grep -q '\"/tmp' '$PROJECT_DIR/install.sh'"

section "3. DE Agnosticism — Static"

setup_sandbox

assert "divbar contains detect_backend function" "grep -q 'detect_backend()' '$PROJECT_DIR/divbar.sh'"
assert "divbar checks XDG_CURRENT_DESKTOP" "grep -q 'XDG_CURRENT_DESKTOP' '$PROJECT_DIR/divbar.sh'"
assert "divbar checks KDE_FULL_SESSION" "grep -q 'KDE_FULL_SESSION' '$PROJECT_DIR/divbar.sh'"
assert "divbar has dialog_menu wrapper" "grep -q 'dialog_menu()' '$PROJECT_DIR/divbar.sh'"
assert "divbar has dialog_file wrapper" "grep -q 'dialog_file()' '$PROJECT_DIR/divbar.sh'"
assert "divbar has dialog_info wrapper" "grep -q 'dialog_info()' '$PROJECT_DIR/divbar.sh'"
assert "divbar has dialog_error wrapper" "grep -q 'dialog_error()' '$PROJECT_DIR/divbar.sh'"
assert "divbar has dialog_confirm wrapper" "grep -q 'dialog_confirm()' '$PROJECT_DIR/divbar.sh'"
assert "divbar has dialog_checklist wrapper" "grep -q 'dialog_checklist()' '$PROJECT_DIR/divbar.sh'"
assert "divbar has parse_desktop_name helper" "grep -q 'parse_desktop_name()' '$PROJECT_DIR/divbar.sh'"
assert "divbar references both zenity and kdialog" \
    "grep -q 'zenity' '$PROJECT_DIR/divbar.sh' && grep -q 'kdialog' '$PROJECT_DIR/divbar.sh'"
assert "refresh_cache only runs on kdialog backend" \
    "awk '/^refresh_cache\\(\\)/,/^}/' '$PROJECT_DIR/divbar.sh' | grep -q 'DIALOG_BACKEND.*kdialog'"
assert "Installer .desktop Name is DE-agnostic" \
    "! grep -qi 'name=.*kde\\|name=.*gnome\\|name=.*xfce' '$PROJECT_DIR/install.sh'"
assert "Icon prefix is div- not kde-sep- or sep-" \
    "! grep -q '\"kde-sep-' '$PROJECT_DIR/divbar.sh' && grep -q '\"div-' '$PROJECT_DIR/divbar.sh'"
assert "No X-KDE-StartupNotify in div .desktop" \
    "! grep -q 'X-KDE-StartupNotify' '$PROJECT_DIR/divbar.sh'"
assert "App name is divbar" "grep -q 'APP_NAME=\"divbar\"' '$PROJECT_DIR/divbar.sh'"

section "4. Backend Detection — DE Matrix"

test_detect_backend "KDE"           "true"  "yes" "yes" "kdialog" "KDE + both tools -> kdialog"
test_detect_backend "KDE"           "true"  "yes" "no"  "zenity"  "KDE + zenity only -> zenity"
test_detect_backend "KDE"           "true"  "no"  "yes" "kdialog" "KDE + kdialog only -> kdialog"
test_detect_backend "KDE"           "true"  "no"  "no"  "none"    "KDE + no tools -> none"
test_detect_backend "__unset__"     "true"  "yes" "yes" "kdialog" "KDE_FULL_SESSION only + both -> kdialog"
test_detect_backend "KDE"           ""      "yes" "yes" "kdialog" "XDG=KDE without KDE_FULL_SESSION -> kdialog"
test_detect_backend "KDE:KDE"       "true"  "yes" "yes" "kdialog" "XDG=KDE:KDE + both -> kdialog"

test_detect_backend "GNOME"         ""      "yes" "yes" "zenity"  "GNOME + both tools -> zenity"
test_detect_backend "GNOME"         ""      "yes" "no"  "zenity"  "GNOME + zenity only -> zenity"
test_detect_backend "GNOME"         ""      "no"  "yes" "kdialog" "GNOME + kdialog only -> kdialog fallback"
test_detect_backend "GNOME"         ""      "no"  "no"  "none"    "GNOME + no tools -> none"
test_detect_backend "ubuntu:GNOME"  ""      "yes" "no"  "zenity"  "ubuntu:GNOME + zenity -> zenity"

test_detect_backend "XFCE"          ""      "yes" "yes" "zenity"  "XFCE + both -> zenity"
test_detect_backend "XFCE"          ""      "yes" "no"  "zenity"  "XFCE + zenity only -> zenity"
test_detect_backend "XFCE"          ""      "no"  "yes" "kdialog" "XFCE + kdialog only -> kdialog fallback"
test_detect_backend "XFCE"          ""      "no"  "no"  "none"    "XFCE + no tools -> none"

test_detect_backend "X-Cinnamon"    ""      "yes" "no"  "zenity"  "Cinnamon + zenity -> zenity"
test_detect_backend "X-Cinnamon"    ""      "no"  "yes" "kdialog" "Cinnamon + kdialog only -> kdialog fallback"
test_detect_backend "MATE"          ""      "yes" "no"  "zenity"  "MATE + zenity -> zenity"
test_detect_backend "MATE"          ""      "no"  "yes" "kdialog" "MATE + kdialog only -> kdialog fallback"
test_detect_backend "LXQt"          ""      "yes" "yes" "zenity"  "LXQt + both -> zenity"
test_detect_backend "LXQt"          ""      "no"  "yes" "kdialog" "LXQt + kdialog only -> kdialog fallback"
test_detect_backend "Budgie:GNOME"  ""      "yes" "no"  "zenity"  "Budgie:GNOME + zenity -> zenity"
test_detect_backend "Pantheon"      ""      "yes" "no"  "zenity"  "Pantheon + zenity -> zenity"
test_detect_backend "sway"          ""      "yes" "no"  "zenity"  "Sway + zenity -> zenity"
test_detect_backend "sway"          ""      "no"  "yes" "kdialog" "Sway + kdialog only -> kdialog fallback"
test_detect_backend "Hyprland"      ""      "yes" "no"  "zenity"  "Hyprland + zenity -> zenity"

test_detect_backend "__unset__"     ""      "yes" "no"  "zenity"  "No DE + zenity -> zenity"
test_detect_backend "__unset__"     ""      "no"  "yes" "kdialog" "No DE + kdialog only -> kdialog fallback"
test_detect_backend "__unset__"     ""      "yes" "yes" "zenity"  "No DE + both -> zenity"
test_detect_backend "__unset__"     ""      "no"  "no"  "none"    "No DE + no tools -> none"

test_detect_backend "LXDE"          ""      "yes" "no"  "zenity"  "LXDE + zenity -> zenity"
test_detect_backend "Deepin"        ""      "yes" "no"  "zenity"  "Deepin + zenity -> zenity"
test_detect_backend "ENLIGHTENMENT" ""      "yes" "no"  "zenity"  "Enlightenment + zenity -> zenity"

test_detect_backend "kde"           ""      "yes" "yes" "kdialog" "Lowercase kde + both -> kdialog"
test_detect_backend "plasma:KDE"    "true"  "yes" "yes" "kdialog" "plasma:KDE + both -> kdialog"

section "5. sanitize_name() Unit Tests"

setup_sandbox

test_sanitize_name "Hello World"          "hello-world"      "Lowercases and replaces spaces"
test_sanitize_name "Test@#\$%^&"          "test"             "Strips special chars"
test_sanitize_name "  trailing-dashes--"  "trailing-dashes"  "Trims and collapses hyphens"
test_sanitize_name "UPPERCASE"            "uppercase"        "All uppercase to lowercase"
test_sanitize_name "multiple   spaces"    "multiple-spaces"  "Multiple spaces to single hyphen"
test_sanitize_name "café-résumé"          "caf-rsum"         "Non-ASCII stripped, hyphens kept"
test_sanitize_name "!@#\$%"               ""                 "All-special-chars to empty"
test_sanitize_name "clean-name-123"       "clean-name-123"   "Already clean unchanged"
test_sanitize_name "a"                    "a"                "Single char preserved"
test_sanitize_name ""                     ""                 "Empty input to empty"
test_sanitize_name "     "                ""                 "Spaces-only trimmed"
test_sanitize_name "../../etc/passwd"     "etcpasswd"        "Path traversal sanitized"
test_sanitize_name "; rm -rf /"           "rm-rf"            "Command injection stripped"

section "6. Installer — Happy Path"

setup_sandbox
run_installer &>/dev/null
INSTALL_EXIT=$?
assert_equals "Installer exits 0" "0" "$INSTALL_EXIT"

assert_dir_exists "Assets dir created" "$FAKE_HOME/.local/share/$APP_NAME/assets"
assert_dir_exists "Vertical assets copied" "$FAKE_HOME/.local/share/$APP_NAME/assets/vertical"
assert_dir_exists "Horizontal assets copied" "$FAKE_HOME/.local/share/$APP_NAME/assets/horizontal"
assert_file_exists "white.png asset present" "$FAKE_HOME/.local/share/$APP_NAME/assets/vertical/white.png"
assert_file_exists "Executable installed" "$FAKE_HOME/.local/bin/$APP_NAME"
assert_executable "Installed executable" "$FAKE_HOME/.local/bin/$APP_NAME"
assert_file_exists ".desktop entry created" "$FAKE_HOME/.local/share/applications/$APP_NAME.desktop"

assert_file_contains ".desktop has Type=Application" \
    "$FAKE_HOME/.local/share/applications/$APP_NAME.desktop" "Type=Application"
assert_file_contains ".desktop has correct Name" \
    "$FAKE_HOME/.local/share/applications/$APP_NAME.desktop" "Name=DivBar"
assert_file_contains ".desktop has Exec path" \
    "$FAKE_HOME/.local/share/applications/$APP_NAME.desktop" "Exec=$FAKE_HOME/.local/bin/$APP_NAME"
assert_file_contains ".desktop has Terminal=false" \
    "$FAKE_HOME/.local/share/applications/$APP_NAME.desktop" "Terminal=false"
assert_file_contains ".desktop starts with [Desktop Entry]" \
    "$FAKE_HOME/.local/share/applications/$APP_NAME.desktop" '^\[Desktop Entry\]'

assert_file_contains "ASSETS_DIR patched" \
    "$FAKE_HOME/.local/bin/$APP_NAME" \
    "ASSETS_DIR=\"$FAKE_HOME/.local/share/$APP_NAME/assets\""
assert_file_contains "Patch marker preserved" \
    "$FAKE_HOME/.local/bin/$APP_NAME" "# __INSTALLER_PATCH__"

PATCH_COUNT=$(grep -c '__INSTALLER_PATCH__' "$FAKE_HOME/.local/bin/$APP_NAME")
assert_equals "Exactly one patch marker" "1" "$PATCH_COUNT"

section "7. Installer — Idempotency"

setup_sandbox
run_installer &>/dev/null
run_installer &>/dev/null
RE_INSTALL_EXIT=$?

assert_equals "Re-install exits 0" "0" "$RE_INSTALL_EXIT"
assert_file_exists "Executable still present" "$FAKE_HOME/.local/bin/$APP_NAME"
assert_file_contains "ASSETS_DIR still patched correctly" \
    "$FAKE_HOME/.local/bin/$APP_NAME" \
    "ASSETS_DIR=\"$FAKE_HOME/.local/share/$APP_NAME/assets\""

section "8. Installer — Error Cases"

setup_sandbox
rm -rf "$PROJECT_DIR/assets"
set +e
run_installer &>/dev/null
EXIT=$?
set -e
assert "Missing assets -> non-zero exit" "[ $EXIT -ne 0 ]"

ERR_OUT=$(run_installer 2>&1 || true)
echo "$ERR_OUT" > "$SANDBOX/err.log"
assert_file_contains "Error mentions assets" "$SANDBOX/err.log" "assets"

setup_sandbox
rm "$PROJECT_DIR/divbar.sh"
set +e
run_installer &>/dev/null
EXIT=$?
set -e
assert "Missing divbar.sh -> non-zero exit" "[ $EXIT -ne 0 ]"

ERR_OUT=$(run_installer 2>&1 || true)
echo "$ERR_OUT" > "$SANDBOX/err.log"
assert_file_contains "Error mentions divbar.sh" "$SANDBOX/err.log" "divbar.sh"

section "9. Manager — Add Div (zenity)"

setup_sandbox
run_installer &>/dev/null

create_zenity_mock "add" "vertical" "white.png" "__YES__"
run_manager &>/dev/null
EXIT=$?
assert_equals "Manager exits 0 on add" "0" "$EXIT"

assert_file_exists "div_1.desktop created" "$FAKE_HOME/.local/share/applications/div_1.desktop"

SEP="$FAKE_HOME/.local/share/applications/div_1.desktop"
assert_file_contains "Has Type=Application" "$SEP" "Type=Application"
assert_file_contains "Has Name" "$SEP" "^Name="
assert_file_contains "References vertical" "$SEP" "vertical"
assert_file_contains "Has Exec=/usr/bin/true" "$SEP" "Exec=/usr/bin/true"
assert_file_contains "Has StartupNotify=false" "$SEP" "StartupNotify=false"
assert_file_not_contains "No X-KDE-StartupNotify" "$SEP" "X-KDE-StartupNotify"

assert "Icon installed with -1 suffix (uniqueness fix)" \
    "[ -f '$FAKE_HOME/.local/share/icons/hicolor/128x128/apps/div-vertical-white-1.png' ]"

ICON="$FAKE_HOME/.local/share/icons/hicolor/128x128/apps/div-vertical-white-1.png"
if [ -f "$ICON" ]; then
    PERMS="$(stat -c '%a' "$ICON" 2>/dev/null || stat -f '%Lp' "$ICON" 2>/dev/null)"
    assert_equals "Icon has 644 permissions" "644" "$PERMS"
fi

section "10. Manager — Add Div (kdialog/KDE)"

setup_sandbox
run_installer &>/dev/null

create_kdialog_mock "add" "horizontal" "red.png" "__YES__"
run_manager_kde &>/dev/null
EXIT=$?
assert_equals "Manager exits 0 on add (KDE)" "0" "$EXIT"
assert_file_exists "div_1.desktop created (KDE)" "$FAKE_HOME/.local/share/applications/div_1.desktop"
assert_file_contains "References horizontal" \
    "$FAKE_HOME/.local/share/applications/div_1.desktop" "horizontal"

section "10b. Multi-DE Integration — Add Div"

# Only tests DEs where detect_backend chooses zenity naturally.
# These work because mock zenity is first in PATH.
for de_test in \
    "XFCE vertical white.png" \
    "X-Cinnamon horizontal red.png" \
    "MATE vertical white.png" \
    "Budgie:GNOME horizontal red.png" \
    "Pantheon vertical white.png" \
    "sway horizontal red.png" \
    "Hyprland vertical white.png" \
    "__unset__ vertical white.png" \
    "LXDE vertical white.png" \
    "Deepin horizontal red.png" \
    "ENLIGHTENMENT vertical white.png" \
    "ubuntu:GNOME vertical white.png"; do

    read -r de orient file <<< "$de_test"

    setup_sandbox
    run_installer &>/dev/null
    create_zenity_mock "add" "$orient" "$file" "__YES__"
    run_manager_de "$de" &>/dev/null
    assert_file_exists "$de: div_1 created" \
        "$FAKE_HOME/.local/share/applications/div_1.desktop"
done

section "10c. Custom Image — Valid"

setup_sandbox
run_installer &>/dev/null

mkdir -p "$FAKE_HOME/Pictures"
echo "CUSTOM_PNG" > "$FAKE_HOME/Pictures/my-divider.png"

create_zenity_mock "add" "vertical" "__custom__" "$FAKE_HOME/Pictures/my-divider.png" "__YES__"
run_manager &>/dev/null

assert_file_exists "Custom image: div_1 created" \
    "$FAKE_HOME/.local/share/applications/div_1.desktop"

SEP="$FAKE_HOME/.local/share/applications/div_1.desktop"
assert_file_contains "Custom image: Name includes my-divider" "$SEP" "my-divider"
assert_file_contains "Custom image: Icon path is absolute" "$SEP" "Icon=/"

assert "Custom image: icon filename has -1 suffix" \
    "[ -f '$FAKE_HOME/.local/share/icons/hicolor/128x128/apps/div-vertical-my-divider-1.png' ]"

section "10d. Custom Image — SVG"

setup_sandbox
run_installer &>/dev/null

mkdir -p "$FAKE_HOME/Pictures"
echo '<svg xmlns="http://www.w3.org/2000/svg"/>' > "$FAKE_HOME/Pictures/custom-wall.svg"

create_zenity_mock "add" "horizontal" "__custom__" "$FAKE_HOME/Pictures/custom-wall.svg" "__YES__"
run_manager &>/dev/null

assert_file_exists "Custom SVG: div_1 created" "$FAKE_HOME/.local/share/applications/div_1.desktop"
assert "Custom SVG: icon installed with -1 suffix" \
    "[ -f '$FAKE_HOME/.local/share/icons/hicolor/128x128/apps/div-horizontal-custom-wall-1.svg' ]"

section "10e. Custom Image — Bad Extension"

for ext in sh exe txt py; do
    setup_sandbox
    run_installer &>/dev/null
    mkdir -p "$FAKE_HOME/Pictures"
    echo "NOT_AN_IMAGE" > "$FAKE_HOME/Pictures/bad.$ext"

    create_zenity_mock "add" "vertical" "__custom__" "$FAKE_HOME/Pictures/bad.$ext"
    set +e; run_manager &>/dev/null; set -e

    assert_file_missing "No div created for .$ext" \
        "$FAKE_HOME/.local/share/applications/div_1.desktop"
done

section "10f. Custom Image — Bad Extension (kdialog)"

setup_sandbox
run_installer &>/dev/null

mkdir -p "$FAKE_HOME/Pictures"
echo "NOT_AN_IMAGE" > "$FAKE_HOME/Pictures/malware.bat"

create_kdialog_mock "add" "horizontal" "__custom__" "$FAKE_HOME/Pictures/malware.bat"
set +e; run_manager_kde &>/dev/null; set -e

assert_file_missing "KDE: No div created for .bat" \
    "$FAKE_HOME/.local/share/applications/div_1.desktop"

section "10g. Custom Image — Cancel"

setup_sandbox
run_installer &>/dev/null

create_zenity_mock "add" "vertical" "__custom__" "__CANCEL__"
set +e; run_manager &>/dev/null; EXIT=$?; set -e
assert_equals "Cancel at file picker -> exit 0" "0" "$EXIT"
assert_file_missing "No div created on cancel" \
    "$FAKE_HOME/.local/share/applications/div_1.desktop"

section "10h. Custom Image — Filename Sanitization"

setup_sandbox
run_installer &>/dev/null

mkdir -p "$FAKE_HOME/Pictures"
echo "DATA" > "$FAKE_HOME/Pictures/My Awesome Wall!!!.png"

create_zenity_mock "add" "vertical" "__custom__" "$FAKE_HOME/Pictures/My Awesome Wall!!!.png" "__YES__"
run_manager &>/dev/null

assert_file_exists "Sanitized custom: div_1 created" \
    "$FAKE_HOME/.local/share/applications/div_1.desktop"

ICON_FILES="$(ls "$FAKE_HOME/.local/share/icons/hicolor/128x128/apps"/div-vertical-* 2>/dev/null)"
assert "Sanitized custom: icon exists" "[ -n '$ICON_FILES' ]"
assert "Sanitized custom: no spaces in icon name" "! echo '$ICON_FILES' | grep -q ' '"
assert "Sanitized custom: no exclamation marks" "! echo '$ICON_FILES' | grep -q '!'"

section "11. Sequential Numbering & Icon Uniqueness"

setup_sandbox
run_installer &>/dev/null

create_zenity_mock "add" "vertical" "white.png" "__YES__"
run_manager &>/dev/null
create_zenity_mock "add" "horizontal" "red.png" "__YES__"
run_manager &>/dev/null
create_zenity_mock "add" "vertical" "black.png" "__YES__"
run_manager &>/dev/null

assert_file_exists "div_1 exists" "$FAKE_HOME/.local/share/applications/div_1.desktop"
assert_file_exists "div_2 exists" "$FAKE_HOME/.local/share/applications/div_2.desktop"
assert_file_exists "div_3 exists" "$FAKE_HOME/.local/share/applications/div_3.desktop"

assert_file_exists "Icon 1 has -1 suffix" \
    "$FAKE_HOME/.local/share/icons/hicolor/128x128/apps/div-vertical-white-1.png"
assert_file_exists "Icon 2 has -2 suffix" \
    "$FAKE_HOME/.local/share/icons/hicolor/128x128/apps/div-horizontal-red-2.png"
assert_file_exists "Icon 3 has -3 suffix" \
    "$FAKE_HOME/.local/share/icons/hicolor/128x128/apps/div-vertical-black-3.png"

setup_sandbox
run_installer &>/dev/null
create_zenity_mock "add" "vertical" "white.png" "__YES__"
run_manager &>/dev/null
create_zenity_mock "add" "vertical" "white.png" "__YES__"
run_manager &>/dev/null
create_zenity_mock "add" "vertical" "white.png" "__YES__"
run_manager &>/dev/null

assert_file_exists "Dup style 1: div-vertical-white-1.png" \
    "$FAKE_HOME/.local/share/icons/hicolor/128x128/apps/div-vertical-white-1.png"
assert_file_exists "Dup style 2: div-vertical-white-2.png" \
    "$FAKE_HOME/.local/share/icons/hicolor/128x128/apps/div-vertical-white-2.png"
assert_file_exists "Dup style 3: div-vertical-white-3.png" \
    "$FAKE_HOME/.local/share/icons/hicolor/128x128/apps/div-vertical-white-3.png"

setup_sandbox
run_installer &>/dev/null
create_zenity_mock "add" "vertical" "white.png" "__YES__"
run_manager &>/dev/null
create_zenity_mock "add" "vertical" "black.png" "__YES__"
run_manager &>/dev/null

rm -f "$FAKE_HOME/.local/share/applications/div_2.desktop"

create_zenity_mock "add" "vertical" "blue.svg" "__YES__"
run_manager &>/dev/null

assert_file_exists "Gap-filling: div_2 recreated" \
    "$FAKE_HOME/.local/share/applications/div_2.desktop"

section "12. Cancel Handling — zenity"

setup_sandbox
run_installer &>/dev/null

create_zenity_mock "__CANCEL__"
set +e; run_manager &>/dev/null; EXIT=$?; set -e
assert_equals "zenity: Cancel at main menu -> exit 0" "0" "$EXIT"

create_zenity_mock "add" "__CANCEL__"
set +e; run_manager &>/dev/null; EXIT=$?; set -e
assert_equals "zenity: Cancel at orientation -> exit 0" "0" "$EXIT"

create_zenity_mock "add" "vertical" "__CANCEL__"
set +e; run_manager &>/dev/null; EXIT=$?; set -e
assert_equals "zenity: Cancel at style -> exit 0" "0" "$EXIT"

DESKTOP_COUNT="$(ls "$FAKE_HOME/.local/share/applications"/div_*.desktop 2>/dev/null | wc -l)"
assert_equals "zenity: No divs from cancelled ops" "0" "$DESKTOP_COUNT"

section "12b. Cancel Handling — kdialog"

setup_sandbox
run_installer &>/dev/null

create_kdialog_mock "__CANCEL__"
set +e; run_manager_kde &>/dev/null; EXIT=$?; set -e
assert_equals "kdialog: Cancel at main menu -> exit 0" "0" "$EXIT"

create_kdialog_mock "add" "__CANCEL__"
set +e; run_manager_kde &>/dev/null; EXIT=$?; set -e
assert_equals "kdialog: Cancel at orientation -> exit 0" "0" "$EXIT"

create_kdialog_mock "add" "vertical" "__CANCEL__"
set +e; run_manager_kde &>/dev/null; EXIT=$?; set -e
assert_equals "kdialog: Cancel at style -> exit 0" "0" "$EXIT"

create_kdialog_mock "add" "vertical" "white.png" "__YES__"
run_manager_kde &>/dev/null

create_kdialog_mock "uninstall" "complete" "__NO__"
set +e; run_manager_kde &>/dev/null; EXIT=$?; set -e
assert_equals "kdialog: Decline uninstall -> exit 0" "0" "$EXIT"
assert_file_exists "kdialog: Div preserved after decline" \
    "$FAKE_HOME/.local/share/applications/div_1.desktop"

section "13. Selective Removal — zenity"

setup_sandbox
run_installer &>/dev/null

create_zenity_mock "add" "vertical" "white.png" "__YES__"
run_manager &>/dev/null
create_zenity_mock "add" "horizontal" "red.png" "__YES__"
run_manager &>/dev/null
create_zenity_mock "add" "vertical" "black.png" "__YES__"
run_manager &>/dev/null

create_zenity_mock "uninstall" "select" "div_1.desktop__NL__div_3.desktop" "__YES__" "__YES__"
run_manager &>/dev/null

assert_file_missing "div_1 removed" "$FAKE_HOME/.local/share/applications/div_1.desktop"
assert_file_exists "div_2 kept" "$FAKE_HOME/.local/share/applications/div_2.desktop"
assert_file_missing "div_3 removed" "$FAKE_HOME/.local/share/applications/div_3.desktop"

assert "Icons preserved after selective removal" \
    "ls '$FAKE_HOME/.local/share/icons/hicolor/128x128/apps'/div-* 2>/dev/null | wc -l | grep -qv '^0\$'"

section "13b. Selective Removal — kdialog"

setup_sandbox
run_installer &>/dev/null

create_kdialog_mock "add" "vertical" "white.png" "__YES__"
run_manager_kde &>/dev/null
create_kdialog_mock "add" "horizontal" "red.png" "__YES__"
run_manager_kde &>/dev/null

create_kdialog_mock "uninstall" "select" "div_2.desktop" "__YES__" "__YES__"
run_manager_kde &>/dev/null

assert_file_exists "KDE: div_1 kept" "$FAKE_HOME/.local/share/applications/div_1.desktop"
assert_file_missing "KDE: div_2 removed" "$FAKE_HOME/.local/share/applications/div_2.desktop"

section "13c. Selective Removal — Empty"

setup_sandbox
run_installer &>/dev/null

create_zenity_mock "uninstall" "select" "__YES__"
set +e; run_manager &>/dev/null; EXIT=$?; set -e
assert_equals "No divs -> exits cleanly" "0" "$EXIT"

section "13d. Selective Removal — Cancel"

setup_sandbox
run_installer &>/dev/null

create_zenity_mock "add" "vertical" "white.png" "__YES__"
run_manager &>/dev/null

create_zenity_mock "uninstall" "select" "__CANCEL__"
set +e; run_manager &>/dev/null; EXIT=$?; set -e
assert_equals "Cancel at checklist -> exit 0" "0" "$EXIT"
assert_file_exists "Div preserved after cancel" \
    "$FAKE_HOME/.local/share/applications/div_1.desktop"

create_zenity_mock "uninstall" "select" "div_1.desktop" "__NO__"
set +e; run_manager &>/dev/null; EXIT=$?; set -e
assert_equals "Decline confirm -> exit 0" "0" "$EXIT"
assert_file_exists "Div preserved after decline" \
    "$FAKE_HOME/.local/share/applications/div_1.desktop"

section "14. Clear All Divs — zenity"

setup_sandbox
run_installer &>/dev/null

create_zenity_mock "add" "vertical" "white.png" "__YES__"
run_manager &>/dev/null
create_zenity_mock "add" "horizontal" "red.png" "__YES__"
run_manager &>/dev/null

create_zenity_mock "uninstall" "all" "__YES__" "__YES__"
run_manager &>/dev/null

assert_file_missing "div_1 removed" "$FAKE_HOME/.local/share/applications/div_1.desktop"
assert_file_missing "div_2 removed" "$FAKE_HOME/.local/share/applications/div_2.desktop"
assert_file_exists "App .desktop preserved" "$FAKE_HOME/.local/share/applications/$APP_NAME.desktop"
assert_file_exists "Executable preserved" "$FAKE_HOME/.local/bin/$APP_NAME"
assert_dir_exists "Assets preserved" "$FAKE_HOME/.local/share/$APP_NAME/assets"

section "14b. Clear All Divs — kdialog"

setup_sandbox
run_installer &>/dev/null

create_kdialog_mock "add" "vertical" "white.png" "__YES__"
run_manager_kde &>/dev/null
create_kdialog_mock "add" "horizontal" "red.png" "__YES__"
run_manager_kde &>/dev/null

create_kdialog_mock "uninstall" "all" "__YES__" "__YES__"
run_manager_kde &>/dev/null

assert_file_missing "KDE: div_1 removed" "$FAKE_HOME/.local/share/applications/div_1.desktop"
assert_file_missing "KDE: div_2 removed" "$FAKE_HOME/.local/share/applications/div_2.desktop"
assert_file_exists "KDE: App .desktop preserved" "$FAKE_HOME/.local/share/applications/$APP_NAME.desktop"

section "15. Complete Uninstall — zenity"

setup_sandbox
run_installer &>/dev/null

create_zenity_mock "add" "vertical" "white.png" "__YES__"
run_manager &>/dev/null

create_zenity_mock "uninstall" "complete" "__YES__" "__YES__"
run_manager &>/dev/null

assert_file_missing "div_1 removed" "$FAKE_HOME/.local/share/applications/div_1.desktop"
assert_file_missing "App .desktop removed" "$FAKE_HOME/.local/share/applications/$APP_NAME.desktop"
assert_dir_missing "Assets dir removed" "$FAKE_HOME/.local/share/$APP_NAME"
assert_file_missing "Executable removed" "$FAKE_HOME/.local/bin/$APP_NAME"

ICON_COUNT=$(ls "$FAKE_HOME/.local/share/icons/hicolor/128x128/apps"/div-* 2>/dev/null | wc -l)
assert_equals "Icons removed on complete uninstall" "0" "$ICON_COUNT"

section "15b. Complete Uninstall — kdialog"

setup_sandbox
run_installer &>/dev/null

create_kdialog_mock "add" "vertical" "black.png" "__YES__"
run_manager_kde &>/dev/null

create_kdialog_mock "uninstall" "complete" "__YES__" "__YES__"
run_manager_kde &>/dev/null

assert_file_missing "KDE: div_1 removed" "$FAKE_HOME/.local/share/applications/div_1.desktop"
assert_file_missing "KDE: App .desktop removed" "$FAKE_HOME/.local/share/applications/$APP_NAME.desktop"
assert_dir_missing "KDE: Assets dir removed" "$FAKE_HOME/.local/share/$APP_NAME"
assert_file_missing "KDE: Executable removed" "$FAKE_HOME/.local/bin/$APP_NAME"

section "15c. Complete Uninstall — Multi-DE"

for de in "XFCE" "sway" "__unset__"; do
    setup_sandbox
    run_installer &>/dev/null
    create_zenity_mock "add" "vertical" "white.png" "__YES__"
    run_manager_de "$de" &>/dev/null
    create_zenity_mock "uninstall" "complete" "__YES__" "__YES__"
    run_manager_de "$de" &>/dev/null
    assert_file_missing "$de: Executable removed" "$FAKE_HOME/.local/bin/$APP_NAME"
    assert_dir_missing "$de: Assets removed" "$FAKE_HOME/.local/share/$APP_NAME"
done

section "16. Uninstall Declined — zenity"

setup_sandbox
run_installer &>/dev/null

create_zenity_mock "add" "vertical" "white.png" "__YES__"
run_manager &>/dev/null

create_zenity_mock "uninstall" "complete" "__NO__"
run_manager &>/dev/null

assert_file_exists "Executable preserved after decline" "$FAKE_HOME/.local/bin/$APP_NAME"
assert_file_exists "Div preserved after decline" "$FAKE_HOME/.local/share/applications/div_1.desktop"

section "17. .desktop Format Validation"

setup_sandbox
run_installer &>/dev/null

create_zenity_mock "add" "vertical" "white.png" "__YES__"
run_manager &>/dev/null

SEP="$FAKE_HOME/.local/share/applications/div_1.desktop"

assert "Starts with [Desktop Entry]" \
    "head -1 '$SEP' | grep -q '^\\[Desktop Entry\\]\$'"
assert "Has required Type field" "grep -q '^Type=' '$SEP'"
assert "Has required Name field" "grep -q '^Name=' '$SEP'"
assert "Has required Exec field" "grep -q '^Exec=' '$SEP'"
assert "Has Icon field" "grep -q '^Icon=' '$SEP'"
assert "Icon field is absolute path" "grep -q '^Icon=/' '$SEP'"

section "18. Edge Cases — Filenames"

setup_sandbox
run_installer &>/dev/null

mkdir -p "$FAKE_HOME/Pictures"
echo "DATA" > "$FAKE_HOME/Pictures/with spaces.png"

create_zenity_mock "add" "vertical" "__custom__" "$FAKE_HOME/Pictures/with spaces.png" "__YES__"
run_manager &>/dev/null

assert_file_exists "Filename with spaces: div_1 created" \
    "$FAKE_HOME/.local/share/applications/div_1.desktop"

ICON="$(ls "$FAKE_HOME/.local/share/icons/hicolor/128x128/apps"/div-vertical-* 2>/dev/null | head -1)"
assert "Sanitized icon filename has no spaces" "[ -n '$ICON' ] && ! echo '$ICON' | grep -q ' '"

section "19. Empty Assets"

setup_sandbox
run_installer &>/dev/null
rm -f "$FAKE_HOME/.local/share/$APP_NAME/assets/vertical"/*

create_zenity_mock "add" "vertical"
set +e
run_manager &>"$SANDBOX/empty_assets.out"
set -e

assert_file_missing "No div created with empty assets" \
    "$FAKE_HOME/.local/share/applications/div_1.desktop"

section "20. Path Traversal"

setup_sandbox
run_installer &>/dev/null

mkdir -p "$FAKE_HOME/Pictures"
echo "DATA" > "$FAKE_HOME/Pictures/..sneaky..png"

create_zenity_mock "add" "vertical" "__custom__" "$FAKE_HOME/Pictures/..sneaky..png" "__YES__"
run_manager &>/dev/null

ICON="$(ls "$FAKE_HOME/.local/share/icons/hicolor/128x128/apps"/div-vertical-* 2>/dev/null | head -1)"
assert "Path traversal sequence stripped from icon name" \
    "[ -n '$ICON' ] && ! echo '$ICON' | grep -q '\\.\\./'"

section "21. File Permissions"

setup_sandbox
run_installer &>/dev/null

assert "Executable has exec bit" "[ -x '$FAKE_HOME/.local/bin/$APP_NAME' ]"

create_zenity_mock "add" "vertical" "white.png" "__YES__"
run_manager &>/dev/null

ICON="$FAKE_HOME/.local/share/icons/hicolor/128x128/apps/div-vertical-white-1.png"
if [ -f "$ICON" ]; then
    PERMS="$(stat -c '%a' "$ICON" 2>/dev/null || stat -f '%Lp' "$ICON" 2>/dev/null)"
    assert_equals "Icon has 644 permissions" "644" "$PERMS"
fi

section "22. PATH Advisory"

setup_sandbox
PATH_OUT=$(
    export HOME="$FAKE_HOME"
    export PATH="/usr/bin:/bin"
    export XDG_CURRENT_DESKTOP="GNOME"
    patch_root_guard "$PROJECT_DIR/install.sh"
    cd "$PROJECT_DIR"
    bash install.sh 2>&1 || true
)
echo "$PATH_OUT" > "$SANDBOX/path_advisory.out"
assert_file_contains "PATH advisory appears when ~/.local/bin missing" \
    "$SANDBOX/path_advisory.out" "PATH"

setup_sandbox
PATH_OUT=$(
    export HOME="$FAKE_HOME"
    export PATH="$FAKE_HOME/.local/bin:/usr/bin:/bin"
    export XDG_CURRENT_DESKTOP="GNOME"
    patch_root_guard "$PROJECT_DIR/install.sh"
    cd "$PROJECT_DIR"
    bash install.sh 2>&1 || true
)
echo "$PATH_OUT" > "$SANDBOX/path_ok.out"
assert "No PATH advisory when ~/.local/bin already in PATH" \
    "! grep -q 'is not in your PATH' '$SANDBOX/path_ok.out'"

section "23. Extension Validation"

setup_sandbox
run_installer &>/dev/null

for ext in png svg jpg jpeg ico; do
    mkdir -p "$FAKE_HOME/Pictures"
    echo "DATA" > "$FAKE_HOME/Pictures/test.$ext"

    rm -f "$FAKE_HOME/.local/share/applications"/div_*.desktop

    create_zenity_mock "add" "vertical" "__custom__" "$FAKE_HOME/Pictures/test.$ext" "__YES__"
    run_manager &>/dev/null

    assert_file_exists "Valid extension .$ext accepted" \
        "$FAKE_HOME/.local/share/applications/div_1.desktop"
done

section "24. KDE Cache Refresh"

setup_sandbox
run_installer_kde &>/dev/null
assert "KDE install succeeds" "[ -f '$FAKE_HOME/.local/bin/$APP_NAME' ]"

setup_sandbox
run_installer &>/dev/null
assert "Non-KDE install succeeds" "[ -f '$FAKE_HOME/.local/bin/$APP_NAME' ]"

setup_sandbox
run_installer_kde &>/dev/null

cat > "$MOCK_BIN/kbuildsycoca5" <<MOCK
#!/bin/bash
echo "called" >> "$SANDBOX/kbuildsycoca.log"
exit 0
MOCK
chmod +x "$MOCK_BIN/kbuildsycoca5"

: > "$SANDBOX/kbuildsycoca.log"
create_kdialog_mock "add" "vertical" "white.png" "__YES__"
run_manager_kde &>/dev/null

assert "KDE add: kbuildsycoca called for cache refresh" \
    "[ -s '$SANDBOX/kbuildsycoca.log' ]"

setup_sandbox
run_installer &>/dev/null
cat > "$MOCK_BIN/kbuildsycoca5" <<MOCK
#!/bin/bash
echo "called" >> "$SANDBOX/kbuildsycoca.log"
exit 0
MOCK
chmod +x "$MOCK_BIN/kbuildsycoca5"

: > "$SANDBOX/kbuildsycoca.log"
create_zenity_mock "add" "vertical" "white.png" "__YES__"
run_manager &>/dev/null

assert "Non-KDE add: kbuildsycoca NOT called" \
    "[ ! -s '$SANDBOX/kbuildsycoca.log' ]"

section "25. Error Dialogs — kdialog Backend"

setup_sandbox
run_installer &>/dev/null
rm -rf "$FAKE_HOME/.local/share/$APP_NAME/assets/vertical"

create_kdialog_mock "add" "vertical"
set +e
run_manager_kde &>/dev/null
set -e

assert_file_missing "No div created when assets missing" \
    "$FAKE_HOME/.local/share/applications/div_1.desktop"

section "26. Installer DE Detection"

setup_sandbox
run_installer_kde &>"$SANDBOX/kde_install.out"
assert "KDE installer succeeds" "grep -q 'Done\\|DivBar' '$SANDBOX/kde_install.out'"

setup_sandbox
cat > "$MOCK_BIN/kbuildsycoca5" <<MOCK
#!/bin/bash
echo "INSTALLER_CALLED" >> "$SANDBOX/kbuild_installer.log"
exit 0
MOCK
chmod +x "$MOCK_BIN/kbuildsycoca5"

: > "$SANDBOX/kbuild_installer.log"
run_installer &>/dev/null

assert "Non-KDE installer doesn't call kbuildsycoca" \
    "[ ! -s '$SANDBOX/kbuild_installer.log' ]"

section "27. verify.sh — Happy Path"

if [ ! -f "$PROJECT_DIR/verify.sh" ]; then
    skip_test "verify.sh not present in source directory"
else
    setup_sandbox
    run_installer &>/dev/null

    set +e
    run_verify > "$SANDBOX/verify.out" 2>&1
    VERIFY_EXIT=$?
    set -e

    assert_equals "verify.sh exits 0 on clean install" "0" "$VERIFY_EXIT"
    assert_file_contains "verify.sh reports executable passes" \
        "$SANDBOX/verify.out" "[Ee]xecutable"
    assert_file_contains "verify.sh reports assets pass" \
        "$SANDBOX/verify.out" "[Aa]ssets"
    assert_file_contains "verify.sh reports menu entry passes" \
        "$SANDBOX/verify.out" "[Mm]enu\\|entry"
    assert_file_contains "verify.sh reports success" \
        "$SANDBOX/verify.out" "verified\\|Launch\\|[Pp]assed"
fi

section "28. verify.sh — Missing Executable"

if [ ! -f "$PROJECT_DIR/verify.sh" ]; then
    skip_test "verify.sh not present"
else
    setup_sandbox
    run_installer &>/dev/null
    rm -f "$FAKE_HOME/.local/bin/$APP_NAME"

    set +e
    run_verify > "$SANDBOX/verify_noexec.out" 2>&1
    VERIFY_EXIT=$?
    set -e

    assert "verify.sh exits non-zero when executable missing" "[ $VERIFY_EXIT -ne 0 ]"
    assert_file_contains "verify.sh reports executable missing" \
        "$SANDBOX/verify_noexec.out" "[Ee]xecutable\\|not found"
fi

section "29. verify.sh — Missing Assets"

if [ ! -f "$PROJECT_DIR/verify.sh" ]; then
    skip_test "verify.sh not present"
else
    setup_sandbox
    run_installer &>/dev/null
    rm -rf "$FAKE_HOME/.local/share/$APP_NAME/assets"

    set +e
    run_verify > "$SANDBOX/verify_noassets.out" 2>&1
    VERIFY_EXIT=$?
    set -e

    assert "verify.sh exits non-zero when assets missing" "[ $VERIFY_EXIT -ne 0 ]"
    assert_file_contains "verify.sh reports asset issue" \
        "$SANDBOX/verify_noassets.out" "[Aa]sset"
fi

section "30. verify.sh — Missing .desktop"

if [ ! -f "$PROJECT_DIR/verify.sh" ]; then
    skip_test "verify.sh not present"
else
    setup_sandbox
    run_installer &>/dev/null
    rm -f "$FAKE_HOME/.local/share/applications/$APP_NAME.desktop"

    set +e
    run_verify > "$SANDBOX/verify_nodesktop.out" 2>&1
    VERIFY_EXIT=$?
    set -e

    assert "verify.sh exits non-zero when .desktop missing" "[ $VERIFY_EXIT -ne 0 ]"
    assert_file_contains "verify.sh reports desktop issue" \
        "$SANDBOX/verify_nodesktop.out" "[Dd]esktop\\|entry"
fi

section "31. verify.sh — All Pieces Missing"

if [ ! -f "$PROJECT_DIR/verify.sh" ]; then
    skip_test "verify.sh not present"
else
    setup_sandbox

    set +e
    (
        export HOME="$FAKE_HOME"
        export PATH="/usr/bin:/bin"
        bash "$PROJECT_DIR/verify.sh" > "$SANDBOX/verify_empty.out" 2>&1
    )
    VERIFY_EXIT=$?
    set -e

    assert "verify.sh exits non-zero on empty install" "[ $VERIFY_EXIT -ne 0 ]"
    assert_file_contains "Reports verification failed" \
        "$SANDBOX/verify_empty.out" "[Ff]ailed\\|not found"
fi

section "32. Installer — Step 5 Verify Integration"

if [ ! -f "$PROJECT_DIR/verify.sh" ]; then
    skip_test "verify.sh not present"
else
    setup_sandbox
    INSTALL_OUT=$(run_installer 2>&1)
    echo "$INSTALL_OUT" > "$SANDBOX/install_with_verify.out"

    assert_file_contains "Installer invokes verification step" \
        "$SANDBOX/install_with_verify.out" "[Vv]erif"
fi

section "33. Exec Field — Divs Coexist"

setup_sandbox
run_installer &>/dev/null

create_zenity_mock "add" "vertical" "white.png" "__YES__"
run_manager &>/dev/null
create_zenity_mock "add" "vertical" "white.png" "__YES__"
run_manager &>/dev/null
create_zenity_mock "add" "vertical" "white.png" "__YES__"
run_manager &>/dev/null

COUNT=$(ls "$FAKE_HOME/.local/share/applications"/div_*.desktop 2>/dev/null | wc -l)
assert_equals "Three divs coexist" "3" "$COUNT"

for f in "$FAKE_HOME/.local/share/applications"/div_*.desktop; do
    assert "Exec field present in $(basename "$f")" "grep -q '^Exec=' '$f'"
done

section "34. Display Name Formatting"

setup_sandbox
run_installer &>/dev/null

create_zenity_mock "add" "vertical" "white.png" "__YES__"
run_manager &>/dev/null
create_zenity_mock "add" "horizontal" "red.png" "__YES__"
run_manager &>/dev/null

D1="$FAKE_HOME/.local/share/applications/div_1.desktop"
D2="$FAKE_HOME/.local/share/applications/div_2.desktop"

assert_file_contains "div_1 Name contains 1" "$D1" "Name=.*1"
assert_file_contains "div_2 Name contains 2" "$D2" "Name=.*2"
assert_file_contains "div_1 Name references vertical" "$D1" "vertical"
assert_file_contains "div_2 Name references horizontal" "$D2" "horizontal"

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "  ${GREEN}Passed:${RESET}  $PASS_COUNT"
if [ $FAIL_COUNT -gt 0 ]; then
    echo -e "  ${RED}Failed:${RESET}  $FAIL_COUNT"
else
    echo -e "  ${GREEN}Failed:${RESET}  0"
fi
if [ $SKIP_COUNT -gt 0 ]; then
    echo -e "  ${YELLOW}Skipped:${RESET} $SKIP_COUNT"
else
    echo -e "  ${YELLOW}Skipped:${RESET} 0"
fi
echo -e "  Total:   $TOTAL_COUNT"

if [ $FAIL_COUNT -gt 0 ]; then
    echo ""
    echo -e "${RED}${BOLD}Failed tests:${RESET}"
    for failed in "${FAILED_TESTS[@]}"; do
        echo -e "  ${RED}•${RESET} $failed"
    done
    echo ""
    echo -e "${RED}${BOLD}Some tests failed.${RESET}"
    exit 1
fi

echo ""
echo -e "${GREEN}${BOLD}All tests passed!${RESET}"
exit 0
