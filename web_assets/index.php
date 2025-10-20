<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta
      name="description"
      content="Access Node portal,mesh info and download server."
    >
    <title>Node LAN portal</title>
    <link rel="stylesheet" href="styles.css">
  </head>
  <body>
    <a class="skip-link" href="#main-content">Skip to main content</a>
    <?php include __DIR__ . '/php/menu.php'; ?>
    <?php include __DIR__ . '/php/theme-toggle.php'; ?>
    <main id="main-content" class="page-main" tabindex="-1">
      <header class="page-hero">
        <p class="hero-eyebrow">Pi Download Server</p>
        <h1>Welcome to the Raspberry Pi download server</h1>
        <p>Files: <a href="downloads.php">Download files</a></p>
        <p class="hero-summary">
          Your hub for firmware, operating system images, and mesh network resources for
          Raspberry Pi devices managed by the field network team.
        </p>
        <div class="hero-actions">
          <a class="button primary" href="downloads.php">Browse downloads</a>
          <a class="button" href="mesh.php">Explore mesh resources</a>
        </div>
      </header>

      <section class="content-card">
        <h2>Getting started</h2>
        <p>
          Use the download center to grab the latest operating system builds, configuration
          archives, and supporting documentation. Each download entry links directly to the
          files hosted on this server so you can mirror or script access as needed.
        </p>
        <ul class="feature-list">
          <li>Review release notes before flashing a new image to your devices.</li>
          <li>Download assets directly or copy the link for automated deployments.</li>
          <li>Visit the mesh network area for site-to-site tooling and guidance.</li>
        </ul>
      </section>

      <section class="content-card">
        <h2>Quick links</h2>
        <p>
          Ready to dive straight into the repository? Jump directly to the full directory
          listing to locate a specific image or asset.
        </p>
        <p class="cta-link"><a href="/files/">Open the /files/ directory</a></p>
      </section>
    </main>

    <?php include __DIR__ . '/php/footer.php'; ?>
    <script src="js/menu.js"></script>
    <script src="js/theme-toggle.js"></script>
  </body>
</html>
