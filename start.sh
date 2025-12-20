#!/usr/bin/env bash
# start.sh
# Setup / Install / Bootstrap
# - Installiert DSP via SteamCMD (falls nötig)
# - Installiert Goldberg/Extra (optional)
# - Installiert BepInEx / Nebula (Defaults: GitHub Releases; override via env)
# - Injectet BepInEx.cfg (no comments, console enabled)
# - Optional: importiert SAVE_IMPORT (*.dsv) aus /data/import in Wine Save-Ordner
# - Startet dann startgame.sh

set -euo pipefail

log() { echo "[$(date -Iseconds)] $*"; }
require_env() { [[ -n "${!1:-}" ]] || { echo "ERROR: env var $1 is required" >&2; exit 1; }; }

require_env STEAM_USER
require_env STEAM_PASS

DATA_ROOT="/data"
SERVER_DIR="$DATA_ROOT/server"
WINE_DIR="$DATA_ROOT/wine"
STEAM_DIR="$DATA_ROOT/steam"
LOG_DIR="$DATA_ROOT/logs"
EXTRA_DIR="$DATA_ROOT/goldgoldgold"
IMPORT_DIR="${IMPORT_DIR:-$DATA_ROOT/import}"

mkdir -p "$SERVER_DIR" "$WINE_DIR" "$STEAM_DIR" "$LOG_DIR" "$EXTRA_DIR" "$IMPORT_DIR" /opt

ln -sfn "$SERVER_DIR" /opt/dsp
ln -sfn "$WINE_DIR" /root/.wine
ln -sfn "$STEAM_DIR" /root/Steam

export STEAM_INSTALL_DIR="/opt/dsp"
export HOME="/root"
export WINEPREFIX="$WINE_DIR"
export WINEDLLOVERRIDES="winhttp=n,b"
export LIBGL_ALWAYS_SOFTWARE=1

# Allow overriding WINEDEBUG from compose; default -all
export WINEDEBUG="${WINEDEBUG:--all}"

STEAM_APP_ID="${STEAM_APP_ID:-1366540}"
STEAMCMD_BIN="/usr/local/bin/steamcmd"
FORCE_UPDATE="${FORCE_UPDATE:-0}"

# --- DEFAULT URLs (override via docker-compose env if you want) ---
BEPINEX_URL="${BEPINEX_URL:-https://github.com/BepInEx/BepInEx/releases/download/v5.4.23.4/BepInEx_win_x64_5.4.23.4.zip}"
NEBULA_URL="${NEBULA_URL:-https://github.com/NebulaModTeam/nebula/releases/download/v0.9.19/Nebula_0.9.19.zip}"
EXTRA_ZIP_URL="${EXTRA_ZIP_URL:-}"
EXTRA_FORCE="${EXTRA_FORCE:-0}"

# Save import controls (optional)
SAVE_IMPORT="${SAVE_IMPORT:-}"                 # e.g. world.dsv (place in /data/import/)
SAVE_IMPORT_FORCE="${SAVE_IMPORT_FORCE:-0}"    # 1 = overwrite
SAVE_IMPORT_LOAD="${SAVE_IMPORT_LOAD:-1}"      # 1 = set SAVE_NAME if not set

download_with_retries() {
  local url="$1"
  local out="$2"
  local n=1
  while (( n <= 10 )); do
    log "Downloading (attempt $n/10): $url"
    rm -f "$out" || true
    if curl -L --fail --connect-timeout 8 --max-time 600 -o "$out" "$url"; then
      return 0
    fi
    sleep $((2 * n))
    n=$((n+1))
  done
  log "ERROR: Download failed: $url"
  exit 1
}

download_and_unzip() {
  local url="$1"
  local dest="$2"
  local tmp="/tmp/art_$(date +%s%N).zip"
  mkdir -p "$dest"
  download_with_retries "$url" "$tmp"
  unzip -o "$tmp" -d "$dest" >/dev/null
  rm -f "$tmp"
}

log "wine OK: $(wine --version || true)"
log "Initializing Wine prefix..."
wineboot -u >/dev/null 2>&1 || true

