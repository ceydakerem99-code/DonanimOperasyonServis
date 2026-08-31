#!/bin/sh
# Manual/CLI helper — keep in sync with the inline preBuildScript in project.yml.
set -eu

GEN_DIR="${SRCROOT}/DonanimOperasyonServis/Resources/Generated"
XCCONFIG_DIR="${SRCROOT}/Config/Generated"

mkdir -p "${GEN_DIR}" "${XCCONFIG_DIR}"

if [ "${CONFIGURATION:-Debug}" != "Debug" ]; then
  exit 0
fi

IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"

if [ -n "${IP}" ]; then
  printf '%s\n' "${IP}" > "${GEN_DIR}/RealtimeGatewayHost.dev"
  {
    echo "// Generated at build time — do not commit"
    echo "REALTIME_GATEWAY_HOST = ${IP}"
  } > "${XCCONFIG_DIR}/RealtimeGatewayHost.xcconfig"
else
  : > "${GEN_DIR}/RealtimeGatewayHost.dev"
  {
    echo "// Generated at build time — do not commit"
    echo "REALTIME_GATEWAY_HOST ="
  } > "${XCCONFIG_DIR}/RealtimeGatewayHost.xcconfig"
fi
