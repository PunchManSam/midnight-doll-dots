import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "midnight-doll.visualizer"

  readonly property var shellBar: root.bar
  readonly property color secondaryColor: (shellBar && shellBar.secondaryColor) ? shellBar.secondaryColor : "#bb9af7"
  readonly property color urgentColor: (shellBar && shellBar.urgent) ? shellBar.urgent : Color.accent
  readonly property string fontFam: (shellBar && shellBar.fontFamily) ? shellBar.fontFamily : "JetBrainsMono Nerd Font"
  readonly property string homeDir: Quickshell.env("HOME")

  implicitWidth: cavaRow.implicitWidth
  implicitHeight: root.barSize

  property var spectrum: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  property real bassLevel: 0
  property real midLevel: 0
  property real airLevel: 0

  function updateValues(vals) {
    spectrum = vals
    var b = 0, m = 0, a = 0
    for (var i = 0; i < 4; i++) b += (vals[i] || 0)
    for (var j = 4; j < 10; j++) m += (vals[j] || 0)
    for (var k = 10; k < 16; k++) a += (vals[k] || 0)
    bassLevel = Math.min(1.0, (b / 4) / 100.0)
    midLevel = Math.min(1.0, (m / 6) / 100.0)
    airLevel = Math.min(1.0, (a / 6) / 100.0)
    waveCanvas.requestPaint()
  }

  Process {
    id: cavaProc
    command: ["cava", "-p", root.homeDir + "/.config/omarchy/cava.conf"]
    running: root.visible
    stdout: SplitParser {
      onRead: function(line) {
        if (!line) return
        var parts = line.trim().split(";")
        var vals = []
        for (var i = 0; i < parts.length; i++) {
          if (parts[i] !== "") vals.push(parseInt(parts[i], 10) || 0)
        }
        if (vals.length >= 12) {
          root.updateValues(vals)
        }
      }
    }
  }

  Row {
    id: cavaRow
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2

    // Inverted Stacked Meters: AIR (top), MID (middle), BASS (bottom)
    Column {
      id: metersCol
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: -2
      spacing: 0

      // AIR (Top)
      Row {
        spacing: 3
        Text {
          text: "AIR"
          font.family: root.fontFam
          font.pixelSize: 7
          font.bold: true
          color: root.airLevel > 0.6 ? root.urgentColor : root.secondaryColor
          anchors.verticalCenter: parent.verticalCenter
          width: 18
          horizontalAlignment: Text.AlignRight
        }
        Rectangle {
          width: 24
          height: 2
          color: Qt.rgba(root.secondaryColor.r, root.secondaryColor.g, root.secondaryColor.b, 0.22)
          anchors.verticalCenter: parent.verticalCenter
          Rectangle {
            anchors.left: parent.left
            height: parent.height
            width: Math.max(1, Math.round(parent.width * root.airLevel))
            color: Color.accent
          }
        }
      }

      // MID (Middle)
      Row {
        spacing: 3
        Text {
          text: "MID"
          font.family: root.fontFam
          font.pixelSize: 7
          font.bold: true
          color: root.midLevel > 0.6 ? root.urgentColor : root.secondaryColor
          anchors.verticalCenter: parent.verticalCenter
          width: 18
          horizontalAlignment: Text.AlignRight
        }
        Rectangle {
          width: 24
          height: 2
          color: Qt.rgba(root.secondaryColor.r, root.secondaryColor.g, root.secondaryColor.b, 0.22)
          anchors.verticalCenter: parent.verticalCenter
          Rectangle {
            anchors.left: parent.left
            height: parent.height
            width: Math.max(1, Math.round(parent.width * root.midLevel))
            color: Color.accent
          }
        }
      }

      // BASS (Bottom)
      Row {
        spacing: 3
        Text {
          text: "BASS"
          font.family: root.fontFam
          font.pixelSize: 7
          font.bold: true
          color: root.bassLevel > 0.6 ? root.urgentColor : root.secondaryColor
          anchors.verticalCenter: parent.verticalCenter
          width: 18
          horizontalAlignment: Text.AlignRight
        }
        Rectangle {
          width: 24
          height: 2
          color: Qt.rgba(root.secondaryColor.r, root.secondaryColor.g, root.secondaryColor.b, 0.22)
          anchors.verticalCenter: parent.verticalCenter
          Rectangle {
            anchors.left: parent.left
            height: parent.height
            width: Math.max(1, Math.round(parent.width * root.bassLevel))
            color: Color.accent
          }
        }
      }
    }

    // Dynamic LED Dot Matrix Visualizer
    Canvas {
      id: waveCanvas
      width: 140
      height: 16
      anchors.verticalCenter: parent.verticalCenter
      renderTarget: Canvas.FramebufferObject

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var w = width
        var h = height
        var s = root.spectrum
        if (!s || s.length < 12) return

        var numCols = 22
        var colStep = (w - 8) / (numCols - 1)

        for (var c = 0; c < numCols; c++) {
          var specIdx = Math.floor(c * (s.length - 1) / (numCols - 1))
          var val = Math.min(100, Math.max(0, s[specIdx]))
          var numDots = val > 0 ? Math.max(1, Math.min(5, Math.ceil((val / 100.0) * 5))) : 0
          var cx = 4 + c * colStep

          for (var d = 0; d < 5; d++) {
            var cy = (h - 3) - d * 2.6
            ctx.beginPath()
            ctx.arc(cx, cy, 1.3, 0, 2 * Math.PI)
            if (d < numDots) {
              if (d === numDots - 1) {
                ctx.fillStyle = Color.accent ? Color.accent : "#ff51c5"
              } else {
                ctx.fillStyle = root.secondaryColor
              }
            } else {
              ctx.fillStyle = Qt.rgba(root.secondaryColor.r, root.secondaryColor.g, root.secondaryColor.b, 0.28)
            }
            ctx.fill()
          }
        }
      }
    }
  }
}
