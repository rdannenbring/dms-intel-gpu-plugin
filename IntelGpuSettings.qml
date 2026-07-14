import QtQuick
import Quickshell
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.Widgets

PluginSettings {
    id: root

    pluginId: "intelGpuMonitor"

    readonly property var chartTypeModel: [
        { "label": "Horizontal Bar", "value": "hbar" },
        { "label": "Vertical Bar", "value": "bar" },
        { "label": "Gauge", "value": "gauge" },
        { "label": "Donut", "value": "donut" },
        { "label": "Pie", "value": "pie" },
        { "label": "Thermometer", "value": "thermometer" }
    ]
    readonly property var actionModel: [
        { "label": "Show detail view", "value": "detail" },
        { "label": "Show menu", "value": "menu" },
        { "label": "Open in terminal", "value": "terminal" },
        { "label": "Nothing", "value": "nothing" }
    ]
    function gpuModel() {
        const items = [{ "label": "Auto (prefer Intel)", "value": "" }];
        const gpus = DgopService.availableGpus || [];
        for (let i = 0; i < gpus.length; i++) {
            const g = gpus[i];
            items.push({ "label": g.displayName || g.fullName || ("GPU " + (i + 1)), "value": g.pciId });
        }
        return items;
    }

    // ====================================================================
    // Reusable building blocks
    // ====================================================================
    component Card: StyledRect {
        id: card
        property string title: ""
        property string subtitle: ""
        default property alias cardContent: cardColumn.data
        width: parent ? parent.width : 0
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh
        implicitHeight: cardColumn.implicitHeight + Theme.spacingL * 2

        Column {
            id: cardColumn
            x: Theme.spacingL
            y: Theme.spacingL
            width: parent.width - Theme.spacingL * 2
            spacing: Theme.spacingM

            Column {
                width: parent.width
                spacing: 2
                visible: card.title.length > 0
                StyledText {
                    text: card.title
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.Bold
                    color: Theme.surfaceText
                }
                StyledText {
                    width: parent.width
                    visible: card.subtitle.length > 0
                    text: card.subtitle
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    component BoolSetting: DankToggle {
        id: boolCtl
        property string settingKey: ""
        property bool defaultValue: false
        property bool value: defaultValue
        width: parent ? parent.width : 0
        checked: value
        function loadValue() { value = root.loadValue(settingKey, defaultValue); }
        Component.onCompleted: loadValue()
        onToggled: checked => { value = checked; root.saveValue(settingKey, checked); }
        // pluginService is assigned after Component.onCompleted, so reload once it exists.
        Connections { target: root; function onPluginServiceChanged() { boolCtl.loadValue(); } }
    }

    component ChoiceSetting: Column {
        id: choice
        property string settingKey: ""
        property string label: ""
        property string helpText: ""
        property var model: []
        property string defaultValue: ""
        property string value: defaultValue
        width: parent ? parent.width : 0
        spacing: 0
        function labelFor(v) { for (const o of model) if (o.value === v) return o.label; return v; }
        function valueFor(l) { for (const o of model) if (o.label === l) return o.value; return l; }
        function labels() { return model.map(o => o.label); }
        function loadValue() { value = String(root.loadValue(settingKey, defaultValue)); }
        Component.onCompleted: loadValue()
        Connections { target: root; function onPluginServiceChanged() { choice.loadValue(); } }
        DankDropdown {
            width: parent.width
            text: choice.label
            description: choice.helpText
            options: choice.labels()
            currentValue: choice.labelFor(choice.value)
            onValueChanged: newLabel => {
                choice.value = choice.valueFor(newLabel);
                root.saveValue(choice.settingKey, choice.value);
            }
        }
    }

    component SliderSetting: Column {
        id: slider
        property string settingKey: ""
        property string label: ""
        property int minimum: 0
        property int maximum: 100
        property string unit: ""
        property int defaultValue: 0
        property int value: defaultValue
        width: parent ? parent.width : 0
        spacing: Theme.spacingXS
        function loadValue() { value = Number(root.loadValue(settingKey, defaultValue)); }
        Component.onCompleted: loadValue()
        Connections { target: root; function onPluginServiceChanged() { slider.loadValue(); } }
        StyledText {
            text: slider.label
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceText
        }
        DankSlider {
            width: parent.width
            value: slider.value
            minimum: slider.minimum
            maximum: slider.maximum
            unit: slider.unit
            wheelEnabled: false
            onSliderValueChanged: newValue => {
                slider.value = newValue;
                root.saveValue(slider.settingKey, newValue);
            }
        }
    }

    component StringSetting: Column {
        id: str
        property string settingKey: ""
        property string label: ""
        property string placeholder: ""
        property string helpText: ""
        property string defaultValue: ""
        property string value: defaultValue
        width: parent ? parent.width : 0
        spacing: Theme.spacingXS
        function loadValue() { value = String(root.loadValue(settingKey, defaultValue)); }
        Component.onCompleted: loadValue()
        Connections { target: root; function onPluginServiceChanged() { str.loadValue(); } }
        StyledText {
            text: str.label
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceText
        }
        StyledText {
            width: parent.width
            visible: str.helpText.length > 0
            text: str.helpText
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }
        DankTextField {
            width: parent.width
            text: str.value
            placeholderText: str.placeholder
            onEditingFinished: { str.value = text; root.saveValue(str.settingKey, text); }
            onFocusStateChanged: hasFocus => {
                if (!hasFocus) { str.value = text; root.saveValue(str.settingKey, text); }
            }
        }
    }

    component IconSetting: Column {
        id: iconSetting
        property string settingKey: ""
        property string label: ""
        property string value: ""
        width: parent ? parent.width : 0
        spacing: Theme.spacingXS
        function loadValue() {
            value = String(root.loadValue(settingKey, ""));
            if (picker.setIcon) picker.setIcon(value, "icon");
        }
        Component.onCompleted: loadValue()
        Connections { target: root; function onPluginServiceChanged() { iconSetting.loadValue(); } }
        StyledText {
            text: iconSetting.label
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceText
        }
        Row {
            width: parent.width
            spacing: Theme.spacingS
            DankIconPicker {
                id: picker
                width: Math.max(200, parent.width - 32 - Theme.spacingS)
                Component.onCompleted: if (iconSetting.value.length > 0) setIcon(iconSetting.value, "icon")
                onIconSelected: (iconName, iconType) => {
                    iconSetting.value = iconName;
                    root.saveValue(iconSetting.settingKey, iconName);
                }
            }
            DankActionButton {
                anchors.verticalCenter: parent.verticalCenter
                iconName: "close"
                tooltipText: "Use default icon"
                onClicked: {
                    iconSetting.value = "";
                    root.saveValue(iconSetting.settingKey, "");
                }
            }
        }
    }

    // A metric block: show value / show chart (+ type) / show icon (+ picker).
    // Extends Card, so the fixed controls below and any per-card extras added by
    // an instance all flow into the card column, in declaration order.
    component MetricCard: Card {
        id: mc
        property string metricKey: ""
        property string defaultChartType: "gauge"
        property bool defaultShowValue: true
        property bool defaultShowChart: false

        BoolSetting {
            settingKey: mc.metricKey + "ShowValue"
            defaultValue: mc.defaultShowValue
            text: "Show value in bar"
            description: "Display the numeric reading."
        }
        BoolSetting {
            id: chartToggle
            settingKey: mc.metricKey + "ShowChart"
            defaultValue: mc.defaultShowChart
            text: "Show chart in bar"
            description: "Display a graphical 0–100% indicator."
        }
        ChoiceSetting {
            id: chartChoice
            visible: chartToggle.value
            settingKey: mc.metricKey + "ChartType"
            label: "Chart type"
            model: root.chartTypeModel
            defaultValue: mc.defaultChartType
        }
        SliderSetting {
            visible: chartToggle.value && (chartChoice.value === "bar" || chartChoice.value === "hbar")
            settingKey: mc.metricKey + "BarThickness"
            label: chartChoice.value === "hbar" ? "Bar height (%)" : "Bar width (%)"
            minimum: 5
            maximum: 100
            unit: "%"
            defaultValue: 35
        }
        BoolSetting {
            id: iconToggle
            settingKey: mc.metricKey + "ShowIcon"
            defaultValue: false
            text: "Show icon in bar"
        }
        IconSetting {
            visible: iconToggle.value
            settingKey: mc.metricKey + "IconName"
            label: "Custom icon"
        }
    }

    // ====================================================================
    // Content
    // ====================================================================
    Card {
        title: "How it works"
        subtitle: "No installation or special permissions required."

        StyledText {
            width: parent.width
            text: "Usage, VRAM and the per-process list are read from the kernel's DRM fdinfo (per-process GPU engine and memory counters), filtered to the Intel GPU. Temperature and frequency come from sysfs. Nothing needs elevated access, and reading these does not wake the GPU."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceText
            wrapMode: Text.WordWrap
        }
        StyledText {
            width: parent.width
            text: "intel_gpu_top (from intel-gpu-tools) is only used for the optional “open in terminal” action, if you enable it. It is not required for the widget."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }
    }

    Card {
        title: "General"

        SliderSetting {
            settingKey: "pollInterval"
            label: "Refresh interval (ms)"
            minimum: 500
            maximum: 30000
            unit: "ms"
            defaultValue: 2000
        }
        StyledText {
            width: parent.width
            text: "How often the metrics refresh. Each refresh does one lightweight scan of /proc; a longer interval (e.g. 5000+) is lighter — worth raising if your GPU has little headroom."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }
    }

    MetricCard {
        title: "GPU Usage"
        metricKey: "usage"
        defaultChartType: "gauge"
        defaultShowValue: true
        defaultShowChart: true

        StyledText {
            width: parent.width
            text: "Usage is the busiest GPU engine (render, blitter, video, video-enhance, compute), aggregated from per-process fdinfo counters — the same source intel_gpu_top uses. The detail view breaks it down per engine and per process."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }
    }

    MetricCard {
        title: "VRAM Usage"
        metricKey: "vram"
        defaultChartType: "bar"
        defaultShowValue: false
        defaultShowChart: false

        StringSetting {
            settingKey: "vramTotalMbOverride"
            label: "Total VRAM override (MB)"
            placeholder: "0 = auto"
            helpText: "0 = auto (system RAM for shared-memory iGPUs). For discrete Intel Arc GPUs set your card's VRAM, e.g. 8192 for an 8 GB A770 — this is the % denominator."
            defaultValue: "0"
        }
        StyledText {
            width: parent.width
            text: "VRAM comes from the same fdinfo scan as usage (no extra cost). iGPUs report shared system memory, so the percentage is of system RAM and reads low. Discrete Intel Arc GPUs report dedicated (local) memory — that path is implemented but untested (developer has no Arc card)."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }
    }

    MetricCard {
        title: "Temperature"
        metricKey: "temp"
        defaultChartType: "thermometer"
        defaultShowValue: true
        defaultShowChart: false

        ChoiceSetting {
            settingKey: "tempGpuPciId"
            label: "GPU (for temperature source)"
            model: root.gpuModel()
            defaultValue: ""
        }
        SliderSetting {
            settingKey: "tempMin"
            label: "Chart range: min (°C)"
            minimum: 0
            maximum: 90
            unit: "°"
            defaultValue: 30
        }
        SliderSetting {
            settingKey: "tempMax"
            label: "Chart range: max (°C)"
            minimum: 60
            maximum: 120
            unit: "°"
            defaultValue: 100
        }
        StyledText {
            width: parent.width
            text: "Temperature is read from the GPU's own hwmon sensor when available (discrete cards); "
                + "integrated GPUs have no separate sensor, so it falls back to the CPU package/die temperature "
                + "(shown as “GPU Temp (die)”). A typical Intel GPU idles ~35–45 °C and throttles near 100 °C "
                + "(TjMax), so the default 30–100 °C range maps cleanly to 0–100%."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }
    }

    Card {
        title: "Interaction"

        ChoiceSetting {
            settingKey: "leftClickAction"
            label: "Left click"
            model: root.actionModel
            defaultValue: "detail"
        }
        ChoiceSetting {
            settingKey: "rightClickAction"
            label: "Right click"
            model: root.actionModel
            defaultValue: "menu"
        }
        ChoiceSetting {
            settingKey: "middleClickAction"
            label: "Middle click"
            model: root.actionModel
            defaultValue: "nothing"
        }
        BoolSetting {
            settingKey: "terminalEnabled"
            defaultValue: true
            text: "Enable “open intel_gpu_top in terminal”"
            description: "Adds a terminal launcher to the menu and click actions."
        }
        StringSetting {
            settingKey: "terminalCommand"
            label: "Terminal command"
            placeholder: "auto ($TERMINAL)"
            helpText: "Leave blank to use your default terminal ($TERMINAL). Launched as: <terminal> <flag> intel_gpu_top — the run flag (-e, --, start --) is chosen automatically for known terminals."
            defaultValue: ""
        }
    }

    Card {
        title: "Backlog"
        subtitle: "Planned: per-value thresholds to drive icon changes, color changes and alert messages. Not yet implemented."
    }
}
