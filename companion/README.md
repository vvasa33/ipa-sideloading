# Ubuntu stats companion

Small HTTP service the iPad polls for CPU, memory, temperature, disk, and network rates. The iPad and this computer need to be on the same network.

## Install

From this `companion` directory:

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python server.py
```

The process prints a URL like `http://192.168.1.20:8765/stats`. Put that address and port `8765` in the iPad app (long-press the clock).

If the repo is not at `~/ipa-sideloading`, edit `WorkingDirectory` and `ExecStart` in `ipadcc-stats.service` before installing it.

CPU temperature comes from lm-sensors. If the iPad shows `n/a`, install the package and detect sensors:

```bash
sudo apt install lm-sensors
sudo sensors-detect
```

Intel machines usually expose `coretemp`.

## Run at login

```bash
mkdir -p ~/.config/systemd/user
cp ipadcc-stats.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now ipadcc-stats
loginctl enable-linger "$USER"
```

`enable-linger` keeps the service up after you log out.

## Firewall

```bash
sudo ufw allow 8765/tcp
```

Check it from another machine with `curl http://<this-computer>:8765/stats`.
