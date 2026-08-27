# syntax=docker/dockerfile:1
ARG TC_TAG=latest

FROM jetbrains/teamcity-server:${TC_TAG}
ARG TARGETPLATFORM
USER root

# Installs the mkcert root CA from the `certs` named build context (declared in docker-compose.yml)
COPY --from=certs . /tmp/certs/
RUN <<EOF
set -e
if [ ! -f /tmp/certs/docker-host-mkcert-rootCA.crt ]; then
  echo "" >&2
  echo "ERROR: certs/docker-host-mkcert-rootCA.crt is missing." >&2
  echo "" >&2
  echo "Generate this lab's TLS material, then re-run the build:" >&2
  echo "    macOS/Linux:  ./scripts/setup-certs.sh" >&2
  echo "    Windows:      pwsh ./scripts/setup-certs.ps1" >&2
  echo "" >&2
  exit 1
fi
cp /tmp/certs/docker-host-mkcert-rootCA.crt /usr/local/share/ca-certificates/
rm -rf /tmp/certs
update-ca-certificates
keytool -importcert \
    -alias docker-host-mkcert-rootCA \
    -file /usr/local/share/ca-certificates/docker-host-mkcert-rootCA.crt \
    -cacerts \
    -storepass changeit \
    -noprompt \
    -trustcacerts
EOF

# Optional tooling: debugging conveniences, safe to delete
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        fd-find \
        iproute2 \
        iputils-ping  \
        jq \
        neovim \
        ripgrep \
        wget && \
    rm -rf /var/lib/apt/lists/*

# Install and configure Yazi. Optional, safe to delete
RUN echo "Platform is $TARGETPLATFORM" \
    && VERSION=$(curl -s https://api.github.com/repos/sxyazi/yazi/releases/latest | jq -r '.tag_name') \
    && case "$TARGETPLATFORM" in \
        *amd64) YAZI_DISTRO_URL="https://github.com/sxyazi/yazi/releases/download/${VERSION}/yazi-x86_64-unknown-linux-gnu.deb" ;; \
        *arm64) YAZI_DISTRO_URL="https://github.com/sxyazi/yazi/releases/download/${VERSION}/yazi-aarch64-unknown-linux-gnu.deb" ;; \
    esac \
    && curl -L -o /tmp/yazi.deb $YAZI_DISTRO_URL
RUN apt-get update && apt-get install -y \
    /tmp/yazi.deb \
    && rm -rf /var/lib/apt/lists/* \
    && rm /tmp/yazi.deb
RUN <<EOF
mkdir -p /root/.config/yazi/ /home/tcuser/.config/yazi/
cat << 'EOT' | tee -a /root/.config/yazi/yazi.toml /home/tcuser/.config/yazi/yazi.toml > /dev/null
[mgr]
show_hidden = true
EOT
EOF

# Yazi Bash profile setup
RUN <<EOF
cat << 'EOT' | tee -a /root/.bashrc /home/tcuser/.bashrc > /dev/null
# Yazi: change directory to the one selected in Yazi
# Use `y` instead of `yazi` to start, and press `q` to quit, you'll see the CWD changed. Sometimes, you don't want to change, press `Q` to quit.
function y() {
  local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
  yazi "$@" --cwd-file="$tmp"
  IFS= read -r -d '' cwd < "$tmp"
  [ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
  rm -f -- "$tmp"
}
EOT
EOF

# Create fd symlink
RUN ln -s /usr/bin/fdfind /usr/local/bin/fd

# Restore file ownership after Yazi installation
RUN chown -R tcuser /home/tcuser

USER tcuser
