# 05 — Eliminar o ponto único de falha (cluster multi-node)

**Prioridade:** P1 — Alta
**Área:** Disponibilidade / Topologia
**Arquivos afetados:** configuração do kind, `k8s/app/deployment.yaml`

## Descrição

O cluster tem **um único nó**, `kind-control-plane`, que acumula todas as funções:

- Control plane (etcd, apiserver, scheduler, controller-manager)
- Workloads da aplicação e do banco

Além disso, o taint `node-role.kubernetes.io/control-plane` foi **removido** (`Taints: <none>`), permitindo que pods de aplicação sejam agendados junto dos componentes críticos do cluster.

A consequência prática: as 2 réplicas do `kube-news` dão **zero resiliência real**. Elas rodam no mesmo nó, no mesmo kernel, no mesmo Docker. Se o nó cai, cai tudo — aplicação, banco e control plane simultaneamente. O `replicas: 2` transmite uma sensação de redundância que não existe.

## Orientação para a tarefa

1. Recriar o cluster kind com topologia multi-node, via `kind-config.yaml`:

   ```yaml
   kind: Cluster
   apiVersion: kind.x-k8s.io/v1alpha4
   nodes:
   - role: control-plane
   - role: worker
   - role: worker
   ```
   ```
   kind create cluster --config kind-config.yaml
   ```

2. **Não remover o taint do control-plane.** Deixe os workers receberem as aplicações. Isso reproduz a separação de responsabilidades de um cluster real.

3. Adicionar `podAntiAffinity` ao `kube-news` para que as réplicas se espalhem entre nós distintos:

   ```yaml
   affinity:
     podAntiAffinity:
       preferredDuringSchedulingIgnoredDuringExecution:
       - weight: 100
         podAffinityTerm:
           topologyKey: kubernetes.io/hostname
           labelSelector:
             matchLabels:
               app.kubernetes.io/name: kube-news
   ```

   Alternativa mais moderna e declarativa — `topologySpreadConstraints` com `maxSkew: 1`.

4. Atenção ao card **01**: a StorageClass `local-path` prende o volume a um nó específico. Com múltiplos nós, o pod do Postgres passa a depender do nó onde o volume foi criado. Isso é esperado e aceitável em laboratório — o `WaitForFirstConsumer` já cuida do agendamento coerente.

5. Revalidar todos os manifestos no cluster novo.

## Critério de aceite

- `kubectl get nodes` mostra 3 nós `Ready` (1 control-plane + 2 workers)
- `kubectl describe node <control-plane>` mostra o taint `NoSchedule` presente
- `kubectl get pods -o wide` mostra as duas réplicas do `kube-news` em **nós diferentes**
- Nenhum pod de aplicação agendado no control-plane

## Observações

Em laboratório (kind), isso não entrega HA de verdade — todos os nós continuam sendo containers no mesmo host. O valor está em **exercitar a topologia correta**: anti-affinity, taints e comportamento de scheduling se comportam como em produção, e os manifestos ficam prontos para um cluster real.
