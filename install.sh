#!/bin/zsh
# Vorssaint Add-ons: KDE Connect and AirDrop drop targets for the Dynamic Island.
#
# Takes the latest official Vorssaint release, applies the add-on patch on top,
# builds it and installs it as /Applications/Vorssaint.app, in place of the
# official download. Settings stay as they are.
#
#   install.sh                   install (with the daily update check), or update
#   install.sh --force           rebuild even if already up to date
#   install.sh --no-auto-update  install without the daily check, or turn it off
#   install.sh --uninstall       go back to the official Vorssaint
#
# It can also run straight from GitHub:
#   curl -fsSL https://raw.githubusercontent.com/RaspyGray/vorssaint-addons/main/install.sh | zsh
set -euo pipefail
# Never stop to ask for a GitHub password: everything here is public.
export GIT_TERMINAL_PROMPT=0

ADDON_REPO="https://github.com/RaspyGray/vorssaint-addons.git"
UPSTREAM="https://github.com/vorssaint/vorssaint-utils.git"
RELEASES_API="https://api.github.com/repos/vorssaint/vorssaint-utils/releases/latest"
HOME_DIR="$HOME/Library/Application Support/Vorssaint Addons"
INSTALLED_COPY="$HOME_DIR/addon"
STATE="$HOME_DIR/installed-version"
LOG="$HOME_DIR/install.log"
AGENT_ID="com.vorssaint.addons.update"
AGENT="$HOME/Library/LaunchAgents/$AGENT_ID.plist"
APP="/Applications/Vorssaint.app"
# Earlier versions of the add-on installed a second, separate app.
OLD_APP="/Applications/Vorssaint (Developer).app"
OFFICIAL_ID="com.vorssaint.utils"
OLD_ID="com.vorssaint.utils.dev"

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

# The installed app carries the add-ons, rather than an official update
# installed over it since.
has_addons() {
    [[ -x "$APP/Contents/MacOS/Vorssaint" ]] && command grep -q notchKDEConnectEnabled "$APP/Contents/MacOS/Vorssaint"
}

if (( UNINSTALL )); then
    disable_agent
    say "Downloading the official Vorssaint…"
    DMG_URL="$(curl -fsSL "$RELEASES_API" | sed -n 's/.*"browser_download_url": *"\([^"]*\.dmg\)".*/\1/p' | head -1)"
    [[ -n "$DMG_URL" ]] || { say "Could not reach GitHub. Check the connection and try again."; exit 1; }
    TMP="$(mktemp -d)"
    curl -fsSL "$DMG_URL" -o "$TMP/Vorssaint.dmg"
    hdiutil attach -nobrowse -quiet -mountpoint "$TMP/mount" "$TMP/Vorssaint.dmg"
    osascript -e 'quit app "Vorssaint"' >/dev/null 2>&1 || true
    sleep 1
    rm -rf "$APP"
    ditto "$TMP/mount/Vorssaint.app" "$APP"
    hdiutil detach -quiet "$TMP/mount" || true
    rm -rf "$TMP" "$HOME_DIR"
    open "$APP"
    print "Back to the official Vorssaint. Your settings are unchanged."
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

if (( ! FORCE )) && [[ -f "$STATE" && "$(cat "$STATE")" == "$WANT" ]] && has_addons; then
    say "Already up to date: Vorssaint $TAG with the add-ons."
    exit 0
fi

FIRST_INSTALL=1
has_addons && FIRST_INSTALL=0
WAS_RUNNING=0
pgrep -xq Vorssaint && WAS_RUNNING=1

say "Building Vorssaint $TAG with the add-ons. This takes several minutes…"
SRC="$HOME_DIR/src"
rm -rf "$SRC"
git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$TAG" "$UPSTREAM" "$SRC"
cd "$SRC"
if git apply --whitespace=nowarn "$PATCH" 2>/dev/null; then
    :
elif patch -p1 --forward --fuzz=3 --no-backup-if-mismatch < "$PATCH" >> "$LOG" 2>&1; then
    say "The patch needed small adjustments for $TAG; applied."
else
    say "The add-ons do not fit Vorssaint $TAG yet. Your current version keeps working; the patch needs an update."
    notify "Vorssaint $TAG is out, but the add-ons need an update before they can be rebuilt."
    exit 1
fi

# The finished app replaces /Applications/Vorssaint.app; build.sh quits the
# running one first.
if ! VORSSAINT_ADDONS=1 ./build.sh --install >> "$LOG" 2>&1; then
    say "The build failed; details in $LOG. Your current version keeps working."
    notify "Rebuilding Vorssaint $TAG with the add-ons failed."
    exit 1
fi

print -- "$WANT" > "$STATE"
cd "$HOME_DIR"
rm -rf "$SRC"

# Coming from the earlier two-app setup: keep the settings used there, and
# remove the second app.
if [[ -d "$OLD_APP" ]]; then
    osascript -e 'quit app "Vorssaint (Developer)"' >/dev/null 2>&1 || true
    if defaults read "$OLD_ID" >/dev/null 2>&1; then
        defaults export "$OFFICIAL_ID" "$HOME_DIR/settings-before-merge.plist" 2>/dev/null || true
        defaults export "$OLD_ID" - | defaults import "$OFFICIAL_ID" -
        SUPPORT="$HOME/Library/Application Support"
        if [[ -d "$SUPPORT/$OLD_ID" ]]; then
            rm -rf "$SUPPORT/$OFFICIAL_ID"
            cp -R "$SUPPORT/$OLD_ID" "$SUPPORT/$OFFICIAL_ID"
        fi
    fi
    rm -rf "$OLD_APP"
    say "Removed the separate Vorssaint (Developer) app; its settings are now in Vorssaint."
fi

say "Installed: $APP (Vorssaint $TAG with KDE Connect and AirDrop)."
notify "Vorssaint $TAG with the add-ons is installed."
if (( FIRST_INSTALL && ! QUIET )); then
    say "macOS may ask once more for Vorssaint's permissions, since this copy was built on your Mac."
fi
(( WAS_RUNNING || ! QUIET )) && open "$APP"
exit 0
