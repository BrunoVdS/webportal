# Mesh network (BAT0)
Creating the bat0 mesh for the nodes to connect.
Node komes online when the node boots/reboots.

# Reticulum installation
The installation script provisions Reticulum inside an isolated virtual environment located at `/opt/reticulum-venv` and exposes the `rn*` command-line tools via symlinks in `/usr/local/bin`. This avoids modifying system Python packages while keeping the utilities globally accessible.
config file is located ~/.reticulum

# Access point (AP on wlan0)
Building access point on erry Pi's wifi(wlan0).

# Webportal
Creating webportal with different functions:
  - Download server (software & manuals)
  - Display mesh staus
  - ...


## Follow-up tasks

* Enhance download-page - more elegant solution to add and change the data. Database driven might be the option.
* Enhance the index.html, status of the installed services.
* Integrate the mesh info page of Natak Mesh.
* Create a QR code on the landings page to give temporary access to the AP. valid for hr. Or have code pressent that can create this code.

## Features
* Use a client-side astronomical algorithm (e.g., the NOAA Solar Calculator or the U.S. Naval Observatory algorithm) that accepts latitude, longitude, date, and timezone. These formulas are well-documented and easy to implement in JavaScript. To gather location data, we are using the android or iOS phone/tablet GSP location. If no loctaion is found, no automation.
* Create a local webadress so users do not have to use the IP to connect to the website.
