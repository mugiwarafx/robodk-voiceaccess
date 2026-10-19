QT += core gui widgets
TEMPLATE = lib
CONFIG += plugin c++17
CONFIG -= app_bundle
isEmpty(VOICEACCESS_BUILD_TAG): error("Build through scripts/build_dock.py")
TARGET = VoiceAccessDock$$VOICEACCESS_BUILD_TAG
INCLUDEPATH += $$PWD/vendor
HEADERS += $$PWD/VoiceAccessDock.h
OBJECTIVE_SOURCES += $$PWD/VoiceAccessDock.mm
LIBS += -framework AppKit
QMAKE_MACOSX_DEPLOYMENT_TARGET = 13.0
QMAKE_RPATHDIR += @executable_path/../Frameworks
