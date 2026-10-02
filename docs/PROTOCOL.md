# The Vault — App ↔ Server protocol (v1)

Technical reference. Security rationale: `SECURITY.md`. Behaviour: `SPEC.md`.

## 1. Conventions

- Base URL: `https://<host>`; every endpoint lives under `/v1`. The server itself listens on plain HTTP on `127.0.0.1`;
  TLS is terminated by Tailscale Funnel (or any reverse proxy).
- Request/response bodies are JSON (`Content-Type: application/json; charset=utf-8`) except blob parts.
- Binary values inside JSON are **base64url without padding** (`b64`).
- IDs are UUID v4 strings (lowercase).
- Timestamps are Unix milliseconds (int64), server clock.
- Auth: `Authorization: Bearer <deviceToken>` (base64url, 32 random bytes).
- Every response carries `X-TheVault-Server: <version>`.
- Errors: HTTP status + body `{"error": {"code": "<snake_case>", "message": "<human, English>"}}`.

| Status | Codes (examples) |
|---|---|
| 400 | `bad_request`, `invalid_email`, `invalid_field` |
| 401 | `unauthorized` (missing/unknown/revoked token) |
| 403 | `forbidden` (wrong device status for this call), `device_revoked` |
| 404 | `not_found` |
| 409 | `conflict` (stale `baseRev`), `already_initialized` |
| 410 | `otp_expired`, `approval_expired` |
| 413 | `too_large` |
| 422 | `otp_invalid`, `missing_blob`, `recovery_invalid` |
| 429 | `rate_limited` (with `Retry-After`) |

## 2. Device status

| Status | Meaning | Allowed |
|---|---|---|
| `setup` | OTP ok, account has no vault yet | `GET /v1/me`, `POST /v1/vault/init`, `DELETE /v1/devices/self` |
| `pending` | OTP ok, vault exists, waiting for approval | `GET /v1/me`, approvals (own), recovery, WS (own approval events), `DELETE /v1/devices/self` |
| `active` | full access | everything except `vault/init` and the pending-only calls |
| (revoked) | token deleted | nothing → `401` |

## 3. Endpoints

### 3.1 Health
`GET /v1/health` → `200 {"service":"thevault","version":"1.0.0","time":1730000000000}` (no auth).

### 3.2 Login
`POST /v1/auth/otp/request` `{"email":"a@b.c","locale":"it","deviceName":"MacBook"}` → `202 {}` (also for non-allowed
emails, which get an unusable code so that they behave exactly like allowed ones). `503 mail_failed` if the server could
not send the email.
Rate-limited: 5/hour/email, 30/hour/IP. Resend cooldown 30 s per email (`429` + `Retry-After`).

`POST /v1/auth/otp/verify`
```json
{"email":"a@b.c","code":"123456",
 "device":{"name":"MacBook di Simone","platform":"macos","publicKey":"<b64 32B X25519>"}}
```
→ `200 {"token":"<b64>","deviceId":"<uuid>","userId":"<uuid>","status":"setup"|"pending"}`
Errors: `422 otp_invalid` (with `attemptsLeft`), `410 otp_expired`, `429 rate_limited`.
A user record is created on first successful verification of an allowed email.

`GET /v1/me` →
```json
{"userId":"…","email":"a@b.c",
 "device":{"id":"…","name":"…","platform":"macos","status":"active"},
 "vault":{"initialized":true,"keyCheck":"<b64>"}}
```

### 3.3 Vault initialisation (first device, status `setup`)
`POST /v1/vault/init`
```json
{"keyCheck":"<b64 16B>",
 "recovery":{"salt":"<b64 16B>","opsLimit":2,"memLimit":67108864,"wrap":"<b64 nonce‖ct>"},
 "recoveryAuth":"<b64 32B>"}
```
→ `200 {"status":"active"}`; `409 already_initialized` if another device won the race (client then restarts as `pending`).

### 3.4 Devices (status `active`, except `self`)
- `GET /v1/devices` → `{"devices":[{"id","name","platform","status","createdAt","lastSeenAt","current":bool}]}`
- `PATCH /v1/devices/self` `{"name":"…"}` → `200`
- `DELETE /v1/devices/self` → `204` (log out; any status)
- `DELETE /v1/devices/{id}` → `204` (revoke another device; it receives `device.revoked` if connected)

