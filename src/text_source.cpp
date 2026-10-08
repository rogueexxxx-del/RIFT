#include "text_source.hpp"
#include "rhi_context.hpp"

#include <QImage>
#include <QPainter>
#include <QFont>
#include <QFontMetricsF>
#include <QColor>
#include <QString>
#include <cmath>

namespace rift {

TextSource::~TextSource() {
    if (tex_ && rhi_) rhi_->releaseTexture(tex_);
}

uint32_t TextSource::texture(const TextSpec& spec, int w, int h) {
    if (!rhi_ || w <= 0 || h <= 0) return 0;
    if (have_ && tex_ && last_w_ == w && last_h_ == h && spec == last_)
        return tex_;                       // nothing changed: reuse

    QImage img(w, h, QImage::Format_RGBA8888);
    // Transparent, not black: the compositor honours the layer's alpha, so text
    // over footage shows the footage between the glyphs instead of a black box.
    img.fill(Qt::transparent);

    if (!spec.text.empty()) {
        QPainter p(&img);
        p.setRenderHint(QPainter::Antialiasing, true);
        p.setRenderHint(QPainter::TextAntialiasing, true);

        QFont f(spec.font.empty() ? QStringLiteral("Consolas")
                                  : QString::fromStdString(spec.font));
        // Size as a fraction of frame height, so the same project looks the same
        // at 720p and 4K instead of the text shrinking as resolution rises.
        f.setPixelSize(std::max(4, int(spec.size * h)));
        f.setBold(spec.bold);
        if (spec.letterSpacing != 0.0)
            f.setLetterSpacing(QFont::AbsoluteSpacing, spec.letterSpacing);
        p.setFont(f);
        p.setPen(QColor::fromRgbF(spec.r, spec.g, spec.b));

        const QString s = QString::fromStdString(spec.text);
        // Anchor on the CENTRE of the text block at (x, y): moving a caption
        // around the frame should not also change how it is justified.
        const int boxW = spec.wrapWidth > 0.0
                       ? int(spec.wrapWidth * w) : w;
        QFontMetricsF fm(f);
        const QRectF bounds = fm.boundingRect(
            QRectF(0, 0, boxW, h * 4),
            Qt::AlignHCenter | Qt::TextWordWrap, s);

        const QRectF box(spec.x * w - bounds.width() / 2.0,
                         spec.y * h - bounds.height() / 2.0,
                         bounds.width(), bounds.height());
        p.drawText(box, Qt::AlignHCenter | Qt::AlignVCenter | Qt::TextWordWrap, s);
        p.end();
    }

    // uploadMedia flips rows on the way in (decoded frames arrive top-down while
    // the fullscreen quad samples v=0 at the bottom). QImage is top-down too, so
    // it goes through the same call and lands the same way up.
    tex_ = rhi_->uploadMedia(tex_, img.constBits(), w, h);
    last_ = spec; last_w_ = w; last_h_ = h; have_ = true;
    return tex_;
}

} // namespace rift
