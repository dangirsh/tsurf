# Phase 35 Research: Unified Messaging Bridge

Research completed 2026-02-27. Answers the question: "What do I need to know to PLAN this phase well?"

---

## 1. Repo Split Decision

### What Needs Custom Code vs. Pure NixOS Config

| Component | Type | Where |
|-----------|------|-------|
| Conduit homeserver | NixOS module config only | neurosys `modules/matrix.nix` |
| mautrix-telegram bridge | NixOS module config only | neurosys `modules/matrix.nix` |
| mautrix-whatsapp bridge | NixOS module config only | neurosys `modules/matrix.nix` |
| mautrix-signal bridge | NixOS module config only | neurosys `modules/matrix.nix` |
| Bridge registration YAML | Auto-generated at first start, then pasted into Conduit admin room | One-time manual step |
| AI read bot | Custom Python (~100-150 lines) using matrix-nio | **Separate repo** |
| Historical ingest scripts | Custom Python (3 scripts, ~100-200 lines each) | **Separate repo** |
| Spacebot LanceDB integration | API calls to Spacebot's ingest endpoint or direct LanceDB writes | **Same separate repo** |

### Recommendation: Single New Repo `dangirsh/matrix-bridge-tools`

**Rationale:** The AI read bot and historical ingest scripts are custom code that will evolve independently of NixOS config. They share a common dependency (matrix-nio for the bot, Spacebot LanceDB format for ingest output). A single repo keeps them together.

**Repo contents:**
```
matrix-bridge-tools/
  bot/
    reader.py          # matrix-nio sync bot, forwards messages to Spacebot
  ingest/
    telegram.py        # Telegram JSON export -> Spacebot LanceDB
    signal.py          # signalbackup-tools output -> Spacebot LanceDB
    whatsapp.py        # WhatsApp .txt export -> Spacebot LanceDB
  pyproject.toml       # Python project with matrix-nio dependency
  flake.nix            # Optional: Nix package for the bot
```

**How neurosys pulls it in:**

Two options, depending on how the bot is deployed:

- **Option A (repos.nix clone, preferred for simplicity):** Clone to `/data/projects/matrix-bridge-tools` via repos.nix. The AI bot runs as a systemd service with `ExecStart` pointing to the Python script in the cloned repo. Ingest scripts are run manually one-time. This matches the `home-assistant-config` pattern.

- **Option B (flake input):** Add as flake input with `flake = false` (like automaton), build a Python package via `buildPythonApplication`, and run as a systemd service. More Nix-native but heavier for ~100-line scripts.

**Recommendation: Option A.** The bot is simple enough that a repos.nix clone + `writePython3Bin` or direct `python3 reader.py` exec is sufficient. No need for Nix packaging of a few small Python scripts. This matches the home-assistant-config pattern (config repo cloned at activation, referenced by the NixOS module).

### Precedent Comparison

| Existing repo | Integration pattern | Why |
|---|---|---|
| home-assistant-config | repos.nix clone, referenced by HA module | Config files only, no build step |
| automaton | flake input + buildNpmPackage + NixOS module | Complex Node.js app with native addons |
| parts, claw-swap | flake inputs with NixOS modules | Full service deployments with sops |

The matrix-bridge-tools repo is closest to home-assistant-config: simple code that doesn't need a Nix build step.

---

## 2. NixOS Module Availability (Corrected)

**Key correction from phase description:** The phase description stated "mautrix-telegram - package only (no NixOS module)." This is WRONG. All three bridges have full NixOS modules in nixpkgs (nixos-25.11):

| Service | NixOS Module | Package | Module Location |
|---------|-------------|---------|-----------------|
| Conduit | `services.matrix-conduit` | `matrix-conduit` | Full module, 6 options |
| mautrix-telegram | `services.mautrix-telegram` | `mautrix-telegram` | Full module, 6 options |
| mautrix-whatsapp | `services.mautrix-whatsapp` | `mautrix-whatsapp` | Full module, 6 options |
| mautrix-signal | `services.mautrix-signal` | `mautrix-signal` | Full module, 6 options |

All four services have: `enable`, `package`, `settings`, `environmentFile`, `serviceDependencies`, `registerToSynapse`.

**Implication:** No manual appservice config needed. All three bridges can be declared purely in Nix. The `registerToSynapse` option won't work with Conduit (Synapse-specific), but registration YAML is auto-generated and only needs one-time paste into Conduit admin room.

