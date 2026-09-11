SHELL := /bin/bash
PROJECT := DockNet.xcodeproj
SCHEME := DockNet
CONFIGURATION := Debug
DESTINATION := platform=macOS
BUILD_DIR := $(CURDIR)/build
DERIVED_DATA := $(BUILD_DIR)/DerivedData
APP_BUNDLE := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/DockNet.app
INSTALL_DIR := $(HOME)/Applications
INSTALLED_APP := $(INSTALL_DIR)/DockNet.app

# Optional xcbeautify formatter
BEAUTIFY := $(shell command -v xcbeautify 2> /dev/null)

.PHONY: all build release-build test test-unit test-ui test-ui-live test-notification test-all clean install run diagnose watch live-status regenerate-project help

all: build

help:
	@echo "DockNet Build Targets:"
	@echo "  make build               - Build DockNet Debug configuration with xcodebuild"
	@echo "  make release-build       - Build universal Release app, DMG, and checksum"
	@echo "  make test                - Run unit tests with xcodebuild (same as test-unit)"
	@echo "  make test-unit           - Run pure unit tests (NetworkStateMachineTests)"
	@echo "  make test-ui             - Run deterministic XCUITest suite (DockNetUITests)"
	@echo "  make test-ui-live        - Run observational live network smoke test (DockNetLiveUITests)"
	@echo "  make test-notification   - Trigger a manual test notification using installed app"
	@echo "  make test-all            - Run both unit and deterministic UI test suites"
	@echo "  make clean               - Clean local build artifacts and DerivedData"
	@echo "  make install             - Install DockNet.app to ~/Applications/"
	@echo "  make run                 - Install and launch DockNet.app"
	@echo "  make watch               - Stream live state transitions from running DockNet"
	@echo "  make diagnose            - Run comprehensive read-only network diagnostics"
	@echo "  make regenerate-project  - Regenerate DockNet.xcodeproj using xcodegen"

build:
	@echo "Building DockNet ($(CONFIGURATION))..."
	@mkdir -p $(BUILD_DIR)
	@set -o pipefail; xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIGURATION) \
		-destination '$(DESTINATION)' \
		-derivedDataPath $(DERIVED_DATA) \
		build $(if $(BEAUTIFY),| xcbeautify)

release-build:
	@chmod +x scripts/build-release.sh
	@./scripts/build-release.sh $(VERSION) $(BUILD_NUMBER)

test: test-unit

test-unit:
	@echo "Running DockNet unit tests..."
	@mkdir -p $(BUILD_DIR)
	@set -o pipefail; xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIGURATION) \
		-destination '$(DESTINATION)' \
		-derivedDataPath $(DERIVED_DATA) \
		-only-testing:DockNetTests \
		test $(if $(BEAUTIFY),| xcbeautify)

test-ui:
	@echo "Running DockNet deterministic UI automation tests (XCUITest)..."
	@mkdir -p $(BUILD_DIR)
	@set -o pipefail; xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIGURATION) \
		-destination '$(DESTINATION)' \
		-derivedDataPath $(DERIVED_DATA) \
		-only-testing:DockNetUITests/DockNetUITests \
		test $(if $(BEAUTIFY),| xcbeautify)
	@$(MAKE) export-screenshots

test-ui-live:
	@echo "Running DockNet live hardware observational smoke test..."
	@mkdir -p $(BUILD_DIR)
	@set -o pipefail; xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIGURATION) \
		-destination '$(DESTINATION)' \
		-derivedDataPath $(DERIVED_DATA) \
		-only-testing:DockNetUITests/DockNetLiveUITests \
		test $(if $(BEAUTIFY),| xcbeautify)
	@$(MAKE) export-screenshots

test-notification: install
	@echo "Running DockNet manual test notification..."
	@"$(INSTALLED_APP)/Contents/MacOS/DockNet" --test-notification

test-all:
	@echo "Running all DockNet tests (unit + UI)..."
	@mkdir -p $(BUILD_DIR)
	@set -o pipefail; xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIGURATION) \
		-destination '$(DESTINATION)' \
		-derivedDataPath $(DERIVED_DATA) \
		test $(if $(BEAUTIFY),| xcbeautify)
	@$(MAKE) export-screenshots

export-screenshots:
	@mkdir -p $(BUILD_DIR)/screenshots
	@LATEST_RESULT=$$(find $(DERIVED_DATA)/Logs/Test -name "*.xcresult" 2>/dev/null | tail -n 1); \
	if [ -n "$$LATEST_RESULT" ]; then \
		xcrun xcresulttool export attachments --path "$$LATEST_RESULT" --output-path $(BUILD_DIR)/screenshots >/dev/null 2>&1 || true; \
		if [ -f "$(BUILD_DIR)/screenshots/manifest.json" ]; then \
			python3 -c 'import json, shutil, os; \
			data = json.load(open("$(BUILD_DIR)/screenshots/manifest.json")); \
			[shutil.copyfile(os.path.join("$(BUILD_DIR)/screenshots", a["exportedFileName"]), os.path.join("$(BUILD_DIR)/screenshots", (a["suggestedHumanReadableName"].split("_0_")[0] if "_0_" in a["suggestedHumanReadableName"] else a["suggestedHumanReadableName"].replace(".png", "")) + ".png")) for e in data for a in e.get("attachments", []) if os.path.exists(os.path.join("$(BUILD_DIR)/screenshots", a["exportedFileName"]))];' 2>/dev/null || true; \
		fi; \
		echo "Screenshots preserved in $(BUILD_DIR)/screenshots/"; \
	fi

clean:
	@echo "Cleaning local build artifacts..."
	@rm -rf $(BUILD_DIR)
	@rm -rf /tmp/docknet_screenshots
	@echo "Clean completed."

install: build
	@echo "Installing DockNet to $(INSTALL_DIR)..."
	@mkdir -p $(INSTALL_DIR)
	@if [ -d "$(INSTALLED_APP)" ]; then \
		echo "Removing previous installation..."; \
		rm -rf "$(INSTALLED_APP)"; \
	fi
	@cp -R "$(APP_BUNDLE)" "$(INSTALL_DIR)/"
	@echo "DockNet installed successfully at $(INSTALLED_APP)"

run: install
	@echo "Launching DockNet..."
	@open "$(INSTALLED_APP)"

watch: live-status

live-status:
	@echo "Watching DockNet live state transitions (Ctrl+C to stop)..."
	@/usr/bin/log stream --predicate 'subsystem == "com.andrewtryder.DockNet"' --style compact

diagnose:
	@chmod +x scripts/diagnose.sh
	@./scripts/diagnose.sh

regenerate-project:
	@which xcodegen > /dev/null || (echo "xcodegen not found. Install via: brew install xcodegen" && exit 1)
	@xcodegen generate
	@echo "Regenerated $(PROJECT)"
