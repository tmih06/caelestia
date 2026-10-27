#include "service.hpp"

namespace caelestia::shell::services {

Service::Service(QObject* parent)
    : QObject(parent) {}

void Service::ref(QObject* sender) {
    if (!sender || m_refs.contains(sender)) {
        return;
    }
    if (m_refs.isEmpty()) {
        start();
    }

    QObject::connect(sender, &QObject::destroyed, this, &Service::unref, Qt::UniqueConnection);
    m_refs << sender;
}

void Service::unref(QObject* sender) {
    if (m_refs.remove(sender) && m_refs.isEmpty()) {
        stop();
    }
}

} // namespace caelestia::shell::services
