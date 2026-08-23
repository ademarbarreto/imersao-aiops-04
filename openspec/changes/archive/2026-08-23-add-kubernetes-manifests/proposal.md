## Why

A aplicação kube-news hoje só roda localmente via `docker-compose`. Para rodar em um cluster Kubernetes, precisamos de manifestos que descrevam a app e o banco de dados como workloads do cluster, com exposição de rede adequada.

## What Changes

- Adiciona manifestos Kubernetes em `k8s/` para a aplicação (`app`) e para o banco de dados (`db`), um arquivo por objeto.
- `app`: `Deployment` com múltiplas réplicas, imagem com tag versionada (não `latest`), probes de liveness/readiness apontando para `/health` e `/ready`, e `Service` do tipo `LoadBalancer`.
- `db`: `Deployment` com 1 réplica, estratégia de rollout `Recreate`, volume via `PersistentVolumeClaim` (ReadWriteOnce), e `Service` do tipo `ClusterIP`.
- Credenciais de banco (`DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`) continuam como variáveis de ambiente simples nos manifestos (sem uso de `Secret` neste momento).
- Validação obrigatória: aplicar os manifestos em um cluster `kind` efêmero e exercitar a aplicação (via `port-forward`, já que `kind` não provisiona `LoadBalancer` real) antes de considerar a mudança concluída.

## Capabilities

### New Capabilities
- `kubernetes-deployment`: Descreve como a aplicação e o banco de dados são implantados e expostos em um cluster Kubernetes (Deployments, Services, probes, storage).

### Modified Capabilities
(nenhuma — não há specs existentes em `openspec/specs/`)

## Impact

- Novo diretório `k8s/` com manifestos YAML (não afeta `docker-compose.yml` nem o `Dockerfile` existentes).
- Nenhuma mudança de código-fonte da aplicação.
- Passa a exigir uma imagem publicada com tag versionada (ex.: `fabricioveronez/kube-news-imersao:v1`) em vez da tag `latest` usada localmente.
