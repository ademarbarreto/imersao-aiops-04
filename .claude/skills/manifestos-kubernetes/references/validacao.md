# Validação dos manifestos em cluster kind

Leia este arquivo ao executar a Fase 7 — depois de criar ou alterar qualquer manifesto — e sempre que um Pod não subir e for preciso diagnosticar.

## Índice

- [Por que validar sempre](#por-que-validar-sempre)
- [Checklist de execução](#checklist-de-execução)
- [Quando algo falha](#quando-algo-falha)
- [Relatório de evidências](#relatório-de-evidências)

---

## Por que validar sempre

`kubectl apply` aceitar o arquivo prova uma coisa só: que ele é um objeto Kubernetes bem formado. Não prova que funciona, e a distância entre as duas coisas é onde moram os erros mais comuns.

Selector do Service que não casa com as labels do template, `containerPort` diferente da porta real do processo, imagem que não existe no nó, probe apontando para uma rota que a aplicação não tem, variável de ambiente com o nome errado — **todos passam no apply sem uma linha de aviso.** Vários deles produzem até um Pod `Running`. A única forma de distinguir um manifesto certo de um que só parece certo é aplicar e exercitar.

O cluster kind é descartável de propósito: ele não toca em nada que já exista, sobe em menos de um minuto e some no fim.

---

## Checklist de execução

**1. Criar o cluster**

```bash
kind create cluster --name kube-news-valida
```

O kind usa o Docker. Se o daemon não estiver rodando, o comando falha aí — avise o usuário e não conclua a tarefa como validada.

Ele também troca o contexto atual do `kubectl` para o cluster novo. Guarde qual era o contexto anterior antes de seguir:

```bash
kubectl config current-context
```

Isso é necessário porque o `kind delete cluster` do passo 8 **não devolve o contexto anterior** — ele remove a entrada do cluster apagado e deixa o `current-context` vazio. Quem tinha um contexto ativo apontando para outro cluster fica sem nenhum, e o próximo `kubectl` do usuário falha com `current-context is not set`. Restaurar é responsabilidade sua, não do kind.

**2. Carregar a imagem no cluster**

```bash
kind load docker-image kube-news:1.0.0 --name kube-news-valida
```

Obrigatório quando a imagem foi construída localmente e não está publicada em registry nenhum. O nó do kind é um Docker separado do seu — a imagem que existe na sua máquina não existe dentro dele. Pular este passo é a causa número um de `ImagePullBackOff`, e o erro engana: ele parece problema de rede ou de credencial, quando é só a imagem nunca ter chegado ali.

Confirme que chegou:

```bash
docker exec kube-news-valida-control-plane crictl images | grep kube-news
```

**3. Aplicar os manifestos**

```bash
kubectl apply -f k8s/
```

**4. Esperar o rollout de verdade**

```bash
kubectl rollout status deployment/kube-news --timeout=120s
```

Este comando bloqueia até todos os Pods estarem prontos, ou até o timeout. Ele é a diferença entre esperar e checar uma vez: um `kubectl get pods` logo depois do apply mostra `ContainerCreating`, que não é sucesso nem fracasso.

Se houver dependência (banco), aplique e espere ela primeiro — a aplicação vai reiniciar algumas vezes enquanto o banco sobe, e isso é esperado.

**5. Confirmar que o Service acha os Pods**

```bash
kubectl get endpoints kube-news
```

**Este passo não é opcional.** É o único que prova que o selector do Service casa com as labels do template — e é o erro que não gera nenhum sintoma em lugar nenhum. A saída precisa listar IPs:

```
NAME        ENDPOINTS                         AGE
kube-news   10.244.0.8:8080,10.244.0.9:8080   30s
```

Se aparecer `<none>`, o Service não achou Pod nenhum. Compare `spec.selector` do Service com `spec.template.metadata.labels` do Deployment — não com as labels do `metadata` do Deployment, que é a confusão de sempre.

**6. Exercitar os endpoints reais**

```bash
kubectl port-forward svc/kube-news 8080:80 &
sleep 2
curl -s http://localhost:8080/health
curl -s http://localhost:8080/ready
curl -s http://localhost:8080/ | head -20
```

Health prova que o processo subiu; readiness prova que a probe aponta para algo real; a rota principal prova que a aplicação serve conteúdo. Se o projeto serve arquivos estáticos, confirme que uma URL de asset responde.

Se houver operação de escrita, execute uma — é o que prova que a conexão com a dependência funciona de ponta a ponta, e não só que o Pod do banco subiu:

```bash
curl -s -X POST http://localhost:8080/api/recurso \
  -H "Content-Type: application/json" \
  -d '{"campo":"valor"}'
```

Depois confirme que o dado aparece na leitura.

**7. Provar que o Pod é recriado e o dado sobrevive**

```bash
kubectl delete pod -l app.kubernetes.io/name=kube-news
kubectl rollout status deployment/kube-news --timeout=120s
```

Confirme que os Pods voltaram com nomes novos e que o dado escrito no passo 6 continua lá. Isso prova duas coisas: que o ReplicaSet faz o seu trabalho, e que o estado vive na dependência, não na memória do Pod da aplicação.

**O que este passo não prova:** que o dado sobrevive à morte do Pod **do banco**. Sem PersistentVolumeClaim — fora do escopo desta skill —, ele não sobrevive. Diga isso no relatório em vez de deixar a prova parecer mais forte do que é.

**8. Destruir o cluster**

```bash
kind delete cluster --name kube-news-valida
```

Rode isto **inclusive quando algo falhou**. Um cluster kind órfão continua consumindo memória depois que você esqueceu dele, e o ciclo seguinte herda o estado sujo do anterior — objetos velhos aplicados, imagem antiga carregada — o que produz resultados que não têm nada a ver com o manifesto atual.

E devolva o contexto que você anotou no passo 1:

```bash
kubectl config use-context <contexto-anterior>
```

Sem isso você deixa o `kubectl` do usuário sem contexto nenhum — uma quebra que ele vai descobrir depois, longe daqui, sem ligar com a validação que você rodou.

---

## Quando algo falha

Leia o estado antes de alterar qualquer arquivo. Mudar o manifesto no chute normalmente troca um erro por outro e alonga o ciclo.

```bash
kubectl describe pod <pod>     # eventos: pull, scheduling, probes
kubectl logs <pod>             # o que a aplicação disse
kubectl logs <pod> --previous  # o que ela disse antes do último restart
```

Em `CrashLoopBackOff`, `--previous` costuma ser a única fonte útil: o container atual acabou de nascer e ainda não falhou.

| Sintoma | Causa provável | Como confirmar |
|---|---|---|
| `ImagePullBackOff` / `ErrImagePull` | Faltou `kind load`, ou `imagePullPolicy: Always` com imagem só local | `describe` mostra o evento `Failed to pull image` |
| `CrashLoopBackOff` logo no início | App conectou na dependência antes de ela aceitar conexões — normal nos primeiros ciclos | `logs --previous` mostra erro de conexão; espere e reobserve |
| `CrashLoopBackOff` persistente | Liveness apertada demais, ou erro real de configuração | `describe` mostra `Liveness probe failed`; sem isso, é a aplicação |
| `endpoints` vazio (`<none>`) | Selector do Service não casa com as labels do template | Compare `spec.selector` do Service com `spec.template.metadata.labels` |
| Pod `Running` mas `0/1 READY` | Readiness falhando — rota errada, porta errada ou app ainda subindo | `describe` mostra `Readiness probe failed` com o código HTTP |
| Pod `Pending` | `requests` maiores que a capacidade do nó | `describe` mostra `Insufficient cpu` ou `Insufficient memory` |
| `CreateContainerConfigError` | `runAsNonRoot: true` numa imagem que roda como root | `describe` mostra `container has runAsNonRoot and image will run as root` |
| `port-forward` conecta mas `curl` recusa | `containerPort`/`targetPort` diferente da porta real do processo | `kubectl exec <pod> -- <cliente http> localhost:<porta>` |
| Rollout travado em `Waiting for deployment...` | Os Pods novos nunca ficam ready | `kubectl get pods` mostra o Pod novo em `0/1`; siga para readiness |
| `OOMKilled` no `describe` | `limits.memory` abaixo do que a aplicação usa | `kubectl top pod` durante a carga, se houver metrics-server |

Depois de corrigir, **repita o checklist do início** — uma correção pode desfazer algo que já passava.

---

## Relatório de evidências

Ao concluir, relate o que foi executado e o que retornou. Sem isso o usuário não tem como distinguir "validei" de "presumo que funcione".

Formato:

```
Validação executada em cluster kind (kube-news-valida, destruído ao final):

- Imagem: `kind load docker-image kube-news:1.0.0` — carregada no nó
- Apply: `kubectl apply -f k8s/` — deployment.yaml, service.yaml
- Rollout: `rollout status deployment/kube-news` — 2/2 réplicas prontas em 18s
- Endpoints: `get endpoints kube-news` → 10.244.0.8:8080, 10.244.0.9:8080 (Service acha os Pods)
- GET /health → {"state":"up",...}
- GET /ready → Ok
- GET / → página renderizada, CSS respondendo
- POST /api/post → recurso criado, confirmado na listagem
- Resiliência: `delete pod -l ...` → Pods recriados pelo ReplicaSet, dado preservado

Não coberto: persistência do banco. Sem PVC, o dado não sobrevive à morte do Pod
do Postgres — só à da aplicação, que foi o que este ciclo testou.
```

Se algum passo não pôde ser executado — Docker parado, aplicação sem rota de health, ausência de operação de escrita —, diga qual e por quê, em vez de omitir. Uma validação parcial declarada é informação útil; uma validação parcial apresentada como completa não é.
