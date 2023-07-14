<div class="site-header-inner">
    <h1 class="site-title">
        <a href="{{ url_for('.') }}" class="logo">{{ config.title }}</a>
    </h1>

    <nav id="nav-top">
        {% if theme.menu %}
            <ul id="menu-top" class="nav-top-items">
                <li class="menu-item">
                  <a href="https://bobs-club.net/site/funemy/pred" title="previous site">&lt;&lt;</a>
                  <a href="https://bobs-club.net/site/funemy/random" title="random site">?</a>
                  <a href="https://bobs-club.net/" title="web ring">bob's club</a>
                  <a href="https://bobs-club.net/site/funemy/succ" title="next site">&gt;&gt;</a>
                </li>
                {% for name, path in theme.menu %}
                    <li class="menu-item">
                        <a href="{{ url_for(path) }}">
                            {% set itemName = 'menu.' + name.toLowerCase() %}
                            {% if itemName.startsWith('menu') %}
                                {{ name }}
                            {% else %}
                                {{ __(itemName) }}
                            {% endif %}
                        </a>
                    </li>
                {% endfor %}
            </ul>
        {% endif %}
  </nav>
</div>
