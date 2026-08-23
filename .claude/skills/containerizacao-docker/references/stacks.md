# Receitas por stack

Leia apenas a seção da stack do projeto. Cada uma traz a imagem base Debian recomendada, como instalar só as dependências de produção, se vale multi-stage, o entrypoint típico e a armadilha mais comum.

## Índice

- [Node.js](#nodejs)
- [Python](#python)
- [Go](#go)
- [Java](#java)
- [.NET](#net)
- [PHP](#php)
- [Ruby](#ruby)
- [Decidir sobre multi-stage](#decidir-sobre-multi-stage)

---

## Node.js

**Base:** `node:20-bookworm` (ou a versão maior que o projeto exigir; `node:20-slim` se o tamanho importar e não houver módulo nativo exótico).

**Instalação:** `npm ci --omit=dev` quando existe `package-lock.json` — `npm ci` respeita o lock exatamente e falha se ele estiver dessincronizado do `package.json`, que é o comportamento que se quer num build. Sem lockfile, `npm install --omit=dev`. Para pnpm, `pnpm install --prod --frozen-lockfile`; para yarn, `yarn install --production --frozen-lockfile`.

**Copiar antes de instalar:** `COPY package*.json ./`

**Usuário não-root:** a imagem oficial já traz o usuário `node` — basta `USER node` depois de copiar o código.

**Multi-stage:** desnecessário para JavaScript puro. Necessário para TypeScript, Next.js, Vite e afins: um estágio instala tudo e compila, o estágio final recebe só o build e as dependências de produção.

**Entrypoint:** `CMD ["node", "server.js"]` — prefira chamar o Node direto em vez de `npm start`, para não colocar o npm entre o init do container e o processo (ele atrapalha o repasse de sinais).

**Healthcheck sem curl:** `CMD node -e "require('http').get('http://localhost:PORTA/health', r => {if (r.statusCode !== 200) throw new Error(r.statusCode)})"`

**Armadilha comum:** caminhos relativos. `express.static('static')`, leitura de `views/` e afins resolvem a partir do diretório de trabalho do processo — o `WORKDIR` e o layout do `COPY` precisam reproduzir a estrutura que a aplicação espera.

---

## Python

**Base:** `python:3.12-slim` (Debian slim; evite Alpine, onde wheels pré-compilados não se aplicam e o pip recorre a compilar do zero).

**Instalação:** `pip install --no-cache-dir -r requirements.txt`. Com Poetry, exporte para requirements ou use `poetry install --only main --no-root`. Com uv, `uv sync --no-dev`.

**Copiar antes de instalar:** `COPY requirements.txt ./` (ou `pyproject.toml`/`poetry.lock`).

**Variáveis úteis:** `PYTHONDONTWRITEBYTECODE=1` e `PYTHONUNBUFFERED=1` — a segunda importa de verdade, sem ela os logs ficam presos no buffer e não aparecem em `docker compose logs`.

**Usuário não-root:** as imagens oficiais não trazem um; crie com `useradd`.

**Multi-stage:** vale quando há dependência que compila (`psycopg2` de fonte, `cryptography` sem wheel). Um estágio instala num virtualenv, o final copia o virtualenv pronto.

**Entrypoint:** `CMD ["gunicorn", "--bind", "0.0.0.0:8000", "app:app"]` para WSGI, `CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]` para ASGI/FastAPI.

**Armadilha comum:** aplicação que escuta em `127.0.0.1` em vez de `0.0.0.0`. Dentro do container isso a torna inalcançável de fora, mesmo com a porta publicada.

---

## Go

**Base:** multi-stage obrigatório na prática — `golang:1.22-bookworm` para compilar, e para o estágio final `gcr.io/distroless/base-debian12` (Debian, sem shell) ou `debian:bookworm-slim`.

**Compilação:** `CGO_ENABLED=0 go build -o /app/bin/servico ./cmd/servico`. Com `CGO_ENABLED=0` o binário fica estático e roda em qualquer base; se o projeto precisa de cgo, mantenha o estágio final em `debian:bookworm-slim`.

**Cache de dependências:** `COPY go.mod go.sum ./` seguido de `RUN go mod download`, antes de copiar o código.

**Entrypoint:** `CMD ["/app/bin/servico"]`.

**Armadilha comum:** copiar o binário para uma base incompatível. Binário compilado com cgo numa base Debian não roda em distroless `static`; se houver dúvida, use `CGO_ENABLED=0`.

---

## Java

**Base:** multi-stage. `maven:3.9-eclipse-temurin-21` ou `gradle:8-jdk21` para compilar; `eclipse-temurin:21-jre-jammy` (Ubuntu/Debian) no estágio final — JRE, não JDK.

**Cache de dependências:** `COPY pom.xml ./` seguido de `RUN mvn dependency:go-offline` antes de copiar `src/`.

**Compilação:** `mvn -q -DskipTests package` (os testes rodam no CI, não no build da imagem).

**Entrypoint:** `CMD ["java", "-jar", "/app/app.jar"]`.

**Armadilha comum:** não limitar heap. A JVM em container pode calcular mal a memória disponível em configurações antigas; versões recentes respeitam cgroups, mas conferir `-XX:MaxRAMPercentage` evita OOM kill silencioso.

---

## .NET

**Base:** multi-stage. `mcr.microsoft.com/dotnet/sdk:8.0` para compilar; `mcr.microsoft.com/dotnet/aspnet:8.0` (Debian) no estágio final.

**Cache de dependências:** `COPY *.csproj ./` seguido de `RUN dotnet restore` antes de copiar o resto.

**Publicação:** `dotnet publish -c Release -o /app/publish --no-restore`.

**Entrypoint:** `CMD ["dotnet", "MinhaApp.dll"]`.

**Armadilha comum:** a aplicação escutando na porta padrão do host em vez da do container. Defina `ASPNETCORE_URLS=http://+:8080` e publique essa porta.

---

## PHP

**Base:** `php:8.3-fpm-bookworm` (com nginx num serviço separado do compose) ou `php:8.3-apache-bookworm` quando um único container basta.

**Instalação:** `composer install --no-dev --optimize-autoloader --no-interaction`. Copie `composer.json` e `composer.lock` antes do código.

**Extensões:** instale com `docker-php-ext-install pdo_pgsql mysqli` — em Debian as dependências de sistema vêm do apt, o que é bem mais previsível que no Alpine.

**Entrypoint:** o da imagem oficial já serve; ajuste só se houver script de inicialização.

**Armadilha comum:** permissão em diretórios de cache/upload. O usuário do PHP-FPM (`www-data`) precisa conseguir escrever neles.

---

## Ruby

**Base:** `ruby:3.3-bookworm` (ou `-slim`).

**Instalação:** `bundle config set --local without 'development test' && bundle install`. Copie `Gemfile` e `Gemfile.lock` antes do código.

**Entrypoint:** `CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]`.

**Armadilha comum:** em Rails, `server.pid` remanescente impede o boot. Remova-o no início ou use um entrypoint que limpe.

---

## Decidir sobre multi-stage

Multi-stage vale quando o que produz o artefato **não precisa estar** na imagem final. Compiladores, SDKs, toolchains e dependências de desenvolvimento pesam e ampliam a superfície de ataque sem servir a nada em runtime.

- **Sempre multi-stage:** Go, Java, .NET, Rust — linguagens compiladas onde só o artefato importa.
- **Multi-stage quando há build step:** TypeScript, Next.js, Vite, Angular, assets de frontend em qualquer stack.
- **Estágio único costuma bastar:** Node com JavaScript puro, Python sem dependência que compile, PHP, Ruby.

Na dúvida, comece com estágio único. Multi-stage sem necessidade só acrescenta um arquivo mais difícil de ler.
