pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import M3Shapes
import Caelestia
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.widgets
import qs.services

Item {
    id: root

    property bool sharedMedia: false
    property bool animating: true

    readonly property real centerX: width / 2
    readonly property real centerY: height / 2
    readonly property real spacing: Tokens.spacing.medium
    readonly property real maxMagnitude: (implicitWidth - cover.implicitWidth) / 2 - spacing

    function updateValues(): void {
        if (!animating)
            return;
        const values = Audio.cava.values;
        const paths = bars.instances;
        for (let i = 0; i < paths.length; i++)
            paths[i].value = Math.max(1e-2, Math.min(1, values[i] ?? 0));
    }

    objectName: "dockMorphWave"

    onAnimatingChanged: updateValues()
    Component.onCompleted: updateValues()

    Connections {
        function onValuesChanged(): void {
            root.updateValues();
        }

        target: Audio.cava
        enabled: root.animating
    }

    ServiceRef {
        service: root.enabled && root.visible && (Players.active?.isPlaying ?? false) ? Audio.cava : null
    }

    Shape {
        anchors.fill: parent
        asynchronous: true
        preferredRendererType: Shape.CurveRenderer
        data: bars.instances
    }

    Variants {
        id: bars

        model: Array.from({
            length: GlobalConfig.services.visualiserBars
        }, (_, i) => i)

        ShapePath {
            id: bar

            required property int modelData
            property real value: 1e-2

            readonly property real angle: modelData * 2 * Math.PI / GlobalConfig.services.visualiserBars
            readonly property real dist: shapeEdgeDist + value * root.maxMagnitude
            readonly property real shapeEdgeDist: {
                const shape = coverArt.item?.shape;
                if (root.sharedMedia || !shape)
                    return cover.width / 2 + root.spacing + strokeWidth / 2;
                CUtils.dependency(shape.rotation);
                return shape.distanceAtAngle(modelData * 360 / GlobalConfig.services.visualiserBars + 90) + root.spacing + strokeWidth / 2;
            }
            readonly property real cos: Math.cos(angle)
            readonly property real sin: Math.sin(angle)

            asynchronous: true
            capStyle: root.Tokens.rounding.scale === 0 ? ShapePath.SquareCap : ShapePath.RoundCap
            strokeWidth: 360 / GlobalConfig.services.visualiserBars - root.Tokens.spacing.small / 4
            strokeColor: Colours.palette.m3primary

            startX: root.centerX + shapeEdgeDist * cos
            startY: root.centerY + shapeEdgeDist * sin

            PathLine {
                x: root.centerX + bar.dist * bar.cos
                y: root.centerY + bar.dist * bar.sin
            }

            Behavior on strokeColor {
                CAnim {}
            }
        }
    }

    Item {
        id: cover

        objectName: "dockMorphCover"

        anchors.centerIn: parent
        implicitWidth: Tokens.sizes.dashboard.mediaCoverArtSize
        implicitHeight: Tokens.sizes.dashboard.mediaCoverArtSize

        Loader {
            id: coverArt

            anchors.fill: parent
            active: !root.sharedMedia

            sourceComponent: CoverArt {
                animated: root.animating
                shape.shape: MaterialShape.Cookie9Sided
            }
        }
    }
}
