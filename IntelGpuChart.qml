import QtQuick
import QtQuick.Shapes
import qs.Common
import qs.Widgets

// Reusable 0..1 progress chart: bar | gauge | donut | pie | thermometer.
// Uses cheap Rectangles (bar/thermometer) and GPU-accelerated QtQuick.Shapes
// (gauge/donut/pie) — no Canvas, so it doesn't rasterize on the CPU every update.
Item {
    id: root

    property string chartType: "gauge"
    property real progress: 0            // 0..1
    property color fillColor: "#8ab4f8"
    property color trackColor: Qt.rgba(fillColor.r, fillColor.g, fillColor.b, 0.18)
    property real lineWidth: Math.max(2, Math.round(Math.min(width, height) * 0.12))
    property real barThickness: 0.35     // 0..1 cross-axis thickness for bar / hbar
    property string labelIcon: ""        // Material Symbol name shown inside the chart
    property string labelText: ""        // 1–2 char letter shown inside the chart
    property bool labelTop: false        // anchor the label to the top (linear types) vs center

    readonly property real p: Math.max(0, Math.min(1, progress))
    // gauge/donut have empty centers → use the accent; the filled/linear types put
    // the element through the center → use the neutral text color for legibility.
    readonly property bool _labelHollow: chartType === "gauge" || chartType === "donut"

    Loader {
        anchors.fill: parent
        sourceComponent: {
            switch (root.chartType) {
            case "bar": return barComp;
            case "hbar": return hbarComp;
            case "thermometer": return thermoComp;
            case "pie": return pieComp;
            case "donut": return donutComp;
            default: return gaugeComp;
            }
        }
    }

    // ---- In-chart label (icon or letter), centered -------------------------
    Item {
        anchors.fill: parent
        visible: root.labelIcon.length > 0 || root.labelText.length > 0
        readonly property color lc: root._labelHollow ? root.fillColor : Theme.widgetTextColor

        // Horizontal-center anchored; vertical position via explicit y so we never
        // mix top/verticalCenter anchors (which QML can drop, dumping the item at 0,0).
        DankIcon {
            id: labelIconItem
            visible: root.labelIcon.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.labelTop ? 0 : Math.round((parent.height - height) / 2)
            name: root.labelIcon
            size: Math.round(Math.min(parent.width, parent.height) * (root.labelTop ? 0.42 : 0.52))
            color: parent.lc
        }
        StyledText {
            id: labelTextItem
            visible: root.labelIcon.length === 0 && root.labelText.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.labelTop ? 0 : Math.round((parent.height - height) / 2)
            text: root.labelText
            font.pixelSize: Math.round(Math.min(parent.width, parent.height) * (root.labelTop ? 0.42 : 0.5))
            font.weight: Font.Bold
            color: parent.lc
        }
    }

    // ---- VERTICAL BAR: column of barThickness width, fills from the bottom --
    Component {
        id: barComp
        Item {
            anchors.fill: parent
            readonly property real colW: Math.max(3, width * root.barThickness)
            Rectangle {
                width: parent.colW
                height: parent.height
                radius: width / 2
                anchors.horizontalCenter: parent.horizontalCenter
                color: root.trackColor
                Rectangle {
                    width: parent.width
                    height: Math.max(root.p > 0 ? parent.width : 0, parent.height * root.p)
                    radius: parent.radius
                    anchors.bottom: parent.bottom
                    color: root.fillColor
                }
            }
        }
    }

    // ---- HORIZONTAL BAR: bar of barThickness height, fills from the left ----
    Component {
        id: hbarComp
        Item {
            anchors.fill: parent
            readonly property real barH: Math.max(3, height * root.barThickness)
            Rectangle {
                width: parent.width
                height: parent.barH
                radius: height / 2
                anchors.verticalCenter: parent.verticalCenter
                color: root.trackColor
                Rectangle {
                    width: Math.max(root.p > 0 ? parent.height : 0, parent.width * root.p)
                    height: parent.height
                    radius: parent.radius
                    color: root.fillColor
                }
            }
        }
    }

    // ---- THERMOMETER: bulb + stem ------------------------------------------
    Component {
        id: thermoComp
        Item {
            id: th
            anchors.fill: parent
            readonly property real bulbR: Math.max(4, Math.min(width, height) * 0.16)
            readonly property real tubeW: Math.max(4, bulbR * 0.9)
            readonly property real topY: Math.max(2, height * 0.06)
            readonly property real bulbCy: height - bulbR - 1

            // Track: stem + bulb.
            Rectangle {
                x: th.width / 2 - th.tubeW / 2
                y: th.topY
                width: th.tubeW
                height: th.bulbCy - th.topY
                radius: th.tubeW / 2
                color: root.trackColor
            }
            Rectangle {
                x: th.width / 2 - th.bulbR
                y: th.bulbCy - th.bulbR
                width: th.bulbR * 2
                height: th.bulbR * 2
                radius: th.bulbR
                color: root.trackColor
            }
            // Fill: bulb always filled + stem up to p.
            Rectangle {
                x: th.width / 2 - th.bulbR
                y: th.bulbCy - th.bulbR
                width: th.bulbR * 2
                height: th.bulbR * 2
                radius: th.bulbR
                color: root.fillColor
            }
            Rectangle {
                readonly property real fh: Math.max(0, (th.bulbCy - th.topY) * root.p)
                x: th.width / 2 - th.tubeW / 2
                width: th.tubeW
                y: th.bulbCy - fh
                height: fh
                radius: th.tubeW / 2
                color: root.fillColor
            }
        }
    }

    // ---- GAUGE: 270° arc with a gap at the bottom --------------------------
    Component {
        id: gaugeComp
        Shape {
            id: g
            anchors.fill: parent
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer
            readonly property real cx: width / 2
            readonly property real cy: height / 2
            readonly property real r: Math.max(1, Math.min(width, height) / 2 - root.lineWidth)

            ShapePath {
                strokeColor: root.trackColor
                strokeWidth: root.lineWidth
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: g.cx; centerY: g.cy; radiusX: g.r; radiusY: g.r; startAngle: 135; sweepAngle: 270 }
            }
            ShapePath {
                strokeColor: root.fillColor
                strokeWidth: root.lineWidth
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: g.cx; centerY: g.cy; radiusX: g.r; radiusY: g.r; startAngle: 135; sweepAngle: 270 * root.p }
            }
        }
    }

    // ---- DONUT: full ring --------------------------------------------------
    Component {
        id: donutComp
        Shape {
            id: d
            anchors.fill: parent
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer
            readonly property real cx: width / 2
            readonly property real cy: height / 2
            readonly property real r: Math.max(1, Math.min(width, height) / 2 - root.lineWidth)

            ShapePath {
                strokeColor: root.trackColor
                strokeWidth: root.lineWidth
                fillColor: "transparent"
                PathAngleArc { centerX: d.cx; centerY: d.cy; radiusX: d.r; radiusY: d.r; startAngle: 0; sweepAngle: 360 }
            }
            ShapePath {
                strokeColor: root.fillColor
                strokeWidth: root.lineWidth
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: d.cx; centerY: d.cy; radiusX: d.r; radiusY: d.r; startAngle: -90; sweepAngle: 360 * root.p }
            }
        }
    }

    // ---- PIE: filled sector ------------------------------------------------
    Component {
        id: pieComp
        Shape {
            id: pie
            anchors.fill: parent
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer
            readonly property real cx: width / 2
            readonly property real cy: height / 2
            readonly property real r: Math.max(1, Math.min(width, height) / 2 - 1)

            ShapePath {
                fillColor: root.trackColor
                strokeColor: "transparent"
                strokeWidth: 0
                PathAngleArc { centerX: pie.cx; centerY: pie.cy; radiusX: pie.r; radiusY: pie.r; startAngle: 0; sweepAngle: 360 }
            }
            ShapePath {
                fillColor: root.fillColor
                strokeColor: "transparent"
                strokeWidth: 0
                startX: pie.cx
                startY: pie.cy
                PathAngleArc { centerX: pie.cx; centerY: pie.cy; radiusX: pie.r; radiusY: pie.r; startAngle: -90; sweepAngle: 360 * root.p; moveToStart: false }
                PathLine { x: pie.cx; y: pie.cy }
            }
        }
    }
}
