# 04 — Mover credenciais do banco para Secret

**Prioridade:** P1 — Alta
**Área:** Segurança
**Arquivos afetados:** `k8s/app/deployment.yaml`, `k8s/db/deployment.yaml`

## Descrição

A senha do banco está em **texto plano** nos manifestos dos dois workloads:

```yaml
- name: DB_PASSWORD
  value: Pg#123
```

Há dois agravantes:

1. A senha está **duplicada** — no Deployment da aplicação e no do Postgres. Qualquer rotação exige lembrar dos dois lugares.
2. O Kubernetes replicou o manifesto inteiro no annotation `kubectl.kubernetes.io/last-applied-configuration`. A senha é legível por **qualquer pessoa com permissão de `get deployment`**, mesmo que os manifestos em disco sejam corrigidos depois.

Além disso, a credencial está versionada no Git, o que significa que ela vive no histórico do repositório mesmo após ser removida do arquivo atual.

## Orientação para a tarefa

1. Criar um Secret para as credenciais. **Não commite o Secret com o valor real** — use um dos padrões abaixo:
   - Gerar via linha de comando no ambiente (bom para laboratório):
     ```
     kubectl create secret generic postgres-credentials \
       --from-literal=POSTGRES_USER=kubedevnews \
       --from-literal=POSTGRES_PASSWORD='<nova-senha-forte>' \
       --from-literal=POSTGRES_DB=kubedevnews
     ```
   - Ou adotar **Sealed Secrets** / **External Secrets Operator** para poder versionar com segurança.

2. Referenciar no Deployment da aplicação (`k8s/app/deployment.yaml`):
   ```yaml
   - name: DB_PASSWORD
     valueFrom:
       secretKeyRef:
         name: postgres-credentials
         key: POSTGRES_PASSWORD
   ```

3. Fazer o mesmo no manifesto do Postgres, para `POSTGRES_USER`, `POSTGRES_PASSWORD` e `POSTGRES_DB`. Considere `envFrom.secretRef` para injetar todas de uma vez.

4. Manter em `env` literal apenas o que **não é sensível**: `DB_HOST`, `DB_PORT`, `DB_SSL_REQUIRE`. Esses são bons candidatos a um `ConfigMap`.

5. **Trocar a senha.** A atual (`Pg#123`) deve ser considerada comprometida: está no histórico do Git e nos annotations do cluster. Uma nova senha forte é parte da correção, não um extra.

6. Limpar o annotation com a senha antiga recriando os objetos, ou aplicando com `kubectl apply --server-side --force-conflicts`.

## Critério de aceite

- `grep -ri "Pg#123" k8s/` não retorna nada
- `kubectl get deploy kube-news -o yaml` não expõe a senha em lugar nenhum, incluindo annotations
- `kubectl get secret postgres-credentials` existe e os pods sobem consumindo dele
- A aplicação conecta normalmente ao banco com a nova senha

## Observações

Em produção real, o ideal vai além: senhas geradas dinamicamente com rotação automática (Vault, AWS Secrets Manager). Para este ambiente, sair do texto plano já elimina a exposição mais grosseira.
