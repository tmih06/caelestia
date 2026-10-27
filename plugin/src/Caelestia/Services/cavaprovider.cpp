#include "cavaprovider.hpp"

#include <qloggingcategory.h>

#include <cava/cavacore.h>

#include <algorithm>
#include <cstddef>

#include "audiocollector.hpp"
#include "audioprovider.hpp"

namespace {

Q_LOGGING_CATEGORY(lcCava, "caelestia.services.cava", QtInfoMsg)
Q_LOGGING_CATEGORY(lcCavaProcessor, "caelestia.services.cava.processor", QtInfoMsg)

// ~6s of digital silence without an audible bar is indistinguishable from the visualiser's own
// decay. After that we can stop running the FFT chain until new signal arrives.
constexpr int k_idleTicks = 512;
constexpr double k_silentValue = 1e-4;

} // namespace

namespace caelestia::shell::services {

CavaProcessor::CavaProcessor(QObject* parent)
    : AudioProcessor(parent)
    , m_plan(nullptr)
    , m_in(new double[ac::k_chunkSize])
    , m_out(nullptr)
    , m_bars(0) {};

CavaProcessor::~CavaProcessor() {
    cleanup();
    delete[] m_in;
}

void CavaProcessor::process() {
    if (!m_plan || m_bars == 0 || !m_out) {
        return;
    }

    auto& collector = AudioCollector::instance();

    // The timer is slightly faster than the capture period. Skip the odd duplicate window, but keep
    // processing when the stream stalls so the bars still decay through silence to zero.
    const quint64 chunk = collector.chunkGeneration();
    if (chunk == m_lastChunk) {
        if (m_duplicateTicks < 1) {
            ++m_duplicateTicks;
            return;
        }
    } else {
        m_lastChunk = chunk;
        m_duplicateTicks = 0;
    }

    const quint64 signal = collector.signalGeneration();
    if (signal != m_lastSignal) {
        m_lastSignal = signal;
        m_silentTicks = 0;
        m_idle = false;
    } else if (m_idle) {
        return;
    } else {
        if (m_silentTicks < k_idleTicks) {
            ++m_silentTicks;
        }
        if (m_silentTicks >= k_idleTicks) {
            const auto peak = m_work.empty() ? 0.0 : std::ranges::max(m_work);
            if (peak < k_silentValue) {
                // The animation has fully decayed; pin it to zero and stop doing work until audio resumes
                if (!m_publishValues.empty() && std::ranges::any_of(m_publishValues, [](double v) {
                        return v > 0.0;
                    })) {
                    m_publishValues.assign(static_cast<size_t>(m_bars), 0.0);
                    emit valuesChanged(QVector<double>(static_cast<qsizetype>(m_bars), 0.0));
                }
                m_idle = true;
                return;
            }
        }
    }

    const int count = static_cast<int>(collector.readChunk(m_in));

    // Process in data via cava
    cava_execute(m_in, count, m_out, m_plan);

    // Filter into the reusable scratch buffer
    if (m_work.size() != static_cast<size_t>(m_bars)) {
        m_work.resize(static_cast<size_t>(m_bars));
    }

    // Left to right pass
    const double inv = 1.0 / 1.5;
    double carry = 0.0;
    for (int i = 0; i < m_bars; ++i) {
        carry = std::max(m_out[i], carry * inv);
        m_work[static_cast<size_t>(i)] = carry;
    }

    // Right to left pass and combine
    carry = 0.0;
    for (int i = m_bars - 1; i >= 0; --i) {
        carry = std::max(m_out[i], carry * inv);
        const auto index = static_cast<size_t>(i);
        m_work[index] = std::max(m_work[index], carry);
    }

    // Update values. Only one update may be queued at a time so a slow GUI thread drops
    // intermediate frames instead of building a backlog; the newest values are sent next tick.
    // The retained snapshot is plain storage, and the queued QVector is a fresh immutable copy:
    // publishing never causes a later scratch write to detach shared storage.
    if (!std::ranges::equal(m_work, m_publishValues) && !m_updatePending.exchange(true, std::memory_order_acq_rel)) {
        if (m_publishValues.size() != m_work.size()) {
            m_publishValues.resize(m_work.size());
        }
        std::copy(m_work.begin(), m_work.end(), m_publishValues.begin());
        emit valuesChanged(QVector<double>(m_work.begin(), m_work.end()));
    }
}

void CavaProcessor::setBars(int bars) {
    if (bars < 0) {
        qCWarning(lcCavaProcessor) << "setBars: bars must be greater than 0. Setting to 0.";
        bars = 0;
    }

    if (m_bars != bars) {
        m_bars = bars;
        reload();
    }
}

void CavaProcessor::reload() {
    cleanup();
    initCava();
}

void CavaProcessor::cleanup() {
    if (m_plan) {
        cava_destroy(m_plan);
        m_plan = nullptr;
    }

    if (m_out) {
        delete[] m_out;
        m_out = nullptr;
    }
}

void CavaProcessor::initCava() {
    if (m_plan || m_bars == 0) {
        return;
    }

    m_plan = cava_init(m_bars, ac::k_sampleRate, 1, 1, 0.85, 50, 10000);
    m_out = new double[static_cast<size_t>(m_bars)];
    m_work.assign(static_cast<size_t>(m_bars), 0.0);
    m_publishValues.assign(static_cast<size_t>(m_bars), 0.0);
}

CavaProvider::CavaProvider(QObject* parent)
    : AudioProvider(parent)
    , m_bars(0)
    , m_values(m_bars, 0.0) {
    m_processor = new CavaProcessor();

    connect(static_cast<CavaProcessor*>(m_processor), &CavaProcessor::valuesChanged, this, &CavaProvider::updateValues);
}

void CavaProvider::prepareProcessor() {
    static_cast<CavaProcessor*>(m_processor)->setBars(m_bars);
}

int CavaProvider::bars() const {
    return m_bars;
}

void CavaProvider::setBars(int bars) {
    if (bars < 0) {
        qCWarning(lcCava) << "setBars: bars must be greater than 0. Setting to 0.";
        bars = 0;
    }

    if (m_bars == bars) {
        return;
    }

    m_values.resize(bars, 0.0);
    m_bars = bars;
    emit barsChanged();
    emit valuesChanged();

    // Before the processor thread exists the pending value is applied by prepareProcessor()
    if (processorThreadStarted()) {
        QMetaObject::invokeMethod(
            static_cast<CavaProcessor*>(m_processor), &CavaProcessor::setBars, Qt::QueuedConnection, bars);
    }
}

QVector<double> CavaProvider::values() const {
    return m_values;
}

void CavaProvider::updateValues(const QVector<double>& values) {
    static_cast<CavaProcessor*>(m_processor)->clearUpdatePending();
    if (values != m_values) {
        m_values = values;
        emit valuesChanged();
    }
}

} // namespace caelestia::shell::services
