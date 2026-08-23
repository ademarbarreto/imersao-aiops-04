# Lint estático do Dockerfile com hadolint

Leia este arquivo ao executar a Fase 7 — sempre que o lint apontar algo que você não sabe se corrige, se aceita ou se suprime — e quando quiser ajustar o próprio gate.

## Índice

- [Por que lintar antes de subir a stack](#por-que-lintar-antes-de-subir-a-stack)
- [Como rodar](#como-rodar)
- [Catálogo de regras](#catálogo-de-regras)
- [Achados aceitáveis e por quê](#achados-aceitáveis-e-por-quê)
- [`SKILL001` — a lacuna que o hadolint deixa](#skill001--a-lacuna-que-o-hadolint-deixa)
- [Quando usar pragma de ignore](#quando-usar-pragma-de-ignore)
- [Ajustar o gate](#ajustar-o-gate)

---

## Por que lintar antes de subir a stack

A skill enuncia em prosa um conjunto de regras duras — tag fixa, exec form, usuário não-root, `WORKDIR` absoluto, `COPY` em vez de `ADD`. Até aqui, a única verificação dessas regras era você reler o arquivo que acabou de escrever, que é a forma menos confiável de checagem que existe: o mesmo raciocínio que produziu o erro é o que vai procurá-lo.

O lint custa milissegundos e é determinístico. E ele pega uma classe de problema que a validação em runtime **não pega**: um container rodando como root sobe normalmente, responde ao health e passa em todos os `curl` do checklist da Fase 8. Uma imagem em `latest` também. Esses erros não têm sintoma — só consequência, mais tarde.

Por isso a ordem é lint primeiro, `docker compose up` depois. O erro estático é descoberto sem gastar um ciclo de build.

---

## Como rodar

```bash
.claude/skills/containerizacao-docker/scripts/lint-dockerfile.sh src/Dockerfile
```

Sem argumentos, o script descobre os Dockerfiles do projeto a partir do diretório atual (ignorando `.git`, `node_modules`, `vendor`, `.venv`, `target`). Com argumentos, lint só nos caminhos indicados — use isso quando o repositório tem vários serviços e você mexeu em um.

A configuração vem de `assets/hadolint.yaml`, dentro da skill. Se o projeto já tiver um `.hadolint.yaml` na raiz, ele tem precedência: a config do repositório é a fonte de verdade, e a da skill é só o default para quem não tem uma.

O script termina com uma linha-resumo estável, feita para ser citada no relatório de evidências:

```
LINT: OK — 0 error, 0 warning, 0 política (1 info, 0 style) em 1 arquivo
LINT: BLOQUEADO — 1 error, 0 warning, 0 política (1 info, 0 style) em 1 arquivo
LINT: BLOQUEADO — 0 error, 0 warning, 1 política (0 info, 0 style) em 1 arquivo
LINT: PULADO — hadolint não encontrado (instale com: brew install hadolint)
```

O contador `política` são os achados da checagem própria da skill (hoje só o `SKILL001`), que o hadolint não faz. Eles bloqueiam como `error`.

Os três códigos de saída significam coisas diferentes e não devem ser confundidos:

| Código | Significado | O que fazer |
|---|---|---|
| `0` | Liberado. Pode haver achados `info`/`style`. | Leia os achados restantes, decida sobre cada um e siga para a Fase 8. |
| `1` | Bloqueado. Há `error`, `warning` ou `política` — ou um caminho passado não existe. | Corrija antes de seguir. Não suba a stack para "ver se funciona mesmo assim". |
| `2` | O hadolint não está instalado, ou não há Dockerfile a lintar. | Não é reprovação. Registre no relatório que o lint não rodou e siga para a Fase 8. |

Confundir `1` com `2` transforma "não consegui checar" em "está reprovado", que é uma mentira em direção oposta à do relatório otimista — mas ainda é uma mentira.

Um caminho inexistente fica em `1`, e não em `2`, por uma diferença que importa: hadolint ausente é uma limitação do ambiente, path errado é um erro seu que custa segundos para corrigir. Se ele saísse como "pulado", um typo no comando viraria um Dockerfile entregue sem nunca ter passado pelo gate — com o relatório dizendo, de boa-fé, que o lint não pôde rodar.

---

## Catálogo de regras

Nível "na skill" é o que a config de `assets/hadolint.yaml` aplica, que nem sempre é o default do hadolint.

| Código | Nível na skill | Fase que protege | Como corrigir |
|---|---|---|---|
| `DL3000` | error | Fase 2, item 2 | `WORKDIR` com caminho absoluto (`/app`), nunca relativo. |
| `DL3002` | error | Fase 2, item 6 | O último `USER` da imagem não pode ser root. Use o usuário embutido (`USER node`) ou crie um. Cobre só o root **explícito** — a omissão é do `SKILL001`. |
| `DL3006` | error | Fase 3 | `FROM` sem tag. Fixe a versão maior do runtime (`node:20-bookworm-slim`). |
| `DL3007` | error | Fase 3 | `FROM ... :latest`. Mesma correção — tag explícita. |
| `DL3025` | error | Fase 2, itens 8 e 9 | `CMD`, `ENTRYPOINT` ou `HEALTHCHECK` em shell form. Passe para exec form (array JSON). |
| `DL3020` | error (default) | Fase 2, item 5 | `ADD` para arquivo local. Use `COPY` — `ADD` também baixa URL e descompacta tar, comportamento que ninguém quer por acidente. |
| `DL3003` | warning (default) | Fase 2, item 2 | `cd` dentro de `RUN`. Use `WORKDIR`, que persiste entre instruções. |
| `DL3013` | warning (default) | Fase 2, item 4 | `pip install <pacote>` sem versão. Instale a partir do manifesto (`-r requirements.txt`), como a Fase 2 já manda. |
| `DL3042` | warning (default) | Fase 2, item 4 | `pip install` sem `--no-cache-dir` — o cache fica gravado na camada e infla a imagem sem serventia. |
| `DL3027` | warning (default) | — | `apt` no lugar de `apt-get`. `apt` não tem interface estável para script. |
| `DL4006` | warning (default) | — | Pipe dentro de `RUN` sem `SHELL ["/bin/bash","-o","pipefail","-c"]` — a falha no meio do pipe passa despercebida. |
| `DL3009` | info (default) | — | `apt-get install` sem limpar `/var/lib/apt/lists`. Vale corrigir; a skill não exige. |
| `DL3015` | info (default) | — | `apt-get install` sem `--no-install-recommends`. Idem. |
| `DL3008` | **rebaixada para info** | — | Pin de versão em `apt-get install`. Ver abaixo. |
| `DL3018` | **rebaixada para info** | — | Pin de versão em `apk add`. Idem. |
| `DL3066` | info (default) | conflita de leve com Fase 2, item 6 | UID não-numérico em `USER`. Ver abaixo. |
| `SKILL001` | política (bloqueia) | Fase 2, item 6 | **Não é do hadolint** — é checagem do próprio script. O estágio final não declara `USER` nenhum. Declare um usuário sem privilégio nele. Ver abaixo. |

`DL3008` e `DL3018` são `warning` no hadolint e, sob a política desta skill, bloqueariam praticamente todo Dockerfile que instala qualquer coisa via `apt`/`apk`. A skill nunca pediu pin de versão de pacote de sistema — e em Debian a versão exata muda a cada ponto de release, o que faz o pin quebrar builds sozinho. Por isso descem para `info`: continuam visíveis, param de reprovar.

---

## Achados aceitáveis e por quê

**`DL3066` — "Non-numeric user-id may not be resolvable by host system".**

Este vai aparecer em quase todo Dockerfile que segue a skill, porque a Fase 2 item 6 recomenda usar o usuário embutido da imagem (`USER node`, `USER nobody`) em vez de inventar um. O hadolint prefere `USER 1000` porque o nome só existe dentro do `/etc/passwd` da imagem: quem lê o `USER` de fora — o runtime do host, uma política de segurança — não sabe resolvê-lo.

Na maior parte dos casos isso é irrelevante e a legibilidade de `USER node` vence. Vale trocar por UID numérico quando:

- a imagem vai rodar em Kubernetes com `runAsNonRoot: true` no pod security context, que precisa de um UID numérico para validar antes de o container iniciar;
- há bind mount cujo dono precisa bater com o UID do processo.

Nesses casos, use o UID do usuário embutido (na imagem `node` é `1000`) em vez de criar outro. Fora deles, aceite o achado e mencione a decisão no relatório — é isso que a linha `(1 info: DL3066, aceito)` comunica.

---

## `SKILL001` — a lacuna que o hadolint deixa

A Fase 2, item 6 exige que o processo não rode como root. A regra do hadolint para isso, `DL3002`, verifica se o **último `USER` é root** — o que só reprova quem escreveu `USER root` de propósito. O Dockerfile que nunca declara `USER` nenhum, que é como a maioria dos containers acaba rodando como root, passa com "sem achados".

Isso importa mais aqui do que em outro lugar porque é exatamente o erro que a Fase 8 não pega: o container sobe, responde ao health, passa em todo `curl` do checklist e vai para produção com privilégio que ninguém quis dar. Se o gate não cobrisse a omissão, a Fase 7 estaria prometendo uma garantia que não entrega.

Por isso o script faz a checagem por conta própria, e ela sai como `política` em vez de `error` — não é veredito do hadolint, e misturar as duas origens tornaria a linha-resumo enganosa para quem for reproduzir o resultado na mão.

O que a checagem entende:

- Só o **estágio final** conta. `USER` num estágio de build não protege a imagem que vai rodar.
- Se o estágio final é construído sobre um estágio anterior (`FROM base`), ela segue a cadeia e aceita o `USER` herdado dele.
- Continuações de linha, comentários e flags de `FROM` (`--platform=...`) não confundem a leitura.
- O que ela **não** enxerga é o `USER` que vem de dentro da imagem base — nenhuma análise estática do arquivo enxerga. É para esse caso que existe o pragma abaixo.

---

## Quando usar pragma de ignore

O hadolint aceita supressão por instrução:

```dockerfile
# hadolint ignore=DL3008 # imagem de build descartada no multi-stage; pin aqui não agrega
RUN apt-get update && apt-get install -y build-essential
```

Duas condições, e ambas importam:

**Sempre com o motivo na mesma linha.** Um pragma sem justificativa é indistinguível de alguém que quis calar o linter, e seis meses depois ninguém sabe se a supressão ainda vale.

**Sempre comunicado ao usuário.** Suprimir um achado é uma decisão sobre o Dockerfile dele, não um detalhe de implementação seu. Diga na resposta qual regra você suprimiu e por quê — a diferença entre um gate honesto e um teatro de gate é exatamente essa.

O `SKILL001` tem pragma próprio, porque não passa pelo hadolint — vale para o arquivo inteiro e vai em qualquer linha de comentário:

```dockerfile
# skill ignore=SKILL001 # nginx-unprivileged já roda como uid 101
FROM nginxinc/nginx-unprivileged:1.27-bookworm
```

O caso legítimo dele é sempre o mesmo: a imagem base já define um usuário sem privilégio (`nginx-unprivileged`, distroless `nonroot`, imagens internas que fazem isso), e o arquivo não tem como provar. Confirme que é o caso — `docker inspect --format '{{.Config.User}}' <imagem>` responde — antes de suprimir. Se não for, declarar o `USER` é mais barato que justificar.

Se você se pegar querendo suprimir a mesma regra em vários arquivos, o pragma é o instrumento errado: o certo é ajustar o nível dela na config.

---

## Ajustar o gate

O ponto de tuning das regras do hadolint é `assets/hadolint.yaml`, nunca o script. O script implementa a política (`error`/`warning`/`política` bloqueiam, `info`/`style` são observação); a config decide em qual nível cada regra do hadolint cai.

A exceção é o `SKILL001`, que não existe no hadolint e por isso vive no script (`checa_usuario_final`). Se a skill ganhar outra regra que nenhuma ferramenta cobre, é ali que ela entra — e sempre no nível `política`, para continuar distinguível do que veio do hadolint.

O princípio do arquivo: **ele codifica as regras que a skill já afirma em prosa, e nada além disso.** Um gate que reprova por coisas que ninguém pediu é um gate que as pessoas aprendem a ignorar — e aí ele para de valer para as coisas que importam. Se você quiser promover uma regra a `error`, o teste é: a skill exige isso em algum lugar do SKILL.md? Se não exige, ou a regra fica em `info`, ou a prosa da skill precisa mudar junto.

A lista completa de regras está em https://github.com/hadolint/hadolint#rules.
