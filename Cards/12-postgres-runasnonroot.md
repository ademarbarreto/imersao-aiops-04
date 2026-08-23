# 12 — Declarar `runAsNonRoot` explicitamente no Postgres

**Prioridade:** P3 — Baixa
**Área:** Segurança / Hardening
**Arquivo afetado:** `k8s/db/deployment.yaml`

## Descrição

O `securityContext` do Postgres define usuário e grupo, mas **não declara `runAsNonRoot: true`**:

```yaml
securityContext:
  fsGroup: 999
  runAsGroup: 999
  runAsUser: 999
```

Na prática o container roda como uid 999 (não-root), então o comportamento atual está correto. O problema é que isso é uma **coincidência de configuração, não uma garantia**. Sem `runAsNonRoot: true`, o kubelet não valida nada: se alguém alterar o `runAsUser` para 0, ou se a imagem for trocada por uma que define `USER root`, o container sobe como root sem nenhum bloqueio.

Vale notar o contraste com o `kube-news`, cujo securityContext está exemplar — `runAsNonRoot: true`, uid/gid 1000, `allowPrivilegeEscalation: false` e `capabilities.drop: [ALL]`. Este card apenas nivela o banco ao mesmo padrão.

## Orientação para a tarefa

1. Adicionar a garantia no `securityContext` de pod do Postgres:

   ```yaml
   securityContext:
     runAsNonRoot: true
     runAsUser: 999
     runAsGroup: 999
     fsGroup: 999
   ```

2. Confirmar que o `securityContext` de container já presente permanece:
   ```yaml
   securityContext:
     allowPrivilegeEscalation: false
     capabilities:
       drop: ["ALL"]
   ```

3. Considerar `readOnlyRootFilesystem: true` — exige mapear os diretórios de escrita do Postgres (`/var/run/postgresql`, `/tmp`) como `emptyDir`. É um hardening a mais, com custo de teste.

4. Validar que o `fsGroup: 999` continua dando ao Postgres permissão de escrita no volume persistente (card 01). Essa é a parte que costuma quebrar: se o pod entrar em `CrashLoopBackOff` com erro de permissão em `PGDATA`, o `fsGroup` é o primeiro lugar a olhar.

5. Como evolução, aplicar **Pod Security Standards** no namespace, que passa a impor essas regras a todos os pods:
   ```
   kubectl label namespace kube-news \
     pod-security.kubernetes.io/enforce=restricted
   ```

## Critério de aceite

- `kubectl get pod <postgres> -o jsonpath='{.spec.securityContext}'` inclui `runAsNonRoot: true`
- O pod sobe `1/1 Running` sem erro de permissão
- `kubectl exec <postgres> -- id` retorna uid 999, não 0
- O banco lê e escreve normalmente no volume

## Observações

Item de hardening, não de correção — nada está quebrado hoje. O valor é transformar um acerto acidental em uma garantia que o cluster faz cumprir.
