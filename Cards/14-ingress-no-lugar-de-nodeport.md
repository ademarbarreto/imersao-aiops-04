# 14 — Expor a aplicação via Ingress em vez de NodePort

**Prioridade:** P3 — Baixa
**Área:** Rede / Exposição
**Arquivo afetado:** `k8s/app/service.yaml`, novo `k8s/app/ingress.yaml`

## Descrição

A aplicação está exposta por um Service do tipo **NodePort** na porta `30080`:

```yaml
type: NodePort
ports:
- port: 80
  targetPort: 8080
  nodePort: 30080
```

O NodePort funciona e é adequado para laboratório, mas tem limitações que não sobrevivem a um ambiente real:

- Porta restrita à faixa `30000-32767` — nada de 80/443 direto
- Abre a porta em **todos os nós** do cluster, ampliando a superfície exposta
- Sem TLS, sem roteamento por host ou path, sem uma porta de entrada única
- Não escala: cada aplicação nova consome mais uma porta e mais uma URL esquisita

Um Ingress resolve tudo isso com um único ponto de entrada, roteamento por nome de host e terminação TLS centralizada.

## Orientação para a tarefa

1. Instalar um Ingress Controller. No kind, o `ingress-nginx` tem um manifesto próprio:
   ```
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
   ```

   > O cluster precisa ter sido criado com `extraPortMappings` para as portas 80 e 443 no `kind-config.yaml`. Aproveite o card **05**, que já recria o cluster, para incluir esse ajuste de uma vez.

2. Mudar o Service do `kube-news` de `NodePort` para **`ClusterIP`** — com Ingress, a exposição direta do Service deixa de ser necessária.

3. Criar `k8s/app/ingress.yaml`:

   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: kube-news
     namespace: kube-news
   spec:
     ingressClassName: nginx
     rules:
     - host: kube-news.localhost
       http:
         paths:
         - path: /
           pathType: Prefix
           backend:
             service:
               name: kube-news
               port:
                 number: 80
   ```

4. Como evolução, adicionar TLS. Em cluster real, **cert-manager** com Let's Encrypt automatiza emissão e renovação de certificados.

## Critério de aceite

- `kubectl get ingress -n kube-news` mostra o recurso com endereço atribuído
- A aplicação responde em `http://kube-news.localhost` (porta 80, sem `:30080`)
- `kubectl get svc kube-news` mostra `TYPE: ClusterIP`
- Nenhuma porta NodePort permanece aberta nos nós

## Observações

Faz par natural com o card **05**, que já envolve recriar o cluster kind — aproveite para incluir os `extraPortMappings` e evitar recriar duas vezes.
