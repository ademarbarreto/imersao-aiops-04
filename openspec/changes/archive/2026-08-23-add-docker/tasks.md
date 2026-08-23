## 1. Imagem Docker da aplicação

- [x] 1.1 Criar `src/Dockerfile` a partir de `node:20-bookworm-slim`, copiando `package.json`/`package-lock.json` e rodando `npm ci --omit=dev` antes de copiar o restante do código
- [x] 1.2 Configurar o container para executar como usuário não-root (`USER node`)
- [x] 1.3 Expor a porta 8080 (`EXPOSE 8080`)
- [x] 1.4 Adicionar `HEALTHCHECK` consultando `http://127.0.0.1:8080/health` via `node -e` (sem dependência externa como `curl`)
- [x] 1.5 Definir `CMD` para iniciar a aplicação (`node server.js`)

## 2. Contexto de build

- [x] 2.1 Criar `src/.dockerignore` excluindo `node_modules`, `.git`, `.gitignore`, `.env`/`.env.*`, arquivos de log e os próprios arquivos de definição de container (`Dockerfile`, `.dockerignore`, `docker-compose.yml`)

## 3. Docker Compose

- [x] 3.1 Criar `docker-compose.yml` na raiz do projeto com o serviço `app` (build a partir de `src/`, imagem `fabricioveronez/kube-news-imersao`, porta `8080:8080`)
- [x] 3.2 Adicionar o serviço `db` (`postgres:16-bookworm`) com `healthcheck` via `pg_isready`
- [x] 3.3 Declarar as credenciais do banco (`DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`) uma única vez no compose (com defaults, sobrescrevíveis via `.env`) e reutilizá-las em `app.environment` (`DB_*`) e `db.environment` (`POSTGRES_*`)
- [x] 3.4 Configurar `app` com `depends_on: db: condition: service_healthy`
- [x] 3.5 Adicionar volume nomeado para persistir os dados do Postgres (`/var/lib/postgresql/data`)

## 4. Validação

- [x] 4.1 Rodar `docker compose up --build` e confirmar que `app` e `db` sobem sem erros
- [x] 4.2 Verificar que `/health`, `/ready` e `/` respondem HTTP 200 via `curl http://localhost:8080/...`
- [x] 4.3 Confirmar nos logs da aplicação que a conexão com o Postgres do compose está funcionando (query executada com sucesso)
- [x] 4.4 Rodar `docker compose down` (sem `-v`) e `docker compose up` novamente, confirmando que os dados gravados antes persistem
