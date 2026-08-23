---
name: manifestos-kubernetes
description: Cria e revisa manifestos Kubernetes — Pod, ReplicaSet, Deployment e Service — seguindo um padrão fixo: arquivos em `k8s/` na raiz, um por objeto, imagem com tag imutável, labels e selectors coerentes, probes e resources declarados, e validação obrigatória aplicando tudo num cluster kind efêmero e exercitando a aplicação antes de entregar. USE QUANDO o pedido for: criar, corrigir ou revisar um Deployment, Service, Pod ou ReplicaSet; escrever os YAMLs para subir uma aplicação no cluster; expor um serviço para receber tráfego; ajustar réplicas, probes, resources, imagem, porta ou variáveis de ambiente de um workload; ou transformar uma aplicação já containerizada em algo que roda no Kubernetes. Vale mesmo quando a palavra Kubernetes não aparece no pedido, desde que o resultado esperado seja a aplicação rodando no cluster. NÃO USE para escrever chart de Helm ou overlay de Kustomize, para assuntos de cluster operator (RBAC, NetworkPolicy, admission controllers, instalação de cluster), para pipelines de CI/CD, ou para depurar um workload que já está rodando sem alterar manifesto.
---

# Manifestos Kubernetes padronizados

O objetivo desta skill é que qualquer aplicação saia para o cluster no mesmo padrão: arquivos no lugar certo, um objeto por arquivo, imagem previsível, selectors que casam, probes que dizem a verdade sobre o estado do processo e — o ponto que mais falha na prática — **comprovadamente funcionando**, porque os manifestos foram aplicados num cluster de verdade e a aplicação foi exercitada antes de você dizer que está pronto.

Trabalhe nas fases abaixo em ordem. Elas existem porque cada uma depende de informação que a anterior descobriu: você não escolhe entre Pod e Deployment sem saber se a aplicação precisa continuar de pé, e não escreve probe sem saber qual endpoint prova que o processo está vivo.

---

## Fase 1 — Descobrir a aplicação e a imagem antes de escrever qualquer linha

Manifesto escrito por suposição gera um objeto que o cluster aceita sem reclamar e um Pod que não serve tráfego. Leia o projeto e responda a estas perguntas com evidência no código, não com o palpite mais provável:

- **Qual imagem e qual tag.** Ela já existe? Foi construída localmente ou está publicada num registry? Isso decide duas coisas mais adiante: se a validação precisa de `kind load docker-image`, e qual `imagePullPolicy` não vai quebrar. Uma imagem que só existe no Docker local com `imagePullPolicy: Always` resulta em `ImagePullBackOff` garantido.
- **Porta que o processo escuta.** Leia no código. Muitas aplicações fixam a porta em vez de ler de variável de ambiente, e um `containerPort` diferente da porta real produz um Pod `Running`, `1/1 READY` — se não houver probe — e um `curl` que recusa conexão.
- **Variáveis de ambiente de configuração e seus defaults.** Elas vão inline no `env` do container (veja Fase 6) e precisam bater com o que o código assume, senão a aplicação sobe apontando para o lugar errado.
- **Endpoints de saúde, e se são dois endpoints diferentes.** Esta pergunta decide a Fase 4 inteira: com rotas separadas para "o processo está vivo" e "o processo pode receber tráfego", dá para ter liveness e readiness com propósitos distintos. Com uma rota só, você tem uma escolha a fazer e um trade-off a declarar.
- **Dependências externas** — banco, cache, fila. Cada uma vira outro Deployment e outro Service, e o host de cada uma passa a ser o nome do Service, nunca `localhost`.
- **A aplicação faz retry de conexão com a dependência?** Se ela conecta uma vez no boot e morre em caso de falha, o Pod vai entrar em `CrashLoopBackOff` até a dependência ficar pronta. Isso se resolve sozinho e é aceitável — mas você precisa saber que é isso, para não sair "corrigindo" um manifesto que está certo.
- **A aplicação guarda estado em disco local?** Se guarda, o estado morre junto com o Pod. Diga isso ao usuário em vez de escrever um manifesto que finge que o problema não existe.
- **O processo consegue rodar sem privilégio?** Se a imagem já declara um `USER` sem privilégio, o `securityContext` da Fase 4 só formaliza o que já é verdade. Se ela roda como root, `runAsNonRoot: true` impede o container de iniciar — e o erro aparece só no `describe`.

