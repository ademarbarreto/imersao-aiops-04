# 03 — Tornar a imagem da aplicação recuperável em um registry

**Prioridade:** P0 — Crítico
**Área:** Supply chain / Reprodutibilidade
**Arquivo afetado:** `k8s/app/deployment.yaml`, `src/Dockerfile`

## Descrição

Durante o levantamento do cluster, dois pods do `kube-news` entraram em `ImagePullBackOff` com o erro:

```
Failed to pull image "fabricioveronez/kube-news-imersao:v1":
pull access denied, repository does not exist or may require authorization:
server message: insufficient_scope: authorization failed
```

A imagem **não é acessível no Docker Hub**. Os pods que estão rodando hoje só funcionam porque a imagem foi carregada manualmente no nó (`kind load docker-image`) e o `imagePullPolicy` é `IfNotPresent` — ou seja, eles vivem do **cache local do nó**.

Essa é uma dependência invisível. A aplicação deixa de subir se: o kubelet fizer garbage collection de imagens, o pod for agendado num nó sem o cache, o cluster for recriado, ou outra pessoa tentar reproduzir o ambiente. O cluster, hoje, não é reproduzível a partir dos manifestos.

## Orientação para a tarefa

Escolha **um** dos dois caminhos abaixo.

### Caminho A — Publicar num registry público (recomendado)

1. Confirmar que o repositório existe e está público no Docker Hub (ou usar `ghcr.io`, que é gratuito e integra com o GitHub).
2. Fazer build multi-arquitetura — o cluster roda **arm64**, e uma imagem só-amd64 falharia:
   ```
   docker buildx build --platform linux/amd64,linux/arm64 \
     -t <registry>/kube-news-imersao:v1 --push ./src
   ```
3. Validar o pull a partir de uma máquina limpa: `docker pull <registry>/kube-news-imersao:v1`.

### Caminho B — Registry privado com imagePullSecret

1. Criar o secret de acesso:
   ```
   kubectl create secret docker-registry regcred \
     --docker-server=<registry> --docker-username=<user> --docker-password=<token>
   ```
2. Referenciar no pod template do `k8s/app/deployment.yaml`:
   ```yaml
   spec:
     imagePullSecrets:
     - name: regcred
   ```

### Em ambos os casos

3. Manter a tag imutável `v1` — isso já está correto no manifesto e deve continuar. Nunca use `latest`.
4. Considerar fixar a imagem por **digest** (`@sha256:...`) para garantia total de imutabilidade.
5. Validar que o pull funciona de verdade forçando a recriação dos pods com a imagem removida do cache do nó.

## Critério de aceite

- `docker pull` da imagem funciona a partir de uma máquina que nunca a construiu
- Após `kubectl delete pod -l app.kubernetes.io/name=kube-news`, os pods sobem **puxando do registry**, não do cache
- `kubectl describe pod` mostra o evento `Pulled` com a mensagem de download, não `already present on machine`
- Um `kind delete cluster && kind create cluster` seguido de `kubectl apply -f k8s/` reconstrói o ambiente inteiro sem passo manual de `kind load`

## Observações

Este card é o que separa "funciona na minha máquina" de "funciona". Enquanto não estiver resolvido, todo o resto do ambiente é frágil por baixo.
