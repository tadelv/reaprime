# Scenario: ETag / If-None-Match on list endpoints

Verifies the conditional-GET behaviour for the five cacheable list reads.

## Preconditions

```bash
scripts/sb-dev.sh start --platform macos --connect-machine MockDe1 --connect-scale MockScale
```

## Steps

Pick any covered endpoint and walk:

```bash
ENDPOINT=/api/v1/beans   # or /api/v1/grinders, /api/v1/profiles, /api/v1/shots, /api/v1/beans/{beanId}/batches

# 1. First request: 200 + ETag header
curl -is "http://localhost:8080${ENDPOINT}" | sed -n '1,/^\r$/p'

# 2. Capture the ETag and re-request conditionally — expect 304
etag=$(curl -sf -D - "http://localhost:8080${ENDPOINT}" -o /dev/null \
  | awk '/^[Ee][Tt][Aa][Gg]:/ {print $2}' | tr -d '\r')
curl -is -H "If-None-Match: ${etag}" "http://localhost:8080${ENDPOINT}" | sed -n '1,/^\r$/p'
# -> HTTP/1.1 304 Not Modified, ETag matches, no body
```

One-shot success assertion (run for each endpoint):

```bash
for ep in /api/v1/beans /api/v1/grinders /api/v1/profiles /api/v1/shots; do
  etag=$(curl -sf -D - "http://localhost:8080${ep}" -o /dev/null \
    | awk '/^[Ee][Tt][Aa][Gg]:/ {print $2}' | tr -d '\r')
  status=$(curl -sf -o /dev/null -w '%{http_code}' \
    -H "If-None-Match: ${etag}" "http://localhost:8080${ep}")
  test "$status" = "304" || { echo "FAIL ${ep}: got $status"; exit 1; }
done
echo OK
```

Mutation invalidation — a write should change the ETag:

```bash
old_etag=$(curl -sf -D - http://localhost:8080/api/v1/beans -o /dev/null \
  | awk '/^[Ee][Tt][Aa][Gg]:/ {print $2}' | tr -d '\r')
curl -sf -X POST http://localhost:8080/api/v1/beans \
  -H 'Content-Type: application/json' \
  -d '{"roaster":"Sey","name":"Gichathaini"}' >/dev/null
new_etag=$(curl -sf -D - http://localhost:8080/api/v1/beans -o /dev/null \
  | awk '/^[Ee][Tt][Aa][Gg]:/ {print $2}' | tr -d '\r')
test "$old_etag" != "$new_etag" || { echo FAIL; exit 1; }
echo MUTATION_OK
```

Wildcard `If-None-Match: *` short-circuits to 304:

```bash
status=$(curl -sf -o /dev/null -w '%{http_code}' \
  -H 'If-None-Match: *' http://localhost:8080/api/v1/beans)
test "$status" = "304" && echo WILDCARD_OK
```

## Postconditions

```bash
scripts/sb-dev.sh stop
```
