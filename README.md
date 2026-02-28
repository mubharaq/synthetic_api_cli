# synthetic_api_cli

A declarative mock backend CLI for frontend developers — written in Dart.

You define API routes in JSON, then run a local or cloud-hosted mock API with:
- REST methods (`GET`, `POST`, `PUT`, `PATCH`, `DELETE`, `HEAD`, `OPTIONS`)
- optional auth (`none`, `bearer`, `apiKey`)
- request validation (`querySchema`, `bodySchema`, `headersSchema`)
- simulated errors and latency
- offset/cursor pagination
- configurable CORS

## Quick Start (New Project)

```bash
dart pub global activate synthetic_api_cli
mkdir my-mock-api && cd my-mock-api
synthetic-api init
synthetic-api dev
```

Then call:
- `GET http://localhost:4010/`
- `GET http://localhost:4010/health`
- `GET http://localhost:4010/__routes`

`init` scaffolds:
- `synthetic-api.config.json`
- `fixtures/users.json`
- deploy files: `Dockerfile`, `.dockerignore`, `render.yaml`, `railway.json`, `Procfile`

Behavior:
- Existing files are skipped by default.
- Use `--force` to overwrite existing files.

## Install

Install globally via pub:

```bash
dart pub global activate synthetic_api_cli
synthetic-api --help
```

## CLI

```bash
synthetic-api init [--config synthetic-api.config.json] [--force]
synthetic-api dev [--config synthetic-api.config.json] [--port 4010] [--watch true|false]
synthetic-api validate [--config synthetic-api.config.json]
synthetic-api tunnel [--port 4010] [--provider auto|cloudflared|ngrok]
```

Port resolution order for `dev`:
- `--port`
- `PORT` environment variable
- `4010`

## Built-in Endpoints

- `GET /health` — healthcheck payload (for cloud probes)
- `GET /__routes` — routes index (includes system + declared routes)

## Config Example

```json
{
  "version": 1,
  "global": {
    "latencyMs": [50, 250],
    "cors": {
      "enabled": true,
      "origin": "*",
      "methods": ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"],
      "headers": ["content-type", "authorization", "x-api-key"]
    }
  },
  "auth": {
    "tokens": ["demo-token"],
    "apiKeys": ["demo-key"]
  },
  "routes": [
    {
      "method": "GET",
      "path": "/users",
      "querySchema": { "page": "number?", "limit": "number?" },
      "pagination": { "type": "offset", "defaultLimit": 5 },
      "response": { "status": 200, "bodyFrom": "fixtures/users.json" },
      "errors": [{ "status": 500, "probability": 0.05 }]
    }
  ]
}
```

Template variables in response strings:
- `{{params.id}}`
- `{{query.page}}`
- `{{body.email}}`

## Cloud Deploy

`init` generates deploy-ready files for:
- **Railway** — `railway.json`
- **Render** — `render.yaml`
- **Heroku** — `Procfile`
- **Docker** — `Dockerfile`, `.dockerignore`

The `Dockerfile` compiles the Dart project to a native binary and runs it in a minimal `scratch` container — no Dart SDK required at runtime.

## Also Available for Node.js

The original Node.js version is available on npm:

```bash
npx synthetic-api init
```

See [synthetic-api on npm](https://www.npmjs.com/package/synthetic-api).