# DSP_docker
A Docker image for a headless DSP multiplayer server with wine

## Note about the first start (one-time restart)
On some systems the server **may not come up on the very first boot**.  
This is a known quirk of running DSP headless under Wine/Xvfb: the initial Unity window / display initialization can fail once, and a restart fixes it.

**Good news:** the container handles this automatically.
- During the first startup it waits a short time for the server to report readiness (`Listening server on port` in `BepInEx/LogOutput.log`).
- If that message does not appear within ~2 minutes, the container exits once, and Docker restarts it (because `restart: unless-stopped` is enabled).
- After that one restart, it should run normally.

If you ever get stuck in a restart loop, check the logs:
```bash
docker compose logs -f --tail=200
tail -n 200 ./data/logs/console_headless.log
tail -n 200 ./data/server/BepInEx/LogOutput.log
```
```yml
services:
  dsp:
    image: ghcr.io/fox4fun31/dsp_hosting:latest
    # build:
    #   context: .
    container_name: dsp_nebula_server

    ports:
      - "8469:8469/tcp"

    environment:
      # ---- Steam (user must own DSP) ----
      STEAM_USER: "steamname"
      STEAM_PASS: "steampw"
      STEAM_APP_ID: "1366540"

      # ---- Debug (optional) ----
      WINEDEBUG: "-all"
      # WINEDEBUG: "+seh,+error,+warn"

      # ---- Mods (defaults exist in start.sh, but explicitly set here) ----
      BEPINEX_URL: "https://github.com/BepInEx/BepInEx/releases/download/v5.4.23.4/BepInEx_win_x64_5.4.23.4.zip"
      NEBULA_URL: "https://github.com/NebulaModTeam/nebula/releases/download/v0.9.20/Nebula_0.9.20.zip"

      # ---- Goldberg emulator ----
      EXTRA_ZIP_URL: "https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/jobs/4247811310/artifacts/download"
      # EXTRA_FORCE: "1"

      # =========================================================
      # DSP START MODE (choose ONE option!)
      # =========================================================

      # A) Import a save (host path: /data/import/world.dsv) and auto-load it
      # SAVE_IMPORT: "world.dsv"
      # SAVE_IMPORT_LOAD: "1"
      # SAVE_IMPORT_FORCE: "1"

      # B) Load a specific save directly (no import):
      # DSP_LOAD: "world"

      # C) Load the latest save:
      # DSP_LOAD_LATEST: "1"

      # D) Start a new game (peace mode):
      # DSP_NEWGAME_SEED: "123456"
      # DSP_NEWGAME_STARCOUNT: "64"
      # DSP_NEWGAME_RESOURCE_MULT: "1.0"

      # E) Start a new game using Nebula config:
      DSP_NEWGAME_CFG: "1"

      # F) Start a new game with vanilla defaults:
      # DSP_NEWGAME_DEFAULT: "1"

      # Optional: set UPS (5–240)
      # DSP_UPS: "60"

      # Optional: force Steam update on every start
      # FORCE_UPDATE: "1"

    volumes:
      # Everything is persistent
      - ./data:/data

    restart: unless-stopped

```
```bash
docker logs -f dsp_nebula_server
```
Follow the container logs in real time to see the SteamCMD login process and verify whether authentication and game installation succeed or fail.
