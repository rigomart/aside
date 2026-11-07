# The system's xcode-select points at the Command Line Tools; builds need full Xcode.
export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

DERIVED := build/DerivedData
APP := $(DERIVED)/Build/Products/Debug/Aside.app
RELEASE_APP := $(DERIVED)/Build/Products/Release/Aside.app
INSTALLED := /Applications/Aside.app
BUNDLE_ID := com.rigomart.aside
# Extra xcodebuild settings; CI uses it to build without a signing certificate.
XCODEBUILD_FLAGS ?=

.PHONY: generate build test check run install stop logs clean

generate:
	xcodegen generate --quiet

build: generate
	xcodebuild -project Aside.xcodeproj -scheme Aside -configuration Debug \
		-destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED) -quiet $(XCODEBUILD_FLAGS) build

test:
	swift test --package-path Packages/AsideCore

check: build test

run: build stop
	open $(APP)

# Builds the Release app, replaces /Applications/Aside.app with it, and opens it. Aside keeps running
# during the build; only the copy step quits it.
install: generate
	xcodebuild -project Aside.xcodeproj -scheme Aside -configuration Release \
		-destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED) -quiet $(XCODEBUILD_FLAGS) build
	@$(MAKE) --no-print-directory stop
	@for i in $$(seq 50); do \
		osascript -e 'application id "$(BUNDLE_ID)" is running' | grep -q true || exit 0; sleep 0.2; \
	done; echo "Aside didn't quit. Close any alert it shows, then run make install again." >&2; exit 1
	rm -rf $(INSTALLED)
	ditto $(RELEASE_APP) $(INSTALLED)
	open $(INSTALLED)
	@echo "Installed $(INSTALLED)"

stop:
	@osascript -e 'if application id "$(BUNDLE_ID)" is running then tell application id "$(BUNDLE_ID)" to quit'

logs:
	log stream --level debug --predicate 'subsystem == "$(BUNDLE_ID)"'

clean:
	rm -rf build Aside.xcodeproj App/Info.plist Packages/AsideCore/.build
