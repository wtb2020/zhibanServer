#!/bin/sh
# POSIX shell: works with `sh`, including Debian/Raspberry Pi OS dash.
set -eu
ZB_BOOTSTRAP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ZB_PROJECT_ROOT=$(CDPATH= cd -- "$ZB_BOOTSTRAP_DIR/.." && pwd)
ZB_MODE=server
ZB_ACTION=start
ZB_NO_INSTALL=0
ZB_NO_BROWSER=0
ZB_WITH_BROWSER=0
ZB_CHECK_ONLY=0
ZB_PYTHON=

zb_fail() { printf '%s\n' "Startup failed: $*" >&2; exit 1; }
zb_usage() {
    printf '%s\n' 'Bootstrap options: --check-only --no-install --no-browser --with-browser' \
      'Application options follow these flags, for example: sh start.sh --no-install -- --port 8080' \
      'EDU_PYTHON may name an existing Python 3.10+ executable.'
}
while [ "$#" -gt 0 ]; do
    case "$1" in
        --project-root) [ "$#" -ge 2 ] || zb_fail 'Missing project root'; ZB_PROJECT_ROOT=$2; shift 2 ;;
        --mode) [ "$#" -ge 2 ] || zb_fail 'Missing mode'; ZB_MODE=$2; shift 2 ;;
        --action) [ "$#" -ge 2 ] || zb_fail 'Missing action'; ZB_ACTION=$2; shift 2 ;;
        --no-install) ZB_NO_INSTALL=1; shift ;;
        --no-browser) ZB_NO_BROWSER=1; shift ;;
        --with-browser) ZB_WITH_BROWSER=1; shift ;;
        --check-only) ZB_CHECK_ONLY=1; ZB_NO_INSTALL=1; shift ;;
        --bootstrap-help) zb_usage; exit 0 ;;
        --) shift; break ;;
        *) break ;;
    esac
done
case "$ZB_MODE" in server|client|demo) ;; *) zb_fail 'Invalid mode' ;; esac
case "$ZB_ACTION" in start|setup|reset) ;; *) zb_fail 'Invalid action' ;; esac
ZB_PROJECT_ROOT=$(CDPATH= cd -- "$ZB_PROJECT_ROOT" && pwd)
ZB_DOCTOR=$ZB_BOOTSTRAP_DIR/runtime_doctor.py

zb_try_python() {
    [ -n "$1" ] || return 1
    if ZB_RESULT=$("$1" "$ZB_DOCTOR" --print-executable 2>/dev/null); then
        [ -n "$ZB_RESULT" ] || return 1
        ZB_PYTHON=$ZB_RESULT
        return 0
    fi
    return 1
}
zb_find_python() {
    if [ -n "${EDU_PYTHON:-}" ]; then
        zb_try_python "$EDU_PYTHON" || zb_fail 'EDU_PYTHON is set but failed the Python 3.10+/SQLite/SSL check.'
        return 0
    fi
    if [ -e "$ZB_PROJECT_ROOT/.venv" ]; then
        for ZB_LOCAL_PYTHON in "$ZB_PROJECT_ROOT/.venv/bin/python" "$ZB_PROJECT_ROOT/.venv/Scripts/python.exe"; do
            if [ -f "$ZB_LOCAL_PYTHON" ] && zb_try_python "$ZB_LOCAL_PYTHON" && "$ZB_PYTHON" -c 'import sys; sys.exit(0 if sys.prefix != sys.base_prefix else 1)' >/dev/null 2>&1; then return 0; fi
        done
        zb_fail 'The project .venv is incomplete or invalid. Rebuild it on this device; system Python will not silently replace it.'
    fi
    if [ -r "$ZB_PROJECT_ROOT/.runtime/python-path.txt" ]; then
        ZB_CACHED=$(cat "$ZB_PROJECT_ROOT/.runtime/python-path.txt")
        if zb_try_python "$ZB_CACHED"; then return 0; fi
    fi
    for ZB_CANDIDATE in python3 python3.14 python3.13 python3.12 python3.11 python3.10 python; do
        if command -v "$ZB_CANDIDATE" >/dev/null 2>&1 && zb_try_python "$ZB_CANDIDATE"; then return 0; fi
    done
    return 1
}
zb_root() {
    if [ "$(id -u)" -eq 0 ]; then "$@"
    elif command -v sudo >/dev/null 2>&1; then sudo "$@"
    else zb_fail 'Installing OS packages requires root or sudo. Ask the device administrator to install the listed dependency.'
    fi
}
zb_install_python() {
    printf '%s\n' 'Python 3.10+ with SQLite/SSL is missing. Installing through the OS package manager (internet required).'
    if command -v apt-get >/dev/null 2>&1; then
        zb_root apt-get update || zb_fail 'apt metadata update failed; check the network and package sources.'
        zb_root apt-get install -y python3 ca-certificates || zb_fail 'apt Python installation failed.'
    elif command -v dnf >/dev/null 2>&1; then
        zb_root dnf install -y python3 ca-certificates || zb_fail 'dnf Python installation failed.'
    elif command -v brew >/dev/null 2>&1; then
        brew install python || zb_fail 'Homebrew Python installation failed.'
    else
        zb_fail 'No supported package manager (apt-get/dnf/brew). Install Python 3.10+ with SQLite/SSL, or set EDU_PYTHON, then retry.'
    fi
    hash -r 2>/dev/null || true
}
zb_have_browser() {
    for ZB_BROWSER in chromium chromium-browser google-chrome google-chrome-stable microsoft-edge firefox; do
        if command -v "$ZB_BROWSER" >/dev/null 2>&1; then return 0; fi
    done
    return 1
}
zb_install_browser() {
    printf '%s\n' 'Installing a missing browser through the OS package manager.'
    if command -v apt-get >/dev/null 2>&1; then
        zb_root apt-get update || zb_fail 'apt metadata update failed.'
        if ! zb_root apt-get install -y chromium; then
            zb_root apt-get install -y chromium-browser || zb_fail 'Browser installation failed. Install a desktop browser manually, or use --no-browser for a headless device.'
        fi
    elif command -v dnf >/dev/null 2>&1; then
        zb_root dnf install -y chromium || zb_fail 'Browser installation failed.'
    elif command -v brew >/dev/null 2>&1; then
        brew install --cask google-chrome || zb_fail 'Browser installation failed.'
    else zb_fail 'Install a browser manually; this OS has no supported browser package manager.'
    fi
    zb_have_browser || zb_fail 'Browser installer finished, but a browser command was not detected.'
}

