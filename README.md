# mesh network
creating the bat0 mesh for the nodes to connect

# Reticulum installation
The installation script provisions Reticulum inside an isolated virtual environment located at `/opt/reticulum-venv` and exposes the `rn*` command-line tools via symlinks in `/usr/local/bin`. This avoids modifying system Python packages while keeping the utilities globally accessible.

# webportal
Raspberry Pi access point and website with all features


## Follow-up tasks

* Enhance download-page with clean interface (pics of software, menu interface, ...)
* Build in red version of the website for night use.
* Enhance the index.html, menu interface, mesh info, status of the instlled services.
* Create a QR code on the landings page to give temporary access to the AP. valid for hr. Or have code pressent that can create this code.

## Features
* Use a client-side astronomical algorithm (e.g., the NOAA Solar Calculator or the U.S. Naval Observatory algorithm) that accepts latitude, longitude, date, and timezone. These formulas are well-documented and easy to implement in JavaScript. To gather location data without the internet, allow the user to input latitude/longitude manually, or use offline GPS hardware (e.g., via serial/USB) if available.
