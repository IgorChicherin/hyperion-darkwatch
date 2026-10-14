#!/bin/sh
systemctl --user disable --now hyper-darkwatch.service 2>/dev/null || true
rm -f "$HOME/.local/bin/hyper-darkwatch" "$HOME/.config/systemd/user/hyper-darkwatch.service"
systemctl --user daemon-reload
