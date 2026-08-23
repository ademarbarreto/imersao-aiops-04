# 07 — Isolar o banco de dados com NetworkPolicy

**Prioridade:** P2 — Média
**Área:** Segurança de rede
**Arquivo afetado:** novo — `k8s/db/networkpolicy.yaml`

## Descrição

Não existe **nenhuma NetworkPolicy no cluster**. O modelo padrão do Kubernetes é rede totalmente plana: qualquer pod, em qualquer namespace, alcança qualquer outro pod em qualquer porta.

Na prática, isso significa que **qualquer pod do cluster consegue abrir conexão na porta 5432 do Postgres**. Um container comprometido, um pod de debug esquecido ou uma aplicação de terceiro têm caminho direto até o banco. A senha em texto plano (card 04) torna esse cenário ainda mais concreto.

É o ganho de segurança mais barato disponível neste ambiente: um manifesto pequeno, sem impacto na aplicação.

## Orientação para a tarefa

1. Confirmar que a CNI suporta NetworkPolicy. O cluster usa **kindnet**, que tem suporte nas versões recentes. Se não funcionar, recriar o kind com `disableDefaultCNI: true` e instalar **Calico** ou **Cilium**.

2. Criar `k8s/db/networkpolicy.yaml` restringindo o ingress do Postgres apenas à aplicação:

   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: postgres-allow-app
     namespace: default
   spec:
     podSelector:
       matchLabels:
         app.kubernetes.io/name: postgres
         app.kubernetes.io/component: database
     policyTypes:
     - Ingress
     ingress:
     - from:
       - podSelector:
           matchLabels:
             app.kubernetes.io/name: kube-news
             app.kubernetes.io/component: web
       ports:
       - protocol: TCP
         port: 5432
   ```

3. Como evolução, adicionar uma policy `default-deny` de ingress no namespace e liberar explicitamente o que é necessário — inclusive **egress para o DNS** (porta 53 UDP/TCP em `kube-system`), que costuma ser o erro clássico ao adotar default-deny.

4. Testar de verdade: subir um pod avulso e confirmar que ele **não** consegue alcançar o banco.

## Critério de aceite

- `kubectl get networkpolicy -n default` lista a policy
- A aplicação `kube-news` continua funcionando normalmente (leitura e escrita no banco)
- Um pod de teste sem os labels da aplicação **falha** ao conectar:
  ```
  kubectl run test --rm -it --image=busybox --restart=Never -- nc -zv postgres 5432
  ```
  deve dar timeout

## Observações

NetworkPolicy é allowlist: uma vez que um pod é selecionado por alguma policy de Ingress, tudo que não estiver explicitamente permitido passa a ser negado. Teste a aplicação após aplicar — não confie apenas no manifesto.
