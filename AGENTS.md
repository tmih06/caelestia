# Working in Caelestia

This repository can be the user's running desktop shell, not an isolated app.

The contributor guide is the source of truth for project workflows:

- **Before editing code:** read [Safe workflow](.github/CONTRIBUTING.md#safe-workflow) and [Build and run](.github/CONTRIBUTING.md#build-and-run). Confirm which checkout and native libraries the running instance uses.
- **Finding ownership:** use the [Code map](.github/CONTRIBUTING.md#code-map); extend the existing shared component or service rather than creating another implementation.
- **Changing QML or UI behavior:** read [Rendering and dashboard invariants](.github/CONTRIBUTING.md#rendering-and-dashboard-invariants), including cached-page activation and shared media morphing.
- **Changing services, C++, or performance:** read [Resource lifecycle](.github/CONTRIBUTING.md#resource-lifecycle) before changing polling, worker shutdown, caching, or ownership.
- **Before handing off:** use [Validation](.github/CONTRIBUTING.md#validation) and [Delivery](.github/CONTRIBUTING.md#delivery). Distinguish actual-shell evidence from isolated probes and unavailable hardware.

For installation dependencies and user-facing configuration, see [README.md](README.md). Keep detailed guidance in the contributor guide rather than duplicating it here.
