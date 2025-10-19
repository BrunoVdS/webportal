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

    <main>
      <h1>Download Center</h1>
      <p>Select an application below to view its description and download the latest build.</p>

      <section class="download-grid" aria-label="Available downloads">
        <?php foreach ($downloads as $download): ?>
          <article class="download-card">
            <img
              src="<?php echo htmlspecialchars($download['logo'], ENT_QUOTES); ?>"
              alt="<?php echo htmlspecialchars($download['title'], ENT_QUOTES); ?> logo"
              class="download-card__logo"
            >
            <div class="download-card__body">
              <h2 class="download-card__title"><?php echo htmlspecialchars($download['title']); ?></h2>
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
      </section>

      <p class="back-link"><a href="index.php">Back to the home page</a></p>
    </main>

    <?php include __DIR__ . '/php/footer.php'; ?>
    <script src="js/menu.js"></script>
    <script src="js/theme-toggle.js"></script>
  </body>
</html>
