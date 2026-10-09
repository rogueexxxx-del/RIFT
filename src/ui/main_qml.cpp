// P4 shell entry point â€” loads the QML UI and hands it the shader dir.
//
// Qt Quick must run on the RHI D3D11 backend: the engine renders with QRhi
// D3D11, and RiftViewport shares Quick's device rather than creating a second
// one. Any other graphics api leaves rendererInterface() with no QRhi to give.
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QQmlContext>
#include <QQuickWindow>
#include <QFontDatabase>
#include <QDir>
#include <QSGRendererInterface>
#include <QTimer>

#include "asset_paths.hpp"

#ifndef SHADER_QSB_DIR
#define SHADER_QSB_DIR "."
#endif
#ifndef RIFT_FONT_DIR
#define RIFT_FONT_DIR ""
#endif
#ifndef RIFT_ASSETS_DIR
#define RIFT_ASSETS_DIR ""
#endif

int main(int argc, char** argv) {
    QQuickWindow::setGraphicsApi(QSGRendererInterface::Direct3D11);
    QQuickWindow::setTextRenderType(QQuickWindow::NativeTextRendering);

    // Pass-through high DPI scaling preserves 1:1 pixel grid without nearest-neighbor blur
    QGuiApplication::setHighDpiScaleFactorRoundingPolicy(
        Qt::HighDpiScaleFactorRoundingPolicy::PassThrough);

    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("RIFT"));
    // QSettings refuses to initialise without these, which is what the QML
    // Settings type uses to persist preferences.
    app.setOrganizationName(QStringLiteral("RIFT"));
    app.setOrganizationDomain(QStringLiteral("rift.local"));

    // Fonts ship beside the exe; the build-time path is only a dev fallback.
    // They used to be loaded straight out of the Python prototype's directory,
    // which meant the "standalone" app was not standalone at all.
    const QDir fontDir(rift::assetDir(QStringLiteral("fonts"),
                                      QStringLiteral(RIFT_FONT_DIR)));
    if (fontDir.exists()) {
        const auto files = fontDir.entryList({ QStringLiteral("*.ttf"),
                                               QStringLiteral("*.otf") },
                                             QDir::Files, QDir::Name);
        for (const QString& f : files)
            QFontDatabase::addApplicationFont(fontDir.filePath(f));
    }

    // Set Geist with subpixel antialiasing and native DirectWrite hinting
    QFont appFont(QStringLiteral("Geist"), 10);
    appFont.setStyleHint(QFont::SansSerif, QFont::PreferAntialias);
    appFont.setHintingPreference(QFont::PreferFullHinting);
    app.setFont(appFont);

    // Basic, not the native Windows style: the shell is fully themed, the
    // native style fights it visually, and its PNG-based indicators need an
    // image plugin that is not deployed (menu arrows/checkmarks fail to decode).
    QQuickStyle::setStyle(QStringLiteral("Basic"));

    QQmlApplicationEngine engine;
    engine.addImportPath(app.applicationDirPath() + QStringLiteral("/qml"));
    // Bisect helper: load an arbitrary .qml instead of the Rift module, to tell
    // whether a problem lives in this C++ setup or in the shell's QML.
    const QByteArray testQml = qgetenv("RIFT_UI_TESTQML");
    if (!testQml.isEmpty()) {
        engine.load(QUrl::fromLocalFile(QString::fromLocal8Bit(testQml)));
        return engine.rootObjects().isEmpty() ? 1 : app.exec();
    }
    // Shader dir is a build-time path for now; project loading supplies it later.
    // --media / --audio preload straight into a file, skipping the dialogs.
    QString initialMedia, initialAudio, initialAnalysis, initialExport, initialChain;
    QString initialSave, initialOpen;      // --save / --open project files
    QString initialSavePreset;             // --savepreset NAME: save look, quit
    QVariantList initialParams;          // --param INDEX=VALUE (repeatable)
    QVariantList initialClips;           // --clip PATH (repeatable)
    QVariantList initialBlends;          // --blend IDX|MODE|OPACITY
    QVariantList initialKeys;            // --key PARAM|TIME|VALUE|INTERP
    QVariantList initialGrade;           // --grade INDEX=VALUE
    QVariantList initialMaps;            // --map KEY=PARAM (repeatable)
    QVariantList initialNodeBlends;      // --nodeblend IDX|MODE|MIX
    QString initialOsc;                  // --osc PORT
    QString initialQueue;                // --queue PATH: batch render and quit
    QVariantList initialTexts;           // --text TEXT[|LANE|SECONDS|SIZE]
    QString initialScreenshot;           // --screenshot PATH: capture window and quit
    const QStringList args = app.arguments();
    for (int i = 1; i + 1 < args.size(); ++i) {
        if (args[i] == QLatin1String("--media")) initialMedia = args[i + 1];
        else if (args[i] == QLatin1String("--audio")) initialAudio = args[i + 1];
        else if (args[i] == QLatin1String("--analysis")) initialAnalysis = args[i + 1];
        else if (args[i] == QLatin1String("--export")) initialExport = args[i + 1];
        else if (args[i] == QLatin1String("--chain"))  initialChain  = args[i + 1];
        else if (args[i] == QLatin1String("--param")) initialParams << args[i + 1];
        else if (args[i] == QLatin1String("--clip"))  initialClips  << args[i + 1];
        else if (args[i] == QLatin1String("--blend")) initialBlends << args[i + 1];
        else if (args[i] == QLatin1String("--key"))   initialKeys   << args[i + 1];
        else if (args[i] == QLatin1String("--grade")) initialGrade  << args[i + 1];
        else if (args[i] == QLatin1String("--save"))  initialSave   = args[i + 1];
        else if (args[i] == QLatin1String("--savepreset"))
            initialSavePreset = args[i + 1];
        else if (args[i] == QLatin1String("--open"))  initialOpen   = args[i + 1];
        else if (args[i] == QLatin1String("--osc"))   initialOsc    = args[i + 1];
        else if (args[i] == QLatin1String("--map"))   initialMaps   << args[i + 1];
        else if (args[i] == QLatin1String("--nodeblend"))
            initialNodeBlends << args[i + 1];
        else if (args[i] == QLatin1String("--queue"))
            initialQueue = args[i + 1];
        else if (args[i] == QLatin1String("--text"))
            initialTexts << args[i + 1];
        else if (args[i] == QLatin1String("--screenshot"))
            initialScreenshot = args[i + 1];
    }

    const QString assetsDir = rift::assetDir(QStringLiteral("assets"), QStringLiteral(RIFT_ASSETS_DIR));
    const QUrl assetsUrl = QUrl::fromLocalFile(QDir(assetsDir).absolutePath() + QLatin1Char('/'));
    engine.rootContext()->setContextProperty(QStringLiteral("assetsUrl"), assetsUrl);

    engine.setInitialProperties({
        { QStringLiteral("assetsUrl"),    assetsUrl },
        { QStringLiteral("shaderDir"),    rift::assetDir(QStringLiteral("shaders"),
                                              QStringLiteral(SHADER_QSB_DIR)) },
        { QStringLiteral("initialMedia"), initialMedia },
        { QStringLiteral("initialAudio"), initialAudio },
        { QStringLiteral("initialAnalysis"), initialAnalysis },
        { QStringLiteral("initialPlay"),  args.contains(QStringLiteral("--play")) },
        { QStringLiteral("initialLive"),  args.contains(QStringLiteral("--live")) },
        { QStringLiteral("initialParams"), initialParams },
        { QStringLiteral("initialClips"),  initialClips },
        { QStringLiteral("initialBlends"), initialBlends },
        { QStringLiteral("initialKeys"),   initialKeys },
        { QStringLiteral("initialGrade"),  initialGrade },
        { QStringLiteral("initialExport"), initialExport },
        { QStringLiteral("initialChain"),  initialChain },
        { QStringLiteral("initialSave"),   initialSave },
        { QStringLiteral("initialSavePreset"), initialSavePreset },
        { QStringLiteral("initialOpen"),   initialOpen },
        { QStringLiteral("initialOsc"),    initialOsc },
        { QStringLiteral("initialMaps"),   initialMaps },
        { QStringLiteral("initialNodeBlends"), initialNodeBlends },
        { QStringLiteral("initialQueue"),      initialQueue },
        { QStringLiteral("initialTexts"),      initialTexts }
    });
    engine.loadFromModule("Rift", "Main");
    if (engine.rootObjects().isEmpty()) return 1;

    if (!initialScreenshot.isEmpty()) {
        auto* win = qobject_cast<QQuickWindow*>(engine.rootObjects().value(0));
        qWarning() << "[Screenshot] target:" << initialScreenshot << "win:" << win;
        if (win) {
            win->show();
            QTimer::singleShot(2500, [win, initialScreenshot, &app]() {
                const QImage img = win->grabWindow();
                const bool ok = img.save(initialScreenshot);
                qWarning() << "[Screenshot] grabbed size:" << img.size() << "isNull:" << img.isNull() << "saved:" << ok;
                app.quit();
            });
        }
    }

    return app.exec();
}



