# Os quatro objetos

Leia este arquivo ao executar a Fase 2 — quando precisar decidir qual objeto escrever — e sempre que quiser o exemplo mínimo de um deles ou entender por que o cluster criou algo que você não escreveu.

## Índice

- [Pod](#pod)
- [ReplicaSet](#replicaset)
- [Deployment](#deployment)
- [Service](#service)
- [A hierarquia na prática](#a-hierarquia-na-prática)
- [Declarar uma dependência](#declarar-uma-dependência)

---

## Pod

**Quando usar:** experimento, depuração, um container de utilidade que você vai apagar em seguida. Nunca para uma aplicação que precisa continuar de pé.

**Exemplo mínimo:**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: kube-news-debug
  labels:
    app.kubernetes.io/name: kube-news
spec:
  containers:
    - name: app
      image: kube-news:1.0.0
      ports:
        - name: http
          containerPort: 8080
```

**O que ele não faz:** não se recria. Se o nó cair, se o processo terminar com `restartPolicy: Never`, se alguém rodar `kubectl delete pod`, o Pod acabou — e nada no cluster tem a obrigação de trazê-lo de volta. `restartPolicy: Always` reinicia o *container* dentro do Pod, o que é outra coisa: o Pod continua preso ao nó onde nasceu.

**Armadilha comum:** confundir "o container reiniciou" com "o Pod é resiliente". Um Pod avulso que reinicia o container mil vezes ainda morre junto com o nó.

---

## ReplicaSet

**Quando usar:** quase nunca, escrito à mão. Ele existe para você **entender** o que o Deployment faz por baixo, e para ler o cluster com informação — não como objeto de trabalho.

**Exemplo mínimo:**

```yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: kube-news
spec:
  replicas: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: kube-news
  template:
    metadata:
      labels:
        app.kubernetes.io/name: kube-news
    spec:
      containers:
        - name: app
          image: kube-news:1.0.0
          ports:
            - name: http
              containerPort: 8080
```

**O que ele não faz:** rollout. Ele garante que existam N Pods casando com o selector, e só. Trocar a `image` no manifesto e reaplicar **não substitui nada** — os Pods antigos continuam rodando a versão velha, porque continuam casando com o selector e a contagem continua batendo. A nova imagem só aparece nos Pods que nascerem depois, o que significa apagar os antigos na mão.

**Armadilha comum:** exatamente a acima — reaplicar com imagem nova, ver `kubectl get rs` reportar `2/2 READY` e concluir que o deploy funcionou.

---

## Deployment

**Quando usar:** qualquer aplicação de longa duração. É o default, e as exceções precisam de justificativa.

**Exemplo mínimo** (a Fase 4 do `SKILL.md` acrescenta probes, resources e securityContext):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kube-news
  labels:
    app.kubernetes.io/name: kube-news
    app.kubernetes.io/component: web
spec:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app.kubernetes.io/name: kube-news
      app.kubernetes.io/component: web
  template:
    metadata:
      labels:
        app.kubernetes.io/name: kube-news
        app.kubernetes.io/component: web
        app.kubernetes.io/version: "1.0.0"
    spec:
      containers:
        - name: app
          image: kube-news:1.0.0
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 8080
```

Repare que `version` aparece só no `template`, nunca no `selector` — é a regra dura da Fase 4, item 4.

**O que ele não faz:** não guarda estado, não garante identidade estável de rede por Pod e não ordena a subida das réplicas. Banco de dados de produção quer StatefulSet, que está fora do escopo desta skill — quando o caso aparecer, diga ao usuário em vez de entregar um Deployment fingindo que serve.

**Armadilha comum:** mexer no `selector` de um Deployment que já existe. O campo é imutável; a API rejeita a alteração e a única saída é apagar e recriar o objeto — com a interrupção que isso implica.

---

## Service

**Quando usar:** sempre que algo precisa alcançar os Pods por um endereço estável. IP de Pod muda a cada recriação; o Service é o nome que não muda.

**Exemplo mínimo:**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: kube-news
  labels:
    app.kubernetes.io/name: kube-news
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: kube-news
    app.kubernetes.io/component: web
  ports:
    - name: http
      port: 80
      targetPort: http
```

O `selector` aqui casa com as labels do **template do Pod** do Deployment acima — não com as do `metadata` dele. E note que `selector` no Service é um mapa direto, sem `matchLabels`: a sintaxe é diferente da do Deployment, e trocar uma pela outra é rejeitado pela API.

**O que ele não faz:** não termina TLS, não roteia por caminho de URL e não sabe nada de HTTP — ele trabalha em nível de conexão. Roteamento por host e path é Ingress, fora do escopo desta skill.

**Armadilha comum:** o selector que não casa, descrito na Fase 5. Confirme sempre com:

```bash
kubectl get endpoints kube-news
```

Se a coluna `ENDPOINTS` mostra `<none>`, nenhum Pod foi encontrado — e nada mais no cluster vai avisar você disso.

---

## A hierarquia na prática

Aplique o Deployment e olhe o que apareceu junto:

```bash
kubectl get deploy,rs,pod -l app.kubernetes.io/name=kube-news
```

Você escreveu um objeto e existem três. O ReplicaSet tem o nome do Deployment mais um hash (`kube-news-7d9f8b6c5`), e os Pods têm o nome do ReplicaSet mais um sufixo aleatório. Esse hash vem do conteúdo do `template`: qualquer mudança nele — imagem, variável de ambiente, probe — produz um hash diferente e, portanto, um ReplicaSet novo.

É isso que o rollout é. Trocando a imagem e rodando `kubectl get rs` de novo:

```
NAME                   DESIRED   CURRENT   READY
kube-news-7d9f8b6c5    0         0         0
kube-news-5c4a9d2f1    2         2         2
```

O ReplicaSet antigo continua ali, zerado. Ele é o histórico — `kubectl rollout undo deployment/kube-news` apenas o reativa e zera o novo. Um ReplicaSet antigo que **não** zerou depois de um rollout concluído é sinal de Pods órfãos, quase sempre por causa de `version` no selector.

---

## Declarar uma dependência

Um banco, cache ou fila dentro do escopo desta skill vira o mesmo par: um Deployment e um Service.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: postgres
  ports:
    - name: postgres
      port: 5432
      targetPort: postgres
```

O que a aplicação usa como host é o **nome do Service** — `DB_HOST: postgres` —, nunca `localhost`. Dentro do Pod, `localhost` é o próprio container.

Duas coisas para dizer ao usuário quando isso acontecer, em vez de deixar implícitas:

**O dado não sobrevive ao Pod.** Sem PersistentVolumeClaim — fora do escopo desta skill —, o banco escreve no sistema de arquivos efêmero do container. O Pod é recriado, o banco volta vazio. Isso é aceitável para desenvolvimento e estudo, e é uma perda de dados em qualquer outro contexto.

**A aplicação vai reiniciar algumas vezes no primeiro deploy.** Não existe `depends_on` no Kubernetes: todos os Pods sobem em paralelo, e uma aplicação que conecta no banco durante o boot vai falhar enquanto o Postgres ainda inicia. O `restartPolicy` resolve sozinho em alguns ciclos. Ver `CrashLoopBackOff` nesse intervalo é esperado — o erro seria "consertar" um manifesto que está correto.
