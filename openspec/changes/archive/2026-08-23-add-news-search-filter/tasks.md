## 1. Servidor: entregar os dados de busca à página

- [x] 1.1 Em `src/server.js`, na rota `GET /`, repassar `content` de cada post ao `render('index', ...)` (hoje só `title`, `summary`, `publishDate`, `id` chegam ao template — `content` já vem de `Post.findAll()` mas não é passado adiante).

## 2. Template: campo de busca e dados embutidos

- [x] 2.1 Em `src/views/index.ejs`, adicionar o campo de busca (`<input>`) no topo da tela principal, visível apenas quando `posts.length > 0`.
- [x] 2.2 Embutir os posts (id, título, resumo, conteúdo completo) como JSON não visível na página (ex.: `<script type="application/json" id="posts-data">`), sem escrever o conteúdo completo como texto solto no DOM.
- [x] 2.3 Adicionar um elemento de mensagem "Nenhum resultado encontrado para sua busca", inicialmente oculto, distinto do bloco de "Ainda não temos nenhum post".
- [x] 2.4 Manter a estrutura de card atual (data, título, resumo, botão "Saiba Mais") intacta para os itens filtrados.

## 3. JavaScript client-side: filtro em tempo real

- [x] 3.1 Criar `src/static/scripts/search.js` (primeiro script client-side do projeto) — sem bundler, sem dependências novas.
- [x] 3.2 Ler o JSON embutido de posts no carregamento da página.
- [x] 3.3 A cada evento de input no campo de busca, filtrar os posts comparando o termo (lowercase, trim) como substring contra título, resumo e conteúdo completo (lowercase) de cada post.
- [x] 3.4 Re-renderizar a lista exibida no DOM a cada tecla, sem requisição ao servidor e sem recarregar a página.
- [x] 3.5 Termo vazio ou só com espaços em branco (após trim) exibe todos os posts.
- [x] 3.6 Quando o filtro não encontra nenhum post, ocultar a grid de cards e mostrar a mensagem de "nenhum resultado"; quando encontra, o inverso.
- [x] 3.7 Incluir `search.js` em `src/views/index.ejs` (`<script src="/scripts/search.js">`), carregado só quando há posts.

## 4. Estilo

- [x] 4.1 Adicionar estilos do campo de busca e da mensagem de "nenhum resultado" em `src/static/styles/main.css`, consistentes com o visual existente da tela principal.

## 5. Verificação manual

- [x] 5.1 Subir a aplicação localmente (`docker-compose` ou stack existente) com pelo menos duas notícias cadastradas, uma delas com um termo exclusivo no conteúdo completo (fora de título/resumo).
- [x] 5.2 Digitar esse termo no campo de busca e confirmar que a notícia aparece, sem reload de página (URL inalterada).
- [x] 5.3 Digitar um termo que não corresponde a nenhuma notícia e confirmar a mensagem de "nenhum resultado", distinta da mensagem de "sem posts".
- [x] 5.4 Apagar o campo de busca e confirmar que todas as notícias voltam a aparecer.
- [x] 5.5 Digitar um termo só com espaços e confirmar que todas as notícias aparecem (tratado como busca vazia).
- [x] 5.6 Testar com o banco sem nenhuma notícia cadastrada e confirmar que o campo de busca fica oculto e a mensagem de "ainda não há posts" continua aparecendo.
- [x] 5.7 Confirmar case-insensitive: buscar um termo em caixa diferente da grafia original no título/resumo/conteúdo de uma notícia.
