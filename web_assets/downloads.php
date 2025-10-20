<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta
      name="description"
      content="Browse and download files available from the Raspberry Pi download server."
    >
    <title>Download Center</title>
    <link rel="stylesheet" href="styles.css">
  </head>
  <body>
    <?php include __DIR__ . '/php/menu.php'; ?>
    <?php include __DIR__ . '/php/theme-toggle.php'; ?>
    <?php
      $downloads = [
        [
          'title' => 'ATAK for Raspberry Pi',
          'description' => 'Latest Android Team Awareness Kit client build packaged for Raspberry Pi devices.',
          'file' => '/files/atak.apk',
          'logo' => 'images/apatch-logo.svg',
        ],
        [
          'title' => 'Sideband Communications Suite',
          'description' => 'Secure messaging and voice add-on to enhance field communications and coordination.',
          'file' => '/files/sideband.apk',
          'logo' => 'images/apatch-logo.svg',
        ],
        [
          'title' => 'RNS Field Tools (Coming Soon)',
          'description' => 'Utility toolkit for managing RNS deployments. Subscribe for alerts when the APK is published.',
          'file' => null,
          'logo' => 'images/apatch-logo.svg',
        ],
      ];
    ?>

    <main id="main-content" class="page-main" tabindex="-1">
      <header class="page-hero">
        <p class="hero-eyebrow">Download Center</p>
        <h1>Mission ready software packages</h1>
        <p class="hero-summary">
          Select an application below to review its capabilities and grab the latest
          build for your field kits. All downloads are served directly from this node
          for reliable offline mirroring.
        </p>
        <div class="hero-actions">
          <a class="button" href="/files/">View raw directory</a>
          <a class="button" href="index.php">Return to dashboard</a>
        </div>
      </header>

      <section class="content-card">
        <h2>Available downloads</h2>
        <p>
          Browse curated tooling, communications suites, and support utilities engineered
          for rapid deployment. Each entry includes a signed package ready for transfer to
          your devices.
        </p>

        <div class="download-grid" aria-label="Available downloads">
          <?php foreach ($downloads as $download): ?>
            <article class="download-card">
              <div class="download-card__media" aria-hidden="true">
                <img
                  src="<?php echo htmlspecialchars($download['logo'], ENT_QUOTES); ?>"
                  alt=""
                  class="download-card__logo"
                >
              </div>
              <div class="download-card__body">
                <h3 class="download-card__title"><?php echo htmlspecialchars($download['title']); ?></h3>
                <p class="download-card__description"><?php echo htmlspecialchars($download['description']); ?></p>
              </div>
              <?php if (!empty($download['file'])): ?>
                <a class="download-card__button" href="<?php echo htmlspecialchars($download['file'], ENT_QUOTES); ?>" download>
                  Download APK
                </a>
              <?php else: ?>
                <span class="download-card__placeholder" aria-label="Download coming soon">Coming Soon</span>
              <?php endif; ?>
            </article>
          <?php endforeach; ?>
        </div>
      </section>

      <section class="content-card">
        <h2>Need direct access?</h2>
        <p>
          The <code>/files/</code> directory mirrors every artifact exposed through this
          portal. Use the link below to script automated retrievals or to capture checksums
          for integrity verification before field deployment.
        </p>
        <p class="cta-link"><a href="/files/">Open the /files/ directory</a></p>
      </section>
    </main>

    <?php include __DIR__ . '/php/footer.php'; ?>
    <script src="js/menu.js"></script>
    <script src="js/theme-toggle.js"></script>
  </body>
</html>
