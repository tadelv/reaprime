# Scenario: firmware endpoints

Verifies the bundled firmware catalog, managed apply progress stream, and idempotent cancellation response.

## Preconditions

```bash
scripts/sb-dev.sh start --platform macos --connect-machine MockDe1
```

## Steps

```bash
curl -sf http://localhost:8080/api/v1/machine/firmware \
  | jq -e '.operation.state == "idle" and (.artifacts | length > 0)'

curl -sN -X POST http://localhost:8080/api/v1/machine/firmware/apply \
  -H 'Content-Type: application/json' \
  --data '{"artifactId":"de1-1352"}' \
  | tee /tmp/decent-firmware.ndjson

jq -s -e '
  .[-1].status == "done"
  and any(.[]; .status == "erasing")
  and any(.[]; .status == "uploading")
' /tmp/decent-firmware.ndjson

curl -sf -X DELETE http://localhost:8080/api/v1/machine/firmware \
  | jq -e '. == {"operation":{"state":"idle"}}'
```

The apply stream is newline-delimited JSON. A terminal `error` event instead of `done` indicates that the upload failed; inspect the emitted event before retrying.

## Postconditions

```bash
scripts/sb-dev.sh stop
```
