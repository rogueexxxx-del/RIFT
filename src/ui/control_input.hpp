// ControlInput - external controllers: MIDI CC in, and OSC over UDP.
//
// Both sources normalise to the same thing: a string key identifying the
// control ("cc:74", "/rift/blur") plus a 0..1 value. Everything downstream
// (learn mode, the mapping table) works on that pair, so adding a source later
// means emitting the same signal.
//
// MIDI uses winmm directly rather than a library: it is part of Windows, and
// the alternative was another multi-hour vcpkg build for one small feature.
// OSC is parsed inline - the format is a few dozen lines and the prototype's
// parser (core/osc_server.py) is the reference.
//
// Threading: the MIDI callback fires on a system thread, so it marshals to the
// GUI thread before emitting. OSC arrives on the Qt event loop already.
#pragma once
#include <QObject>
#include <QStringList>
#include <memory>

class QUdpSocket;

class ControlInput : public QObject {
    Q_OBJECT
public:
    explicit ControlInput(QObject* parent = nullptr);
    ~ControlInput() override;

    QStringList midiDevices() const;          // names, index = device id
    bool openMidi(int deviceIndex);           // false if unavailable
    void closeMidi();
    int  openMidiIndex() const { return midi_index_; }
    QString openMidiName() const { return midi_name_; }

    bool startOsc(quint16 port);              // false if the port is taken
    void stopOsc();
    quint16 oscPort() const { return osc_port_; }

signals:
    // key: "cc:<n>" or an OSC address. value normalised to 0..1.
    void controlReceived(const QString& key, qreal value);

private slots:
    void onOscDatagram();

public:
    // Called from the MIDI system thread; re-emit on the GUI thread.
    void postMidiCC(int cc, int value);
    void postMidiNote(int note, int velocity);

private:
    struct Midi;
    std::unique_ptr<Midi> midi_;
    int midi_index_ = -1;
    QString midi_name_;

    QUdpSocket* osc_ = nullptr;
    quint16     osc_port_ = 0;
};
