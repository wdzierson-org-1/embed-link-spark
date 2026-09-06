# Listing Stash's MCP server in directories

Endpoint: `https://www.gostash.it/mcp` · transport: Streamable HTTP · auth:
OAuth 2.1 with dynamic client registration (Supabase Auth) · read-only.
Discovery documents: `/.well-known/oauth-protected-resource[/mcp]`,
`/.well-known/mcp-server-card` (site root and under `/mcp/.well-known/…`);
registry entry `mcp/server.json`. Spec:
`docs/superpowers/specs/2026-09-05-mcp-server-design.md`.

## 1. Official MCP Registry (registry.modelcontextprotocol.io)

Namespace `it.gostash/stash` is verified by DNS on `gostash.it`.

```bash
brew install mcp-publisher            # or: curl -L https://github.com/modelcontextprotocol/registry/releases/latest/download/mcp-publisher_$(uname -s)_$(uname -m).tar.gz | tar xz
openssl genpkey -algorithm Ed25519 -out ~/.mcp-publisher-gostash.pem
mcp-publisher login dns --domain gostash.it --private-key ~/.mcp-publisher-gostash.pem
# prints a TXT record like:  v=MCPv1; k=ed25519; p=<public key>
# add it to gostash.it's DNS (host: @ / gostash.it), wait for propagation, re-run login if it timed out
cd mcp && mcp-publisher publish
```
Bump `mcp/server.json` `version` on every republish (the registry rejects duplicates).

## 2. Claude connectors directory

Portal: https://claude.ai/admin-settings/directory/submissions/new (needs a
Team or Enterprise organization; individual plans can't submit).

Have ready: server URL `https://www.gostash.it/mcp`; transport Streamable
HTTP; "every user connects to the same URL"; auth mode **OAuth with dynamic
client registration**; documentation URL `https://www.gostash.it/settings`
(Connected agents tab) until a public docs page exists; privacy policy
`https://www.gostash.it/privacy`; support contact; icon `public/icon-512.png`;
name "Stash"; tagline (≤55 chars) "Search what you saved, from any agent";
categories: Productivity, Knowledge; use cases: recall saved links/notes/
photos/memos; **reads data only**; test account: a dedicated fixture account
with saved items (create one — never Will's account); confirm every tool was
run via MCP Inspector or a custom connector.

The portal syncs tools from the server and groups them by annotation — every
tool already carries `title` + `readOnlyHint: true` / `destructiveHint: false`.

If Anthropic asks for held credentials (`oauth_anthropic_creds`) instead of
DCR, create a confidential client (§5) with redirect
`https://claude.ai/api/mcp/auth_callback` and email its id/secret to
`mcp-review@anthropic.com`.

## 3. ChatGPT

Settings → Apps & Connectors → Advanced → Developer mode → Add custom
connector → URL `https://www.gostash.it/mcp`. ChatGPT requires OAuth + DCR
(present) and the `search`/`fetch` tools (present). Public listing goes
through OpenAI's app submission once available for connectors.

## 4. Editor and desktop clients

- Claude Code: `claude mcp add --transport http stash https://www.gostash.it/mcp`
- Cursor (`~/.cursor/mcp.json`): `{ "mcpServers": { "stash": { "url": "https://www.gostash.it/mcp" } } }`
- VS Code (`mcp.json`): `{ "servers": { "stash": { "type": "http", "url": "https://www.gostash.it/mcp" } } }`
- Windsurf / others: remote server URL `https://www.gostash.it/mcp`; OAuth
  sign-in opens automatically.
- URL catalogs (Smithery, Glama, PulseMCP, mcp.so): submit the URL; they read
  `/.well-known/mcp-server-card` and `mcp/server.json` where supported.

## 5. Pre-registered (confidential) OAuth clients

For directories that hold a fixed client id/secret. Uses the service-role key —
run from a trusted machine only; the secret is shown once.

```bash
SERVICE_ROLE=<service role key from Supabase dashboard → Project Settings → API>
curl -s -X POST https://uqqsgmwkvslaomzxptnp.supabase.co/auth/v1/admin/oauth/clients \
  -H "apikey: $SERVICE_ROLE" -H "Authorization: Bearer $SERVICE_ROLE" -H "Content-Type: application/json" \
  -d '{"client_name":"Claude (Anthropic-held)","client_uri":"https://claude.ai","redirect_uris":["https://claude.ai/api/mcp/auth_callback"],"grant_types":["authorization_code","refresh_token"],"response_types":["code"],"token_endpoint_auth_method":"client_secret_basic"}'
```
List/revoke: `GET`/`DELETE …/admin/oauth/clients[/<id>]` with the same headers.
