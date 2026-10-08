// Every shader's manifest must describe the SAME parameter slots, in the same
// order, as its layout - the manifest is turned into a positional float array
// and handed straight to the shader.
//
// This is not hypothetical: blur shipped with RADIUS and MODE swapped, so the
// radius slider drove the mode and the real radius stayed 0, which made the
// blur a no-op. pixel_sort and oscilloscope were shifted the same way. Nothing
// failed loudly - the picture was just wrong.
//
// A manifest may declare FEWER params than the layout: trailing slots the
// engine never sets are allowed. Leading or interleaved ones are not, because
// they shift everything after them.
#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <filesystem>

namespace fs = std::filesystem;

// Minimal extractor: pulls the quoted strings out of "params": [ ... ] and the
// "name" fields out of "uniforms". Avoids a JSON dependency for two shapes.
static std::vector<std::string> json_array(const std::string& src,
                                           const std::string& key) {
    std::vector<std::string> out;
    const size_t k = src.find("\"" + key + "\"");
    if (k == std::string::npos) return out;
    const size_t open = src.find('[', k);
    if (open == std::string::npos) return out;
    int depth = 0;
    for (size_t i = open; i < src.size(); ++i) {
        if (src[i] == '[') ++depth;
        else if (src[i] == ']') { if (--depth == 0) break; }
        else if (src[i] == '"') {
            const size_t e = src.find('"', i + 1);
            if (e == std::string::npos) break;
            out.push_back(src.substr(i + 1, e - i - 1));
            i = e;
        }
    }
    return out;
}

static std::vector<std::string> uniform_names(const std::string& whole) {
    std::vector<std::string> out;
    // Scan ONLY inside the "uniforms" array. The manifest also has a top-level
    // "name" (the effect's display name) before it and a "samplers" list after
    // it, both of which would otherwise be read as parameters.
    const size_t k = whole.find("\"uniforms\"");
    if (k == std::string::npos) return out;
    const size_t open = whole.find('[', k);
    if (open == std::string::npos) return out;
    size_t close = open;
    for (int depth = 0; close < whole.size(); ++close) {
        if (whole[close] == '[') ++depth;
        else if (whole[close] == ']' && --depth == 0) break;
    }
    const std::string src = whole.substr(open, close - open);

    size_t p = 0;
    while ((p = src.find("\"name\"", p)) != std::string::npos) {
        const size_t q1 = src.find('"', src.find(':', p) + 1);
        const size_t q2 = src.find('"', q1 + 1);
        if (q1 == std::string::npos || q2 == std::string::npos) break;
        out.push_back(src.substr(q1 + 1, q2 - q1 - 1));
        p = q2;
    }
    return out;
}

static std::string slurp(const fs::path& p) {
    std::ifstream f(p);
    std::stringstream ss;
    ss << f.rdbuf();
    return ss.str();
}

int main(int argc, char** argv) {
    const fs::path dir = argc > 1 ? argv[1] : "shaders_qrhi";
    if (!fs::exists(dir)) {
        std::printf("shader dir not found: %s\n", dir.string().c_str());
        return 1;
    }

    int checked = 0, bad = 0;
    for (const auto& e : fs::directory_iterator(dir)) {
        const std::string name = e.path().filename().string();
        const std::string suffix = ".layout.json";
        if (name.size() <= suffix.size() ||
            name.compare(name.size() - suffix.size(), suffix.size(), suffix) != 0)
            continue;

        const std::string id = name.substr(0, name.size() - suffix.size());
        const fs::path man = dir / (id + ".manifest.json");
        if (!fs::exists(man)) continue;        // engine-internal pass, no UI

        const auto slots = json_array(slurp(e.path()), "params");
        const auto ui    = uniform_names(slurp(man));
        ++checked;

        if (ui.size() > slots.size()) {
            std::printf("FAIL %-14s manifest has %zu params, shader has %zu\n",
                        id.c_str(), ui.size(), slots.size());
            ++bad;
            continue;
        }
        for (size_t i = 0; i < ui.size(); ++i) {
            if (ui[i] != slots[i]) {
                std::printf("FAIL %-14s slot %zu: manifest '%s' vs shader '%s'\n",
                            id.c_str(), i, ui[i].c_str(), slots[i].c_str());
                ++bad;
                break;
            }
        }
    }

    std::printf("%d shader manifests checked, %d mismatched\n", checked, bad);
    return bad == 0 ? 0 : 1;
}
