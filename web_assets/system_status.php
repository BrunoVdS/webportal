<?php
$meshChecks = [
    [
        'label' => 'Mesh supervisor (mesh)',
        'type' => 'service',
        'target' => 'mesh',
    ],
    [
        'label' => 'Reticulum daemon (rnsd)',
        'type' => 'service',
        'target' => 'rnsd',
    ],
    [
        'label' => 'Meshtastic daemon',
        'type' => 'service',
        'target' => 'meshtasticd',
    ],
    [
        'label' => 'Reticulum CLI (rns)',
        'type' => 'command',
        'target' => 'rns',
    ],
    [
        'label' => 'Meshtastic CLI',
        'type' => 'command',
        'target' => 'meshtastic',
    ],
];

$lanPortalChecks = [
    [
        'label' => 'Web server (nginx)',
        'type' => 'service',
        'target' => 'nginx',
    ],
    [
        'label' => 'PHP FastCGI (php-fpm)',
        'type' => 'service',
        'target' => 'php-fpm',
    ],
    [
        'label' => 'Database server (mariadb)',
        'type' => 'service',
        'target' => 'mariadb',
    ],
    [
        'label' => 'Flask bridge (flask-app)',
        'type' => 'service',
        'target' => 'flask-app',
    ],
    [
        'label' => 'Firewall (nftables)',
        'type' => 'service',
        'target' => 'nftables',
    ],
];

$toolingChecks = [
    [
        'label' => 'Git client',
        'type' => 'command',
        'target' => 'git',
    ],
    [
        'label' => 'batctl utility',
        'type' => 'command',
        'target' => 'batctl',
    ],
    [
        'label' => 'Python 3',
        'type' => 'command',
        'target' => 'python3',
    ],
];

function commandExists(string $command): bool
{
    $lookup = trim(shell_exec('command -v ' . escapeshellarg($command) . ' 2>/dev/null'));

    return $lookup !== '';
}

function checkService(string $service): ?bool
{
    if (commandExists('systemctl')) {
        $output = [];
        exec('systemctl is-active ' . escapeshellarg($service) . ' 2>/dev/null', $output, $status);

        if ($status === 0) {
            return true;
        }
    }

    if (commandExists('service')) {
        $output = [];
        exec('service ' . escapeshellarg($service) . ' status 2>&1', $output, $status);

        if ($status === 0) {
            return true;
        }

        $text = strtolower(implode("\n", $output));

        return str_contains($text, 'running') || str_contains($text, 'started');
    }

    return commandExists('systemctl') ? false : null;
}

function checkCommand(string $command): bool
{
    return commandExists($command);
}

function getCheckStatus(array $check): array
{
    if ($check['type'] === 'service') {
        $isRunning = checkService($check['target']);

        if ($isRunning === null) {
            return [
                'state' => 'unknown',
                'message' => 'Status unavailable',
            ];
        }

        return [
            'state' => $isRunning ? 'online' : 'offline',
            'message' => $isRunning ? 'Running' : 'Not running',
        ];
    }

    $isAvailable = checkCommand($check['target']);

    return [
        'state' => $isAvailable ? 'online' : 'offline',
        'message' => $isAvailable ? 'Available' : 'Not available',
    ];
}

function renderStatusList(array $checks): void
{
    foreach ($checks as $check) {
        $status = getCheckStatus($check);
        $stateClass = htmlspecialchars($status['state'], ENT_QUOTES);
        $label = htmlspecialchars($check['label'], ENT_QUOTES);
        $message = htmlspecialchars($status['message'], ENT_QUOTES);

        echo <<<HTML
          <li class="status-item">
            <div class="status-item__primary">
              <span class="status-indicator status-indicator--{$stateClass}" aria-hidden="true"></span>
              <span class="status-item__label">{$label}</span>
            </div>
            <span class="status-item__state">
              {$message}
              <span class="sr-only">for {$label}</span>
            </span>
          </li>
HTML;
    }
}
?>
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta
      name="description"
      content="Check the health of mesh tooling and LAN portal services."
    >
    <title>System status - Node LAN portal</title>
    <link rel="stylesheet" href="styles.css">
  </head>
  <body>
    <?php include __DIR__ . '/php/menu.php'; ?>
    <?php include __DIR__ . '/php/theme-toggle.php'; ?>
    <main id="main-content" class="page-main" tabindex="-1">
      <header class="page-hero">
        <h1>System status</h1>
        <p class="hero-summary">
          Verify the services, daemons, and tooling that keep the mesh network and LAN portal online.
        </p>
        <div class="hero-actions">
          <a class="button" href="index.php">Back to homepage</a>
          <a class="button" href="downloads.php">Download resources</a>
        </div>
      </header>

      <section class="content-card status-card status-card--standalone" aria-labelledby="status-overview-heading">
        <h2 id="status-overview-heading">Live service overview</h2>
        <p class="status-summary">
          Below is a grouped view of mesh networking components, portal dependencies, and supporting utilities currently detected on this node.
        </p>
        <div class="status-groups">
          <section class="status-group" aria-labelledby="mesh-status-heading">
            <div class="status-group__header">
              <h3 id="mesh-status-heading">Mesh stack</h3>
              <p>Core services and tooling deployed via <code>install_mesh.sh</code>.</p>
            </div>
            <ul class="status-list">
<?php renderStatusList($meshChecks); ?>
            </ul>
          </section>

          <section class="status-group" aria-labelledby="lan-portal-heading">
            <div class="status-group__header">
              <h3 id="lan-portal-heading">LAN portal</h3>
              <p>Services required to keep the local web portal responsive.</p>
            </div>
            <ul class="status-list">
<?php renderStatusList($lanPortalChecks); ?>
            </ul>
          </section>

          <section class="status-group" aria-labelledby="tooling-heading">
            <div class="status-group__header">
              <h3 id="tooling-heading">Supporting tools</h3>
              <p>Utility binaries used for maintenance and diagnostics.</p>
            </div>
            <ul class="status-list">
<?php renderStatusList($toolingChecks); ?>
            </ul>
          </section>
        </div>
      </section>
    </main>

    <?php include __DIR__ . '/php/footer.php'; ?>
    <script src="js/menu.js"></script>
    <script src="js/theme-toggle.js"></script>
  </body>
</html>
