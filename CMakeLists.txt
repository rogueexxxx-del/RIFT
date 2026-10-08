cmake_minimum_required(VERSION 3.24)
project(rift_engine LANGUAGES CXX VERSION 1.0.0)

# ── Toolchain ──────────────────────────────────────────────────
# Configure with vcpkg:
#   cmake -B build -S . \
#     -DCMAKE_TOOLCHAIN_FILE=%VCPKG_ROOT%/scripts/buildsystems/vcpkg.cmake
# Deps (see vcpkg.json): qtbase, qtshadertools, ffmpeg, pffft/kissfft,
#   miniaudio (header). Qt provides QRhi + qsb.

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

if(MSVC)
  add_compile_options(/W4 /permissive- /Zc:__cplusplus)
  add_compile_definitions(_CRT_SECURE_NO_WARNINGS)   # quiet fopen/strcpy noise
endif()

# Phase 0 builds ONLY the C-API + core headers as a static lib with stub
# impls, plus a smoke test. RHI/FFmpeg wiring lands P1+ (guarded below).
option(RIFT_WITH_RHI     "Build Qt RHI render backend (P1+)"     OFF)
option(RIFT_WITH_FFMPEG  "Build libav decode/export (P2/P5)"     OFF)
option(RIFT_WITH_AUDIO   "Build miniaudio playback + pffft (P3)" OFF)
option(RIFT_BUILD_TESTS  "Build smoke + golden-diff tests"       ON)

# Always-build set: C API + backend-agnostic logic (weak default hooks make
# these unit-testable with no GPU). Verified by review; compiles on any C++20.
set(RIFT_SOURCES
  src/api.cpp
  src/audio_mixer.cpp         # real-time timeline audio mixer
  src/audio_system.cpp        # offline channel path (source+smoother+ring);
                              # miniaudio/pffft calls #if RIFT_WITH_AUDIO
)

# RHI-dependent set: real GPU wiring + graph execute + engine threads.
if(RIFT_WITH_RHI)
  list(APPEND RIFT_SOURCES
    src/render_graph.cpp      # topo sort + execute (needs draw_pass)
    src/engine.cpp            # threads + facade (P1 impl)
    src/rhi_context.cpp       # Qt RHI backend (P1 impl)
    src/exporter.cpp          # offscreen render -> H.264 (libav-guarded)
  )
endif()

# FFmpeg-dependent set: async media decode + upload (P2).
if(RIFT_WITH_FFMPEG)
  list(APPEND RIFT_SOURCES
    src/media_decoder.cpp     # libav async HW decode -> FrameQueue (P2)
    src/timeline.cpp          # multi-clip track over MediaDecoder
    src/text_source.cpp       # text rasterized to a source texture
    src/layer_stack.cpp       # per-clip effect passes + layer compositing
  )
endif()

