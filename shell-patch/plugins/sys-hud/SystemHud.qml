import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "midnight-doll.sys-hud"

  readonly property var shellBar: root.bar
  readonly property color secondaryColor: (shellBar && shellBar.secondaryColor) ? shellBar.secondaryColor : "#bb9af7"
  readonly property color urgentColor: (shellBar && shellBar.urgent) ? shellBar.urgent : Color.accent
  readonly property string fontFam: (shellBar && shellBar.fontFamily) ? shellBar.fontFamily : "JetBrainsMono Nerd Font"
  readonly property string homeDir: Quickshell.env("HOME")

  implicitWidth: sysHudRow.implicitWidth
  implicitHeight: root.barSize

  property int cpuVal: 0
  property int memVal: 0
  property string memGb: "0G"
  property int dskVal: 0
  property string rxRate: "0B"
  property string txRate: "0B"

  property bool pressable: true
  function triggerPress(button) {
    if (root.bar) root.bar.run("omarchy-launch-or-focus-tui btop")
  }

  function updateMetrics(raw) {
    if (!raw) return
    var parts = String(raw).trim().split(";")
    for (var i = 0; i < parts.length; i++) {
      var kv = parts[i].split(":")
      if (kv.length === 2) {
        var k = kv[0]
        var v = kv[1]
        if (k === "CPU") cpuVal = parseInt(v, 10) || 0
        else if (k === "MEM") memVal = parseInt(v, 10) || 0
        else if (k === "MEM_GB") memGb = v
        else if (k === "DSK") dskVal = parseInt(v, 10) || 0
        else if (k === "RX") rxRate = v
        else if (k === "TX") txRate = v
      }
    }
  }

  Process {
    id: sysProc
    command: ["/bin/bash", root.homeDir + "/.config/omarchy/sys-hud.sh"]
    stdout: SplitParser {
      onRead: function(line) {
        root.updateMetrics(line)
      }
    }
  }

  Timer {
    interval: 1500
    running: root.visible
    repeat: true
    triggeredOnStart: true
    onTriggered: sysProc.running = true
  }

  Row {
    id: sysHudRow
    anchors.verticalCenter: parent.verticalCenter
    spacing: 5

    // CPU Gauge
    Row {
      spacing: 2
      anchors.verticalCenter: parent.verticalCenter
      Text {
        text: "CPU"
        font.family: root.fontFam
        font.pixelSize: 8
        font.bold: true
        color: root.secondaryColor
        width: 17
        anchors.verticalCenter: parent.verticalCenter
      }
      Rectangle {
        width: 20
        height: 4
        color: Qt.rgba(1, 1, 1, 0.15)
        anchors.verticalCenter: parent.verticalCenter
        Rectangle {
          anchors.left: parent.left
          height: parent.height
          width: Math.max(1, Math.round(parent.width * (root.cpuVal / 100.0)))
          color: root.cpuVal > 80 ? root.urgentColor : Color.accent
        }
      }
      Text {
        text: root.cpuVal + "%"
        font.family: root.fontFam
        font.pixelSize: 8
        color: Color.foreground
        width: 22
        horizontalAlignment: Text.AlignRight
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    // RAM / MEM Gauge
    Row {
      spacing: 2
      anchors.verticalCenter: parent.verticalCenter
      Text {
        text: "RAM"
        font.family: root.fontFam
        font.pixelSize: 8
        font.bold: true
        color: root.secondaryColor
        width: 17
        anchors.verticalCenter: parent.verticalCenter
      }
      Rectangle {
        width: 20
        height: 4
        color: Qt.rgba(1, 1, 1, 0.15)
        anchors.verticalCenter: parent.verticalCenter
        Rectangle {
          anchors.left: parent.left
          height: parent.height
          width: Math.max(1, Math.round(parent.width * (root.memVal / 100.0)))
          color: root.memVal > 85 ? root.urgentColor : Color.accent
        }
      }
      Text {
        text: root.memGb
        font.family: root.fontFam
        font.pixelSize: 8
        color: Color.foreground
        width: 28
        horizontalAlignment: Text.AlignRight
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    // DISK Gauge
    Row {
      spacing: 2
      anchors.verticalCenter: parent.verticalCenter
      Text {
        text: "DSK"
        font.family: root.fontFam
        font.pixelSize: 8
        font.bold: true
        color: root.secondaryColor
        width: 17
        anchors.verticalCenter: parent.verticalCenter
      }
      Rectangle {
        width: 20
        height: 4
        color: Qt.rgba(1, 1, 1, 0.15)
        anchors.verticalCenter: parent.verticalCenter
        Rectangle {
          anchors.left: parent.left
          height: parent.height
          width: Math.max(1, Math.round(parent.width * (root.dskVal / 100.0)))
          color: root.dskVal > 90 ? root.urgentColor : Color.accent
        }
      }
      Text {
        text: root.dskVal + "%"
        font.family: root.fontFam
        font.pixelSize: 8
        color: Color.foreground
        width: 22
        horizontalAlignment: Text.AlignRight
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    // NET Rates
    Row {
      spacing: 2
      anchors.verticalCenter: parent.verticalCenter
      Text {
        text: "NET"
        font.family: root.fontFam
        font.pixelSize: 8
        font.bold: true
        color: root.secondaryColor
        width: 17
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        text: "▲" + root.txRate + " ▼" + root.rxRate
        font.family: root.fontFam
        font.pixelSize: 8
        color: Color.accent
        width: 78
        horizontalAlignment: Text.AlignLeft
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }
}
