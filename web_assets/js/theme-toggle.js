(function () {
  const THEME_KEY = "preferredTheme";
  const body = document.body;
  const toggleButton = document.getElementById("theme-toggle");
  const mediaQuery =
    typeof window.matchMedia === "function"
      ? window.matchMedia("(prefers-color-scheme: dark)")
      : null;

  if (!toggleButton) {
    return;
  }

  function applyTheme(theme) {
    const isNightVision = theme === "night-vision";
    body.classList.toggle("night-vision", isNightVision);
    toggleButton.textContent = isNightVision ? "Disable night vision" : "Enable night vision";
    toggleButton.setAttribute("aria-pressed", String(isNightVision));
  }

  function getStoredTheme() {
    try {
      return localStorage.getItem(THEME_KEY);
    } catch (error) {
      return null;
    }
  }

  function storeTheme(theme) {
    try {
      if (theme === "night-vision" || theme === "standard") {
        localStorage.setItem(THEME_KEY, theme);
      } else {
        localStorage.removeItem(THEME_KEY);
      }
    } catch (error) {
      // Ignore storage errors (e.g., private browsing)
    }
  }

  function determineInitialTheme() {
    const storedTheme = getStoredTheme();

    if (storedTheme === "night-vision" || storedTheme === "standard") {
      return storedTheme;
    }

    if (mediaQuery && mediaQuery.matches) {
      return "night-vision";
    }

    return "standard";
  }

  let currentTheme = determineInitialTheme();
  applyTheme(currentTheme);

  if (mediaQuery) {
    const handlePreferenceChange = (event) => {
      const storedTheme = getStoredTheme();

      if (storedTheme === "night-vision" || storedTheme === "standard") {
        return;
      }

      currentTheme = event.matches ? "night-vision" : "standard";
      applyTheme(currentTheme);
    };

    if (typeof mediaQuery.addEventListener === "function") {
      mediaQuery.addEventListener("change", handlePreferenceChange);
    } else if (typeof mediaQuery.addListener === "function") {
      mediaQuery.addListener(handlePreferenceChange);
    }
  }

  toggleButton.addEventListener("click", () => {
    currentTheme = currentTheme === "night-vision" ? "standard" : "night-vision";
    applyTheme(currentTheme);
    storeTheme(currentTheme);
  });
})();
