#!/usr/bin/env bash
set -euo pipefail
readonly APP=/opt/stash/quality-agent
readonly CONFIG=/etc/stash-quality
fail() { printf 'start: %s\n' "$*" >&2; exit 1; }
[[ $(id -u) == 0 ]] || fail 'supervisor must run as root to drop the child UID/GID'
[[ ! -L "$APP" && $(stat -c %u "$APP") == 0 ]] || fail 'app directory must be root-owned'
[[ ! -L "$CONFIG" && $(stat -c '%u:%a' "$CONFIG") == 0:700 ]] || fail 'configuration directory must be root-owned 0700'
for file in worker.env runtime.env hermes-config.yaml; do
  [[ -f "$CONFIG/$file" && ! -L "$CONFIG/$file" && $(stat -c '%u:%a' "$CONFIG/$file") == 0:600 ]] || fail "$file must be a regular root-owned 0600 file"
done
[[ $("$APP/node" -p 'process.versions.node.split(".")[0]') == 24 ]] || fail 'Node 24 is required'
[[ -x /usr/bin/flock ]] || fail '/usr/bin/flock is required'
[[ ! -L /var/lib/stash-quality && $(stat -c '%u:%a' /var/lib/stash-quality) == 0:711 ]] || fail 'state directory must be root-owned 0711'
if [[ -e /var/lib/stash-quality/service.lock || -L /var/lib/stash-quality/service.lock ]]; then
  [[ -f /var/lib/stash-quality/service.lock && ! -L /var/lib/stash-quality/service.lock && $(stat -c '%u:%a' /var/lib/stash-quality/service.lock) == 0:600 ]] || fail 'service.lock must be a regular root-owned 0600 file'
fi
cd "$APP"
umask 077
# Node parses data files; shell evaluation of secret values is never needed.
# Clear inherited credentials. Fixed runtime settings override worker.env values.
exec /usr/bin/flock --nonblock --no-fork /var/lib/stash-quality/service.lock \
  env -i PATH=/.sprite/bin:/usr/local/bin:/usr/bin:/bin \
  "$APP/node" --env-file="$CONFIG/worker.env" --env-file="$CONFIG/runtime.env" "$APP/server.mjs"
