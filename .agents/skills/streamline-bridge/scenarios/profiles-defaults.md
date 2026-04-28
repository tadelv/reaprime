# Scenario: discover and restore default profiles

Verifies `GET /api/v1/profiles/defaults` lists the bundled default profiles and that `POST /api/v1/profiles/restore/{filename}` accepts a filename returned by `/defaults`.

## Preconditions

```bash
scripts/sb-dev.sh start --connect-machine MockDe1 --connect-scale MockScale
```

## Steps

List defaults:

```bash
curl -sf http://localhost:8080/api/v1/profiles/defaults | jq .
```

Expected: non-empty array. Each element has keys `filename`, `title`, `author`, `notes`, `beverageType` (all strings).

One-shot shape assertion:

```bash
curl -sf http://localhost:8080/api/v1/profiles/defaults \
  | jq -e 'length > 0 and (.[0]
           | has("filename") and has("title") and has("author")
             and has("notes") and has("beverageType"))'
```

Exit 0 → list non-empty and shape correct.

Round-trip — restore the first default by filename:

```bash
filename=$(curl -sf http://localhost:8080/api/v1/profiles/defaults | jq -r '.[0].filename')
curl -sf -X POST "http://localhost:8080/api/v1/profiles/restore/${filename}" | jq -e 'has("id") and has("isDefault") and .isDefault == true'
```

Exit 0 → restore returned a `ProfileRecord` with `isDefault: true`.

## Postconditions

```bash
scripts/sb-dev.sh stop
```
