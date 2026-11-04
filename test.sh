#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
TEST_WORK=$(mktemp -d)
trap 'python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1])" "$TEST_WORK"' EXIT
# Compile a consistent source snapshot while other work may continue in the checkout.
PROJECT_ROOT="$PWD"
mkdir "$TEST_WORK/project"
cp -R Sources Tests "$TEST_WORK/project/"
ln -s "$PROJECT_ROOT/Resources" "$TEST_WORK/project/Resources"
cd "$TEST_WORK/project"
"${FTP_TEST_PYTHON:-python3}" -c 'import pyftpdlib, OpenSSL' || { printf '%s\n' 'FTP tests require pyftpdlib and pyOpenSSL; set FTP_TEST_PYTHON to that interpreter.' >&2; exit 1; }

xcrun swiftc -swift-version 5 -target arm64-apple-macosx13.0 Sources/FileService.swift Tests/FileServiceTests.swift -o "$TEST_WORK/files"
"$TEST_WORK/files"
xcrun swiftc -swift-version 5 -target arm64-apple-macosx13.0 -framework AppKit Sources/Editor.swift Tests/EditorTests.swift -o "$TEST_WORK/editor"
"$TEST_WORK/editor"
xcrun swiftc -swift-version 5 -Onone -target arm64-apple-macosx13.0 -framework AppKit Sources/*.swift -o "$TEST_WORK/ui"
if [[ -n "${TEST_ARTIFACT_DIR:-}" ]]; then
    mkdir -p "$TEST_ARTIFACT_DIR"
    cp "$TEST_WORK/ui" "$TEST_ARTIFACT_DIR/ui"
    cp -R Resources "$TEST_ARTIFACT_DIR/"
fi
"$TEST_WORK/ui" --smoke-test
xcrun swiftc -swift-version 5 -target arm64-apple-macosx13.0 Sources/Operations.swift Tests/OperationsTests.swift -o "$TEST_WORK/operations"
"$TEST_WORK/operations" "$PWD/Resources/7zz"

xcrun swiftc -swift-version 5 -target arm64-apple-macosx13.0 -framework AppKit -framework ImageIO Sources/Lister.swift Tests/ListerTests.swift -o "$TEST_WORK/lister"
"$TEST_WORK/lister"

xcrun swiftc -swift-version 5 Sources/RenameMasks.swift Tests/RenameMasksTests.swift -o "$TEST_WORK/masks"
"$TEST_WORK/masks"
xcrun swiftc -swift-version 5 -framework AppKit Sources/TransferQueue.swift Tests/TransferQueueTests.swift -o "$TEST_WORK/transfers"
"$TEST_WORK/transfers"
xcrun swiftc -swift-version 5 -framework AppKit Sources/Synchronization.swift Tests/SynchronizationTests.swift -o "$TEST_WORK/sync"
"$TEST_WORK/sync"
xcrun swiftc -swift-version 5 Sources/Operations.swift Sources/Checksums.swift Tests/ChecksumTests.swift -o "$TEST_WORK/checksums"
"$TEST_WORK/checksums"

xcrun swiftc -swift-version 5 -framework AppKit -framework ImageIO Sources/FileService.swift Sources/Operations.swift Sources/Lister.swift Sources/ArchiveBrowser.swift Tests/ArchiveBrowserTests.swift -o "$TEST_WORK/archive-browser"
"$TEST_WORK/archive-browser" "$PWD/Resources/7zz"

xcrun swiftc -swift-version 5 -framework AppKit Sources/FTP.swift Tests/FTPTests.swift -o "$TEST_WORK/ftp"
"$TEST_WORK/ftp" "${FTP_TEST_PYTHON:-python3}"

# Provider backends share the same production sources and bundled archive executable.
PROVIDER_SOURCES=(Sources/FileService.swift Sources/Operations.swift Sources/Lister.swift Sources/ArchiveBrowser.swift Sources/ArchiveMutations.swift Sources/FTP.swift Sources/PaneLocations.swift)
xcrun swiftc -swift-version 5 -framework AppKit -framework ImageIO "${PROVIDER_SOURCES[@]}" Tests/PaneLocationsTests.swift -o "$TEST_WORK/pane-locations"
"$TEST_WORK/pane-locations" "$PWD/Resources/7zz"
xcrun swiftc -swift-version 5 -framework AppKit -framework ImageIO "${PROVIDER_SOURCES[@]}" Tests/ArchiveMutationTests.swift -o "$TEST_WORK/archive-mutations"
"$TEST_WORK/archive-mutations" "$PWD/Resources/7zz"
xcrun swiftc -swift-version 5 -D ARCHIVE_EDIT_BACKEND_TESTS -framework AppKit -framework ImageIO "${PROVIDER_SOURCES[@]}" Sources/ArchiveEditing.swift Tests/ArchiveEditingTests.swift -o "$TEST_WORK/archive-editing"
"$TEST_WORK/archive-editing" "$PWD/Resources/7zz"
xcrun swiftc -swift-version 5 -framework AppKit Sources/FTP.swift Sources/RemoteEditing.swift Tests/RemoteEditingTests.swift -o "$TEST_WORK/remote-editing"
"$TEST_WORK/remote-editing"
xcrun swiftc -swift-version 5 -framework AppKit -framework ImageIO "${PROVIDER_SOURCES[@]}" Sources/ProviderTransfers.swift Tests/ProviderTransfersTests.swift -o "$TEST_WORK/provider-transfers"
"$TEST_WORK/provider-transfers" "$PWD/Resources/7zz" "${FTP_TEST_PYTHON:-python3}"
xcrun swiftc -swift-version 5 -D BRIEF_LAYOUT_TEST -framework AppKit Sources/BriefView.swift Tests/BriefLayoutTests.swift -o "$TEST_WORK/brief"
"$TEST_WORK/brief"
xcrun swiftc -swift-version 5 -D SHORTCUT_CONTRACT_TEST -framework AppKit Sources/KeyboardFeatures.swift Tests/ShortcutContractTests.swift -o "$TEST_WORK/shortcuts"
"$TEST_WORK/shortcuts" "$PWD/Tests/Fixtures/KEYBOARD.TXT"
xcrun swiftc -swift-version 5 -D SHORTCUT_CONTRACT_TEST -framework AppKit Sources/KeyboardFeatures.swift Tests/FileListComparisonTests.swift -o "$TEST_WORK/file-list-comparison"
"$TEST_WORK/file-list-comparison"
xcrun swiftc -swift-version 5 -D REFERENCE_MENU_TESTS Sources/ReferenceMenus.swift Tests/ReferenceMenuTests.swift -o "$TEST_WORK/reference-menus"
"$TEST_WORK/reference-menus" "$PWD/Resources"
xcrun swiftc -swift-version 5 -D ARCHIVE_WRITEBACK_TESTS -D ARCHIVE_EDIT_BACKEND_TESTS -framework AppKit -framework ImageIO "${PROVIDER_SOURCES[@]}" Sources/ArchiveWriteback.swift Sources/ArchiveEditing.swift Sources/ProviderTransfers.swift Tests/ArchiveWritebackTests.swift -o "$TEST_WORK/archive-writeback"
"$TEST_WORK/archive-writeback" "$PWD/Resources/7zz"
xcrun swiftc -swift-version 5 Sources/FileParts.swift Tests/FilePartsTests.swift -o "$TEST_WORK/file-parts"
"$TEST_WORK/file-parts"
xcrun swiftc -swift-version 5 -framework AppKit -framework ImageIO "${PROVIDER_SOURCES[@]}" Tests/ArchiveFormatsTests.swift -o "$TEST_WORK/archive-formats"
"$TEST_WORK/archive-formats" "$PWD/Resources/7zz" "$PWD/Tests/Fixtures"
xcrun swiftc -swift-version 5 -framework AppKit Sources/ConfigurationModel.swift Tests/ConfigurationTests.swift -o "$TEST_WORK/configuration"
xcrun swiftc -swift-version 5 -framework AppKit Sources/ConfigurationModel.swift Tests/ConfigurationFormatterTests.swift -o "$TEST_WORK/configuration-formatters"
"$TEST_WORK/configuration-formatters"
xcrun swiftc -swift-version 5 -framework AppKit Sources/ConfigurationModel.swift Sources/ConfigurationFiles.swift Tests/ConfigurationFilesTests.swift -o "$TEST_WORK/configuration-files"
"$TEST_WORK/configuration-files"
"$TEST_WORK/configuration"
xcrun swiftc -swift-version 5 -framework AppKit Sources/ConfigurationModel.swift Tests/ConfigurationFormatterTests.swift -o "$TEST_WORK/configuration-formatters"
"$TEST_WORK/configuration-formatters"
xcrun swiftc -swift-version 5 -framework AppKit Sources/ConfigurationModel.swift Sources/ConfigurationFiles.swift Tests/ConfigurationFilesTests.swift -o "$TEST_WORK/configuration-files"
"$TEST_WORK/configuration-files"
xcrun swiftc -swift-version 5 -framework AppKit Sources/ConfigurationModel.swift Sources/Preferences.swift Tests/ConfigurationUITests.swift -o "$TEST_WORK/configuration-ui"
"$TEST_WORK/configuration-ui"
xcrun swiftc -swift-version 5 -D THUMBNAIL_TEST -framework AppKit -framework ImageIO Sources/Lister.swift Sources/ThumbnailView.swift Tests/ThumbnailTests.swift -o "$TEST_WORK/thumbnails"
"$TEST_WORK/thumbnails"
xcrun swiftc -swift-version 5 -D QUICK_SEARCH_TEST -framework AppKit Sources/QuickSearch.swift Tests/QuickSearchTests.swift -o "$TEST_WORK/quick-search"
"$TEST_WORK/quick-search"
xcrun swiftc -swift-version 5 -D PANEL_COMMANDS_TEST -framework AppKit Sources/FileService.swift Sources/PanelCommands.swift Tests/PanelCommandsTests.swift -o "$TEST_WORK/panel-commands"
"$TEST_WORK/panel-commands"
# Compile actual pane classes with only the application entry annotation removed in a disposable copy.
python3 -c 'import pathlib,sys; p=pathlib.Path("Sources/Main.swift"); pathlib.Path(sys.argv[1]).write_text(p.read_text().replace("@main struct NativeCommander", "struct NativeCommander"))' "$TEST_WORK/MainWithoutEntry.swift"
PANE_SOURCES=()
for SOURCE_FILE in Sources/*.swift; do
    if [[ "$SOURCE_FILE" != "Sources/Main.swift" ]]; then PANE_SOURCES+=("$SOURCE_FILE"); fi
done
xcrun swiftc -swift-version 5 -framework AppKit -framework ImageIO "${PANE_SOURCES[@]}" "$TEST_WORK/MainWithoutEntry.swift" Tests/PaneViewTests.swift -o "$TEST_WORK/pane-views"
xcrun swiftc -swift-version 5 -framework AppKit -framework ImageIO "${PANE_SOURCES[@]}" "$TEST_WORK/MainWithoutEntry.swift" Tests/PanePerformanceTests.swift -o "$TEST_WORK/pane-performance"
"$TEST_WORK/pane-performance"
"$TEST_WORK/pane-views"
xcrun swiftc -swift-version 5 -framework AppKit -framework ImageIO "${PANE_SOURCES[@]}" "$TEST_WORK/MainWithoutEntry.swift" Tests/PanePerformanceTests.swift -o "$TEST_WORK/pane-performance"
"$TEST_WORK/pane-performance"
"${FTP_TEST_PYTHON:-python3}" Tests/ProviderIntegration.py "$TEST_WORK/ui" "$PWD/Resources/7zz"
printf '%s\n' 'All native backend and provider integration suites passed.'
