import QtQuick
import qs.Common
import qs.Widgets

Item {
    id: root

    required property var pluginRoot
    property bool isVerticalOrientation: false

    readonly property int iconSize: Theme.barIconSize(pluginRoot.barThickness, undefined, pluginRoot.barConfig?.maximizeWidgetIcons, pluginRoot.barConfig?.iconScale)
    readonly property int textSize: Theme.barTextSize(pluginRoot.barThickness, pluginRoot.barConfig?.fontScale, pluginRoot.barConfig?.maximizeWidgetText)
    readonly property real chartSize: Math.max(iconSize + 6, Math.round(textSize * 1.75))

    // Shared row height so text-only metrics center on the same midline as
    // metrics that show a (taller) chart, instead of riding up to the top.
    readonly property bool anyChart: {
        const ms = pluginRoot.enabledMetrics || [];
        for (let i = 0; i < ms.length; ++i)
            if (pluginRoot.showChart(ms[i]))
                return true;
        return false;
    }
    readonly property real rowHeight: Math.max(textSize, iconSize, anyChart ? chartSize : 0)

    // Shared width for the vertical layout so text-only metrics center under the
    // chart ones. Computed from font/chart metrics (NOT from the Column's width,
    // which would be a binding loop and collapse the pill to zero width).
    readonly property bool anyValue: {
        const ms = pluginRoot.enabledMetrics || [];
        for (let i = 0; i < ms.length; ++i)
            if (pluginRoot.showValue(ms[i]))
                return true;
        return false;
    }
    readonly property real sharedVWidth: Math.max(iconSize, anyChart ? chartSize : 0, anyValue ? Math.round(textSize * 3.2) : 0)

    implicitWidth: isVerticalOrientation ? verticalLayout.implicitWidth : horizontalLayout.implicitWidth
    implicitHeight: isVerticalOrientation ? verticalLayout.implicitHeight : horizontalLayout.implicitHeight

    // One metric = optional icon + optional chart + optional value, vertically
    // centered within the shared row height.
    component Metric: Item {
        id: metric
        required property string metricKey
        implicitWidth: metricRow.implicitWidth
        implicitHeight: root.rowHeight

        Row {
            id: metricRow
            anchors.centerIn: parent
            spacing: Theme.spacingXS

            DankIcon {
                visible: root.pluginRoot.showIcon(metric.metricKey)
                anchors.verticalCenter: parent.verticalCenter
                name: root.pluginRoot.iconName(metric.metricKey)
                size: root.iconSize
                color: root.pluginRoot.metricColor(metric.metricKey)
            }

            IntelGpuChart {
                visible: root.pluginRoot.showChart(metric.metricKey)
                anchors.verticalCenter: parent.verticalCenter
                width: root.chartSize
                height: root.chartSize
                chartType: root.pluginRoot.chartType(metric.metricKey)
                progress: root.pluginRoot.metricProgress(metric.metricKey)
                fillColor: root.pluginRoot.metricColor(metric.metricKey)
                barThickness: root.pluginRoot.barWidthFraction(metric.metricKey)
            }

            StyledText {
                visible: root.pluginRoot.showValue(metric.metricKey)
                anchors.verticalCenter: parent.verticalCenter
                text: root.pluginRoot.metricValueText(metric.metricKey)
                font.pixelSize: root.textSize
                color: root.pluginRoot.metricColor(metric.metricKey)
            }
        }
    }

    Row {
        id: horizontalLayout
        visible: !root.isVerticalOrientation
        spacing: Theme.spacingS

        Repeater {
            model: root.pluginRoot.enabledMetrics
            delegate: Metric {
                required property var modelData
                metricKey: modelData
            }
        }
    }

    Column {
        id: verticalLayout
        visible: root.isVerticalOrientation
        spacing: Theme.spacingXS

        Repeater {
            model: root.pluginRoot.enabledMetrics
            delegate: Column {
                id: vMetric
                required property var modelData
                spacing: 1
                // Shared width so text-only metrics center under the wider chart ones.
                width: root.sharedVWidth

                DankIcon {
                    visible: root.pluginRoot.showIcon(vMetric.modelData)
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: root.pluginRoot.iconName(vMetric.modelData)
                    size: root.iconSize
                    color: root.pluginRoot.metricColor(vMetric.modelData)
                }
                IntelGpuChart {
                    visible: root.pluginRoot.showChart(vMetric.modelData)
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.chartSize
                    height: root.chartSize
                    chartType: root.pluginRoot.chartType(vMetric.modelData)
                    progress: root.pluginRoot.metricProgress(vMetric.modelData)
                    fillColor: root.pluginRoot.metricColor(vMetric.modelData)
                    barThickness: root.pluginRoot.barWidthFraction(vMetric.modelData)
                }
                StyledText {
                    visible: root.pluginRoot.showValue(vMetric.modelData)
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.pluginRoot.metricValueText(vMetric.modelData)
                    font.pixelSize: root.textSize
                    color: root.pluginRoot.metricColor(vMetric.modelData)
                }
            }
        }
    }

    // Middle-click only. Left/right are NOT accepted here, so they fall through
    // to BasePill's own (exactly-sized) handler — the whole pill stays clickable.
    // cursorShape keeps the pointing-hand over the text; hoverEnabled stays false
    // so BasePill's hover highlight still works.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: false
        acceptedButtons: Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.pluginRoot.dispatch(root.pluginRoot.middleClickAction())
    }
}
