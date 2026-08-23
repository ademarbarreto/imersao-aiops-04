---
prd_number: "001"
status: rascunho
priority: média
created: 2026-08-23
issue: ""
depends_on: []
references: []
---

# PRD 001: Filtro de Notícias na Tela Principal

## 1. Contexto

- **Produto/área**: kube-news, aplicação de publicação de notícias. Tela principal (`GET /`) lista todas as notícias cadastradas.
- **Estado atual**: a tela principal exibe todas as notícias cadastradas, sempre, sem nenhuma forma de busca ou filtro. Cada card mostra data, título e resumo; o conteúdo completo só é visível ao abrir a notícia individualmente. Não há paginação — a lista inteira é carregada de uma vez.
- **Problema**: à medida que o número de notícias cresce, encontrar uma notícia específica exige rolar a lista inteira. Não há como localizar uma notícia por palavra-chave.

> **Contexto técnico** (stack, arquitetura, padrões) vive no TRD (`docs/trd.md`), carregado automaticamente na implementação. Este projeto ainda não tem um TRD.

## 2. Solução Proposta

### Visão de produto

- Adicionar um campo de busca na tela principal.
- Conforme o usuário digita, a lista de notícias exibida é filtrada em tempo real, sem recarregar a página.
- A busca considera título, resumo e o conteúdo completo da notícia — inclusive texto que não aparece no card da listagem.
- Quando nenhuma notícia corresponde ao termo buscado, uma mensagem própria informa isso, distinta da mensagem exibida quando não há nenhuma notícia cadastrada.

### Decisões de produto

1. **Filtro atualiza a lista em tempo real, sem recarregar a página.** Justificativa: a listagem hoje não tem paginação (todas as notícias já chegam à tela principal de uma vez), então filtrar sem esperar um novo carregamento de página é a experiência mais direta.
2. **A busca cobre título, resumo e conteúdo completo, não só o que aparece no card.** Justificativa: limitar a busca ao que é visível no card faria buscas por termos presentes no corpo da notícia retornarem "nenhum resultado" de forma pouco intuitiva para quem lembra de um trecho do texto, mas não do título ou resumo exatos.
3. **Correspondência por trecho (substring), sem diferenciar maiúsculas/minúsculas.** Justificativa: comportamento padrão esperado de um campo de busca simples — não exige que o usuário lembre a grafia exata nem a palavra completa.

### Fora do escopo

- Paginação da listagem de notícias — não existe hoje e não será introduzida por esta feature.
- Busca por outros campos (data de publicação, autor, id).
- Operadores de busca avançados (aspas para frase exata, exclusão de termos, busca por múltiplas palavras com "E"/"OU" explícito).
- Destacar (highlight) o termo buscado no resultado.
- Persistir o termo buscado entre navegações ou ao recarregar a página.

## 3. Funcionalidades

### US01: Buscar notícias por título, resumo ou conteúdo

Como leitor do kube-news, quero digitar um termo em um campo de busca na tela principal, para encontrar rapidamente notícias que contenham esse termo, sem precisar rolar toda a lista.

**Rules:**
- A busca compara o termo digitado (sem diferenciar maiúsculas/minúsculas) contra o título, o resumo e o conteúdo completo de cada notícia.
- Uma notícia é exibida quando o termo aparece como trecho (substring) em pelo menos um desses três campos.
- A lista de notícias exibida é atualizada a cada alteração no campo de busca (a cada tecla digitada), sem recarregar a página e sem chamada adicional ao servidor a cada busca — a busca roda inteiramente no navegador sobre os dados já carregados na tela principal.
- Apagar o conteúdo do campo de busca volta a exibir todas as notícias cadastradas.

**Edge cases:**
- Nenhuma notícia corresponde ao termo digitado, mas existem notícias cadastradas → exibe mensagem "Nenhum resultado encontrado para sua busca", distinta da mensagem de "ainda não há posts".
- Termo digitado contém apenas espaços em branco → tratado como busca vazia; exibe todas as notícias.
- Não existe nenhuma notícia cadastrada no sistema (antes de qualquer busca) → mantém a mensagem atual de "Ainda não temos nenhum post, que tal você criar um?"; o campo de busca fica oculto nesse estado (não há o que buscar).

## 5. Critérios de Aceite

### 5a. Critérios de aceite da feature

