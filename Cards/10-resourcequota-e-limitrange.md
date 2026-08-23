# 10 — Governança de recursos com ResourceQuota e LimitRange

**Prioridade:** P2 — Média
**Área:** Governança / Multi-tenancy
**Arquivo afetado:** novo — `k8s/infra/quota.yaml`

## Descrição

Não existe nenhum `ResourceQuota` nem `LimitRange` no cluster. Duas consequências:

1. **Sem teto agregado.** Nada impede que um workload — ou um erro de digitação em `replicas` — consuma toda a capacidade do nó (15 vCPU / 7,75 GiB) e cause eviction dos demais pods, inclusive do banco de dados.

2. **Sem piso por pod.** Qualquer pod criado sem `resources` declarados entra na classe **BestEffort** e é o primeiro candidato a ser morto sob pressão de memória. Hoje os manifestos do projeto declaram resources corretamente, mas nada obriga que o próximo continue fazendo isso.

O consumo atual é baixo (CPU requests em 8%, memória em 10%), então não há urgência — o valor deste card é preventivo e de disciplina.

## Orientação para a tarefa

1. Criar um `LimitRange` para estabelecer defaults e limites por pod no namespace:

   ```yaml
   apiVersion: v1
   kind: LimitRange
   metadata:
     name: default-limits
     namespace: kube-news
   spec:
     limits:
     - type: Container
       default:
         cpu: 500m
         memory: 256Mi
       defaultRequest:
         cpu: 100m
         memory: 128Mi
       max:
         cpu: "2"
         memory: 1Gi
   ```

   Com isso, um container sem `resources` recebe valores automaticamente, em vez de virar BestEffort.

2. Criar um `ResourceQuota` limitando o total do namespace:

   ```yaml
   apiVersion: v1
   kind: ResourceQuota
   metadata:
     name: namespace-quota
     namespace: kube-news
   spec:
     hard:
       requests.cpu: "4"
       requests.memory: 4Gi
       limits.cpu: "8"
       limits.memory: 8Gi
       persistentvolumeclaims: "5"
       pods: "20"
   ```

3. Dimensionar os valores com base nos dados reais do metrics-server (card 06), não por chute.

4. **Atenção:** uma vez que existe ResourceQuota para CPU/memória no namespace, **todo pod passa a ser obrigado a declarar requests e limits**. Pods sem declaração são rejeitados na criação. Por isso aplique o `LimitRange` **antes** da quota — ele fornece os defaults que evitam a rejeição.

## Critério de aceite

- `kubectl describe quota -n <namespace>` mostra o uso atual contra os limites configurados
- `kubectl describe limitrange -n <namespace>` mostra os defaults ativos
- Um pod de teste criado **sem** `resources` sobe e recebe os valores do LimitRange automaticamente
- Uma tentativa de escalar além da quota é **rejeitada** com mensagem clara
- Os workloads existentes continuam rodando sem alteração

## Observações

Depende do card **11** (namespace dedicado) para fazer sentido pleno — quota no namespace `default` é um instrumento sem dono. Faça os dois juntos.
