# The system's xcode-select points at the Command Line Tools; builds need full Xcode.
export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

DERIVED := build/DerivedData
APP := $(DERIVED)/Build/Products/Debug/Aside.app
BUNDLE_ID := com.rigomart.aside
# Extra xcodebuild settings; CI uses it to build without a signing certificate.
XCODEBUILD_FLAGS ?=

.PHONY: generate build test check run stop logs clean

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

stop:
	@osascript -e 'if application id "$(BUNDLE_ID)" is running then tell application id "$(BUNDLE_ID)" to quit'

logs:
	log stream --level debug --predicate 'subsystem == "$(BUNDLE_ID)"'

clean:
	rm -rf build Aside.xcodeproj App/Info.plist Packages/AsideCore/.build
