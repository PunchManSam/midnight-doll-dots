import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "BarModel.js" as BarModel

Item {
  id: root

  // The omarchy-shell host injects omarchyPath from OMARCHY_PATH.
  property string omarchyPath: ""
  // Injected by the host shell so bar slots can resolve enabled widgets.
  property var barWidgetRegistry: null
  // Injected by the host shell every time shell.json is reloaded. Holds the
  // `bar:` subtree: position, centerAnchor, layout. The host owns file IO;
  // the bar just renders whatever it's handed. The bar font follows the
  // OS-level fontconfig monospace binding — it is not stored in shell.json.
  property var barConfig: fallbackBarConfig
  // Injected by the host shell. Used for shell-wide actions such as opening
  // settings and persisting inline widget state.
  property var shell: null
  // Manifest for the active bar option. Present for custom bars and useful for
  // diagnostics; the built-in bar does not otherwise need it.
  property var manifest: null
  // Mirrors the on-disk `bar-off` flag so the user can hide the bar without
  // killing the entire shell. Hidden panels stay mapped but park off-screen
  // without an exclusion zone; updated by the FileView watcher further down.
  property bool barHidden: false
  property string home: Quickshell.env("HOME")
  FileView {
    id: currentThemeFile
    path: root.home + "/.local/state/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onLoaded: root.activeTheme = String(text() || "").trim()
    onFileChanged: reload()
  }
  property string activeTheme: ""
  property string hudTitle: "MIDNIGHT-DOLL"
  property string hudSubtitle: "HUD"
  property string menuIcon: "󰚌"
  readonly property bool isMidnightDoll: {
    var name = activeTheme.toLowerCase().replace(/[\s_-]+/g, "")
    return name === "midnightdoll"
  }
  readonly property string midnightShortcutsPath: root.home + "/.config/omarchy/midnight-shortcuts.json"
  property var midnightShortcutsList: []
  FileView {
    id: midnightShortcutsFile
    path: root.midnightShortcutsPath
    watchChanges: true
    printErrors: false
    atomicWrites: true
    onLoaded: root.parseMidnightShortcuts(text())
    onFileChanged: reload()
  }
  function parseMidnightShortcuts(raw) {
    try {
      var parsed = JSON.parse(String(raw || "[]"))
      if (Array.isArray(parsed)) {
        midnightShortcutsList = parsed
        return
      }
    } catch (e) {
      console.warn("parseMidnightShortcuts error", e)
    }
    midnightShortcutsList = []
  }
  function saveMidnightShortcuts(list) {
    midnightShortcutsList = list
    midnightShortcutsFile.setText(JSON.stringify(list, null, 2) + "\n")
  }
  property bool midnightShortcutEditorOpen: false
  property QtObject leftBarContext: QtObject {
    id: leftBarCtx
    property string position: "left"
    property bool vertical: true
    property int barSize: 36
    property color foreground: root.foreground
    property color background: root.background
    property color urgent: root.urgent
    property color barForeground: root.barForeground
    property color themeForeground: root.themeForeground
    property string fontFamily: root.fontFamily
    property bool foregroundAnimationEnabled: true
    property bool barHovered: root.barHovered
    property var activePopout: root.activePopout
    property var shell: root.shell

    function run(cmd) { root.run(cmd) }
    function requestPopout(owner) { root.requestPopout(owner) }
    function releasePopout(owner) { root.releasePopout(owner) }
    function showTooltip(target, text) { root.showTooltip(target, text) }
    function hideTooltip(target) { root.hideTooltip(target) }
    function moduleWidgets(name) { return root.moduleWidgets(name) }
    function canonicalWidgetId(id) { return root.canonicalWidgetId(id) }
  }
  property string stateHome: home + "/.local/state"
  property string omarchyConfigDir: home + "/.config/omarchy"
  property var fallbackBarConfig: ({
    position: "top",
    transparent: false,
    centerAnchor: "omarchy.clock",
    layout: { left: [], center: [], right: [] }
  })
  property var layoutConfig: fallbackBarConfig.layout
  property string centerAnchor: ""
  property bool requestedTransparent: false
  property bool useTransparentForeground: false
  property bool transparent: false
  property bool centerSectionHovered: false
  // One bar surface exists per monitor and each reports into this count, so a
  // pointer crossing from one monitor's bar to another's stays counted however
  // the enter and leave interleave. A single shared bool would be left false by
  // whichever event landed last.
  property int barHoverCount: 0
  // True while the pointer is over any bar, widgets included.
  readonly property bool barHovered: barHoverCount > 0
  property bool centerSectionRevealHeld: false
  property bool centerHoverRevealSuppressed: false
  property int barConfigSerial: 0
  property string position: "top"
  property string fontFamily: isMidnightDoll ? "JetBrainsMono Nerd Font" : Style.font.family
  // Bound to the central Color singleton so the bar tracks shell.toml's
  // [bar] section. Property names kept for the rest of this file's bindings.
  property color themeForeground: isMidnightDoll ? Color.accent : Color.bar.text
  property color themeContrastForeground: Color.background
  property color transparentForeground: Color.bar.text
  property color foreground: themeForeground
  property color barForeground: (isMidnightDoll || !useTransparentForeground) ? themeForeground : transparentForeground
  property bool foregroundAnimationEnabled: true
  property color background: isMidnightDoll ? "#010101" : Color.bar.background
  property color urgent: isMidnightDoll ? Color.accent : Color.bar.active

  Behavior on barForeground { enabled: root.foregroundAnimationEnabled; ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  Behavior on background { ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  Behavior on urgent { ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  property var tooltipTarget: null
  property var pendingTooltipTarget: null
  property string tooltipText: ""
  property string pendingTooltipText: ""
  property bool tooltipShown: false
  property int tooltipRequest: 0
  property var activePopout: null
  property var barDragSource: null
  property var barDragTarget: null
  property var barDragTargetGeometry: null
  property bool barDragAfter: false
  property var barDragWindow: null
  property var barDragScreen: null
  property url barDragImageUrl: ""
  property real barDragSceneX: 0
  property real barDragSceneY: 0
  property real barDragScreenX: 0
  property real barDragScreenY: 0
  property real barDragOffsetX: 0
  property real barDragOffsetY: 0
  property bool barMoveActive: false
  property string barMoveCandidate: ""
  property var barMoveWindow: null
  property var barMoveScreen: null
  property var clickTargets: []
  property var moduleSlots: []

  function registerClickTarget(target) {
    if (!target || clickTargets.indexOf(target) !== -1) return
    var next = clickTargets.slice()
    next.push(target)
    clickTargets = next
  }

  function unregisterClickTarget(target) {
    var next = clickTargets.filter(function(item) { return item !== target })
    clickTargets = next
  }

  function registerModuleSlot(slot) {
    if (!slot || moduleSlots.indexOf(slot) !== -1) return
    var next = moduleSlots.slice()
    next.push(slot)
    moduleSlots = next
  }

  function unregisterModuleSlot(slot) {
    var next = moduleSlots.filter(function(item) { return item !== slot })
    moduleSlots = next
  }

  function debugBarGeometry() {
    var out = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem) continue
      var point = { x: slot.x, y: slot.y }
      try {
        point = slot.mapToItem(null, 0, 0)
      } catch (e) {
      }
      out.push({
        id: slot.moduleName,
        section: slot.region,
        x: Math.round(point.x),
        y: Math.round(point.y),
        width: Math.round(slot.width),
        height: Math.round(slot.height),
        visible: slot.visible === true && slot.width > 0 && slot.height > 0,
        itemVisible: slot.activeItem.visible === true,
        itemWidth: Math.round(slot.activeItem.implicitWidth || 0),
        itemHeight: Math.round(slot.activeItem.implicitHeight || 0)
      })
    }
    return out
  }

  function targetWindow(target) {
    return target && target.QsWindow ? target.QsWindow.window : null
  }

  function targetBelongsToWindow(target, window) {
    return !!target && !!window && targetWindow(target) === window
  }

  function slotWindow(slot) {
    if (!slot) return null
    return targetWindow(slot.activeItem) || targetWindow(slot)
  }

  function sameWindow(left, right) {
    if (!left || !right) return false
    if (left === right) return true
    return !!left.screen && !!right.screen && !!left.screen.name && !!right.screen.name && left.screen.name === right.screen.name
  }

  function targetTooltipHovered(target) {
    return !!target && target.visible !== false && target.opacity !== 0 && target.tooltipHovered === true
  }

  function clearTooltip() {
    tooltipTimer.stop()
    pendingTooltipTarget = null
    pendingTooltipText = ""
    tooltipTarget = null
    tooltipText = ""
    tooltipShown = false
  }

  function clearBarDrag() {
    barDragSource = null
    barDragWindow = null
    barDragScreen = null
    barDragImageUrl = ""
    barDragTarget = null
    barDragTargetGeometry = null
    barDragAfter = false
    barDragSceneX = 0
    barDragSceneY = 0
    barDragScreenX = 0
    barDragScreenY = 0
    barDragOffsetX = 0
    barDragOffsetY = 0
  }

  function windowScreenPoint(scenePoint, window) {
    var x = scenePoint ? scenePoint.x : 0
    var y = scenePoint ? scenePoint.y : 0
    if (!window || !window.screen) return { x: x, y: y }

    if (root.position === "bottom")
      y += Math.max(0, window.screen.height - window.height)
    else if (root.position === "right")
      x += Math.max(0, window.screen.width - window.width)

    return { x: x, y: y }
  }

  function barDragScreenPoint(scenePoint) {
    return windowScreenPoint(scenePoint, barDragWindow)
  }

  function dropMarkerRect(slot, after) {
    if (!slot) return null

    try {
      var slotPoint = slot.mapToItem(null, 0, 0)
      var screenPoint = barDragScreenPoint(slotPoint)
      var thickness = Style.spacing.xs
      if (vertical) {
        return {
          x: screenPoint.x,
          y: screenPoint.y + (after ? slot.height : 0) - thickness / 2,
          width: slot.width,
          height: thickness
        }
      }

      return {
        x: screenPoint.x + (after ? slot.width : 0) - thickness / 2,
        y: screenPoint.y,
        width: thickness,
        height: slot.height
      }
    } catch (e) {
      return null
    }
  }

  // Split the screen along its diagonals (in normalized space, so widescreens
  // don't bias toward left/right): whichever triangle holds the cursor names
  // the candidate edge.
  function nearestScreenEdge(point, screen) {
    var nx = screen.width > 0 ? Util.clamp(point.x / screen.width, 0, 1) : 0.5
    var ny = screen.height > 0 ? Util.clamp(point.y / screen.height, 0, 1) : 0.5

    var edge = "top"
    var best = ny
    if (1 - ny < best) { edge = "bottom"; best = 1 - ny }
    if (nx < best) { edge = "left"; best = nx }
    if (1 - nx < best) { edge = "right"; best = 1 - nx }
    return edge
  }

  function beginBarMove(window) {
    barMoveWindow = window
    barMoveScreen = window ? window.screen : null
    barMoveCandidate = position
    barMoveActive = true
  }

  function updateBarMove(screenPoint) {
    if (!barMoveActive || !barMoveScreen) return
    barMoveCandidate = nearestScreenEdge(screenPoint, barMoveScreen)
  }

  function clearBarMove() {
    barMoveActive = false
    barMoveCandidate = ""
    barMoveWindow = null
    barMoveScreen = null
  }

  function finishBarMove() {
    var edge = barMoveCandidate
    if (!barMoveActive || !edge || edge === position) {
      clearBarMove()
      return
    }

    clearBarMove()
    setBarPosition(edge)
  }

  function setBarPosition(value) {
    var next = normalizePosition(value)
    if (root.shell && typeof root.shell.mutateShellConfig === "function") {
      root.shell.mutateShellConfig(function(config) {
        if (!Util.isPlainObject(config.bar)) config.bar = {}
        config.bar.position = next
      })
    } else {
      root.position = next
    }
  }

  function captureBarDragGhost(slot) {
    var item = slot && slot.activeItem ? slot.activeItem : null
    barDragImageUrl = ""
    if (!item || typeof item.grabToImage !== "function") return

    var grabWidth = Math.max(1, Math.ceil(item.width || item.implicitWidth || slot.width || 1))
    var grabHeight = Math.max(1, Math.ceil(item.height || item.implicitHeight || slot.height || 1))
    item.grabToImage(function(result) {
      if (root.barDragSource !== slot || !result || !result.url) return
      root.barDragImageUrl = result.url
    }, Qt.size(grabWidth, grabHeight))
  }

  function requestPopout(owner) {
    if (activePopout === owner) return
    if (activePopout) {
      if ("closeForPopoutSwitch" in activePopout) activePopout.closeForPopoutSwitch()
      else if ("close" in activePopout) activePopout.close()
    }
    activePopout = owner
  }

  function releasePopout(owner) {
    if (activePopout === owner) activePopout = null
  }

  readonly property bool vertical: position === "left" || position === "right"
  readonly property int barSize: vertical ? Style.bar.sizeVertical : (isMidnightDoll ? 30 : Style.bar.sizeHorizontal)

  function normalizePosition(value) {
    return BarModel.normalizePosition(value)
  }

  // Apply tray-pinning on top of the shared layout normalization so the
  // bar host and scriptable config helpers can't drift on entry shape.
  function normalizeLayout(layout) {
    var normalized = Util.normalizeLayout(Util.isPlainObject(layout) ? layout : fallbackBarConfig.layout)
    return {
      left:   pinTrayToInner(normalized.left,   "left"),
      center: pinTrayToInner(normalized.center, "center"),
      right:  pinTrayToInner(normalized.right,  "right")
    }
  }

  // The tray drawer reveals inward (away from the bar edge). Place it at the
  // section's inner edge: start of the right section, end of the left/center
  // sections. The drawer's reserved space then sits next to the bar center,
  // not stranded mid-section.
  function pinTrayToInner(entries, section) {
    return BarModel.pinTrayToInner(entries, section)
  }

  function applyBarConfig() {
    var config = Util.isPlainObject(barConfig) ? barConfig : fallbackBarConfig

    position = normalizePosition(config.position)
    setRequestedTransparency(config.transparent === true)
    centerAnchor = Util.canonicalWidgetId(config.centerAnchor || "")

    // layoutEntries feeds plain JS arrays to the module Repeaters, and QML
    // cannot diff those: reassigning layoutConfig rebuilds every widget on
    // every monitor. When a shell.json write only changed inline widget
    // settings, patch the live layout and running widgets in place instead.
    var next = normalizeLayout(config.layout)
    var delta = BarModel.inlineSettingsDelta(layoutConfig, next)
    if (delta) {
      applySettingsDelta(delta)
      return
    }
    layoutConfig = next
    barConfigSerial++
  }

  function applySettingsDelta(delta) {
    for (var i = 0; i < delta.length; i++) {
      var change = delta[i]
      layoutConfig[change.region][change.index] = change.entry
      var settings = entrySettings(change.entry)
      for (var s = 0; s < moduleSlots.length; s++) {
        var slot = moduleSlots[s]
        if (!slot || slot.region !== change.region || slot.moduleName !== entryId(change.entry)) continue
        var item = slot.activeItem
        if (item && "settings" in item) item.settings = settings
      }
    }
  }

  onBarConfigChanged: applyBarConfig()

  function layoutEntries(region) {
    var serial = barConfigSerial
    var entries = layoutConfig ? layoutConfig[region] : null
    return Array.isArray(entries) ? entries : []
  }

  // Tab order for the panels in one bar region. Scoped to a single bar surface
  // so tabbing walks the bar the open panel belongs to instead of hopping the
  // panel to another monitor's copy of the same widget.
  function panelNavigationSlots(region, window) {
    var entries = layoutEntries(region)
    var slots = []
    for (var i = 0; i < entries.length; i++) {
      var id = entryId(entries[i])
      for (var j = 0; j < moduleSlots.length; j++) {
        var slot = moduleSlots[j]
        if (!slot || slot.region !== region || slot.moduleName !== id) continue
        if (window && !sameWindow(slotWindow(slot), window)) continue
        var item = slot.activeItem
        if (!item || item.visible !== true || slot.visible !== true || slot.width <= 0 || slot.height <= 0) continue
        if (typeof item.open !== "function" || typeof item.close !== "function" || item.opened === undefined) continue
        slots.push(slot)
        break
      }
    }
    return slots
  }

  // The Nth panel in a bar region, counted the way the bar reads: layout order,
  // and only the panels actually on screen. A widget with no panel (the tray)
  // and one that is hiding itself are passed over, so the number lands on the
  // Nth panel icon the user can see rather than the Nth layout entry.
  // One-based, because it exists for hotkeys; anything else lands on no slot.
  //
  // Counting any bar surface is enough: every monitor lays its bar out from the
  // one layout, and summoning the id routes through pickPanelSlot, which opens
  // the focused monitor's copy whichever surface was counted.
  function panelWidgetIdAt(region, index) {
    var slots = panelNavigationSlots(String(region || ""), null)
    var slot = slots[Math.round(Number(index)) - 1]
    return slot ? String(slot.moduleName || "") : ""
  }

  function switchPanelFrom(owner, direction) {
    if (!owner) return false

    var currentSlot = null
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (slot && slot.activeItem === owner) {
        currentSlot = slot
        break
      }
    }
    if (!currentSlot) return false

    var slots = panelNavigationSlots(currentSlot.region, slotWindow(currentSlot))
    if (slots.length < 2) return false

    var currentIndex = -1
    for (var j = 0; j < slots.length; j++) {
      if (slots[j] === currentSlot) {
        currentIndex = j
        break
      }
    }
    if (currentIndex < 0) return false

    var step = direction < 0 ? -1 : 1
    var nextSlot = slots[(currentIndex + step + slots.length) % slots.length]
    if (!nextSlot || !nextSlot.activeItem || nextSlot.activeItem === owner) return false

    nextSlot.activeItem.open()
    return true
  }

  // Every live instance of a widget id. A bar surface is built per monitor, so
  // a widget that appears once in the layout is still live once per screen.
  function moduleWidgets(pluginId) {
    var id = String(pluginId || "")
    var items = []
    if (!id) return items
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem || slot.moduleName !== id) continue
      items.push(slot.activeItem)
    }
    return items
  }

  function slotScreenName(slot) {
    var window = slotWindow(slot)
    return window && window.screen ? String(window.screen.name || "") : ""
  }

  // The output Hyprland has focused, which is where a keyboard-summoned panel
  // belongs. Empty until Hyprland reports one, which leaves panel routing on
  // its per-monitor fallback rather than guessing at an output.
  function focusedScreenName() {
    var monitor = Hyprland.focusedMonitor
    return monitor ? String(monitor.name || "") : ""
  }

  // Resolve the live bar-widget instance for a plugin id (e.g. "omarchy.bluetooth").
  // Only widgets that expose popup open/close methods count; plain indicators
  // (clock, workspaces, tray) return null. Used by shell.summon/toggle so
  // panel hotkeys route through the bar instead of a per-target IPC handler
  // that only reaches whichever per-monitor instance claimed the target.
  function findPanelWidget(pluginId) {
    var id = String(pluginId || "")
    if (!id) return null
    var candidates = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem) continue
      if (slot.moduleName !== id) continue
      var item = slot.activeItem
      if (typeof item.open !== "function" || typeof item.close !== "function" || item.opened === undefined) continue
      candidates.push({ slot: slot, screenName: slotScreenName(slot), opened: item.opened === true })
    }
    // One copy per monitor, plus a zero-size placeholder for anchored center
    // modules. See BarModel.pickPanelSlot for which one a hotkey acts on.
    var chosen = BarModel.pickPanelSlot(candidates, focusedScreenName())
    return chosen ? chosen.activeItem : null
  }

  function summonBarWidget(pluginId) {
    var item = findPanelWidget(pluginId)
    if (!item || typeof item.open !== "function") return false
    item.open()
    return true
  }

  function hideBarWidget(pluginId) {
    var item = findPanelWidget(pluginId)
    if (!item || typeof item.close !== "function") return false
    item.close()
    return true
  }

  function isBarWidgetOpen(pluginId) {
    var item = findPanelWidget(pluginId)
    return !!item && item.opened === true
  }

  function entrySettings(entry) {
    return BarModel.entrySettings(entry)
  }

  function entryId(entry) {
    return BarModel.entryId(entry)
  }

  function moduleString(entry, key, fallback) {
    return BarModel.moduleString(entry, key, fallback)
  }

  function entryIndex(entries, name) {
    return BarModel.entryIndex(entries, name)
  }

  function entriesBefore(entries, name) {
    return BarModel.entriesBefore(entries, name)
  }

  function entriesAfter(entries, name) {
    return BarModel.entriesAfter(entries, name)
  }

  function canonicalWidgetId(name) {
    return Util.canonicalWidgetId(name)
  }

  function expandPath(path) {
    return BarModel.expandPath(path, home)
  }

  function customModuleSafeName(name) {
    return BarModel.customModuleSafeName(name)
  }

  function customModuleType(entry) {
    return BarModel.customModuleType(entry)
  }

  function customModuleSource(entry) {
    var source = BarModel.customModulePath(entry, home, omarchyConfigDir)
    return source ? Util.fileUrl(source) : ""
  }

  Component.onCompleted: applyBarConfig()

  // Revealing the indicators widens their section, which can slide a neighbour
  // under a stationary pointer. Collapsing on that un-hover would move it back
  // out and re-open the peek, so hold until the pointer leaves the bar.
  function setCenterSectionHovered(hovered) {
    centerSectionHovered = hovered
    if (hovered) {
      centerSectionRevealTimer.stop()
      centerSectionRevealHeld = true
    } else {
      centerSectionRevealTimer.restart()
    }
  }

  function setBarHovered(hovered) {
    barHoverCount = Math.max(0, barHoverCount + (hovered ? 1 : -1))
    if (barHoverCount === 0) centerSectionRevealTimer.restart()
  }

  Timer {
    id: centerSectionRevealTimer
    interval: 120
    // Collapse only. Opening the peek is the center section's own gesture, done
    // in setCenterSectionHovered, so a timer left pending by a pointer that dipped
    // off the bar and came back cannot reveal indicators it never pointed at.
    onTriggered: if (!root.centerSectionHovered && !root.barHovered) root.centerSectionRevealHeld = false
  }

  function run(command) {
    if (!command) return

    Util.execDetached(command)
  }

  function toggleTransparency() {
    var nextTransparent = !(root.requestedTransparent === true)
    if (root.shell && typeof root.shell.mutateShellConfig === "function") {
      root.shell.mutateShellConfig(function(config) {
        if (!Util.isPlainObject(config.bar)) config.bar = {}
        config.bar.transparent = nextTransparent
      })
    } else {
      root.setRequestedTransparency(nextTransparent)
    }
  }

  function rawLayoutSection(config, region) {
    if (!Util.isPlainObject(config.bar)) config.bar = {}
    if (!Util.isPlainObject(config.bar.layout)) config.bar.layout = {}
    if (!Array.isArray(config.bar.layout[region])) config.bar.layout[region] = []

    return config.bar.layout[region]
  }

  function rawEntryIndex(entries, name) {
    for (var i = 0; i < entries.length; i++) {
      if (root.entryId(entries[i]) === name) return i
    }

    return -1
  }

  function moveModuleInConfig(config, fromRegion, fromName, toRegion, beforeName) {
    var fromEntries = rawLayoutSection(config, fromRegion)
    var toEntries = rawLayoutSection(config, toRegion)
    var fromIndex = rawEntryIndex(fromEntries, fromName)
    if (fromIndex < 0) return false

    var toIndex = beforeName ? rawEntryIndex(toEntries, beforeName) : toEntries.length
    if (toIndex < 0) toIndex = toEntries.length

    if (fromRegion === toRegion && fromIndex === toIndex) return false

    var movedEntry = fromEntries[fromIndex]
    fromEntries.splice(fromIndex, 1)

    if (fromRegion === toRegion && fromIndex < toIndex) toIndex -= 1
    if (toIndex < 0) toIndex = 0
    if (toIndex > toEntries.length) toIndex = toEntries.length
    if (fromRegion === toRegion && fromIndex === toIndex) {
      fromEntries.splice(fromIndex, 0, movedEntry)
      return false
    }

    toEntries.splice(toIndex, 0, movedEntry)
    return true
  }

  function dropBarModule(source, toRegion, beforeName) {
    if (!source || !source.region || !source.moduleName || !toRegion) return false
    if (source.region === toRegion && source.moduleName === beforeName) return false
    if (!root.shell || typeof root.shell.mutateShellConfig !== "function") return false

    var changed = false
    root.shell.mutateShellConfig(function(config) {
      changed = moveModuleInConfig(config, source.region, source.moduleName, toRegion, beforeName)
    })
    return changed
  }

  function moduleDropAtScene(scenePoint, sourceSlot) {
    var sourceWindow = root.slotWindow(sourceSlot) || root.barDragWindow
    if (sourceWindow && sourceWindow.contentItem) {
      var barPoint = sourceWindow.contentItem.mapFromItem(null, scenePoint.x, scenePoint.y)
      if (barPoint.x < 0 || barPoint.x > sourceWindow.contentItem.width ||
          barPoint.y < 0 || barPoint.y > sourceWindow.contentItem.height)
        return null
    }

    var candidates = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || slot === sourceSlot || !slot.visible || slot.width <= 0 || slot.height <= 0) continue
      if (sourceWindow && !root.sameWindow(root.slotWindow(slot), sourceWindow)) continue

      var slotPoint = { x: slot.x, y: slot.y }
      try {
        slotPoint = slot.mapToItem(null, 0, 0)
      } catch (e) {
      }

      candidates.push({
        slot: slot,
        x: slotPoint.x,
        y: slotPoint.y,
        width: slot.width,
        height: slot.height
      })
    }

    return BarModel.nearestDropTarget(candidates, scenePoint, root.vertical)
  }

  function visibleModuleSlot(region, name, sourceSlot) {
    var sourceWindow = root.slotWindow(sourceSlot) || root.barDragWindow
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || slot === sourceSlot || slot.region !== region || slot.moduleName !== name ||
          !slot.visible || slot.width <= 0 || slot.height <= 0) continue
      if (sourceWindow && !root.sameWindow(root.slotWindow(slot), sourceWindow)) continue
      return slot
    }

    return null
  }

  function nextVisibleModuleName(region, afterName, sourceSlot) {
    var entries = layoutEntries(region)
    var found = false
    for (var i = 0; i < entries.length; i++) {
      var name = entryId(entries[i])
      if (!found) {
        found = name === afterName
        continue
      }

      if (visibleModuleSlot(region, name, sourceSlot)) return name
    }

    return ""
  }

  function dropBarModuleAtTarget(sourceSlot, targetSlot, afterTarget) {
    if (!sourceSlot || !targetSlot) return false

    var beforeName = afterTarget ? nextVisibleModuleName(targetSlot.region, targetSlot.moduleName, sourceSlot) : targetSlot.moduleName
    return dropBarModule(sourceSlot, targetSlot.region, beforeName)
  }

  function moduleTargetClickable(target) {
    return target
      && target.visible !== false
      && target.opacity !== 0
      && target.interactive !== false
      && target.pressable !== false
      && target.concealed !== true
      && typeof target.triggerPress === "function"
  }

  function moduleClickTargetAt(slot, localX, localY) {
    for (var i = clickTargets.length - 1; i >= 0; i--) {
      var target = clickTargets[i]
      if (!moduleTargetClickable(target)) continue

      var targetPoint = { x: localX, y: localY }
      try {
        targetPoint = slot.mapToItem(target, localX, localY)
      } catch (e) {
        continue
      }

      if (targetPoint.x >= 0 && targetPoint.x <= target.width &&
          targetPoint.y >= 0 && targetPoint.y <= target.height) {
        return target
      }
    }

    if (moduleTargetClickable(slot.activeItem)) return slot.activeItem
    return null
  }

  function pressModuleClickTarget(slot, button, localX, localY) {
    var target = moduleClickTargetAt(slot, localX, localY)
    if (!target) return false

    target.triggerPress(button)
    return true
  }

  function colorHex(colorValue) {
    var c = colorValue
    if (typeof c === "string") c = Qt.color(c)
    function hexChannel(value) {
      var s = Math.round(Util.clamp(value, 0, 1) * 255).toString(16)
      return s.length < 2 ? "0" + s : s
    }
    return "#" + hexChannel(c.r) + hexChannel(c.g) + hexChannel(c.b)
  }

  function setRequestedTransparency(value) {
    var nextTransparent = value === true
    requestedTransparent = nextTransparent
    if (!nextTransparent) {
      foregroundAnimationEnabled = false
      useTransparentForeground = false
      transparent = false
      transparentForeground = themeForeground
      restoreForegroundAnimation()
      return
    }
    scheduleTransparentForegroundRefresh()
  }

  function restoreForegroundAnimation() {
    Qt.callLater(function() {
      Qt.callLater(function() { root.foregroundAnimationEnabled = true })
    })
  }

  function scheduleTransparentForegroundRefresh() {
    if (!requestedTransparent) {
      transparentForeground = themeForeground
      return
    }
    transparentForegroundTimer.restart()
  }

  function refreshTransparentForeground() {
    if (!requestedTransparent || transparentForegroundProc.running) return

    transparentForegroundProc.command = [
      "omarchy-bar-text-color",
      root.position,
      String(root.barSize),
      colorHex(root.themeForeground),
      colorHex(root.themeContrastForeground)
    ]
    transparentForegroundProc.running = true
  }

  onRequestedTransparentChanged: scheduleTransparentForegroundRefresh()
  onPositionChanged: scheduleTransparentForegroundRefresh()
  onThemeForegroundChanged: scheduleTransparentForegroundRefresh()
  onThemeContrastForegroundChanged: scheduleTransparentForegroundRefresh()

  Timer {
    id: transparentForegroundTimer
    interval: 120
    repeat: false
    onTriggered: root.refreshTransparentForeground()
  }

  Process {
    id: transparentForegroundProc
    stdout: SplitParser {
      onRead: function(line) {
        var value = String(line || "").trim()
        if (!/^#[0-9A-Fa-f]{6}$/.test(value)) return

        root.foregroundAnimationEnabled = false
        root.transparentForeground = value
        if (root.requestedTransparent) {
          root.useTransparentForeground = true
          root.transparent = true
        }
        root.restoreForegroundAnimation()
      }
    }
  }

  FileView {
    path: root.stateHome + "/omarchy/current"
    watchChanges: true
    printErrors: false
    onFileChanged: root.scheduleTransparentForegroundRefresh()
  }

  function runProcess(process) {
    if (!process.running)
      process.running = true
  }

  function showTooltip(target, text) {
    clearTooltip()

    if (!targetTooltipHovered(target) || !text) {
      tooltipRequest += 1
      return
    }

    var request = tooltipRequest + 1
    tooltipRequest = request
    pendingTooltipTarget = target
    pendingTooltipText = text

    Qt.callLater(function() {
      if (request !== tooltipRequest) return
      if (!targetTooltipHovered(pendingTooltipTarget)) {
        clearTooltip()
        return
      }
      tooltipTarget = pendingTooltipTarget
      tooltipText = pendingTooltipText
      pendingTooltipTarget = null
      pendingTooltipText = ""
      tooltipTimer.restart()
    })
  }

  function hideTooltip(target) {
    if (tooltipTarget !== target && pendingTooltipTarget !== target) return

    tooltipRequest += 1
    clearTooltip()
  }

  Timer {
    id: tooltipTimer
    interval: 400
    onTriggered: {
      if (root.targetTooltipHovered(root.tooltipTarget)) root.tooltipShown = true
      else root.clearTooltip()
    }
  }

  Timer {
    interval: 100
    running: root.tooltipShown
    repeat: true
    onTriggered: if (!root.targetTooltipHovered(root.tooltipTarget)) root.hideTooltip(root.tooltipTarget)
  }

  // Presence of the `bar-off` flag = bar hidden. Watching the parent toggles
  // directory because FileView can't observe a file that doesn't exist yet,
  // and the flag is created/removed by `omarchy-toggle-bar`.
  Process {
    id: barHiddenProbe
    running: true
    command: ["bash", "-c", "[[ -f $HOME/.local/state/omarchy/toggles/bar-off ]] && echo yes || echo no"]
    stdout: SplitParser { onRead: function(line) { root.barHidden = String(line).trim() === "yes" } }
  }
  FileView {
    path: root.home + "/.local/state/omarchy/toggles"
    watchChanges: true
    printErrors: false
    onFileChanged: barHiddenProbe.running = true
  }

  // The directory watch can permanently stop delivering events after flag
  // changes land in quick succession, stranding the bar off screen until the
  // shell restarts. `omarchy-toggle-bar` nudges this after flipping the flag
  // so the probe re-reads it even when the watch has gone quiet.
  IpcHandler {
    target: "omarchy.bar"

    // Start rather than restart: a probe already in flight was launched by the
    // directory watch after the flag flipped, so its answer is current, and
    // killing it here can swallow the result entirely.
    function syncHidden(): void {
      barHiddenProbe.running = true
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      BarPanel {
        required property var modelData

        screen: modelData
      }
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      MidnightCornerOverlay {
        required property var modelData

        ghostScreen: modelData
      }
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      MidnightLeftPanel {
        required property var modelData

        screen: modelData
      }
    }
  }

  component MidnightCornerOverlay: PanelWindow {
    id: cornerWindow
    required property var ghostScreen
    screen: ghostScreen

    visible: root.isMidnightDoll && !root.barHidden && !remapGuardCorner.remapping
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-midnight-corner"
    WlrLayershell.layer: WlrLayer.Top

    ScreenMoveRemap {
      id: remapGuardCorner
      window: cornerWindow
    }

    anchors {
      top: true
      left: true
    }

    margins {
      top: root.barSize - 1
      left: 35
    }

    implicitWidth: 13
    implicitHeight: 13
    color: "transparent"
    surfaceFormat.opaque: false

    Canvas {
      id: cornerFillet
      anchors.fill: parent
      renderTarget: Canvas.FramebufferObject

      Connections {
        target: Color
        function onBarChanged() { cornerFillet.requestPaint() }
        function onAccentChanged() { cornerFillet.requestPaint() }
      }

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var r = width
        if (r <= 1) return

        // Fill background fillet in concave corner
        ctx.fillStyle = Color.bar.background
        ctx.beginPath()
        ctx.moveTo(0, 0)
        ctx.lineTo(r, 0)
        ctx.arc(r, r, r, -Math.PI / 2, Math.PI, true)
        ctx.closePath()
        ctx.fill()

        // Stroke accent border arc
        ctx.strokeStyle = Color.accent
        ctx.lineWidth = 1.0
        ctx.beginPath()
        ctx.arc(r, r, r - 0.5, -Math.PI / 2, Math.PI, true)
        ctx.stroke()
      }
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      MidnightShortcutEditorDialog {
        required property var modelData

        ghostScreen: modelData
      }
    }
  }

  component MidnightShortcutEditorDialog: PanelWindow {
    id: shortcutModalWindow
    required property var ghostScreen
    screen: ghostScreen

    visible: root.isMidnightDoll && root.midnightShortcutEditorOpen
    color: "transparent"
    surfaceFormat.opaque: false
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-midnight-shortcuts-modal"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.midnightShortcutEditorOpen = false
    }

    Rectangle {
      anchors.centerIn: parent
      width: 480
      height: 520
      color: Color.popups.background
      border.color: Color.accent
      border.width: 2
      radius: 0

      MouseArea {
        anchors.fill: parent
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8

        RowLayout {
          Layout.fillWidth: true
          Text {
            text: "LAUNCHER SHORTCUTS"
            font.family: root.fontFamily
            font.bold: true
            font.pixelSize: Style.font.title
            color: Color.accent
            Layout.fillWidth: true
          }
          Button {
            text: "✕"
            onClicked: root.midnightShortcutEditorOpen = false
          }
        }

        ListView {
          id: shortcutsView
          Layout.fillWidth: true
          Layout.preferredHeight: 160
          clip: true
          model: root.midnightShortcutsList

          delegate: Rectangle {
            required property var modelData
            required property int index

            width: shortcutsView.width
            height: 32
            color: index % 2 === 0 ? Qt.rgba(1, 1, 1, 0.04) : "transparent"
            radius: 0

            RowLayout {
              anchors.fill: parent
              anchors.margins: 3
              spacing: 4

              Text {
                text: modelData.glyph || "󰣇"
                font.family: root.fontFamily
                font.pixelSize: 14
                color: root.urgent
              }

              Text {
                text: modelData.name || ""
                font.family: root.fontFamily
                font.bold: true
                font.pixelSize: Style.font.body
                color: Color.foreground
                Layout.preferredWidth: 90
                elide: Text.ElideRight
              }

              Text {
                text: modelData.command || ""
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                color: Qt.rgba(1, 1, 1, 0.6)
                Layout.fillWidth: true
                elide: Text.ElideRight
              }

              Button {
                text: "▲"
                enabled: index > 0
                implicitWidth: 22
                implicitHeight: 22
                onClicked: {
                  var copy = root.midnightShortcutsList.slice()
                  var temp = copy[index - 1]
                  copy[index - 1] = copy[index]
                  copy[index] = temp
                  root.saveMidnightShortcuts(copy)
                }
              }

              Button {
                text: "▼"
                enabled: index < root.midnightShortcutsList.length - 1
                implicitWidth: 22
                implicitHeight: 22
                onClicked: {
                  var copy = root.midnightShortcutsList.slice()
                  var temp = copy[index + 1]
                  copy[index + 1] = copy[index]
                  copy[index] = temp
                  root.saveMidnightShortcuts(copy)
                }
              }

              Button {
                text: "🗑"
                implicitWidth: 22
                implicitHeight: 22
                onClicked: {
                  var copy = root.midnightShortcutsList.slice()
                  copy.splice(index, 1)
                  root.saveMidnightShortcuts(copy)
                }
              }
            }
          }
        }

        Rectangle {
          Layout.fillWidth: true
          height: 1
          color: Color.border
        }

        RowLayout {
          Layout.fillWidth: true
          Text {
            text: "SELECT ICON PRESET"
            font.family: root.fontFamily
            font.bold: true
            font.pixelSize: Style.font.caption
            color: Color.accent
            Layout.fillWidth: true
          }
          Button {
            text: "󰌹 NERD FONTS CHEAT SHEET"
            onClicked: root.run("xdg-open 'https://www.nerdfonts.com/cheat-sheet'")
          }
        }

        Flow {
          Layout.fillWidth: true
          spacing: 4

          Repeater {
            model: [
              { name: "Terminal", glyph: "󰞷", cmd: "ghostty" },
              { name: "Browser", glyph: "󰇧", cmd: "google-chrome-stable" },
              { name: "Files", glyph: "󰉋", cmd: "nautilus" },
              { name: "Code", glyph: "󰨞", cmd: "code" },
              { name: "Agent", glyph: "󰧑", cmd: "ghostty" },
              { name: "Discord", glyph: "󰙯", cmd: "discord" },
              { name: "Spotify", glyph: "󰓇", cmd: "spotify" },
              { name: "Steam", glyph: "󰊴", cmd: "steam" },
              { name: "Music", glyph: "󰝚", cmd: "ghostty" },
              { name: "Settings", glyph: "󰒓", cmd: "omarchy-menu" },
              { name: "Omarchy", glyph: "󰣇", cmd: "omarchy-menu" },
              { name: "Video", glyph: "󰕧", cmd: "mpv" },
              { name: "Camera", glyph: "󰄀", cmd: "cheese" },
              { name: "Database", glyph: "󰆼", cmd: "dbeaver" }
            ]

            delegate: Rectangle {
              required property var modelData
              width: 26
              height: 26
              color: iconHover.hovered ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.05)
              border.color: newGlyphField.text === modelData.glyph ? Color.accent : "transparent"
              border.width: 1
              radius: 0

              HoverHandler { id: iconHover }

              Text {
                anchors.centerIn: parent
                text: modelData.glyph
                font.family: root.fontFamily
                font.pixelSize: 14
                color: root.foreground
              }

              MouseArea {
                anchors.fill: parent
                onClicked: {
                  newGlyphField.text = modelData.glyph
                  if (!newNameField.text) newNameField.text = modelData.name
                  if (!newCmdField.text) newCmdField.text = modelData.cmd
                }
              }
            }
          }
        }

        Rectangle {
          Layout.fillWidth: true
          height: 1
          color: Color.border
        }

        RowLayout {
          Layout.fillWidth: true
          Text {
            text: "ADD CUSTOM SHORTCUT"
            font.family: root.fontFamily
            font.bold: true
            font.pixelSize: Style.font.caption
            color: Color.foreground
            Layout.fillWidth: true
          }
          Text {
            text: "Paste glyphs from nerdfonts.com/cheat-sheet"
            font.family: root.fontFamily
            font.pixelSize: 10
            color: Qt.rgba(1, 1, 1, 0.45)
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: 6

          TextField {
            id: newNameField
            placeholderText: "Name"
            font.family: root.fontFamily
            Layout.preferredWidth: 100
            color: Color.foreground
          }

          TextField {
            id: newGlyphField
            placeholderText: "󰨞 (NF)"
            font.family: root.fontFamily
            Layout.preferredWidth: 60
            color: root.urgent
            horizontalAlignment: Text.AlignHCenter
          }

          TextField {
            id: newCmdField
            placeholderText: "Command (e.g. ghostty -e btop)"
            font.family: root.fontFamily
            Layout.fillWidth: true
            color: Color.foreground
          }
        }

        Button {
          text: "+ ADD SHORTCUT"
          Layout.fillWidth: true
          onClicked: {
            if (newNameField.text.trim() && newCmdField.text.trim()) {
              var copy = root.midnightShortcutsList.slice()
              copy.push({
                name: newNameField.text.trim(),
                glyph: newGlyphField.text.trim() || "󰣇",
                command: newCmdField.text.trim()
              })
              root.saveMidnightShortcuts(copy)
              newNameField.text = ""
              newGlyphField.text = ""
              newCmdField.text = ""
            }
          }
        }
      }
    }
  }

  component MidnightLeftPanel: PanelWindow {
    id: leftBarWindow

    visible: root.isMidnightDoll && !root.barHidden && !remapGuardLeft.remapping
    exclusionMode: (root.isMidnightDoll && !root.barHidden) ? ExclusionMode.Auto : ExclusionMode.Ignore

    ScreenMoveRemap {
      id: remapGuardLeft
      window: leftBarWindow
    }

    margins {
      top: 0
      bottom: 0
      left: root.barHidden ? -36 : 0
      right: 0
    }

    anchors {
      top: true
      bottom: true
      left: true
      right: false
    }

    implicitWidth: 36
    implicitHeight: 0
    color: "#010101"
    surfaceFormat.opaque: true
    WlrLayershell.namespace: "omarchy-midnight-left-bar"
    WlrLayershell.layer: WlrLayer.Top

    Item {
      anchors.fill: parent

      Rectangle {
        anchors.fill: parent
        color: "#010101"
      }

      Rectangle {
        anchors {
          top: parent.top
          topMargin: (root.isMidnightDoll && root.position === "top") ? 11 : 0
          bottom: parent.bottom
          right: parent.right
        }
        width: 1
        color: Color.accent
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) {
            root.midnightShortcutEditorOpen = !root.midnightShortcutEditorOpen
          }
        }
      }

      Column {
        id: launcherColumn
        anchors {
          top: parent.top
          topMargin: 6
          left: parent.left
          right: parent.right
          rightMargin: 1
        }
        spacing: 2

        Repeater {
          model: root.midnightShortcutsList

          delegate: Rectangle {
            required property var modelData
            required property int index

            width: 35
            height: 35
            radius: 0
            color: itemHover.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

            HoverHandler {
              id: itemHover
              onHoveredChanged: {
                if (hovered) {
                  root.showTooltip(parent, (modelData.name || "Shortcut") + " (Right-click: edit)")
                } else {
                  root.hideTooltip(parent)
                }
              }
            }

            Text {
              anchors.centerIn: parent
              text: modelData.glyph || "󰣇"
              font.family: root.fontFamily
              font.pixelSize: 18
              color: itemHover.hovered ? root.urgent : root.foreground
            }

            MouseArea {
              anchors.fill: parent
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              onClicked: function(mouse) {
                if (mouse.button === Qt.LeftButton) {
                  root.run(modelData.command)
                } else if (mouse.button === Qt.RightButton) {
                  root.midnightShortcutEditorOpen = !root.midnightShortcutEditorOpen
                }
              }
            }
          }
        }

        Rectangle {
          width: 35
          height: 24
          radius: 0
          color: addBtnHover.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

          HoverHandler {
            id: addBtnHover
            onHoveredChanged: {
              if (hovered) {
                root.showTooltip(parent, "Edit Shortcuts (Nerd Fonts)")
              } else {
                root.hideTooltip(parent)
              }
            }
          }

          Text {
            anchors.centerIn: parent
            text: "󰐕"
            font.family: root.fontFamily
            font.pixelSize: 13
            color: addBtnHover.hovered ? Color.accent : Qt.rgba(1, 1, 1, 0.25)
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: root.midnightShortcutEditorOpen = !root.midnightShortcutEditorOpen
          }
        }
      }

      Column {
        id: statusColumn
        anchors {
          bottom: parent.bottom
          bottomMargin: 6
          left: parent.left
          right: parent.right
          rightMargin: 1
        }
        spacing: 2

        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          width: 18
          height: 1
          color: Color.border
          opacity: 0.5
        }

        Column {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 0

          Repeater {
            model: root.layoutEntries("right")

            ModuleSlot {
              required property var modelData
              entry: modelData
              region: "right"
              isLeftPanel: true
            }
          }
        }
      }
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      DragGhostPanel {
        required property var modelData

        screen: modelData
        ghostScreen: modelData
      }
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      BarMoveGhostPanel {
        required property var modelData

        screen: modelData
        ghostScreen: modelData
      }
    }
  }

  component BarPanel: PanelWindow {
    id: barWindow

    // Hiding parks the bar just past its screen edge instead of unmapping it.
    // Unmapping frees the layer surface and the whole scene graph, so every
    // reveal has to rebuild them — new surface, re-shaped glyphs, re-uploaded
    // textures — which measures ~150ms against ~20ms to tear down. Parking
    // keeps the surface alive, so showing is only a margin change.
    visible: !remapGuard.remapping
    exclusionMode: root.barHidden ? ExclusionMode.Ignore : ExclusionMode.Auto

    ScreenMoveRemap {
      id: remapGuard
      window: barWindow
    }

    margins {
      top: root.barHidden && root.position === "top" ? -root.barSize : 0
      bottom: root.barHidden && root.position === "bottom" ? -root.barSize : 0
      left: root.barHidden && root.position === "left" ? -root.barSize : 0
      right: root.barHidden && root.position === "right" ? -root.barSize : 0
    }

    anchors {
      top: root.position === "top" || root.vertical
      bottom: root.position === "bottom" || root.vertical
      left: root.position === "left" || !root.vertical
      right: root.position === "right" || !root.vertical
    }

    implicitWidth: root.vertical ? root.barSize : 0
    implicitHeight: root.vertical ? 0 : root.barSize
    color: root.transparent ? "transparent" : (root.isMidnightDoll ? "#010101" : root.background)
    surfaceFormat.opaque: false
    WlrLayershell.namespace: "omarchy-bar"
    WlrLayershell.layer: WlrLayer.Top

    Rectangle {
      anchors.fill: parent
      color: root.transparent ? "transparent" : (root.isMidnightDoll ? "#010101" : root.background)
      z: -1
    }

    Rectangle {
      id: midnightBottomBorder
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.leftMargin: (root.isMidnightDoll && root.position === "top") ? 47 : 0
      anchors.right: parent.right
      height: 1
      color: Color.accent
      visible: root.isMidnightDoll && !root.barHidden && root.position === "top"
      z: 999
    }

    Loader {
      anchors.fill: parent
      sourceComponent: root.vertical ? verticalBar : horizontalBar

      // A child of the loader, not a sibling of the sections: an ancestor stays
      // hovered while the pointer is over a widget, where a sibling would lose
      // hover to the section the pointer entered.
      HoverHandler {
        onHoveredChanged: root.setBarHovered(hovered)
        // Unplugging a monitor destroys its bar without a leave event, which
        // would strand this surface's tally and hold the peek open for good.
        Component.onDestruction: if (hovered) root.setBarHovered(false)
      }
    }

    PopupWindow {
      id: tooltipWindow

      visible: root.tooltipShown && root.tooltipTarget !== null && root.tooltipText !== "" && root.targetBelongsToWindow(root.tooltipTarget, barWindow)
      color: "transparent"
      implicitWidth: Math.ceil(tooltipBubble.implicitWidth)
      implicitHeight: Math.ceil(tooltipBubble.implicitHeight)

      anchor {
        id: tooltipAnchor
        window: barWindow
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.width: 1
        rect.height: 1

        onAnchoring: {
          var target = root.tooltipTarget
          if (!root.targetBelongsToWindow(target, barWindow)) return

          var popupWidth = tooltipWindow.implicitWidth
          var popupHeight = tooltipWindow.implicitHeight
          var localX = target.width / 2 - popupWidth / 2
          var localY = target.height + 6

          if (root.position === "bottom") {
            localY = -popupHeight - 6
          } else if (root.position === "left") {
            localX = target.width + 6
            localY = target.height / 2 - popupHeight / 2
          } else if (root.position === "right") {
            localX = -popupWidth - 6
            localY = target.height / 2 - popupHeight / 2
          }

          var point = barWindow.contentItem.mapFromItem(target, localX, localY)
          tooltipAnchor.rect.x = Math.round(point.x)
          tooltipAnchor.rect.y = Math.round(point.y)
        }
      }

      BorderSurface {
        id: tooltipBubble
        implicitWidth: tooltipLabel.implicitWidth + 20
        implicitHeight: tooltipLabel.implicitHeight + 14
        color: Color.tooltip.background
        borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
        radius: Style.cornerRadius

        Text {
          id: tooltipLabel
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: root.tooltipText
          color: Color.tooltip.text
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }
      }
    }

    Component {
      id: horizontalBar

      Item {
        anchors.fill: parent

        CenterModules { anchors.fill: parent }

        LeftModules {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
        }

        Row {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: 6

          MidnightSystemHud {
            visible: root.isMidnightDoll
          }

          MidnightCavaVisualizer {
            visible: root.isMidnightDoll
          }

          RightModules {}
        }
      }
    }

    Component {
      id: verticalBar

      Item {
        anchors.fill: parent

        CenterModules { anchors.fill: parent }

        LeftModules {
          anchors.top: parent.top
          anchors.topMargin: Style.space(8)
          anchors.horizontalCenter: parent.horizontalCenter
        }

        RightModules {
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(8)
          anchors.horizontalCenter: parent.horizontalCenter
        }
      }
    }
  }

  Component { id: emptyModuleComponent; Item { implicitWidth: 0; implicitHeight: 0; visible: false } }

  component DragGhostPanel: PanelWindow {
    id: ghostWindow

    required property var ghostScreen
    readonly property bool screenMatches: root.barDragScreen === ghostScreen ||
      (root.barDragScreen && ghostScreen && root.barDragScreen.name && ghostScreen.name && root.barDragScreen.name === ghostScreen.name)
    readonly property bool active: root.barDragSource && root.barDragScreen && screenMatches
    readonly property var sourceItem: root.barDragSource ? root.barDragSource.activeItem : null
    readonly property int ghostPadding: Style.space(1)
    readonly property int ghostWidth: sourceItem ? Math.max(1, Math.ceil(sourceItem.width)) : 1
    readonly property int ghostHeight: sourceItem ? Math.max(1, Math.ceil(sourceItem.height)) : 1

    visible: active && sourceItem !== null
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-bar-drag-ghost"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    // Visual-only drag feedback. Keep the input region empty so the ghost can
    // sit under the cursor without stealing the MouseArea's active pointer grab.
    mask: Region {}

    Item {
      visible: ghostWindow.visible
      x: Math.round(root.barDragScreenX - root.barDragOffsetX - ghostWindow.ghostPadding)
      y: Math.round(root.barDragScreenY - root.barDragOffsetY - ghostWindow.ghostPadding)
      width: ghostWindow.ghostWidth + ghostWindow.ghostPadding * 2
      height: ghostWindow.ghostHeight + ghostWindow.ghostPadding * 2

      BorderSurface {
        anchors.fill: parent
        color: root.transparent ? "transparent" : root.background
        borderSpec: Border.flat(root.barForeground, 1)
        radius: Math.min(Style.cornerRadius, height / 2)
        opacity: root.transparent ? 0.45 : 0.94
      }

      Image {
        anchors.fill: parent
        anchors.margins: ghostWindow.ghostPadding
        source: root.barDragImageUrl
        fillMode: Image.Stretch
        smooth: true
        opacity: 0.84
      }
    }

    Rectangle {
      readonly property var targetRect: root.barDragTargetGeometry

      visible: ghostWindow.active && targetRect !== null
      x: targetRect ? Math.round(targetRect.x) : 0
      y: targetRect ? Math.round(targetRect.y) : 0
      width: targetRect ? targetRect.width : 0
      height: targetRect ? targetRect.height : 0
      color: Color.accent
      radius: Math.min(width, height) / 2
    }
  }

  component BarMoveGhostPanel: PanelWindow {
    id: moveGhostWindow

    required property var ghostScreen
    readonly property bool screenMatches: root.barMoveScreen === ghostScreen ||
      (root.barMoveScreen && ghostScreen && root.barMoveScreen.name && ghostScreen.name && root.barMoveScreen.name === ghostScreen.name)
    visible: root.barMoveActive && screenMatches
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-bar-move-ghost"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    // Visual-only preview of the candidate edge. Keep the input region empty
    // so the overlay never steals the gesture area's active pointer grab.
    mask: Region {}

    // One fixed-geometry slab per edge, crossfaded on candidate changes.
    // Resizing a single slab between edges repaints mid-transition and
    // flickers; fading between static ones does not.
    Repeater {
      model: ["top", "bottom", "left", "right"]

      BorderSurface {
        id: edgeSlab

        required property string modelData
        readonly property bool edgeVertical: modelData === "left" || modelData === "right"
        readonly property int edgeSize: edgeVertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal

        x: modelData === "right" ? parent.width - edgeSize : 0
        y: modelData === "bottom" ? parent.height - edgeSize : 0
        width: edgeVertical ? edgeSize : parent.width
        height: edgeVertical ? parent.height : edgeSize
        color: root.transparent ? "transparent" : root.background
        borderSpec: Border.flat(root.barForeground, 1)
        visible: opacity > 0
        opacity: root.barMoveCandidate === modelData ? (root.transparent ? 0.45 : 0.7) : 0

        Behavior on opacity {
          NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
      }
    }
  }

  function findCenterAnchorEntry() {
    var entries = root.layoutEntries("center")
    var idx = root.entryIndex(entries, root.centerAnchor)
    return idx === -1 ? null : entries[idx]
  }

  component LeftModules: ModuleList {
    entries: root.layoutEntries("left")
    region: "left"
  }

  component RightModules: ModuleList {
    entries: root.isMidnightDoll ? [] : root.layoutEntries("right")
    region: "right"
    visible: !root.isMidnightDoll
  }

  component CenterModules: Item {
    id: centerRoot

    property var entries: root.layoutEntries("center")
    readonly property bool hasAnchor: root.entryIndex(entries, root.centerAnchor) !== -1
    readonly property var anchorEntry: root.findCenterAnchorEntry()
    visible: true

    Loader {
      anchors.fill: parent
      sourceComponent: root.vertical ? verticalCenterModules : horizontalCenterModules
    }

    Component {
      id: horizontalCenterModules

      Item {
        anchors.fill: parent

        CenterGestureArea { anchors.fill: parent }

        HoverHandler {
          onHoveredChanged: root.setCenterSectionHovered(hovered)
        }

        ModuleList {
          visible: !centerRoot.hasAnchor
          entries: centerRoot.entries
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesBefore(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.right: centerAnchorModule.left
          anchors.verticalCenter: centerAnchorModule.verticalCenter
        }

        ModuleSlot {
          id: centerAnchorModule
          visible: centerRoot.hasAnchor
          entry: centerRoot.anchorEntry
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesAfter(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.left: centerAnchorModule.right
          anchors.verticalCenter: centerAnchorModule.verticalCenter
        }
      }
    }

    Component {
      id: verticalCenterModules

      Item {
        anchors.fill: parent

        CenterGestureArea { anchors.fill: parent }

        HoverHandler {
          onHoveredChanged: root.setCenterSectionHovered(hovered)
        }

        ModuleList {
          visible: !centerRoot.hasAnchor
          entries: centerRoot.entries
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesBefore(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.bottom: centerAnchorModule.top
          anchors.horizontalCenter: centerAnchorModule.horizontalCenter
        }

        ModuleSlot {
          id: centerAnchorModule
          visible: centerRoot.hasAnchor
          entry: centerRoot.anchorEntry
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesAfter(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.top: centerAnchorModule.bottom
          anchors.horizontalCenter: centerAnchorModule.horizontalCenter
        }
      }
    }
  }

  component CenterGestureArea: MouseArea {
    id: gestureArea

    property bool dragging: false
    property bool suppressClick: false
    property real pressedX: 0
    property real pressedY: 0
    readonly property real dragThreshold: Style.space(4)

    acceptedButtons: Qt.LeftButton
    cursorShape: dragging ? Qt.ClosedHandCursor : Qt.ArrowCursor
    pressAndHoldInterval: 200

    function startDrag(x, y) {
      if (dragging) return
      dragging = true
      root.beginBarMove(root.targetWindow(gestureArea))
      var scenePoint = gestureArea.mapToItem(null, x, y)
      root.updateBarMove(root.windowScreenPoint(scenePoint, root.barMoveWindow))
    }

    onPressed: function(mouse) {
      dragging = false
      suppressClick = false
      pressedX = mouse.x
      pressedY = mouse.y
    }

    onPressAndHold: function(mouse) {
      // A widget above us propagates its composed press-and-hold down here without
      // ever handing over the grab, so we'd get no release or cancel to end the move.
      if (!gestureArea.pressed) return
      startDrag(mouse.x, mouse.y)
    }

    onPositionChanged: function(mouse) {
      if (!(mouse.buttons & Qt.LeftButton)) return

      if (!dragging) {
        var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
        if (distance < dragThreshold) return
        startDrag(mouse.x, mouse.y)
        return
      }

      var scenePoint = gestureArea.mapToItem(null, mouse.x, mouse.y)
      root.updateBarMove(root.windowScreenPoint(scenePoint, root.barMoveWindow))
    }

    onReleased: function(mouse) {
      if (!dragging) return
      dragging = false
      suppressClick = true
      root.finishBarMove()
      mouse.accepted = true
    }

    onCanceled: {
      dragging = false
      suppressClick = false
      root.clearBarMove()
    }

    onClicked: function(mouse) {
      if (suppressClick) {
        suppressClick = false
        mouse.accepted = true
      }
    }

    onDoubleClicked: function(mouse) {
      if (suppressClick) {
        suppressClick = false
        return
      }
      if (mouse.button === Qt.LeftButton) {
        root.toggleTransparency()
        mouse.accepted = true
      }
    }
  }

  component ModuleList: Loader {
    id: moduleListRoot

    property var entries: []
    property string region: ""

    visible: entries.length > 0
    // A hidden list must not build its modules. The center section declares
    // both an anchored and an unanchored arrangement and shows whichever
    // fits, so leaving the other one loaded mounts every center module
    // twice — two IPC handlers registered for the same target, two clocks
    // ticking, two of every timer and fetch behind them.
    active: visible && entries.length > 0
    sourceComponent: root.vertical ? verticalModuleList : horizontalModuleList
    width: item ? item.implicitWidth : 0
    height: item ? item.implicitHeight : 0

    Component {
      id: horizontalModuleList

      Row {
        spacing: 0

        Repeater {
          model: moduleListRoot.entries

          Row {
            spacing: 0

            ModuleSlot {
              visible: !(root.isMidnightDoll && (modelData.id === "omarchy.menu" || modelData.name === "omarchy.menu"))
              width: visible ? implicitWidth : 0
              entry: modelData
              region: moduleListRoot.region
            }

            WidgetButton {
              id: midnightMenuBtn
              visible: root.isMidnightDoll && (modelData.id === "omarchy.menu" || modelData.name === "omarchy.menu")
              bar: root
              text: root.menuIcon
              fontFamily: "JetBrainsMono Nerd Font"
              fontSize: 18
              foreground: Color.accent
              horizontalMargin: 6
              fixedWidth: 28
              fixedHeight: root.barSize
              onPressed: function(button) {
                if (button === Qt.RightButton) root.run("xdg-terminal-exec")
                else root.run("omarchy-shell shell toggle omarchy.menu '{\"menu\":\"root\"}'")
              }
            }

            Row {
              visible: root.isMidnightDoll && (modelData.id === "omarchy.menu" || modelData.name === "omarchy.menu") && moduleListRoot.region === "left"
              spacing: 0
              anchors.verticalCenter: parent.verticalCenter
              leftPadding: 6
              rightPadding: 8

              Text {
                text: root.hudTitle
                font.family: root.fontFamily
                font.bold: true
                font.pixelSize: 12
                color: "#bb9af7"
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                visible: root.hudSubtitle !== ""
                text: " // "
                font.family: root.fontFamily
                font.bold: true
                font.pixelSize: 12
                color: Qt.rgba(1, 1, 1, 0.4)
                anchors.verticalCenter: parent.verticalCenter
              }
              Item {
                visible: root.hudSubtitle !== ""
                width: hudSubtitleText.implicitWidth
                height: hudSubtitleText.implicitHeight
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  id: hudSubtitleText
                  anchors.fill: parent
                  text: root.hudSubtitle
                  font.family: root.fontFamily
                  font.bold: true
                  font.pixelSize: 12
                  color: hudSubMouse.containsMouse ? "#ffffff" : Color.accent

                  Behavior on color {
                    ColorAnimation { duration: 120 }
                  }
                }

                MouseArea {
                  id: hudSubMouse
                  anchors.centerIn: parent
                  width: parent.width + 8
                  height: root.barSize
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  property bool tooltipHovered: containsMouse
                  onEntered: root.showTooltip(hudSubMouse, "Activity Monitor (btop)")
                  onExited: root.hideTooltip(hudSubMouse)
                  onClicked: root.run("omarchy-launch-or-focus-tui btop")
                }
              }
            }
          }
        }
      }
    }

    Component {
      id: verticalModuleList

      Column {
        spacing: 0

        Repeater {
          model: moduleListRoot.entries

          Column {
            spacing: 0

            ModuleSlot {
              visible: !(root.isMidnightDoll && (modelData.id === "omarchy.menu" || modelData.name === "omarchy.menu"))
              height: visible ? implicitHeight : 0
              required property var modelData
              entry: modelData
              region: moduleListRoot.region
            }

            WidgetButton {
              visible: root.isMidnightDoll && (modelData.id === "omarchy.menu" || modelData.name === "omarchy.menu")
              bar: root
              text: root.menuIcon
              fontFamily: "JetBrainsMono Nerd Font"
              fontSize: 18
              foreground: Color.accent
              verticalPadding: 6
              fixedWidth: root.barSize
              fixedHeight: 28
              onPressed: function(button) {
                if (button === Qt.RightButton) root.run("xdg-terminal-exec")
                else root.run("omarchy-shell shell toggle omarchy.menu '{\"menu\":\"root\"}'")
              }
            }
          }
        }
      }
    }
  }

  component ModuleSlot: Item {
    id: slot

    required property var entry
    property string region: ""
    property bool isLeftPanel: false
    readonly property string moduleName: root.entryId(entry)
    readonly property var moduleSettings: root.entrySettings(entry)
    readonly property string customType: root.customModuleType(entry)
    // Re-evaluate when the registry mutates (Component reference changes,
    // plugin enabled/disabled, etc.). Reading the `widgets` property creates
    // the binding dependency — the wrapped function call alone wouldn't.
    readonly property var registryComponent: {
      var w = root.barWidgetRegistry.widgets
      if (customType) return null
      var registryName = root.canonicalWidgetId(moduleName)
      return w[registryName] ? w[registryName].component : null
    }
    readonly property bool qmlCustom: customType === "qml"
    readonly property bool commandCustom: customType === "command"
    readonly property bool registered: registryComponent !== null
    readonly property var activeItem: {
      if (registered) return registryLoader.item
      if (qmlCustom) return qmlLoader.item
      return componentLoader.item
    }
    readonly property bool hovered: moduleHover.hovered
    readonly property bool dragSource: root.barDragSource === slot
    readonly property bool panelOpen: root.activePopout === slot.activeItem
    // Modules bigger than the mark they want (a text label in a padded slot,
    // a multi-line stack on a vertical bar) can say how long the open-panel
    // dot should be along the bar, so it tracks what the module paints
    // instead of a fraction of whatever slot it happens to fill.
    readonly property real panelIndicatorExtent: {
      var key = (root.vertical || isLeftPanel) ? "openPanelIndicatorHeight" : "openPanelIndicatorWidth"
      var hint = activeItem && key in activeItem ? activeItem[key] : undefined
      if (hint !== undefined && hint !== null && hint > 0) return Math.round(hint)
      return Math.max(Style.space(10), Math.round(((root.vertical || isLeftPanel) ? slot.height : slot.width) * 0.55))
    }
    implicitWidth: activeItem && activeItem.visible ? ((root.vertical || isLeftPanel) ? (isLeftPanel ? 35 : root.barSize) : activeItem.implicitWidth) : 0
    implicitHeight: activeItem && activeItem.visible ? activeItem.implicitHeight : 0
    width: implicitWidth
    height: implicitHeight
    z: modulePointer.dragging ? 100 : 0

    Component.onCompleted: root.registerModuleSlot(slot)
    Component.onDestruction: {
      if (root.barDragSource === slot) root.clearBarDrag()
      root.unregisterModuleSlot(slot)
    }

    HoverHandler { id: moduleHover }

    BorderSurface {
      visible: slot.dragSource
      anchors.fill: parent
      anchors.margins: Style.space(1)
      color: root.transparent ? "transparent" : root.background
      borderSpec: Border.flat(root.barForeground, 1)
      radius: Math.min(Style.cornerRadius, height / 2)
      opacity: root.transparent ? 0.22 : 0.32
    }

    Loader {
      id: componentLoader
      active: !slot.qmlCustom && !slot.registered
      sourceComponent: slot.commandCustom ? customCommandModuleComponent : emptyModuleComponent
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Loader {
      id: registryLoader
      active: slot.registered
      sourceComponent: slot.registered ? slot.registryComponent : null
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Loader {
      id: qmlLoader
      active: slot.qmlCustom
      source: slot.qmlCustom ? root.customModuleSource(slot.entry) : ""
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Rectangle {
      id: openPanelIndicator

      readonly property int inset: Style.space(2)

      visible: opacity > 0
      opacity: slot.panelOpen && !slot.dragSource ? 0.9 : 0
      color: Color.accent
      radius: Math.min(width, height) / 2
      width: root.vertical ? Style.space(2) : slot.panelIndicatorExtent
      height: root.vertical ? slot.panelIndicatorExtent : Style.space(2)
      // The mark sits on the module's inner edge — the one facing the
      // desktop — so it underlines a top bar, overlines a bottom one, and
      // points inward from a left or right one. It reads as pointing at the
      // panel that opens on that side.
      x: root.vertical
        ? (root.position === "left" ? parent.width - width - inset : inset)
        : Math.round((parent.width - width) / 2)
      y: root.vertical
        ? Math.round((parent.height - height) / 2)
        : (root.position === "top" ? parent.height - height - inset : inset)
      z: 50

      Behavior on opacity {
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
      }
    }

    MouseArea {
      id: modulePointer

      property bool dragging: false
      property bool suppressClick: false
      property real pressedX: 0
      property real pressedY: 0
      readonly property bool canReorder: root.shell && typeof root.shell.mutateShellConfig === "function"
      readonly property real dragThreshold: Style.space(4)

      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      enabled: slot.visible && slot.width > 0 && slot.height > 0
      propagateComposedEvents: true
      cursorShape: root.moduleClickTargetAt(slot, mouseX, mouseY) ? Qt.PointingHandCursor : Qt.ArrowCursor
      // Do not assign drag.target here: ModuleSlot is owned by Row/Column
      // positioners, and mutating slot.x/slot.y can leave stale offsets that
      // make neighboring modules overlap after a small aborted drag.

      onPressed: function(mouse) {
        dragging = false
        suppressClick = false
        pressedX = mouse.x
        pressedY = mouse.y
        root.clearBarDrag()
      }

      onPositionChanged: function(mouse) {
        if (!canReorder || !(mouse.buttons & Qt.LeftButton)) return

        var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
        if (distance >= dragThreshold) {
          if (!dragging) {
            root.barDragWindow = root.targetWindow(slot.activeItem) || root.targetWindow(slot)
            root.barDragScreen = root.barDragWindow ? root.barDragWindow.screen : null
            root.barDragOffsetX = pressedX
            root.barDragOffsetY = pressedY
            root.captureBarDragGhost(slot)
            root.barDragSource = slot
          }
          dragging = true
          root.hideTooltip(slot.activeItem)
        }

        if (dragging) {
          var scenePoint = slot.mapToItem(null, mouse.x, mouse.y)
          var screenPoint = root.barDragScreenPoint(scenePoint)
          root.barDragSceneX = scenePoint.x
          root.barDragSceneY = scenePoint.y
          root.barDragScreenX = screenPoint.x
          root.barDragScreenY = screenPoint.y

          var drop = root.moduleDropAtScene(scenePoint, slot)
          root.barDragTarget = drop ? drop.slot : null
          root.barDragAfter = drop ? drop.after : false
          root.barDragTargetGeometry = drop ? root.dropMarkerRect(drop.slot, drop.after) : null
        }
      }

      onReleased: function(mouse) {
        var wasDragging = dragging
        var targetSlot = root.barDragTarget
        var afterTarget = root.barDragAfter

        if (wasDragging) suppressClick = true

        dragging = false
        root.clearBarDrag()

        if (wasDragging && targetSlot) {
          root.dropBarModuleAtTarget(slot, targetSlot, afterTarget)
          mouse.accepted = true
        } else if (!wasDragging) {
          mouse.accepted = false
        }
      }

      onCanceled: {
        dragging = false
        suppressClick = false
        root.clearBarDrag()
      }

      onClicked: function(mouse) {
        if (suppressClick) {
          suppressClick = false
          mouse.accepted = true
          return
        }

        if (!root.pressModuleClickTarget(slot, mouse.button, mouse.x, mouse.y)) mouse.accepted = false
      }
    }

    onActiveItemChanged: Qt.callLater(injectProps)
    onModuleSettingsChanged: injectProps()

    function injectProps() {
      var target = activeItem
      if (!target) return
      if ("bar" in target) target.bar = (slot.isLeftPanel ? root.leftBarContext : root)
      if ("moduleName" in target) target.moduleName = moduleName
      if ("settings" in target) target.settings = moduleSettings
    }

    Component {
      id: customCommandModuleComponent
      CustomCommandModule { entry: slot.entry }
    }
  }

  component CustomCommandModule: WidgetButton {
    id: customRoot

    required property var entry
    readonly property string moduleName: root.entryId(entry)
    readonly property var settings: root.entrySettings(entry)
    property string outputText: ""
    property string outputTooltip: ""
    property bool outputActive: false

    function setting(name, fallback) {
      var value = settings ? settings[name] : undefined
      return value === undefined || value === null ? fallback : value
    }

    function update(raw) {
      var data = Util.parseModuleJson(raw)
      var klass = data.class || data.alt || ""

      outputText = data.text || String(raw || "").trim()
      outputTooltip = data.tooltip || String(setting("tooltip", ""))
      outputActive = klass === "active" || (Array.isArray(klass) && klass.indexOf("active") !== -1)
    }

    bar: root
    text: outputText || String(setting("text", ""))
    tooltipText: outputTooltip || String(setting("tooltip", ""))
    active: outputActive
    keepSpace: setting("keepSpace", false) === true
    horizontalMargin: Number(setting("horizontalMargin", 7.5))
    verticalPadding: Number(setting("verticalPadding", 6))
    fontSize: Number(setting("fontSize", 12))

    onPressed: function(button) {
      var command = ""
      if (button === Qt.RightButton)
        command = String(setting("onRightClick", ""))
      else if (button === Qt.MiddleButton)
        command = String(setting("onMiddleClick", ""))
      else
        command = String(setting("onClick", ""))

      if (command) root.run(command)
    }

    Process {
      id: customProc
      command: ["bash", "-lc", String(customRoot.setting("exec", ""))]
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: customRoot.update(text)
      }
    }

    Timer {
      interval: Math.max(1, Number(customRoot.setting("interval", 5))) * 1000
      running: String(customRoot.setting("exec", "")) !== ""
      repeat: true
      triggeredOnStart: true
      onTriggered: root.runProcess(customProc)
    }
  }

  component MidnightSystemHud: Row {
    id: sysHudRoot
    visible: root.isMidnightDoll && !root.barHidden
    spacing: 5
    anchors.verticalCenter: parent.verticalCenter
    height: root.barSize

    property int cpuVal: 0
    property int memVal: 0
    property string memGb: "0G"
    property int dskVal: 0
    property string rxRate: "0B"
    property string txRate: "0B"

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
      command: ["/bin/bash", root.home + "/.config/omarchy/sys-hud.sh"]
      stdout: SplitParser {
        onRead: function(line) {
          sysHudRoot.updateMetrics(line)
        }
      }
    }

    Timer {
      interval: 1500
      running: sysHudRoot.visible
      repeat: true
      triggeredOnStart: true
      onTriggered: sysProc.running = true
    }

    // CPU Gauge (Fixed Width)
    Row {
      spacing: 2
      anchors.verticalCenter: parent.verticalCenter
      Text {
        text: "CPU"
        font.family: root.fontFamily
        font.pixelSize: 8
        font.bold: true
        color: "#bb9af7"
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
          width: Math.max(1, Math.round(parent.width * (sysHudRoot.cpuVal / 100.0)))
          color: sysHudRoot.cpuVal > 80 ? root.urgent : Color.accent
        }
      }
      Text {
        text: sysHudRoot.cpuVal + "%"
        font.family: root.fontFamily
        font.pixelSize: 8
        color: Color.foreground
        width: 22
        horizontalAlignment: Text.AlignRight
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    // RAM / MEM Gauge (Fixed Width)
    Row {
      spacing: 2
      anchors.verticalCenter: parent.verticalCenter
      Text {
        text: "RAM"
        font.family: root.fontFamily
        font.pixelSize: 8
        font.bold: true
        color: "#bb9af7"
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
          width: Math.max(1, Math.round(parent.width * (sysHudRoot.memVal / 100.0)))
          color: sysHudRoot.memVal > 85 ? root.urgent : Color.accent
        }
      }
      Text {
        text: sysHudRoot.memGb
        font.family: root.fontFamily
        font.pixelSize: 8
        color: Color.foreground
        width: 28
        horizontalAlignment: Text.AlignRight
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    // DISK Gauge (Fixed Width)
    Row {
      spacing: 2
      anchors.verticalCenter: parent.verticalCenter
      Text {
        text: "DSK"
        font.family: root.fontFamily
        font.pixelSize: 8
        font.bold: true
        color: "#bb9af7"
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
          width: Math.max(1, Math.round(parent.width * (sysHudRoot.dskVal / 100.0)))
          color: sysHudRoot.dskVal > 90 ? root.urgent : Color.accent
        }
      }
      Text {
        text: sysHudRoot.dskVal + "%"
        font.family: root.fontFamily
        font.pixelSize: 8
        color: Color.foreground
        width: 22
        horizontalAlignment: Text.AlignRight
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    // NET Rates (Fixed Width)
    Row {
      spacing: 2
      anchors.verticalCenter: parent.verticalCenter
      Text {
        text: "NET"
        font.family: root.fontFamily
        font.pixelSize: 8
        font.bold: true
        color: "#bb9af7"
        width: 17
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        text: "▲" + sysHudRoot.txRate + " ▼" + sysHudRoot.rxRate
        font.family: root.fontFamily
        font.pixelSize: 8
        color: Color.accent
        width: 78
        horizontalAlignment: Text.AlignLeft
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

  component MidnightCavaVisualizer: Row {
    id: cavaRoot
    visible: root.isMidnightDoll && !root.barHidden
    spacing: 2
    anchors.verticalCenter: parent.verticalCenter
    height: root.barSize

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
      command: ["cava", "-p", root.home + "/.config/omarchy/cava.conf"]
      running: cavaRoot.visible
      stdout: SplitParser {
        onRead: function(line) {
          if (!line) return
          var parts = line.trim().split(";")
          var vals = []
          for (var i = 0; i < parts.length; i++) {
            if (parts[i] !== "") vals.push(parseInt(parts[i], 10) || 0)
          }
          if (vals.length >= 12) {
            cavaRoot.updateValues(vals)
          }
        }
      }
    }

    // Inverted Stacked Meters: AIR (top), MID (middle), BASS (bottom)
    Column {
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: -2
      spacing: 0

      // AIR (Top)
      Row {
        spacing: 3
        Text {
          text: "AIR"
          font.family: root.fontFamily
          font.pixelSize: 7
          font.bold: true
          color: cavaRoot.airLevel > 0.6 ? root.urgent : "#bb9af7"
          anchors.verticalCenter: parent.verticalCenter
          width: 18
          horizontalAlignment: Text.AlignRight
        }
        Rectangle {
          width: 24
          height: 2
          color: Qt.rgba(0.73, 0.60, 0.97, 0.22)
          anchors.verticalCenter: parent.verticalCenter
          Rectangle {
            anchors.left: parent.left
            height: parent.height
            width: Math.max(1, Math.round(parent.width * cavaRoot.airLevel))
            color: Color.accent
          }
        }
      }

      // MID (Middle)
      Row {
        spacing: 3
        Text {
          text: "MID"
          font.family: root.fontFamily
          font.pixelSize: 7
          font.bold: true
          color: cavaRoot.midLevel > 0.6 ? root.urgent : "#bb9af7"
          anchors.verticalCenter: parent.verticalCenter
          width: 18
          horizontalAlignment: Text.AlignRight
        }
        Rectangle {
          width: 24
          height: 2
          color: Qt.rgba(0.73, 0.60, 0.97, 0.22)
          anchors.verticalCenter: parent.verticalCenter
          Rectangle {
            anchors.left: parent.left
            height: parent.height
            width: Math.max(1, Math.round(parent.width * cavaRoot.midLevel))
            color: Color.accent
          }
        }
      }

      // BASS (Bottom)
      Row {
        spacing: 3
        Text {
          text: "BASS"
          font.family: root.fontFamily
          font.pixelSize: 7
          font.bold: true
          color: cavaRoot.bassLevel > 0.6 ? root.urgent : "#bb9af7"
          anchors.verticalCenter: parent.verticalCenter
          width: 18
          horizontalAlignment: Text.AlignRight
        }
        Rectangle {
          width: 24
          height: 2
          color: Qt.rgba(0.73, 0.60, 0.97, 0.22)
          anchors.verticalCenter: parent.verticalCenter
          Rectangle {
            anchors.left: parent.left
            height: parent.height
            width: Math.max(1, Math.round(parent.width * cavaRoot.bassLevel))
            color: Color.accent
          }
        }
      }
    }

    // Dynamic Rich Violet LED Dot Matrix Visualizer
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
        var s = cavaRoot.spectrum
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
                ctx.fillStyle = Color.accent ? Color.accent : "#ff51c5" // Vibrant neon accent peak
              } else {
                ctx.fillStyle = "#bb9af7" // Bright violet active LED
              }
            } else {
              ctx.fillStyle = Qt.rgba(0.73, 0.60, 0.97, 0.28) // Visible glowing violet base LED
            }
            ctx.fill()
          }
        }
      }
    }
  }
}
