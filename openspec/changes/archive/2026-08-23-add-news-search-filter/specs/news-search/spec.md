## ADDED Requirements

### Requirement: Busca por título, resumo e conteúdo completo
O sistema SHALL exibir um campo de busca na tela principal quando houver pelo menos uma notícia cadastrada. O sistema SHALL filtrar a lista de notícias exibida comparando o termo digitado, sem diferenciar maiúsculas/minúsculas, como trecho (substring) contra o título, o resumo e o conteúdo completo de cada notícia — inclusive contra texto que não é exibido no card da listagem.

#### Scenario: Busca encontra notícia pelo título
- **WHEN** o usuário digita um termo que aparece no título de uma notícia cadastrada
- **THEN** a notícia é exibida na lista

#### Scenario: Busca encontra notícia pelo resumo
- **WHEN** o usuário digita um termo que aparece apenas no resumo de uma notícia cadastrada
- **THEN** a notícia é exibida na lista

#### Scenario: Busca encontra notícia pelo conteúdo completo, não exibido no card
- **WHEN** o usuário digita um termo que aparece apenas no conteúdo completo de uma notícia, e esse termo não aparece no título nem no resumo
- **THEN** a notícia é exibida na lista

#### Scenario: Busca é case-insensitive
- **WHEN** o usuário digita um termo em caixa diferente da grafia original no título, resumo ou conteúdo de uma notícia (ex.: minúsculo onde o texto original é maiúsculo)
- **THEN** a notícia correspondente é exibida na lista

### Requirement: Filtragem em tempo real sem recarregar a página
O sistema SHALL atualizar a lista de notícias exibida a cada tecla digitada no campo de busca, sem recarregar a página e sem realizar nenhuma requisição adicional ao servidor por busca.

#### Scenario: Lista atualiza a cada tecla digitada
- **WHEN** o usuário digita ou apaga um caractere no campo de busca
- **THEN** a lista de notícias exibida é atualizada imediatamente, sem que a página seja recarregada (URL e demais elementos da tela permanecem)

#### Scenario: Apagar o campo de busca restaura a lista completa
- **WHEN** o usuário apaga todo o conteúdo do campo de busca
- **THEN** todas as notícias cadastradas voltam a ser exibidas

#### Scenario: Termo com apenas espaços em branco é tratado como busca vazia
- **WHEN** o usuário digita um termo composto só de espaços em branco
- **THEN** todas as notícias cadastradas são exibidas, como se o campo estivesse vazio

### Requirement: Mensagem distinta para busca sem resultado
O sistema SHALL exibir uma mensagem própria de "nenhum resultado encontrado" quando existir ao menos uma notícia cadastrada mas nenhuma corresponder ao termo buscado, distinta da mensagem exibida quando não há nenhuma notícia cadastrada no sistema.

#### Scenario: Busca sem correspondência, havendo notícias cadastradas
- **WHEN** existe ao menos uma notícia cadastrada e o usuário digita um termo que não corresponde a nenhuma notícia
- **THEN** o sistema exibe uma mensagem de "nenhum resultado encontrado para sua busca", diferente da mensagem de "ainda não há posts"

#### Scenario: Nenhuma notícia cadastrada no sistema
- **WHEN** não existe nenhuma notícia cadastrada no sistema
- **THEN** o sistema mantém a mensagem existente de "Ainda não temos nenhum post, que tal você criar um?" e o campo de busca fica oculto
