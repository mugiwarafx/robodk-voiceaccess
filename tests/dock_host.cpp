#include <QApplication>
#include <QMainWindow>
#include <QPluginLoader>
#include <QJsonObject>
#include <QJsonDocument>
#include <QTimer>
#include <QFile>
#include <QLabel>
#include <QElapsedTimer>
#include "iapprobodk.h"
#include <cstdio>

int main(int argc, char** argv) {
    QApplication application(argc, argv);
    if (argc != 4) return 2;
    QPluginLoader loader(QString::fromLocal8Bit(argv[1]));
    auto instance = loader.instance();
    if (!instance) { fprintf(stderr, "%s\n", qPrintable(loader.errorString())); return 3; }
    auto plugin = qobject_cast<IAppRoboDK*>(instance);
    if (!plugin) return 4;
    QMainWindow window;
    window.setWindowTitle(QStringLiteral("VoiceAccess integration test host"));
    window.resize(1200, 900);
    auto workspace = new QLabel(QStringLiteral("RoboDK workspace"));
    workspace->setMinimumSize(400, 200);
    window.setCentralWidget(workspace);
    window.show();
    plugin->PluginLoad(&window, window.menuBar(), window.statusBar(), nullptr);
    QFile config(QString::fromLocal8Bit(argv[2])); if (!config.open(QIODevice::ReadOnly)) return 6;
    auto configured = plugin->PluginCommand(QStringLiteral("configure"), QString::fromUtf8(config.readAll()));
    fprintf(stderr, "configure: %s\n", qPrintable(configured));
    QElapsedTimer elapsed; elapsed.start();
    QTimer poll;
    QObject::connect(&poll, &QTimer::timeout, [&] {
        auto report = QJsonDocument::fromJson(plugin->PluginCommand(QStringLiteral("report"), QStringLiteral("{}")).toUtf8()).object();
        if (report.value("rows").toInt() > 2) {
            poll.stop();
            window.resize(900, 500);
            QApplication::processEvents();
            const bool canShrink = window.height() <= 500;
            window.resize(1200, 900);
            plugin->PluginCommand(QStringLiteral("show"), QStringLiteral("{}"));
            QTimer::singleShot(200, [&, canShrink] {
                auto output = plugin->PluginCommand(QStringLiteral("self-test"), QStringLiteral("{}"));
                auto checks = QJsonDocument::fromJson(output.toUtf8()).object();
                checks["host_can_shrink_to_500px"] = canShrink;
                QFile result(QString::fromLocal8Bit(argv[3])); if (!result.open(QIODevice::WriteOnly)) { application.exit(7); return; } result.write(QJsonDocument(checks).toJson()); result.close();
                plugin->PluginUnload();
                application.exit(0);
            });
        } else if (elapsed.elapsed() > 20000) {
            fprintf(stderr, "Timed out: %s\n", qPrintable(QString::fromUtf8(QJsonDocument(report).toJson())));
            application.exit(5);
        }
    });
    poll.start(200);
    return application.exec();
}
