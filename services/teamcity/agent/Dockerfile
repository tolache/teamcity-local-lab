# syntax=docker/dockerfile:1
ARG TC_TAG=latest

FROM jetbrains/teamcity-agent:${TC_TAG}
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

# Work around the error `/etc/init.d/docker:62: ulimit: limit setting error (Invalid argument)` when starting Docker: https://forums.docker.com/t/etc-init-d-docker-62-ulimit-error-setting-limit-invalid-argument-problem/139424
RUN sed -i 's/ulimit -Hn 524288/ulimit -n 524288/g' /etc/init.d/docker

# Optional tooling: debugging conveniences, safe to delete
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        dnsutils \
        fd-find \
        iputils-ping \
        jq \
        neovim \
        ripgrep \
        tree \
        wget \
        yq && \
    rm -rf /var/lib/apt/lists/*

# Install PowerShell
RUN echo "Platform is $TARGETPLATFORM" \
    && VERSION=$(curl -s https://api.github.com/repos/PowerShell/PowerShell/releases/latest | jq -r '.tag_name') \
    && case "$TARGETPLATFORM" in \
        *amd64) PS_DISTRO_URL="https://github.com/PowerShell/PowerShell/releases/download/$VERSION/powershell-${VERSION#v}-linux-x64.tar.gz" ;; \
        *arm64) PS_DISTRO_URL="https://github.com/PowerShell/PowerShell/releases/download/$VERSION/powershell-${VERSION#v}-linux-arm64.tar.gz" ;; \
    esac \
    && curl -L -o /tmp/powershell.tar.gz $PS_DISTRO_URL
RUN mkdir -p /opt/microsoft/powershell/7
RUN tar zxf /tmp/powershell.tar.gz -C /opt/microsoft/powershell/7
RUN chmod +x /opt/microsoft/powershell/7/pwsh
RUN ln -s /opt/microsoft/powershell/7/pwsh /usr/bin/pwsh

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
mkdir -p /root/.config/yazi/ /home/buildagent/.config/yazi/
cat << 'EOT' | tee -a /root/.config/yazi/yazi.toml /home/buildagent/.config/yazi/yazi.toml > /dev/null
[mgr]
show_hidden = true
EOT
EOF

# Yazi Bash profile setup
RUN <<EOF
cat << 'EOT' | tee -a /root/.bashrc /home/buildagent/.bashrc > /dev/null
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
RUN chown -R buildagent /home/buildagent

USER buildagent
