import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.menu"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: (root.bar && root.bar.isMidnightDoll) ? "\udb81\ude8c" : "\ue900"
    fontFamily: (root.bar && root.bar.isMidnightDoll) ? "JetBrainsMono Nerd Font" : "omarchy"
    fontSize: (root.bar && root.bar.isMidnightDoll) ? 18 : Style.font.body
    foreground: (root.bar && root.bar.isMidnightDoll) ? Color.accent : (root.bar ? root.bar.barForeground : Color.foreground)
    horizontalMargin: (root.bar && root.bar.isMidnightDoll) ? 6 : 7.5
    fixedWidth: (root.bar && root.bar.isMidnightDoll) ? 28 : -1
    fixedHeight: root.bar ? root.bar.barSize : -1
    onPressed: function(button) {
      if (!root.bar) return
      if (button === Qt.RightButton) root.bar.run("xdg-terminal-exec")
      else root.bar.run("omarchy-shell shell toggle omarchy.menu '{\"menu\":\"root\"}'")
    }
  }
}
