PYTHON ?= python3
QMAKE ?= $(if $(VOICEACCESS_QT),$(VOICEACCESS_QT)/bin/qmake,qmake)

.PHONY: build package unit integration fixture install-development

build:
	$(PYTHON) scripts/build_voiceaccess.py
	$(PYTHON) scripts/build_dock.py
	$(PYTHON) scripts/package_addin.py --metadata-only

package: build
	$(PYTHON) scripts/package_addin.py
	$(PYTHON) tests/verify_package.py

unit:
	mkdir -p build/tests build/reports/evidence
	$(PYTHON) tests/verify_deactivation.py
	$(PYTHON) tests/verify_dock_routing.py
	$(PYTHON) tests/verify_toolbar.py
	xcrun swiftc -O -swift-version 5 -framework AppKit native/StationOutline.swift tests/verify_outline.swift -o build/tests/outline
	build/tests/outline build/reports/outline.json
	xcrun swiftc -O -swift-version 5 native/Integration.swift tests/verify_integration.swift -o build/tests/integration
	build/tests/integration build/reports/integration.json
	xcrun swiftc -O -swift-version 5 native/Speech.swift tests/verify_speech.swift -o build/tests/speech
	build/tests/speech build/reports/speech.json build/reports/evidence

integration:
	mkdir -p build/dock-host build/reports/evidence
	cd build/dock-host && $(QMAKE) ../../tests/dock_host.pro && $(MAKE)
	ROBODK_AI=noui $(PYTHON) tests/verify_voiceaccess.py
	ROBODK_AI=noui $(PYTHON) tests/verify_dock.py

fixture:
	ROBODK_AI=noui $(PYTHON) tests/station_fixture.py

install-development:
	$(PYTHON) scripts/package_addin.py --metadata-only
	$(PYTHON) scripts/install_development.py
