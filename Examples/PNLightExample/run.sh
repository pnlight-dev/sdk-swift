#!/usr/bin/env bash
set -euo pipefail

# Build, install and launch the example app on an iOS Simulator without Xcode.
#
# Useful when Xcode's Run action hangs (package resolution, "Waiting to attach",
# a wedged CoreSimulator): this drives xcodebuild + simctl directly, so a
# successful run here proves the project and the SDK binary are fine and the
# problem is Xcode's own pipeline.
#
# Usage: ./run.sh [options]
#   -d, --device <name|udid>  Simulator to use (default: newest available iPhone)
#   -g, --generate            Run `xcodegen generate` before building
#   -c, --clean               Wipe DerivedData first (forces package re-resolution)
#   -l, --local               Talk to a local backend, using local.env next to this
#                             script: PNLIGHT_API_KEY=<project token> and optionally
#                             PNLIGHT_BASE_DOMAIN (default http://localhost:3000)
#   -p, --placement <id>      Remote UI placement for the paywall and the test bench
#       --locale <code>       Launch in this language, e.g. fr: the locale Remote UI gets
#   -b, --bench               Open the Remote UI test bench on launch
#       --no-console          Launch detached instead of streaming the app's stdout
#   -h, --help                Show this help

EXAMPLE_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$EXAMPLE_DIR/../../../.." && pwd)"
DERIVED_DATA="$ROOT_DIR/Build/SPMExampleDerivedData"
PROJECT="$EXAMPLE_DIR/PNLightExample.xcodeproj"
SCHEME="PNLightExample"

DEVICE=""
GENERATE=0
CLEAN=0
CONSOLE=1
LOCAL=0
LOCALE=""
PLACEMENT=""
BENCH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--device)   DEVICE="${2:-}"; shift 2 ;;
    -g|--generate) GENERATE=1; shift ;;
    -c|--clean)    CLEAN=1; shift ;;
    -l|--local)    LOCAL=1; shift ;;
    -p|--placement) PLACEMENT="${2:-}"; shift 2 ;;
    --locale)      LOCALE="${2:-}"; shift 2 ;;
    -b|--bench)    BENCH=1; shift ;;
    --no-console)  CONSOLE=0; shift ;;
    -h|--help)     sed -n '4,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 1 ;;
  esac
done

# The API key lives in a gitignored file, so a fresh clone has no config at all.
if [[ ! -f "$EXAMPLE_DIR/PNLightExample/PNLightConfig.swift" ]]; then
  echo "==> Creating PNLightConfig.swift from the template"
  cp "$EXAMPLE_DIR/PNLightExample/PNLightConfig.example.swift" \
     "$EXAMPLE_DIR/PNLightExample/PNLightConfig.swift"
  echo "    Fill in your API key in PNLightExample/PNLightConfig.swift"
fi

# Launch arguments land in the app's UserDefaults argument domain, so they
# override saved settings for this launch only and never touch PNLightConfig.swift.
LAUNCH_ARGS=()
if [[ $LOCAL -eq 1 ]]; then
  LOCAL_ENV="$EXAMPLE_DIR/local.env"
  [[ -f "$LOCAL_ENV" ]] || {
    echo "--local needs $LOCAL_ENV with PNLIGHT_API_KEY=<project token>" >&2; exit 1; }
  # shellcheck disable=SC1090
  source "$LOCAL_ENV"
  [[ -n "${PNLIGHT_API_KEY:-}" ]] || { echo "PNLIGHT_API_KEY is empty in $LOCAL_ENV" >&2; exit 1; }
  LAUNCH_ARGS+=(-PNLightBaseDomain "${PNLIGHT_BASE_DOMAIN:-http://localhost:3000}" -PNLightAPIKey "$PNLIGHT_API_KEY")
fi
if [[ -n "$PLACEMENT" ]]; then
  LAUNCH_ARGS+=(-PNLightPlacement "$PLACEMENT")
