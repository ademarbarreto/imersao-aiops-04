# Pós-mortem — Indisponibilidade total do kube-news

| Campo | Valor |
|---|---|
| **Data do incidente** | 2026-08-22 |
| **Início** | 18:11:31 (-03) / 21:11:31 UTC |
| **Detecção** | ~18:13 (-03) — relato manual de usuário |
| **Mitigação concluída** | ~18:17:45 (-03) / 21:17:45 UTC |
| **Duração da indisponibilidade** | ~6 minutos |
| **Severidade** | **SEV-1** — indisponibilidade total, 100% das requisições falhando |
| **Serviço afetado** | `kube-news` (frontend web) |
| **Ambiente** | Cluster kind `kind-kind`, namespace `default` |
| **Status** | Resolvido — cluster e repositório corrigidos; ações preventivas P0-2 em diante em aberto |
| **Autor** | Investigação conduzida via MCP Server do Kubernetes |

> ✅ **Resolvido.** O incidente foi mitigado no cluster e os manifestos do repositório foram corrigidos
> (`k8s/app/deployment.yaml`, linhas 33 e 48). Cluster e repositório estão convergidos — `kubectl diff`
> retorna vazio. As demais ações preventivas seguem em aberto (ver [§11](#11-ações-preventivas)).

---

## 1. Resumo executivo

Um deploy da aplicação `kube-news` introduziu **dois erros de digitação** nos manifestos do Kubernetes:
o nome da imagem do container (`kube-news-iersao` em vez de `kube-news-imersao`) e a senha do banco de dados
(`Pg#23` em vez de `Pg#123`). Como os manifestos foram **deletados e recriados** em vez de atualizados via
`kubectl apply`, o mecanismo de rolling update — que teria bloqueado o deploy sem derrubar nada — não atuou,
e a aplicação ficou com **zero pods disponíveis**.

O segundo erro (senha) permaneceu **mascarado** pelo primeiro: como nenhum container chegava a iniciar,
a falha de autenticação no banco só se manifestou depois que a imagem foi corrigida.

---

## 2. Impacto

- **100% das requisições** ao `kube-news` falhando por ~6 minutos.
- O Service `kube-news` ficou **sem nenhum endpoint** — não havia pod saudável para receber tráfego.
- Nenhuma perda de dados. O Postgres permaneceu íntegro e disponível durante todo o incidente.
- Nenhum impacto em outros serviços do cluster.

---

## 3. Linha do tempo

Horários em UTC. Referências relativas reconstruídas a partir de `kubectl get events`.

| Horário | Evento |
|---|---|
| ~20:26 | Deploy inicial. ReplicaSet `kube-news-65bb68bc87` criado com a imagem **correta** (`kube-news-imersao:v1`). |
| ~20:28 | `Successfully pulled image "fabricioveronez/kube-news-imersao:v1" in 5.875s`. Containers iniciam. **Aplicação saudável.** |
| ~20:28 | Rollout de rotina. Pods substituídos, mesma imagem correta. Aplicação segue saudável por ~42 min. |
| **21:10:36** | **Todos os recursos deletados** (`Killing` em ambos os pods do app e no pod do Postgres). |
| **21:11:31** | **INÍCIO DO INCIDENTE.** Recursos recriados a partir dos manifestos. Novo ReplicaSet `kube-news-669f5cc889` com a imagem **incorreta** (`kube-news-iersao:v1`). |
| 21:11:33 | Primeiro `ErrImagePull`. `pull access denied, repository does not exist`. |
| 21:11:50 | Pods entram em `ImagePullBackOff`. Deployment em `0/2 AVAILABLE`. Service sem endpoints. |
| ~21:13 | **Detecção.** Incidente reportado: "aplicação completamente indisponível". |
| 21:13–21:14 | Investigação. Causa raiz nº 1 identificada nos eventos do pod. |
| ~21:14:30 | **Correção nº 1:** imagem corrigida para `kube-news-imersao:v1`. Pull passa a funcionar. |
| ~21:15 | Pods iniciam e entram em **`CrashLoopBackOff`** (4 restarts). **Causa raiz nº 2 revelada.** |
| ~21:16 | Logs expõem `FATAL 28P01: password authentication failed for user "kubedevnews"`. |
| ~21:17:20 | **Correção nº 2:** `DB_PASSWORD` corrigida para `Pg#123`. |
| **21:17:45** | **FIM DO INCIDENTE.** Deployment `2/2 READY`, 0 restarts, endpoints populados. |
| 21:18–21:20 | Validação end-to-end: HTTP 200 em `/health`, `/ready` e `/`; query ao Postgres executando. |

---

## 4. Causa raiz

Foram **duas falhas independentes**, ambas erros de digitação, ambas no mesmo arquivo
(`k8s/app/deployment.yaml`), introduzidas no mesmo deploy.

### 4.1 Causa raiz nº 1 — Nome da imagem incorreto (a que derrubou o serviço)

O Deployment apontava para um repositório inexistente no Docker Hub. Faltava o **`m`** de `imersao`:

```
fabricioveronez/kube-news-iersao:v1     ← errado (deployado)
fabricioveronez/kube-news-imersao:v1    ← correto
                        ↑ falta o "m"
```

Evidência (evento do pod `kube-news-669f5cc889-jmjbw`):

```
Warning  Failed  kubelet  Failed to pull image "fabricioveronez/kube-news-iersao:v1":
  failed to pull and unpack image "docker.io/fabricioveronez/kube-news-iersao:v1":
  failed to resolve reference "docker.io/fabricioveronez/kube-news-iersao:v1":
  pull access denied, repository does not exist or may require authorization:
  server message: insufficient_scope: authorization failed
```

> **Nota sobre a mensagem de erro:** o Docker Hub responde `insufficient_scope: authorization failed`
> para repositórios **inexistentes**, para não vazar quais repositórios privados existem. Isso induz ao
> diagnóstico errado — parece problema de credencial/`imagePullSecret`, mas é nome inválido.
> **Sempre confirme a existência do repositório antes de investigar autenticação.**

### 4.2 Causa raiz nº 2 — Senha do banco divergente (mascarada pela nº 1)

A senha no Deployment da aplicação divergia da senha com que o Postgres foi inicializado. Faltava o **`1`**:

| Origem | Variável | Valor |
|---|---|---|
| `k8s/app/deployment.yaml` | `DB_PASSWORD` | `Pg#23` ← errado |
| `k8s/db/deployment.yaml` | `POSTGRES_PASSWORD` | `Pg#123` ← fonte da verdade |

Evidência (log do pod `kube-news-5666885694-8jbpl`):

```
original: error: password authentication failed for user "kubedevnews"
    at Parser.parseErrorMessage (/app/node_modules/pg-protocol/dist/parser.js:287:98)
    ...
  severity: 'FATAL',
  code: '28P01',
  file: 'auth.c',
  routine: 'auth_failed'
```

O Postgres foi eleito fonte da verdade porque o banco **já estava inicializado** com `Pg#123`
(`POSTGRES_PASSWORD` só tem efeito na primeira inicialização do volume de dados). Corrigir o lado da
aplicação era a única opção sem recriar o banco.

### 4.3 Fator agravante — por que virou indisponibilidade **total**

Esta é a parte mais importante do incidente.

O Deployment `kube-news` está configurado com uma estratégia de rollout **segura**:

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1
    maxUnavailable: 0    # ← nenhum pod antigo é removido antes de um novo ficar Ready
```

Com `maxUnavailable: 0`, se o deploy defeituoso tivesse sido aplicado com `kubectl apply` sobre o
Deployment existente, o Kubernetes teria:

1. criado **1 pod novo** com a imagem inválida;
2. esperado esse pod ficar `Ready` — o que **nunca aconteceria**;
3. **mantido os 2 pods antigos e saudáveis servindo tráfego** o tempo todo;
4. falhado o rollout após `progressDeadlineSeconds: 600`, sem **nenhum** impacto ao usuário.

**Não houve rolling update porque os recursos foram deletados e recriados do zero.** Sem pods antigos,
não havia o que preservar. Um erro de configuração que o Kubernetes estava preparado para absorver
sem downtime virou uma indisponibilidade total.

Confirmação de que houve `delete` + `apply` (e não `apply`):

```
$ kubectl rollout history deployment/kube-news
REVISION  CHANGE-CAUSE
1         <none>
```

Só existia a revisão 1. O histórico havia sido zerado — prova de que o Deployment era novo, não atualizado.
**Isso também eliminou o caminho de recuperação mais rápido: `kubectl rollout undo` era impossível.**

---

## 5. Evidências

### 5.1 Estado durante o incidente

```
$ kubectl get all
NAME                             READY   STATUS             RESTARTS   AGE
pod/kube-news-669f5cc889-jmjbw   0/1     ImagePullBackOff   0          82s
pod/kube-news-669f5cc889-z9896   0/1     ImagePullBackOff   0          82s
pod/postgres-7c869dcbd-ggwjw     1/1     Running            0          82s

NAME                        READY   UP-TO-DATE   AVAILABLE   IMAGES
deployment.apps/kube-news   0/2     2            0           fabricioveronez/kube-news-iersao:v1
deployment.apps/postgres    1/1     1            1           postgres:16-bookworm
```

`AVAILABLE = 0` → Service sem endpoints → 100% das requisições falhando.

### 5.2 A prova definitiva: os três ReplicaSets

Os ReplicaSets registram, lado a lado, cada estado pelo qual o Deployment passou:

```
$ kubectl get rs -o custom-columns=RS:.metadata.name,DESIRED:.spec.replicas,\
READY:.status.readyReplicas,IMAGE:...containers[0].image,PASS:...env[?(@.name=="DB_PASSWORD")].value

RS                     DESIRED   READY    IMAGE                                  PASS
kube-news-669f5cc889   0         <none>   fabricioveronez/kube-news-iersao:v1    Pg#23    ← o incidente
kube-news-5666885694   0         <none>   fabricioveronez/kube-news-imersao:v1   Pg#23    ← após correção nº 1
kube-news-65bb68bc87   2         2        fabricioveronez/kube-news-imersao:v1   Pg#123   ← saudável
```

**Detalhe forense relevante:** o ReplicaSet saudável final é o `65bb68bc87` — **exatamente o mesmo hash**
do ReplicaSet que servia a aplicação antes do incidente (ver linha das ~20:26 na timeline). O hash de um
ReplicaSet é derivado do `pod template`; hashes idênticos significam templates idênticos. Isso **prova**
que a configuração corrigida é byte a byte igual à última configuração comprovadamente boa — não é uma
correção aproximada, é o retorno exato ao estado saudável.

---

## 6. Correções aplicadas

Aplicadas **diretamente no cluster** via MCP Server do Kubernetes, sem alterar arquivos do repositório.

| # | Recurso | Campo | Antes | Depois | Comando |
|---|---|---|---|---|---|
| 1 | `deployment/kube-news` | `image` | `...kube-news-iersao:v1` | `...kube-news-imersao:v1` | `kubectl patch` |
| 2 | `deployment/kube-news` | `env.DB_PASSWORD` | `Pg#23` | `Pg#123` | `kubectl set env` |

```bash
kubectl patch deployment kube-news -n default --type=strategic -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"kube-news","image":"fabricioveronez/kube-news-imersao:v1"}]}}}}'

kubectl set env deployment/kube-news -n default DB_PASSWORD='Pg#123'
```

---

## 7. Validação pós-correção

Todas as verificações abaixo passaram:

**Estado dos workloads** — 2/2 prontos, **zero restarts**:
```
NAME                         READY   STATUS    RESTARTS   AGE
kube-news-65bb68bc87-hcxpz   1/1     Running   0          2m20s
kube-news-65bb68bc87-slwtg   1/1     Running   0          2m9s
postgres-7c869dcbd-ggwjw     1/1     Running   0          8m10s
```

**Roteamento do Service** — ambos os pods registrados como endpoints:
```
NAME        ENDPOINTS
kube-news   10.244.0.14:8080,10.244.0.15:8080
```

**HTTP através do Service (dentro do cluster)**:
```
/health 200 application/json; charset=utf-8
/ready  200 text/html; charset=utf-8
/       200 text/html; charset=utf-8
```

**HTTP a partir do host (via `kubectl port-forward`)**:
```
/health -> HTTP 200   {"state":"up","machine":"kube-news-65bb68bc87-hcxpz"}
/ready  -> HTTP 200
/       -> HTTP 200
```

**Conectividade real com o banco** — query executando com sucesso nos logs da aplicação:
```
Executing (default): SELECT "id", "title", "summary", "publishDate", "content",
                     "createdAt", "updatedAt" FROM "Posts" AS "Post";
```

---

## 8. O que funcionou bem

- **As readiness/liveness probes fizeram exatamente o seu trabalho.** Pods não saudáveis nunca foram
  registrados como endpoints do Service. Nenhuma requisição foi roteada para um container quebrado —
  a aplicação ficou indisponível, mas **não serviu erros nem respostas corrompidas**.
- **`maxUnavailable: 0` estava corretamente configurado.** A proteção existia; apenas não teve chance de agir.
- **Os eventos e logs do Kubernetes foram suficientes** para o diagnóstico completo, sem necessidade de
  ferramental externo. A causa raiz nº 1 saiu direto de `kubectl describe pod`; a nº 2, de `kubectl logs`.
- **O Postgres permaneceu íntegro** durante todo o incidente. Nenhuma perda de dados.

## 9. O que não funcionou

- **Nenhuma validação impediu que um nome de imagem inexistente chegasse ao cluster.** Não há checagem de
  registry no fluxo de deploy. `kubectl apply --dry-run=server` **não** detecta isso: a validação é de
  schema, não de existência da imagem.
- **A senha do banco está duplicada em dois manifestos independentes.** Dois lugares para manter o mesmo
  valor é uma divergência esperando para acontecer — e aconteceu.
- **`delete` + `apply` em vez de `apply`** destruiu simultaneamente a proteção do rolling update e o
  histórico de rollout, transformando um deploy falho em outage e removendo o `rollout undo`.
- **Detecção foi manual.** O incidente foi descoberto por relato humano, não por alerta. Não há
  monitoramento de `AVAILABLE = 0` nem de pods em `ImagePullBackOff`/`CrashLoopBackOff`.
- **O deploy não foi verificado.** Nada acompanhou o resultado do rollout; o deploy foi dado como concluído
  enquanto o serviço estava fora.
- **Um erro mascarou o outro.** A senha errada só apareceu após corrigir a imagem, dobrando o tempo de
  diagnóstico. Falhas de configuração são frequentemente múltiplas — nunca pare na primeira causa encontrada.

---

## 10. Aprendizados

1. **Sempre use `kubectl apply`, nunca `delete` + `apply`.** O rolling update do Kubernetes é uma rede de
   proteção real: com `maxUnavailable: 0`, um deploy defeituoso **não causa downtime algum**. Deletar
   recursos joga essa proteção fora e ainda apaga o histórico de rollout — o caminho de recuperação mais rápido.
2. **Valor duplicado é valor que vai divergir.** A senha vivia em dois manifestos. A correção estrutural não
   é "prestar mais atenção", é ter **uma única fonte da verdade** (um Secret consumido pelos dois lados).
3. **`insufficient_scope` do Docker Hub geralmente significa "repositório não existe", não "sem permissão".**
   Verifique o nome antes de investigar credenciais.
4. **Um incidente pode ter mais de uma causa raiz.** Corrigir a primeira revelou a segunda. Valide sempre até
   o serviço responder de fato, não até "o erro que eu vi sumir".
5. **Deploy sem verificação não é deploy concluído.** `kubectl rollout status` teria falhado o deploy em
   segundos, em vez de deixar o serviço fora até alguém reclamar.
6. **Erros de digitação em manifestos são falhas de sistema, não de pessoas.** A prevenção eficaz é
   automatizada (validação de imagem em CI, Secret único, gate de rollout), não disciplina individual.

---

## 11. Ações preventivas

| ID | Ação | Prioridade | Previne | Status |
|---|---|---|---|---|
| **P0-1** | Corrigir os dois defeitos em `k8s/app/deployment.yaml` (linha 33: imagem; linha 48: senha). | **P0** | Reincidência imediata | ✅ **Concluída** — 2026-08-22 |
| **P0-2** | Padronizar o deploy em `kubectl apply -f k8s/`. Proibir `delete` + `apply` como procedimento. | **P0** | Fator agravante (§4.3) | ⬜ Em aberto |
| **P0-3** | Adicionar `kubectl rollout status deployment/kube-news --timeout=120s` como **gate obrigatório** ao final de todo deploy, falhando o processo se o rollout não convergir. | **P0** | Deploy quebrado passar despercebido | ⬜ Em aberto |
| **P1-1** | Mover as credenciais para um **único `Secret`**, consumido via `secretKeyRef` tanto pelo Postgres (`POSTGRES_PASSWORD`) quanto pela aplicação (`DB_PASSWORD`). Elimina estruturalmente a divergência **e** remove senha em texto plano do Git. | **P1** | Causa raiz nº 2 | ⬜ Em aberto |
| **P1-2** | Validar a existência da imagem em CI antes do apply: `docker manifest inspect <imagem>` (ou `crane manifest`), falhando o pipeline se o repositório/tag não existir. | **P1** | Causa raiz nº 1 | ⬜ Em aberto |
| **P1-3** | Criar alerta para `Deployment.status.availableReplicas == 0` e para pods em `ImagePullBackOff`/`CrashLoopBackOff` por mais de 2 minutos. | **P1** | Detecção manual | ⬜ Em aberto |
| **P2-1** | Substituir o `emptyDir` do Postgres por um `PersistentVolumeClaim`. Hoje **todo o banco é perdido** se o pod reiniciar. *(Risco pré-existente, não causou este incidente.)* | **P2** | Perda de dados | ⬜ Em aberto |
| **P2-2** | Fixar imagens por digest (`@sha256:...`) além da tag, garantindo imutabilidade real do artefato deployado. | **P2** | Deploy não reprodutível | ⬜ Em aberto |

### Comando de validação para P1-2

```bash
# Falha se o repositório ou a tag não existirem — pegaria a causa raiz nº 1 em CI
IMAGE=$(grep -oP '(?<=image: ).*' k8s/app/deployment.yaml)
docker manifest inspect "$IMAGE" > /dev/null \
  || { echo "ERRO: imagem inexistente ou inacessível: $IMAGE"; exit 1; }
```

---

## 12. Apêndice — comandos usados no diagnóstico

```bash
# 1. Visão geral — revelou ImagePullBackOff e AVAILABLE=0
kubectl get all -o wide

# 2. Causa raiz nº 1 — mensagem completa do erro de pull
kubectl describe pod <pod> -n default
kubectl get events -n default --sort-by=lastTimestamp

# 3. Verificação de caminho de recuperação — histórico zerado, rollout undo indisponível
kubectl rollout history deployment/kube-news -n default

# 4. Causa raiz nº 2 — falha de autenticação no Postgres
kubectl logs <pod> -n default --tail=50
kubectl logs <pod> -n default --previous

# 5. Comparação das credenciais entre app e banco
kubectl get deployment postgres -n default -o yaml

# 6. Validação do roteamento
kubectl get endpoints kube-news -n default

# 7. Validação HTTP end-to-end
kubectl port-forward svc/kube-news 18080:80 -n default
curl -s http://127.0.0.1:18080/health
```
