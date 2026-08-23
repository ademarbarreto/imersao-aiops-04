## Why

O kube-news não tem hoje nenhuma forma de rodar em container: não existe `Dockerfile`, `.dockerignore` ou `docker-compose.yml` no repositório. Essa versão containerizada já existiu neste repo e chegou a rodar em produção (documentado no pós-mortem `docs/postmortem-2026-08-22-kube-news-indisponivel.md`), mas foi removida deliberadamente para ser reconstruída do zero como exercício. É preciso reintroduzir a imagem Docker da aplicação e um ambiente de desenvolvimento local via Compose (app + Postgres), aplicando também a lição do pós-mortem sobre não duplicar a senha do banco entre serviços.

## What Changes

- Adiciona `src/Dockerfile` construindo a imagem da aplicação a partir de `node:20-bookworm-slim`, com `npm ci --omit=dev`, execução como usuário não-root (`node`), porta 8080 exposta e `HEALTHCHECK` batendo no endpoint `/health` já existente na aplicação.
- Adiciona `src/.dockerignore` excluindo `node_modules`, arquivos de git, logs e arquivos de ambiente do contexto de build.
- Adiciona `docker-compose.yml` na raiz do projeto com dois serviços:
  - `app`: builda a imagem a partir de `src/`, publicada como `fabricioveronez/kube-news-imersao` (sem tag explícita, `latest` implícito), expõe a porta 8080 e depende do banco estar saudável (`depends_on: condition: service_healthy`).
  - `db`: `postgres:16-bookworm` com volume nomeado para persistência dos dados e `healthcheck` via `pg_isready`.
  - Variáveis de banco (`DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`) vêm de uma única fonte (arquivo `.env` / defaults no compose) e são reutilizadas nos dois serviços, evitando a duplicação que causou a causa raiz nº 2 do incidente SEV-1.

## Capabilities

### New Capabilities
- `containerization`: build da imagem Docker da aplicação e orquestração local via Docker Compose (app + Postgres), incluindo healthchecks e configuração de variáveis de ambiente sem duplicação.

### Modified Capabilities
(nenhuma — não há specs existentes sendo alteradas)

## Impact

- Novo `src/Dockerfile` e `src/.dockerignore`.
- Novo `docker-compose.yml` na raiz do projeto.
- Nenhuma mudança no código da aplicação (`src/server.js`, `src/models/post.js`, etc.) — a aplicação já expõe `/health` e lê configuração de banco via variáveis de ambiente (`DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`, `DB_SSL_REQUIRE`), então nenhum ajuste de código é necessário.
- Não inclui manifestos Kubernetes (`k8s/`) — fica fora de escopo desta mudança.
