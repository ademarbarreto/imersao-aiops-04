# 13 — Desabilitar o automount do token de ServiceAccount

**Prioridade:** P3 — Baixa
**Área:** Segurança / Redução de superfície
**Arquivos afetados:** `k8s/app/deployment.yaml`, `k8s/db/deployment.yaml`

## Descrição

Ambos os workloads usam a ServiceAccount `default` do namespace e, por comportamento padrão do Kubernetes, recebem um **token de acesso à API do cluster** montado automaticamente em:

```
/var/run/secrets/kubernetes.io/serviceaccount/token
```

Nem o `kube-news` nem o `postgres` conversam com a API do Kubernetes. Nenhum dos dois precisa desse token — ele é superfície de ataque pura. Se um container for comprometido (via RCE na aplicação, por exemplo), o atacante encontra credenciais válidas do cluster prontas para uso, e passa a poder enumerar recursos conforme as permissões da ServiceAccount `default`.

Remover o que não é usado é o hardening de menor custo e menor risco disponível.

## Orientação para a tarefa

1. Adicionar ao `spec` do pod template dos dois Deployments:

   ```yaml
   spec:
     automountServiceAccountToken: false
     containers:
     - name: ...
   ```

2. Alternativa mais abrangente — desabilitar na própria ServiceAccount, cobrindo todos os pods que a usarem:

   ```yaml
   apiVersion: v1
   kind: ServiceAccount
   metadata:
     name: default
     namespace: kube-news
   automountServiceAccountToken: false
   ```

3. Como boa prática adicional, criar uma **ServiceAccount dedicada por aplicação** em vez de usar a `default`. Isso permite RBAC granular no dia em que algum workload realmente precisar falar com a API — e deixa claro, pela leitura do manifesto, que a escolha foi deliberada.

4. Validar que as aplicações continuam funcionando. Como nenhuma usa a API, o impacto esperado é zero.

## Critério de aceite

- `kubectl exec <pod> -- ls /var/run/secrets/kubernetes.io/serviceaccount/` retorna erro de diretório inexistente
- `kubectl get pod <pod> -o yaml` mostra `automountServiceAccountToken: false`
- A aplicação `kube-news` responde normalmente e conecta ao banco
- O Postgres continua `1/1 Running`

## Observações

Duas linhas de YAML, impacto operacional nulo, uma superfície de ataque a menos. É o tipo de mudança que só custa caro quando não é feita.
