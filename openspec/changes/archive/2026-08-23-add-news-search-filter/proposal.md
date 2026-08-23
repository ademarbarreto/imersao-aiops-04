## Why

A tela principal do kube-news lista todas as notícias cadastradas de uma vez, sem nenhuma forma de busca. À medida que o número de notícias cresce, encontrar uma notícia específica exige rolar a lista inteira, e não há como localizar uma notícia por palavra-chave — inclusive por palavras que só aparecem no conteúdo completo, não no card exibido na listagem.

## What Changes

- Adiciona um campo de busca na tela principal (`GET /`).
- Filtra a lista de notícias exibida a cada tecla digitada, sem recarregar a página e sem nenhuma requisição nova ao servidor por busca — a filtragem roda inteiramente no navegador sobre os dados já entregues no carregamento inicial da página.
- A busca compara o termo digitado (case-insensitive, por trecho/substring) contra título, resumo e conteúdo completo de cada notícia — inclusive texto que hoje não é enviado ao HTML da listagem.
- Exibe uma mensagem própria de "nenhum resultado encontrado" quando a busca não encontra correspondência, distinta da mensagem de "ainda não há posts".
- Campo de busca some quando não há nenhuma notícia cadastrada (nada para buscar).
- Termo de busca vazio ou só com espaços em branco volta a exibir todas as notícias.
- Introduz o primeiro JavaScript client-side do projeto (hoje 100% renderizado no servidor via EJS, sem nenhum script no cliente).

## Capabilities

### New Capabilities
- `news-search`: busca client-side por título, resumo e conteúdo completo das notícias na tela principal, com filtragem em tempo real conforme o usuário digita.

### Modified Capabilities
- Nenhuma capacidade existente documentada em `openspec/specs/` (apenas `containerization`) tem requisitos alterados por esta mudança.

## Impact

- **Código afetado**: `src/views/index.ejs` (novo campo de busca, dados de busca embutidos na página, elemento de "nenhum resultado"), `src/server.js` (rota `GET /` passa a fornecer título/resumo/conteúdo completo de cada post ao template, dado hoje já disponível em `Post.findAll()` mas não repassado ao HTML).
- **Novo asset estático**: um arquivo JS client-side (ex.: `src/static/scripts/search.js`) — primeiro do projeto.
- **Sem mudança de API/rotas**: nenhum endpoint novo é criado; a busca não faz nenhuma requisição ao servidor.
- **Sem mudança de schema/banco de dados**.
- **Trade-off aceito**: o conteúdo completo de toda notícia cadastrada passa a ser enviado ao navegador no carregamento da tela principal, mesmo para notícias que o usuário nunca abra. Isso aumenta o peso da página inicial proporcionalmente ao volume e tamanho do conteúdo cadastrado (campo `content` é limitado a 2000 caracteres). Se o volume de notícias crescer a ponto de impactar a experiência, a abordagem deve ser reavaliada (ex.: mover a busca para o servidor).
- **Fora do escopo**: paginação da listagem, busca por outros campos (data, autor, id), operadores de busca avançados, highlight do termo buscado, e persistência do termo buscado entre navegações.
