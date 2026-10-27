#pragma once

#include <qqmlintegration.h>

#include <cava/cavacore.h>

#include <atomic>
#include <vector>

#include "audioprovider.hpp"

namespace caelestia::shell::services {

class CavaProcessor : public AudioProcessor {
    Q_OBJECT

public:
    explicit CavaProcessor(QObject* parent = nullptr);
    ~CavaProcessor() override;

    void setBars(int bars);

    // Called on the GUI thread once a queued valuesChanged has been consumed
    void clearUpdatePending() noexcept { m_updatePending.store(false, std::memory_order_release); }

signals:
    // const-ref so emitting does not copy into the signal parameter; only the queued event
    // holds the immutable snapshot passed to the GUI thread.
    void valuesChanged(const QVector<double>& values);

protected:
    void process() override;

private:
    struct cava_plan* m_plan;
    double* m_in;
    double* m_out;

    int m_bars;
    std::vector<double> m_publishValues; // Last published values, retained for change detection
    std::vector<double> m_work;          // Reused scratch

    // Skip FFT work while the captured stream is pure digital silence
    quint64 m_lastSignal = 0;
    quint64 m_lastChunk = ~0ull;
    int m_duplicateTicks = 0;
    int m_silentTicks = 0;
    bool m_idle = true;
    // At most one valuesChanged may be queued; newer frames replace it when the GUI thread lags
    std::atomic_bool m_updatePending{ false };

    void reload();
    void initCava();
    void cleanup();
};

class CavaProvider : public AudioProvider {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(int bars READ bars WRITE setBars NOTIFY barsChanged)

    Q_PROPERTY(QVector<double> values READ values NOTIFY valuesChanged)

public:
    explicit CavaProvider(QObject* parent = nullptr);

    [[nodiscard]] int bars() const;
    void setBars(int bars);

    [[nodiscard]] QVector<double> values() const;

signals:
    void barsChanged();
    void valuesChanged();

protected:
    void prepareProcessor() override;

private:
    int m_bars;
    QVector<double> m_values;

    void updateValues(const QVector<double>& values);
};

} // namespace caelestia::shell::services