Additional packages confirmed in nixpkgs:
- `signal-cli` - Signal CLI client (used by mautrix-signal)
- `signalbackup-tools` - Signal Android backup decryption
- `python3Packages.matrix-nio` - Python Matrix client library (for the AI read bot)

---

## 3. Conduit + mautrix Bridge Wiring

### Conduit Appservice Registration Sequence

Conduit does NOT use config files for appservice registration. It uses admin room commands.

**Exact sequence:**

1. Deploy Conduit via `services.matrix-conduit`
2. Register the first user (becomes admin automatically) — either via `allow_registration = true` temporarily or via `registration_token`
3. Join the `#admins:your.server.name` room (auto-created)
4. Start each bridge (mautrix-telegram, mautrix-whatsapp, mautrix-signal)
5. Each bridge auto-generates `registration.yaml` at first start (at `/var/lib/mautrix-*/registration.yaml` on NixOS)
6. Read the contents of each `registration.yaml`
7. In the admin room, send: `@conduit:your.server.name: register-appservice` followed by the YAML in a code block
8. Verify with: `@conduit:your.server.name: list-appservices`

**No Conduit restart required.** The bridge starts processing immediately.

### Python Bridge Gotcha (mautrix-telegram)

mautrix-telegram is a Python-based bridge. Per mautrix docs: "you have to register the bridge bot account manually when using Python-based bridges (Telegram or Google Chat) with Conduit."

**Manual bot registration workaround:**
```bash
curl -H "Authorization: Bearer <as_token>" \
  -d '{"username": "telegrambot"}' \
  -X POST https://conduit.local/_matrix/client/r0/register?kind=user
```
Where `<as_token>` comes from the generated registration.yaml, and `telegrambot` matches the `bot_username` in the bridge config.

This is only needed for mautrix-telegram. mautrix-whatsapp and mautrix-signal are Go bridges and handle bot registration automatically.

### Automation Opportunity

The registration step is manual (one-time, via Matrix admin room). It cannot be easily automated in NixOS activation scripts because it requires an authenticated Matrix client session. Options:
- Accept it as a one-time manual step (recommended — it happens once per bridge, ever)
- Write a script using matrix-nio to automate it (over-engineering for 3 one-time commands)

---

## 4. AI Read Bot

### Recommended Approach: matrix-nio Python Bot

**Why matrix-nio:**
- In nixpkgs as `python3Packages.matrix-nio`
- Simplest API for reading Matrix room messages
- Handles sync, pagination, and auth transparently
- ~50-100 lines for a read-only message forwarder

**Why NOT other approaches:**
- Direct Conduit RocksDB/SQLite query: Conduit uses RocksDB by default, not trivially queryable. Also couples the bot to Conduit's internal schema.
- HTTP poller (raw CS API): More code than matrix-nio for the same result, no advantage.
- Matrix-commander/simplematrixbotlib: Extra dependencies with no benefit over matrix-nio.

### Minimal Bot Implementation (Sketch)

```python
import asyncio
from nio import AsyncClient, RoomMessageText

async def main():
    client = AsyncClient("http://localhost:6167", "@aibot:neurosys.local")
    client.access_token = "<token-from-sops>"
    client.user_id = "@aibot:neurosys.local"
    client.device_id = "NEUROSYS_BOT"

    # Forward new messages to Spacebot's ingest API
    async def on_message(room, event):
        # POST to Spacebot's /api/ingest or write directly to LanceDB
        pass

    client.add_event_callback(on_message, RoomMessageText)
    await client.sync_forever(timeout=30000)

asyncio.run(main())
```

**Bot user creation:** Register `@aibot:neurosys.local` on Conduit (one-time), then invite it to all bridged rooms. The bot joins automatically via auto-join or manual join command.

**Integration with Spacebot:** Two options:
1. HTTP POST to Spacebot's API (if it has an ingest endpoint)
2. Direct write to LanceDB directory at `/var/lib/spacebot/` (if the bot has filesystem access)

Option 1 is cleaner (decoupled). Need to check if Spacebot exposes an ingest API.

---

## 5. Port Assignments

