---
name: containerizacao-docker
description: Cria e revisa Dockerfile, .dockerignore e Docker Compose seguindo um padrão fixo — Dockerfile junto ao código-fonte, imagens base Debian, dependências do projeto declaradas como serviços e validação obrigatória subindo a stack e exercitando os endpoints antes de entregar. USE QUANDO o pedido for: containerizar ou dockerizar uma aplicação; criar, corrigir ou revisar um Dockerfile; criar ou ajustar um docker-compose; adicionar banco, cache ou fila como dependência do compose; trocar imagem base, healthcheck, volume, porta ou variáveis de ambiente de containers; ou fazer o projeto rodar sem instalar runtime e banco na máquina do desenvolvedor. Vale mesmo quando a palavra Docker não aparece no pedido, desde que o resultado esperado seja a aplicação rodando em container. NÃO USE para escrever manifestos de Kubernetes, pipelines de CI/CD, ou depurar um container que já está rodando sem alterar Dockerfile ou compose.
---

# Containerização padronizada com Docker

O objetivo desta skill é que qualquer projeto saia containerizado no mesmo padrão: arquivos no lugar certo, imagens previsíveis, dependências declaradas no compose e — o ponto que mais falha na prática — **comprovadamente funcionando**, porque a stack foi subida e exercitada antes de você dizer que está pronto.

Trabalhe nas fases abaixo em ordem. Elas existem porque cada uma depende de informação que a anterior descobriu: você não escolhe imagem base sem saber a linguagem, e não escreve healthcheck sem saber qual endpoint a aplicação expõe.

---

## Fase 1 — Descobrir a stack antes de escrever qualquer linha

Containerização feita por suposição quebra em detalhes silenciosos. Leia o projeto e responda a estas perguntas com evidência no código, não com o palpite mais provável:

- **Linguagem, runtime e gerenciador de pacotes** — procure o manifesto: `package.json`, `requirements.txt`/`pyproject.toml`, `go.mod`, `pom.xml`/`build.gradle`, `*.csproj`, `composer.json`, `Gemfile`. Ele também diz se existe lockfile, o que muda o comando de instalação.
- **Onde o código vive.** Raiz do repositório ou uma subpasta (`src/`, `app/`, `backend/`)? Isso define onde o Dockerfile vai ficar e qual é o build context.
- **Entrypoint** — o script de start no manifesto, ou o arquivo com a função `main`.
- **Porta que a aplicação escuta.** Leia no código. Muitas aplicações fixam a porta em vez de ler de variável de ambiente, e publicar a porta errada gera um container que sobe mas não responde.
- **Variáveis de ambiente de configuração e seus defaults.** Elas precisam aparecer no compose com os mesmos valores default que o código assume, senão a aplicação sobe apontando para o lugar errado.
- **Dependências externas** — banco, cache, fila, storage. Cada uma vira um serviço no compose.
- **Existe build step?** Transpilação, bundler, compilação. Se sim, considere multi-stage (veja `references/stacks.md`).
- **Caminhos relativos no código.** Este é o detalhe que mais causa bug sutil: se a aplicação faz algo como servir arquivos estáticos por caminho relativo, o `WORKDIR` precisa corresponder ao diretório de onde a aplicação espera rodar. Caso contrário o container sobe, o health responde, e só o CSS não carrega.
- **A aplicação faz retry de conexão com o banco?** Se ela conecta uma vez no boot e morre em caso de falha, o compose precisa esperar o banco ficar saudável antes de iniciá-la.

Se algo permanecer ambíguo depois de ler o código — por exemplo, qual banco usar quando o projeto não fixa um — pergunte em vez de escolher por você.

---

## Fase 2 — Dockerfile junto ao código-fonte

**O Dockerfile fica na mesma pasta do código que ele constrói.** Se a aplicação está em `src/`, o arquivo é `src/Dockerfile` e seus `COPY` usam caminhos relativos a `src/`, não `COPY src/... `.

Isso não é preferência estética. O build context passa a conter só o que a imagem precisa, o que reduz o que é enviado ao daemon e diminui a chance de vazar arquivo indevido para dentro da imagem. E, mais importante, o Dockerfile acompanha o serviço que ele descreve — num repositório com `api/`, `worker/` e `web/`, cada um tem o seu, e nenhum Dockerfile na raiz precisa saber da existência dos outros. O compose aponta para cada pasta via `build.context`.

