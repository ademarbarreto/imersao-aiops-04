# 02 — Migrar o Postgres de Deployment para StatefulSet

**Prioridade:** P1 — Alta
**Área:** Arquitetura de workload
**Arquivo afetado:** `k8s/db/deployment.yaml` → `k8s/db/statefulset.yaml`

## Descrição

O Postgres está declarado como `Deployment`. Deployments foram desenhados para workloads **stateless e intercambiáveis**: os pods têm nomes aleatórios, sobem em qualquer ordem e são tratados como descartáveis.

Um banco de dados não é nada disso. Ele precisa de identidade estável, volume atrelado a essa identidade e ordem previsível de criação e terminação. O objeto correto do Kubernetes para isso é o `StatefulSet`.

Hoje o sintoma é discreto porque há apenas 1 réplica, mas o modelo errado cobra o preço na hora do incidente: rollouts que anexam volume no pod errado, ordem de terminação imprevisível e nenhum caminho de evolução para réplica de leitura ou cluster.

## Orientação para a tarefa

1. Criar `k8s/db/statefulset.yaml` convertendo o Deployment atual, com três mudanças estruturais:

   - `kind: StatefulSet`
   - Adicionar `serviceName: postgres` (aponta para o Service headless do passo 2)
   - Trocar a seção `volumes` por `volumeClaimTemplates`:

   ```yaml
   spec:
     serviceName: postgres
     replicas: 1
     selector:
       matchLabels:
         app.kubernetes.io/name: postgres
         app.kubernetes.io/component: database
     template:
       # ... mesmo pod template atual (env, probes, resources, securityContext)
     volumeClaimTemplates:
     - metadata:
         name: postgres-data
       spec:
         accessModes: [ "ReadWriteOnce" ]
         resources:
           requests:
             storage: 5Gi
   ```

2. Ajustar `k8s/db/service.yaml` para um Service **headless** (`clusterIP: None`). O StatefulSet usa esse Service para dar DNS estável ao pod (`postgres-0.postgres.default.svc.cluster.local`).

3. Preservar integralmente do manifesto atual: as probes `pg_isready`, os `resources`, o `securityContext` (uid/gid 999, `fsGroup: 999`) e a variável `PGDATA`.

4. Se o card **01** já estiver aplicado e houver dados a preservar, faça dump antes de migrar: `kubectl exec <pod> -- pg_dump -U kubedevnews kubedevnews > backup.sql`. A troca de Deployment para StatefulSet não reaproveita o PVC anterior automaticamente — o nome gerado é `postgres-data-postgres-0`.

5. Remover o Deployment antigo só depois que o StatefulSet estiver `Running` e validado.

## Critério de aceite

- `kubectl get statefulset postgres` mostra `1/1 READY`
- O pod se chama `postgres-0` (identidade estável, não hash aleatório)
- `kubectl get pvc` mostra `postgres-data-postgres-0` **Bound**
- A aplicação `kube-news` continua conectando normalmente pelo host `postgres`
- Após `kubectl delete pod postgres-0`, o pod volta com o mesmo nome e o mesmo volume

## Observações

Depende do entendimento do card **01**. Se ainda não aplicou nenhum dos dois, é legítimo pular direto para este card e resolver persistência e modelo de workload de uma vez.
