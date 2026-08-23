# 08 — Proteger a aplicação com PodDisruptionBudget

**Prioridade:** P2 — Média
**Área:** Disponibilidade
**Arquivo afetado:** novo — `k8s/app/pdb.yaml`

## Descrição

Não existe nenhum `PodDisruptionBudget` no cluster. Sem ele, o Kubernetes pode derrubar **todas as réplicas do `kube-news` ao mesmo tempo** durante uma disrupção voluntária:

- `kubectl drain` de um nó para manutenção
- Upgrade de versão do cluster
- Reescalonamento por autoscaler de nós

O `kube-news` já tem `maxUnavailable: 0` na estratégia de RollingUpdate, o que protege durante **deploys**. Mas o RollingUpdate não cobre drenagem de nó — são mecanismos diferentes. O PDB é o que informa ao Kubernetes o mínimo que precisa continuar de pé em qualquer operação.

## Orientação para a tarefa

1. Criar `k8s/app/pdb.yaml`:

   ```yaml
   apiVersion: policy/v1
   kind: PodDisruptionBudget
   metadata:
     name: kube-news
     namespace: default
   spec:
     minAvailable: 1
     selector:
       matchLabels:
         app.kubernetes.io/name: kube-news
         app.kubernetes.io/component: web
   ```

2. Usar `minAvailable: 1` com as 2 réplicas atuais. Com mais réplicas, `maxUnavailable: 25%` escala melhor do que um número fixo.

3. **Não crie PDB com `minAvailable` igual ao número de réplicas.** Isso torna a drenagem do nó impossível e trava manutenções — um erro comum e frustrante de diagnosticar.

4. Avaliar se vale um PDB para o Postgres. Com 1 réplica única, um PDB `minAvailable: 1` **bloquearia qualquer drain do nó**. Só faz sentido depois que houver replicação de banco de verdade.

5. Validar com uma drenagem real.

## Critério de aceite

- `kubectl get pdb -n default` mostra `kube-news` com `ALLOWED DISRUPTIONS: 1`
- Durante `kubectl drain <node> --ignore-daemonsets`, pelo menos 1 pod do `kube-news` permanece `Running` a todo momento
- A aplicação continua respondendo durante a drenagem

## Observações

O PDB só tem efeito real quando existem **múltiplos nós** (card 05). Em cluster single-node, drenar o único nó derruba tudo de qualquer forma. Faça o card 05 antes para que este tenha valor prático.
