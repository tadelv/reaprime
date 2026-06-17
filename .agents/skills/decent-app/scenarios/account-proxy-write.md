# Scenario: Account proxy write forwarding

Verifies that write methods on `/api/v1/account/proxy/*` require
`account:proxy:write` and relay the body through the linked Decent account.

## Preconditions

- The app is running with a linked Decent account.
- A user-managed API token exists with `account:proxy:write`.
- A read-only skin token or API token exists with `account:proxy`.
- Pick a safe `support/api/...` write endpoint and payload for the account under
  test.

```bash
scripts/sb-dev.sh start --platform macos
```

## Steps

Read-only tokens must not be enough for writes:

```bash
READ_TOKEN=replace-with-read-token

status=$(curl -sS -o /tmp/account-proxy-read-only.json -w '%{http_code}' \
  -X POST http://localhost:8080/api/v1/account/proxy/support/api/example \
  -H "Authorization: Bearer ${READ_TOKEN}" \
  -H 'Content-Type: application/json' \
  -d '{"dryRun":true}')
test "$status" = "403" || { cat /tmp/account-proxy-read-only.json; exit 1; }
```

Write-scoped tokens should forward the request:

```bash
WRITE_TOKEN=replace-with-write-token

curl -isS \
  -X POST http://localhost:8080/api/v1/account/proxy/support/api/example \
  -H "Authorization: Bearer ${WRITE_TOKEN}" \
  -H 'Content-Type: application/json' \
  -d '{"dryRun":true}'
```

Repeat with `PUT` for a safe endpoint that accepts updates:

```bash
curl -isS \
  -X PUT http://localhost:8080/api/v1/account/proxy/support/api/example \
  -H "Authorization: Bearer ${WRITE_TOKEN}" \
  -H 'Content-Type: application/json' \
  -d '{"dryRun":true}'
```

## Expected Results

- Missing or invalid tokens return `401`.
- Read-only tokens return `403` for `POST` and `PUT`.
- Write-scoped tokens reach the Decent backend.
- The app log includes the proxy caller id and method.
- Response headers do not expose `authorization`, `set-cookie`,
  `www-authenticate`, transfer, length, or encoding headers.

## Postconditions

```bash
scripts/sb-dev.sh stop
```
