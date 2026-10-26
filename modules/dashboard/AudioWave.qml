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

    implicitWidth: 64
    implicitHeight: 28

    onRunningChanged: {
        if (running && canvas)
            canvas.requestPaint();
    }

    onColourChanged: {
        if (canvas)
            canvas.requestPaint();
    }

    ServiceRef {
        service: Audio.cava
    }

    Timer {
        interval: 50
        repeat: true
        running: root.running

        onTriggered: {
            const values = Audio.cava.values;
            const next = [];
            const count = root.bands.length;

            for (let i = 0; i < count; i++) {
                let peak = 0;
                if (values && values.length > 0) {
                    const start = Math.floor(i * values.length / count);
                    const end = Math.max(start + 1, Math.floor((i + 1) * values.length / count));
                    for (let j = start; j < end; j++)
                        peak = Math.max(peak, Math.max(0, Math.min(1, values[j])));
                }
                next.push(root.bands[i] * 0.72 + peak * 0.28);
            }

            root.bands = next;
        }
    }

    Timer {
        interval: 33
        repeat: true
        running: root.running

        onTriggered: {
            root.phase = (root.phase + 0.16) % (Math.PI * 2);
            canvas.requestPaint();
        }
    }

    Canvas {
        id: canvas

        anchors.fill: parent
        antialiasing: true

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            const centres = [0.08, 0.29, 0.5, 0.71, 0.92];
            const spread = 0.12;
            const mid = height / 2;
            const maxAmplitude = height / 2 - 4;

            function envelope(t) {
                let value = 0;
                for (let i = 0; i < centres.length; i++) {
                    const d = (t - centres[i]) / spread;
                    value += root.bands[i] * Math.exp(-d * d);
                }
                return Math.min(1, value);
            }

            function amplitude(t) {
                const edge = 0.35 + 0.65 * Math.sin(Math.PI * t);
                const ripple = Math.sin(t * Math.PI * 6 + root.phase * 2) * 1.3;
                return Math.max(0.7, (1.2 + envelope(t) * maxAmplitude + ripple) * edge);
            }

            const upper = [];
            const lower = [];
            for (let x = 0; x <= width; x++) {
                const amp = amplitude(x / width);
                upper.push([x, mid - amp]);
                lower.push([x, mid + amp]);
            }

            const rgb = `rgba(${Math.round(root.colour.r * 255)}, ${Math.round(root.colour.g * 255)}, ${Math.round(root.colour.b * 255)},`;

            const gradient = ctx.createLinearGradient(0, 0, 0, height);
            gradient.addColorStop(0, `${rgb} 0)`);
            gradient.addColorStop(0.5, `${rgb} 0.3)`);
            gradient.addColorStop(1, `${rgb} 0)`);

            ctx.beginPath();
            ctx.moveTo(0, mid);
            for (const point of upper)
                ctx.lineTo(point[0], point[1]);
            for (let i = lower.length - 1; i >= 0; i--)
                ctx.lineTo(lower[i][0], lower[i][1]);
            ctx.closePath();
            ctx.fillStyle = gradient;
            ctx.fill();

            ctx.strokeStyle = `${rgb} 0.9)`;
            ctx.lineWidth = 1.5;
            ctx.lineJoin = "round";
            ctx.lineCap = "round";

            ctx.beginPath();
            ctx.moveTo(upper[0][0], upper[0][1]);
            for (let i = 1; i < upper.length; i++)
                ctx.lineTo(upper[i][0], upper[i][1]);
            ctx.stroke();
        }

        onHeightChanged: requestPaint()
        onWidthChanged: requestPaint()
    }
}
