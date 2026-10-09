#!/usr/bin/env bash
# Install this service from a reviewed checkout after bootstrap-hermes.sh.
# Does not start the service, provision credentials, or call a model.
set -euo pipefail
readonly APP=/opt/stash/quality-agent
readonly CONFIG=/etc/stash-quality
readonly HERMES_ROOT=/opt/stash/hermes
readonly COMMIT=818c13be1dc4fd28987e1e881a9408224afd4535
readonly SOURCE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
fail() { printf 'install: %s\n' "$*" >&2; exit 1; }
[[ $(uname -s) == Linux && $(id -u) == 0 ]] || fail 'run as root on the Linux Sprite'
for file in server.mjs supervisor.mjs startup.mjs config.mjs protocol.mjs runner.mjs start.sh hermes-config.yaml; do
  [[ -f "$SOURCE/$file" && ! -L "$SOURCE/$file" ]] || fail "missing service source: $file"
done
[[ -d "$HERMES_ROOT/.git" && ! -L "$HERMES_ROOT" ]] || fail 'pinned Hermes checkout is missing'
[[ $(git -C "$HERMES_ROOT" rev-parse HEAD) == "$COMMIT" ]] || fail 'unexpected Hermes revision'
git -C "$HERMES_ROOT" diff --quiet && git -C "$HERMES_ROOT" diff --cached --quiet || fail 'Hermes has tracked modifications'

node_path=${NODE_BINARY:-/.sprite/bin/node}
[[ -x "$node_path" ]] || fail 'Node 24 is required; set NODE_BINARY to its absolute path'
node_path=$(readlink -f -- "$node_path")
[[ $(stat -c %u "$node_path") == 0 ]] || fail 'Node binary must be root-owned'
(( (8#$(stat -c %a "$node_path") & 8#022) == 0 )) || fail 'Node binary must not be writable by group/others'
[[ $("$node_path" -p 'process.versions.node.split(".")[0]') == 24 ]] || fail 'Node major version must be 24'
[[ -x /usr/bin/flock ]] || fail '/usr/bin/flock is required to serialize service startup'

# PM owns the location. Never guess .venv or edit its facts/generation records.
hermes_venv=$(cd "$HERMES_ROOT" && env -i HOME=/root PATH=/usr/local/bin:/usr/bin:/bin \
  HERMES_HOME=/opt/stash/hermes-state HERMES_RUNTIME_DIR=/opt/stash/hermes-tools \
  python3 -c 'from pathlib import Path; from pm.environments import selected_venv; print(selected_venv(Path.cwd()))')
case "$hermes_venv" in /opt/stash/hermes-state/installs/*/environments/*/venv) ;; *) fail 'unexpected PM environment location' ;; esac
[[ -x "$hermes_venv/bin/hermes" ]] || fail 'run bootstrap-hermes.sh first'
[[ $(stat -c %u "$hermes_venv") == 0 ]] || fail 'Hermes environment must be root-owned'

# Refuse foreign directories or symlinks rather than replacing existing state.
for path in "$APP" "$CONFIG" /var/lib/stash-quality /var/lib/stash-quality/jobs; do
  [[ ! -L "$path" ]] || fail "refusing symlink: $path"
  if [[ -e "$path" ]]; then
    [[ -d "$path" && $(stat -c %u "$path") == 0 ]] || fail "unexpected owner/type: $path"
    (( (8#$(stat -c %a "$path") & 8#022) == 0 )) || fail "directory is writable by group/others: $path"
  fi
done
if [[ -d "$APP" ]]; then
  [[ -f "$APP/install-manifest.json" ]] || fail 'existing app directory has no installation manifest'
  "$node_path" -e 'const m=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); if(m.service!=="stash-quality" || m.hermesCommit!==process.argv[2]) process.exit(1)' "$APP/install-manifest.json" "$COMMIT" || fail 'existing app manifest does not match'
fi
if [[ -e "$CONFIG/worker.env" || -L "$CONFIG/worker.env" ]]; then
  [[ -f "$CONFIG/worker.env" && ! -L "$CONFIG/worker.env" && $(stat -c '%u:%a' "$CONFIG/worker.env") == 0:600 ]] || fail 'worker.env must be a regular root-owned 0600 file'
fi
for path in "$CONFIG/runtime.env" "$CONFIG/hermes-config.yaml" "$APP/install-manifest.json"; do
  [[ ! -L "$path" ]] || fail "refusing symlink: $path"
done

if ! id stash-hermes >/dev/null 2>&1; then
  useradd --system --user-group --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin stash-hermes
fi
hermes_uid=$(id -u stash-hermes)
hermes_gid=$(id -g stash-hermes)
[[ "$hermes_uid" != 0 && "$hermes_gid" != 0 && $(id -G stash-hermes) == "$hermes_gid" ]] || fail 'stash-hermes must be an unprivileged account without supplementary groups'
[[ $(getent passwd stash-hermes | cut -d: -f6-7) == /nonexistent:/usr/sbin/nologin ]] || fail 'existing stash-hermes account has an unexpected home or shell'

install -d -o root -g root -m 0755 "$APP"
install -d -o root -g root -m 0700 "$CONFIG"
install -d -o root -g root -m 0711 /var/lib/stash-quality /var/lib/stash-quality/jobs
for file in "$SOURCE"/*.mjs; do
  [[ "$file" != *.test.mjs ]] || continue
  install -o root -g root -m 0644 "$file" "$APP/$(basename "$file")"
done
install -o root -g root -m 0755 "$SOURCE/start.sh" "$APP/start.sh"
install -o root -g root -m 0600 "$SOURCE/hermes-config.yaml" "$CONFIG/hermes-config.yaml"
ln -sfn -- "$node_path" "$APP/node"
if [[ ! -f "$CONFIG/worker.env" ]]; then
  install -o root -g root -m 0600 /dev/null "$CONFIG/worker.env"
fi
umask 077
cat > "$CONFIG/runtime.env" <<EOF
NODE_ENV=production
PORT=8080
HERMES_EXECUTABLE=$hermes_venv/bin/hermes
HERMES_UID=$hermes_uid
HERMES_GID=$hermes_gid
HERMES_MODEL=gpt-4.1
HERMES_PROVIDER=openai-api
HERMES_CONFIG_TEMPLATE=$CONFIG/hermes-config.yaml
QUALITY_JOBS_DIR=/var/lib/stash-quality/jobs
EOF
"$node_path" -e 'const fs=require("fs"); fs.writeFileSync(process.argv[1], JSON.stringify({service:"stash-quality",hermesTag:"v0.21.6",hermesCommit:process.argv[2],node:process.argv[3],hermesExecutable:process.argv[4]},null,2)+"\n",{mode:0o644})' \
  "$APP/install-manifest.json" "$COMMIT" "$node_path" "$hermes_venv/bin/hermes"
printf 'Installed service files. Provision %s/worker.env (root:root 0600), then register the Sprite service as documented.\n' "$CONFIG"
