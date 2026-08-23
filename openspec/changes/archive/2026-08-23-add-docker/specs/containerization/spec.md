## ADDED Requirements

### Requirement: Imagem Docker da aplicação
O sistema SHALL fornecer um `Dockerfile` em `src/` capaz de construir uma imagem executável da aplicação kube-news a partir de `node:20-bookworm-slim`, instalando dependências de produção via `npm ci --omit=dev`, executando o processo como usuário não-root, expondo a porta 8080, e definindo um `HEALTHCHECK` que consulta o endpoint `/health` da própria aplicação.

#### Scenario: Build da imagem a partir do contexto `src/`
- **WHEN** `docker build` é executado com contexto `src/`
- **THEN** a imagem é construída com sucesso, contendo o código da aplicação e as dependências de produção declaradas em `package.json`

#### Scenario: Container roda sem privilégios de root
- **WHEN** o container é iniciado a partir da imagem
- **THEN** o processo da aplicação executa como o usuário `node`, não como `root`

#### Scenario: Healthcheck reporta saudável quando a aplicação responde
- **WHEN** a aplicação está no ar e o endpoint `/health` responde HTTP 200
- **THEN** o `HEALTHCHECK` do container reporta o container como saudável

#### Scenario: Healthcheck reporta não saudável quando a aplicação não responde
- **WHEN** o endpoint `/health` não responde ou retorna um status diferente de 200
- **THEN** o `HEALTHCHECK` do container reporta o container como não saudável

### Requirement: Contexto de build excluindo arquivos desnecessários
O sistema SHALL fornecer um arquivo `.dockerignore` em `src/` que exclua do contexto de build artefatos que não devem entrar na imagem, incluindo `node_modules`, arquivos de controle de versão (`.git`, `.gitignore`), arquivos de ambiente (`.env`, `.env.*`), logs e os próprios arquivos de definição de container (`Dockerfile`, `.dockerignore`, `docker-compose.yml`).

#### Scenario: node_modules do host não entra na imagem
- **WHEN** o diretório `src/node_modules` existe no host durante o build
- **THEN** o conteúdo de `node_modules` não é copiado para o contexto de build da imagem

#### Scenario: Segredos locais não entram na imagem
- **WHEN** um arquivo `.env` existe em `src/` no host durante o build
- **THEN** o arquivo `.env` não é copiado para o contexto de build da imagem

### Requirement: Ambiente local via Docker Compose
O sistema SHALL fornecer um `docker-compose.yml` na raiz do projeto que orquestre dois serviços — `app` (build a partir de `src/`, imagem `fabricioveronez/kube-news-imersao`) e `db` (`postgres:16-bookworm`) — permitindo subir a aplicação e sua dependência de banco com um único comando.

#### Scenario: Subir o ambiente completo
- **WHEN** `docker compose up --build` é executado na raiz do projeto
- **THEN** os serviços `app` e `db` são construídos/baixados e iniciados, e a aplicação fica acessível na porta 8080 do host

#### Scenario: Aplicação só inicia após o banco estar saudável
- **WHEN** o serviço `db` ainda não passou no seu `healthcheck` (`pg_isready`)
- **THEN** o serviço `app` não é iniciado, aguardando o `db` reportar-se saudável

#### Scenario: Dados do Postgres persistem entre reinicializações
- **WHEN** o ambiente é derrubado com `docker compose down` (sem `-v`) e subido novamente com `docker compose up`
- **THEN** os dados previamente gravados no Postgres continuam disponíveis, pois estão armazenados em um volume nomeado

### Requirement: Fonte única de credenciais do banco no Compose
O sistema SHALL definir as credenciais do banco (`DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`) uma única vez no `docker-compose.yml`, com valores compartilhados entre o serviço `app` (variáveis `DB_*` da aplicação) e o serviço `db` (variáveis `POSTGRES_*`), de modo que os dois serviços nunca fiquem com valores divergentes.

#### Scenario: Aplicação autentica com sucesso no Postgres do compose
- **WHEN** o ambiente é iniciado via `docker compose up` sem sobrescrever as credenciais padrão
- **THEN** o serviço `app` consegue autenticar no serviço `db` usando as mesmas credenciais com que o Postgres foi inicializado

#### Scenario: Sobrescrever credenciais via variáveis de ambiente
- **WHEN** o usuário define `DB_PASSWORD` (ou `DB_DATABASE`/`DB_USERNAME`) no ambiente ou em um arquivo `.env` antes de subir o compose
- **THEN** o novo valor é aplicado igualmente aos serviços `app` e `db`, mantendo as credenciais consistentes entre os dois
