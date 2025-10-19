# mesh network
creating the bat0 mesh for the nodes to connect

# webportal
Raspberry Pi access point and website with all features

## Follow-up tasks

* Replace the `pip3 --break-system-packages` installation of Reticulum with a distribution-friendly alternative (e.g., virtual environment, packaged dependency, or documented prerequisite) to avoid system package conflicts.
* Check all logs for concistency, change most log in to echo in the ap and webserver config.
* Enhance download-page with clean interface (pics of software, menu interface, ...)
* Build in red version of the website for night use.
* Enhance the index.html, menu interface, mesh info, status of the instlled services.

## Reticulum installation

The installation script provisions Reticulum inside an isolated virtual environment located at `/opt/reticulum-venv` and exposes the `rn*` command-line tools via symlinks in `/usr/local/bin`. This avoids modifying system Python packages while keeping the utilities globally accessible.