Se algo permanecer ambíguo depois de ler o código — quantas réplicas, qual porta expor no Service —, pergunte em vez de escolher por você.

---

## Fase 2 — Escolher o objeto: Pod, ReplicaSet ou Deployment

Os três descrevem containers rodando, e é comum tratá-los como intercambiáveis. Não são: eles formam uma hierarquia, e cada nível acrescenta uma garantia que o de baixo não tem.

**Um Deployment governa ReplicaSets, e cada ReplicaSet governa Pods.** Quando você troca a imagem de um Deployment, ele cria um ReplicaSet novo, sobe os Pods dele e desliga os do antigo — o antigo continua existindo com zero réplicas, e é isso que torna o rollback possível.

A regra de decisão:

- **Pod avulso** — quando o Pod morre, ninguém o recria. O nó caiu, o Pod acabou. Serve para experimento, depuração e para entender a hierarquia; **nunca** para algo que precisa continuar de pé.
- **ReplicaSet** — mantém a contagem de Pods, mas não sabe fazer rollout. Trocar a imagem nele não substitui nada: os Pods antigos continuam rodando a versão velha, e só somem se você apagá-los na mão. Escrito à mão, quase sempre é o objeto errado.
- **Deployment** — o default para qualquer aplicação de longa duração. Ganha a contagem de réplicas do ReplicaSet e acrescenta rollout, rollback e histórico de revisões.

Na dúvida, é Deployment. As exceções são conscientes e você deve conseguir dizer qual é.

Para o exemplo mínimo de cada objeto, o que cada um não faz e como ler a hierarquia com `kubectl`, leia `references/objetos.md`.

---

## Fase 3 — Manifestos em `k8s/`, um arquivo por objeto

**Os manifestos ficam em `k8s/` na raiz do repositório, um arquivo por objeto, nomeado pelo kind em minúsculas:** `k8s/deployment.yaml`, `k8s/service.yaml`.

Repare que a regra é o oposto da do Dockerfile, que fica junto do código que ele constrói — e a diferença tem motivo. O Dockerfile descreve o build de uma pasta específica; o manifesto descreve o deploy do sistema, incluindo objetos que não pertencem a pasta de código nenhuma. Um Service não é artefato de `src/`.

Um arquivo por objeto, em vez de um YAML só com `---` entre os documentos, porque:

- `kubectl apply -f k8s/` aplica o diretório inteiro de qualquer jeito — não se ganha nada juntando tudo;
- o diff de uma mudança fica isolado no objeto que mudou, em vez de misturar Deployment e Service no mesmo trecho do histórico;
- dá para agir cirurgicamente: `kubectl delete -f k8s/service.yaml` recria só o Service.

Num repositório com vários serviços, cada um tem seu diretório: `k8s/api/`, `k8s/worker/`.

---

## Fase 4 — Anatomia do Deployment

Escreva na ordem abaixo. Cada item existe por causa do que acontece quando ele falta:

1. **`apiVersion: apps/v1`, `kind: Deployment`, `metadata.name`.** O nome é o prefixo de tudo que o objeto gera — ReplicaSets e Pods herdam dele.

2. **Labels em `metadata.labels`**, usando o padrão `app.kubernetes.io/name`, `app.kubernetes.io/component`, `app.kubernetes.io/version`. Elas não afetam o roteamento, mas são o que ferramentas de observabilidade e o próprio `kubectl get -l` usam para achar o objeto depois.

3. **`replicas`.** Duas ou mais para qualquer coisa que precise sobreviver à queda de um nó ou a um drain. Uma réplica é uma decisão legítima em ambiente de estudo — só não confunda com o default seguro.

4. **`selector.matchLabels` com labels estáveis — e nunca `version` entre elas.** Este é o erro que atravessa toda a validação sem sintoma: o primeiro `apply` funciona, os Pods sobem, tudo responde. Ele só aparece no rollout seguinte, quando a versão muda, o selector deixa de casar com os Pods antigos e eles ficam órfãos — rodando, servindo tráfego, e fora do controle do Deployment. O selector é imutável depois de criado, então corrigir exige apagar o Deployment.

5. **`template.metadata.labels` cobrindo o selector.** Pode ter labels a mais — `version` mora aqui —, nunca a menos. Se faltar uma, a API rejeita o objeto na hora, o que é o melhor tipo de erro: barulhento e imediato.

