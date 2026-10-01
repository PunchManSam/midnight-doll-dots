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
  property int cpuTemp: 0
  property int fanVal: 0
  property int fanPct: 0
  property var fanList: [0]
  property int memVal: 0
  property string memGb: "0G"
  property int dskVal: 0
  property string rxRate: "0B"
  property string txRate: "0B"
  property int connsVal: 0

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
        else if (k === "CPUTEMP" || k === "CPU_TEMP" || k === "TEMP") cpuTemp = parseInt(v, 10) || 0
        else if (k === "FAN" || k === "FAN_RPM") fanVal = parseInt(v, 10) || 0
        else if (k === "FAN_PCT") {
          fanPct = parseInt(v, 10) || 0
          if (fanList.length <= 1) fanList = [fanPct]
        }
        else if (k === "FAN_PCTS") {
          var arr = v.split(",")
          var pcts = []
          for (var j = 0; j < arr.length; j++) {
            var n = parseInt(arr[j], 10)
            if (!isNaN(n)) pcts.push(n)
          }
          if (pcts.length > 0) fanList = pcts
        }
        else if (k === "MEM") memVal = parseInt(v, 10) || 0
        else if (k === "MEM_GB") memGb = v
        else if (k === "DSK") dskVal = parseInt(v, 10) || 0
        else if (k === "RX") rxRate = v
        else if (k === "TX") txRate = v
        else if (k === "CONNS") connsVal = parseInt(v, 10) || 0
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
    spacing: 6

    // Hardware Telemetry Group (CPU, FAN, RAM, DSK) -> Launches btop
    Row {
      id: hwGroup
      spacing: 6
      width: implicitWidth
      height: root.barSize
      anchors.verticalCenter: parent.verticalCenter
      property bool pressable: true
      function triggerPress(button) {
        if (root.bar) root.bar.run("omarchy-launch-or-focus-tui btop")
      }
      Component.onCompleted: if (root.bar && typeof root.bar.registerClickTarget === "function") root.bar.registerClickTarget(this)
      Component.onDestruction: if (root.bar && typeof root.bar.unregisterClickTarget === "function") root.bar.unregisterClickTarget(this)

      // CPU Gauge
      Row {
        spacing: 4
        anchors.verticalCenter: parent.verticalCenter
        Text {
          text: "CPU"
          font.family: root.fontFam
          font.pixelSize: 8
          font.bold: true
          color: root.secondaryColor
          rightPadding: 2
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
          horizontalAlignment: Text.AlignLeft
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          visible: root.cpuTemp > 0
          text: root.cpuTemp + "°C"
          font.family: root.fontFam
          font.pixelSize: 8
          color: root.cpuTemp > 80 ? root.urgentColor : Color.foreground
          width: visible ? 24 : 0
          horizontalAlignment: Text.AlignLeft
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      // Divider
      Text {
        text: "|"
        font.family: root.fontFam
        font.pixelSize: 8
        color: Qt.rgba(1, 1, 1, 0.22)
        anchors.verticalCenter: parent.verticalCenter
      }

      // FAN Gauge (Vertical Bars per Fan)
      Row {
        spacing: 4
        anchors.verticalCenter: parent.verticalCenter
        Text {
          text: "FAN"
          font.family: root.fontFam
          font.pixelSize: 8
          font.bold: true
          color: root.secondaryColor
          rightPadding: 2
          anchors.verticalCenter: parent.verticalCenter
        }
        Row {
          spacing: 2
          anchors.verticalCenter: parent.verticalCenter
          Repeater {
            model: root.fanList
            Rectangle {
              width: 3
              height: 10
              color: Qt.rgba(1, 1, 1, 0.15)
              anchors.verticalCenter: parent.verticalCenter
              Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: Math.max(modelData > 0 ? 1 : 0, Math.round(parent.height * (Math.min(100, modelData) / 100.0)))
                color: modelData > 80 ? root.urgentColor : Color.accent
              }
            }
          }
        }
        Text {
          text: root.fanVal > 0 ? (root.fanVal >= 10000 ? (root.fanVal / 1000).toFixed(1) + "k" : String(root.fanVal)) : "OFF"
          font.family: root.fontFam
          font.pixelSize: 8
          color: root.fanPct > 80 ? root.urgentColor : Color.foreground
          width: 24
          horizontalAlignment: Text.AlignLeft
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      // Divider
      Text {
        text: "|"
        font.family: root.fontFam
        font.pixelSize: 8
        color: Qt.rgba(1, 1, 1, 0.22)
        anchors.verticalCenter: parent.verticalCenter
      }

      // RAM / MEM Gauge
      Row {
        spacing: 4
        anchors.verticalCenter: parent.verticalCenter
        Text {
          text: "RAM"
          font.family: root.fontFam
          font.pixelSize: 8
          font.bold: true
          color: root.secondaryColor
          rightPadding: 2
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
          text: root.memVal + "%"
          font.family: root.fontFam
          font.pixelSize: 8
          color: Color.foreground
          width: 22
          horizontalAlignment: Text.AlignLeft
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      // Divider
      Text {
        text: "|"
        font.family: root.fontFam
        font.pixelSize: 8
        color: Qt.rgba(1, 1, 1, 0.22)
        anchors.verticalCenter: parent.verticalCenter
      }

      // DISK Gauge
      Row {
        spacing: 4
        anchors.verticalCenter: parent.verticalCenter
        Text {
          text: "DSK"
          font.family: root.fontFam
          font.pixelSize: 8
          font.bold: true
          color: root.secondaryColor
          rightPadding: 2
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
          horizontalAlignment: Text.AlignLeft
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }

    // Divider
    Text {
      text: "|"
      font.family: root.fontFam
      font.pixelSize: 8
      color: Qt.rgba(1, 1, 1, 0.22)
      anchors.verticalCenter: parent.verticalCenter
    }

    // Comms Telemetry Group (NET, CONNS) -> Launches smart comms inspector
    Row {
      id: commsGroup
      spacing: 6
      width: implicitWidth
      height: root.barSize
      anchors.verticalCenter: parent.verticalCenter
      property bool pressable: true
      function triggerPress(button) {
        if (root.bar) root.bar.run("omarchy-launch-or-focus-tui --app-id=TUI.float " + root.homeDir + "/.config/omarchy/launch-comms.sh")
      }
      Component.onCompleted: if (root.bar && typeof root.bar.registerClickTarget === "function") root.bar.registerClickTarget(this)
      Component.onDestruction: if (root.bar && typeof root.bar.unregisterClickTarget === "function") root.bar.unregisterClickTarget(this)

      // NET Rates
      Row {
        spacing: 4
        anchors.verticalCenter: parent.verticalCenter
        Text {
          text: "NET"
          font.family: root.fontFam
          font.pixelSize: 8
          font.bold: true
          color: root.secondaryColor
          rightPadding: 2
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

      // Divider
      Text {
        text: "|"
        font.family: root.fontFam
        font.pixelSize: 8
        color: Qt.rgba(1, 1, 1, 0.22)
        anchors.verticalCenter: parent.verticalCenter
      }

      // Connections Indicator
      Row {
        spacing: 4
        anchors.verticalCenter: parent.verticalCenter
        Text {
          text: "CONNS"
          font.family: root.fontFam
          font.pixelSize: 8
          font.bold: true
          color: root.secondaryColor
          rightPadding: 2
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          text: String(root.connsVal)
          font.family: root.fontFam
          font.pixelSize: 8
          color: root.connsVal > 100 ? root.urgentColor : Color.accent
          width: 18
          horizontalAlignment: Text.AlignLeft
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }
  }
}
