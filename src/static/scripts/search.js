(function () {
    var searchInput = document.getElementById('posts-search__input');
    var postsGrid = document.getElementById('posts-list__grid');
    var noResultsContainer = document.getElementById('no-results__container');
    var postsDataElement = document.getElementById('posts-data');

    if (!searchInput || !postsGrid || !noResultsContainer || !postsDataElement) {
        return;
    }

    var posts = JSON.parse(postsDataElement.textContent);

    function buildCard(post) {
        var item = document.createElement('div');
        item.className = 'posts-list__item';

        var card = document.createElement('div');
        card.className = 'post__card';

        var date = document.createElement('span');
        date.className = 'post__card__date';
        date.textContent = post.publishDate;

        var title = document.createElement('h4');
        title.className = 'post__card__title';
        title.textContent = post.title;

        var description = document.createElement('p');
        description.className = 'post__card__description';
        description.textContent = post.summary;

        var button = document.createElement('button');
        button.className = 'post__card__button';
        button.textContent = 'Saiba Mais';
        button.addEventListener('click', function () {
            location.href = '/post/' + post.id;
        });

        card.appendChild(date);
        card.appendChild(title);
        card.appendChild(description);
        card.appendChild(button);
        item.appendChild(card);

        return item;
    }

    function renderPosts(filteredPosts) {
        postsGrid.innerHTML = '';
        filteredPosts.forEach(function (post) {
            postsGrid.appendChild(buildCard(post));
        });

        var hasResults = filteredPosts.length > 0;
        postsGrid.hidden = !hasResults;
        noResultsContainer.hidden = hasResults;
    }

    function filterPosts(term) {
        var normalizedTerm = term.trim().toLowerCase();

        if (normalizedTerm === '') {
            return posts;
        }

        return posts.filter(function (post) {
            return post.title.toLowerCase().includes(normalizedTerm) ||
                post.summary.toLowerCase().includes(normalizedTerm) ||
                post.content.toLowerCase().includes(normalizedTerm);
        });
    }

    searchInput.addEventListener('input', function (event) {
        renderPosts(filterPosts(event.target.value));
    });
})();
