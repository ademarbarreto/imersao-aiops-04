# 11 — Mover a aplicação para um namespace dedicado

**Prioridade:** P2 — Média
**Área:** Organização / Isolamento
**Arquivos afetados:** todos em `k8s/`

## Descrição

Toda a aplicação — `kube-news`, `postgres` e seus Services — está no namespace **`default`**.

O `default` é o namespace de conveniência: é onde recursos caem quando ninguém decidiu onde eles deveriam estar. Usá-lo como destino permanente impede quatro coisas:

- **ResourceQuota e LimitRange** (card 10) por aplicação
- **RBAC granular** — permissões escopadas a quem cuida desta aplicação
- **NetworkPolicy por namespace** (card 07) com regras de fronteira claras
- **Limpeza atômica** — `kubectl delete namespace` remove tudo de uma vez, sem rastrear objeto por objeto

Também aumenta o risco operacional: um `kubectl delete` distraído no `default` atinge recursos que ninguém pretendia tocar.

## Orientação para a tarefa

1. Criar `k8s/namespace.yaml`:

   ```yaml
   apiVersion: v1
   kind: Namespace
   metadata:
     name: kube-news
     labels:
       app.kubernetes.io/name: kube-news
   ```

2. Adicionar `namespace: kube-news` no `metadata` de **todos** os manifestos em `k8s/` — Deployments, Services, PVC, Secret, NetworkPolicy, PDB, HPA.

   > Alternativa mais limpa: usar **Kustomize** com `namespace: kube-news` no `kustomization.yaml`, que injeta o namespace em todos os recursos sem repetição. Isso também elimina o risco de esquecer um arquivo.

3. Conferir que o DNS interno continua correto. Como aplicação e banco ficam **no mesmo namespace**, o host `postgres` continua resolvendo sem alteração. Se um dia forem separados, será preciso o FQDN: `postgres.kube-news.svc.cluster.local`.

4. Aplicar no namespace novo, validar, e só então remover os recursos antigos do `default`.

5. Definir o contexto padrão para evitar erro humano:
   ```
   kubectl config set-context --current --namespace=kube-news
   ```

## Critério de aceite

- `kubectl get all -n kube-news` lista todos os recursos da aplicação
- `kubectl get all -n default` mostra apenas o Service `kubernetes` (nativo do cluster)
- A aplicação responde normalmente e conecta ao banco
- Nenhum manifesto em `k8s/` depende do namespace implícito

## Observações

Este card é pré-requisito prático do card **10** e potencializa o **07**. Executar os três em sequência entrega o isolamento completo do ambiente.
