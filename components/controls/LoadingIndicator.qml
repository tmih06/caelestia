import QtQuick
import Quickshell
import M3Shapes
import qs.components
import qs.services

MaterialShape {
    id: root

    property list<int> shapes: {
        if (containsIcon)
            return [MaterialShape.SoftBurst, MaterialShape.Cookie9Sided, MaterialShape.Pill, MaterialShape.Sunny, MaterialShape.Cookie4Sided, MaterialShape.Oval];
        return [MaterialShape.SoftBurst, MaterialShape.Cookie9Sided, MaterialShape.Pentagon, MaterialShape.Pill, MaterialShape.Sunny, MaterialShape.Cookie4Sided, MaterialShape.Oval];
    }
    property int shapeIndex
    property real cRotation
    property real lRotation
    property real thisLRotation
    property bool containsIcon

    property bool animated: true
    property int morphAnimRotation: 60
    property real morphScale: 0.14
    property alias rotateAnimDuration: rotateAnim.duration

    property real stiffness: 180
    property real dampingRatio: 0.6
    property real visibilityThreshold: 0.075

    readonly property bool animationActive: animated && visible && enabled && opacity > 0
    readonly property real naturalFrequency: Math.sqrt(stiffness)
    readonly property real decayRate: dampingRatio * naturalFrequency
    readonly property real dampedFrequency: naturalFrequency * Math.sqrt(1 - dampingRatio * dampingRatio)
    readonly property real springDuration: Math.log(visibilityThreshold * Math.sqrt(1 - dampingRatio * dampingRatio)) / -decayRate
    readonly property real springMaxVelocity: naturalFrequency * Math.exp(-dampingRatio * Math.acos(dampingRatio) / Math.sqrt(1 - dampingRatio * dampingRatio))
    property bool springSettled: true

    implicitSize: 38
    color: Colours.palette.m3primary
    toShape: shapes[0]

    ElapsedTimer {
        id: timer
    }

    FrameAnimation {
        running: root.animationActive && !root.springSettled
        onTriggered: {
            const t = timer.elapsed();

            if (t >= root.springDuration) {
                root.springSettled = true;
            } else {
                const angle = root.dampedFrequency * t;
                const decay = Math.exp(-root.decayRate * t);
                const pos = 1 - decay * (Math.cos(angle) + root.decayRate / root.dampedFrequency * Math.sin(angle));
                const vel = decay * root.stiffness / root.dampedFrequency * Math.sin(angle);
                root.morphProgress = Math.min(1, pos); // Overshooting the morph looks weird
                root.thisLRotation = pos * root.morphAnimRotation;
                root.scale = 1 + vel * root.morphScale / root.springMaxVelocity;
            }
        }
    }

    Timer {
        interval: 650
        repeat: true
        triggeredOnStart: true
        running: root.animationActive
        onTriggered: {
            root.beginBatchUpdate();
            root.fromShape = root.toShape;
            root.shapeIndex = (root.shapeIndex + 1) % root.shapes.length;
            root.toShape = root.shapes[root.shapeIndex];
            root.morphProgress = 0;

            root.rotation = root.rotation;
            root.lRotation = (root.lRotation + root.thisLRotation) % 360;
            root.thisLRotation = 0;
            root.rotation = Qt.binding(() => root.cRotation + root.lRotation + root.thisLRotation);

            root.springSettled = false;
            timer.restart();
            root.endBatchUpdate();
        }
    }

    RotationAnimation on cRotation {
        id: rotateAnim

        running: root.animated
        paused: running && !root.animationActive
        from: 0
        to: 360
        easing.type: Easing.Linear
        loops: Animation.Infinite
        duration: 4666
    }

    Behavior on color {
        CAnim {}
    }
}
