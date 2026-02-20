# VoidReader Makefile
# Run `make help` for available commands

.PHONY: help project build run run-debug test test-ui test-ui-debug clean format lint xcode setup install dmg dmg-signed staple

# Default target
help:
	@echo "VoidReader Development Commands"
	@echo ""
	@echo "Build & Run:"
	@echo "  make build        - Build the app (Debug)"
	@echo "  make release      - Build the app (Release)"
	@echo "  make run          - Build and run the app"
	@echo "  make run-debug    - Run with debug telemetry (VOID_READER_DEBUG=1)"
	@echo "  make run-debug-file - Run with debug telemetry + file logging"
	@echo ""
	@echo "Testing:"
	@echo "  make test         - Run unit tests"
	@echo "  make test-ui      - Run UI tests (XCUITest)"
	@echo "  make test-ui-debug - Run UI tests with debug logging"
	@echo ""
	@echo "Project:"
	@echo "  make setup        - First-time setup (install dependencies)"
	@echo "  make project      - Regenerate Xcode project from project.yml"
	@echo "  make xcode        - Open project in Xcode"
	@echo "  make clean        - Clean build artifacts"
	@echo "  make format       - Format Swift code"
	@echo "  make lint         - Lint Swift code"
	@echo ""
	@echo "Distribution:"
	@echo "  make install      - Build release and install to /Applications"
	@echo "  make dmg          - Build release DMG (unsigned)"
	@echo "  make dmg-signed   - Build signed & notarized DMG"
	@echo "  make staple       - Staple notarization ticket to DMG"
	@echo ""

# First-time setup
setup:
	@echo "Checking dependencies..."
	@command -v xcodegen >/dev/null 2>&1 || { echo "Installing xcodegen..."; brew install xcodegen; }
	@command -v swiftlint >/dev/null 2>&1 || { echo "Installing swiftlint..."; brew install swiftlint; }
	@command -v swiftformat >/dev/null 2>&1 || { echo "Installing swiftformat..."; brew install swiftformat; }
	@echo "Generating Xcode project..."
	@$(MAKE) project
	@echo ""
	@echo "✓ Setup complete!"
	@echo ""
	@echo "Next steps:"
	@echo "  1. make xcode"
	@echo "  2. Select your signing team in Xcode"
	@echo "  3. Cmd+R to run"

# Regenerate Xcode project
project:
	@echo "Generating Xcode project..."
	xcodegen generate
	@echo "✓ Project generated"

# Build (Debug)
build:
	@echo "Building (Debug)..."
	xcodebuild -scheme VoidReader -configuration Debug build -quiet
	@echo "✓ Build succeeded"

# Build (Release)
release:
	@echo "Building (Release)..."
	xcodebuild -scheme VoidReader -configuration Release build -quiet
	@echo "✓ Release build succeeded"

# Install to /Applications
install: release
	@echo "Installing to /Applications..."
	@rm -rf /Applications/VoidReader.app
	@cp -R "$$(xcodebuild -scheme VoidReader -configuration Release -showBuildSettings | grep -m 1 'BUILT_PRODUCTS_DIR' | awk '{print $$3}')/VoidReader.app" /Applications/
	@echo "✓ Installed to /Applications/VoidReader.app"

# Build and run
run: build
	@echo "Running VoidReader..."
	@open "$$(xcodebuild -scheme VoidReader -configuration Debug -showBuildSettings | grep -m 1 'BUILT_PRODUCTS_DIR' | awk '{print $$3}')/VoidReader.app"

# Run with debug telemetry enabled
run-debug: build
	@echo "Running VoidReader with debug telemetry..."
	@VOID_READER_DEBUG=1 open "$$(xcodebuild -scheme VoidReader -configuration Debug -showBuildSettings | grep -m 1 'BUILT_PRODUCTS_DIR' | awk '{print $$3}')/VoidReader.app"
	@echo ""
	@echo "View logs in Console.app with filter: subsystem:com.voidreader.debug"

# Run with debug telemetry and file logging
run-debug-file: build
	@echo "Running VoidReader with debug telemetry (file logging)..."
	@VOID_READER_DEBUG=1 VOID_READER_DEBUG_FILE=/tmp/voidreader_debug.log open "$$(xcodebuild -scheme VoidReader -configuration Debug -showBuildSettings | grep -m 1 'BUILT_PRODUCTS_DIR' | awk '{print $$3}')/VoidReader.app"
	@echo ""
	@echo "Logs being written to: /tmp/voidreader_debug.log"
	@echo "Tail with: tail -f /tmp/voidreader_debug.log"

# Run tests (unit tests only)
test:
	@echo "Running package tests..."
	swift test
	@echo ""
	@echo "Running app tests..."
	xcodebuild -scheme VoidReader -configuration Debug test -only-testing:VoidReaderTests -quiet || true
	@echo "✓ Tests complete"

# Run UI tests
test-ui:
	@echo "Running UI tests..."
	xcodebuild -scheme VoidReader -configuration Debug test -only-testing:VoidReaderUITests -quiet || true
	@echo "✓ UI tests complete"

# Run UI tests with debug telemetry and capture output
test-ui-debug:
	@echo "Running UI tests with debug telemetry..."
	@rm -f /tmp/voidreader_uitest_*.log
	xcodebuild -scheme VoidReader -configuration Debug test -only-testing:VoidReaderUITests 2>&1 | tee /tmp/uitest_output.log || true
	@echo ""
	@echo "✓ UI tests complete"
	@echo "Debug logs written to: /tmp/voidreader_uitest_*.log"
	@ls -la /tmp/voidreader_uitest_*.log 2>/dev/null || echo "No debug logs found"

# Clean
clean:
	@echo "Cleaning..."
	rm -rf .build
	rm -rf ~/Library/Developer/Xcode/DerivedData/VoidReader-*
	xcodebuild clean -scheme VoidReader -quiet 2>/dev/null || true
	@echo "✓ Clean complete"

# Format code
format:
	@echo "Formatting Swift code..."
	swiftformat Sources App Tests --swiftversion 5.9
	@echo "✓ Formatting complete"

# Lint code
lint:
	@echo "Linting Swift code..."
	swiftlint Sources App Tests
	@echo "✓ Linting complete"

# Open in Xcode
xcode: project
	@echo "Opening Xcode..."
	open VoidReader.xcodeproj

# Build DMG for distribution (unsigned)
dmg:
	@./scripts/build-dmg.sh

# Build signed & notarized DMG
dmg-signed:
	@./scripts/build-signed-dmg.sh

# Staple notarization ticket to existing DMG (after Apple approves)
staple:
	@echo "Stapling notarization ticket..."
	xcrun stapler staple build/VoidReader.dmg
	@echo "✓ Stapled. DMG ready for distribution."