# --- Extra ZIP (optional) ---
if [[ -n "$EXTRA_ZIP_URL" ]]; then
  mkdir -p "$EXTRA_DIR"
  if [[ "$EXTRA_FORCE" == "1" || -z "$(ls -A "$EXTRA_DIR" 2>/dev/null)" ]]; then
    log "Extracting EXTRA ZIP from: $EXTRA_ZIP_URL"
    rm -rf "$EXTRA_DIR"/*
    download_and_unzip "$EXTRA_ZIP_URL" "$EXTRA_DIR"
  else
    log "Extra ZIP already present -> skipping"
  fi
fi

# --- Install DSP (SteamCMD) ---
DSP_EXE="$STEAM_INSTALL_DIR/DSPGAME.exe"
if [[ "$FORCE_UPDATE" == "1" || ! -f "$DSP_EXE" ]]; then
  log "Installing DSP via SteamCMD"
  "$STEAMCMD_BIN" \
    +@sSteamCmdForcePlatformType windows \
    +force_install_dir "$STEAM_INSTALL_DIR" \
    +login "$STEAM_USER" "$STEAM_PASS" \
    +app_update "$STEAM_APP_ID" validate \
    +quit
else
  log "DSP already present -> skipping SteamCMD"
fi

# Optional: copy steam_api64.dll from extra zip if present
if [[ -f "$EXTRA_DIR/steam_api64.dll" ]]; then
  mkdir -p "$STEAM_INSTALL_DIR/DSPGAME_Data/Plugins/x86_64"
  cp -f "$EXTRA_DIR/steam_api64.dll" \
    "$STEAM_INSTALL_DIR/DSPGAME_Data/Plugins/x86_64/steam_api64.dll"
  log "Applied steam_api64.dll override from EXTRA_DIR"
elif [[ -n "$EXTRA_ZIP_URL" ]]; then
  log "WARNING: EXTRA_ZIP_URL set but steam_api64.dll not found in $EXTRA_DIR"
fi

# --- Install BepInEx (default URL, override via env) ---
if [[ ! -f "$STEAM_INSTALL_DIR/BepInEx/core/BepInEx.dll" ]]; then
  log "Installing BepInEx from: $BEPINEX_URL"
  download_and_unzip "$BEPINEX_URL" "$STEAM_INSTALL_DIR"
else
  log "BepInEx already present -> skipping"
fi

# --- Install Nebula (default URL, override via env) ---
if [[ ! -d "$STEAM_INSTALL_DIR/BepInEx/plugins/nebula-NebulaMultiplayerMod" ]]; then
  log "Installing Nebula from: $NEBULA_URL"
  mkdir -p "$STEAM_INSTALL_DIR/BepInEx/plugins"
  download_and_unzip "$NEBULA_URL" "$STEAM_INSTALL_DIR/BepInEx/plugins"
else
  log "Nebula already present -> skipping"
fi

# Logs
mkdir -p "$LOG_DIR"
touch "$LOG_DIR/unity_headless.log" "$LOG_DIR/console_headless.log"

# Inject BepInEx.cfg (no comments) + Console Enabled=true + WriteUnityLog=true
BEP_CFG_DIR="$STEAM_INSTALL_DIR/BepInEx/config"
BEP_CFG_FILE="$BEP_CFG_DIR/BepInEx.cfg"
mkdir -p "$BEP_CFG_DIR"

log "Injecting BepInEx.cfg (no comments, console enabled, WriteUnityLog=true)"
cat > "$BEP_CFG_FILE" <<'EOF'
[Caching]
EnableAssemblyCache = true

[Chainloader]
HideManagerGameObject = false

[Harmony.Logger]
LogChannels = Warn, Error

[Logging]
UnityLogListening = true
LogConsoleToUnityLog = false

[Logging.Console]
Enabled = true
PreventClose = false
ShiftJisEncoding = false
StandardOutType = Auto
LogLevels = Fatal, Error, Warning, Message, Info

[Logging.Disk]
WriteUnityLog = true
AppendLog = false
Enabled = true
LogLevels = Fatal, Error, Warning, Message, Info

[Preloader]
ApplyRuntimePatches = true
HarmonyBackend = auto
DumpAssemblies = false
LoadDumpedAssemblies = false
BreakBeforeLoadAssemblies = false

[Preloader.Entrypoint]
Assembly = UnityEngine.CoreModule.dll
Type = Application
Method = .cctor
EOF

# --- Save import ---
WINE_SAVE_DIR="$WINE_DIR/drive_c/users/root/Documents/Dyson Sphere Program/Save"
mkdir -p "$WINE_SAVE_DIR"

if [[ -n "$SAVE_IMPORT" ]]; then
  SRC="$IMPORT_DIR/$SAVE_IMPORT"
  if [[ ! -f "$SRC" ]]; then
    log "ERROR: SAVE_IMPORT='$SAVE_IMPORT' but file not found: $SRC"
    log "Tip: put your save on host into: ./data/import/$SAVE_IMPORT"
    exit 1
  fi

  DEST="$WINE_SAVE_DIR/$SAVE_IMPORT"
  if [[ -f "$DEST" && "$SAVE_IMPORT_FORCE" != "1" ]]; then
    log "Save already exists -> skipping import (set SAVE_IMPORT_FORCE=1 to overwrite): $DEST"
  else
    log "Importing save: $SRC -> $DEST"
    cp -f "$SRC" "$DEST"
  fi

  if [[ "$SAVE_IMPORT_LOAD" == "1" && -z "${SAVE_NAME:-}" ]]; then
    STEM="${SAVE_IMPORT%.*}" # world.dsv -> world
    export SAVE_NAME="$STEM"
    log "Auto-setting SAVE_NAME='$SAVE_NAME' (from SAVE_IMPORT)"
  fi
fi

log "Starting DSP for real via startgame.sh"
exec /bin/bash /startgame.sh
