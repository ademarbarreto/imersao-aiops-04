# 09 — Escalar a aplicação automaticamente com HPA

**Prioridade:** P2 — Média
**Área:** Elasticidade
**Arquivo afetado:** novo — `k8s/app/hpa.yaml`

## Descrição

O `kube-news` está fixo em `replicas: 2`. Não há nenhum `HorizontalPodAutoscaler` no cluster.

Isso significa que a aplicação não responde a variação de carga: sob pico ela satura as 2 réplicas (limite de 500m de CPU cada) e degrada; em ociosidade, mantém capacidade reservada sem uso. O dimensionamento é uma decisão manual e estática.

A aplicação tem tudo o que o HPA precisa para funcionar bem — `resources.requests` declarados (obrigatório para o HPA calcular percentual de utilização) e readiness probe configurada.

## Orientação para a tarefa

1. **Pré-requisito obrigatório:** o card **06** (metrics-server) precisa estar concluído. Sem a Metrics API, o HPA fica com status `unknown` e nunca escala.

2. Criar `k8s/app/hpa.yaml`:

   ```yaml
   apiVersion: autoscaling/v2
   kind: HorizontalPodAutoscaler
   metadata:
     name: kube-news
     namespace: default
   spec:
     scaleTargetRef:
       apiVersion: apps/v1
       kind: Deployment
       name: kube-news
     minReplicas: 2
     maxReplicas: 10
     metrics:
     - type: Resource
       resource:
         name: cpu
         target:
           type: Utilization
           averageUtilization: 70
     - type: Resource
       resource:
         name: memory
         target:
           type: Utilization
           averageUtilization: 80
   ```

3. **Remover o campo `replicas` do Deployment** ou aceitar que o HPA passa a ser dono dele. Manter `replicas` fixo no manifesto e reaplicar com `kubectl apply` cria um conflito onde o deploy desfaz o trabalho do autoscaler.

4. Considerar `behavior` para controlar a velocidade de scale-down e evitar oscilação (flapping) em cargas irregulares.

5. Testar com carga sintética e observar o escalonamento acontecer.

## Critério de aceite

- `kubectl get hpa kube-news` mostra os targets com valores reais (ex.: `5%/70%`), não `<unknown>`
- Sob carga gerada, o número de réplicas **aumenta** automaticamente
- Ao cessar a carga, as réplicas voltam para `minReplicas: 2` após o período de estabilização
- O Deployment não reverte o número de réplicas ao ser reaplicado

## Observações

O HPA depende diretamente de `requests` bem calibrados: ele calcula utilização como percentual do request, não do limit. Com `requests` subestimados, a aplicação escala cedo demais; superestimados, escala tarde demais. Use os dados do metrics-server para calibrar antes de confiar no autoscaler.
