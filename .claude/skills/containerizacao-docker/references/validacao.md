# Validação da stack containerizada

Leia este arquivo ao executar a Fase 8 — depois de criar ou alterar qualquer Dockerfile, `.dockerignore` ou arquivo de compose, e depois de o lint da Fase 7 ter passado — e sempre que a subida falhar e for preciso diagnosticar.

## Índice

- [Por que validar sempre](#por-que-validar-sempre)
- [Checklist de execução](#checklist-de-execução)
- [Quando algo falha](#quando-algo-falha)
- [Relatório de evidências](#relatório-de-evidências)

---

## Por que validar sempre

Os erros mais comuns de containerização não aparecem na leitura do arquivo. `WORKDIR` incompatível com caminho relativo, porta publicada diferente da que a aplicação escuta, variável de ambiente que não bate entre app e banco, dependência que ainda não aceita conexão quando a aplicação inicia — todos produzem arquivos que parecem corretos e uma stack que não funciona.

Validar custa poucos minutos e é a diferença entre entregar algo verificado e transferir para o usuário a descoberta de que não funciona.

O lint da Fase 7 e esta validação cobrem classes diferentes de erro e nenhuma substitui a outra: o lint pega o que sobe funcionando mas está errado (root, `latest`, shell form), e a subida pega o que só aparece com a stack de pé. Por isso as duas entram no relatório.

---

## Checklist de execução

Rode a partir da raiz do projeto (onde está o arquivo de compose).

**1. Subir a stack**

```bash
docker compose up -d --build
```

Se o daemon não estiver rodando, a saída diz `Cannot connect to the Docker daemon`. Nesse caso, avise o usuário que precisa iniciar o Docker Desktop / daemon — não conclua a tarefa como validada.

**2. Confirmar o estado dos containers**

```bash
docker compose ps
```

O que precisa ser verdade: cada serviço de dependência aparece como `healthy` (não só `Up`), e o serviço da aplicação está `Up` com a porta publicada. `health: starting` significa que o healthcheck ainda não completou — aguarde e repita antes de concluir qualquer coisa.

**3. Exercitar os endpoints reais**

```bash
curl -s http://localhost:PORTA/health
curl -s http://localhost:PORTA/ | head -20
```

Health respondendo prova que o processo subiu; a rota principal prova que a aplicação serve conteúdo de verdade. Se o projeto serve arquivos estáticos, confirme que uma URL de asset responde — é assim que se pega `WORKDIR` errado, já que a página carrega mas o CSS não.

**4. Exercitar uma escrita**

Se a aplicação tem operação de escrita (API de criação, formulário), execute uma. É o teste que prova que a conexão com o banco funciona de ponta a ponta — não só que o container do banco subiu.

```bash
curl -s -X POST http://localhost:PORTA/api/recurso \
  -H "Content-Type: application/json" \
  -d '{"campo":"valor"}'
```

Depois confirme que o dado aparece na leitura.

**5. Provar persistência — reinício da aplicação**

```bash
docker compose restart app
```

Aguarde subir e confirme que o dado escrito no passo 4 continua lá. Isso prova que o estado vive no banco, não na memória do container da aplicação.

**6. Provar persistência — ciclo completo**

```bash
docker compose down && docker compose up -d
```

Confirme de novo que o dado continua lá. É este passo que valida o volume nomeado: sem ele, o banco volta vazio e o dado some. `docker compose down -v` **remove** o volume — use apenas quando a intenção for descartar os dados.

---

## Quando algo falha

Leia os logs antes de alterar qualquer arquivo. Mudar o Dockerfile no chute normalmente troca um erro por outro e alonga o ciclo.

```bash
docker compose logs app
docker compose logs db
```

Sintomas frequentes e o que costumam significar:

| Sintoma | Causa provável |
|---|---|
| App em crash loop logo após subir | Conectou ao banco antes de ele aceitar conexões — falta `depends_on` com `condition: service_healthy` |
| `ECONNREFUSED` / `connection refused` para o banco | `DB_HOST` apontando para `localhost` em vez do nome do serviço |
| Autenticação falhando no banco | Variáveis do app e do serviço de banco com valores diferentes |
| Container `Up` mas `curl` não responde | Porta publicada diferente da que a aplicação escuta, ou app escutando em `127.0.0.1` em vez de `0.0.0.0` |
| Página carrega sem CSS/imagens | `WORKDIR` incompatível com os caminhos relativos do código |
| Healthcheck sempre `unhealthy` | Comando do healthcheck usa binário que não existe na imagem (`curl`/`wget`), ou aponta para rota inexistente |
| Build lento a cada alteração de código | `COPY` do código antes da instalação de dependências, invalidando o cache |

Depois de corrigir, **repita o checklist do início** — uma correção pode desfazer algo que já passava.

---

## Relatório de evidências

Ao concluir, relate o que foi executado e o que retornou. Sem isso o usuário não tem como distinguir "validei" de "presumo que funcione".

Formato:

```
Validação executada:

- Lint: `lint-dockerfile.sh src/Dockerfile` — 0 error, 0 warning (1 info: DL3066, aceito)
- Build e subida: `docker compose up -d --build` — concluído
- Estado: db `healthy`, app `Up` com porta 8080 publicada
- GET /health → {"state":"up",...}
- GET / → página renderizada
- POST /api/post → recurso criado, confirmado na listagem
- Persistência: dado preservado após `restart` da app e após `down`/`up`
```

Se algum passo não pôde ser executado — daemon parado, aplicação sem endpoint de escrita, ausência de rota de health, hadolint não instalado — diga qual e por quê, em vez de omitir. Uma validação parcial declarada é informação útil; uma validação parcial apresentada como completa não é.