6. **`image` com tag imutável.** Nunca `latest`: ela transforma "qual versão está rodando" numa pergunta sem resposta, e faz um Pod recriado subir com código diferente do vizinho.

7. **`imagePullPolicy`.** `IfNotPresent` quando a imagem foi construída localmente e carregada no cluster — é o que permite ao kubelet usar a que já está no nó em vez de procurar num registry onde ela não existe. `Always` só faz sentido com imagem publicada.

8. **`containerPort` nomeada** (`name: http`). O nome é o que deixa a probe e o Service referenciarem a porta sem repetir o número — e é por isso que trocar a porta depois vira uma edição em vez de três.

9. **`env` com as variáveis descobertas na Fase 1**, inline no container. O host de cada dependência é o nome do Service dela. **Se alguma dessas variáveis for credencial, ela fica em texto claro num arquivo versionado** — diga isso ao usuário e ofereça o Secret; não crie um por conta própria (Fase 6), e não entregue calado.

10. **`resources` com `requests` e `limits`.** Sem `requests`, o scheduler não tem como saber se o Pod cabe no nó, e o Pod vai parar num nó já saturado. Sem `limits.memory`, um vazamento derruba os vizinhos em vez de só o culpado.

11. **Probes.** `readinessProbe` sempre que a aplicação tem qualquer warm-up ou dependência — é ela que impede o Service de mandar tráfego para um Pod que ainda não pode atender. `livenessProbe` num endpoint que verifica **só o processo local**: se ela depender do banco, uma indisponibilidade do banco vira reinício em massa da aplicação, transformando um incidente externo em dois. Detalhes de timing e dos três tipos em `references/probes-e-recursos.md`.

12. **`securityContext`** — `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`. Confirme na Fase 1 que a imagem roda sem privilégio: com `runAsNonRoot: true` numa imagem que roda como root, o container nem inicia.

13. **`strategy: RollingUpdate` com `maxUnavailable: 0`** quando o rollout não pode derrubar tráfego. O custo é uma réplica a mais de capacidade durante a troca. `Recreate` só quando duas versões não podem coexistir.

---

## Fase 5 — Service: como o tráfego chega no Pod

O Service não aponta para o Deployment. Ele procura Pods por label, e **as labels que importam são as do `template` do Pod, não as do `metadata` do Deployment.** Confundir as duas é o erro mais caro desta fase, porque ele não gera erro nenhum.

Um selector que não casa produz um `apply` bem-sucedido, um objeto que existe, um `kubectl get svc` que mostra tudo normal — e nenhum tráfego, para sempre. A única evidência é o `kubectl get endpoints <nome>`, que volta com `<none>`. Por isso ele é passo obrigatório da Fase 7: é a diferença entre um Service certo e um Service que só parece certo.

O resto:

- **`port` é onde o Service escuta; `targetPort` é a porta do container.** Elas podem ser diferentes, e normalmente são: `port: 80`, `targetPort: http`.
- **Use `targetPort` pelo nome** definido no `containerPort`. Assim o Service não precisa saber o número, e mudar a porta da aplicação não exige lembrar de dois lugares.
- **`ClusterIP` é o default e é o certo** para tráfego dentro do cluster.
- **`NodePort` e `LoadBalancer`** só com motivo declarado. `NodePort` serve para acesso em cluster local sem load balancer; `LoadBalancer` provisiona um recurso pago por Service na nuvem.

---

## Fase 6 — Escopo: só manifestos

Gere **apenas** os objetos desta skill: Deployment, Service, Pod e ReplicaSet. Nada de chart de Helm, `kustomization.yaml`, README de deploy, script auxiliar, workflow de CI — e nada de Namespace, ConfigMap, Secret, Ingress, HPA ou PodDisruptionBudget sem que o usuário tenha pedido.

O motivo é direto: arquivo não solicitado entra no repositório, aparece no diff e vira trabalho de revisão que ninguém pediu.

Isso vai ficar desconfortável num caso específico, e ele é previsível: quando houver senha entre as variáveis da Fase 4, item 9. A resposta certa não é criar o Secret nem omitir o problema — é escrever a variável inline, dizer numa linha na resposta que aquela credencial está em texto claro no manifesto, e deixar a decisão com o usuário. O mesmo vale para qualquer outro objeto que você achar que ajudaria: mencione, não crie.

---

## Fase 7 — Validação obrigatória em cluster kind

