# reference-service

Minimal Go HTTP service exposing a single health-check endpoint, used as the
first workload deployed through the failure-mode-circus CI/CD pipeline
(build → push → deploy → k6 smoke test) before any real failure-mode
scenario is built.

## Endpoint

- `GET /healthz` — returns `200 OK` with body `ok`.

## Configuration

- `LISTEN_ADDR` (optional) — address to listen on. Defaults to `:8080`.

## Compile and run locally

Requires Go 1.26+.

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
