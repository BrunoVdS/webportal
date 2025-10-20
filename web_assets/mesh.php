<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta
      name="description"
      content="Explore mesh network documentation and tools available from the Raspberry Pi download server."
    >
    <title>Mesh Network Resources</title>
    <link rel="stylesheet" href="styles.css">
  </head>
  <body>
    <a class="skip-link" href="#main-content">Skip to main content</a>
    <?php include __DIR__ . '/php/menu.php'; ?>
    <?php include __DIR__ . '/php/theme-toggle.php'; ?>
    <header class="page-hero">
      <p class="hero-eyebrow">Mesh Network Resources</p>
      <h1>Build resilient field connectivity</h1>
      <p class="hero-summary">
        Access playbooks, diagnostics, and deployment utilities that keep the mesh network
        operating across remote Raspberry Pi sites.
      </p>
    </header>

    <main id="main-content" class="page-main" tabindex="-1">
      <section class="content-card">
        <h2>Documentation</h2>
        <p>
          Review step-by-step guides for standing up new nodes, integrating with backhaul
          links, and troubleshooting on-site issues.
        </p>
        <p class="cta-link"><a href="/mesh/docs/">Browse mesh documentation</a></p>
      </section>

      <section class="content-card">
        <h2>Tools and utilities</h2>
        <p>
          Download monitoring scripts, configuration templates, and firmware bundles that
          support day-to-day network maintenance.
        </p>
        <p class="cta-link"><a href="/mesh/tools/">Download mesh tooling</a></p>
      </section>
    </main>

    <?php include __DIR__ . '/php/footer.php'; ?>
    <script src="js/menu.js"></script>
    <script src="js/theme-toggle.js"></script>
  </body>
</html>
