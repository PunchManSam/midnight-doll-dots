import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Layer-shell popup attached to a bar widget icon, designed for
// click-driven AND keyboard-driven panels (e.g. SUPER+CTRL+W summon).
//
// Built on PanelWindow with a brief WlrKeyboardFocus.Exclusive prime followed
// by OnDemand rather than PopupWindow (xdg-popup). The prime acquires focus
// both when the surface maps and when it reopens while still mapped for its
// fade-out. xdg-popups don't get that — they only receive keys after a
// click/hover routes focus through their parent surface — so keyboard-summoned
// popups fell flat without it.
//
// Exclusive would also grant map-time focus, but it makes Hyprland route
// *every* pointer event to the exclusive surface no matter which output
// the cursor is over, which leaves clicks on any other monitor unable to
// reach the dismissal surfaces below.
//
// API is a subset of Common.PopupCard: anchorItem, owner, bar, open,
// padding, margin, contentWidth/Height, centerOnBar, default contentItem.
// Missing on purpose (for now): triggerMode ("hover"), containsMouse.
//
// Positioning: full-screen layer-shell with the card placed inside at
// `cardOrigin`. We use the bar window's height/width for the perpendicular
// axis (away-from-bar) because mapToItem on the anchor returns
// bar-content-relative coords with internal layout offsets baked in
// (e.g. ~13px from the bar's vertical centering of its widget row). The
// parallel axis (along-the-bar) uses the anchor's content x/y since the
// bar spans full screen on that axis.
//
// Outside-click dismissal: an overlay MouseArea catches clicks, with the
// QsWindow.mask subtracting the bar strip so clicks on the bar still
// reach the bar widgets (activePopout coordinator hands off to another
// popup if the user clicks a different bar icon).
PanelWindow {
  id: root

  required property Item anchorItem
  required property QtObject bar
  property var owner: null
  property int margin: Style.gapsOut
  property int padding: Style.spacing.popupPadding
  property int contentWidth: Style.space(280)
  property int contentHeight: Style.space(200)
  property var borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
  property bool centerOnBar: false
  property bool open: false
  property int gap: Style.gapsOut  // distance between bar edge and panel
  property bool popoutSwitching: false
  property bool popoutSwitchClosing: false
  property bool focusPrimed: false

  readonly property bool isTargetOpen: root.open && !root.popoutSwitchClosing
  property real slideProgress: isTargetOpen ? 1.0 : 0.0

  Behavior on slideProgress {
    enabled: !root.popoutSwitching
    NumberAnimation {
      duration: root.isTargetOpen ? Style.duration(220) : Style.duration(160)
      easing.type: root.isTargetOpen ? Easing.OutCubic : Easing.InCubic
    }
  }

  readonly property bool isMidnightDoll: {
    if (bar && bar.isMidnightDoll !== undefined) return bar.isMidnightDoll
    if (Style.themeName) {
      var n = Style.themeName.toLowerCase().replace(/[\s_-]+/g, "")
      if (n === "midnightdoll" || n.indexOf("midnightdoll") >= 0) return true
    }
    return false
  }

  readonly property bool isBarTransparent: isMidnightDoll && bar && (bar.transparent === true)

  // Item that should take keyboard focus once the panel maps. Typically a
  // PanelKeyCatcher inside the panel content. Layer-shell grants focus to the
  // surface during the Exclusive prime, but Qt still needs an active-focus
  // target inside the surface for Keys.onPressed handlers to fire. Schedule
  // the focus through Qt.callLater so it runs after the surface is fully
  // mapped and child items have completed layout.
  property Item focusTarget: null

  default property alias contentItem: contentHolder.children

  readonly property var coordinatorKey: owner || root
  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property string barPos: bar ? bar.position : "top"

  function close() {
    if (owner && "close" in owner) owner.close()
    else root.open = false
  }

  function beginFocusPrime() {
    if (open && backingWindowVisible) focusPrimeTimer.restart()
  }

  // --- screen + lifetime ---------------------------------------------------

  screen: (anchorWindow && anchorWindow.screen)
    ? anchorWindow.screen
    : (bar && bar.screen ? bar.screen : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null))
  visible: open || slideProgress > 0.001 || card.opacity > 0 || popoutSwitching
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore

  WlrLayershell.namespace: "omarchy-keyboard-panel"
  WlrLayershell.layer: WlrLayer.Overlay
  // Keyboard focus follows `open` (NOT `visible`). The window remains
  // mapped during the fade-out so the opacity animation has something to
  // animate, but keyboard/click ownership must release the moment the
  // logical close fires — otherwise the user is locked out for 140ms.
  //
  // Prime with Exclusive on every open, then settle on OnDemand. Hyprland
  // focuses OnDemand when a surface first maps, but not when an already-mapped
  // fade-out surface changes from None back to OnDemand. Exclusive also takes
  // focus when the previously focused application has constrained the pointer.
  // The brief prime covers both cases; OnDemand then releases compositor-wide
  // pointer hit-testing so clicks can reach the dismissal windows below.
  WlrLayershell.keyboardFocus: open
    ? (focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
    : WlrKeyboardFocus.None

  onBackingWindowVisibleChanged: beginFocusPrime()

  // Full-screen layer-shell. The visible card is positioned inside via
  // `cardOrigin`. The `mask` below makes the bar area click-through (so
  // the user can click another bar icon while the panel is open and the
  // activePopout coordinator swaps to that popup); everywhere else, the
  // overlay catches the click and dismisses via the MouseArea below.
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  // Clickable region is the whole screen. Clicks in the bar strip are
  // forwarded to registered bar buttons so switching between panel icons
  // works in one click even when the overlay surface is above the bar.
  readonly property real _barStripSize: {
    if (!bar) return 0
    var actual = (root.barPos === "top" || root.barPos === "bottom") ? root.barH : root.barW
    return Math.max(bar.barSize, actual) + root.gap
  }
  mask: Region {
    width: root.screenW
    height: root.screenH
  }

  // Track every layout change between the bar's contentItem and the
  // anchor item. `transform` updates whenever any item in that chain
  // moves/resizes, which is what makes the position binding below
  // actually reactive — mapToItem on its own is a one-shot.
  TransformWatcher {
    id: anchorWatcher
    a: anchorWindow ? anchorWindow.contentItem : null
    b: anchorItem
  }

  // Anchor item's position within the bar's content surface. For a
  // full-width top bar, the content x maps directly to screen x; the y
  // returned here has the bar's internal padding baked in (e.g. ~13px
  // from vertical centering of the widget row), which is why `cardOrigin`
  // below uses `barH` for the perpendicular axis instead of this y.
  readonly property point anchorScreenPos: {
    anchorWatcher.transform  // reactive dependency
    if (!anchorItem) return Qt.point(0, 0)
    try {
      if (anchorWindow && anchorWindow.contentItem) {
        return anchorItem.mapToItem(anchorWindow.contentItem, 0, 0)
      }
      return anchorItem.mapToItem(null, 0, 0)
    } catch (e) {
      return Qt.point(0, 0)
    }
  }
  readonly property real anchorW: anchorItem ? anchorItem.width : 0
  readonly property real anchorH: anchorItem ? anchorItem.height : 0
  readonly property real screenW: screen ? screen.width : (Quickshell.screens.length > 0 ? Quickshell.screens[0].width : 1920)
  readonly property real screenH: screen ? screen.height : (Quickshell.screens.length > 0 ? Quickshell.screens[0].height : 1080)
  readonly property real availableCardWidth: screenW > 0
    ? Math.max(120, screenW - ((barPos === "left" || barPos === "right") ? (root.isMidnightDoll ? (bar ? bar.barSize : 36) : (barW + gap)) + margin : margin * 2))
    : 0
  readonly property real availableCardHeight: screenH > 0
    ? Math.max(120, screenH - ((barPos === "top" || barPos === "bottom") ? (root.isMidnightDoll ? (bar ? bar.barSize : 30) : (barH + gap)) + margin : margin * 2))
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

  readonly property real barW: anchorWindow ? anchorWindow.width : (bar && bar.barSize ? bar.barSize : 36)
  readonly property real barH: anchorWindow ? anchorWindow.height : (bar && bar.barSize ? bar.barSize : 30)

  readonly property real snapDistance: Style.space(48)
  readonly property real leftBarEdge: isMidnightDoll ? 35 : 0
  readonly property real topBarEdge: isMidnightDoll ? 29 : 0

  readonly property bool isSnappedLeft: !isBarTransparent && isMidnightDoll && (barPos === "top" || barPos === "bottom") && (cardOrigin.x <= leftBarEdge + 1)
  readonly property bool isSnappedRight: !isBarTransparent && isMidnightDoll && (barPos === "top" || barPos === "bottom") && (cardOrigin.x + contentWidth >= screenW - 2)
  readonly property bool isSnappedBottom: !isBarTransparent && isMidnightDoll && (barPos === "left" || barPos === "right") && (cardOrigin.y + contentHeight >= screenH - 2)
  readonly property bool isSnappedTop: !isBarTransparent && isMidnightDoll && (barPos === "left" || barPos === "right") && (cardOrigin.y <= topBarEdge + 1)

  readonly property point cardOrigin: {
    if (!anchorItem || !bar) return Qt.point(margin, margin)
    var x = 0, y = 0

    if (isBarTransparent) {
      if (centerOnBar && (barPos === "top" || barPos === "bottom")) {
        x = screenW / 2 - contentWidth / 2
        y = (barPos === "bottom") ? (screenH - barH - contentHeight - margin) : (topBarEdge + margin)
      } else if (centerOnBar) {
        x = (barPos === "left") ? (leftBarEdge + margin) : (screenW - barW - contentWidth - margin)
        y = screenH / 2 - contentHeight / 2
      } else if (barPos === "left") {
        x = leftBarEdge + margin
        var targetY = anchorScreenPos.y + anchorH / 2 - contentHeight / 2
        y = Math.max(margin, Math.min(targetY, screenH - contentHeight - margin))
      } else if (barPos === "right") {
        x = screenW - barW - contentWidth - margin
        var targetY = anchorScreenPos.y + anchorH / 2 - contentHeight / 2
        y = Math.max(margin, Math.min(targetY, screenH - contentHeight - margin))
      } else if (barPos === "bottom") {
        x = Math.max(margin, Math.min(anchorScreenPos.x + anchorW / 2 - contentWidth / 2, screenW - contentWidth - margin))
        y = screenH - barH - contentHeight - margin
      } else { // "top"
        x = Math.max(margin, Math.min(anchorScreenPos.x + anchorW / 2 - contentWidth / 2, screenW - contentWidth - margin))
        y = topBarEdge + margin
      }
      return Qt.point(Math.round(x), Math.round(y))
    }

    if (centerOnBar && (barPos === "top" || barPos === "bottom")) {
      x = screenW / 2 - contentWidth / 2
      if (barPos === "bottom") {
        y = screenH - barH - contentHeight - gap
      } else {
        y = isMidnightDoll ? topBarEdge : (barH + gap)
      }
    } else if (centerOnBar) {
      if (barPos === "left") {
        x = isMidnightDoll ? leftBarEdge : (barW + gap)
      } else {
        x = screenW - barW - contentWidth - gap
      }
      y = screenH / 2 - contentHeight / 2
    } else if (barPos === "bottom") {
      x = anchorScreenPos.x + anchorW / 2 - contentWidth / 2
      y = screenH - barH - contentHeight - gap
    } else if (barPos === "left") {
      x = isMidnightDoll ? leftBarEdge : (barW + gap)
      var targetY = anchorScreenPos.y + anchorH / 2 - contentHeight / 2
      if (isMidnightDoll) {
        if (anchorScreenPos.y >= screenH / 2 || (targetY + contentHeight >= screenH - snapDistance)) {
          y = screenH - contentHeight
        } else if (targetY <= topBarEdge + snapDistance) {
          y = topBarEdge
        } else {
          y = Math.max(topBarEdge + margin, Math.min(targetY, screenH - contentHeight - margin))
        }
      } else {
        y = targetY
      }
    } else if (barPos === "right") {
      x = screenW - barW - contentWidth - gap
      y = anchorScreenPos.y + anchorH / 2 - contentHeight / 2
    } else { // "top" (default)
      var targetX = anchorScreenPos.x + anchorW / 2 - contentWidth / 2
      if (isMidnightDoll) {
        if (targetX <= leftBarEdge + snapDistance) {
          x = leftBarEdge
        } else if (targetX + contentWidth >= screenW - snapDistance) {
          x = screenW - contentWidth
        } else {
          x = Math.max(leftBarEdge + margin, Math.min(targetX, screenW - contentWidth - margin))
        }
        y = topBarEdge
      } else {
        x = targetX
        y = barH + gap
      }
    }

    if (!isMidnightDoll) {
      x = Math.max(margin, Math.min(x, screenW - contentWidth - margin))
      y = Math.max(margin, Math.min(y, screenH - contentHeight - margin))
    }
    return Qt.point(Math.round(x), Math.round(y))
  }


  // --- popout coordination (same-bar single-popout model) -----------------

  // Coordinate on `open`, not `visible`. `visible` lags into the fade-out
  // animation, which made ownership transfer to a sibling popup race.
  onOpenChanged: {
    if (open) {
      focusPrimed = false
      beginFocusPrime()
      if (focusTarget) Qt.callLater(function() {
        if (root.open && root.focusTarget) root.focusTarget.forceActiveFocus()
      })
    } else {
      focusPrimeTimer.stop()
      focusPrimed = false
    }
    if (!bar) return
    if (open) {
      popoutSwitchClosing = false
      popoutSwitching = bar.activePopout && bar.activePopout !== coordinatorKey
      bar.requestPopout(coordinatorKey)
      if (popoutSwitching) popoutSwitchTimer.restart()
    } else {
      popoutSwitchClosing = !!(owner && owner.popoutSwitchClosing)
      popoutSwitching = false
      if (bar.activePopout === coordinatorKey) bar.releasePopout(coordinatorKey)
      if (popoutSwitchClosing) closeSwitchTimer.restart()
    }
  }

  Timer {
    id: focusPrimeTimer
    // Leave enough time for multiple Qt/Wayland commit cycles after the
    // backing window becomes visible while keeping the compositor-wide
    // Exclusive phase imperceptibly short. This interval is covered by the
    // immediate hide/re-summon acceptance case.
    interval: 75
    onTriggered: if (root.open) root.focusPrimed = true
  }

  Timer {
    id: popoutSwitchTimer
    interval: 150
    onTriggered: root.popoutSwitching = false
  }

  Timer {
    id: closeSwitchTimer
    interval: 1
    onTriggered: root.popoutSwitchClosing = false
  }

  // --- outside-click dismissal --------------------------------------------

  // Catches clicks anywhere in the clickable region (i.e. everywhere on
  // screen except the bar strip, which is masked out). The card has its
  // own MouseArea below so clicks on it don't bubble up here. Disabled
  // during the fade-out so the dying overlay doesn't swallow clicks that
  // were meant for the apps behind it.
  MouseArea {
    id: dismissArea
    anchors.fill: parent
    enabled: root.open
    acceptedButtons: Qt.AllButtons
    hoverEnabled: true
    property bool hoveringBar: false
    cursorShape: hoveringBar ? Qt.PointingHandCursor : Qt.ArrowCursor

    function inBarRegion(px, py) {
      if (root.barPos === "bottom") return py >= root.screenH - root._barStripSize
      if (root.barPos === "left") return px <= root._barStripSize
      if (root.barPos === "right") return px >= root.screenW - root._barStripSize
      return py <= root._barStripSize
    }

    function barPoint(px, py) {
      if (root.barPos === "bottom") return Qt.point(px, py - (root.screenH - root.barH))
      if (root.barPos === "right") return Qt.point(px - (root.screenW - root.barW), py)
      return Qt.point(px, py)
    }

    function pressTargetAt(px, py) {
      if (!root.anchorWindow || !root.anchorWindow.contentItem || !root.bar || !root.bar.clickTargets) return null
      var p = barPoint(px, py)
      var targets = root.bar.clickTargets
      for (var i = targets.length - 1; i >= 0; i--) {
        var target = targets[i]
        if (!target || !target.triggerPress || target.visible === false || target.opacity === 0 || !target.mapToItem) continue
        if (root.bar.targetBelongsToWindow && !root.bar.targetBelongsToWindow(target, root.anchorWindow)) continue
        var pos = root.anchorWindow.itemPosition(target)
        if (p.x >= pos.x && p.x <= pos.x + target.width && p.y >= pos.y && p.y <= pos.y + target.height) return target
      }
      return null
    }

    function forwardBarClick(px, py, button) {
      if (button !== Qt.LeftButton && button !== Qt.RightButton && button !== Qt.MiddleButton) return false
      var target = pressTargetAt(px, py)
      if (!target) return false
      target.triggerPress(button)
      return true
    }

    onPositionChanged: function(mouse) { hoveringBar = inBarRegion(mouse.x, mouse.y) }
    onExited: hoveringBar = false
    onClicked: function(mouse) {
      // While Exclusive is priming, Hyprland may route a click from another
      // output here with translated coordinates. Never interpret that as a
      // click on this output's bar.
      if (root.focusPrimed && inBarRegion(mouse.x, mouse.y) && forwardBarClick(mouse.x, mouse.y, mouse.button)) return
      root.close()
    }
  }

  // The panel surface only spans the anchor's screen, and the compositor
  // hit-tests pointer input per output, so `dismissArea` above can never see
  // a click on another monitor. Give every other output a transparent twin
  // whose only job is to catch that click. They exist only while the panel is
  // logically open (not during the fade-out, matching `dismissArea.enabled`).
  //
  // Keyboard focus is None: these must catch the pointer without taking focus
  // from the panel when the cursor merely crosses onto their output.
  Variants {
    model: root.open ? Quickshell.screens : []

    delegate: Component {
      PanelWindow {
        required property var modelData

        screen: modelData
        // Compare by output name: the anchor screen must be known before any
        // twin maps, or a twin would cover the panel's own output.
        visible: root.open && !!root.screen && modelData.name !== root.screen.name
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore

        WlrLayershell.namespace: "omarchy-keyboard-panel-dismiss"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
          top: true
          bottom: true
          left: true
          right: true
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.AllButtons
          onPressed: root.close()
        }
      }
    }
  }

  // --- shelf clip & slide container ----------------------------------------

  Item {
    id: shelfClip
    x: (root.isMidnightDoll && !root.isBarTransparent) ? (root.barPos === "left" ? root.leftBarEdge : 0) : 0
    y: (root.isMidnightDoll && !root.isBarTransparent) ? (root.barPos === "top" ? root.topBarEdge : 0) : 0
    width: (root.isMidnightDoll && !root.isBarTransparent) ? (root.barPos === "left" ? (root.screenW - root.leftBarEdge) : (root.barPos === "right" ? (root.screenW - root.barW) : root.screenW)) : root.screenW
    height: (root.isMidnightDoll && !root.isBarTransparent) ? (root.barPos === "top" ? (root.screenH - root.topBarEdge) : (root.barPos === "bottom" ? (root.screenH - root.barH) : root.screenH)) : root.screenH
    clip: root.isMidnightDoll && !root.isBarTransparent

    Item {
      id: card
      readonly property real targetLocalX: root.cardOrigin.x - shelfClip.x
      readonly property real targetLocalY: root.cardOrigin.y - shelfClip.y

      readonly property real slideDistanceX: (root.isMidnightDoll && !root.isBarTransparent) ? card.width : Style.space(24)
      readonly property real slideDistanceY: (root.isMidnightDoll && !root.isBarTransparent) ? card.height : Style.space(24)

      x: {
        var base = targetLocalX
        if (root.barPos === "left") return Math.round(base - slideDistanceX * (1.0 - root.slideProgress))
        if (root.barPos === "right") return Math.round(base + slideDistanceX * (1.0 - root.slideProgress))
        return Math.round(base)
      }
      y: {
        var base = targetLocalY
        if (root.barPos === "top") return Math.round(base - slideDistanceY * (1.0 - root.slideProgress))
        if (root.barPos === "bottom") return Math.round(base + slideDistanceY * (1.0 - root.slideProgress))
        return Math.round(base)
      }
      width: root.contentWidth
      height: root.contentHeight
      opacity: root.popoutSwitching ? (root.open ? 1.0 : 0) : Math.max(0, Math.min(1, root.slideProgress * 1.5))

    readonly property real shelfRadius: Math.min(Style.cornerRadius > 0 ? Style.cornerRadius : 14, Math.floor(Math.min(card.width, card.height) / 2))

    readonly property real borderTop: root.isBarTransparent ? 1 : (root.isMidnightDoll ? (root.barPos === "top" ? 0 : (root.isSnappedTop ? 0 : 1)) : Border.top(root.borderSpec))
    readonly property real borderRight: root.isBarTransparent ? 1 : (root.isMidnightDoll ? (root.isSnappedRight ? 0 : 1) : Border.right(root.borderSpec))
    readonly property real borderBottom: root.isBarTransparent ? 1 : (root.isMidnightDoll ? (root.isSnappedBottom ? 0 : 1) : Border.bottom(root.borderSpec))
    readonly property real borderLeft: root.isBarTransparent ? 1 : (root.isMidnightDoll ? (root.barPos === "left" ? 0 : (root.isSnappedLeft ? 0 : 1)) : Border.left(root.borderSpec))

    readonly property real contentTopInset: root.isBarTransparent ? (root.padding + 1) : (root.isMidnightDoll ? (root.barPos === "top" ? (root.padding + 2) : (root.isSnappedTop ? (root.padding + 2) : (root.padding + 1))) : (borderTop + root.padding))
    readonly property real contentRightInset: root.isBarTransparent ? (root.padding + 1) : (root.isMidnightDoll ? (root.isSnappedRight ? root.padding : (root.padding + 1)) : (borderRight + root.padding))
    readonly property real contentBottomInset: root.isBarTransparent ? (root.padding + 1) : (root.isMidnightDoll ? (root.isSnappedBottom ? root.padding : (root.padding + 1)) : (borderBottom + root.padding))
    readonly property real contentLeftInset: root.isBarTransparent ? (root.padding + 1) : (root.isMidnightDoll ? (root.barPos === "left" ? (root.padding + 2) : (root.isSnappedLeft ? (root.padding + 2) : (root.padding + 1))) : (borderLeft + root.padding))

    // Stock BorderSurface for non-midnight themes
    BorderSurface {
      anchors.fill: parent
      visible: !root.isMidnightDoll
      color: Color.popups.background
      borderSpec: root.borderSpec
      padding: root.padding
      radius: Style.cornerRadius
    }

    // Midnight-doll shelf background fill (seamless #010101 with bar, or dedicated panel)
    Rectangle {
      id: shelfBackground
      anchors.fill: parent
      visible: root.isMidnightDoll
      color: "#010101"
      topLeftRadius: root.isBarTransparent ? card.shelfRadius : 0
      topRightRadius: root.isBarTransparent ? card.shelfRadius : ((root.barPos === "left" && !root.isSnappedTop) ? card.shelfRadius : 0)
      bottomLeftRadius: root.isBarTransparent ? card.shelfRadius : ((root.barPos === "top" && !root.isSnappedLeft) ? card.shelfRadius : 0)
      bottomRightRadius: root.isBarTransparent ? card.shelfRadius : ((root.isSnappedBottom || root.isSnappedRight) ? 0 : card.shelfRadius)
    }

    // Midnight-doll dedicated floating panel border when bar is transparent (rounded corners all around)
    Shape {
      id: shelfBorderDedicatedPanel
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      asynchronous: false
      visible: root.isMidnightDoll && root.isBarTransparent
      z: 10

      ShapePath {
        strokeWidth: 1.0
        strokeColor: Color.accent
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

    // Midnight-doll shelf continuous pink accent border for top bar (standard, when not snapped)
    Shape {
      id: shelfBorderTopStandard
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      asynchronous: false
      visible: root.isMidnightDoll && !root.isBarTransparent && root.barPos !== "left" && !root.isSnappedLeft && !root.isSnappedRight
      z: 10

      ShapePath {
        strokeWidth: 1.0
        strokeColor: Color.accent
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

    // Midnight-doll shelf continuous pink accent border for top bar (snapped-left: merged with left bar!)
    // No left border, no top border.
    // Starts at left bar seam (0.0, height - 0.5), runs bottom edge,
    // rounds bottom-right corner, runs up right edge to top bar.
    Shape {
      id: shelfBorderTopSnappedLeft
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      asynchronous: false
      visible: root.isMidnightDoll && !root.isBarTransparent && root.barPos !== "left" && root.isSnappedLeft
      z: 10

      ShapePath {
        strokeWidth: 1.0
        strokeColor: Color.accent
        fillColor: "transparent"
        capStyle: ShapePath.FlatCap
        joinStyle: ShapePath.RoundJoin

        startX: 0.0
        startY: card.height - 0.5
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

    // Midnight-doll shelf continuous pink accent border for top bar (snapped-right: merged with screen right edge!)
    // No right border, no top border.
    // Starts at top bar (0.5, 0.0), runs down left edge,
    // rounds bottom-left corner, runs along bottom to screen edge (card.width, height - 0.5).
    Shape {
      id: shelfBorderTopSnappedRight
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      asynchronous: false
      visible: root.isMidnightDoll && !root.isBarTransparent && root.barPos !== "left" && root.isSnappedRight && !root.isSnappedLeft
      z: 10

      ShapePath {
        strokeWidth: 1.0
        strokeColor: Color.accent
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
        PathLine { x: card.width; y: card.height - 0.5 }
      }
    }

    // Midnight-doll shelf continuous pink accent border for left bar (standard, floating along left bar)
    Shape {
      id: shelfBorderLeftStandard
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      asynchronous: false
      visible: root.isMidnightDoll && !root.isBarTransparent && root.barPos === "left" && !root.isSnappedBottom && !root.isSnappedTop
      z: 10

      ShapePath {
        strokeWidth: 1.0
        strokeColor: Color.accent
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

    // Midnight-doll shelf continuous pink accent border for left bar (snapped-bottom: flush with screen bottom!)
    // Top border runs to top-right corner, rounds, right border runs straight down to screen bottom.
    // Zero bottom line, zero bottom-right arc.
    Shape {
      id: shelfBorderLeftSnappedBottom
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      asynchronous: false
      visible: root.isMidnightDoll && !root.isBarTransparent && root.barPos === "left" && root.isSnappedBottom && !root.isSnappedTop
      z: 10

      ShapePath {
        strokeWidth: 1.0
        strokeColor: Color.accent
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

    // Midnight-doll shelf continuous pink accent border for left bar (snapped-top: flush with top bar!)
    // Zero top line, zero top-right arc.
    // Right border runs from top bar down, rounds bottom-right corner, bottom line runs to left bar.
    Shape {
      id: shelfBorderLeftSnappedTop
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      asynchronous: false
      visible: root.isMidnightDoll && !root.isBarTransparent && root.barPos === "left" && root.isSnappedTop && !root.isSnappedBottom
      z: 10

      ShapePath {
        strokeWidth: 1.0
        strokeColor: Color.accent
        fillColor: "transparent"
        capStyle: ShapePath.FlatCap
        joinStyle: ShapePath.RoundJoin

        startX: card.width - 0.5
        startY: 0.0
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

    Behavior on opacity {
      enabled: root.popoutSwitching
      NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic }
    }

    // Swallow clicks on the card so they don't bubble to the dismissal
    // MouseArea behind us.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
    }

    Item {
      id: contentHolder
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
      opacity: root.popoutSwitching ? (root.open ? 1.0 : 0) : 1.0

      Behavior on opacity {
        enabled: root.popoutSwitching
        NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic }
      }
    }
  }
}
}
