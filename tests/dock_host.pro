QT += core gui widgets
TEMPLATE = app
CONFIG += console c++17
CONFIG -= app_bundle
TARGET = voiceaccess-dock-host
INCLUDEPATH += $$PWD/../native/dock/vendor
SOURCES += $$PWD/dock_host.cpp
QMAKE_MACOSX_DEPLOYMENT_TARGET = 13.0
