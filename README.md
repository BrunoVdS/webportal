# mesh network
creating the bat0 mesh for the nodes to connect

# webportal
Raspberry Pi access point and website with all features

## Follow-up tasks

* Define or source the helper shell functions (`ask`, `ask_hidden`, `confirm`, `die`) used in `install_mesh.sh` so the installer can run without terminating immediately.
* Align logging to the intended destination by either changing the `mesh_log` path to `/var/log/mesh-install.log` or updating the log messages to match the actual file being written.
* Replace the `pip3 --break-system-packages` installation of Reticulum with a distribution-friendly alternative (e.g., virtual environment, packaged dependency, or documented prerequisite) to avoid system package conflicts.
* Provide a faster, deterministic method for locating the `rnsd` binary instead of recursively searching the entire filesystem with `find /`.
* Harden the default Reticulum configuration by disabling or restricting the TCP server interface so the service is not exposed on unintended networks by default.
* Check all logs for concistency, change most log in to echo in the ap and webserver config.