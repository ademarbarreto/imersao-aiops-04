# Probes, recursos e o resto do container

Leia este arquivo ao executar os itens 10 a 13 da Fase 4 — probes, resources, securityContext e estratégia de rollout — e sempre que um Pod estiver reiniciando, ficando `Pending` ou nunca chegando a `READY`.

## Índice

- [As três probes](#as-três-probes)
- [Por que liveness e readiness não compartilham endpoint](#por-que-liveness-e-readiness-não-compartilham-endpoint)
- [Timing: quanto tempo até o cluster desistir](#timing-quanto-tempo-até-o-cluster-desistir)
- [Quando a startupProbe é a resposta](#quando-a-startupprobe-é-a-resposta)
- [Requests e limits](#requests-e-limits)
- [Classes de QoS](#classes-de-qos)
- [securityContext](#securitycontext)
- [Estratégia de rollout](#estratégia-de-rollout)

---

## As três probes

Elas parecem variações do mesmo check, e não são. Cada uma responde a uma pergunta diferente, e o cluster faz coisas diferentes com a resposta.

**`livenessProbe` — "este processo ainda está são?"** Falhou o suficiente, o kubelet **mata o container** e o reinicia. É a única das três que destrói alguma coisa, e por isso é a mais perigosa de configurar mal: uma liveness apertada demais transforma lentidão temporária em reinício, e reinício em mais lentidão.

**`readinessProbe` — "este Pod pode receber tráfego agora?"** Falhou, o Pod sai dos endpoints do Service. Nada é morto; ele simplesmente para de receber requisições até voltar a passar. É a probe mais segura e a que mais gente esquece — sem ela, o Service manda tráfego para um Pod que ainda está subindo, e o usuário vê erro durante todo rollout.

**`startupProbe` — "já terminou de subir?"** Enquanto ela não passa, liveness e readiness ficam suspensas. Serve para aplicação com boot longo, e existe justamente para você poder ter uma liveness rápida depois sem que ela mate o container durante a inicialização.

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: http
  periodSeconds: 10
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /ready
    port: http
  periodSeconds: 5
  failureThreshold: 2
```

Note o `port: http` — o nome definido no `containerPort`, não o número. Trocar a porta da aplicação passa a ser uma edição em um lugar só.

---

## Por que liveness e readiness não compartilham endpoint

Este é o erro com a pior relação entre facilidade de cometer e tamanho do estrago.

Suponha um endpoint `/health` que testa a conexão com o banco — parece a coisa mais responsável a fazer — e suponha que ele seja usado nas duas probes. O banco fica indisponível por dois minutos. O que acontece:

1. A readiness falha. Todos os Pods saem dos endpoints. Correto: eles realmente não podem atender.
2. A liveness falha também, nos mesmos Pods, ao mesmo tempo. O kubelet mata todos.
3. Os Pods novos sobem, encontram o mesmo banco indisponível, e são mortos de novo.
4. O banco volta — e agora a aplicação está no meio de um ciclo de reinícios, com cache frio e conexões sendo refeitas.

Uma indisponibilidade de dois minutos no banco virou uma indisponibilidade mais longa na aplicação, causada inteiramente pela configuração das probes.

A separação certa:

- **Liveness verifica só o processo local.** "O event loop responde", "o servidor HTTP aceita conexão". Nada de rede externa. Se este check falha, reiniciar realmente é a ação certa — o processo travou.
- **Readiness pode verificar dependências.** Falhar readiness durante um incidente é o comportamento desejado: o Pod se remove do balanceamento e volta sozinho quando a dependência voltar, sem perder o processo.

Quando a aplicação só tem um endpoint de saúde, a escolha é usar esse endpoint na readiness e deixar a liveness de fora — ou dar a ela um check trivialmente local. Um Pod sem liveness que trava é um problema; um Pod com liveness errada é um incidente amplificado. Se você fizer essa escolha, diga ao usuário qual foi e por quê.

---

## Timing: quanto tempo até o cluster desistir

A conta que importa é `periodSeconds × failureThreshold` — o tempo entre o problema começar e a ação acontecer.

```
periodSeconds: 10, failureThreshold: 3  →  até 30s travado antes do restart
periodSeconds: 5,  failureThreshold: 2  →  até 10s fora do balanceamento
```

Os dois lados têm custo. Muito curto, e um GC longo ou um pico de latência viram restart. Muito longo, e o Pod fica servindo erro por meio minuto antes de alguém notar.

Ponto de partida razoável: liveness tolerante (`10s × 3`), readiness ágil (`5s × 2`). A readiness pode ser agressiva porque errar nela é barato — o Pod só sai do balanceamento e volta.

`timeoutSeconds` (default `1s`) merece atenção quando o endpoint de saúde faz qualquer trabalho real: uma probe que demora mais que o timeout conta como falha, e o sintoma é indistinguível de aplicação quebrada.

---

## Quando a startupProbe é a resposta

Existe uma saída errada comum para "a aplicação demora a subir": aumentar o `initialDelaySeconds` da liveness. Ela funciona, e cobra o preço para sempre — aquele atraso passa a valer em todo restart, inclusive nos que não têm nada a ver com boot.

A startupProbe resolve melhor porque só vale uma vez:

```yaml
startupProbe:
  httpGet:
    path: /health
    port: http
  periodSeconds: 5
  failureThreshold: 30   # até 150s para subir
```

Enquanto ela não passa, liveness e readiness ficam suspensas — e depois que passa, a liveness pode ser tão rápida quanto você quiser. Vale a partir de mais ou menos 30 segundos de boot.

---

## Requests e limits

São dois mecanismos diferentes com nomes parecidos:

**`requests` é para o scheduler.** É a informação que ele usa para decidir em qual nó o Pod cabe. Não limita nada em runtime — o container pode usar mais. Sem `requests`, o scheduler assume que o Pod não precisa de nada e pode colocá-lo num nó já saturado, o que produz um Pod lento sem causa aparente.

**`limits` é para o runtime.** É um teto real:

- `limits.memory` estourado → o kernel mata o processo. `OOMKilled` no `describe`, e o container reinicia.
- `limits.cpu` estourado → o processo é **throttled**, não morto. Ele continua rodando, só mais devagar, e o sintoma é latência que ninguém consegue explicar olhando para a aplicação.

```yaml
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    memory: "256Mi"
```

Sobre `limits.cpu` não há consenso, e vale saber por quê antes de copiar a decisão de alguém: ele protege os vizinhos de um processo que consome CPU demais, mas throttling em aplicação sensível a latência produz cauda alta de p99 sem nenhuma métrica de erro subindo junto. `limits.memory`, ao contrário, é consenso — sem ele, um vazamento derruba o nó inteiro em vez de só o culpado.

Comece conservador e ajuste com métrica real. Número inventado no primeiro manifesto é normal; número inventado que nunca foi revisitado é dívida.

---

## Classes de QoS

O Kubernetes classifica cada Pod a partir de requests e limits, e a classe decide quem morre primeiro quando o nó fica sem memória:

| Classe | Como se obtém | O que acontece sob pressão |
|---|---|---|
| `Guaranteed` | requests iguais a limits, em todos os containers | Último a ser despejado |
| `Burstable` | requests definidos, limits diferentes ou ausentes | Despejado depois dos BestEffort |
| `BestEffort` | nenhum request nem limit | **Primeiro a morrer** |

Você não escolhe a classe diretamente — ela é consequência do que escreveu. Um Pod sem `resources` é `BestEffort`, e será a primeira vítima de qualquer aperto de memória no nó. Confira com:

```bash
kubectl get pod <nome> -o jsonpath='{.status.qosClass}'
```

---

## securityContext

```yaml
securityContext:
  runAsNonRoot: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
  readOnlyRootFilesystem: true
```

O que cada um fecha:

- **`runAsNonRoot: true`** — o kubelet recusa iniciar o container se a imagem rodar como root. É verificação, não conversão: se a imagem não declara um usuário sem privilégio, o Pod não sobe, e a mensagem aparece só no `kubectl describe`. Foi por isso que a Fase 1 mandou confirmar isso antes.
- **`runAsUser: <uid>`** — força o UID. Necessário quando `runAsNonRoot` não consegue provar que a imagem não é root, porque o `USER` dela é um nome e não um número.
- **`allowPrivilegeEscalation: false`** — impede que um processo dentro do container ganhe mais privilégio do que o pai tinha.
- **`capabilities.drop: ["ALL"]`** — remove as capabilities do Linux que vêm por default e quase nenhuma aplicação usa.
- **`readOnlyRootFilesystem: true`** — vale quando a aplicação não escreve em disco. Se ela escreve em `/tmp`, monte um `emptyDir` ali em vez de abrir o filesystem inteiro.

---

## Estratégia de rollout

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1
    maxUnavailable: 0
```

`maxSurge` é quantos Pods a mais podem existir durante a troca; `maxUnavailable`, quantos a menos.

Com `maxUnavailable: 0`, o Deployment sobe o Pod novo, **espera ele ficar ready** e só então derruba um antigo — a capacidade nunca cai abaixo de `replicas`. O custo é uma réplica extra de recurso durante o rollout e um rollout um pouco mais lento.

O detalhe que faz isso funcionar: "ficar ready" é a readinessProbe. **Sem readiness, `maxUnavailable: 0` não garante nada** — o Pod é considerado pronto assim que o container inicia, que é bem antes de a aplicação conseguir atender. As duas configurações são um par, não duas decisões independentes.

`Recreate` derruba tudo antes de subir o novo. Aceita downtime em troca de garantir que duas versões nunca coexistam — o que importa em migração destrutiva de schema ou processo que exige ser único.
