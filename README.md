# Infra

Docker Compose configurations for infrastructure and full local deployment. All stacks attach to the shared `braingain` bridge network so application containers (`backend`, `litellm`, `cdn`, `frontend`, `seed`) can reach them by container name.

## Dokploy Deployment (branch `deploy/dokploy`)

On this branch the root `docker-compose.yml` is the production stack for Dokploy, served at
`https://braingain.joachimkern.de`: `postgres`, `rustfs` + `s3-init`, `piper`, `cdn`, `litellm`
(+ oneshots `litellm-db-init`, `litellm-key-init`), `backend`, `frontend`, `seed`. `llama` and
`glances` are not deployed. No service publishes a host port; Traefik routes only to `frontend`,
whose nginx proxies `/api/` → `backend:8000` and `/cdn/` → `cdn:8080`, so the frontend needs no
configuration. Secrets come from the environment (`.env.example`).

The game generator runs with `LLM_PROVIDER=litellm`: the backend calls the LiteLLM proxy at
`http://litellm:4000` with the alias `smart` and its own budgeted virtual key
(`LITELLM_BACKEND_KEY`, registered by `litellm-key-init`); the proxy routes to Anthropic
(`claude-haiku-5-5`), keeps spend in its own `litellm` database (created by `litellm-db-init`),
never logs prompts and stops at a 50 USD / 30 days cap.

Setup (once):

1. DNS: `A` record `braingain.joachimkern.de` → the Dokploy host.
2. Dokploy → project → *Create Service → Compose*; source `brAIn-gAIm/Infra`, branch
   `deploy/dokploy`, compose path `./docker-compose.yml`.
3. *Environment*: paste `.env.example` and replace every value.
4. *Domains*: host `braingain.joachimkern.de`, service `frontend`, port `80`, path `/`,
   HTTPS with Let's Encrypt.
5. *Advanced*: enable *Isolated Deployment*, so Traefik joins this stack's network and
   names like `backend` or `cdn` cannot collide with other apps on `dokploy-network`.
6. Deploy. Set a monthly spend limit on the Anthropic workspace as a backstop.

Check the LLM route from the backend container:

```bash
curl -s http://litellm:4000/v1/chat/completions -H "Authorization: Bearer $LLM_API_KEY" \
  -H 'Content-Type: application/json' -d '{"model": "smart", "messages": [{"role": "user", "content": "hi"}]}'
```

The backend uses `CDN_BASE_URL=${PUBLIC_URL}/cdn` for browser links *and* for its own
uploads/downloads, so it must be able to reach the public URL from inside the container.

## Quick Start (Full Local Stack, `main`)

Start the entire prototype (`postgres`, `rustfs`, `s3-init`, `piper`, `llama`, `glances`, `cdn`, `backend`, `frontend`, and the oneshot `seed` container that registers a default `braingain` user and seeds all games from `github.com/brAIn-gAIm/Backend`):

```bash
docker compose up -d
```

- **Frontend**: `http://localhost:8080` (default seeded user: `braingain` / `braingain`)
- **Backend API / Docs**: `http://localhost:3000/docs`
- **CDN**: `http://localhost:8081` (`https://localhost:8444`)
- **RustFS Console**: `http://localhost:9001` (`braingain` / `braingain-secret`)
- **Glances UI**: `http://localhost:61208`

## Services

### 1. PostgreSQL (`postgres/`)
- **Image**: `postgres:18.6-alpine3.24`
- **Port**: `5432`
- **Volume**: `postgres_data` -> `/var/lib/postgresql`
- **Default Credentials**:
  - User: `braingain`
  - Password: `braingain`
  - Database: `braingain`
- **Internal URL**: `postgresql://braingain:braingain@postgres:5432/braingain`

Start service:
```bash
docker compose -f postgres/docker-compose.yml up -d
```

### 2. RustFS (`rustfs/`)
- **Image**: `rustfs/rustfs:1.0.3`
- **Ports**:
  - `9000`: S3 API
  - `9001`: Web Console
- **Volume**: `rustfs_data` -> `/data`
- **Default Credentials**:
  - Access Key: `braingain`
  - Secret Key: `braingain-secret`
- **Bucket**: `braingain` (auto-created on startup via `s3-init`)
- **Internal URL**: `http://rustfs:9000`
- **Web Console URL**: `http://localhost:9001`

Start service:
```bash
docker compose -f rustfs/docker-compose.yml up -d
```

### 3. Glances (`glances/`)
- **Image**: `nicolargo/glances:latest-full`
- **Port**:
  - `61208`: Web UI
- **Volume**:
  - `/var/run/docker.sock` -> `/var/run/docker.sock:ro`
- **PID**: `host`
- **Web UI URL**: `http://localhost:61208`

Start service:
```bash
docker compose -f glances/docker-compose.yml up -d
```

### 4. Piper TTS (`piper/`)
- **Image**: `braingain/piper:1.8.0` (built locally from `piper/Dockerfile`, `piper-tts[http]==1.8.0`)
- **Port**:
  - `5000`: HTTP API
- **Voice**: `en_US-hfc_female-medium` (baked into the image; change via the `VOICE` build arg in `piper/docker-compose.yml`)
- **Internal URL**: `http://piper:5000`

Synthesize speech (returns WAV):
```bash
curl -X POST -H 'Content-Type: application/json' -d '{"text": "Hello"}' -o out.wav http://localhost:5000/synthesize
```

Start service:
```bash
docker compose -f piper/docker-compose.yml up -d --build
```

### 5. llama.cpp (`llama/`)
- **Image**: `ghcr.io/ggml-org/llama.cpp:server-b11515` (CPU)
- **Port**:
  - `8082`: OpenAI-compatible HTTP API (container port `8080`; host `8080` is the frontend)
- **Model**: `unsloth/Qwen3-1.7B-GGUF:Q4_K_M` (~1.1 GB, downloaded on first start)
- **Volume**: `llama_models` -> `/models`
- **Limits**: 3 threads, 5 GB memory, 8192-token context, 1 request at a time
- **Internal URL**: `http://llama:8080/v1`

Chat completion with JSON-schema-constrained output:
```bash
curl http://localhost:8082/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "messages": [{"role": "user", "content": "One quiz question about photosynthesis."}],
  "max_tokens": 300,
  "response_format": {"type": "json_schema", "json_schema": {"name": "quiz", "schema": {
    "type": "object",
    "properties": {"question": {"type": "string"}, "answers": {"type": "array", "items": {"type": "string"}}},
    "required": ["question", "answers"]
  }}}
}'
```

Start service:
```bash
docker compose -f llama/docker-compose.yml up -d
```
