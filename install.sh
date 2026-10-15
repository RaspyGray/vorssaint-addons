#!/bin/zsh
# Vorssaint Add-ons: KDE Connect and AirDrop drop targets for the Dynamic Island.
#
# Takes the latest official Vorssaint release, applies the add-on patch on top,
# builds it and installs "Vorssaint (Developer).app" next to the official app.
#
#   install.sh                   install (with the daily update check), or update
#   install.sh --force           rebuild even if already up to date
#   install.sh --no-auto-update  install without the daily check, or turn it off
#   install.sh --uninstall       remove the add-on build and the daily check
#
# It can also run straight from GitHub:
#   curl -fsSL https://raw.githubusercontent.com/RaspyGray/vorssaint-addons/main/install.sh | zsh
set -euo pipefail
# Never stop to ask for a GitHub password: everything here is public.
export GIT_TERMINAL_PROMPT=0

ADDON_REPO="https://github.com/RaspyGray/vorssaint-addons.git"
UPSTREAM="https://github.com/vorssaint/vorssaint-utils.git"
HOME_DIR="$HOME/Library/Application Support/Vorssaint Addons"
INSTALLED_COPY="$HOME_DIR/addon"
STATE="$HOME_DIR/installed-version"
LOG="$HOME_DIR/install.log"
AGENT_ID="com.vorssaint.addons.update"
AGENT="$HOME/Library/LaunchAgents/$AGENT_ID.plist"
APP="/Applications/Vorssaint (Developer).app"
OFFICIAL_ID="com.vorssaint.utils"
DEV_ID="com.vorssaint.utils.dev"

FORCE=0; QUIET=0; AUTO=""; UNINSTALL=0; SYNCED=0
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=1 ;;
        --quiet) QUIET=1 ;;
        --auto-update) AUTO=on ;;
        --no-auto-update) AUTO=off ;;
        --uninstall) UNINSTALL=1 ;;
        --synced) SYNCED=1 ;;
        *) print "Unknown option: $arg"; exit 2 ;;
    esac
done

mkdir -p "$HOME_DIR"
say() { (( QUIET )) || print -- "$@"; print -- "$(date '+%F %T') $*" >> "$LOG"; }
notify() { osascript -e "display notification \"$1\" with title \"Vorssaint Add-ons\"" >/dev/null 2>&1 || true; }

disable_agent() {
    launchctl bootout "gui/$UID/$AGENT_ID" >/dev/null 2>&1 || true
    rm -f "$AGENT"
}

if (( UNINSTALL )); then
    disable_agent
    osascript -e 'quit app "Vorssaint (Developer)"' >/dev/null 2>&1 || true
    rm -rf "$APP" "$HOME_DIR"
    print "Removed Vorssaint (Developer) and the daily update check. The official Vorssaint is untouched."
    exit 0
fi

# Building needs Apple's command line tools (they also bring git). macOS
# offers to install them with a dialog; the script waits for the next run.
if ! xcode-select -p >/dev/null 2>&1; then
    xcode-select --install >/dev/null 2>&1 || true
    say "First, macOS needs its command line developer tools."
    say "Click \"Install\" in the window that just opened, wait until it finishes, then run the same command again."
    exit 1
fi

# Where this script came from: a folder with the patch next to it (a clone of
# the repo), or nothing at all (piped from curl).
SCRIPT_DIR=""
[[ -f "${0:A}" ]] && SCRIPT_DIR="${0:A:h}"

