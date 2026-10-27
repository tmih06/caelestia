pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Services
import qs.services

Item {
    id: root

    property bool running: true
    property real phase: 0
    property var bands: [0, 0, 0, 0, 0]
    property color colour: Colours.palette.m3primary

    // Precomputed per-pixel Gaussian weights (bandCount per column), rebuilt
    // only when the canvas width changes; paints reuse the geometry buffers.
    readonly property int bandCount: 5
    property var envelopeWeights: null
    property var lowerBuffer: null
    property real lastSampleTime: 0

    function rebuildEnvelope(): void {
        const steps = Math.ceil(width);
        const count = root.bandCount;
        const centres = [0.08, 0.29, 0.5, 0.71, 0.92];
        const spread = 0.12;
        const weights = new Float32Array((steps + 1) * count);

        for (let x = 0; x <= steps; x++) {
            const t = x / Math.max(1, width);
            for (let i = 0; i < count; i++) {
                const d = (t - centres[i]) / spread;
                weights[x * count + i] = Math.exp(-d * d);
            }
        }

        root.envelopeWeights = weights;
        root.lowerBuffer = new Float32Array(steps + 1);
    }

    implicitWidth: 32
    implicitHeight: 24

    onRunningChanged: {
        if (running) {
            if (canvas)
                canvas.requestPaint();
        } else {
            // Restart from the historical first-sample response instead of
            // applying a large elapsed-time correction after idling.
            root.lastSampleTime = 0;
        }
    }

    onColourChanged: {
        if (canvas)
            canvas.requestPaint();
    }

    ServiceRef {
        service: root.running ? Audio.cava : null
    }

    Timer {
        interval: 33
        repeat: true
        running: root.running

        onTriggered: {
            root.phase = (root.phase + 0.16) % (Math.PI * 2);

            // Sample cava every repaint and compensate the smoothing by the
            // actual elapsed time so the response matches the historical
            // 0.28@50ms while avoiding a second timer wakeup.
            const now = Date.now();
            const elapsed = root.lastSampleTime === 0 ? 50 : Math.min(250, Math.max(1, now - root.lastSampleTime));
            root.lastSampleTime = now;
            const alpha = 1 - Math.pow(0.72, elapsed / 50);
            const values = Audio.cava.values;
            const count = root.bandCount;
            const next = new Array(count);

            for (let i = 0; i < count; i++) {
                let peak = 0;
                if (values && values.length > 0) {
                    const start = Math.floor(i * values.length / count);
                    const end = Math.max(start + 1, Math.floor((i + 1) * values.length / count));
                    for (let j = start; j < end; j++)
                        peak = Math.max(peak, Math.max(0, Math.min(1, values[j])));
                }
                next[i] = root.bands[i] * (1 - alpha) + peak * alpha;
            }

            root.bands = next;
            canvas.requestPaint();
        }
    }

    Canvas {
        id: canvas

        anchors.fill: parent
        antialiasing: true

        onPaint: {
            const steps = Math.ceil(width);
            const weights = root.envelopeWeights;
            const lower = root.lowerBuffer;
            if (!weights || !lower || lower.length !== steps + 1)
                return;

            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            const bands = root.bands;
            const count = root.bandCount;
            const mid = height / 2;
            const maxAmplitude = Math.min(24, height / 2 - 4);
            const phase = root.phase;

            for (let x = 0; x <= steps; x++) {
                const weightBase = x * count;
                let envelope = 0;
                for (let i = 0; i < count; i++)
                    envelope += bands[i] * weights[weightBase + i];
                envelope = Math.min(1, envelope);

                const t = x / Math.max(1, width);
                const edge = 0.35 + 0.65 * Math.sin(Math.PI * t);
                const ripple = Math.sin(t * Math.PI * 6 + phase * 2) * 1.3;
                const amplitude = Math.max(0.7, (1.2 + envelope * maxAmplitude + ripple) * edge);
                lower[x] = mid + amplitude;
            }

            const rgb = `rgba(${Math.round(root.colour.r * 255)}, ${Math.round(root.colour.g * 255)}, ${Math.round(root.colour.b * 255)},`;

            const gradient = ctx.createLinearGradient(0, 0, 0, height);
            gradient.addColorStop(0, `${rgb} 0)`);
            gradient.addColorStop(0.5, `${rgb} 0.3)`);
            gradient.addColorStop(1, `${rgb} 0)`);

            ctx.beginPath();
            ctx.moveTo(0, mid);
            for (let x = 0; x <= steps; x++)
                ctx.lineTo(x, 2 * mid - lower[x]);
            for (let x = steps; x >= 0; x--)
                ctx.lineTo(x, lower[x]);
            ctx.closePath();
            ctx.fillStyle = gradient;
            ctx.fill();

            ctx.strokeStyle = `${rgb} 0.9)`;
            ctx.lineWidth = 1.5;
            ctx.lineJoin = "round";
            ctx.lineCap = "round";

            ctx.beginPath();
            for (let x = 0; x <= steps; x++) {
                const y = 2 * mid - lower[x];
                if (x === 0)
                    ctx.moveTo(x, y);
                else
                    ctx.lineTo(x, y);
            }
            ctx.stroke();
        }

        onHeightChanged: requestPaint()
        onWidthChanged: {
            root.rebuildEnvelope();
            requestPaint();
        }
        Component.onCompleted: root.rebuildEnvelope()
    }
}
