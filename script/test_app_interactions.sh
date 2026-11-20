#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source script/build_paths.sh
work_dir="$(mktemp -d "$HOSTSHELF_TOOL_CACHE/app-interactions.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
mkdir -p .tmp/app-interaction-check
xcrun swiftc -swift-version 5 -module-cache-path "$work_dir/module-cache" \
    -emit-module -emit-library -module-name HostShelfCore Sources/HostShelfCore/*.swift \
    -emit-module-path "$work_dir/HostShelfCore.swiftmodule" -o "$work_dir/libHostShelfCore.dylib"
compile_only() {
    local output="$1"
    shift
    xcrun swiftc -swift-version 5 -D DEBUG -module-cache-path "$work_dir/module-cache" \
        -parse-as-library -I "$work_dir" -L "$work_dir" -lHostShelfCore \
        -Xlinker -rpath -Xlinker "$work_dir" "$@" -o "$work_dir/$output"
}
compile_check() {
    local output="$1"
    shift
    compile_only "$output" "$@"
    "$work_dir/$output"
}
{
    compile_check store-check \
        Sources/HostShelf/Services/TerminalLauncher.swift Sources/HostShelf/Stores/AppStore.swift \
        Tests/ServiceChecks/AppStoreInteractionCheck.swift
    compile_check ui-check \
        Sources/HostShelf/Views/SearchHighlight.swift Sources/HostShelf/Views/HostSearchField.swift \
        Tests/ServiceChecks/InteractionUICheck.swift
    # Keep this check in the production file's lexical scope so it can host the private list.
    cat Sources/HostShelf/Views/ContentView.swift Tests/ServiceChecks/HostListSelectionCheck.swift \
        > "$work_dir/HostListSelectionCheck.swift"
    compile_check host-selection-check \
        Sources/HostShelf/Services/TerminalLauncher.swift Sources/HostShelf/Stores/AppStore.swift \
        Sources/HostShelf/Views/{SidebarView,HostDetailView,HostMetadataSection,HostSourceSections,DiagnosticsView,RefreshConfigurationButton,SearchHighlight,HostSearchField}.swift \
        "$work_dir/HostListSelectionCheck.swift"
    compile_only large-list-layout-check \
        Sources/HostShelf/Services/TerminalLauncher.swift Sources/HostShelf/Stores/AppStore.swift \
        Sources/HostShelf/Views/{ContentView,SidebarView,HostDetailView,HostMetadataSection,HostSourceSections,DiagnosticsView,RefreshConfigurationButton,SearchHighlight,HostSearchField}.swift \
        Tests/ServiceChecks/LargeListLayoutCheck.swift Tests/ServiceChecks/InFlightExcerptGate.swift
    python3 -c 'import subprocess, sys; subprocess.run(sys.argv[1:], timeout=30, check=True)' \
        "$work_dir/large-list-layout-check"
} 2>&1 | tee .tmp/app-interaction-check/check.log
