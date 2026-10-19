#pragma once
#include <QObject>
#include <QLibrary>
#include <QPointer>
#include "vendor/iapprobodk.h"
class QDockWidget;
class QWindow;

class VoiceAccessDock : public QObject, public IAppRoboDK {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "RoboDK.IAppRoboDK")
    Q_INTERFACES(IAppRoboDK)
public:
    QString PluginName() override { return QStringLiteral("VoiceAccess Dock"); }
    QString PluginLoad(QMainWindow*, QMenuBar*, QStatusBar*, IRoboDK*, const QString& = QString()) override;
    void PluginUnload() override;
    QString PluginCommand(const QString&, const QString&) override;
private:
    bool create(const QString&);
    void setVisible(bool);
    static void visibilityCallback(int, void*);
    QPointer<QMainWindow> mainWindow;
    QPointer<QDockWidget> dock;
    QPointer<QWindow> foreignWindow;
    QLibrary native;
    using Create = void* (*)(const char*, void (*)(int, void*), void*);
    using Void = void (*)();
    using Visible = void (*)(int);
    using Command = char* (*)(const char*, const char*);
    Create createNative = nullptr;
    Void attachNative = nullptr, destroyNative = nullptr;
    Visible visibleNative = nullptr;
    Command commandNative = nullptr;
    QString lastError;
};
