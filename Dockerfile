# Dockerfile (Ubuntu 24.04; Steam-Logik bleibt in start.sh)
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Spart Platz beim Build
RUN printf '%s\n' 'Binary::apt::APT::Keep-Downloaded-Packages "false";' > /etc/apt/apt.conf.d/99no-cache

# --- APT / Signaturen fixen: Keyring bootstrap OHNE apt-get update ---
# 1) Sources auf HTTP stellen (hilft bei Umgebungen mit TLS/CA-Problemen beim ersten apt)
RUN set -eux; \
    if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then \
      sed -i 's|https://|http://|g' /etc/apt/sources.list.d/ubuntu.sources; \
    fi; \
    if [ -f /etc/apt/sources.list ]; then \
      sed -i 's|https://|http://|g' /etc/apt/sources.list; \
    fi

# 2) Ubuntu Keyring direkt laden und installieren (damit InRelease Signaturen wieder passen)
ADD http://archive.ubuntu.com/ubuntu/pool/main/u/ubuntu-keyring/ubuntu-keyring_2023.11.28.1build1_all.deb /tmp/ubuntu-keyring.deb
RUN set -eux; \
    dpkg -i /tmp/ubuntu-keyring.deb || true; \
    rm -f /tmp/ubuntu-keyring.deb

# 3) Basispakete + Universe (Wine meta package lives there)
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      software-properties-common \
      ca-certificates curl wget unzip xz-utils \
      gnupg dirmngr \
      bash coreutils findutils procps \
      xvfb xauth \
    ; \
    add-apt-repository -y universe; \
    update-ca-certificates; \
    rm -rf /var/lib/apt/lists/*

# --- Wine + 32-bit deps (Ubuntu 24.04 / noble) ---
# Install 'wine' meta-package so /usr/bin/wine exists.
RUN set -eux; \
    dpkg --add-architecture i386; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      wine \
      wine64 \
      wine32 \
      wine32-preloader \
      libc6:i386 \
      libstdc++6:i386 \
      libgcc-s1:i386 \
      winbind \
      cabextract \
      libnss3 \
      libasound2t64 \
      libgl1 \
      libx11-6 libxext6 libxcursor1 libxrandr2 libxinerama1 libxi6 libxrender1 \
      libgtk-3-0t64 \
      libglib2.0-0t64 \
    ; \
    rm -rf /var/lib/apt/lists/*

# Sanity check: only verify binaries exist (don't execute them during build)
RUN set -eux; \
    test -x /usr/bin/wine; \
    test -x /usr/bin/wine64 || true; \
    command -v wine; \
    command -v wine64 || true

# --- SteamCMD (offizieller Tarball) ---
RUN set -eux; \
    mkdir -p /opt/steamcmd; \
    curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
      | tar -xz -C /opt/steamcmd; \
    chmod +x /opt/steamcmd/steamcmd.sh; \
    chmod +x /opt/steamcmd/linux32/steamcmd /opt/steamcmd/linux64/steamcmd || true; \
    printf '%s\n' '#!/bin/sh' 'exec /opt/steamcmd/steamcmd.sh "$@"' > /usr/local/bin/steamcmd; \
    chmod +x /usr/local/bin/steamcmd

# Defaults (damit start.sh ohne extra config läuft)
ENV \
  STEAM_APP_ID="1366540" \
  STEAM_INSTALL_DIR="/opt/dsp" \
  SERVER_PORT="8469" \
  WINEPREFIX="/root/.wine" \
  WINEDEBUG="-all" \
  BEPINEX_URL="https://github.com/BepInEx/BepInEx/releases/download/v5.4.23.4/BepInEx_win_x64_5.4.23.4.zip" \
  NEBULA_URL="https://github.com/NebulaModTeam/nebula/releases/download/v0.9.19/Nebula_0.9.19.zip" \
  GAME_ARGS="-batchmode -nographics -nebula-server"

# Startscript
COPY start.sh /start.sh
COPY startgame.sh /startgame.sh
RUN chmod +x /start.sh /startgame.sh

WORKDIR /root
EXPOSE 8469/tcp
ENTRYPOINT ["/start.sh"]
