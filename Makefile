# Photo River: build the macOS app with the Command Line Tools alone (no Xcode).
#   make app      build build/PhotoRiver.app
#   make run      build and open it on your Photos library
#   make sample   build and open it on the synthetic sample library
#   make icon     redraw mac/AppIcon.icns from mac/icon/make-icon.swift
#   make test     run the Swift tests (mac/Tests) and the exporter's Python tests (tests/)
#   make clean    remove build output

APP := build/PhotoRiver.app
BIN := mac/.build/release/PhotoRiver
ICON := mac/AppIcon.icns

.PHONY: app run sample icon test clean

app: $(ICON)
	swift build -c release --package-path mac
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BIN) $(APP)/Contents/MacOS/PhotoRiver
	cp mac/Info.plist $(APP)/Contents/Info.plist
	cp $(ICON) $(APP)/Contents/Resources/AppIcon.icns
	cp data/sample/photos.json $(APP)/Contents/Resources/sample-photos.json
	codesign --force --sign - $(APP)

icon: $(ICON)

# The .icns is committed, so builds don't need to redraw it; this rule runs only when the
# drawing script is newer. iconutil wants every size, each at 1x and 2x.
$(ICON): mac/icon/make-icon.swift
	rm -rf build/AppIcon.iconset && mkdir -p build/AppIcon.iconset
	swift mac/icon/make-icon.swift build/AppIcon-1024.png
	for s in 16 32 128 256 512; do \
	  sips -z $$s $$s build/AppIcon-1024.png --out build/AppIcon.iconset/icon_$${s}x$${s}.png >/dev/null; \
	  sips -z $$((s*2)) $$((s*2)) build/AppIcon-1024.png --out build/AppIcon.iconset/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	iconutil -c icns build/AppIcon.iconset -o $(ICON)

# --disable-xctest: XCTest ships only with Xcode; these tests use Swift Testing, which the
# Command Line Tools include. Their copy of the Testing macro plugin sits in a plugins/testing/
# subfolder that the default build system misses whenever it recompiles the tests ("plugin for
# module 'TestingMacros' not found"), so load it by path when it's there.
TESTING_MACROS := $(wildcard $(shell xcode-select -p)/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib)

test:
	swift test --package-path mac --disable-xctest $(if $(TESTING_MACROS),-Xswiftc -load-plugin-library -Xswiftc $(TESTING_MACROS))
	uv run python -m unittest discover tests

run: app
	open $(APP)

sample: app
	open -n $(APP) --args --sample

clean:
	rm -rf build mac/.build