Estrutura do arquivo, na ordem:

1. **`FROM` com imagem base Debian e tag fixa** (veja Fase 3).
2. **`WORKDIR`** — um caminho absoluto e estável, como `/app`.
3. **Copiar só o manifesto de dependências**, depois instalar. Dependências mudam com menos frequência que o código; separar as duas etapas faz o Docker reaproveitar a camada de instalação em quase todo rebuild. Inverter essa ordem torna todo build uma reinstalação completa.
4. **Instalar apenas dependências de produção** — a imagem final não precisa de framework de teste nem linter. O comando exato por stack está em `references/stacks.md`.
5. **Copiar o restante do código.**
6. **Usuário não-root.** Um processo que roda como root dentro do container tem privilégios desnecessários e, se houver escape ou bind mount mal configurado, o estrago é maior. Muitas imagens oficiais já trazem um usuário sem privilégio (`node`, por exemplo); quando não trazem, crie um.
7. **`EXPOSE`** com a porta real descoberta na Fase 1.
8. **`HEALTHCHECK`** apontando para um endpoint de saúde real da aplicação. Se o projeto não tem um, um teste de TCP na porta ainda é melhor que nada — mas prefira um endpoint que prove que a aplicação está respondendo, não só que a porta abriu. Evite depender de `curl`/`wget` sem confirmar que existem na imagem; use o runtime que você já sabe que está lá (por exemplo, `node -e` numa imagem Node, `python -c` numa imagem Python). **Também em exec form**, pelo mesmo motivo do item 9:

   ```dockerfile
   HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 \
       CMD ["node", "-e", "require('http').get('http://127.0.0.1:8080/health', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"]
   ```

9. **`CMD` em exec form** (`CMD ["node", "server.js"]`). A shell form embrulha o processo num shell, que não repassa sinais — o container passa a ignorar `SIGTERM` e só morre no timeout do `docker stop`.

Se a stack exige compilação, use multi-stage: um estágio compila, outro só recebe o artefato. `references/stacks.md` indica quais stacks pedem isso.

---

## Fase 3 — Imagens base Debian

**Prefira variantes Debian (`-bookworm`, `-bullseye`, `-slim`) a Alpine.**

O motivo é concreto: Alpine usa musl no lugar da glibc. Módulos nativos de Node, wheels pré-compilados de Python e binários que assumem glibc ou falham na instalação ou, pior, compilam do zero e transformam um build de segundos num de minutos. Diagnóstico dentro do container também é mais pobre. A economia de tamanho existe, mas raramente compensa o tempo perdido — e as variantes `-slim` do Debian já cobrem boa parte dessa diferença.

Fixe a tag com a versão maior do runtime (`node:20-bookworm`, `python:3.12-slim`, `postgres:16`). Nunca use `latest`: ela transforma um build reproduzível em algo que muda sozinho entre duas execuções.

Exceção legítima: se o usuário pedir Alpine explicitamente, siga o pedido — a regra existe como default, não como veto.

---

## Fase 4 — `.dockerignore`

Crie o `.dockerignore` na raiz do build context — ou seja, na mesma pasta do Dockerfile. Sem ele, o diretório inteiro é enviado ao daemon a cada build e artefatos locais podem sobrescrever o que foi instalado dentro da imagem.

Cubra no mínimo: diretório de dependências instaladas localmente (`node_modules`, `.venv`, `vendor`, `target`), `.git`, logs, arquivos de ambiente (`.env`), artefatos de build local e o próprio `Dockerfile`/compose.

---

## Fase 5 — Docker Compose com as dependências do projeto

O compose é onde a aplicação deixa de precisar de qualquer coisa instalada na máquina. Todo serviço externo descoberto na Fase 1 entra aqui.

Convenções:

- **Sem a chave `version`** — é obsoleta e o Docker Compose emite aviso ao encontrá-la.
- **Serviço da aplicação** com `build.context` apontando para a pasta onde está o Dockerfile, e `ports` publicando a porta real.
- **Serviços de dependência com healthcheck próprio.** Postgres usa `pg_isready`, MySQL usa `mysqladmin ping`, Redis usa `redis-cli ping`. Sem healthcheck, o compose considera o container "iniciado" no instante em que o processo sobe, muito antes de o banco aceitar conexões.
- **`depends_on` com `condition: service_healthy`** quando a aplicação não faz retry de conexão. `depends_on` puro só garante ordem de partida, não prontidão — e uma aplicação que conecta no boot morre nesse intervalo.
- **Volume nomeado** para todo dado que precisa sobreviver a `docker compose down`. Sem isso, o banco é recriado vazio a cada ciclo.
- **Variáveis com interpolação e default** (`${DB_PASSWORD:-Pg#123}`), usando os mesmos defaults que o código assume. Elas precisam bater dos dois lados: o valor que o serviço de banco usa para criar o usuário tem que ser o mesmo que a aplicação usa para conectar.
- **O host do banco é o nome do serviço**, não `localhost`. Dentro da rede do compose, `localhost` é o próprio container.
- **Rede própria** declarada para a stack, mantendo os serviços isolados.

---

## Fase 6 — Escopo: só arquivos de Docker

Gere **apenas** `Dockerfile`, `.dockerignore` e o arquivo de compose. Nada de `README`/`DOCKER.md`, `.env.example`, manifestos de Kubernetes, scripts auxiliares ou workflows de CI sem que o usuário tenha pedido.

O motivo é direto: arquivos não solicitados entram no repositório, aparecem no diff e viram trabalho de revisão que ninguém pediu. Se durante o trabalho você achar que um arquivo extra ajudaria, mencione em uma linha na resposta e deixe a decisão com o usuário — não crie por conta própria.

Isso vale também para conteúdo dentro dos arquivos permitidos: não encha o Dockerfile de comentários explicando Docker para o leitor.

A restrição é sobre o que entra no repositório do usuário. Os scripts e configs que acompanham esta skill — como o linter da Fase 7 — rodam de dentro dela e não geram arquivo no projeto.

---

## Fase 7 — Lint estático do Dockerfile

Antes de gastar um ciclo de build, passe o Dockerfile pelo linter:

```bash
.claude/skills/containerizacao-docker/scripts/lint-dockerfile.sh src/Dockerfile
```

Esta fase vem antes da validação em runtime por duas razões. A primeira é custo: o lint roda em milissegundos e não precisa de daemon, então um erro estático é descoberto sem esperar um `up --build`. A segunda é cobertura — e é a mais importante: **os erros que o lint pega não têm sintoma em runtime.** Um container rodando como root sobe normalmente, responde ao health e passa em todos os `curl` do checklist da Fase 8. Uma imagem em `latest` também. Sem o lint, essas falhas atravessam a validação inteira sem serem vistas.

O linter também é o que transforma as regras que esta skill enuncia em prosa — tag fixa, exec form, não-root, `WORKDIR` absoluto — em verificação mecânica. Reler o arquivo que você mesmo acabou de escrever é a checagem menos confiável que existe, porque o raciocínio que produziu o erro é o mesmo que vai procurá-lo.

Uma dessas regras o hadolint não cobre sozinho, e vale saber por quê: o `DL3002` só reprova quando o último `USER` é literalmente root, então um Dockerfile que **nunca declara `USER`** — a forma mais comum de entregar um processo rodando como root — passaria limpo. O script fecha essa lacuna com uma checagem própria, `SKILL001`, que sai no nível `política` e bloqueia igual a um `error`. Se a imagem base já roda sem privilégio (`nginx-unprivileged`, distroless `nonroot`), desligue a checagem no arquivo com `# skill ignore=SKILL001 # motivo` e diga na resposta que fez isso — suprimir um gate é decisão do usuário, não detalhe seu.

O que fazer com o resultado, pelo código de saída do script:

- **`0` (OK)** — nenhum achado bloqueante. Se sobraram achados `info`/`style`, leia cada um, decida e mencione a decisão na resposta. Siga para a Fase 8.
- **`1` (BLOQUEADO)** — há `error`, `warning` ou achado de `política` — ou um caminho que você passou não existe. Corrija e rode de novo. Não suba a stack para "ver se funciona mesmo assim": funcionar não é o critério aqui, já que a maior parte desses achados produz um container que sobe bem.
- **`2` (PULADO)** — o hadolint não está instalado. Isso **não** é reprovação: siga para a Fase 8 e registre no relatório que o lint não rodou, com o motivo. Validação parcial declarada é informação útil; validação parcial omitida não é. O caminho errado, ao contrário, bloqueia: corrigir um path está inteiramente na sua mão, e tratá-lo como "não deu para checar" faria um erro de digitação virar um Dockerfile entregue sem nunca ter passado pelo gate.

A configuração fica em `assets/hadolint.yaml`, **dentro da skill** — ela não é escrita no repositório do usuário, o que manteria a Fase 6 intacta. Se o projeto já tiver um `.hadolint.yaml` próprio, o script usa o do projeto.

Para o catálogo de regras, os achados que a skill aceita de propósito e quando um pragma de ignore se justifica, leia `references/lint.md`.

---

## Fase 8 — Validação obrigatória

**Toda criação ou alteração de Dockerfile ou compose termina subindo a stack e exercitando a aplicação.** Não espere o usuário pedir, e não declare pronto com base em leitura do arquivo — a maior parte dos erros de containerização (WORKDIR errado, porta errada, variável que não bate, dependência que não sobe a tempo) só aparece em runtime.

O ciclo mínimo:

1. `docker compose up -d --build` a partir da raiz do projeto.
2. `docker compose ps` — confirmar que as dependências chegaram a `healthy` e que a aplicação está `Up`.
3. Exercitar endpoints reais: health, a rota principal, e pelo menos uma operação de escrita se a aplicação tiver uma.
4. Provar persistência: reiniciar só o serviço da aplicação e confirmar que o dado escrito continua lá; depois `down` seguido de `up` e confirmar de novo — isso valida o volume nomeado.
5. Reportar as evidências: o que foi executado e o que retornou.

Se algo falhar, leia `docker compose logs <serviço>` e diagnostique antes de mexer nos arquivos. Alterar o Dockerfile no chute costuma trocar um erro por outro.

O checklist com os comandos concretos e o formato do relatório está em `references/validacao.md`.

---

## Anti-padrões

Estes são os erros que aparecem com mais frequência e o que cada um custa:

- **Dockerfile na raiz quando o código está em subpasta** — build context inflado e Dockerfile que não acompanha o serviço.
- **`latest` ou tag ausente** — build que muda sozinho entre execuções.
- **Imagem Alpine por reflexo** — módulos nativos quebrados e builds lentos, sem ganho proporcional.
- **Copiar o código antes de instalar dependências** — cache inútil, todo build reinstala tudo.
- **Rodar como root** — privilégio desnecessário no processo da aplicação.
- **`depends_on` sem `condition: service_healthy`** numa aplicação que não retenta conexão — a app morre no primeiro boot e o usuário vê um crash loop.
- **Banco sem volume nomeado** — dados somem no primeiro `docker compose down`.
- **`DB_HOST=localhost` dentro do compose** — a aplicação tenta conectar nela mesma.
- **Segredo em `ARG` ou `ENV`** — fica gravado nas camadas da imagem e sobrevive à remoção do arquivo.
- **`CMD` em shell form** — sinais não chegam ao processo e o container ignora `SIGTERM`.
- **Entregar sem lintar** — a skill enuncia regras (tag fixa, exec form, não-root) que uma ferramenta verifica em milissegundos, e várias delas produzem um container que sobe bem e passa na validação de runtime. Conferir de olho o arquivo que você acabou de escrever é a auto-avaliação menos confiável que existe.
- **Declarar sucesso sem ter subido a stack** — o mais caro de todos, porque transfere para o usuário a descoberta de que não funciona.

---

## Quando aprofundar

| Situação | Leia |
|---|---|
| Escolher imagem base, comando de instalação, multi-stage ou entrypoint para uma stack específica (Node, Python, Go, Java, .NET, PHP, Ruby) | `references/stacks.md` |
| Interpretar um achado do hadolint, ajustar a severidade de uma regra ou decidir por um pragma de ignore | `references/lint.md` |
| Executar a validação da Fase 8, diagnosticar falha na subida ou montar o relatório de evidências | `references/validacao.md` |
