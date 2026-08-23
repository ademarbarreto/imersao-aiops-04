## Context

kube-news roda hoje via `docker-compose.yml`: um serviço `app` (Node/Express, porta 8080, buildado de `src/Dockerfile`) e um serviço `db` (Postgres 16), conectados por variáveis de ambiente (`DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`).

A aplicação expõe dois endpoints relevantes para health checking (`src/system-life.js`):
- `GET /health`: sempre responde "up" a menos que `PUT /unhealth` tenha sido chamado — é um sinalizador manual, não uma checagem real de dependências (não testa conexão com o Postgres).
- `GET /ready`: compara um timestamp interno com o relógio atual; só fica "not ready" se `PUT /unreadyfor/:seconds` for chamado. Também não reflete o estado real da conexão com o banco.

A validação da mudança ocorre aplicando os manifestos em um cluster `kind` efêmero.

## Goals / Non-Goals

**Goals:**
- Manifestos Kubernetes (`k8s/`) que sobem a aplicação e o banco de dados como workloads independentes.
- Expor a aplicação para receber tráfego externo.
- Persistir os dados do Postgres entre reinícios do pod, dentro do cluster.

**Non-Goals:**
- Não cobre Helm chart, Kustomize, Ingress, HPA, NetworkPolicy ou RBAC.
- Não introduz gerenciamento de segredos (`Secret`) — fica para uma mudança futura.
- Não garante alta disponibilidade do Postgres (fica com 1 réplica, sem replicação).
- Não resolve a limitação de `/health` e `/ready` não checarem a conexão real com o banco — isso é comportamento existente da aplicação, fora do escopo desta mudança.

## Decisions

**App como `Deployment` + `Service` tipo `LoadBalancer`.**
Múltiplas réplicas da app atrás de um `Service` externo. Alternativa considerada: `NodePort` — descartada porque `LoadBalancer` é o padrão esperado para expor uma aplicação web em clusters gerenciados (EKS/GKE/AKS); em `kind` local, o Service ficará com `EXTERNAL-IP` em `<pending>`, e a validação usará `kubectl port-forward` como substituto.

**DB como `Deployment` (não `StatefulSet`) com 1 réplica.**
Decisão explícita do usuário: não há necessidade de identidade estável de rede/storage por réplica (só existe uma réplica), então o overhead conceitual de um `StatefulSet` não se justifica aqui.

**DB com `PersistentVolumeClaim` (ReadWriteOnce) em vez de `emptyDir`.**
Alternativa considerada e inicialmente recomendada: `emptyDir` (mais simples, alinhado ao escopo restrito de objetos da skill de manifestos). Descartada a pedido do usuário em favor de persistência real dos dados entre reinícios do pod — mais fiel ao volume nomeado (`db-data`) já usado no `docker-compose.yml`.

**DB com `strategy: Recreate`.**
Consequência direta de usar PVC com `ReadWriteOnce` num Deployment: com a estratégia padrão (`RollingUpdate`), o pod novo tentaria montar o mesmo volume antes do pod antigo liberá-lo, travando o rollout. `Recreate` derruba o pod antigo antes de subir o novo, evitando esse conflito.

**Imagem da app com tag versionada, não `latest`.**
O `docker-compose.yml` builda a imagem sem tag explícita (`latest` implícito). Para o manifesto Kubernetes, a imagem usa uma tag imutável (ex.: `fabricioveronez/kube-news-imersao:v1`), evitando ambiguidade sobre qual conteúdo está rodando após um `kubectl rollout restart`.

**Credenciais como env vars simples, sem `Secret`.**
Decisão explícita do usuário para manter o escopo desta mudança restrito a workloads e rede — gestão de segredos fica para depois.

## Risks / Trade-offs

- [`LoadBalancer` não recebe IP externo em `kind`] → Validar via `kubectl port-forward svc/app 8080:8080` durante o teste local; em cluster gerenciado real, o comportamento nativo do provedor de nuvem resolve isso.
- [`/health` e `/ready` não refletem o estado real da conexão com o Postgres] → Aceito como limitação conhecida da aplicação; os probes ainda detectam se o processo Node está de pé e respondendo, o que já cobre o caso mais comum (pod travado/não inicializado).
- [Credenciais em texto claro no manifesto] → Aceito para o escopo atual; deve ser revisitado antes de qualquer uso além de ambiente de aprendizado/validação.
- [PVC com `ReadWriteOnce` restringe o Postgres a rodar sempre no mesmo nó com storage disponível] → Aceitável com 1 réplica fixa; não escala horizontalmente, mas não é um objetivo desta mudança.

## Migration Plan

1. Publicar a imagem da app com a tag versionada usada no manifesto (`fabricioveronez/kube-news-imersao:v1`).
2. Criar cluster `kind` efêmero para validação.
3. Aplicar os manifestos em `k8s/` (`kubectl apply -f k8s/`).
4. Validar: pods `Running`, `Service` da app acessível via `port-forward`, fluxo de criação/listagem de posts funcionando fim a fim contra o Postgres.
5. Destruir o cluster `kind` de validação.

Não há rollback formal — trata-se da introdução inicial dos manifestos, sem estado anterior em produção a reverter.

## Open Questions

Nenhuma pendente — todas as decisões de design foram fechadas durante a exploração prévia.
