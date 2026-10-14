# hyperion-darkwatch

Starts [Hyperion](https://github.com/hyperion-project/hyperion.ng) (`hyperiond`, ambient lighting daemon)
when the KDE Plasma color scheme turns dark, and stops it when the scheme turns light.
Pair it with Plasma's automatic day/night theme switching and Hyperion runs from sunset on.

This repo holds the watcher service and the steps to build `hyperiond` from source on Arch Linux.
It does not contain Hyperion itself.

## How it works

`bin/hyper-darkwatch` reads `ColorScheme` from `~/.config/kdeglobals` once per second.

- Name contains "dark" (for example `BreezeDark`): start `hyperiond` if it is not running.
- Anything else: `pkill -x hyperiond`.

`systemd/hyper-darkwatch.service` runs the script as a user service, enabled at login.

Sunset itself is not detected by this project. Let Plasma switch the theme:
System Settings, Appearance, Day/Night cycle (Plasma 6.5 or later), switch at sunset.

> **Do not rename the script to start with `hyperiond`.** Hyperion's single-instance check
> treats any process whose name starts with `hyperiond` as a running copy and aborts with
> "The Hyperion Daemon is already running". That is why the script is called `hyper-darkwatch`.

## Requirements

- KDE Plasma 6 (uses the `ColorScheme` key of `kdeglobals`)
- systemd user session
- `hyperiond` reachable at `~/.local/bin/hyperiond` (edit `bin/hyper-darkwatch` for another path)

## Install

```sh
./install.sh
systemctl --user status hyper-darkwatch
```

Remove with `./uninstall.sh`.

Test: `plasma-apply-colorscheme BreezeDark`, wait two seconds, run `pgrep -x hyperiond`.
Then `plasma-apply-colorscheme BreezeLight` and it should be gone.

The watcher kills `hyperiond` whenever the scheme is not dark, including copies you start by hand.

## Build hyperiond from source (Arch Linux)

These steps match the build options of the installation this repo was made on
(Release, Ninja, Qt 6, system packages for Qt and libraries, bundled third-party code).
The package list was taken from the working build; a clean rebuild from scratch has not been re-run.

### 1. Dependencies

```sh
sudo pacman -S --needed base-devel git cmake ninja pkgconf python \
  qt6-base qt6-serialport qt6-5compat \
  libusb hidapi libcec alsa-lib avahi openssl zlib \
  libdrm libx11 libxcb libxrandr libxrender xcb-util-image
```

### 2. Get the source

```sh
git clone --recurse-submodules https://github.com/hyperion-project/hyperion.ng.git ~/Projects/hyperion
cd ~/Projects/hyperion
```

### 3. Configure

```sh
cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_DEPLOY_DEPENDENCIES=ON \
  -DENABLE_V4L2=ON -DENABLE_DRM=ON -DENABLE_X11=ON -DENABLE_XCB=ON -DENABLE_QT=ON \
  -DENABLE_AUDIO=ON -DENABLE_CEC=ON -DENABLE_MDNS=ON \
  -DENABLE_TESTING=OFF \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DCMAKE_EXE_LINKER_FLAGS="-pie" -DCMAKE_CXX_FLAGS="-fPIE"
```

The last two lines build a position-independent executable (PIE). Without them the link can
fail with Qt 6.12, see [Troubleshooting](#troubleshooting).

Other options (device drivers, servers, effect engine) were left at their defaults.
`cmake -LH build` lists them.

### 4. Compile

```sh
cmake --build build -j"$(nproc)"
```

Never run the build with `sudo`. It leaves root-owned files in `build/`.
If the compiler crashes, rerun with fewer jobs (`-j6 -k 0`), see [Troubleshooting](#troubleshooting).

### 5. Install to your home directory

```sh
cmake --install build --prefix "$HOME/.local/share/hyperion"
mkdir -p ~/.local/bin
ln -sf ../share/hyperion/bin/hyperiond ~/.local/bin/hyperiond
ln -sf ../share/hyperion/bin/hyperion-remote ~/.local/bin/hyperion-remote
printf '[Paths]\nPlugins=../share/hyperion/lib/\n' > ~/.local/bin/qt.conf
```

The `qt.conf` is needed because Qt looks for it next to the path you launch, not next to the
file the symlink points to. Without it `hyperiond` aborts, see [Troubleshooting](#troubleshooting).

Make sure `~/.local/bin` is in `PATH`. Check with `hyperiond --version`.

### 6. First run

Start `hyperiond` and open <http://localhost:8090> to configure LEDs and capture.
Settings live in `~/.hyperion`.

## Troubleshooting

### `Error writing to build log: Permission denied` (ninja)

Some files in `build/` are owned by root, because an earlier build or install ran with `sudo`.

```sh
sudo chown -R "$USER:$USER" build
```

Do not use `sudo cmake --build ... --target install/strip`. Build as your user, then run
`cmake --install` on its own (it does not rebuild), with `sudo` only if you install system-wide.

### `internal compiler error: Segmentation fault` in `cc1plus`

Seen with GCC 16.2.1 on different files each time, in trivial code. Rerunning fixes it:

```sh
ninja -C build -j6 -k 0
```

`-k 0` keeps going past failures, so one rerun finishes the rest. If the crashes keep coming,
test the RAM (`memtester`, `memtest86+`). If the same file always crashes, try `CXX=clang++`
or `-O2` for that dependency.

### Link error: `copy relocation against non-copyable protected symbol 'qt_resourceFeatureZstd'`

The executable was linked as non-PIE and Qt 6.12 does not allow a copy relocation for that symbol.
Reconfigure with the PIE flags from step 3 and rebuild. Check with
`file build/bin/hyperiond`: it must say `shared object`, not `executable`.

### `Could not find the Qt platform plugin "xcb"` / `SIGABRT` at start

Qt cannot find the bundled plugins (`share/hyperion/lib/platforms/libqxcb.so`).

- Launching through the `~/.local/bin/hyperiond` symlink needs the `qt.conf` from step 5.
- Another `hyperiond` earlier in `PATH` may be running instead, for example a stale copy in
  `/usr/local/bin`. Check with `type -a hyperiond` and remove the old one
  (`sudo rm -rf /usr/local/share/hyperion /usr/local/bin/hyperiond`).
- Test by hand: `QT_QPA_PLATFORM_PLUGIN_PATH=$HOME/.local/share/hyperion/lib/platforms hyperiond`

### LED device: `Permission denied` / `Failed to open device`

Serial LED controllers (CH340, for example Skydimo) show up as `/dev/ttyUSB0`, owned by
group `uucp` on Arch. Do not run `hyperiond` as root. Add your user to the group:

```sh
sudo usermod -aG uucp "$USER"
```

Group changes apply only to new login sessions. A plain logout is sometimes not enough,
because the terminal inherits its groups from `systemd --user`. Reboot, then check
`id -nG | grep uucp`. Re-enable the device in the web UI afterwards, Hyperion keeps it
disabled after an error. A one-off test without relogging: `sudo -u "$USER" -g uucp hyperiond`.

If it still fails, check `ls -l /dev/ttyUSB0` and `fuser -v /dev/ttyUSB0` (another program may hold the port).

### `GRABBER-X11: Grabber does not work under Wayland!`

You run a Wayland session (`echo $WAYLAND_DISPLAY` is set). Pick another capture type in the
web UI, Capturing Hardware, Platform Capture: the Qt grabber, or the DRM grabber
(needs access to `/dev/dri/card*`, usually group `video` or `render`).