**Toda criação ou alteração de manifesto termina com os objetos aplicados num cluster real e a aplicação exercitada.** Não espere o usuário pedir, e não declare pronto com base em leitura do arquivo — `kubectl apply` aceitar o YAML prova apenas que ele é um objeto válido, não que ele funciona. Selector que não casa, porta errada, imagem que não existe no nó, probe apontando para rota inexistente: todos passam no `apply`.

O ciclo mínimo:

1. `kind create cluster --name <projeto>-valida` — um cluster descartável, para não tocar em nada que já exista.
2. `kind load docker-image <imagem>` quando a imagem foi construída localmente. Pular este passo é a causa número um de `ImagePullBackOff`.
3. `kubectl apply -f k8s/`.
4. `kubectl rollout status deployment/<nome> --timeout=120s` — esperar de verdade, em vez de checar uma vez e concluir.
5. `kubectl get endpoints <servico>` — **confirmar que não está vazio.** É o único passo que prova que o Service acha os Pods.
6. `kubectl port-forward` e exercitar os endpoints reais: health, readiness, a rota principal e pelo menos uma escrita, se houver.
7. Matar o Pod da aplicação e confirmar que ele volta sozinho e que o dado escrito continua lá.
8. `kind delete cluster --name <projeto>-valida` — **também quando algo dá errado.** Cluster órfão consome memória e faz o próximo ciclo herdar estado sujo. Devolva também o contexto do `kubectl` que o `kind create` trocou no passo 1: apagar o cluster deixa o `current-context` vazio, e quem paga por isso é o próximo comando que o usuário rodar.
9. Reportar as evidências: o que foi executado e o que retornou.

Se algo falhar, leia `kubectl describe pod <pod>` e `kubectl logs <pod>` antes de mexer nos arquivos. Alterar o manifesto no chute costuma trocar um erro por outro.

O checklist com os comandos concretos, a tabela de diagnóstico e o formato do relatório está em `references/validacao.md`.

---

## Anti-padrões

Estes são os erros que aparecem com mais frequência e o que cada um custa:

- **`image: app:latest`** — impossível saber qual versão está rodando, e dois Pods do mesmo Deployment podem estar em código diferente.
- **`version` dentro de `selector.matchLabels`** — o primeiro apply funciona e o rollout seguinte deixa Pods órfãos servindo tráfego. Como o selector é imutável, a correção exige recriar o Deployment.
- **Selector do Service casando com as labels do Deployment em vez das do template** — nenhum erro, nenhum tráfego, e `endpoints` vazio como única pista.
- **Pod avulso para algo que precisa continuar de pé** — o Pod morre e ninguém o recria.
- **ReplicaSet escrito à mão para uma aplicação** — trocar a imagem não substitui Pod nenhum.
- **Sem `resources.requests`** — o scheduler coloca o Pod num nó saturado porque não tinha como saber que ele não cabia.
- **Liveness e readiness no mesmo endpoint que consulta o banco** — o banco cai e a aplicação inteira entra em reinício, transformando um incidente em dois.
- **Sem `readinessProbe` numa aplicação com warm-up** — o Service manda tráfego para um Pod que ainda não pode atender, e o usuário vê erro durante todo rollout.
- **`imagePullPolicy: Always` com imagem que só existe local** — `ImagePullBackOff` num cluster que tinha a imagem no nó o tempo todo.
- **`replicas: 1` para algo que precisa sobreviver a drain** — a manutenção de um nó derruba o serviço.
- **`runAsNonRoot: true` numa imagem que roda como root** — o container não inicia, e o erro só aparece no `describe`.
- **Declarar sucesso sem ter aplicado num cluster** — o mais caro de todos, porque transfere para o usuário a descoberta de que não funciona.

---

## Quando aprofundar

| Situação | Leia |
|---|---|
| Escolher entre Pod, ReplicaSet, Deployment e Service; ver o exemplo mínimo de cada; entender a hierarquia na prática; declarar um banco como dependência | `references/objetos.md` |
| Configurar liveness, readiness ou startup; calcular timing de probe; definir requests, limits e classe de QoS; ajustar securityContext ou estratégia de rollout | `references/probes-e-recursos.md` |
| Executar a validação da Fase 7, diagnosticar um Pod que não sobe ou um Service sem endpoints, montar o relatório de evidências | `references/validacao.md` |
