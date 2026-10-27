#include "beattracker.hpp"

#include "audiocollector.hpp"
#include "audioprovider.hpp"

namespace caelestia::shell::services {

BeatProcessor::BeatProcessor(QObject* parent)
    : AudioProcessor(parent)
    , m_tempo(nullptr)
    , m_in(nullptr)
    , m_out(nullptr) {};

void BeatProcessor::prepare() {
    if (!m_tempo) {
        m_tempo = new_aubio_tempo("default", 1024, ac::k_chunkSize, ac::k_sampleRate);
    }
    if (!m_in) {
        m_in = new_fvec(ac::k_chunkSize);
    }
    if (!m_out) {
        m_out = new_fvec(2);
    }
}

BeatProcessor::~BeatProcessor() {
    if (m_tempo) {
        del_aubio_tempo(m_tempo);
    }
    if (m_in) {
        del_fvec(m_in);
    }
    if (m_out) {
        del_fvec(m_out);
    }
}

void BeatProcessor::process() {
    if (!m_tempo || !m_in || !m_out) {
        return;
    }

    // Digital silence cannot contain a beat; skip the FFT chain until new signal arrives
    auto& collector = AudioCollector::instance();
    const quint64 chunk = collector.chunkGeneration();
    if (chunk == m_lastChunk) {
        return;
    }
    m_lastChunk = chunk;

    const quint64 signal = collector.signalGeneration();
    if (signal == m_lastSignal) {
        return;
    }
    m_lastSignal = signal;

    collector.readChunk(m_in->data);

    aubio_tempo_do(m_tempo, m_in, m_out);
    if (!qFuzzyIsNull(m_out->data[0])) {
        emit beat(aubio_tempo_get_bpm(m_tempo));
    }
}

BeatTracker::BeatTracker(QObject* parent)
    : AudioProvider(parent)
    , m_bpm(120) {
    m_processor = new BeatProcessor();

    connect(static_cast<BeatProcessor*>(m_processor), &BeatProcessor::beat, this, &BeatTracker::updateBpm);
}

void BeatTracker::prepareProcessor() {
    static_cast<BeatProcessor*>(m_processor)->prepare();
}

smpl_t BeatTracker::bpm() const {
    return m_bpm;
}

void BeatTracker::updateBpm(smpl_t bpm) {
    if (!qFuzzyCompare(bpm + 1.0f, m_bpm + 1.0f)) {
        m_bpm = bpm;
        emit bpmChanged();
    }
}

} // namespace caelestia::shell::services