| Service | Default Port | NixOS Setting | Add to internalOnlyPorts |
|---------|-------------|---------------|--------------------------|
| Conduit | 6167 (NixOS default 8000, override to 6167) | `services.matrix-conduit.settings.global.port` | YES: `"6167" = "matrix-conduit"` |
| mautrix-telegram | 29317 | `services.mautrix-telegram.settings.appservice.port` | YES: `"29317" = "mautrix-telegram"` |
| mautrix-whatsapp | 29318 | `services.mautrix-whatsapp.settings.appservice.port` | YES: `"29318" = "mautrix-whatsapp"` |
| mautrix-signal | 29328 | `services.mautrix-signal.settings.appservice.port` | YES: `"29328" = "mautrix-signal"` |

**Note on Conduit port:** The Conduit docs say default is 8000 in the package, but the NixOS module may differ. Override to 6167 (conventional Matrix port) to avoid confusion. All ports bind to localhost or are on trustedInterfaces only. No reverse proxy needed since this is Tailscale-only (no federation, no public access).

**Conduit config recommendation:**
- `address = "0.0.0.0"` (bind all interfaces, Tailscale access like other services)
- `port = 6167`
- `allow_federation = false` (private hub, no federation needed)
- `allow_registration = false` (register users manually via token)
- `database_backend = "rocksdb"` (recommended by Conduit docs)

---

## 6. mautrix-signal libsignal Constraint

**Confirmed:** mautrix-signal v0.7.3+ (libsignal v0.62.0+) is incompatible with `MemoryDenyWriteExecute=true`.

**Impact:** The NixOS mautrix-signal module may set systemd hardening by default. Need to override:

```nix
systemd.services.mautrix-signal.serviceConfig = {
  MemoryDenyWriteExecute = false;
};
```

**Risk assessment:** This relaxes one systemd sandbox constraint for the mautrix-signal service only. The service still runs as a dedicated system user with other hardening in place. This is a documented upstream requirement, not a neurosys-specific weakness.

**Document as accepted risk** with a `@decision` annotation in the module.

---

## 7. Secret Count and Names

### New sops secrets needed (in `secrets/neurosys.yaml`)

| Secret Name | Purpose | Source | Notes |
|-------------|---------|--------|-------|
| `telegram-api-id` | Telegram API ID | https://my.telegram.org/apps | Numeric, obtain once |
| `telegram-api-hash` | Telegram API hash | https://my.telegram.org/apps | Hex string, obtain once |
| `matrix-registration-token` | Conduit user registration | Generate random string | One-time user creation |
| `matrix-bot-token` | AI read bot access token | Created after bot user registration on Conduit | Matrix access token for @aibot |

**Total: 4 new sops secrets.**

### Secrets NOT needed (clarifications)

- **mautrix as_token / hs_token:** Auto-generated by bridges at first start, stored in `/var/lib/mautrix-*/registration.yaml`. These are NOT sops secrets — they're generated files owned by the service user.
- **Signal phone number:** Not a secret, just a config value. But the Signal registration/linking process is interactive (QR code scan) — it happens via bridge commands after deployment.
- **WhatsApp pairing code:** Not a persistent secret. WhatsApp linking is also interactive (QR code scan via bridge command). Session data is stored in the bridge's database, not as a separate secret.
- **Telegram bot token:** Optional, only needed for relay bot mode. Not needed for personal puppeting (which is our use case).

### Environment file pattern

Each bridge uses `environmentFile` for secrets. Following the spacebot pattern:

```nix
sops.templates."mautrix-telegram-env" = {
  content = ''
    MAUTRIX_TELEGRAM_APPSERVICE_AS_TOKEN=generate
    MAUTRIX_TELEGRAM_APPSERVICE_HS_TOKEN=generate
    MAUTRIX_TELEGRAM_TELEGRAM_API_ID=${config.sops.placeholder."telegram-api-id"}
    MAUTRIX_TELEGRAM_TELEGRAM_API_HASH=${config.sops.placeholder."telegram-api-hash"}
  '';
  owner = "mautrix-telegram";
  mode = "0400";
};
```

**Note:** Verify exact environment variable names by checking the NixOS module's `environmentFile` documentation. mautrix bridges use a specific naming convention for environment variable overrides of config values.

---

## 8. Historical Ingest Pipeline

### Telegram (JSON export)

**Export source:** Telegram Desktop > Settings > Advanced > Export Telegram Data > Format: JSON

