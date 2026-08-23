# kubernetes-deployment

## Purpose

TBD - Fazer a aplicação kube-news e sua dependência de banco de dados rodarem em um cluster Kubernetes, com a aplicação exposta externamente e o banco de dados acessível apenas internamente.

## Requirements

### Requirement: Application Deployment
A aplicação kube-news SHALL rodar como um Kubernetes `Deployment`, com múltiplas réplicas, imagem referenciada por tag imutável (não `latest`), e probes de liveness e readiness configurados.

#### Scenario: Deployment sobe com múltiplos pods saudáveis
- **WHEN** o manifesto do Deployment da aplicação é aplicado no cluster
- **THEN** o número de réplicas especificado fica no estado `Running` e `Ready`

#### Scenario: Liveness probe usa o endpoint de health
- **WHEN** o kubelet executa a liveness probe do pod da aplicação
- **THEN** a probe chama `GET /health` e reinicia o container apenas se a resposta não for bem-sucedida

#### Scenario: Readiness probe usa o endpoint de readiness
- **WHEN** o kubelet executa a readiness probe do pod da aplicação
- **THEN** a probe chama `GET /ready` e remove o pod dos endpoints do Service enquanto a resposta não for bem-sucedida

#### Scenario: Imagem usa tag imutável
- **WHEN** o manifesto do Deployment da aplicação referencia a imagem do container
- **THEN** a tag usada é uma versão explícita (ex.: `v1`), nunca `latest`

### Requirement: Application Service Exposure
A aplicação SHALL ser exposta por um `Service` do tipo `LoadBalancer`, permitindo receber tráfego externo ao cluster.

#### Scenario: Service expõe a porta da aplicação
- **WHEN** o manifesto do Service da aplicação é aplicado no cluster
- **THEN** o Service é do tipo `LoadBalancer` e encaminha tráfego para a porta 8080 dos pods da aplicação

### Requirement: Database Deployment
O banco de dados PostgreSQL SHALL rodar como um Kubernetes `Deployment` com exatamente 1 réplica, estratégia de rollout `Recreate`, e armazenamento persistente via `PersistentVolumeClaim`.

#### Scenario: Deployment do banco sobe com 1 réplica
- **WHEN** o manifesto do Deployment do banco de dados é aplicado no cluster
- **THEN** exatamente 1 pod do banco de dados fica no estado `Running` e `Ready`

#### Scenario: Dados persistem entre reinícios do pod
- **WHEN** o pod do banco de dados é reiniciado ou recriado
- **THEN** os dados gravados anteriormente no volume da `PersistentVolumeClaim` continuam disponíveis

#### Scenario: Rollout usa estratégia Recreate
- **WHEN** o Deployment do banco de dados sofre uma atualização
- **THEN** o pod antigo é terminado e libera a `PersistentVolumeClaim` antes do novo pod ser criado

### Requirement: Database Service Exposure
O banco de dados SHALL ser exposto internamente ao cluster por um `Service` do tipo `ClusterIP`, usado pela aplicação para se conectar via `DB_HOST`.

#### Scenario: Aplicação se conecta ao banco pelo Service interno
- **WHEN** o pod da aplicação resolve a variável de ambiente `DB_HOST`
- **THEN** o valor aponta para o nome do Service `ClusterIP` do banco de dados, e a conexão na porta configurada é bem-sucedida
