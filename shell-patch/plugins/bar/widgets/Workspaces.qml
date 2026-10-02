import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  readonly property bool isMidnightDoll: !!(root.bar && root.bar.isMidnightDoll)

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  readonly property var notificationService: root.bar && root.bar.shell ? root.bar.shell.firstPartyServiceFor("omarchy.notifications") : null
  property var urgentAddresses: ({})
  property int tick: 0

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event) return
      if (event.name === "urgent") {
        var addr = String(event.data || "").trim()
        if (addr) {
          var map = Object.assign({}, root.urgentAddresses)
          map[addr] = true
          root.urgentAddresses = map
          root.tick = (root.tick + 1) % 1000
        }
      } else if (event.name === "activewindow" || event.name === "activewindowv2") {
        var activeTop = Hyprland.activeToplevel
        var activeAddr = (activeTop && activeTop.lastIpcObject) ? activeTop.lastIpcObject.address : null
        if (activeAddr && root.urgentAddresses[activeAddr]) {
          var map = Object.assign({}, root.urgentAddresses)
          delete map[activeAddr]
          root.urgentAddresses = map
          root.tick = (root.tick + 1) % 1000
        }
      }
    }
  }

  Timer {
    interval: 800
    running: true
    repeat: true
    onTriggered: {
      root.tick = (root.tick + 1) % 1000
    }
  }

  function workspaceNotificationCount(workspaceId, workspaceObj) {
    if (!workspaceObj) return 0

    var total = 0
    var toplevels = (workspaceObj.toplevels && workspaceObj.toplevels.values) ? workspaceObj.toplevels.values : []

    // 1. Check toplevels on this workspace
    for (var i = 0; i < toplevels.length; i++) {
      var top = toplevels[i]
      if (!top) continue

      var winCount = 0
      var ipc = top.lastIpcObject
      if (ipc) {
        var title = String(ipc.title || "").trim()
        var winClass = String(ipc.class || "").trim()
        var isDiscord = /discord|vesktop|webcord/i.test(title) || /discord|vesktop|webcord/i.test(winClass)

        var numMatch = title.match(/^(?:[\u2022\u25CF\*]\s*)?(?:\(([0-9]+)[\+\!]?\)|\[([0-9]+)[\+\!]?\])/)
        if (numMatch) {
          winCount = parseInt(numMatch[1] || numMatch[2], 10)
        } else if (!isDiscord && /^[\u2022\u25CF\*]/.test(title)) {
          winCount = 1
        }

        var isUrgent = (top.urgent === true) || (ipc.address && root.urgentAddresses && root.urgentAddresses[ipc.address])
        if (isUrgent && winCount === 0) {
          winCount = 1
        }
      } else if (top.urgent === true) {
        winCount = 1
      }

      total += winCount
    }

    // 2. Check active desktop notification popups matching windows on this workspace
    if (root.notificationService && root.notificationService.popupModel) {
      var count = root.notificationService.popupModel.count
      if (count > 0 && toplevels.length > 0) {
        var matchedPopups = 0
        for (var p = 0; p < count; p++) {
          var popup = root.notificationService.popupModel.get(p)
          if (!popup) continue
          var app = String(popup.app || "").toLowerCase().trim()
          if (!app) continue
          for (var t = 0; t < toplevels.length; t++) {
            var tipc = toplevels[t] ? toplevels[t].lastIpcObject : null
            if (!tipc) continue
            var cClass = String(tipc.class || "").toLowerCase()
            var cTitle = String(tipc.title || "").toLowerCase()
            if (cClass.indexOf(app) !== -1 || app.indexOf(cClass) !== -1 || cTitle.indexOf(app) !== -1) {
              matchedPopups++
              break
            }
          }
        }
        if (matchedPopups > total) {
          total = matchedPopups
        }
      }
    }

    return total
  }

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : (root.isMidnightDoll ? 2 : Style.space(1))
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      Item {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
        readonly property int notificationCount: {
          var _ = root.tick
          return root.workspaceNotificationCount(modelData, workspace)
        }
        readonly property bool hasNotification: notificationCount > 0

        implicitWidth: root.isMidnightDoll ? (btn.labelWidth + 8) : btn.implicitWidth
        implicitHeight: root.barSize

        Rectangle {
          visible: root.isMidnightDoll && focused
          anchors.centerIn: parent
          width: parent.width
          height: root.barSize - 6
          color: Color.accent
          radius: 0
        }

        // Subtle notification count indicator badge in accent color below workspace button (NO flashing)
        Rectangle {
          id: countBadge
          visible: hasNotification && !focused
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 1
          anchors.horizontalCenter: parent.horizontalCenter
          height: 8
          width: Math.max(8, countText.implicitWidth + 4)
          radius: root.isMidnightDoll ? 2 : 4
          color: Color.accent
          z: 10

          Text {
            id: countText
            anchors.centerIn: parent
            text: notificationCount > 99 ? "99+" : String(notificationCount)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: 7
            font.bold: true
            color: "#010101"
            renderType: Text.NativeRendering
          }
        }

        WidgetButton {
          id: btn
          anchors.fill: parent
          bar: root.bar
          text: root.isMidnightDoll
            ? ("[" + (modelData === 10 ? "0" : String(modelData)) + "]")
            : (focused ? "\uDB85\uDCFB" : (modelData === 10 ? "0" : String(modelData)))

          foreground: (root.isMidnightDoll && focused)
            ? "#010101"
            : (root.isMidnightDoll ? Color.accent : (hasNotification ? Color.accent : (root.bar ? root.bar.barForeground : Color.foreground)))
          active: root.isMidnightDoll ? false : true
          useActiveColor: root.isMidnightDoll ? false : true
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          opacity: root.isMidnightDoll ? 1.0 : (occupied || focused || hasNotification ? 1 : 0.5)
          horizontalMargin: root.isMidnightDoll ? 2 : 6
          verticalPadding: root.isMidnightDoll ? 2 : 6
          fixedWidth: root.isMidnightDoll ? -1 : (root.vertical ? root.barSize : Style.space(20))
          fixedHeight: root.barSize
          onPressed: function() { root.focusWorkspace(modelData) }
        }

        HoverHandler {
          onHoveredChanged: {
            if (hovered && hasNotification && root.bar) {
              root.bar.showTooltip(parent, "Workspace " + modelData + " (" + notificationCount + (notificationCount === 1 ? " notification)" : " notifications)"))
            } else if (!hovered && root.bar) {
              root.bar.hideTooltip(parent)
            }
          }
        }
      }
    }
  }
}

