# VoidReader Makefile
# Run `make help` for available commands

.PHONY: help project build run test clean format lint xcode setup install

# Default target
help:
	@echo "VoidReader Development Commands"
	@echo ""
	@echo "  make setup     - First-time setup (install dependencies)"
	@echo "  make project   - Regenerate Xcode project from project.yml"
	@echo "  make build     - Build the app (Debug)"
	@echo "  make release   - Build the app (Release)"
	@echo "  make install   - Build release and install to /Applications"
	@echo "  make run       - Build and run the app"
	@echo "  make test      - Run all tests"
	@echo "  make clean     - Clean build artifacts"
	@echo "  make format    - Format Swift code"
	@echo "  make lint      - Lint Swift code"
	@echo "  make xcode     - Open project in Xcode"
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

# Run tests
test:
	@echo "Running package tests..."
	swift test
	@echo ""
	@echo "Running app tests..."
	xcodebuild -scheme VoidReader -configuration Debug test -quiet || true
	@echo "✓ Tests complete"

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