| Critério | Razão de negócio | Como verificar (observável) |
|----------|------------------|-----------------------------|
| Digitar um termo no campo de busca filtra a lista sem recarregar a página | A listagem já carrega todas as notícias de uma vez (sem paginação); recarregar a página a cada busca seria uma regressão de fluidez sem necessidade técnica | Digitar um termo e observar que a lista muda sem que a página recarregue (URL e demais elementos da tela permanecem) |
| A busca encontra notícias por termos presentes só no conteúdo completo (não exibido no card) | Evita que o usuário receba "nenhum resultado" para um termo que lembra do corpo da notícia, mas não do título/resumo | Buscar um termo presente apenas no campo "Notícia" (conteúdo completo) de um post cadastrado e confirmar que ele aparece no resultado |
| Buscar um termo sem nenhuma correspondência, havendo notícias cadastradas, exibe mensagem própria de "nenhum resultado" | Diferencia visualmente de "não há posts cadastrados", evitando confundir o usuário sobre o motivo da lista vazia | Cadastrar ao menos uma notícia, buscar um termo que não aparece em nenhuma, e conferir a mensagem exibida |

### 5b. Métricas de sucesso

| Métrica | Baseline (fonte) | Meta | Prazo | Mín. aceitável | Responsável |
|---------|-------------------|------|-------|-----------------|-------------|
| Uso do campo de busca (buscas realizadas / sessões na tela principal) | A levantar — não há instrumentação de uso hoje *(premissa — confirme ou corrija)* | A definir | A definir | A definir | A definir |

## 6. Milestones

### Milestone 1: Buscar notícias na tela principal

**Por que é um marco:** entrega ao usuário a capacidade de localizar uma notícia específica sem depender de rolar a lista inteira — comportamento novo e perceptível na tela principal.

**Funcionalidades:** US01

**Checklist de aceite** (marcado pelo Aprovador após a implementação):
- [ ] Digitar um termo no campo de busca filtra a lista sem recarregar a página
- [ ] A busca encontra notícias por termos presentes só no conteúdo completo
- [ ] Buscar um termo sem correspondência exibe mensagem própria de "nenhum resultado"

**Aprovador:** Dono do produto *(premissa — confirme ou corrija)*

## 7. Riscos e Dependências

| Risco | Impacto | Mitigação | Status |
|-------|---------|-----------|--------|
| Crescimento do volume de notícias torna o filtro em tempo real perceptivelmente lento, já que todo o conteúdo completo precisa estar disponível na tela principal para a busca funcionar | Baixo | Reavaliar a abordagem (ex.: mover a busca para o servidor) se o volume de notícias crescer a ponto de impactar a experiência | Monitorando |

**Dependências:**

Nenhuma dependência de outra feature ou decisão de produto identificada.

## 8. Referências

Nenhuma referência externa identificada.

## 9. Registro de Decisões

- **2026-08-23:** Filtro implementado como atualização em tempo real (sem recarregar a página), em vez de busca via novo carregamento de página. Motivo: a listagem já carrega todas as notícias de uma vez hoje (sem paginação), então filtrar sem esperar um novo carregamento de página é a experiência mais direta, sem custo adicional relevante.
- **2026-08-23:** A busca cobre título, resumo e conteúdo completo da notícia, não só os campos exibidos no card da listagem. Motivo: evitar que buscas por trechos do corpo da notícia retornem "nenhum resultado" de forma pouco intuitiva.
- **2026-08-23:** O filtro é implementado como busca client-side: o conteúdo necessário para a busca (título, resumo e conteúdo completo de cada notícia) é entregue à tela principal já no carregamento inicial da página, e a filtragem a cada tecla digitada roda no navegador, sem nenhuma requisição nova ao servidor por busca. Motivo: é a única forma de sustentar "atualiza a cada tecla, sem recarregar a página, sem atraso perceptível" (decisões acima) sem depender de latência de rede; a alternativa (buscar via requisição ao servidor a cada busca) exigiria debounce e aceitaria uma janela de atraso, o que não está no escopo definido. Este é o primeiro código JavaScript client-side do projeto — hoje a aplicação é 100% renderizada no servidor (EJS), sem nenhum script no cliente. Trade-off aceito: o conteúdo completo de toda notícia cadastrada passa a ser enviado ao navegador no carregamento da tela principal, mesmo para notícias que o usuário nunca abra — crescimento de volume/tamanho de conteúdo impacta o peso da página inicial (ver risco na seção 7). Quando a stack e os padrões técnicos forem formalizados em TRD, esta decisão deve ser revisitada lá.
- **2026-08-23:** Quando não há nenhuma notícia cadastrada, o campo de busca fica oculto (não desabilitado). Motivo: não há o que buscar nesse estado; ocultar é mais direto que exibir um campo inerte.
- **2026-08-23:** Termo de busca contendo apenas espaços em branco é tratado como busca vazia (exibe todas as notícias). Motivo: comportamento padrão esperado, sem necessidade de mensagem de erro para um caso que não é um erro do usuário.
