#include "audioprovider.hpp"

#include <qloggingcategory.h>
#include <qthread.h>

#include "audiocollector.hpp"
#include "service.hpp"

namespace {

Q_LOGGING_CATEGORY(lcAp, "caelestia.services.ap", QtInfoMsg)

} // namespace

namespace caelestia::shell::services {

AudioProcessor::AudioProcessor(QObject* parent)
    : QObject(parent) {}

AudioProcessor::~AudioProcessor() {
    stop();
}

void AudioProcessor::init() {
    m_timer = new QTimer(this);
    m_timer->setInterval(static_cast<int>(ac::k_chunkSize * 1000.0 / ac::k_sampleRate));
    connect(m_timer, &QTimer::timeout, this, &AudioProcessor::process);
}

void AudioProcessor::start() {
    m_started = true;
    QMetaObject::invokeMethod(&AudioCollector::instance(), &AudioCollector::ref, Qt::QueuedConnection, this);
    if (m_timer) {
        m_timer->start();
    }
}

void AudioProcessor::stop() {
    if (m_timer) {
        m_timer->stop();
    }
    if (m_started) {
        m_started = false;
        QMetaObject::invokeMethod(&AudioCollector::instance(), &AudioCollector::unref, Qt::QueuedConnection, this);
    }
}

AudioProvider::AudioProvider(QObject* parent)
    : Service(parent)
    , m_processor(nullptr)
    , m_thread(nullptr) {}

AudioProvider::~AudioProvider() {
    if (m_thread) {
        m_thread->quit();
        m_thread->wait();
    } else {
        // The processor thread was never needed, so we own the processor directly
        delete m_processor;
    }
}

void AudioProvider::init() {
    if (!m_processor) {
        qCWarning(lcAp) << "init: attempted to init with no processor set";
        return;
    }

    m_thread = new QThread(this);
    m_thread->setObjectName(QStringLiteral("caelestia-audio"));
    m_processor->moveToThread(m_thread);

    connect(m_thread, &QThread::started, m_processor, &AudioProcessor::init);
    connect(m_thread, &QThread::finished, m_processor, &AudioProcessor::deleteLater);
    connect(m_thread, &QThread::finished, m_thread, &QThread::deleteLater);

    m_thread->start();
}

void AudioProvider::start() {
    if (!m_processor) {
        return;
    }

    AudioCollector::instance(); // Create instance on main thread
    if (!m_thread) {
        // Defer the processor thread, its timer and its DSP plans until something actually uses audio
        prepareProcessor();
        init();
    }
    QMetaObject::invokeMethod(m_processor, &AudioProcessor::start);
}

void AudioProvider::stop() {
    if (m_processor && m_thread) {
        QMetaObject::invokeMethod(m_processor, &AudioProcessor::stop);
    }
}

} // namespace caelestia::shell::services
