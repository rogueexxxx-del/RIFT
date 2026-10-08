# Third-party notices

RIFT ships other people's work. This file records what, under what terms, and
what those terms oblige us to do. It is installed alongside the application.

---

## Typefaces

### Yessie's brother Regular
- **Author:** Adele Markova
- **Published by:** SUVA Type Foundry, Estonian Academy of Arts, Tallinn
  (<https://www.suvatypefoundry.ee/yessiesbrotherregular/>)
- **Terms:** free to use. The foundry asks that the author be credited, and
  that work made with it be shared with them where possible.
- **Obligation:** credit Adele Markova. This is done in Help ▸ About RIFT and
  here.
- Used for the RIFT logo lockup (wordmark and application icon) only -
  the app's interface is set in Geist.

> Note: the foundry states a request for credit rather than publishing a formal
> licence with an explicit redistribution clause. Bundling the file in an
> installer is redistribution. Crediting the author satisfies what they ask for;
> if a written grant is ever needed, suvatypefoundry@artun.ee is the contact.

### Geist, Geist Mono
- Vercel - SIL Open Font License 1.1. Redistribution permitted; may not be sold
  on its own.

### JetBrains Mono
- JetBrains - SIL Open Font License 1.1.

### Bebas Neue
- Ryoichi Tsunekawa / Dharma Type - SIL Open Font License 1.1.

---

## Libraries

### Qt 6
- The Qt Company and contributors - **LGPL v3** (this build is from vcpkg, not
  a commercial licence).
- **Obligation:** Qt is linked **dynamically**, as separate DLLs beside the
  executable. That is what keeps LGPL compliance straightforward - a user can
  replace the Qt DLLs with their own build. Do not statically link Qt without
  first resolving the licensing.
- Source: <https://download.qt.io/>

### FFmpeg (libavcodec, libavformat, libavutil, libswscale, libswresample)
- FFmpeg contributors - **LGPL v2.1 or later**. The build used is BtbN's
  `lgpl-shared`, which deliberately excludes GPL-only components.
- **Obligation:** linked dynamically as DLLs; this notice must ship, and source
  must be made available on request.
- Source: <https://ffmpeg.org/download.html>
- Do not swap in a GPL FFmpeg build without re-examining the whole licence.

### miniaudio
- David Reid - public domain (Unlicense) or MIT-0, at your option.

### pffft
- Julien Pommier - BSD-style licence, derived from FFTPACK.

---

## Not redistributed

The offline analysis tooling under `tools/` is development-only and is not part
of the installed application. The runtime has no Python dependency.
