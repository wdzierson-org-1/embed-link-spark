# Hosted quality audit worker

A Node 24 supervisor runs one bounded Hermes audit for each authenticated wake. Supabase owns jobs, leases, retries and scheduling. The Sprite does not run a cron scheduler. The initial pilot audits captured snapshots with **no tools**; web research is not enabled or verified.

The pilot compares text snapshots only. It does not inspect image pixels or fetch current pages, so image correctness and live freshness remain unverified.

## Runtime and boundaries

- Hermes is pinned to [v0.21.6](https://github.com/NousResearch/hermes-agent/tree/v0.21.6), commit `818c13be1dc4fd28987e1e881a9408224afd4535`.
- The supervisor runs as root so it can spawn Hermes with a separate `stash-hermes` UID/GID and no supplementary groups. The child receives an explicit environment allowlist, a fresh home/profile and no supervisor tokens.
- Each child receives only its short-lived lease token as `OPENAI_API_KEY`. Its `OPENAI_BASE_URL` points to the fenced quality-model proxy for that job. No standing model-provider credential belongs on the Sprite.
- Provider is explicitly `openai-api`; the pilot model is `gpt-4.1`. The template pins `model.api_mode: chat_completions`, matching the proxy route; this provider otherwise defaults to the Responses API. No extra API-mode environment override is needed. The backend proxy independently enforces its model and spending limits.
- The runner selects the recognized `all` toolset and the template disables `agent.disabled_toolsets: [all]`, yielding zero tools. Do not substitute `--toolsets none`: that unrecognized name prints a non-JSON warning before the JSONL stream in this pinned release.
- A job allows at most six turns and an 80-second Hermes budget, within the supervisor's 90-second job deadline. The supervisor sends process-group SIGTERM, then SIGKILL after 1.5 seconds if needed. Hermes' own `--run-budget` is cooperative and does not replace that timeout.
- Memory, user profiles, background review and the skill curator are disabled. The root-owned config template is copied into each fresh profile. Normal exits and timeout handling remove the attempt workspace. A crash can leave a workspace behind. Startup removes only recognized, child-owned attempt directories and refuses to start while any process still uses the child UID; later attempts never reuse an old home as memory.

This is Unix UID isolation, not a container or a network sandbox. Keep the Sprite dedicated to this service.

## Installation

Requirements: an existing private Linux Sprite, root/sudo access, Git, `/usr/bin/flock`, bootstrap Python 3.11–3.14, and a root-owned Node **24** executable (`/.sprite/bin/node` on the pilot). Hermes PM provisions its exact locked Python runtime; the host's Python version does not select the agent runtime. Download access to the release's pinned artifacts and Python dependencies is required.

1. Place the official Hermes repository at `/opt/stash/hermes`, owned by root, at the exact commit above. The scripts refuse a mismatched revision or tracked changes; they do not reset or replace an existing checkout.
2. Copy this service directory to the Sprite, including all `.mjs` modules.
3. Run from the copied directory:

   ```sh
   sudo bash bootstrap-hermes.sh
   sudo bash install.sh
   ```

   The bootstrap uses the release's [PM install command](https://github.com/NousResearch/hermes-agent/blob/v0.21.6/pm/cli.py) and excludes the optional browser packages. PM owns the environment location under `/opt/stash/hermes-state`; `install.sh` resolves it through `pm.environments.selected_venv`. Do not substitute a guessed `.venv` path or mutate the environment with raw pip/uv. See [official package management](https://hermes-agent.nousresearch.com/docs/reference/package-management).

4. Provision `/etc/stash-quality/worker.env` as a regular **root:root 0600** file. Use Node env-file syntax, not shell commands. Required values:

   ```dotenv
   QUALITY_API_URL=https://PROJECT.supabase.co/functions/v1/quality-worker
   QUALITY_MODEL_BASE_URL=https://PROJECT.supabase.co/functions/v1/quality-model
   QUALITY_WORKER_TOKEN=PROVISION_A_RANDOM_32_TO_256_CHARACTER_TOKEN
   QUALITY_WAKE_TOKEN=PROVISION_A_DIFFERENT_RANDOM_32_TO_256_CHARACTER_TOKEN
   ```

   Provision the matching tokens in the backend through its normal secret mechanism. Do not add `OPENAI_API_KEY` or a Supabase service-role credential to this file. The installer preserves existing `worker.env` contents.

5. Register the service from the Sprite account, using the [documented service command](https://docs.fly.io/sprites/working-with-sprites#wake-up-behavior):

   ```sh
   /.sprite/bin/sprite-env services create stash-quality \
     --cmd /usr/bin/sudo --args /opt/stash/quality-agent/start.sh \
     --http-port 8080 --no-stream
   ```

   This requires the Sprite account's passwordless sudo permission. If a service with that name already exists, inspect and update it through the Sprite service controls; do not create a second worker. Verify `/run` rejects unauthenticated requests before making the HTTP URL reachable by Supabase. The pilot uses a public HTTP route with application-token authentication; Sprite management/exec access remains account-authenticated. Do not copy the Fly account token into Stash or Hermes.

6. Verify `GET /health` and an authenticated `POST /run` through the backend dispatcher. A wake contains no prompts or job IDs. Check that an idle queue returns idle before authorizing a model-backed pilot run.

### Installed layout

| Path | Purpose |
| --- | --- |
| `/opt/stash/hermes` | Pinned, root-owned Hermes source |
| `/opt/stash/hermes-tools` | PM-managed pinned tool/Python runtime |
| `/opt/stash/hermes-state` | PM environment state and generations |
| `/opt/stash/quality-agent` | Root-owned supervisor modules and launcher |
| `/etc/stash-quality/worker.env` | Root-only supervisor URLs and tokens |
| `/etc/stash-quality/runtime.env` | Root-only fixed runtime settings |
| `/etc/stash-quality/hermes-config.yaml` | Root-only config template |
| `/var/lib/stash-quality/jobs` | Root-owned 0711 parent; per-attempt directories are child-owned 0700 |

`runtime.env` fixes `NODE_ENV=production`, `PORT=8080`, `HERMES_EXECUTABLE`, `HERMES_UID`, `HERMES_GID`, `HERMES_MODEL`, `HERMES_PROVIDER`, `HERMES_CONFIG_TEMPLATE` and `QUALITY_JOBS_DIR`. It takes precedence over `worker.env`. `start.sh` clears the inherited environment before Node reads either file and holds an exclusive `flock` for the supervisor's lifetime, serializing startup and cleanup.

## HTTP and lifecycle

`GET /health` reports readiness, busy state and `audit_only` mode. Readiness checks configuration and paths; it does not prove that the model proxy or a paid model call works.

`POST /run` requires `Authorization: Bearer QUALITY_WAKE_TOKEN`. It holds the HTTP connection while the job runs, allows one active job, and rejects concurrent wakes. Disconnecting the owning request cancels the attempt. It heartbeats the Supabase lease every 20 seconds and submits the fenced result through the worker API.

[Sprite documentation](https://docs.fly.io/sprites/working-with-sprites#idle-detection) lists open TCP connections as activity and says processes do not survive sleep; registered Services restart on wake. Holding the request supports the documented activity model. Neither an in-memory background job nor a periodic outbound heartbeat is a documented guarantee against sleep. Lease expiry remains necessary for crash/sleep recovery.

## Verification

Local checks: `bash -n bootstrap-hermes.sh install.sh start.sh` and `node --test *.test.mjs` (Node 24). Before activating a deployment, verify the resolved Hermes executable's `--help` under `stash-hermes`, including traversal of its Python interpreter path. Do not treat a successful root launch as proof that the child can launch.

The scripts and unit tests do not by themselves verify Sprite service registration, proxy authentication, real model output or web research. Record those deployment checks separately. The [release's JSONL emitter](https://github.com/NousResearch/hermes-agent/blob/v0.21.6/hermes_cli/stream_json.py) is the protocol source; stdout is parsed as records and only a successful terminal `result` is accepted.
