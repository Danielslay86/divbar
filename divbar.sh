#!/usr/bin/env bash
# ----------------------------------------------------
# DivBar
# Version 1.0
# 
# Clean .svg separators for any taskbar irregardless of linux desktop environment.
# ----------------------------------------------------
set -u

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "Error: Do NOT run as root." >&2
    echo "This is a user-level tool." >&2
    exit 1
fi

readonly APP_NAME="divbar"
readonly APP_DIR="$HOME/.local/share/applications"
readonly ICONS_DIR="$HOME/.local/share/icons/hicolor/128x128/apps"
ASSETS_DIR="$HOME/.local/share/$APP_NAME/assets" # __INSTALLER_PATCH__

detect_backend() {
    local de="${XDG_CURRENT_DESKTOP:-}"
    de="${de,,}"

    if [[ "$de" = *"kde"* ]] || [ "${KDE_FULL_SESSION:-}" = "true" ]; then
        if command -v kdialog &>/dev/null; then 
            echo "kdialog"
            return
        fi 
    fi 

    if command -v zenity &>/dev/null; then
        echo "zenity"
        return
    fi 

    if command -v kdialog &>/dev/null; then 
        echo "kdialog"
        return
    fi 

    echo "none"
}

DIALOG_BACKEND="$(detect_backend)"

if [ "$DIALOG_BACKEND" = "none" ]; then
    if command -v notify-send &>/dev/null; then
        notify-send "DivBar" \
            "Error: No dialog tool found. Install zenity or kdialog."
    fi
    echo "Error: No dialog tool found. Install zenity or kdialog." >&2
    exit 1
fi

