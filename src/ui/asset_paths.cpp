#include "asset_paths.hpp"
#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>

namespace rift {

QString assetDir(const QString& name, const QString& compiledFallback) {
    // applicationDirPath() is the real exe location even when the working
    // directory is somewhere else entirely - which it is when the app is
    // launched from a Start-menu shortcut.
    const QString beside = QDir(QCoreApplication::applicationDirPath())
                               .filePath(name);
    if (QFileInfo(beside).isDir()) return beside;
    return compiledFallback;
}

} // namespace rift
