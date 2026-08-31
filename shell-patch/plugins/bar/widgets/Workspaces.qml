import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  readonly property bool isMidnightDoll: root.bar && root.bar.isMidnightDoll

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

        WidgetButton {
          id: btn
          anchors.fill: parent
          bar: root.bar
          text: root.isMidnightDoll
            ? ("[" + (modelData === 10 ? "0" : String(modelData)) + "]")
            : (focused ? "\uDB85\uDCFB" : (modelData === 10 ? "0" : String(modelData)))

          foreground: (root.isMidnightDoll && focused)
            ? "#010101"
            : (root.isMidnightDoll ? Color.accent : (root.bar ? root.bar.barForeground : Color.foreground))
          active: root.isMidnightDoll ? false : true
          useActiveColor: root.isMidnightDoll ? false : true
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          opacity: root.isMidnightDoll ? 1.0 : (occupied || focused ? 1 : 0.5)
          horizontalMargin: root.isMidnightDoll ? 2 : 6
          verticalPadding: root.isMidnightDoll ? 2 : 6
          fixedWidth: root.isMidnightDoll ? -1 : (root.vertical ? root.barSize : Style.space(20))
          fixedHeight: root.barSize
          onPressed: function() { root.focusWorkspace(modelData) }
        }
      }
    }
  }
}

