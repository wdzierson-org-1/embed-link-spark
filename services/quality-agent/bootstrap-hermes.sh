#!/usr/bin/env bash
# Prepare the pinned release through its package manager; no model calls.
set -euo pipefail
readonly HERMES_ROOT=/opt/stash/hermes
readonly HERMES_COMMIT=818c13be1dc4fd28987e1e881a9408224afd4535
fail() { printf 'bootstrap-hermes: %s\n' "$*" >&2; exit 1; }
[[ $(uname -s) == Linux && $(id -u) == 0 ]] || fail 'run as root on the Linux Sprite'
[[ -d "$HERMES_ROOT/.git" && ! -L "$HERMES_ROOT" ]] || fail 'provision the official Hermes checkout first'
[[ $(git -C "$HERMES_ROOT" rev-parse HEAD) == "$HERMES_COMMIT" ]] || fail 'Hermes revision does not match v0.21.6'
git -C "$HERMES_ROOT" diff --quiet && git -C "$HERMES_ROOT" diff --cached --quiet || fail 'Hermes has tracked modifications'
[[ $(stat -c %u "$HERMES_ROOT") == 0 ]] || fail 'Hermes checkout must be root-owned'
command -v python3 >/dev/null || fail 'bootstrap Python 3.11 or newer is required'
python3 -c 'import sys; assert (3, 11) <= sys.version_info < (3, 15), sys.version' || fail 'unsupported bootstrap Python'
install -d -m 0755 -o root -g root /opt/stash/hermes-state /opt/stash/hermes-tools
cd "$HERMES_ROOT"
# PM supplies the actual locked Python runtime. The host Python only boots PM.
# The two optional browser packages are unnecessary for this audit-only pilot.
env -i HOME=/root PATH=/usr/local/bin:/usr/bin:/bin \
  HERMES_HOME=/opt/stash/hermes-state HERMES_RUNTIME_DIR=/opt/stash/hermes-tools \
  python3 -m pm.cli install --without agent-browser --without cua-driver
printf 'Hermes package-manager installation finished; run install.sh to verify the executable and install the supervisor.\n'
