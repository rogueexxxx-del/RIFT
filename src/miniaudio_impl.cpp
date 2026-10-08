// The single translation unit that compiles miniaudio's implementation.
//
// miniaudio is a ~96k-line header-only library: MINIAUDIO_IMPLEMENTATION must
// be defined in exactly ONE .cpp or the linker reports duplicate symbols, and
// compiling it alongside real code would slow every rebuild of that file.
// Everything else includes <miniaudio.h> for declarations only.
#define MINIAUDIO_IMPLEMENTATION

// Decoders we actually need. The engine's own libav handles video; this is the
// monitor path for audio files.
#define MA_NO_ENCODING
#define MA_NO_GENERATION

#include <miniaudio.h>
