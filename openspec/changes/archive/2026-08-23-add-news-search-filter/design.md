## Context

A tela principal (`GET /`) é renderizada inteiramente no servidor via EJS. A rota busca todos os posts com `Post.findAll()` (Sequelize) — o que já traz `title`, `summary`, `content`, `publishDate` e `id` de cada post para dentro do processo Node — mas `views/index.ejs` só imprime `publishDate`, `title`, `summary` e `id` no HTML; `content` nunca chega ao navegador hoje.

O projeto não tem, hoje, nenhum JavaScript client-side: sem bundler, sem `<script>` custom nos partials, sem dependência de frontend no `package.json`. Não há paginação — a listagem inteira é carregada de uma vez em cada `GET /`. Não há `docs/trd.md` ainda, então não há um lugar formal onde padrões de frontend do projeto estejam registrados; este design é o primeiro precedente.

## Goals / Non-Goals

**Goals:**
- Filtrar a listagem de notícias por título, resumo e conteúdo completo, a cada tecla digitada, sem recarregar a página e sem latência perceptível.
- Não introduzir nenhuma chamada de rede nova por busca.
- Manter a rota `GET /` e o modelo de dados sem mudanças estruturais.

**Non-Goals:**
- Paginação da listagem.
- Busca no servidor / endpoint de busca dedicado.
- Highlight do termo buscado, operadores de busca avançados, ou persistência do termo entre navegações.
- Otimizar para volumes de notícias muito grandes (ver risco de payload abaixo — mitigação fica para uma revisão futura, fora do escopo desta mudança).

## Decisions

### Decisão 1: busca 100% client-side, dados embutidos no carregamento inicial

A filtragem roda inteiramente no navegador, sobre um array de posts (título, resumo, conteúdo) serializado como JSON e embutido na própria página (`GET /`) no momento do render — sem nenhum `fetch`/XHR novo.

**Por quê:** é a única forma de sustentar "atualiza a cada tecla digitada, sem recarregar a página, sem atraso perceptível" sem depender de latência de rede. A alternativa (buscar via requisição ao servidor a cada busca) exigiria debounce e aceitaria uma janela de atraso variável — comportamento explicitamente fora do que o produto pediu.

**Alternativa considerada e descartada:** endpoint `GET /api/posts?q=...` fazendo `ILIKE '%termo%'` em `title`/`summary`/`content` via Sequelize, chamado via `fetch` debounced a cada tecla, com JS trocando a lista no DOM. Escalaria melhor com volume de notícias e não infla o payload inicial, mas introduz latência de rede por busca (contradizendo a decisão de produto de "sem atraso perceptível") e é o primeiro endpoint JSON do projeto, além do primeiro JS. Fica como caminho de migração se o risco de payload (abaixo) se concretizar.

### Decisão 2: `Post.findAll()` continua sem alterações; `content` passa a ser repassado ao template

`server.js` já busca `content` do banco em `GET /` — só não repassa para o `render`. A mudança é exclusivamente no que é passado para `index.ejs` e no que o template imprime (agora como dado embutido, não necessariamente como HTML visível), não na consulta ao banco.

**Por quê:** evita duplicar lógica de acesso a dados ou criar uma segunda query; o dado já está disponível no processo no momento certo.

### Decisão 3: filtragem case-insensitive por substring, em JS puro

Comparação via `.toLowerCase().includes(termo.toLowerCase())` contra os três campos, sem biblioteca de busca (Fuse.js, Lunr etc.).

**Por quê:** a regra de negócio é substring simples, sem operadores avançados, sem ranking de relevância — trazer uma lib de busca seria complexidade não pedida pelo escopo (ver PRD, "Fora do escopo": operadores de busca avançados).

### Decisão 4: `content` completo do post não é escrito como texto visível no DOM, só como dado (JSON embutido em `<script type="application/json">` ou `data-*` não renderizado)

**Por quê:** o card de listagem não deve passar a exibir o conteúdo completo — só título, resumo, data continuam visíveis, como hoje. O conteúdo full só precisa estar acessível para o JS de filtro ler, não para o usuário ler na tela principal.

## Risks / Trade-offs

- **[Risco] Payload da página inicial cresce com o volume e tamanho do conteúdo cadastrado** (campo `content` é `VARCHAR(2000)`, sem limite de quantidade de posts) → **Mitigação:** aceito como trade-off nesta mudança (risco já registrado como "Baixo" no PRD, seção 7); se o volume de notícias crescer a ponto de impactar a experiência (tempo de carregamento da tela principal), reavaliar para a alternativa de busca no servidor (Decisão 1, alternativa descartada).
- **[Risco] Primeiro JavaScript client-side do projeto** → nenhum padrão de organização de assets frontend existe ainda (não há bundler, não há convenção de módulos). **Mitigação:** manter o script como um único arquivo estático simples (`src/static/scripts/search.js`), sem build step, consistente com o resto do projeto (CSS servido estático sem pré-processamento). Se o projeto ganhar mais JS no futuro, isso deve virar uma decisão de TRD.
- **[Trade-off] Conteúdo completo de toda notícia trafega ao navegador mesmo sem o usuário nunca abrir aquela notícia** → aceito; é inerente à Decisão 1 e já estava implícito na Regra de Negócio do PRD que exige buscar por conteúdo completo sem chamada ao servidor.

## Migration Plan

Sem migração de dados ou schema. Deploy é o fluxo normal do projeto (build de imagem + rollout via k8s manifests existentes). Sem flag de feature — a busca aparece diretamente na tela principal assim que a mudança for deployada. Rollback é reverter o deploy (sem estado persistido pela feature).

## Open Questions

Nenhuma pendente — as ambiguidades identificadas na exploração (client-side vs. servidor, campo oculto vs. desabilitado quando não há posts, tratamento de espaços em branco) já foram decididas e registradas no PRD (`docs/prds/001-filtro-de-noticias.md`, seção 9).
