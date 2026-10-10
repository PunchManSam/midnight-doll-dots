import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "midnight-doll.notifications"
  ipcTarget: "midnight-doll.notifications"

  property var notificationsList: []
  readonly property int unreadCount: notificationsList.length
  readonly property string helperPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/midnight-doll.notifications/helper.py"

  function formatTime(timestamp) {
    if (!timestamp) return ""
    var diff = Math.floor((Date.now() - timestamp) / 1000)
    if (diff < 60) return "Just now"
    if (diff < 3600) return Math.floor(diff / 60) + "m ago"
    if (diff < 86400) return Math.floor(diff / 3600) + "h ago"
    var d = new Date(timestamp)
    return d.toLocaleDateString(undefined, { month: "short", day: "numeric" })
  }

  function refresh() {
    if (!listProc.running) {
      listProc.running = true
    }
  }

  function dismissNotification(filePath, index) {
    if (!filePath) return
    dismissProc.command = ["python3", root.helperPath, "dismiss", filePath]
    dismissProc.running = true
    var next = root.notificationsList.slice()
    next.splice(index, 1)
    root.notificationsList = next
  }

  function clearAll() {
    clearProc.command = ["python3", root.helperPath, "clear"]
    clearProc.running = true
    root.notificationsList = []
  }

  onOpenedChanged: {
    if (opened) {
      refresh()
    }
  }

  Component.onCompleted: {
    refresh()
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: listProc
    command: ["python3", root.helperPath, "list"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var str = String(text || "").trim()
        if (!str) return
        try {
          var parsed = JSON.parse(str)
          if (Array.isArray(parsed)) {
            root.notificationsList = parsed
          }
        } catch (e) {
        }
      }
    }
  }

  Process {
    id: dismissProc
    running: false
    onExited: root.refresh()
  }

  Process {
    id: clearProc
    running: false
    onExited: root.refresh()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.unreadCount > 0 ? "󰂚 " + root.unreadCount : "󰂚"
    slotSize: Style.bar.iconSlot * (root.unreadCount > 0 && !vertical ? (root.unreadCount > 9 ? 2.2 : 1.8) : 1)
    tooltipText: root.unreadCount > 0 ? root.unreadCount + " notifications" : "Notification Center"
    onPressed: function(b) {
      root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Item {
        anchors.fill: parent

      Column {
        id: mainColumn
        anchors.fill: parent
        spacing: Style.space(12)

        // Header Row
        Row {
          width: parent.width
          height: Style.space(32)
          spacing: Style.space(8)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "󰂚"
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.title
            color: Commons.Color.accent
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "NOTIFICATIONS"
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
            color: root.bar ? root.bar.foreground : Commons.Color.foreground
          }

          // Count badge
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.unreadCount > 0
            radius: height / 2
            width: Math.max(height, badgeText.implicitWidth + Style.space(10))
            height: Style.space(18)
            color: Commons.Color.accent

            Text {
              id: badgeText
              anchors.centerIn: parent
              text: String(root.unreadCount)
              color: Commons.Color.background
              font.bold: true
              font.pixelSize: Style.font.caption
            }
          }

          Item {
            width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[1].implicitWidth - (root.unreadCount > 0 ? 40 : 0) - clearBtn.implicitWidth - closeBtn.implicitWidth - 32)
            height: 1
          }

          Button {
            id: clearBtn
            anchors.verticalCenter: parent.verticalCenter
            visible: root.unreadCount > 0
            text: "Clear"
            iconText: "󰃢"
            fontSize: Style.font.caption
            horizontalPadding: Style.space(8)
            verticalPadding: Style.space(4)
            bordered: true
            onClicked: root.clearAll()
          }

          Button {
            id: closeBtn
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰅖"
            fontSize: Style.font.caption
            horizontalPadding: Style.space(6)
            verticalPadding: Style.space(4)
            bordered: false
            onClicked: root.close()
          }
        }

        PanelSeparator {
          width: parent.width
          foreground: root.bar ? root.bar.foreground : Commons.Color.foreground
        }

        // Empty state view
        Item {
          id: emptyState
          visible: root.unreadCount === 0
          width: parent.width
          height: Style.space(420)

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "󰂚"
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.space(48)
              opacity: 0.2
              color: root.bar ? root.bar.foreground : Commons.Color.foreground
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "No notifications"
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.title
              opacity: 0.6
              color: root.bar ? root.bar.foreground : Commons.Color.foreground
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "You're all caught up"
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
              opacity: 0.4
              color: root.bar ? root.bar.foreground : Commons.Color.foreground
            }
          }
        }

        // Scrollable List
        ScrollView {
          id: scrollView
          visible: root.unreadCount > 0
          width: parent.width
          height: Style.space(440)
          clip: true

          ListView {
            id: listView
            width: scrollView.width
            model: root.notificationsList
            spacing: Style.space(8)
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              id: card
              required property var modelData
              required property int index

              width: listView.width - Style.space(8)
              height: cardContent.implicitHeight + Style.space(16)
              radius: Style.space(6)
              color: cardHover.hovered ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.04)
              border.width: 1
              border.color: cardHover.hovered ? Commons.Color.accent : Qt.rgba(1, 1, 1, 0.08)

              HoverHandler {
                id: cardHover
              }

              Column {
                id: cardContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(10)
                spacing: Style.space(4)

                // Top line: App + Time + Dismiss
                Row {
                  width: parent.width
                  spacing: Style.space(6)

                  Text {
                    text: modelData.glyph || "󰂚"
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    color: Commons.Color.accent
                  }

                  Text {
                    text: modelData.app || "Notification"
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    opacity: 0.7
                    color: root.bar ? root.bar.foreground : Commons.Color.foreground
                  }

                  Item {
                    width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[1].implicitWidth - timeText.implicitWidth - dismissBtn.implicitWidth - 24)
                    height: 1
                  }

                  Text {
                    id: timeText
                    text: root.formatTime(modelData.timestamp)
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                    opacity: 0.45
                    color: root.bar ? root.bar.foreground : Commons.Color.foreground
                  }

                  MouseArea {
                    id: dismissBtn
                    width: Style.space(18)
                    height: Style.space(18)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.dismissNotification(modelData.file, index)

                    Text {
                      anchors.centerIn: parent
                      text: "󰅖"
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption
                      color: dismissBtn.containsMouse ? Commons.Color.accent : (root.bar ? root.bar.foreground : Commons.Color.foreground)
                      opacity: dismissBtn.containsMouse ? 1.0 : 0.5
                    }
                  }
                }

                // Summary
                Text {
                  width: parent.width
                  text: modelData.summary || ""
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  wrapMode: Text.Wrap
                  textFormat: Text.PlainText
                  color: root.bar ? root.bar.foreground : Commons.Color.foreground
                }

                // Body
                Text {
                  width: parent.width
                  visible: (modelData.body || "") !== ""
                  text: modelData.body || ""
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.Wrap
                  textFormat: Text.PlainText
                  opacity: 0.8
                  color: root.bar ? root.bar.foreground : Commons.Color.foreground
                }
              }
            }
          }
        }
      }
    }
  }
}
}
