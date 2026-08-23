# Cards de Melhoria — Cluster kube-news

Backlog de melhorias derivado do levantamento do cluster `kind-kind` realizado em **22/08/2026**.

Estado do cluster na data do levantamento: **saudável**, 12/12 pods `Running`, 0 restarts, nenhum incidente ativo. Todos os cards abaixo tratam de **risco e maturidade**, não de falha em curso.

## Índice

| # | Card | Prioridade | Área |
|---|---|---|---|
| 01 | [Persistir os dados do Postgres com PVC](01-persistencia-postgres-pvc.md) | 🔴 P0 | Armazenamento |
| 02 | [Migrar o Postgres para StatefulSet](02-postgres-como-statefulset.md) | 🟠 P1 | Arquitetura |
| 03 | [Tornar a imagem recuperável em um registry](03-publicar-imagem-em-registry.md) | 🔴 P0 | Supply chain |
| 04 | [Mover credenciais para Secret](04-credenciais-em-secret.md) | 🟠 P1 | Segurança |
| 05 | [Eliminar o ponto único de falha](05-alta-disponibilidade-multi-node.md) | 🟠 P1 | Disponibilidade |
| 06 | [Instalar o metrics-server](06-instalar-metrics-server.md) | 🟡 P2 | Observabilidade |
| 07 | [Isolar o banco com NetworkPolicy](07-networkpolicy-isolar-banco.md) | 🟡 P2 | Segurança de rede |
| 08 | [Proteger a aplicação com PodDisruptionBudget](08-poddisruptionbudget.md) | 🟡 P2 | Disponibilidade |
| 09 | [Escalar automaticamente com HPA](09-horizontal-pod-autoscaler.md) | 🟡 P2 | Elasticidade |
| 10 | [ResourceQuota e LimitRange](10-resourcequota-e-limitrange.md) | 🟡 P2 | Governança |
| 11 | [Namespace dedicado](11-namespace-dedicado.md) | 🟡 P2 | Organização |
| 12 | [`runAsNonRoot` explícito no Postgres](12-postgres-runasnonroot.md) | 🟢 P3 | Hardening |
| 13 | [Desabilitar automount do token de ServiceAccount](13-desabilitar-automount-serviceaccount.md) | 🟢 P3 | Hardening |
| 14 | [Ingress no lugar de NodePort](14-ingress-no-lugar-de-nodeport.md) | 🟢 P3 | Rede |

## Ordem sugerida de execução

**Onda 1 — parar o sangramento (P0)**
`01` → `03`. São os dois riscos que transformam um ambiente verde em perda real: o banco não persiste e a imagem não é recuperável. Nada mais importa antes destes.

**Onda 2 — fundação (P1)**
`04` → `11` → `02` → `05`. Credenciais fora do texto plano, namespace próprio, banco no modelo de workload correto e topologia multi-node. O `11` vem cedo porque vários cards seguintes assumem namespace dedicado.

**Onda 3 — operação (P2)**
`06` → `07` → `08` → `09` → `10`. Observabilidade primeiro: o `06` desbloqueia o `09` e dá os dados para calibrar o `10`.

**Onda 4 — refinamento (P3)**
`12` → `13` → `14`. Baixo custo, baixo risco. O `14` faz par com o `05` — se ainda não recriou o cluster, junte os dois.

## Dependências entre cards

- `09` (HPA) **exige** `06` (metrics-server) concluído
- `10` (Quota) **pressupõe** `11` (namespace dedicado)
- `08` (PDB) só tem efeito prático com `05` (multi-node)
- `14` (Ingress) aproveita a recriação do cluster feita em `05`
- `02` (StatefulSet) substitui a abordagem de `01` — se for executar os dois, faça `01` primeiro para reduzir risco imediato

## Estrutura de cada card

Todos os cards seguem o mesmo formato: **título**, **descrição** do problema com evidência coletada do cluster, **orientação para a tarefa** com passos e YAML de referência, **critério de aceite** verificável e **observações** sobre dependências e armadilhas.
