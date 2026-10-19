#include "VoiceAccessDock.h"
#include "VoiceAccessBuild.h"
#include <QMainWindow>
#include <QDockWidget>
#include <QWindow>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDir>
#include <QFileInfo>
#include <QTimer>
#include <QCoreApplication>
#include <QApplication>
#include <dlfcn.h>
#include <cstdlib>
#import <AppKit/AppKit.h>

static void libraryAnchor() {}

QString VoiceAccessDock::PluginLoad(QMainWindow* mw, QMenuBar*, QStatusBar*, IRoboDK*, const QString&) {
    mainWindow = mw;
    return QString();
}

bool VoiceAccessDock::create(const QString& configuration) {
    if (dock) return true;
    Dl_info info{};
    dladdr(reinterpret_cast<void*>(&libraryAnchor), &info);
    native.setFileName(QFileInfo(QString::fromUtf8(info.dli_fname)).dir().filePath(QStringLiteral(VOICEACCESS_NATIVE_LIBRARY)));
    // Swift/Objective-C classes must stay registered for this host's lifetime.
    native.setLoadHints(QLibrary::PreventUnloadHint);
    if (!native.load()) { lastError = native.errorString(); return false; }
    createNative = reinterpret_cast<Create>(native.resolve("va_dock_create"));
    attachNative = reinterpret_cast<Void>(native.resolve("va_dock_attach"));
    destroyNative = reinterpret_cast<Void>(native.resolve("va_dock_destroy"));
    visibleNative = reinterpret_cast<Visible>(native.resolve("va_dock_visible"));
    commandNative = reinterpret_cast<Command>(native.resolve("va_dock_command"));
    if (!createNative || !attachNative || !destroyNative || !visibleNative || !commandNative) { lastError = QStringLiteral("Missing native entry point"); return false; }
    void* view = createNative(configuration.toUtf8().constData(), &visibilityCallback, this);
    if (!view) { lastError = QStringLiteral("Native view factory rejected configuration: ") + configuration; return false; }
    foreignWindow = QWindow::fromWinId(reinterpret_cast<WId>(view));
    if (!foreignWindow) { lastError = QStringLiteral("Qt could not wrap the native NSView"); destroyNative(); return false; }
    dock = new QDockWidget(QStringLiteral("VoiceAccess"), mainWindow);
    dock->setObjectName(QStringLiteral("VoiceAccessInternalDock"));
    dock->setAllowedAreas(Qt::AllDockWidgetAreas);
    dock->setFeatures(QDockWidget::DockWidgetClosable | QDockWidget::DockWidgetMovable | QDockWidget::DockWidgetFloatable);
    auto container = QWidget::createWindowContainer(foreignWindow, dock);
    container->setMinimumSize(300, 220);
    container->setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Expanding);
    container->setFocusPolicy(Qt::StrongFocus);
    dock->setWidget(container);
    mainWindow->addDockWidget(Qt::RightDockWidgetArea, dock);
    dock->show();
    mainWindow->resizeDocks({dock}, {400}, Qt::Horizontal);
    attachNative();
    connect(dock, &QDockWidget::visibilityChanged, this, [this](bool visible) { if (visibleNative) visibleNative(visible); });
    visibleNative(1);
    return true;
}

void VoiceAccessDock::setVisible(bool visible) {
    if (!dock) return;
    dock->setVisible(visible);
    if (visible) { dock->raise(); mainWindow->activateWindow(); }
}
void VoiceAccessDock::visibilityCallback(int visible, void* context) {
    static_cast<VoiceAccessDock*>(context)->setVisible(visible != 0);
}

QString VoiceAccessDock::PluginCommand(const QString& command, const QString& value) {
    if (command == QStringLiteral("status")) {
        QJsonObject status{{"available", true}, {"embedded", !dock.isNull()}, {"visible", dock && dock->isVisible()},
                           {"pid", qint64(QCoreApplication::applicationPid())}, {"qt", QString::fromLatin1(qVersion())},
                           {"version", QStringLiteral(VOICEACCESS_VERSION)}};
        if (dock) {
            status["dock_area"] = int(mainWindow->dockWidgetArea(dock));
            status["width"] = dock->width(); status["height"] = dock->height();
            status["minimum_width"] = dock->minimumWidth(); status["minimum_height"] = dock->minimumHeight();
            status["floatable"] = dock->features().testFlag(QDockWidget::DockWidgetFloatable);
        }
        return QString::fromUtf8(QJsonDocument(status).toJson(QJsonDocument::Compact));
    }
    if (command == QStringLiteral("configure")) {
        if (!create(value)) return QString::fromUtf8(QJsonDocument(QJsonObject{{"error", lastError}}).toJson(QJsonDocument::Compact));
        return QStringLiteral("{\"configured\":true}");
    }
    if (!dock || !commandNative) return QStringLiteral("{\"error\":\"VoiceAccess dock is not configured\"}");
    if (command == QStringLiteral("resize")) {
        const auto options = QJsonDocument::fromJson(value.toUtf8()).object();
        mainWindow->resizeDocks({dock}, {qMax(300, options.value("width").toInt(400))}, Qt::Horizontal);
        return PluginCommand(QStringLiteral("status"), QString());
    }
    if (command == QStringLiteral("show") || command == QStringLiteral("read-selection")) setVisible(true);
    if (command == QStringLiteral("hide")) setVisible(false);
    char* output = commandNative(command.toUtf8().constData(), value.toUtf8().constData());
    const auto result = QString::fromUtf8(output ? output : "{}");
    free(output);
    return result;
}

void VoiceAccessDock::PluginUnload() {
    if (!dock) return;
    disconnect(dock, nullptr, this, nullptr);
    dock->hide();
    // Destroy Qt's wrapper before releasing the underlying NSView.
    delete dock.data(); dock = nullptr; foreignWindow = nullptr;
    if (destroyNative) destroyNative();
}