### 3.5 Approvals
Pending device (D2):
- `POST /v1/approvals` `{"commitment":"<b64 32B>"}` → `201 {"approvalId":"…","expiresAt":…}`
  (replaces any open request of the same device). `429` while the account is in rejection cool-down.
- `GET /v1/approvals/{id}` → current state (see below) — polling fallback when the WS is down.
- `POST /v1/approvals/{id}/reveal` `{"nonce":"<b64 n2>"}` → `200` (only in state `responded`).
- `DELETE /v1/approvals/{id}` → `204` (cancel).

Active device (D1):
- `GET /v1/approvals` → open requests for the account (used on unlock to show pending ones).
- `POST /v1/approvals/{id}/respond` `{"publicKey":"<b64 pk1>","nonce":"<b64 n1>"}` → `200`. First responder wins;
  others get `409` and the request disappears for them (`approval.claimed`).
- `POST /v1/approvals/{id}/approve` `{"box":"<b64>","boxNonce":"<b64 24B>"}` → `200` (only in state `revealed`,
  only by the responding device). D2 becomes `active`.
- `POST /v1/approvals/{id}/reject` → `200`.

Approval object:
```json
{"id":"…","state":"requested|responded|revealed|approved|rejected|expired|cancelled",
 "device":{"id":"…","name":"…","platform":"windows","publicKey":"<b64 pk2>"},
 "commitment":"<b64>","responderPublicKey":"<b64 pk1>|null","responderNonce":"<b64 n1>|null",
 "revealedNonce":"<b64 n2>|null","box":"<b64>|null","boxNonce":"<b64>|null",
 "createdAt":…,"expiresAt":…}
```
Visibility: D2 sees its own request; active devices of the same user see all open requests of that user.
`box` is only returned to D2.

### 3.6 Recovery
- `GET /v1/recovery` (pending) → `{"salt","opsLimit","memLimit","wrap"}`
- `POST /v1/recovery/activate` (pending) `{"recoveryAuth":"<b64>"}` → `200 {"status":"active"}` or
  `422 recovery_invalid`. 5 attempts/hour/account.
- `PUT /v1/recovery` (active) `{"recovery":{…},"recoveryAuth":"<b64>"}` → `200` (new emergency kit).

### 3.7 Records (status `active`)
Record on the wire:
```json
{"id":"<uuid>","rev":1234,"data":"<b64 ciphertext>|null","blobs":["<uuid>",…],
 "deleted":false,"updatedAt":1730000000000,"updatedBy":"<deviceId>"}
```
- `rev` is a per-user, strictly increasing sequence assigned by the server on every write.
- `GET /v1/records?since=<rev>&limit=<n≤1000>` → `{"records":[…],"latest":<rev>,"more":bool}`
  (ordered by `rev`; includes tombstones `deleted:true, data:null`).
- `PUT /v1/records/{id}` `{"baseRev":<rev|0>,"data":"<b64>","blobs":[…]}`
  - `baseRev` must equal the current `rev` of the record (`0` = must not exist yet).
  - → `200 {"rev":<new>,"updatedAt":…}`; `409 conflict` with `{"current":<record>}`;
    `422 missing_blob` if a referenced blob is not complete; `413` if `data` > 1 MiB.
- `DELETE /v1/records/{id}?baseRev=<rev>` → `200 {"rev":<new>}` (permanent delete → tombstone); `409` as above.
  (`baseRev` is a query parameter: some proxies drop bodies on `DELETE`.)

### 3.8 Blobs (status `active`)
Blob ids are generated by the client (UUID v4) so attachments can be added offline.
- `POST /v1/blobs/{id}` `{"size":<total bytes>}` → `201 {"partSize":4194304}` (or `200` with
  `{"receivedParts":[…]}` if the upload already exists — resume).
- `PUT /v1/blobs/{id}/parts/{n}` body: raw bytes (`application/octet-stream`), `n` from 0; every part except the last
  must be exactly `partSize` → `204`.
- `POST /v1/blobs/{id}/complete` `{"parts":<count>,"sha256":"<hex of whole blob>"}` → `200`; `422` on size/hash mismatch.
- `GET /v1/blobs/{id}` → raw bytes; supports `Range` (resumable download); `404` if unknown or incomplete.
- Orphans (complete or incomplete blobs referenced by no record) are garbage-collected after a 24 h grace period,
  so that a conflict copy re-created by another device can still reference them. A record that references a blob
  already collected gets `422 missing_blob`: the client re-uploads it from its local encrypted cache and retries.
