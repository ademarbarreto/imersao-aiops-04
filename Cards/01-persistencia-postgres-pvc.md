# 01 — Persistir os dados do Postgres com PersistentVolumeClaim

**Prioridade:** P0 — Crítico
**Área:** Armazenamento / Confiabilidade
**Arquivo afetado:** `k8s/db/deployment.yaml`

## Descrição

O Postgres hoje armazena o banco em um volume `emptyDir`, que vive e morre junto com o pod:

```yaml
volumes:
- emptyDir: {}
  name: postgres-data
```

Não existe **nenhum PersistentVolumeClaim no cluster inteiro**. Isso significa que qualquer restart do container, eviction, rollout, upgrade de imagem ou reagendamento do pod **apaga o banco de dados por completo**, sem aviso e sem recuperação.

Não é um risco teórico — é o comportamento definido pelo manifesto. Enquanto este card não for resolvido, o ambiente não pode receber nenhum dado que importe.

O cluster já tem a StorageClass `standard` (provisioner `rancher.io/local-path`) marcada como default, com `volumeBindingMode: WaitForFirstConsumer`. Não é preciso instalar nada.

## Orientação para a tarefa

1. Criar o arquivo `k8s/db/pvc.yaml` com um PVC usando a StorageClass default:

   ```yaml
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: postgres-data
     namespace: default
     labels:
       app.kubernetes.io/name: postgres
       app.kubernetes.io/component: database
   spec:
     accessModes:
       - ReadWriteOnce
     resources:
       requests:
         storage: 5Gi
   ```

2. Em `k8s/db/deployment.yaml`, trocar o volume `emptyDir` pela referência ao PVC:

   ```yaml
   volumes:
   - name: postgres-data
     persistentVolumeClaim:
       claimName: postgres-data
   ```

3. Manter o `volumeMount` em `/var/lib/postgresql/data` e a variável `PGDATA: /var/lib/postgresql/data/pgdata` como já estão — o subdiretório `pgdata` evita conflito com o `lost+found` de alguns provisionadores.

4. Manter `strategy: Recreate` no Deployment. Com um volume `ReadWriteOnce`, um RollingUpdate travaria tentando anexar o mesmo volume a dois pods.

5. Aplicar e validar.

## Critério de aceite

- `kubectl get pvc -n default` mostra `postgres-data` com status **Bound**
- O pod do Postgres sobe `1/1 Running` usando o PVC
- Após inserir dados na aplicação e rodar `kubectl delete pod -l app.kubernetes.io/name=postgres`, os dados **continuam lá** quando o novo pod sobe
- `kubectl describe pod` do Postgres mostra o volume como `PersistentVolumeClaim`, não `EmptyDir`

## Observações

Este card resolve a persistência imediata. A evolução natural — usar `StatefulSet` com `volumeClaimTemplates` — está no card **02**. Faça este primeiro: ele para a sangria com o menor risco.
