#!/usr/bin/env bash
# Moves the `latest` tag onto the teamcity-server and teamcity-agent images built for the
# TC_VERSION in .env.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTENV_FILE="$SCRIPT_DIR/../.env"

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
ok()  { echo -e "${GREEN}✔${NC} $*"; }
err() { echo -e "${RED}✘${NC} $*" >&2; }

if [ $# -gt 0 ]; then
  err "This script takes no arguments (got: $*)"
  exit 2
fi

if [ ! -f "$DOTENV_FILE" ]; then
  err ".env file not found at $DOTENV_FILE"
  exit 1
fi
TC_VERSION=$(grep "^TC_VERSION=" "$DOTENV_FILE" | cut -d= -f2- | cut -d'#' -f1 | tr -d '[:space:]')
if [ -z "$TC_VERSION" ]; then
  err "TC_VERSION is not set in .env"
  exit 1
fi

tag_image_latest() {
  local image=$1
  local base_image=${image%%:*}

  if docker image inspect "$image" > /dev/null 2>&1; then
    ok "Image $image exists locally. Tagging as $base_image:latest"
    docker tag "$image" "$base_image:latest"
  else
    err "Image $image does not exist locally."
    return 1
  fi
}

tag_image_latest "tolache/teamcity-server:${TC_VERSION}" || exit 1
tag_image_latest "tolache/teamcity-agent:${TC_VERSION}"  || exit 1

ok "Successfully tagged both images as latest."
