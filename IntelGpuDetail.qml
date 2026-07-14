import QtQuick
import qs.Common
import qs.Widgets

Column {
    id: root

    required property var pluginRoot
    property int maxRows: 12

    readonly property bool isRound: false
    spacing: Theme.spacingM

    function roundType(t) { return t === "gauge" || t === "donut" || t === "pie"; }
    function engineList() {
        const e = root.pluginRoot.engineBusy || {};
        const out = [];
        for (const k in e)
            out.push({ "name": k, "busy": Number(e[k]) || 0 });
        return out;
    }

    // Defer the (GPU-heavier) charts until the popout has finished opening, so
    // the open transition stays smooth on weak GPUs. Numbers show immediately.
    property bool chartsReady: false
    Timer { interval: 280; running: true; repeat: false; onTriggered: root.chartsReady = true }

    // ---- Header -----------------------------------------------------------
    Row {
        width: parent.width
        spacing: Theme.spacingS

        DankIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: "developer_board"
            size: Theme.iconSize
            color: Theme.primary
        }
        Column {
            width: parent.width - Theme.iconSize - Theme.spacingS
            spacing: 0
            StyledText {
                text: "Intel GPU"
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Bold
                color: Theme.surfaceText
            }
            StyledText {
                width: parent.width
                visible: root.pluginRoot.freqMHz >= 0
                text: Math.round(root.pluginRoot.freqMHz) + " MHz"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                elide: Text.ElideRight
            }
        }
    }

    // ---- Big charts -------------------------------------------------------
    Flow {
        width: parent.width
        spacing: Theme.spacingL
        visible: root.pluginRoot.enabledMetrics.length > 0

        Repeater {
            model: root.pluginRoot.enabledMetrics
            delegate: Column {
                id: bigMetric
                required property var modelData
                readonly property string mk: modelData
                width: 96
                spacing: Theme.spacingXS

                Item {
                    width: 84
                    height: 84
                    anchors.horizontalCenter: parent.horizontalCenter

                    Loader {
                        anchors.fill: parent
                        active: root.chartsReady
                        opacity: root.chartsReady ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        sourceComponent: IntelGpuChart {
                            chartType: root.pluginRoot.chartType(bigMetric.mk)
                            progress: root.pluginRoot.metricProgress(bigMetric.mk)
                            fillColor: root.pluginRoot.metricColor(bigMetric.mk)
                            barThickness: root.pluginRoot.barWidthFraction(bigMetric.mk)
                            lineWidth: 8
                        }
                    }
                    StyledText {
                        anchors.centerIn: parent
                        visible: root.roundType(root.pluginRoot.chartType(bigMetric.mk))
                        text: root.pluginRoot.metricValueText(bigMetric.mk)
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: root.pluginRoot.metricColor(bigMetric.mk)
                    }
                }
                StyledText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root.pluginRoot.metricLabel(bigMetric.mk)
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    elide: Text.ElideRight
                }
                StyledText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: !root.roundType(root.pluginRoot.chartType(bigMetric.mk))
                    text: root.pluginRoot.metricValueText(bigMetric.mk)
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Bold
                    color: root.pluginRoot.metricColor(bigMetric.mk)
                }
            }
        }
    }

    // ---- Per-engine breakdown --------------------------------------------
    Flow {
        width: parent.width
        spacing: Theme.spacingM
        visible: engineRepeater.count > 0

        Repeater {
            id: engineRepeater
            model: root.engineList()
            delegate: Row {
                required property var modelData
                spacing: Theme.spacingXS
                StyledText {
                    text: modelData.name
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
                StyledText {
                    text: modelData.busy.toFixed(0) + "%"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }
            }
        }
    }

    // ---- VRAM summary line ------------------------------------------------
    StyledText {
        width: parent.width
        visible: root.pluginRoot.vramSupported
        text: (root.pluginRoot.vramIsDiscrete ? "VRAM (dedicated): " : "GPU memory (shared): ")
              + Math.round(root.pluginRoot.vramUsedMB) + " MB"
              + (root.pluginRoot.vramTotalMB > 0 ? (" / " + Math.round(root.pluginRoot.vramTotalMB) + " MB") : "")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outlineMedium
    }

    // ---- Process table ----------------------------------------------------
    StyledText {
        text: "Processes using the GPU"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    // Column widths (relative).
    QtObject {
        id: cols
        readonly property real gpu: 58
        readonly property real vramMb: 78
        readonly property real vramPct: 54
        readonly property real pid: 56
        readonly property real name: Math.max(80, root.width - gpu - vramMb - vramPct - pid - Theme.spacingS * 4)
    }

    Row {
        width: parent.width
        spacing: Theme.spacingS
        StyledText { width: cols.name; text: "Process"; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium; color: Theme.surfaceVariantText; elide: Text.ElideRight }
        StyledText { width: cols.gpu; text: "GPU %"; horizontalAlignment: Text.AlignRight; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium; color: Theme.surfaceVariantText }
        StyledText { width: cols.vramMb; text: "VRAM"; horizontalAlignment: Text.AlignRight; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium; color: Theme.surfaceVariantText }
        StyledText { width: cols.vramPct; text: "VRAM %"; horizontalAlignment: Text.AlignRight; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium; color: Theme.surfaceVariantText }
        StyledText { width: cols.pid; text: "PID"; horizontalAlignment: Text.AlignRight; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium; color: Theme.surfaceVariantText }
    }

    Repeater {
        model: Math.min(root.maxRows, (root.pluginRoot.clients || []).length)
        delegate: Row {
            id: procRow
            required property int index
            readonly property var proc: root.pluginRoot.clients[index]
            width: root.width
            spacing: Theme.spacingS
            height: procName.implicitHeight + Theme.spacingXS

            StyledText {
                id: procName
                width: cols.name
                anchors.verticalCenter: parent.verticalCenter
                text: procRow.proc ? procRow.proc.name : ""
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                elide: Text.ElideRight
            }
            StyledText {
                width: cols.gpu
                anchors.verticalCenter: parent.verticalCenter
                text: procRow.proc ? procRow.proc.gpu.toFixed(1) + "%" : ""
                horizontalAlignment: Text.AlignRight
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
            }
            StyledText {
                width: cols.vramMb
                anchors.verticalCenter: parent.verticalCenter
                text: procRow.proc ? (procRow.proc.vramMB >= 1 ? Math.round(procRow.proc.vramMB) + " MB" : "—") : ""
                horizontalAlignment: Text.AlignRight
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
            }
            StyledText {
                width: cols.vramPct
                anchors.verticalCenter: parent.verticalCenter
                text: procRow.proc && root.pluginRoot.vramSupported && procRow.proc.vramPercent > 0 ? procRow.proc.vramPercent.toFixed(1) + "%" : "—"
                horizontalAlignment: Text.AlignRight
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
            StyledText {
                width: cols.pid
                anchors.verticalCenter: parent.verticalCenter
                text: procRow.proc && procRow.proc.pid > 0 ? procRow.proc.pid : ""
                horizontalAlignment: Text.AlignRight
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }
    }

    StyledText {
        width: parent.width
        visible: (root.pluginRoot.clients || []).length === 0
        text: root.pluginRoot.fdinfoRan ? "No active GPU clients" : "Reading GPU clients…"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }
    StyledText {
        width: parent.width
        visible: (root.pluginRoot.clients || []).length > root.maxRows
        text: "+ " + ((root.pluginRoot.clients || []).length - root.maxRows) + " more"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }
}
