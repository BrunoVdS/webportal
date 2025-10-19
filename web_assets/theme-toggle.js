(function () {
  const THEME_KEY = "preferredTheme";
  const body = document.body;
  const toggleButton = document.getElementById("theme-toggle");

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
      if (theme === "night-vision") {
        localStorage.setItem(THEME_KEY, theme);
      } else {
        localStorage.removeItem(THEME_KEY);
      }
    } catch (error) {
      // Ignore storage errors (e.g., private browsing)
    }
  }

  let currentTheme = getStoredTheme() === "night-vision" ? "night-vision" : "standard";
  applyTheme(currentTheme);

  toggleButton.addEventListener("click", () => {
    currentTheme = currentTheme === "night-vision" ? "standard" : "night-vision";
    applyTheme(currentTheme);
    storeTheme(currentTheme);
  });
})();
