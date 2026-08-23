# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Kube-News: a small Node.js/Express news portal used as a teaching example for containers and Kubernetes ("Imersão Kubernetes"). The application itself is intentionally simple; most of the repo's substance is in how it's built, run, and deployed.

## Commands

All app commands run from `src/`:

```bash
cd src
npm install
npm start          # node server.js, listens on :8080
```

There is no real test suite — `npm test` is a stub (`exit 1`). Don't assume Jest/Mocha config exists.

Local stack with Postgres via Docker Compose (from repo root):

```bash
docker compose up --build
```

This builds `src/Dockerfile` and starts `app` (port 8080) + `db` (Postgres 16-bookworm), with `app` waiting on the db's healthcheck.

Populate sample data via `popula-dados.http` against `POST /api/post` (VS Code REST Client or curl), body shape `{ artigos: [{ title, description, resumo }, ...] }`.

Deploying to Kubernetes: manifests are in `k8s/` (`app-deployment.yaml`, `app-service.yaml`, `db-deployment.yaml`, `db-service.yaml`, `db-pvc.yaml`). Apply with `kubectl apply -f k8s/`. No Kustomize/Helm — plain manifests, one object per file.

## Architecture

**Entry point**: `src/server.js` wires everything — Express app, Prometheus middleware, health-check router, static files, EJS views, and all routes. There's no router/controller split; routes are defined directly in `server.js`.

**Data layer**: `src/models/post.js` is the only model. It creates its own Sequelize connection from `DB_*` env vars (with hardcoded dev defaults) and exposes `initDatabase()`, which runs `sequelize.sync({ alter: true })` on boot — there are no migration files, schema changes happen via model definition + auto-alter.

**Health/chaos endpoints** (`src/system-life.js`): mounted as a router (`config.routers`) plus a `healthMid` middleware applied *before* routes, both wired near the top of the middleware chain in `server.js`. Beyond normal `/health` and `/ready`, it exposes `/unhealth` (PUT) and `/unreadyfor/:seconds` (PUT) to deliberately break liveness/readiness — used to demonstrate Kubernetes probe behavior. Don't "fix" these as bugs; they're intentional chaos-testing endpoints.

**Metrics**: `src/middleware.js` defines a custom `http_requests_total` counter and logs every request; `express-prom-bundle` (in `server.js`) adds the standard HTTP + default Node metrics. Both are exposed at `/metrics`.

**News search** (client-side, no server round-trip): `GET /` embeds all posts as JSON in a `<script type="application/json" id="posts-data">` tag in `src/views/index.ejs` (HTML-escaped against `<`), and `src/static/scripts/search.js` filters that in-memory array on every keystroke and re-renders the card grid — it matches against title, summary, *and* full content, even though only title/summary are shown on the card. See `openspec/specs/news-search/spec.md` for the full behavioral contract (case-insensitivity, whitespace-only terms, distinct "no results" vs "no posts" messaging).

**Views**: EJS templates in `src/views/` (`index.ejs`, `edit-news.ejs`, `view-news.ejs`) with shared `partial/header.ejs` and `partial/footer.ejs`. Styles are plain CSS in `src/static/styles/` (`main.css`, `admin.css`), no build step/bundler.

## 📦 Estrutura do Projeto

```
/
├── src/                      # Código-fonte principal
│   ├── models/               # Modelos de dados
│   │   └── post.js           # Definição do modelo Post
│   ├── views/                # Templates EJS
│   │   ├── partial/          # Componentes parciais (header, footer)
│   │   ├── edit-news.ejs     # Formulário de edição
│   │   ├── index.ejs         # Página principal
│   │   └── view-news.ejs     # Visualização de notícia
│   ├── static/               # Arquivos estáticos (CSS, imagens)
│   ├── middleware.js         # Middlewares personalizados
│   ├── server.js             # Ponto de entrada da aplicação
│   ├── system-life.js        # Endpoints de health check
│   └── package.json          # Dependências
├── popula-dados.http         # Arquivo para popular o banco com dados de exemplo
└── README.md                 # Documentação
```

## OpenSpec (spec-driven change tracking)

This repo uses OpenSpec (`openspec/`) to track deltas as specs. `openspec/specs/` holds the current accepted behavior per capability (`containerization`, `kubernetes-deployment`, `news-search`); `openspec/changes/archive/` holds completed change proposals. When making a non-trivial behavioral change, check whether an OpenSpec change should be proposed/archived alongside it rather than editing specs by hand — use the `openspec-*` skills for this rather than freehand-editing files under `openspec/`.

## Other repo content

- `Cards/` — a prioritized backlog (P0–P3) of cluster hardening/maturity improvements derived from a point-in-time audit of the `kind-kind` cluster (see `Cards/README.md` for the dependency graph between cards, e.g. HPA depends on metrics-server). These are proposals, not yet-applied manifests — the current `k8s/` manifests don't include all of them (e.g. no NetworkPolicy, no PDB, no dedicated namespace yet).
- `docs/prds/` — product requirement docs for features (e.g. the news-search filter).
- `docs/postmortem-*.md` — incident write-ups.
