#!/usr/bin/env sh
# Optional. Records your acceptance of the TeamCity license agreement in
# internal.properties so the setup wizard skips its license page. Run it before
# docker compose up -d, or skip it and accept in the wizard instead.
set -eu

CONFIG=$(CDPATH= cd -- "$(dirname -- "$0")/../services/teamcity/server/data/config" && pwd)
PROPERTY=teamcity.licenseAgreement.accepted
EULA_URL=https://www.jetbrains.com/legal/docs/teamcity/license/

if grep -q "^$PROPERTY=true" "$CONFIG/internal.properties" 2>/dev/null; then
    echo "License agreement already accepted."
    exit 0
fi

echo "TeamCity requires you to accept its license agreement:"
echo
echo "    $EULA_URL"
echo
printf 'Do you accept it? [y/N] '
read -r answer || answer=

case $answer in
    [yY] | [yY][eE][sS]) ;;
    *)
        echo "Declined. You can accept in the TeamCity setup wizard instead." >&2
        exit 1
        ;;
esac

sed "s|^$PROPERTY=.*|$PROPERTY=true|" "$CONFIG/internal.properties.dist" > "$CONFIG/internal.properties"
echo "Accepted. Now run: docker compose up -d"
