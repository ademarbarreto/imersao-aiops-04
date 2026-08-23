## Context

O kube-news é uma aplicação Node.js/Express com Sequelize/Postgres, sem etapa de build (sem TypeScript/bundler), servindo EJS e expondo `/health`, `/ready` e `/metrics`. Uma versão containerizada (Dockerfile + `.dockerignore` + docker-compose) já existiu neste repositório e chegou a rodar em produção — está documentada indiretamente pelo pós-mortem `docs/postmortem-2026-08-22-kube-news-indisponivel.md`, que registra um incidente SEV-1 causado por (1) nome de imagem digitado errado (`kube-news-iersao` em vez de `kube-news-imersao`) e (2) senha de banco divergente entre o manifesto da aplicação e o do Postgres. Essa versão foi removida deliberadamente do repositório para ser reconstruída do zero como exercício de containerização.

## Goals / Non-Goals

**Goals:**
- Reconstruir `src/Dockerfile`, `src/.dockerignore` e `docker-compose.yml` para permitir build e execução local da aplicação em container, junto com um Postgres para dependência de banco.
- Nomear a imagem corretamente como `fabricioveronez/kube-news-imersao` desde o início, evitando o erro de digitação que causou a causa raiz nº 1 do incidente.
- Definir as credenciais do banco em uma única fonte de valores no compose, reutilizada pelos serviços `app` e `db`, evitando a divergência que causou a causa raiz nº 2 do incidente.
- Reaproveitar o endpoint `/health` já existente na aplicação para o `HEALTHCHECK` da imagem.

**Non-Goals:**
- Não inclui manifestos Kubernetes (`k8s/`) — fica para uma mudança futura.
- Não inclui fluxo de hot-reload/dev container (bind mount + nodemon) — a imagem é "build e roda", igual à versão anterior.
- Não inclui pipeline de CI, push para registry, nem pin de imagem por digest — fica para quando a publicação da imagem entrar em escopo.
- Não altera código da aplicação: as variáveis de ambiente já lidas por `src/system-life.js`/models (`DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`, `DB_SSL_REQUIRE`) já são suficientes.

## Decisions

### Imagem base: `node:20-bookworm-slim` (não Alpine)
A aplicação depende de `pg` e `pg-hstore`, que envolvem bindings nativos. Distribuições baseadas em musl (Alpine) historicamente geram mais atrito com pacotes nativos do Node do que Debian slim. `bookworm-slim` mantém a imagem enxuta sem trocar a libc, reduzindo risco de incompatibilidade.

### Build com `npm ci --omit=dev`, sem multi-stage
Não há etapa de compilação (sem TypeScript, sem bundler) — o multi-stage não traria benefício aqui. `npm ci` garante instalação determinística a partir do `package-lock.json`; `--omit=dev` remove dependências de desenvolvimento (não há nenhuma declarada hoje, mas mantém a prática correta para o futuro).

### Execução como usuário não-root (`USER node`)
A imagem base `node` já provê o usuário `node` (uid 1000). Rodar o processo da aplicação sem privilégios de root é uma prática básica de segurança de containers, sem custo de complexidade.

### `HEALTHCHECK` reaproveitando `/health`
A aplicação já expõe `/health` (usado como liveness probe no pós-mortem). O `HEALTHCHECK` da imagem chama esse mesmo endpoint via `node -e` (sem dependência extra como `curl`), mantendo a imagem sem pacotes adicionais.

### Nome/tag da imagem: `fabricioveronez/kube-news-imersao`, sem tag explícita (`latest` implícito)
O nome de repositório correto — `kube-news-imersao` — é fixado desde a criação do compose, evitando reintroduzir o erro de digitação da causa raiz nº 1 do incidente. A tag fica implícita (`latest`) porque, nesta fase, a imagem só é usada localmente via build do compose; pin por digest e versionamento explícito de tag ficam para quando a publicação em registry entrar em escopo (fora deste change).

### Credenciais do banco: fonte única no compose
`DB_DATABASE`, `DB_USERNAME` e `DB_PASSWORD` são declaradas uma única vez (variáveis do compose com defaults, sobrescrevíveis via `.env`) e referenciadas tanto em `app.environment` quanto em `db.environment`. Isso elimina estruturalmente a divergência que gerou a causa raiz nº 2 do incidente (senha `Pg#23` no app vs. `Pg#123` no banco) — a mesma lição registrada como ação preventiva P1-1 no pós-mortem, aplicada aqui no nível de Compose.

### Ordenação de start: `depends_on: condition: service_healthy`
O serviço `app` só inicia depois que o `healthcheck` do `db` (via `pg_isready`) reporta saudável, evitando falhas de conexão na inicialização por corrida entre os containers.

### Persistência: volume nomeado para o Postgres
Diferente do ambiente de cluster kind descrito no pós-mortem (que usava `emptyDir`, perdendo dados a cada restart — ação preventiva P2-1 em aberto), o compose local usa um volume nomeado desde o início, preservando os dados entre `docker compose down`/`up`.

## Risks / Trade-offs

- [Sem pin de imagem por digest/versão] → Aceito para este change: escopo é ambiente local de desenvolvimento, não publicação/deploy. Revisitar quando `k8s/` for reintroduzido.
- [`latest` implícito pode causar builds inconsistentes se a imagem também for usada fora do compose] → Mitigado por documentar no README que essa tag é apenas para uso local via `docker compose`.
- [Sem hot-reload] → Trade-off aceito deliberadamente (decisão do usuário): manter simetria com a versão anterior; ciclo de dev continua sendo rebuild via `docker compose up --build`.

## Migration Plan

Não há dado ou ambiente em produção afetado por este change (é a criação inicial dos artefatos de containerização). Passos de adoção:
1. Adicionar os arquivos (`src/Dockerfile`, `src/.dockerignore`, `docker-compose.yml`).
2. Validar localmente com `docker compose up --build`, confirmando que `/health`, `/ready` e `/` respondem 200 e que a aplicação conecta ao Postgres.
3. Sem rollback necessário — reverter é apenas remover os arquivos adicionados, como já ocorreu uma vez neste repositório.

## Open Questions

Nenhuma em aberto — decisões de escopo, nome de imagem e estratégia de tag foram fechadas em sessão de exploração antes deste proposal.
