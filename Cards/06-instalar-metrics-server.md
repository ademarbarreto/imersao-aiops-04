# 06 — Instalar o metrics-server

**Prioridade:** P2 — Média
**Área:** Observabilidade
**Arquivo afetado:** novo — `k8s/infra/metrics-server.yaml` (ou instalação via manifest oficial)

## Descrição

O cluster não tem a Metrics API disponível:

```
$ kubectl top nodes
error: Metrics API not available
```

Sem o metrics-server, você não consegue:

- Rodar `kubectl top nodes` / `kubectl top pods` — nenhuma visibilidade de consumo real
- Usar **HorizontalPodAutoscaler** (card 09), que depende da Metrics API
- Validar se os `requests` e `limits` declarados nos manifestos fazem sentido frente ao consumo real

Hoje os valores de resources (`100m/128Mi` para o `kube-news`, `100m/256Mi` para o Postgres) foram definidos por estimativa, sem nenhum dado que os confirme. É a instalação de maior retorno imediato no cluster.

## Orientação para a tarefa

1. Aplicar o manifesto oficial:
   ```
   kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
   ```

2. **No kind, é necessário um ajuste.** Os kubelets usam certificados auto-assinados, e o metrics-server rejeita a conexão por padrão. Adicione a flag ao Deployment:

   ```
   kubectl patch deployment metrics-server -n kube-system --type=json \
     -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
   ```

   > `--kubelet-insecure-tls` é aceitável em laboratório. Em produção, configure os certificados do kubelet corretamente em vez de desabilitar a verificação.

3. Aguardar o pod ficar `Running` e o APIService `v1beta1.metrics.k8s.io` reportar `Available`.

4. Com métricas em mãos, revisar os `requests`/`limits` dos dois workloads comparando com o consumo observado.

## Critério de aceite

- `kubectl get apiservice v1beta1.metrics.k8s.io` mostra `AVAILABLE: True`
- `kubectl top nodes` retorna consumo de CPU e memória do nó
- `kubectl top pods -A` lista o consumo de todos os pods
- Os valores de `requests` dos workloads foram revisados com base nos dados reais

## Observações

O metrics-server entrega métricas **instantâneas**, não histórico. Para séries temporais, dashboards e alertas, o próximo passo é a stack Prometheus + Grafana (`kube-prometheus-stack` via Helm) — um card futuro, quando este ambiente amadurecer.