dialog_menu() {
    local title="$1" text="$2"
    shift 2

    if [ "$DIALOG_BACKEND" = "kdialog" ]; then
        kdialog --title "$title" --menu "$text" "$@"
    else 
        local args=()
        while [ $# -ge 2 ]; do 
            args+=("$1" "$2")
            shift 2
        done 
        zenity --list --title="$title" --text="$text" \
            --column="Key" --column="Option" \
            --hide-column=1 --print-column=1 \
            --width=420 --height=360 \
            "${args[@]}"
    fi 
}

dialog_file() {
    local title="$1" start_dir="$2" filter_label="$3" filter_pattern="$4"

    if [ "$DIALOG_BACKEND" = "kdialog" ]; then
        kdialog --title "$title" --getopenfilename "$start_dir" "$filter_label ($filter_pattern)"
    else 
        zenity --file-selection --title="$title" \
            --filename="$start_dir/" \
            --file-filter="$filter_label | $filter_pattern"
    fi
}

dialog_info() {
    local title="$1" text="$2"

    if [ "$DIALOG_BACKEND" = "kdialog" ]; then    
        kdialog --title "$title" --msgbox "$text"
    else
        zenity --info --title="$title" --text="$text" --width=380
    fi
}

dialog_error() {
    local text="$1"

    if [ "$DIALOG_BACKEND" = "kdialog" ]; then
        kdialog --error "$text" 2>/dev/null
    else
        zenity --error --text="$text" --width=360 --icon-name=dialog-warning 2>/dev/null
    fi
}

dialog_confirm() {
    local title="$1" text="$2"

    if [ "$DIALOG_BACKEND" = "kdialog" ]; then
        kdialog --title "$title" --warningyesno "$text"
    else
        zenity --question --title="$title" --text="$text" \
        --width=360 --icon-name=dialog-warning
    fi
}

dialog_checklist() {
    local title="$1" text="$2"
    shift 2

    if [ "$DIALOG_BACKEND" = "kdialog" ]; then
        local args=()
        while [ $# -ge 2 ]; do
            args+=("$1" "$2" "off")
            shift 2
        done
        local result
        result=$(kdialog --title "$title" --checklist "$text" "${args[@]}") || return 1
        echo "$result" | tr ' ' '\n' | sed 's/^"//; s/"$//' | grep -v '^$'
    else
        local args=()
        while [ $# -ge 2 ]; do
            args+=("FALSE" "$1" "$2")
            shift 2
        done
        local result
        result=$(zenity --list --title="$title" --text="$text" \
            --checklist \
            --column="Select" --column="Key" --column="Div" \
            --hide-column=2 --print-column=2 \
            --width=450 --height=400 \
            --separator=$'\n' \
            "${args[@]}") || return 1
        echo "$result"
    fi
}

die_gui() {
    dialog_error "$1"
    exit 1
}

refresh_cache() {
    if [ "$DIALOG_BACKEND" = "kdialog" ]; then
        kbuildsycoca5 &>/dev/null || kbuildsycoca6 &>/dev/null || true
    fi
}

sanitize_name() {
    local name="$1"
    name="${name,,}"
    name="${name// /-}"
    name="${name//[^a-z0-9-]/}"
    name="$(echo "$name" | sed 's/-\+/-/g; s/^-//; s/-$//')"
    echo "$name"
}

parse_desktop_name() {
    local file="$1"
    grep -m1 '^Name=' "$file" 2>/dev/null | cut -d= -f2-
}

main_menu() {
    ACTION=$(dialog_menu "DivBar" "Choose an action:" \
            "add"  "Add New Div" \
            "uninstall" "Uninstall / Remove") || return 0

    if [ "$ACTION" = "add" ]; then
        TARGET_MODE=$(dialog_menu "Step 1/2: Orientation" \
                        "Where is your taskbar situated?" \
                        "vertical" "Top/Bottom (Vertical Div)" \
                        "horizontal" "Left/Right (Horizontal Div)") || return 0

        COLOR_PATH="$ASSETS_DIR/$TARGET_MODE"

        if [ ! -d "$COLOR_PATH" ]; then
            die_gui "Assets folder not found at:\n$COLOR_PATH"
        fi

        ARGS=()
        shopt -s nullglob
        for f in "$COLOR_PATH"/*; do
            [ -f "$f" ] || continue
            NAME="$(basename "$f")"
            ARGS+=("$NAME" "$NAME")
        done
        shopt -u nullglob

        if [ ${#ARGS[@]} -eq 0 ]; then
            die_gui "No images found in:\n$COLOR_PATH"
        fi

        ARGS+=("__custom__" "Custom Image...")

        SELECTED_CHOICE=$(dialog_menu "Step 2/2: Choose Style" \
                            "Select a div style:" "${ARGS[@]}") || return 0

        if [ "$SELECTED_CHOICE" = "__custom__" ]; then
            SOURCE_ICON=$(dialog_file "Select Custom Image" "$HOME" \
                            "Images" "*.png *.svg *.jpg *.jpeg *.ico") || return 0
            SELECTED_FILE="$(basename "$SOURCE_ICON")"
        else
            SOURCE_ICON="$COLOR_PATH/$SELECTED_CHOICE"
            SELECTED_FILE="$SELECTED_CHOICE"
        fi

        if [ ! -f "$SOURCE_ICON" ]; then
            die_gui "Could not find icon file:\n$SOURCE_ICON"
        fi

        EXTENSION="${SELECTED_FILE##*.}"
        EXTENSION="${EXTENSION,,}"

        case "$EXTENSION" in 
            png|svg|jpg|jpeg|ico) ;;
            *) die_gui "Unsupported image format: .$EXTENSION\nSupported: png, svg, jpg, jpeg, ico" ;;
        esac

        CLEAN_NAME="$(sanitize_name "${SELECTED_FILE%.*}")"
        if [ -z "$CLEAN_NAME" ]; then
            CLEAN_NAME="custom"
        fi

            NEXT_NUM=1 
        while [ -f "$APP_DIR/div_${NEXT_NUM}.desktop" ]; do
            ((NEXT_NUM++))
        done

        ICON_SYSTEM_NAME="div-${TARGET_MODE}-${CLEAN_NAME}-${NEXT_NUM}"
        DEST_ICON="$ICONS_DIR/$ICON_SYSTEM_NAME.$EXTENSION"

        mkdir -p "$ICONS_DIR"
        cp "$SOURCE_ICON" "$DEST_ICON"
        chmod 644 "$DEST_ICON"

        DESKTOP_FILE="$APP_DIR/div_${NEXT_NUM}.desktop"
        DISPLAY_NAME="Div ${NEXT_NUM} (${TARGET_MODE} - ${SELECTED_FILE%.*})"

        cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=$DISPLAY_NAME
Icon=$DEST_ICON
Exec=/usr/bin/true div-${NEXT_NUM}
StartupNotify=false
Categories=Utility;
EOF

        if [ ! -f "$DESKTOP_FILE" ]; then
            die_gui "Failed to write .desktop file to:\n$DESKTOP_FILE"
        fi

        touch "$ICONS_DIR"
        refresh_cache

        dialog_info "Success" "Added: $DISPLAY_NAME\n\nFind it in your Application Menu and drag it to your taskbar."

    elif [ "$ACTION" = "uninstall" ]; then
        UNINSTALL_TYPE=$(dialog_menu "Uninstall Options" \
                        "What would you like to remove?" \
                        "select" "Remove Specific Divs" \
                        "all" "Clear Generated Divs (Keep App)" \
                        "complete" "Complete Uninstall (Remove Everything)") || return 0

        if [ "$UNINSTALL_TYPE" = "select" ]; then
            CHECKLIST_ARGS=()
            shopt -s nullglob
            for f in "$APP_DIR"/div_*.desktop; do
                BASENAME="$(basename "$f")"
                DISPLAY="$(parse_desktop_name "$f")"
                if [ -z "$DISPLAY" ]; then
                    DISPLAY="$BASENAME"
                fi
                CHECKLIST_ARGS+=("$BASENAME" "$DISPLAY")
            done
            shopt -u nullglob

            if [ ${#CHECKLIST_ARGS[@]} -eq 0 ]; then
                dialog_info "Nothing to Remove" "No divs found."
                return 0
            fi

            SELECTED=$(dialog_checklist "Remove Divs" \
                    "Select Divs to remove:" "${CHECKLIST_ARGS[@]}") || return 0
            
            if [ -z "$SELECTED" ]; then
                return 0 
            fi

            COUNT=$(echo "$SELECTED" | wc -l)

            if dialog_confirm "Confirm Removal" \
                "Remove $COUNT selected divs?"; then

                while IFS= read -r filename; do
                    [ -z "$filename" ] && continue
                    rm -f "$APP_DIR/$filename"
                done <<< "$SELECTED"

                refresh_cache
                dialog_info "Done" "Removed $COUNT divs."
            fi

        
        elif [ "$UNINSTALL_TYPE" = "all" ]; then
            if dialog_confirm "Remove Divs" \
                "This will delete all generated div entries.\n\nContinue?"; then

                rm -f "$APP_DIR"/div_*.desktop
                rm -f "$ICONS_DIR"/div-*.*

                refresh_cache
                dialog_info "Done" "All divs have been removed."
            fi
        
        elif [ "$UNINSTALL_TYPE" = "complete" ]; then

            MSG="WARNING: COMPLETE UNINSTALL\n\n"
            MSG+="This will permanently delete:\n\n"
            MSG+="  - All generated divs\n"
            MSG+="  - The assets folder\n"
            MSG+="  - The DivBar executable\n"
            MSG+="  - The application menu entry\n\n"

            if dialog_confirm "Confirm Full Uninstall" "$MSG"; then

                rm -f "$APP_DIR"/div_*.desktop
                rm -f "$APP_DIR/$APP_NAME.desktop"

                DATA_PARENT_DIR="$HOME/.local/share/$APP_NAME"
                if [ -d "$DATA_PARENT_DIR" ]; then
                    
                    rm -rf "$DATA_PARENT_DIR"
                
                fi

                rm -f "$ICONS_DIR"/div-*.*
                rm -f "$HOME/.local/bin/$APP_NAME"

                SELF="$(realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "")"
                if [ -n "$SELF" ] && [ -f "$SELF" ]; then
                    rm -f "$SELF"
                fi

                refresh_cache
                dialog_info "Done" "Uninstall complete.\n\nAll files have been removed."
                exit 0
            fi
        fi
    fi

    main_menu
}

main_menu

exit 0