fi
if [[ -n "$LOCALE" ]]; then
  # The SDK sends Locale.current.languageCode, which follows both of these.
  LAUNCH_ARGS+=(-AppleLanguages "($LOCALE)" -AppleLocale "$LOCALE")
fi
if [[ $BENCH -eq 1 ]]; then
  LAUNCH_ARGS+=(-PNLightOpenBench YES)
fi

if [[ $GENERATE -eq 1 || ! -d "$PROJECT" ]]; then
  command -v xcodegen >/dev/null 2>&1 || {
    echo "xcodegen is required. Install via 'brew install xcodegen'" >&2; exit 1; }
  echo "==> xcodegen generate"
  (cd "$EXAMPLE_DIR" && xcodegen generate)
fi

if [[ $CLEAN -eq 1 ]]; then
  echo "==> Removing $DERIVED_DATA"
  rm -rf "$DERIVED_DATA"
fi

# Resolve the simulator to a UDID: simctl needs one, and pinning the destination
# by id keeps the build and the install/launch on the same device.
echo "==> Selecting simulator${DEVICE:+ ($DEVICE)}"
SELECTED="$(xcrun simctl list devices available --json | DEVICE="$DEVICE" python3 -c '
import json, os, re, sys

want = os.environ["DEVICE"]
devices = []
for runtime, entries in json.load(sys.stdin)["devices"].items():
    version = [int(n) for n in re.findall(r"\d+", runtime.rsplit(".", 1)[-1])]
    for dev in entries:
        if dev.get("isAvailable"):
            devices.append(dict(dev, runtime=runtime, version=version))

if want:
    matches = [d for d in devices if want in (d["udid"], d["name"])]
else:
    # Newest runtime first, and prefer an already-booted device on it.
    matches = sorted(
        (d for d in devices if d["name"].startswith("iPhone")),
        key=lambda d: (d["version"], d["state"] == "Booted"),
        reverse=True,
    )

if not matches:
    sys.exit(f"No available simulator matching {want!r}")

chosen = next((d for d in matches if d["state"] == "Booted"), matches[0])
print("|".join([chosen["udid"], chosen["name"], chosen["runtime"].rsplit(".", 1)[-1]]))
')"

IFS='|' read -r UDID DEVICE_NAME RUNTIME <<<"$SELECTED"
echo "    $DEVICE_NAME ($RUNTIME) $UDID"

echo "==> Booting simulator"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" >/dev/null 2>&1 || true
open -a Simulator --args -CurrentDeviceUDID "$UDID" || true

echo "==> Building"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "id=$UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  build

# Read the product location and bundle id back out of the build settings rather
# than hardcoding them, so renames in project.yml don't silently break the run.
SETTINGS="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
  -destination "id=$UDID" -derivedDataPath "$DERIVED_DATA" -showBuildSettings 2>/dev/null)"
APP_PATH="$(awk -F' = ' '/ TARGET_BUILD_DIR = /{d=$2} / FULL_PRODUCT_NAME = /{n=$2} END{print d"/"n}' <<<"$SETTINGS")"
BUNDLE_ID="$(awk -F' = ' '/ PRODUCT_BUNDLE_IDENTIFIER = /{print $2; exit}' <<<"$SETTINGS")"

echo "==> Installing $BUNDLE_ID"
xcrun simctl install "$UDID" "$APP_PATH"

echo "==> Launching"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
if [[ $CONSOLE -eq 1 ]]; then
  echo "    Streaming app output — Ctrl-C to stop (the app keeps running)"
  xcrun simctl launch --console-pty "$UDID" "$BUNDLE_ID" ${LAUNCH_ARGS[@]+"${LAUNCH_ARGS[@]}"}
else
  xcrun simctl launch "$UDID" "$BUNDLE_ID" ${LAUNCH_ARGS[@]+"${LAUNCH_ARGS[@]}"}
fi