add_library(rift_core STATIC ${RIFT_SOURCES})
target_include_directories(rift_core
  PUBLIC  ${CMAKE_CURRENT_SOURCE_DIR}/include
  PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_compile_definitions(rift_core PRIVATE RIFT_BUILD_DLL=0)

if(RIFT_WITH_RHI)
  find_package(Qt6 REQUIRED COMPONENTS Gui ShaderTools)

  # vcpkg lays private headers under include/Qt6/<Module>/<ver>/<Module>.
  # The standard Qt6*_PRIVATE_INCLUDE_DIRS vars are empty here, so glob the
  # versioned dirs and expose them for #include <rhi/qrhi.h> etc.
  set(_vcpkg_inc "${CMAKE_BINARY_DIR}/vcpkg_installed/${VCPKG_TARGET_TRIPLET}/include")
  file(GLOB RIFT_QTGUI_PRIV "${_vcpkg_inc}/Qt6/QtGui/*/QtGui")
  file(GLOB RIFT_QTST_PRIV  "${_vcpkg_inc}/Qt6/QtShaderTools/*/QtShaderTools")
  # QtQuick privates: the shell needs qsgplaintexture_p.h to disown the
  # QRhiTexture inside a QSGTexture (see updatePaintNode).
  # Versioned dirs so <QtQuick/private/...> resolves, plus the modules those
  # privates include in turn (QtQuick -> QtQml -> QtCore/QtGui).
  file(GLOB RIFT_QTQUICK_PRIV
       "${_vcpkg_inc}/Qt6/QtQuick/*"  "${_vcpkg_inc}/Qt6/QtQuick/*/QtQuick"
       "${_vcpkg_inc}/Qt6/QtQml/*"    "${_vcpkg_inc}/Qt6/QtQml/*/QtQml"
       "${_vcpkg_inc}/Qt6/QtCore/*"   "${_vcpkg_inc}/Qt6/QtCore/*/QtCore"
       "${_vcpkg_inc}/Qt6/QtGui/*"    "${_vcpkg_inc}/Qt6/QtGui/*/QtGui")

  target_link_libraries(rift_core PRIVATE Qt6::Gui)
  target_include_directories(rift_core PRIVATE ${RIFT_QTGUI_PRIV})
  # PUBLIC, not PRIVATE: engine.hpp declares members inside #if RIFT_WITH_*,
  # so a consumer compiled without these sees a DIFFERENT class layout. That is
  # an ODR violation and it crashes at the first member access, not at link.
  target_compile_definitions(rift_core PUBLIC RIFT_WITH_RHI=1 RIFT_HAVE_QSB=1)
endif()

if(RIFT_WITH_FFMPEG)
  # Two ways to supply libav:
  #   -DRIFT_FFMPEG_DIR=<extracted BtbN LGPL-shared dir>  (has include/ lib/ bin/)
  #   else fall back to a vcpkg/system find_package(FFMPEG).
  if(RIFT_FFMPEG_DIR)
    set(FFMPEG_INCLUDE_DIRS "${RIFT_FFMPEG_DIR}/include")
    file(GLOB FFMPEG_LIBRARIES  "${RIFT_FFMPEG_DIR}/lib/*.lib")
    file(GLOB RIFT_FFMPEG_DLLS  "${RIFT_FFMPEG_DIR}/bin/*.dll")
    if(NOT FFMPEG_LIBRARIES)
      message(FATAL_ERROR "RIFT_FFMPEG_DIR set but no .lib under ${RIFT_FFMPEG_DIR}/lib")
    endif()
    message(STATUS "libav (manual): ${RIFT_FFMPEG_DIR}")
  else()
    find_package(FFMPEG REQUIRED)   # avcodec avformat avutil swscale
  endif()
  target_link_libraries(rift_core PRIVATE ${FFMPEG_LIBRARIES})
  target_include_directories(rift_core PRIVATE ${FFMPEG_INCLUDE_DIRS})
  target_compile_definitions(rift_core PUBLIC RIFT_WITH_FFMPEG=1)   # see note above
endif()

if(RIFT_WITH_AUDIO)
  find_package(pffft CONFIG REQUIRED)
  find_path(MINIAUDIO_INCLUDE_DIR miniaudio.h REQUIRED)
  # miniaudio is header-only and ~96k lines: its implementation is compiled in
  # exactly one TU so the linker sees one copy and rebuilds stay fast.
  target_sources(rift_core PRIVATE src/miniaudio_impl.cpp)
  target_link_libraries(rift_core PRIVATE pffft::pffft)
  target_include_directories(rift_core PRIVATE ${MINIAUDIO_INCLUDE_DIR})
  target_compile_definitions(rift_core PUBLIC RIFT_WITH_AUDIO=1)    # see note above
endif()

if(RIFT_BUILD_TESTS)
  enable_testing()
  add_executable(rift_smoke tests/smoke.cpp)
  target_link_libraries(rift_smoke PRIVATE rift_core)
  add_test(NAME smoke COMMAND rift_smoke)

  add_executable(rift_audio_mix_test tests/test_audio_mix.cpp)
  target_link_libraries(rift_audio_mix_test PRIVATE rift_core)
  target_include_directories(rift_audio_mix_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
  add_test(NAME audio_mix COMMAND rift_audio_mix_test)

  # Phase 1 parity gate. Check A (channels) builds headless; check B (frames)
  # activates under RIFT_WITH_RHI. Point it at a golden dir from golden_dump.py.
  # Guards the manifest/layout slot order. Needs no GPU, so it runs everywhere.
  add_executable(rift_manifest tests/manifest_layout_test.cpp)
  add_test(NAME manifest COMMAND rift_manifest
           ${CMAKE_CURRENT_SOURCE_DIR}/shaders_qrhi)

  add_executable(rift_parity tests/parity_test.cpp)
  target_link_libraries(rift_parity PRIVATE rift_core)
  target_include_directories(rift_parity PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
  add_test(NAME parity COMMAND rift_parity
           ${CMAKE_CURRENT_SOURCE_DIR}/testdata/gold
           ${CMAKE_CURRENT_SOURCE_DIR}/testdata/gold.analysis)

  # QRhi offscreen render smoke - proves the GPU path (QRhi + QShaderBaker +
  # D3D11) before it goes into the engine. Only under RIFT_WITH_RHI.
  if(RIFT_WITH_RHI)
    # Precompile GLSL -> .qsb with qsb.exe (ships with qtshadertools). The
    # test loads them at runtime via the public QShader::fromSerialized.
    set(QSB "${CMAKE_BINARY_DIR}/vcpkg_installed/${VCPKG_TARGET_TRIPLET}/tools/Qt6/bin/qsb.exe")
    set(QSB_OUT "${CMAKE_BINARY_DIR}/shaders_qsb")
    file(MAKE_DIRECTORY "${QSB_OUT}")
    # Runtime needs the .layout.json (param order + sampler bindings) beside the
    # .qsb. Copy them at configure time (they change rarely).
    file(GLOB PORTED_LAYOUTS "${CMAKE_CURRENT_SOURCE_DIR}/shaders_qrhi/*.layout.json")
    file(COPY ${PORTED_LAYOUTS} DESTINATION "${QSB_OUT}")
    # Manifests carry the UI metadata (label, min/max/step/default, default
    # channel binding) generated from the prototype by tools/gen_manifests.py,
    # so panel ranges match the Python app exactly.
    file(GLOB PORTED_MANIFESTS "${CMAKE_CURRENT_SOURCE_DIR}/shaders_qrhi/*.manifest.json")
    file(COPY ${PORTED_MANIFESTS} DESTINATION "${QSB_OUT}")
    set(_qsb_files "")
    foreach(sh fullscreen.vert test.frag)
      add_custom_command(
        OUTPUT  "${QSB_OUT}/${sh}.qsb"
        COMMAND "${QSB}" --glsl "330" --hlsl 50 --msl 12
                -o "${QSB_OUT}/${sh}.qsb"
                "${CMAKE_CURRENT_SOURCE_DIR}/tests/shaders/${sh}"
        DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/tests/shaders/${sh}"
        COMMENT "qsb ${sh}")
      list(APPEND _qsb_files "${QSB_OUT}/${sh}.qsb")
    endforeach()
    add_custom_target(rift_shaders DEPENDS ${_qsb_files})

    # Validate ALL ported engine shaders compile through qsb (GLSL 440 ->
    # SPIR-V/HLSL/MSL). `cmake --build --target rift_shaders_all` fails loudly
    # on any bad shader.
    file(GLOB PORTED_FRAGS "${CMAKE_CURRENT_SOURCE_DIR}/shaders_qrhi/*.frag")
    set(_all_qsb "")
    add_custom_command(
      OUTPUT "${QSB_OUT}/engine_fullscreen.vert.qsb"
      COMMAND "${QSB}" --glsl "330" --hlsl 50 --msl 12
              -o "${QSB_OUT}/engine_fullscreen.vert.qsb"
              "${CMAKE_CURRENT_SOURCE_DIR}/shaders_qrhi/fullscreen.vert"
      DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/shaders_qrhi/fullscreen.vert"
      COMMENT "qsb engine fullscreen.vert")
    list(APPEND _all_qsb "${QSB_OUT}/engine_fullscreen.vert.qsb")
    foreach(frag ${PORTED_FRAGS})
      get_filename_component(fn "${frag}" NAME)
      add_custom_command(
        OUTPUT  "${QSB_OUT}/${fn}.qsb"
        COMMAND "${QSB}" --glsl "330" --hlsl 50 --msl 12
                -o "${QSB_OUT}/${fn}.qsb" "${frag}"
        DEPENDS "${frag}" COMMENT "qsb ${fn}")
      list(APPEND _all_qsb "${QSB_OUT}/${fn}.qsb")
    endforeach()
    add_custom_target(rift_shaders_all DEPENDS ${_all_qsb})

    # ── P4: QML shell ──────────────────────────────────────────────────────
    # Must sit after QSB_OUT + rift_shaders_all exist. Optional, so the engine
    # and its tests still build while qtdeclarative installs (it drags in a
    # qtbase rebuild, which is not quick).
    find_package(Qt6 QUIET COMPONENTS Quick Qml QuickControls2 Network)
    if(Qt6Quick_FOUND)
      qt_standard_project_setup(REQUIRES 6.5)

      # The .rc carries the icon and the version block; without it the exe
      # ships with a blank generic icon and empty file properties.
      #
      # It is compiled in its OWN object library rather than listed among
      # rift_shell's sources. A .rc inherits every include directory of its
      # target, and rift_shell carries Qt's private include dirs - enough to
      # push rc.exe past the Windows command-line limit, which surfaces only as
      # "The specified task executable rc.exe could not be run". A bare target
      # keeps that command line short.
      if(WIN32)
        add_library(rift_res OBJECT "${CMAKE_CURRENT_SOURCE_DIR}/assets/rift.rc")
      endif()

      qt_add_executable(rift_shell
        src/ui/main_qml.cpp
        src/ui/rift_viewport.cpp
        src/ui/control_input.cpp
        src/ui/asset_paths.cpp)
      # WINDOWS subsystem, not console. Without this the linker produces a CUI
      # binary and Windows opens a terminal window next to the app on every
      # launch, which is what a tester sees first.
      set_target_properties(rift_shell PROPERTIES WIN32_EXECUTABLE TRUE)
      if(WIN32)
        target_link_libraries(rift_shell PRIVATE rift_res)
      endif()
      add_dependencies(rift_shell rift_shaders_all)

      qt_add_qml_module(rift_shell
        URI Rift
        VERSION 1.0
        QML_FILES
          qml/Main.qml
          qml/Hairline.qml
          qml/VHairline.qml
          qml/FlatButton.qml
          qml/TransportBar.qml
          qml/ParamPanel.qml
          qml/ParamSlider.qml
          qml/PatchRow.qml
          qml/ChainBlock.qml
          qml/ClipTrimHandle.qml
          qml/NodeRail.qml
          qml/ChannelMeters.qml
          qml/TimelinePanel.qml
          qml/ClipInspector.qml
          qml/ViewportOverlay.qml
          qml/ColorPanel.qml
          qml/ColorStyleEditor.qml
          qml/AppMenu.qml
          qml/IconButton.qml
          qml/Dock.qml
          qml/ControllerView.qml
          qml/ExportDialog.qml
          qml/ExportProgressDialog.qml
          qml/PreferencesDialog.qml
          qml/ShortcutSheet.qml
          qml/AboutDialog.qml
          qml/LiveBar.qml
          qml/ControlPanel.qml
          qml/QueuePanel.qml
          qml/ToolTipArea.qml
          qml/StyledMenu.qml
          qml/AppDialog.qml
          qml/NewProjectDialog.qml
          qml/FontPicker.qml
          qml/AudioInputPanel.qml
          qml/MappingList.qml
          qml/EditToolButton.qml
          qml/PresetBar.qml
          qml/PresetGroup.qml
          qml/SectionHeader.qml
        SOURCES
          src/ui/rift_viewport.hpp
          src/ui/control_input.hpp)
      # Theme is a singleton: the property goes on the file, not the module.
      set_source_files_properties(qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
      qt_target_qml_sources(rift_shell QML_FILES qml/Theme.qml)

      target_link_libraries(rift_shell PRIVATE
        rift_core Qt6::Quick Qt6::Qml Qt6::QuickControls2 Qt6::Network)
      if(WIN32)
        target_link_libraries(rift_shell PRIVATE winmm)   # MIDI in
      endif()
      # src/ui must be on the path: Qt's generated qmltyperegistrations.cpp
      # probes `#if __has_include(<rift_viewport.hpp>)`, which fails silently
      # and leaves the type unregistered if the dir is missing.
      target_include_directories(rift_shell PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
        ${CMAKE_CURRENT_SOURCE_DIR}/src/ui
        ${RIFT_QTGUI_PRIV}
        ${RIFT_QTQUICK_PRIV})
      # Dev fallbacks only. At runtime the app looks for `shaders/` and `fonts/`
      # beside the executable first (see src/ui/asset_paths.cpp) - these paths
      # exist so an exe launched straight from an IDE still starts.
      target_compile_definitions(rift_shell PRIVATE
        SHADER_QSB_DIR="${QSB_OUT}"
        RIFT_FONT_DIR="${CMAKE_CURRENT_SOURCE_DIR}/assets/fonts"
        RIFT_ASSETS_DIR="${CMAKE_CURRENT_SOURCE_DIR}/assets")

      # ── deployable layout, built every time ──
      # Assets are copied next to the exe on every build, so a normal dev run
      # exercises exactly the paths a shipped copy uses. Producing the shipping
      # layout only at install time is how it rots without anyone noticing.
      add_custom_command(TARGET rift_shell POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
                "${QSB_OUT}" "$<TARGET_FILE_DIR:rift_shell>/shaders"
        COMMAND ${CMAKE_COMMAND} -E copy_directory
                "${CMAKE_CURRENT_SOURCE_DIR}/assets/fonts"
                "$<TARGET_FILE_DIR:rift_shell>/fonts"
        COMMAND ${CMAKE_COMMAND} -E copy_directory
                "${CMAKE_CURRENT_SOURCE_DIR}/assets"
                "$<TARGET_FILE_DIR:rift_shell>/assets"
        COMMENT "staging shaders, fonts, and assets beside rift_shell")

      # libav lives beside the exe too. This used to be done only for the test
      # targets, and the shell worked purely because every target shares one
      # output directory - an installed copy would have had no libav at all.
      if(RIFT_FFMPEG_DLLS)
        add_custom_command(TARGET rift_shell POST_BUILD
          COMMAND ${CMAKE_COMMAND} -E copy_if_different
                  ${RIFT_FFMPEG_DLLS} "$<TARGET_FILE_DIR:rift_shell>"
          COMMENT "staging libav DLLs beside rift_shell")
      endif()

      # ── install / package ──
      # windeployqt brings the Qt DLLs, the platform + imageformats plugins and
      # the QML modules, which is everything the app needs that CMake does not
      # know about. Without it the installed exe dies at startup with no
      # message (WIN32 subsystem: nowhere to print).
      install(TARGETS rift_shell RUNTIME DESTINATION .)
      install(DIRECTORY "${QSB_OUT}/" DESTINATION shaders)
      install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/assets/fonts/" DESTINATION fonts)
      install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/assets/" DESTINATION assets)
      install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/THIRD-PARTY-NOTICES.md" DESTINATION .)
      if(RIFT_FFMPEG_DLLS)
        install(FILES ${RIFT_FFMPEG_DLLS} DESTINATION .)
      endif()
      if(WIN32)
        find_program(RIFT_WINDEPLOYQT windeployqt
                     HINTS "${_qt_bin_dir}" "${QT6_INSTALL_PREFIX}/bin"
                           "${CMAKE_BINARY_DIR}/vcpkg_installed/${VCPKG_TARGET_TRIPLET}/tools/Qt6/bin")
        if(RIFT_WINDEPLOYQT)
          # --compiler-runtime is what makes the staged folder portable: Qt's
          # own DLLs are not enough, the exe also needs the MSVC runtime
          # (msvcp140 / vcruntime140), and a machine without Visual Studio
          # installed has no copy. Without it a tester gets "the code execution
          # cannot proceed" and nothing else.
          install(CODE "execute_process(COMMAND \"${RIFT_WINDEPLOYQT}\"
                          --release --compiler-runtime
                          --qmldir \"${CMAKE_CURRENT_SOURCE_DIR}/qml\"
                          --no-translations --no-system-d3d-compiler
                          \"\${CMAKE_INSTALL_PREFIX}/rift_shell.exe\")")
        else()
          message(STATUS "windeployqt not found - `cmake --install` will not be runnable")
        endif()
      endif()
    else()
      message(STATUS "Qt6 Quick not found - skipping rift_shell (P4 QML target)")
    endif()

    add_executable(rift_render_test tests/render_test.cpp)
    add_dependencies(rift_render_test rift_shaders)
    target_link_libraries(rift_render_test PRIVATE Qt6::Gui)
    target_include_directories(rift_render_test PRIVATE ${RIFT_QTGUI_PRIV})
    target_compile_definitions(rift_render_test PRIVATE
      SHADER_QSB_DIR="${QSB_OUT}")
    add_test(NAME render COMMAND rift_render_test)

    # Renders a real ported shader (ascii) on an image via QRhi.
    add_executable(rift_render_engine_test tests/render_engine_test.cpp)
    add_dependencies(rift_render_engine_test rift_shaders_all)
    target_link_libraries(rift_render_engine_test PRIVATE Qt6::Gui)
    target_include_directories(rift_render_engine_test PRIVATE ${RIFT_QTGUI_PRIV})
    target_compile_definitions(rift_render_engine_test PRIVATE
      SHADER_QSB_DIR="${QSB_OUT}")

    # Chunk B: full path - RenderGraph drives RhiContext (rift_core) on GPU.
    add_executable(rift_graph_render_test tests/graph_render_test.cpp)
    add_dependencies(rift_graph_render_test rift_shaders_all)
    target_link_libraries(rift_graph_render_test PRIVATE rift_core Qt6::Gui)
    target_include_directories(rift_graph_render_test PRIVATE
      ${CMAKE_CURRENT_SOURCE_DIR}/src ${RIFT_QTGUI_PRIV})
    target_compile_definitions(rift_graph_render_test PRIVATE
      SHADER_QSB_DIR="${QSB_OUT}")
    add_test(NAME graph_render COMMAND rift_graph_render_test)

    # Chunk E: libav decode -> texture -> graph. Only meaningful with FFMPEG.
    if(RIFT_WITH_FFMPEG)
      add_executable(rift_media_decode_test tests/media_decode_test.cpp)
      add_dependencies(rift_media_decode_test rift_shaders_all)
      target_link_libraries(rift_media_decode_test PRIVATE rift_core Qt6::Gui)
      target_include_directories(rift_media_decode_test PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src ${RIFT_QTGUI_PRIV})
      target_compile_definitions(rift_media_decode_test PRIVATE
        SHADER_QSB_DIR="${QSB_OUT}")
      add_test(NAME media_decode COMMAND rift_media_decode_test)

      add_executable(rift_export_test tests/export_test.cpp)
      add_dependencies(rift_export_test rift_shaders_all)
      target_link_libraries(rift_export_test PRIVATE rift_core Qt6::Gui)
      target_include_directories(rift_export_test PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src ${RIFT_QTGUI_PRIV})
      target_compile_definitions(rift_export_test PRIVATE
        SHADER_QSB_DIR="${QSB_OUT}")
      add_test(NAME export COMMAND rift_export_test)

      # Encoder-ladder probe + QPainter overlays (in-process; no Python, P6).
      add_executable(rift_export_hybrid_test tests/export_hybrid_test.cpp)
      add_dependencies(rift_export_hybrid_test rift_shaders_all)
      target_link_libraries(rift_export_hybrid_test PRIVATE rift_core Qt6::Gui)
      target_include_directories(rift_export_hybrid_test PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src ${RIFT_QTGUI_PRIV})
      target_compile_definitions(rift_export_hybrid_test PRIVATE
        SHADER_QSB_DIR="${QSB_OUT}")
      add_test(NAME export_hybrid COMMAND rift_export_hybrid_test)
    endif()

    # The GPU tests construct a QGuiApplication, which aborts (0xc0000409, "no
    # Qt platform plugin") unless Qt can find plugins/platforms. Nothing stages
    # plugins beside the test exes - windeployqt is not in the vcpkg package -
    # so point Qt at the platform plugin's own install location. Taken from the
    # imported target rather than a hardcoded vcpkg path, so each config gets
    # its matching plugins (Debug needs qwindowsd.dll, not qwindows.dll).
    if(TARGET Qt6::QWindowsIntegrationPlugin)
      foreach(t render graph_render media_decode export export_hybrid)
        if(TEST ${t})
          set_tests_properties(${t} PROPERTIES ENVIRONMENT
            "QT_PLUGIN_PATH=$<PATH:GET_PARENT_PATH,$<TARGET_FILE_DIR:Qt6::QWindowsIntegrationPlugin>>")
        endif()
      endforeach()
    endif()

    # Chunk D: on-screen preview via QRhi swapchain. Interactive (opens a
    # window) so it's a build target, not a ctest.
    add_executable(rift_preview_test tests/preview_test.cpp)
    add_dependencies(rift_preview_test rift_shaders_all)
    target_link_libraries(rift_preview_test PRIVATE rift_core Qt6::Gui)
    target_include_directories(rift_preview_test PRIVATE
      ${CMAKE_CURRENT_SOURCE_DIR}/src ${RIFT_QTGUI_PRIV})
    target_compile_definitions(rift_preview_test PRIVATE
      SHADER_QSB_DIR="${QSB_OUT}")

    # Put libav DLLs beside the test exes so they run in place.
    if(RIFT_FFMPEG_DLLS)
      foreach(t rift_graph_render_test rift_media_decode_test rift_export_test
                rift_export_hybrid_test)
        if(TARGET ${t})
          add_custom_command(TARGET ${t} POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                    ${RIFT_FFMPEG_DLLS} $<TARGET_FILE_DIR:${t}>)
        endif()
      endforeach()
    endif()
  endif()
endif()
