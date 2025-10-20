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
    <?php include __DIR__ . '/php/menu.php'; ?>
    <?php include __DIR__ . '/php/theme-toggle.php'; ?>
    <main id="main-content" class="page-main" tabindex="-1">
      <header class="page-hero">
        <p class="hero-eyebrow">Mesh Operations</p>
        <h1>Resources for resilient field connectivity</h1>
        <p class="hero-summary">
          Access deployment guides, live tooling, and situational awareness dashboards for
          your mesh network footprint. Everything here is curated for austere environments.
        </p>
        <div class="hero-actions">
          <a class="button" href="downloads.php">Grab supporting apps</a>
          <a class="button" href="index.php">Return to dashboard</a>
        </div>
      </header>

      <section class="content-card">
        <h2>Documentation</h2>
        <p>
          Detailed field manuals, quick start cards, and network design references to help
          your team stage and maintain resilient coverage.
        </p>
        <ul class="download-links">
          <li><a href="/mesh/docs/">Mesh documentation</a></li>
          <li><a href="/mesh/field-cards/">Field reference cards</a></li>
        </ul>
      </section>

      <section class="content-card">
        <h2>Operational tooling</h2>
        <p>
          Access live utilities for monitoring nodes, planning routes, and coordinating with
          partner teams across the mesh.
        </p>
        <ul class="download-links">
          <li><a href="/mesh/tools/">Mesh tooling suite</a></li>
          <li><a href="/mesh/status/">Network status board</a></li>
        </ul>
      </section>
    </main>

    <?php include __DIR__ . '/php/footer.php'; ?>
    <script src="js/menu.js"></script>
    <script src="js/theme-toggle.js"></script>
  </body>
</html>
