.PHONY: check

QMLLINT ?= /usr/lib/qt6/bin/qmllint
OMARCHY_PATH ?= /usr/share/omarchy

check:
	node tests/model.test.js
	python3 tests/listen-keys.test.py
	omarchy plugin validate .
	$(QMLLINT) -I "$(OMARCHY_PATH)/shell" Overlay.qml BarWidget.qml Panel.qml
