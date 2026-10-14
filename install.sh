#!/bin/sh
# Install the watcher as a systemd user service. Does not build hyperiond (see README).
set -e
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"
install -m 755 "$here/bin/hyper-darkwatch" "$HOME/.local/bin/hyper-darkwatch"
install -m 644 "$here/systemd/hyper-darkwatch.service" "$HOME/.config/systemd/user/hyper-darkwatch.service"
systemctl --user daemon-reload
systemctl --user enable --now hyper-darkwatch.service
echo "installed; check with: systemctl --user status hyper-darkwatch"
