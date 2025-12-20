# DSP_docker
A Docker image for a DSP multiplayer server

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
