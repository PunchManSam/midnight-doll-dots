import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons

PopupWindow {
  id: root

  required property Item anchorItem
  required property QtObject bar
  property var owner: null
  property int margin: Style.gapsOut
  property int padding: Style.spacing.popupPadding
  property int contentWidth: Style.space(280)
  property int contentHeight: Style.space(200)
  property color borderColor: Commons.Color.popups.border
  property var borderSpec: Border.localOrSurfaceSpec("popups", "border", borderColor, Commons.Color.popups.border, Math.max(1, Style.space(2)))
  property bool open: false
  property bool centerOnBar: false
  // "click" — uses HyprlandFocusGrab so clicking outside dismisses the popup.
  // "hover" — passive overlay; the owning widget controls open via hover.
  property string triggerMode: "click"

  readonly property bool isMidnightDoll: {
    if (bar && bar.isMidnightDoll !== undefined) return bar.isMidnightDoll
    if (Style.themeName) {
      var n = Style.themeName.toLowerCase().replace(/[\s_-]+/g, "")
      if (n === "midnightdoll" || n.indexOf("midnightdoll") >= 0) return true
    }
    return false
  }
  readonly property bool isBarTransparent: isMidnightDoll && bar && (bar.transparent === true)

  readonly property var coordinatorKey: owner || root
  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property var popupScreen: (anchorWindow && anchorWindow.screen)
    ? anchorWindow.screen
    : (bar && bar.screen ? bar.screen : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null))
  readonly property bool containsMouse: cardHover.hovered
  readonly property real screenW: popupScreen ? popupScreen.width : (Quickshell.screens.length > 0 ? Quickshell.screens[0].width : 1920)
  readonly property real screenH: popupScreen ? popupScreen.height : (Quickshell.screens.length > 0 ? Quickshell.screens[0].height : 1080)
  readonly property real barW: anchorWindow ? anchorWindow.width : 0
  readonly property real barH: anchorWindow ? anchorWindow.height : 0
  readonly property real availableCardWidth: screenW > 0
    ? Math.max(120, screenW - ((bar && (bar.position === "left" || bar.position === "right")) ? barW : 0) - root.margin * 2)
    : 0
  readonly property real availableCardHeight: screenH > 0
    ? Math.max(120, screenH - ((bar && (bar.position === "top" || bar.position === "bottom")) ? barH : 0) - root.margin * 2)
    : 0
  readonly property real verticalContentInset: padding * 2 + Border.top(borderSpec) + Border.bottom(borderSpec)

  function fittedContentWidth(width, cap) {
    var desired = Math.max(1, Number(width) || 1)
    var maxWidth = root.availableCardWidth > 0 ? root.availableCardWidth : desired
    if (cap !== undefined && Number(cap) > 0) maxWidth = Math.min(maxWidth, Number(cap))
    return Math.round(Math.min(desired, maxWidth))
  }

  function fittedContentHeight(implicitHeight, cap) {
    var desired = Math.max(root.verticalContentInset, (Number(implicitHeight) || 0) + root.verticalContentInset)
    var maxHeight = root.availableCardHeight > 0 ? root.availableCardHeight : desired
    if (cap !== undefined && Number(cap) > 0) maxHeight = Math.min(maxHeight, Number(cap))
    return Math.round(Math.min(desired, maxHeight))
  }

  function cappedContentHeight(height) {
    var desired = Math.max(root.padding * 2, Number(height) || root.padding * 2)
    var maxHeight = root.availableCardHeight > 0 ? root.availableCardHeight : desired
    return Math.round(Math.min(desired, maxHeight))
  }

  function close() {
    if (owner && "close" in owner) owner.close()
    else root.open = false
  }

  default property alias contentItem: contentHolder.children

  visible: open || card.opacity > 0
  color: "transparent"
  implicitWidth: contentWidth
  implicitHeight: contentHeight

  onOpenChanged: {
    if (!bar) return
    if (open) bar.requestPopout(coordinatorKey)
    else if (bar.activePopout === coordinatorKey) bar.releasePopout(coordinatorKey)
  }

  // Outside-click dismissal via Hyprland's focus grab. While `active`, input
  // is routed only to the listed windows; clicking anywhere else clears the
  // grab and we close the popup. Skipped for hover-mode popups so the cursor
  // can move freely between the trigger and the popup.
  HyprlandFocusGrab {
    active: root.open && root.triggerMode === "click"
    windows: root.anchorWindow ? [root, root.anchorWindow] : [root]
    onCleared: root.close()
  }

  anchor {
    id: popupAnchor
    window: anchorItem ? anchorItem.QsWindow.window : null
    adjustment: PopupAdjustment.Slide
    edges: Edges.Top | Edges.Left
    gravity: Edges.Bottom | Edges.Right
    rect.width: 1
    rect.height: 1

    onAnchoring: {
      if (!root.anchorItem || !root.bar) return

      var target = root.anchorItem
      var popupWidth = root.implicitWidth
      var popupHeight = root.implicitHeight
      var localX = target.width / 2 - popupWidth / 2
      var localY = target.height + root.margin

      if (root.bar.position === "bottom") {
        localY = -popupHeight - root.margin
      } else if (root.bar.position === "left") {
        localX = target.width + root.margin
        localY = target.height / 2 - popupHeight / 2
      } else if (root.bar.position === "right") {
        localX = -popupWidth - root.margin
        localY = target.height / 2 - popupHeight / 2
      }

      var window = target.QsWindow.window
      if (!window) return

      if (root.centerOnBar) {
        var cx = 0;
        var cy = 0;
        if (root.bar.position === "top" || root.bar.position === "bottom") {
          cx = window.width / 2 - popupWidth / 2
          if (root.bar.position === "bottom") {
            cy = -popupHeight - root.margin
          } else {
            cy = (root.isMidnightDoll && !root.isBarTransparent) ? ((root.bar.barSize !== undefined ? root.bar.barSize : 30) - 1) : (window.height + root.margin)
          }
          cx = Math.max(root.margin, Math.min(cx, window.width - popupWidth - root.margin))
        } else {
          cx = root.bar.position === "left" ? ((root.isMidnightDoll && !root.isBarTransparent) ? ((root.bar.barSize !== undefined ? root.bar.barSize : 36) - 1) : (window.width + root.margin)) : -popupWidth - root.margin
          cy = window.height / 2 - popupHeight / 2
          cy = Math.max(root.margin, Math.min(cy, window.height - popupHeight - root.margin))
        }

        popupAnchor.rect.x = Math.round(cx)
        popupAnchor.rect.y = Math.round(cy)
        return
      }

      var point = window.contentItem.mapFromItem(target, localX, localY)

      if (root.bar.position === "top" || root.bar.position === "bottom") {
        point.x = Math.max(root.margin, Math.min(point.x, window.width - popupWidth - root.margin))
        if (root.bar.position === "top" && root.isMidnightDoll && !root.isBarTransparent) {
          point.y = (root.bar.barSize !== undefined ? root.bar.barSize : 30) - 1
        }
      } else {
        point.y = Math.max(root.margin, Math.min(point.y, window.height - popupHeight - root.margin))
        if (root.bar.position === "left" && root.isMidnightDoll && !root.isBarTransparent) {
          point.x = (root.bar.barSize !== undefined ? root.bar.barSize : 36) - 1
        }
      }

      popupAnchor.rect.x = Math.round(point.x)
      popupAnchor.rect.y = Math.round(point.y)
    }
  }

  readonly property bool isSnappedBottom: !isBarTransparent && isMidnightDoll && root.bar && (root.bar.position === "left" || root.bar.position === "right") && (popupAnchor.rect.y + contentHeight >= screenH - 2)

  Item {
    id: card
    anchors.fill: parent
    opacity: root.open ? 1.0 : 0

    readonly property real shelfRadius: Math.min(Style.cornerRadius > 0 ? Style.cornerRadius : 14, Math.floor(Math.min(card.width, card.height) / 2))

    readonly property real borderTop: (root.isMidnightDoll && !root.isBarTransparent) ? (root.bar && root.bar.position === "top" ? 0 : 1) : Border.top(root.borderSpec)
    readonly property real borderRight: root.isMidnightDoll ? 1 : Border.right(root.borderSpec)
    readonly property real borderBottom: (root.isMidnightDoll && !root.isBarTransparent) ? (root.isSnappedBottom ? 0 : 1) : Border.bottom(root.borderSpec)
    readonly property real borderLeft: (root.isMidnightDoll && !root.isBarTransparent) ? (root.bar && root.bar.position === "left" ? 0 : 1) : Border.left(root.borderSpec)

    readonly property real contentTopInset: (root.isMidnightDoll && !root.isBarTransparent) ? (root.bar && root.bar.position === "top" ? (root.padding + 2) : (root.padding + 1)) : (borderTop + root.padding)
    readonly property real contentRightInset: root.isMidnightDoll ? (root.padding + 1) : (borderRight + root.padding)
    readonly property real contentBottomInset: (root.isMidnightDoll && !root.isBarTransparent) ? (root.isSnappedBottom ? root.padding : (root.padding + 1)) : (borderBottom + root.padding)
    readonly property real contentLeftInset: (root.isMidnightDoll && !root.isBarTransparent) ? (root.bar && root.bar.position === "left" ? (root.padding + 2) : (root.padding + 1)) : (borderLeft + root.padding)

    // Stock BorderSurface for non-midnight themes
    BorderSurface {
      anchors.fill: parent
      visible: !root.isMidnightDoll
      color: Commons.Color.popups.background
      borderSpec: root.borderSpec
      padding: root.padding
      radius: Style.cornerRadius
    }

    // Midnight-doll shelf background fill (seamless #010101 with bar, or all rounded when transparent)
    Rectangle {
      id: shelfBackground
      anchors.fill: parent
      visible: root.isMidnightDoll
      color: "#010101"
      topLeftRadius: root.isBarTransparent ? card.shelfRadius : 0
      topRightRadius: (root.isBarTransparent || (root.bar && root.bar.position === "left")) ? card.shelfRadius : 0
      bottomLeftRadius: (root.isBarTransparent || (root.bar && root.bar.position === "top")) ? card.shelfRadius : 0
      bottomRightRadius: (!root.isBarTransparent && root.isSnappedBottom) ? 0 : card.shelfRadius
    }

    // Midnight-doll dedicated floating panel shape when bar is transparent (all 4 rounded corners + continuous border)
    Shape {
      id: shelfBorderDedicatedPanel
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      asynchronous: false
      visible: root.isMidnightDoll && root.isBarTransparent
      z: 10

      ShapePath {
        strokeWidth: 1.0
        strokeColor: Commons.Color.accent
        fillColor: "transparent"
        capStyle: ShapePath.FlatCap
        joinStyle: ShapePath.RoundJoin

        startX: card.shelfRadius + 0.5
        startY: 0.5
        PathLine { x: card.width - card.shelfRadius - 0.5; y: 0.5 }
        PathAngleArc {
          centerX: card.width - card.shelfRadius - 0.5
          centerY: card.shelfRadius + 0.5
          radiusX: card.shelfRadius
          radiusY: card.shelfRadius
          startAngle: -90
          sweepAngle: 90
        }
        PathLine { x: card.width - 0.5; y: card.height - card.shelfRadius - 0.5 }
        PathAngleArc {
          centerX: card.width - card.shelfRadius - 0.5
          centerY: card.height - card.shelfRadius - 0.5
          radiusX: card.shelfRadius
          radiusY: card.shelfRadius
          startAngle: 0
          sweepAngle: 90
        }
        PathLine { x: card.shelfRadius + 0.5; y: card.height - 0.5 }
        PathAngleArc {
          centerX: card.shelfRadius + 0.5
          centerY: card.height - card.shelfRadius - 0.5
          radiusX: card.shelfRadius
          radiusY: card.shelfRadius
          startAngle: 90
          sweepAngle: 90
        }
        PathLine { x: 0.5; y: card.shelfRadius + 0.5 }
        PathAngleArc {
          centerX: card.shelfRadius + 0.5
          centerY: card.shelfRadius + 0.5
          radiusX: card.shelfRadius
          radiusY: card.shelfRadius
          startAngle: 180
          sweepAngle: 90
        }
      }
    }

    // Midnight-doll shelf continuous pink accent border for top bar
    Shape {
      id: shelfBorderTop
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      asynchronous: false
      visible: root.isMidnightDoll && !root.isBarTransparent && (!root.bar || root.bar.position !== "left")
      z: 10

      ShapePath {
        strokeWidth: 1.0
        strokeColor: Commons.Color.accent
        fillColor: "transparent"
        capStyle: ShapePath.FlatCap
        joinStyle: ShapePath.RoundJoin

        startX: 0.5
        startY: 0.0
        PathLine { x: 0.5; y: card.height - card.shelfRadius - 0.5 }
        PathAngleArc {
          centerX: card.shelfRadius + 0.5
          centerY: card.height - card.shelfRadius - 0.5
          radiusX: card.shelfRadius
          radiusY: card.shelfRadius
          startAngle: 180
          sweepAngle: -90
        }
        PathLine { x: card.width - card.shelfRadius - 0.5; y: card.height - 0.5 }
        PathAngleArc {
          centerX: card.width - card.shelfRadius - 0.5
          centerY: card.height - card.shelfRadius - 0.5
          radiusX: card.shelfRadius
          radiusY: card.shelfRadius
          startAngle: 90
          sweepAngle: -90
        }
        PathLine { x: card.width - 0.5; y: 0.0 }
      }
    }

    // Midnight-doll shelf continuous pink accent border for left bar (standard)
    Shape {
      id: shelfBorderLeftStandard
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      asynchronous: false
      visible: root.isMidnightDoll && !root.isBarTransparent && root.bar && root.bar.position === "left" && !root.isSnappedBottom
      z: 10

      ShapePath {
        strokeWidth: 1.0
        strokeColor: Commons.Color.accent
        fillColor: "transparent"
        capStyle: ShapePath.FlatCap
        joinStyle: ShapePath.RoundJoin

        startX: 0.0
        startY: 0.5
        PathLine { x: card.width - card.shelfRadius - 0.5; y: 0.5 }
        PathAngleArc {
          centerX: card.width - card.shelfRadius - 0.5
          centerY: card.shelfRadius + 0.5
          radiusX: card.shelfRadius
          radiusY: card.shelfRadius
          startAngle: -90
          sweepAngle: 90
        }
        PathLine { x: card.width - 0.5; y: card.height - card.shelfRadius - 0.5 }
        PathAngleArc {
          centerX: card.width - card.shelfRadius - 0.5
          centerY: card.height - card.shelfRadius - 0.5
          radiusX: card.shelfRadius
          radiusY: card.shelfRadius
          startAngle: 0
          sweepAngle: 90
        }
        PathLine { x: 0.0; y: card.height - 0.5 }
      }
    }

    // Midnight-doll shelf continuous pink accent border for left bar (snapped-bottom)
    Shape {
      id: shelfBorderLeftSnappedBottom
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      asynchronous: false
      visible: root.isMidnightDoll && !root.isBarTransparent && root.bar && root.bar.position === "left" && root.isSnappedBottom
      z: 10

      ShapePath {
        strokeWidth: 1.0
        strokeColor: Commons.Color.accent
        fillColor: "transparent"
        capStyle: ShapePath.FlatCap
        joinStyle: ShapePath.RoundJoin

        startX: 0.0
        startY: 0.5
        PathLine { x: card.width - card.shelfRadius - 0.5; y: 0.5 }
        PathAngleArc {
          centerX: card.width - card.shelfRadius - 0.5
          centerY: card.shelfRadius + 0.5
          radiusX: card.shelfRadius
          radiusY: card.shelfRadius
          startAngle: -90
          sweepAngle: 90
        }
        PathLine { x: card.width - 0.5; y: card.height }
      }
    }

    Behavior on opacity {
      NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic }
    }

    Item {
      id: contentHolder
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
    }

    HoverHandler {
      id: cardHover
    }
  }
}
