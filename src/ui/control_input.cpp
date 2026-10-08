#include "control_input.hpp"
#include <QUdpSocket>
#include <QNetworkDatagram>
#include <QMetaObject>
#include <QtEndian>

#ifdef Q_OS_WIN
#  include <windows.h>
#  include <mmsystem.h>
#endif

struct ControlInput::Midi {
#ifdef Q_OS_WIN
    HMIDIIN handle = nullptr;
#endif
};

#ifdef Q_OS_WIN
// System thread. Do the minimum here and hand off - anything slow in a MIDI
// callback shows up as input latency.
static void CALLBACK midiProc(HMIDIIN, UINT msg, DWORD_PTR inst,
                              DWORD_PTR p1, DWORD_PTR) {
    if (msg != MIM_DATA) return;
    auto* self = reinterpret_cast<ControlInput*>(inst);
    if (!self) return;

    const int status = int(p1 & 0xF0);
    const int data1  = int((p1 >> 8)  & 0x7F);
    const int data2  = int((p1 >> 16) & 0x7F);

    if (status == 0xB0) {                       // knob / fader
        self->postMidiCC(data1, data2);
    } else if (status == 0x90) {                // pad or key down
        // Velocity as the value, so a pad can drive a parameter and not
        // just fire. Note-on with velocity 0 is note-off on most hardware.
        self->postMidiNote(data1, data2);
    } else if (status == 0x80) {                // pad or key up
        self->postMidiNote(data1, 0);
    }
}
#endif

ControlInput::ControlInput(QObject* parent)
    : QObject(parent), midi_(std::make_unique<Midi>()) {}

ControlInput::~ControlInput() {
    closeMidi();
    stopOsc();
}

QStringList ControlInput::midiDevices() const {
    QStringList out;
#ifdef Q_OS_WIN
    const UINT n = midiInGetNumDevs();
    for (UINT i = 0; i < n; ++i) {
        MIDIINCAPSW caps{};
        if (midiInGetDevCapsW(i, &caps, sizeof(caps)) == MMSYSERR_NOERROR)
            out << QString::fromWCharArray(caps.szPname);
        else
            out << QStringLiteral("MIDI %1").arg(i);
    }
#endif
    return out;
}

bool ControlInput::openMidi(int deviceIndex) {
#ifdef Q_OS_WIN
    closeMidi();
    if (deviceIndex < 0 || deviceIndex >= int(midiInGetNumDevs())) return false;

    // Remember the name: the UI picks a controller layout from it.
    MIDIINCAPSW caps{};
    if (midiInGetDevCapsW(UINT(deviceIndex), &caps, sizeof(caps)) == MMSYSERR_NOERROR)
        midi_name_ = QString::fromWCharArray(caps.szPname);

    HMIDIIN h = nullptr;
    if (midiInOpen(&h, UINT(deviceIndex), reinterpret_cast<DWORD_PTR>(midiProc),
                   reinterpret_cast<DWORD_PTR>(this), CALLBACK_FUNCTION)
        != MMSYSERR_NOERROR)
        return false;
    if (midiInStart(h) != MMSYSERR_NOERROR) { midiInClose(h); return false; }

    midi_->handle = h;
    midi_index_ = deviceIndex;
    return true;
#else
    (void)deviceIndex;
    return false;
#endif
}

void ControlInput::closeMidi() {
    midi_name_.clear();
#ifdef Q_OS_WIN
    if (midi_ && midi_->handle) {
        midiInStop(midi_->handle);
        midiInClose(midi_->handle);
        midi_->handle = nullptr;
    }
#endif
    midi_index_ = -1;
}

void ControlInput::postMidiNote(int note, int velocity) {
    const QString key = QStringLiteral("note:%1").arg(note);
    const qreal v = velocity / 127.0;
    QMetaObject::invokeMethod(this, [this, key, v] {
        emit controlReceived(key, v);
    }, Qt::QueuedConnection);
}

void ControlInput::postMidiCC(int cc, int value) {
    // Hop to the GUI thread: this runs on the MIDI callback thread, and
    // everything listening touches UI state.
    const QString key = QStringLiteral("cc:%1").arg(cc);
    const qreal v = value / 127.0;
    QMetaObject::invokeMethod(this, [this, key, v] {
        emit controlReceived(key, v);
    }, Qt::QueuedConnection);
}

bool ControlInput::startOsc(quint16 port) {
    stopOsc();
    osc_ = new QUdpSocket(this);
    if (!osc_->bind(QHostAddress::AnyIPv4, port,
                    QUdpSocket::ShareAddress | QUdpSocket::ReuseAddressHint)) {
        delete osc_;
        osc_ = nullptr;
        return false;
    }
    connect(osc_, &QUdpSocket::readyRead, this, &ControlInput::onOscDatagram);
    osc_port_ = port;
    return true;
}

void ControlInput::stopOsc() {
    if (osc_) { osc_->close(); delete osc_; osc_ = nullptr; }
    osc_port_ = 0;
}

// Minimal OSC: address string, ',' type tags, then args - each section padded
// to a 4-byte boundary. Mirrors the prototype's parse_osc().
void ControlInput::onOscDatagram() {
    while (osc_ && osc_->hasPendingDatagrams()) {
        const QByteArray d = osc_->receiveDatagram().data();

        const int addrEnd = d.indexOf('\0');
        if (addrEnd <= 0) continue;
        const QString address = QString::fromLatin1(d.constData(), addrEnd);

        const int typeStart = ((addrEnd / 4) + 1) * 4;
        if (typeStart >= d.size() || d[typeStart] != ',') continue;
        const int typeEnd = d.indexOf('\0', typeStart);
        if (typeEnd < 0) continue;
        const QByteArray tags = d.mid(typeStart + 1, typeEnd - typeStart - 1);

        int idx = ((typeEnd / 4) + 1) * 4;
        // Only the FIRST numeric argument is used: a mapping targets one value.
        for (char t : tags) {
            if (t == 'f' && idx + 4 <= d.size()) {
                quint32 raw = qFromBigEndian<quint32>(
                    reinterpret_cast<const uchar*>(d.constData() + idx));
                float f;
                std::memcpy(&f, &raw, 4);
                emit controlReceived(address, qBound(0.0, double(f), 1.0));
                break;
            }
            if (t == 'i' && idx + 4 <= d.size()) {
                const qint32 v = qFromBigEndian<qint32>(
                    reinterpret_cast<const uchar*>(d.constData() + idx));
                // Ints arrive from buttons/steps; treat 0..127 like a CC.
                emit controlReceived(address, qBound(0.0, v / 127.0, 1.0));
                break;
            }
            idx += 4;      // skip other 4-byte types
        }
    }
}
