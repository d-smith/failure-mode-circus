# reference-service

Minimal Go HTTP service exposing a health-check endpoint and a small
calculator endpoint, used as the first workload deployed through the
failure-mode-circus CI/CD pipeline (build → push → deploy → k6 smoke test)
before any real failure-mode scenario is built.

## Endpoints

- `GET /healthz` — returns `200 OK` with body `ok`.

- `GET /calc?op1=<number>&op2=<number>&operator=<add|sub|mul|div>` —
  applies `operator` to `op1` and `op2` as `op1 operator op2` and returns
  JSON.

  Success (`200`):
  ```json
  {"op1": 2, "op2": 3, "operator": "sub", "result": -1}
  ```

  Errors (`400`), body `{"error": "<message>"}`:
  - `op1`/`op2` missing or not numeric — `"op1 and op2 must be numeric"`
  - `operator` not one of `add`, `sub`, `mul`, `div` — `"operator must be
    one of add, sub, mul, div"`
  - `operator=div` with `op2=0` — `"division by zero"`

  Any method other than `GET` returns `405`.

## Health check

`./reference-service healthcheck` runs a one-shot self-check instead of
starting the server: it makes an HTTP GET to its own `/healthz` and exits
`0` if that returns `200`, `1` otherwise.

This exists because the runtime image
(`gcr.io/distroless/static-debian12`, see below) has no shell, no curl, and
no wget, so a standard `CMD-SHELL curl -f ... || exit 1` container health
check isn't possible. ECS instead execs the binary directly via the `CMD`
form: `["CMD", "/reference-service", "healthcheck"]`.

## Configuration

- `LISTEN_ADDR` (optional) — address to listen on. Defaults to `:8080`.

## Compile and run locally

Requires Go 1.26+.

```bash
go test ./... -v
```

```bash
go build -o reference-service .
./reference-service
```

In another terminal:

```bash
curl -i http://localhost:8080/healthz
```

Expected response:

```
HTTP/1.1 200 OK
Content-Type: text/plain; charset=utf-8

ok
```

Stop the service with Ctrl+C.

## Build and run the container locally

Build the image (two-stage build: compiles a static binary with
`golang:1.26`, then copies it into a `distroless/static-debian12` runtime
image with no shell or package manager):

```bash
docker build -t reference-service:local .
```

Run it, mapping container port 8080 to a local port:

```bash
docker run --rm -p 8080:8080 --name reference-service reference-service:local
```

In another terminal:

```bash
curl -i http://localhost:8080/healthz
```

Stop the container with Ctrl+C, or from another terminal:

```bash
docker stop reference-service
```

To run on a different local port without changing the image, override the
host-side mapping (the container still listens on 8080 internally):

```bash
docker run --rm -p 9090:8080 --name reference-service reference-service:local
```
