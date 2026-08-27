# syntax=docker/dockerfile:1.4
ARG P4_TAG=26.1

FROM ubuntu:26.04

ARG P4_VERSION=r${P4_TAG:-26.1}
ARG TARGETARCH

ENV P4PORT=1666 \
    P4ROOT=/opt/perforce/servers/master \
    P4USER=p4admin \
    P4PASSWD=SuperSecret123! \
    P4CHARSET=utf8

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates \
    && case "${TARGETARCH}" in \
        "arm64") P4_ARCH="bin.linux26aarch64" ;; \
        "amd64") P4_ARCH="bin.linux26x86_64" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}"; exit 1 ;; \
       esac \
    && echo "Downloading Perforce ${P4_VERSION} for ${P4_ARCH}..." \
    && curl -fsSL "https://cdist2.perforce.com/perforce/${P4_VERSION}/${P4_ARCH}/p4d" -o /usr/local/bin/p4d \
    && curl -fsSL "https://cdist2.perforce.com/perforce/${P4_VERSION}/${P4_ARCH}/p4" -o /usr/local/bin/p4 \
    && chmod +x /usr/local/bin/p4d /usr/local/bin/p4 \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p "${P4ROOT}"

# Embedded Entrypoint Script
COPY <<-"EOF" /usr/local/bin/entrypoint.sh
#!/bin/bash
set -e

# Automatically initialize ONLY if the volume is uninitialized
if [ ! -f "${P4ROOT}/db.counters" ]; then
    echo "Initializing a fresh Perforce server in ${P4ROOT}..."

    # 1. Enable Unicode
    p4d -r "${P4ROOT}" -xi

    # 2. Start p4d temporarily in background
    p4d -r "${P4ROOT}" -p "${P4PORT}" &
    P4D_PID=$!

    echo "Waiting for background p4d to start..."
    while ! env P4PASSWD="" p4 -u "${P4USER}" info -s >/dev/null 2>&1; do sleep 1; done

    # 3. Create initial password (bypassing pre-existing P4PASSWD env check)
    echo -e "${P4PASSWD}\n${P4PASSWD}" | env P4PASSWD="" p4 -u "${P4USER}" passwd

    # 4. Authenticate and write local ticket
    echo "${P4PASSWD}" | env P4PASSWD="" p4 -u "${P4USER}" login

    # 5. Initialize Protection Table for superuser
    p4 -u "${P4USER}" protect -o | sed "s/super user admin/super user ${P4USER}/g" > /tmp/protect.txt
    p4 -u "${P4USER}" protect -i < /tmp/protect.txt
    rm -f /tmp/protect.txt

    # 6. Lower security level to disable complexity checks, adjust min length, and disable forced resets
    p4 -u "${P4USER}" configure set security=1
    p4 -u "${P4USER}" configure set dm.password.minlength=1
    p4 -u "${P4USER}" configure set dm.user.resetpassword=0

    # 7. Stop temporary bootstrap daemon
    echo "Stopping temporary setup daemon..."
    p4 -u "${P4USER}" admin stop
    wait $P4D_PID

    echo "Initialization complete!"
else
    echo "Existing Perforce database detected. Skipping setup."
fi

echo "Starting Helix Core (p4d) on port ${P4PORT}..."
exec p4d -r "${P4ROOT}" -p "${P4PORT}"
EOF

RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 1666
WORKDIR /opt/perforce/servers/master

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]