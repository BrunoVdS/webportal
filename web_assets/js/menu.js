(function () {
  const nav = document.querySelector('.site-menu');
  if (!nav) {
    return;
  }

  const toggle = nav.querySelector('.menu-toggle');
  const drawer = nav.querySelector('.menu-drawer');

  if (!toggle || !drawer) {
    return;
  }

  const closeMenu = () => {
    toggle.setAttribute('aria-expanded', 'false');
    nav.classList.remove('menu-open');
  };

  const openMenu = () => {
    toggle.setAttribute('aria-expanded', 'true');
    nav.classList.add('menu-open');
  };

  const toggleMenu = () => {
    if (nav.classList.contains('menu-open')) {
      closeMenu();
    } else {
      openMenu();
    }
  };

  nav.classList.add('js-ready');
  closeMenu();

  toggle.addEventListener('click', () => {
    toggleMenu();
  });

  nav.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && nav.classList.contains('menu-open')) {
      closeMenu();
      toggle.focus();
    }
  });

  document.addEventListener('click', (event) => {
    if (!nav.contains(event.target)) {
      closeMenu();
    }
  });
})();
