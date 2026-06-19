# Scenario: Account-proxy write forwarding & write-scope gate

Verifies the account write proxy (#299): `POST`/`PUT` on
`/api/v1/account/proxy/*` are registered (`enableWrites: true`) and require the
stronger `account:proxy:write` scope, while `GET` keeps needing only
`account:proxy`. The read-only **skin token** therefore passes a `GET` but is
rejected on `POST`/`PUT` with `403` — the core observable contrast.

The scope check lives in `proxyAuthMiddleware`, which is **outer** to routing, so
a scope rejection (`403`) fires before any route match. That makes the write-gate
behaviour observable with plain `curl` using the skin token alone.

**Not sim-observable:** a *successful* write (`200` relayed from upstream).
Write-scoped tokens are minted only from the account-page UI ("Allow write
access") — there is no headless REST mint endpoint — and a real `POST` to
`decentespresso.com/support/api/*` would mutate the live backend, which a smoke
test must not do. The gate (`403`) and route registration are what we assert here.

## Preconditions

```bash
scripts/sb-dev.sh start --platform macos --connect-machine MockDe1
P=/api/v1/account/proxy/support/api/sn
# The skin token is injected into served skin HTML on :3000; it holds the
# read-only `account:proxy` scope.
TOK=$(curl -s "http://localhost:3000/" | sed -n 's/.*__REA_PROXY_TOKEN__="\([^"]*\)".*/\1/p' | head -1)
echo "skin token: ${TOK:0:8}..."
```

## Steps

```bash
# 1. No / unknown token on a write -> 401 (middleware rejects before routing)
curl -s -o /dev/null -w "POST no-token: %{http_code}\n"  -X POST "http://localhost:8080$P"
curl -s -o /dev/null -w "PUT  no-token: %{http_code}\n"  -X PUT  "http://localhost:8080$P"
curl -s -o /dev/null -w "POST bad-token: %{http_code}\n" -X POST \
  -H "Authorization: Bearer nope" "http://localhost:8080$P"
# -> all 401

# 2. Skin token (read scope) passes the GET scope check -> reaches handler.
#    200 if a Decent account is linked, 401 ("not linked") otherwise.
curl -s -o /dev/null -w "GET  skin-token: %{http_code}\n" \
  -H "Authorization: Bearer $TOK" "http://localhost:8080$P"

# 3. SAME read-only token on POST/PUT -> 403 write-scope gate. This is the
#    behaviour the write proxy adds: write needs account:proxy:write.
curl -s -w "\nPOST skin-token: %{http_code}\n" -X POST \
  -H "Authorization: Bearer $TOK" "http://localhost:8080$P"
curl -s -w "\nPUT  skin-token: %{http_code}\n" -X PUT \
  -H "Authorization: Bearer $TOK" "http://localhost:8080$P"
# -> {"error":"Token is not scoped for account:proxy:write"} ; HTTP 403
```

One-shot assertion (proves the write gate exists and only bites writes):

```bash
TOK=$(curl -s "http://localhost:3000/" | sed -n 's/.*__REA_PROXY_TOKEN__="\([^"]*\)".*/\1/p' | head -1)
get=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOK" "http://localhost:8080$P")
post=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Authorization: Bearer $TOK" "http://localhost:8080$P")
test "$post" = "403" || { echo "FAIL: write not gated (POST=$post)"; exit 1; }
test "$get" != "403" || { echo "FAIL: read wrongly gated (GET=$get)"; exit 1; }
echo "OK: GET=$get passes scope, POST=$post hits write gate"
```

If `POST`/`PUT` return `401`/`404` instead of `403` with a valid read token, the
write routes were not registered — check `enableWrites: true` on the
`AccountProxyHandler` in `webserver_service.dart`.

## Postconditions

```bash
scripts/sb-dev.sh stop
```
