#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
TASK_SWIFTC_PATH="$(xcrun --find swiftc)"
TASK_TEST_PLUGIN="${TASK_SWIFTC_PATH:h:h}/lib/swift/host/plugins/testing/libTestingMacros.dylib"
TASK_SWIFT_TEST_ARGS=(test --disable-xctest --enable-swift-testing)
# Some CLT releases expose Testing.framework without automatically discovering its macro plugin.
if [[ -f "$TASK_TEST_PLUGIN" ]]; then
    TASK_SWIFT_TEST_ARGS+=(-Xswiftc -load-plugin-library -Xswiftc "$TASK_TEST_PLUGIN")
fi
swift "${TASK_SWIFT_TEST_ARGS[@]}" "$@"