**JSON structure:**
```json
{
  "chats": {
    "list": [
      {
        "name": "Contact Name",
        "type": "personal_chat",
        "id": 12345,
        "messages": [
          {
            "id": 1,
            "type": "message",
            "date": "2024-01-15T10:30:00",
            "date_unixtime": "1705312200",
            "from": "Contact Name",
            "from_id": "user12345",
            "text": "Hello!",
            "reply_to_message_id": null,
            "photo": "photos/photo_1.jpg",
            "media_type": "sticker"
          }
        ]
      }
    ]
  }
}
```

**Key fields:** `id`, `date`/`date_unixtime`, `from`, `from_id`, `text` (can be string or list of text entities), `type`, `media_type`, `photo`/`file`

**Complexity:** LOW. Straightforward JSON parsing. The `text` field being either a string or a list (with formatting entities) is the only gotcha — need to flatten formatted text segments into plain text.

**Estimated ingest script:** ~80 lines Python

### Signal (Android backup)

**Export source:** Signal Android > Settings > Chats > Chat backups > Create backup (30-digit passphrase)

**Tool:** `signalbackup-tools` (confirmed in nixpkgs)

**Decryption process:**
```bash
signalbackup-tools signal-backup.backup <30-digit-passphrase> --output /tmp/signal-export/
```

**Output format:** Decrypted directory with:
- `database.sqlite` — All messages, contacts, threads
- `attachments/` — Media files
- Message schema: `sms` and `mms` tables with `body`, `date`, `address` (phone number), `thread_id`

**Complexity:** MEDIUM. Need to query SQLite, join `sms`/`mms` tables with `recipient` table to get contact names, handle thread grouping.

**Estimated ingest script:** ~150 lines Python (SQLite queries + data transformation)

### WhatsApp (.txt export)

**Export source:** WhatsApp > Chat > More options > Export chat > Without media (or with media as .zip)

**Text format:**
```
02/09/2025, 8:34 PM - John: Don't forget to bring the documents tomorrow!
02/09/2025, 8:35 PM - Steve: Sure thing, see you at 10.
02/09/2025, 8:36 PM - John: <Media omitted>
```

**Format:** `MM/DD/YYYY, H:MM AM/PM - Sender: Message text`

**Gotchas:**
- Timestamp format varies by locale (DD/MM vs MM/DD, 12h vs 24h)
- Multi-line messages: continuation lines don't have the timestamp prefix
- System messages (e.g., "Messages and calls are end-to-end encrypted") don't have a sender
- Media attachments: `<Media omitted>` or filename references

**Complexity:** LOW-MEDIUM. Regex parsing with locale handling.

**Estimated ingest script:** ~120 lines Python

### Ingest Target: Spacebot LanceDB

All three scripts need to write to Spacebot's LanceDB. Need to determine:
1. Does Spacebot expose an HTTP ingest endpoint? (Check API docs / source)
2. If not, can we write directly to the LanceDB directory at `/var/lib/spacebot/`?
3. What's the expected document schema for LanceDB entries? (text, metadata fields, embedding generation)

**This is an open question for Plan 35-03.** The ingest scripts' output format depends on Spacebot's data model.

---

## 9. Conduit Configuration Details

### Recommended `services.matrix-conduit` config

```nix
services.matrix-conduit = {
  enable = true;
  settings.global = {
    server_name = "neurosys.local";  # Internal-only, not a real domain
    address = "0.0.0.0";
    port = 6167;
    database_backend = "rocksdb";
    allow_registration = false;       # Use registration_token for manual setup
    allow_federation = false;         # Private hub, no external federation
    allow_encryption = true;          # E2E for Matrix clients (not bridges)
    trusted_servers = [];             # No federation, no trusted servers needed
  };
};
```

**server_name choice:** Since federation is disabled and this is Tailscale-only, `neurosys.local` or `neurosys` works. No DNS/TLS needed.

**Memory footprint:** Conduit uses ~32MB RAM baseline. With 3 bridges and minimal traffic, expect ~100-150MB total for the entire stack.

---

## 10. Module Structure Recommendation

All Matrix-related NixOS config goes in a single `modules/matrix.nix` file. This follows the project convention of one module per concern and keeps the bridge config co-located.