# The daily check runs a copy kept in Application Support, since background
# jobs may not read ~/Documents. That copy is a clone of the GitHub repo, so
# the check also picks up new versions of the add-on itself.
if [[ "$SCRIPT_DIR" != "$INSTALLED_COPY" ]]; then
    REMOTE="$ADDON_REPO"
    if [[ -n "$SCRIPT_DIR" ]]; then
        REMOTE="$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null || print -- "$ADDON_REPO")"
    fi
    rm -rf "$INSTALLED_COPY"
    if ! git clone --quiet "$REMOTE" "$INSTALLED_COPY" 2>/dev/null; then
        [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/vorssaint-addons.patch" ]] \
            || { say "Could not download the add-on from GitHub. Check the connection and try again."; exit 1; }
        mkdir -p "$INSTALLED_COPY"
    fi
    # A local copy of the repo with changes not on GitHub yet wins for this run.
    if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/vorssaint-addons.patch" ]]; then
        cp "$SCRIPT_DIR/install.sh" "$SCRIPT_DIR/vorssaint-addons.patch" "$INSTALLED_COPY/"
    fi
    exec /bin/zsh "$INSTALLED_COPY/install.sh" "$@" --synced
elif [[ -d "$INSTALLED_COPY/.git" ]] && (( ! SYNCED )); then
    # This copy is never edited by hand: match GitHub exactly, then run the
    # script as it now is.
    if git -C "$INSTALLED_COPY" fetch --quiet 2>/dev/null \
        && git -C "$INSTALLED_COPY" reset --quiet --hard '@{u}' 2>/dev/null; then
        print -- "$(date '+%F %T') Checked GitHub for a newer version of the add-on." >> "$LOG"
        exec /bin/zsh "$INSTALLED_COPY/install.sh" "$@" --synced
    fi
fi
PATCH="$INSTALLED_COPY/vorssaint-addons.patch"

# Run by hand, the daily check comes on unless asked otherwise.
[[ -z "$AUTO" ]] && (( ! QUIET )) && [[ ! -f "$AGENT" ]] && AUTO=on
if [[ "$AUTO" == off ]]; then disable_agent; say "Daily update check turned off."; fi
if [[ "$AUTO" == on ]]; then
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$AGENT_ID</string>
  <key>ProgramArguments</key><array>
    <string>/bin/zsh</string><string>$INSTALLED_COPY/install.sh</string><string>--quiet</string>
  </array>
  <key>StartInterval</key><integer>86400</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$HOME_DIR/agent.log</string>
  <key>StandardErrorPath</key><string>$HOME_DIR/agent.log</string>
</dict></plist>
PLIST
    launchctl bootout "gui/$UID/$AGENT_ID" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$UID" "$AGENT"
    say "Daily update check is on."
fi

# The newest stable release (betas carry a dash, e.g. v3.4.1-beta.5).
TAG="$(git ls-remote --tags --refs "$UPSTREAM" 'v*' | sed 's#.*/##' | command grep -v -e '-' | sort -V | tail -1)"
[[ -n "$TAG" ]] || { say "Could not reach GitHub to find the latest Vorssaint release."; exit 1; }
PATCH_SUM="$(shasum "$PATCH" | cut -d' ' -f1)"
WANT="$TAG $PATCH_SUM"

if (( ! FORCE )) && [[ -f "$STATE" && "$(cat "$STATE")" == "$WANT" && -d "$APP" ]]; then
    say "Already up to date: Vorssaint $TAG with the add-ons."
    exit 0
fi

FIRST_INSTALL=0
[[ -d "$APP" ]] || FIRST_INSTALL=1

say "Building Vorssaint $TAG with the add-ons. This takes a few minutes…"
SRC="$HOME_DIR/src"
rm -rf "$SRC"
git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$TAG" "$UPSTREAM" "$SRC"
cd "$SRC"
if git apply --whitespace=nowarn "$PATCH" 2>/dev/null; then
    :
elif patch -p1 --forward --fuzz=3 --no-backup-if-mismatch < "$PATCH" >> "$LOG" 2>&1; then
    say "The patch needed small adjustments for $TAG; applied."
else
    say "The add-ons do not fit Vorssaint $TAG yet. Your current build keeps working; the patch needs an update."
    notify "Vorssaint $TAG is out, but the add-ons need an update before they can be rebuilt."
    exit 1
fi

if ! ./build.sh --dev --install >> "$LOG" 2>&1; then
    say "The build failed; details in $LOG. Your current build keeps working."
    notify "Rebuilding Vorssaint $TAG with the add-ons failed."
    exit 1
fi

print -- "$WANT" > "$STATE"
cd "$HOME_DIR"
rm -rf "$SRC"
say "Installed: $APP (Vorssaint $TAG with KDE Connect and AirDrop)."
notify "Vorssaint $TAG with the add-ons is installed."

if (( FIRST_INSTALL && ! QUIET )); then
    # Start from the settings of an official Vorssaint already in use.
    if defaults read "$OFFICIAL_ID" >/dev/null 2>&1 && ! defaults read "$DEV_ID" >/dev/null 2>&1; then
        defaults export "$OFFICIAL_ID" - | defaults import "$DEV_ID" -
        SUPPORT="$HOME/Library/Application Support"
        [[ -d "$SUPPORT/$OFFICIAL_ID" && ! -d "$SUPPORT/$DEV_ID" ]] && cp -R "$SUPPORT/$OFFICIAL_ID" "$SUPPORT/$DEV_ID"
        say "Copied your settings from the official Vorssaint."
    fi
    # Two islands at once would sit on top of each other.
    if pgrep -xq Vorssaint; then
        osascript -e 'quit app "Vorssaint"' >/dev/null 2>&1 || true
        say "Quit the official Vorssaint, so only one Dynamic Island runs."
    fi
    open "$APP"
fi
