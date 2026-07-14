import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

Column {
    id: root

    required property var pluginRoot
    signal requestClose

    spacing: 2

    component MenuItem: Rectangle {
        id: item
        property string icon: ""
        property string label: ""
        signal triggered

        width: parent.width
        height: 36
        radius: Theme.cornerRadius
        color: hover.containsMouse ? Theme.surfaceContainerHigh : "transparent"

        Row {
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingS

            DankIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: item.icon
                size: Theme.iconSizeSmall
                color: Theme.surfaceText
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: item.label
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
            }
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: item.triggered()
        }
    }

    MenuItem {
        icon: "insights"
        label: "Open detail view"
        onTriggered: root.pluginRoot.openPopoutMode("detail")
    }
    MenuItem {
        visible: root.pluginRoot.terminalEnabled()
        icon: "terminal"
        label: "Open in terminal"
        onTriggered: {
            root.pluginRoot.openInTerminal();
            root.requestClose();
        }
    }
    MenuItem {
        icon: "settings"
        label: "Settings"
        onTriggered: {
            if (typeof PopoutService !== "undefined" && PopoutService.openSettingsWithTab)
                PopoutService.openSettingsWithTab("plugins");
            root.requestClose();
        }
    }
}