```nix
# modules/matrix.nix
# @decision MTX-01: Single module for Conduit + all mautrix bridges
# @decision MTX-02: Federation disabled, Tailscale-only access
# @decision MTX-03: mautrix-signal MemoryDenyWriteExecute=false (libsignal JIT requirement)
# @decision MTX-04: E2E encryption breaks at bridge by design (self-hosted mitigates trust)
# @decision MTX-05: WA account detection/disconnection accepted risk (documented)
{ config, ... }: {
  services.matrix-conduit = { ... };
  services.mautrix-telegram = { ... };
  services.mautrix-whatsapp = { ... };
  services.mautrix-signal = { ... };
  systemd.services.mautrix-signal.serviceConfig.MemoryDenyWriteExecute = false;
  # AI read bot systemd service (points to cloned repo script)
  systemd.services.matrix-reader-bot = { ... };
}
```

Add to `modules/default.nix`:
```nix
imports = [ ... ./matrix.nix ];
```

Add to `networking.nix` `internalOnlyPorts`:
```nix
"6167" = "matrix-conduit";
"29317" = "mautrix-telegram";
"29318" = "mautrix-whatsapp";
"29328" = "mautrix-signal";
```

---

## 11. Deployment Sequence

### Plan 35-01 (Conduit + mautrix-telegram)

1. Add secrets: `telegram-api-id`, `telegram-api-hash`, `matrix-registration-token` to sops
2. Create `modules/matrix.nix` with Conduit + mautrix-telegram config
3. Add ports to `internalOnlyPorts` in networking.nix
4. Deploy (`scripts/deploy.sh`)
5. Register first Conduit user (admin) via registration token
6. Read auto-generated `/var/lib/mautrix-telegram/telegram-registration.yaml`
7. In Conduit admin room: `register-appservice` + paste YAML
8. Manually register telegram bot user (Python bridge Conduit workaround)
9. In mautrix-telegram DM: `login` -> authenticate with Telegram
10. Verify: Telegram DMs appear as Matrix rooms

### Plan 35-02 (WhatsApp + Signal)

1. Add mautrix-whatsapp and mautrix-signal to matrix.nix
2. Add systemd override for mautrix-signal MemoryDenyWriteExecute
3. Deploy
4. Register both appservices in Conduit admin room
5. Link WhatsApp: `login` in mautrix-whatsapp room (QR code scan)
6. Link Signal: `login` in mautrix-signal room (device linking)

### Plan 35-03 (AI bot + historical ingest)

1. Create `dangirsh/matrix-bridge-tools` repo
2. Implement matrix-nio reader bot
3. Add repo to repos.nix for activation cloning
4. Add `matrix-reader-bot` systemd service to matrix.nix
5. Add `matrix-bot-token` to sops
6. Deploy and verify bot reads bridged messages
7. Write and run one-time ingest scripts for Telegram/Signal/WhatsApp history

---

## 12. Risk Register

| Risk | Severity | Mitigation |
|------|----------|------------|
| WhatsApp account ban/disconnect | MEDIUM | Documented accepted risk. mautrix-whatsapp uses unofficial WA Web protocol. Keep backup of WA data. |
| mautrix-telegram Conduit bot registration | LOW | One-time manual curl command with as_token. Well-documented workaround. |
| Signal device linking breaks | LOW | Re-link via bridge command. Signal allows multiple linked devices. |
| Conduit admin room bootstrapping | LOW | First registered user auto-joins admin room. Registration token prevents unauthorized users. |
| Historical data format variations | LOW | Test ingest scripts with actual exports before deploying. WhatsApp locale handling is the main variable. |
| Spacebot LanceDB schema mismatch | MEDIUM | Need to determine Spacebot's ingest API/schema before writing ingest scripts. This is the biggest unknown for Plan 35-03. |

---

## 13. Open Questions for Planning

1. **Spacebot ingest API:** Does Spacebot expose an HTTP endpoint for ingesting documents into LanceDB? Or must we write directly to the LanceDB directory? This determines the AI bot and ingest script architecture.

2. **Conduit server_name:** What domain/hostname to use? `neurosys.local` works for Tailscale-only. If federation is ever desired later, the server_name is permanent and cannot be changed.

3. **Matrix client for human access:** Will the user also use a Matrix client (Element, etc.) to view bridged messages? If so, which port/URL should it connect to?

4. **Which node:** Should the Matrix stack deploy to `neurosys` (Contabo) or `neurosys-prod` (OVH)? The phase description implies neurosys, but the OVH node has more disk space (400GB vs 350GB).
