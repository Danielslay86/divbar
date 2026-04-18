#!/usr/bin/env bash
# ----------------------------------------------------
# DivBar Installer
# Version 1.0
# ----------------------------------------------------
set -euo pipefail

readonly SCRIPT_VERSION="1.0.0"

if [ "${EUID:-$(id -u)}" -eq 0 ]; then    
    echo "Error: Do NOT run as root." >&2
    echo "This is a user-level tool." >&2
    exit 1
fi

readonly APP_NAME="divbar"
readonly BIN_DIR="$HOME/.local/bin"
readonly DATA_DIR="$HOME/.local/share/$APP_NAME"
readonly APP_DIR="$HOME/.local/share/applications"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log_step() { echo "[$1/$2] $3"; }
die() { echo "ERROR: $1" >&2; exit 1; }

detect_de() {
    local de="${XDG_CURRENT_DESKTOP:-}"
    de="${de,,}"
    if [[ "$de" = *"kde"* ]] || [ "${KDE_FULL_SESSION:-}" = "true" ]; then
        echo "kde"
    else 
        echo "other"
    fi
}

echo "----------------------------------------------"
echo " Installing DivBar"
echo " Version: $SCRIPT_VERSION"
echo "----------------------------------------------"

[ -d "$SCRIPT_DIR/assets" ] || die "'assets' folder not found in $SCRIPT_DIR"
[ -f "$SCRIPT_DIR/divbar.sh" ] || die "'divbar.sh' not found in $SCRIPT_DIR" 

log_step 1 5 "Installing assets to $DATA_DIR..."

[[ "$DATA_DIR" == "$HOME/.local/share/"* ]] || die "DATA_DIR path is outside expected location: $DATA_DIR"

rm -rf "$DATA_DIR"
mkdir -p "$DATA_DIR"
cp -r "$SCRIPT_DIR/assets" "$DATA_DIR/"

log_step 2 5 "Installing executable to $BIN_DIR/$APP_NAME..."
mkdir -p "$BIN_DIR"

cp "$SCRIPT_DIR/divbar.sh" "$BIN_DIR/$APP_NAME"
chmod +x "$BIN_DIR/$APP_NAME"

if grep -q '# __INSTALLER_PATCH__' "$BIN_DIR/$APP_NAME"; then   
    sed -i "s|^ASSETS_DIR=.*# __INSTALLER_PATCH__$|ASSETS_DIR=\"$DATA_DIR/assets\" # __INSTALLER_PATCH__|" "$BIN_DIR/$APP_NAME"
else
    sed -i "0,/^ASSETS_DIR=/{s|^ASSETS_DIR=.*|ASSETS_DIR=\"$DATA_DIR/assets\" # __INSTALLER_PATCH__|}" "$BIN_DIR/$APP_NAME"
fi

log_step 3 5 "Creating application menu entry..."
mkdir -p "$APP_DIR"

cat > "$APP_DIR/$APP_NAME.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=DivBar
Comment=Create and manage taskbar divs
Exec=$BIN_DIR/$APP_NAME
Icon=preferences-desktop-display
Terminal=false
Categories=Utility;Settings;
EOF

log_step 4 5 "Refreshing menu cache..."
if [ "$(detect_de)" = "kde" ]; then   
    kbuildsycoca5 &>/dev/null || kbuildsycoca6 &>/dev/null || true
fi

log_step 5 5 "Verifying installation..."
echo ""
if [ -f "$SCRIPT_DIR/verify.sh" ]; then
    set +e
    bash "$SCRIPT_DIR/verify.sh"
    VERIFY_EXIT=$?
    set -e
else
    echo "(verify.sh not found - skipping verification)"
    VERIFY_EXIT=0
fi

if [[ ":${PATH}:" != *":$HOME/.local/bin:"* ]]; then
    echo ""
    echo "NOTE: $HOME/.local/bin is not in your PATH."
    echo " The menu shortcut will work, but to run '$APP_NAME' from a terminal,"
    echo " add this to your ~/.bashrc or ~/.profile:"
    echo " export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo ""
fi

if [ "$VERIFY_EXIT" -ne 0 ]; then
    echo ""
    echo "Install completed with verification failures. Check output above."
    exit "$VERIFY_EXIT"
fi

echo ""
echo "----------------------------------------------------------"
echo "Done! Launch 'DivBar' from your app menu"
echo "----------------------------------------------------------"