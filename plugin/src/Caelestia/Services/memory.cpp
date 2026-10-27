#include "memory.hpp"

#include <qbytearrayview.h>
#include <qfile.h>

#include <charconv>
#include <optional>
#include <system_error>

namespace caelestia::shell::services {

using Qt::StringLiterals::operator""_s;

namespace {

[[nodiscard]] std::optional<quint64> parseFirstNumber(QByteArrayView line) {
    const char* pos = line.constData();
    const char* const end = pos + line.size();
    while (pos < end && (*pos == ' ' || *pos == '\t')) {
        ++pos;
    }

    quint64 value = 0;
    const auto [next, ec] = std::from_chars(pos, end, value);
    if (ec != std::errc{}) {
        return std::nullopt;
    }
    return value;
}

} // namespace

Memory::Memory(QObject* parent)
    : TickingService(parent) {}

qreal Memory::used() const {
    return m_used;
}

qreal Memory::total() const {
    return m_total;
}

qreal Memory::percentage() const {
    return m_total > 0.0 ? m_used / m_total : 0.0;
}

void Memory::tick() {
    QFile f(u"/proc/meminfo"_s);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return;
    }
    const QByteArray data = f.readAll();
    f.close();

    std::optional<quint64> totalKib;
    std::optional<quint64> availKib;

    QByteArrayView remaining(data);
    while (!remaining.isEmpty()) {
        const qsizetype newline = remaining.indexOf('\n');
        const auto line = newline < 0 ? remaining : remaining.first(newline);
        remaining = newline < 0 ? QByteArrayView() : remaining.sliced(newline + 1);

        if (line.startsWith(QByteArrayView("MemTotal:"))) {
            totalKib = parseFirstNumber(line.sliced(9));
        } else if (line.startsWith(QByteArrayView("MemAvailable:"))) {
            availKib = parseFirstNumber(line.sliced(13));
        }
    }

    if (!totalKib || !availKib || *totalKib == 0) {
        return;
    }

    const quint64 total = *totalKib;
    const quint64 usedKib = total > *availKib ? total - *availKib : 0;

    if (total == m_lastTotal && usedKib == m_lastUsed) {
        return;
    }
    m_lastTotal = total;
    m_lastUsed = usedKib;
    m_total = static_cast<qreal>(total);
    m_used = static_cast<qreal>(usedKib);
    emit changed();
}

} // namespace caelestia::shell::services
