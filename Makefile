# Photo River: build the macOS app with the Command Line Tools alone (no Xcode).
#   make app      build build/PhotoRiver.app
#   make run      build and open it on your Photos library
#   make sample   build and open it on the synthetic sample library
#   make clean    remove build output

APP := build/PhotoRiver.app
BIN := mac/.build/release/PhotoRiver

.PHONY: app run sample clean

app:
	swift build -c release --package-path mac
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BIN) $(APP)/Contents/MacOS/PhotoRiver
	cp mac/Info.plist $(APP)/Contents/Info.plist
	cp data/sample/photos.json $(APP)/Contents/Resources/sample-photos.json
	codesign --force --sign - $(APP)

run: app
	open $(APP)

sample: app
	open -n $(APP) --args --sample

clean:
	rm -rf build mac/.build
