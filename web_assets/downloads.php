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
      $downloads_software = [
        [
          'title' => 'ATAK for Raspberry Pi',
          'description' => 'Latest Android Team Awareness Kit client build packaged for Raspberry Pi devices.',
          'file' => '/files/software/atak.apk',
          'logo' => 'images/atak_civ.png',
        ],
        [
          'title' => 'Sideband Communications Suite',
          'description' => 'Secure messaging and voice add-on to enhance field communications and coordination.',
          'file' => '/files/software/sideband.apk',
          'logo' => 'images/reticulum_sideband.png',
        ],
        [
          'title' => 'RNS Field Tools (Coming Soon)',
          'description' => 'Utility toolkit for managing RNS deployments. Subscribe for alerts when the APK is published.',
          'file' => null,
          'logo' => 'images/reticulum_sideband.png',
        ],
      ];
    ?>

    <?php
      $downloads_manual = [
        [
          'title' => 'ATAK manual',
          'description' => 'Complete ATAK manual in PFD format.',
          'file' => '/files/software/atak.PDF',
          'logo' => 'images/atak_civ.png'
        ],
        [
          'title' => 'Reticulum manual',
          'description' => 'Complete Reticulum manual in PFD format.',
          'file' => '/files/manual/reticulum.pdf',
          'logo' => 'images/reticulum_sideband.png',
        ],
        [
          'title' => 'RNS Field Tools manual (Coming Soon)',
          'description' => 'Utility toolkit manual in PDF format.',
          'file' => null,
          'logo' => 'images/reticulum_sideband.png',
        ],
      ];
    ?>

    <main id="main-content" class="page-main" tabindex="-1">
      <header class="page-hero">
        <h1>Download Center</h1>
        <div class="hero-actions">
          <a class="button" href="index.php">Return to dashboard</a>
        </div>
      </header>

      <section class="content-card">
        <h2>Software</h2>
        <p>
          Browse curated tooling, communications suites, and support utilities engineered
          for rapid deployment. Each entry includes a signed package ready for transfer to
          your devices.
        </p>

        <div class="download-grid" aria-label="Available downloads">
          <?php foreach ($downloads_software as $download_software): ?>
            <article class="download-card">
              <div class="download-card__media" aria-hidden="true">
                <img
                  src="<?php echo htmlspecialchars($download_software['logo'], ENT_QUOTES); ?>"
                  alt=""
                  class="download-card__logo"
                >
              </div>
              <div class="download-card__body">
                <h3 class="download-card__title"><?php echo htmlspecialchars($download_software['title']); ?></h3>
                <p class="download-card__description"><?php echo htmlspecialchars($download_software['description']); ?></p>
              </div>
              <div class="download-card__actions">
                <?php if (!empty($download_software['file'])): ?>
                  <a
                    class="download-card__button button"
                    href="<?php echo htmlspecialchars($download_software['file'], ENT_QUOTES); ?>"
                    download
                  >
                    Download APK
                  </a>
                <?php else: ?>
                  <span class="download-card__placeholder" aria-label="Download coming soon">Coming Soon</span>
                <?php endif; ?>
              </div>
            </article>
          <?php endforeach; ?>
        </div>
      </section>

<section class="content-card">
        <h2>Manual</h2>
        <p>
          All the PDF manual you could need to expand your knowledge of the software used in this node.
        </p>

        <div class="download-grid" aria-label="Available downloads">
          <?php foreach ($downloads_manual as $download_manual): ?>
            <article class="download-card">
              <div class="download-card__media" aria-hidden="true">
                <img
                  src="<?php echo htmlspecialchars($download_manual['logo'], ENT_QUOTES); ?>"
                  alt=""
                  class="download-card__logo"
                >
              </div>
              <div class="download-card__body">
                <h3 class="download-card__title"><?php echo htmlspecialchars($download_manual['title']); ?></h3>
                <p class="download-card__description"><?php echo htmlspecialchars($download_manual['description']); ?></p>
              </div>
              <div class="download-card__actions">
                <?php if (!empty($download_manual['file'])): ?>
                  <a
                    class="download-card__button button"
                    href="<?php echo htmlspecialchars($download_manual['file'], ENT_QUOTES); ?>"
                    download
                  >
                    Download manual
                  </a>
                <?php else: ?>
                  <span class="download-card__placeholder" aria-label="Download coming soon">Coming Soon</span>
                <?php endif; ?>
              </div>
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
        <div class="content-card__cta">
          <a class="button" href="/files/">View raw directory</a>
        </div>
      </section>
    </main>

    <?php include __DIR__ . '/php/footer.php'; ?>
    <script src="js/menu.js"></script>
    <script src="js/theme-toggle.js"></script>
  </body>
</html>
