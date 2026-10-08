// Where the app finds the files it ships with.
//
// Shaders and fonts used to be compile-time absolute paths pointing into the
// build tree (and, for fonts, into the Python prototype's directory). That
// works on the machine that built it and nowhere else, which is the single
// thing standing between this and an installable application.
//
// Resolution order is deliberate:
//   1. <exe dir>/<name>   - the deployed layout, and also what a normal dev
//                           build produces, because CMake copies the assets
//                           there post-build. Exercising the shipping path on
//                           every run is the only way it stays working.
//   2. the compile-time fallback - a source/build directory, so an exe run
//                           straight out of an IDE without the copy step still
//                           starts instead of failing with a blank window.
#pragma once
#include <QString>

namespace rift {

// `name` is the folder beside the executable, e.g. "shaders" or "fonts".
// `compiledFallback` is the build-time path, "" if there isn't one.
// Returns the first that exists; the fallback is returned unchecked when
// neither does, so error messages name a real path rather than "".
QString assetDir(const QString& name, const QString& compiledFallback);

} // namespace rift