if ! zb_find_python; then
    [ "$ZB_NO_INSTALL" -eq 0 ] || zb_fail 'No valid Python 3.10+ runtime. Run setup.sh without --no-install, or set EDU_PYTHON.'
    zb_install_python
    zb_find_python || zb_fail 'Installed Python is still incompatible. Older OS releases may ship Python below 3.10; upgrade the OS or set EDU_PYTHON. The system Python symlink was not changed.'
fi
"$ZB_PYTHON" "$ZB_DOCTOR"

ZB_NEEDS_BROWSER=0
if [ "$ZB_ACTION" != reset ] && [ "$ZB_NO_BROWSER" -eq 0 ]; then
    if [ "$ZB_WITH_BROWSER" -eq 1 ]; then ZB_NEEDS_BROWSER=1
    elif { [ "$ZB_MODE" = client ] || [ "$ZB_MODE" = demo ]; } && { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; }; then ZB_NEEDS_BROWSER=1
    fi
fi
if [ "$ZB_NEEDS_BROWSER" -eq 1 ] && ! zb_have_browser; then
    [ "$ZB_NO_INSTALL" -eq 0 ] || zb_fail 'Browser missing. Run setup.sh --with-browser, or use --no-browser for a headless device.'
    zb_install_browser
fi
if [ "$ZB_CHECK_ONLY" -eq 0 ]; then
    mkdir -p "$ZB_PROJECT_ROOT/.runtime"
    printf '%s' "$ZB_PYTHON" > "$ZB_PROJECT_ROOT/.runtime/python-path.txt"
    "$ZB_PYTHON" "$ZB_DOCTOR" --json > "$ZB_PROJECT_ROOT/.runtime/doctor.json"
fi
if [ "$ZB_MODE" = client ] || [ "$ZB_MODE" = demo ]; then
    printf '%s\n' 'Offline speech needs a local English system voice. Test audio in the classroom; no pip packages are required.'
    if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
        printf '%s\n' 'No graphical desktop detected. The local service can run, but interactive teaching needs a browser on this device.'
    fi
fi
if [ "$ZB_ACTION" = setup ] || [ "$ZB_CHECK_ONLY" -eq 1 ]; then
    [ "$#" -eq 0 ] || zb_fail 'Unexpected application arguments for setup/check-only.'
    printf '%s\n' 'Dependency check completed.'
    exit 0
fi
case "$ZB_ACTION:$ZB_MODE" in
    reset:server) ZB_ENTRY=reset_admin.py ;;
    reset:*) zb_fail 'Only the server supports password reset.' ;;
    start:server) ZB_ENTRY=run.py ;;
    start:client) ZB_ENTRY=client.py ;;
    start:demo) ZB_ENTRY=demo.py ;;
esac
if [ "$ZB_ACTION" = start ] && [ "$ZB_NO_BROWSER" -eq 0 ] && { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; }; then
    set -- --open-browser "$@"
fi
cd -- "$ZB_PROJECT_ROOT"
export PYTHONIOENCODING=utf-8
exec "$ZB_PYTHON" "$ZB_ENTRY" "$@"
