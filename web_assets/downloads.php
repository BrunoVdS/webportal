<?php
$downloadDir = __DIR__ . '/files';
$downloadFiles = [];

if (is_dir($downloadDir) && is_readable($downloadDir)) {
    foreach (scandir($downloadDir) as $entry) {
        if ($entry === '.' || $entry === '..' || strpos($entry, '.') === 0) {
            continue;
        }

        $filePath = $downloadDir . DIRECTORY_SEPARATOR . $entry;

        if (!is_file($filePath) || !is_readable($filePath)) {
            continue;
        }

        $downloadFiles[] = [
            'name' => $entry,
            'size' => filesize($filePath),
            'modified' => filemtime($filePath),
            'url' => 'files/' . rawurlencode($entry),
        ];
    }
}

usort($downloadFiles, function ($a, $b) {
    return strcasecmp($a['name'], $b['name']);
});

function formatFileSize(int $bytes): string
{
    if ($bytes < 1024) {
        return $bytes . ' B';
    }

    $units = ['KB', 'MB', 'GB', 'TB'];
    $value = $bytes / 1024;
    $unitIndex = 0;

    while ($value >= 1024 && $unitIndex < count($units) - 1) {
        $value /= 1024;
        $unitIndex++;
    }

    $precision = $value >= 10 ? 0 : 1;

    return number_format($value, $precision) . ' ' . $units[$unitIndex];
}

function formatModifiedDate(int $timestamp): string
{
    return date('F j, Y', $timestamp);
}
?>
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
    <a class="skip-link" href="#main-content">Skip to main content</a>
    <?php include __DIR__ . '/php/menu.php'; ?>
    <?php include __DIR__ . '/php/theme-toggle.php'; ?>
    <header class="page-hero">
      <p class="hero-eyebrow">Download Center</p>
      <h1>Find the files you need for deployment</h1>
      <p class="hero-summary">
        Browse curated firmware, operating system images, and supporting documents for
        Raspberry Pi installations. Get quick access to the latest packages published
        for field teams or open the full repository to script your own sync jobs.
      </p>
    </header>

    <main id="main-content" class="page-main" tabindex="-1">
      <section class="content-card">
        <h2>Available downloads</h2>
        <p>Direct links to the most recent packages for mobile deployment teams.</p>
        <?php if ($downloadFiles) { ?>
        <ul class="download-list">
          <?php foreach ($downloadFiles as $file) { ?>
          <li>
            <div class="download-file">
              <div class="download-meta">
                <h3><?php echo htmlspecialchars($file['name'], ENT_QUOTES, 'UTF-8'); ?></h3>
                <p class="download-details">
                  Updated <?php echo htmlspecialchars(formatModifiedDate($file['modified']), ENT_QUOTES, 'UTF-8'); ?>
                  · <?php echo htmlspecialchars(formatFileSize($file['size']), ENT_QUOTES, 'UTF-8'); ?>
                </p>
              </div>
              <a class="button primary" href="<?php echo htmlspecialchars($file['url'], ENT_QUOTES, 'UTF-8'); ?>">
                Download
              </a>
            </div>
          </li>
          <?php } ?>
        </ul>
        <?php } else { ?>
        <p class="download-empty">
          No downloads are currently published. Check back soon or contact the team if you
          expected to find a specific build here.
        </p>
        <?php } ?>
      </section>

      <section class="content-card">
        <h2>Browse the repository</h2>
        <p>
          Need to script a sync or look for historical builds? Open the full directory
          listing for the downloads share.
        </p>
        <p class="cta-link"><a href="/files/">Open the /files/ directory</a></p>
      </section>

      <section class="content-card">
        <h2>Need something else?</h2>
        <p>
          Reach out to the operations team if a required image or document is missing so we
          can add it to the catalog.
        </p>
        <p class="cta-link"><a href="index.php">Return to the home page</a></p>
      </section>
    </main>

    <?php include __DIR__ . '/php/footer.php'; ?>
    <script src="js/menu.js"></script>
    <script src="js/theme-toggle.js"></script>
  </body>
</html>