- Max blob size: 200 MiB of content (encrypted size is slightly larger; the limit applies to the encrypted size
  with margin: 201 MiB).

### 3.9 Real-time channel
`GET /v1/ws` (WebSocket; `Authorization: Bearer …` header). Server sends JSON text messages; ping every 25 s.

| Event | Payload | To |
|---|---|---|
| `hello` | `{"latest":<rev>,"status":"active"}` | on connect |
| `records.changed` | `{"latest":<rev>,"by":"<deviceId>"}` | active devices of the user |
| `approval.requested` | `{"approval":{…}}` | active devices |
| `approval.responded` | `{"approval":{…}}` | the pending device |
| `approval.revealed` | `{"approval":{…}}` | the responding device |
| `approval.approved` | `{"approval":{…}}` (with `box`) | the pending device |
| `approval.closed` | `{"approvalId":"…","state":"…"}` | everyone else involved (claimed/rejected/expired/cancelled) |
| `devices.changed` | `{}` | active devices |
| `device.revoked` | `{}` | the revoked device, then the socket closes |

Clients treat the WS as a hint: on every `records.changed` (and on connect, and every 60 s when the WS is down)
they pull with `GET /v1/records?since=`.

## 4. Client sync algorithm

Local tables: `records` (last known server state), `pending` (local writes not yet acknowledged), `meta` (cursor),
`blobs` (local encrypted files + upload state).

1. **Local write**: encrypt → upsert into `pending (id, baseRev = records.rev or 0, data, blobs, op)`.
   The UI reads `pending` ∪ `records` (pending wins).
2. **Push** (loop, one record at a time, oldest first): upload any referenced blob that is not yet complete, then
   `PUT`/`DELETE` with `baseRev`.
   - `200` → write the record into `records` with the new `rev`, delete from `pending`.
   - `409` → conflict (step 4).
   - network error → retry with backoff (1 s … 60 s).
3. **Pull**: `GET since=cursor` until `more=false`; upsert into `records`; advance the cursor. If a pulled id also has a
   `pending` entry whose `baseRev` is older, the push will hit `409` and be resolved there.
4. **Conflict** (`409` with `current`):
   - decrypt both; if the contents are equal → drop the pending entry;
   - pending is a `put` and current is live → keep `current` under the original id; re-create the local version as a
     **new record** (new id, title + " (conflitto)"/" (conflict)"); surface a notice;
   - pending is a `put` and current is a tombstone → re-create the local version as a new record;
   - pending is a `delete` and current is live → drop the delete (data is never lost silently);
   - explicit user choice (**Overwrite** in the edit-conflict dialog) → re-`PUT` with `baseRev = current.rev`.
5. **Blobs**: after pull, schedule downloads for referenced blobs missing locally (desktop: all, in background).

## 5. Approval sequence (summary)

```
D2 (pending)                    Server                        D1 (active)
  POST /approvals {c2}  ───────►  state=requested ──WS──────►  approval.requested
                                                    ◄───────  POST respond {pk1,n1}
  ◄──WS approval.responded ─────  state=responded
  POST reveal {n2}      ───────►  state=revealed  ──WS──────►  approval.revealed
  shows SAS                                                    checks c2, shows SAS, user approves
                                                    ◄───────  POST approve {box,boxNonce}
  ◄──WS approval.approved ──────  state=approved, D2 active
  opens box → VK
```

## 6. Item plaintext (inside the encrypted `data`)

```json
{
  "v": 1,
  "title": "Netflix",
  "fields": [
    {"id": "f-1", "k": "sito web", "v": "netflix.com"},
    {"id": "f-2", "k": "email", "v": "simone@icloud.com"},
    {"id": "f-3", "k": "password", "v": "s3cr3t", "h": true},
    {"id": "f-4", "k": "area clienti", "v": "Area clienti", "l": "https://www.netflix.com/account"}
  ],
  "desc": "Account di famiglia",
  "files": [
    {"id": "<blob uuid>", "name": "contratto.pdf", "size": 123456, "mime": "application/pdf",
     "key": "<b64 32B>", "added": 1730000000000}
  ],
  "fav": false,
  "trashed": null,
  "created": 1730000000000,
  "updated": 1730000000000
}
```
- `h` (hidden) and `l` (link) are omitted when false/empty. `trashed` is the trash timestamp or `null`.
- Unknown fields must be preserved by clients (forward compatibility).
- `blobs` on the wire record = ids of `files`.
