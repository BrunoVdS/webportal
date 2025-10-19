<nav class="site-menu" aria-label="Main navigation">
  <button class="menu-toggle" type="button" aria-expanded="false" aria-controls="site-menu-drawer">
    <span class="menu-icon" aria-hidden="true">
      <span></span>
      <span></span>
      <span></span>
    </span>
    <span class="sr-only">Toggle navigation</span>
  </button>
  <div class="menu-drawer" id="site-menu-drawer">
    <ul>
      <li><a href="index.html">Home</a></li>
      <li><a href="downloads.html">Downloads</a></li>
      <li><a href="mesh.html">Mesh</a></li>
    </ul>
  </div>
</nav>
<script>
  (function () {
    const nav = document.querySelector('.site-menu');
    const toggle = nav === null ? null : nav.querySelector('.menu-toggle');
    if (!nav || !toggle) {
      return;
    }

    toggle.addEventListener('click', function () {
      const isExpanded = toggle.getAttribute('aria-expanded') === 'true';
      toggle.setAttribute('aria-expanded', String(!isExpanded));
      nav.classList.toggle('menu-open', !isExpanded);
    });

    nav.addEventListener('keydown', function (event) {
      if (event.key === 'Escape' && nav.classList.contains('menu-open')) {
        toggle.setAttribute('aria-expanded', 'false');
        nav.classList.remove('menu-open');
        toggle.focus();
      }
    });

    document.addEventListener('click', function (event) {
      if (!nav.contains(event.target)) {
        toggle.setAttribute('aria-expanded', 'false');
        nav.classList.remove('menu-open');
      }
    });
  })();
</script>
