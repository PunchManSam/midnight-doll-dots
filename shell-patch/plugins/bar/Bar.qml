import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
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
  onBarHiddenChanged: {
    root.triggerFullscreenSync()
  }

  property string home: Quickshell.env("HOME")
  property bool fullscreenSyncPending: false

  Process {
    id: fullscreenBarSyncProc
    command: ["/home/punch/.local/bin/omarchy-fullscreen-bar-sync"]
    onExited: {
      if (root.fullscreenSyncPending) {
        root.fullscreenSyncPending = false
        fullscreenSyncDebounceTimer.restart()
      }
    }
  }

  Timer {
    id: fullscreenSyncDebounceTimer
    interval: 50
    repeat: false
    onTriggered: {
      if (fullscreenBarSyncProc.running) {
        root.fullscreenSyncPending = true
      } else {
        fullscreenBarSyncProc.running = true
      }
    }
  }

  function triggerFullscreenSync() {
    fullscreenSyncDebounceTimer.restart()
  }

  FileView {
    id: fullscreenStateFile
    path: root.home + "/.local/state/omarchy/fullscreen-bars.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.syncFullscreenFromStateFile()
    onFileChanged: reload()
    onTextChanged: root.syncFullscreenFromStateFile()
  }

  function syncFullscreenFromStateFile() {
    try {
      var raw = fullscreenStateFile.text()
      if (raw && raw.trim().length > 0) {
        var parsed = JSON.parse(raw)
        if (typeof parsed.fullscreen_active === "boolean") {
          var ws = Hyprland.focusedWorkspace
          var wsId = ws ? ws.id : null
          var active = parsed.fullscreen_active
          if (active && parsed.fullscreen_workspace !== undefined && wsId !== null && parsed.fullscreen_workspace !== wsId) {
            active = false
          }
          if (root.fullscreenModeActive !== active) {
            root.fullscreenModeActive = active
          }
          return
        }
      }
    } catch (e) {}
  }
  FileView {
    id: currentThemeFile
    path: root.home + "/.local/state/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onLoaded: root.activeTheme = String(text() || "").trim()
    onFileChanged: reload()
  }
  property string activeTheme: "midnight-doll"
  property string hudTitle: "MIDNIGHT-DOLL"
  property string hudSubtitle: "HUD"
  property string hudCommand: "omarchy-launch-or-focus-tui btop"
  property color secondaryColor: "#bb9af7"
  property string menuIcon: "󰚌"

  function hudTooltipText() {
    if (!root.hudCommand || root.hudCommand.trim() === "") return ""
    if (root.hudCommand.indexOf("btop") !== -1) return "Activity Monitor (btop)"
    return "Run: " + root.hudCommand
  }
  readonly property bool isMidnightDoll: {
    var name = activeTheme.toLowerCase().replace(/[\s_-]+/g, "")
    return name === "midnightdoll"
  }
  onIsMidnightDollChanged: applyBarConfig()
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

  // Responsive corner fillet radius based on bar size and screen resolution / scaling
  readonly property int midnightCornerRadius: {
    if (Style.cornerRadius > 0) return Style.cornerRadius
    var base = Math.round(root.barSize * 0.5)
    var rounded = Math.max(12, Math.min(24, base))
    return Math.round(rounded / 4) * 4
  }

  // Active window in top-left detection and adaptive highlight styling
  property bool topLeftWindowActive: false
  property bool topLeftWindowPresent: false
  readonly property color inactiveBorderColor: {
    try {
      return Qt.rgba(root.secondaryColor.r * 0.22, root.secondaryColor.g * 0.22, root.secondaryColor.b * 0.22, 1.0)
    } catch (e) {
      return "#2b0938"
    }
  }

  property real activeCornerStrokeWidth: 3.0
  property real cornerStrokeWidth: root.topLeftWindowActive ? (root.activeCornerStrokeWidth + 1.0) : 1.0
  Behavior on cornerStrokeWidth {
    NumberAnimation {
      duration: 200
      easing.type: Easing.OutQuint
    }
  }
  readonly property real cornerStrokeOffset: (root.cornerStrokeWidth - 1.0) / 2
  readonly property color cornerStrokeColor: Color.accent

  Process {
    id: hyprBorderSizeProc
    command: ["hyprctl", "getoption", "general:border_size", "-j"]
    running: root.isMidnightDoll
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || "").trim())
          if (parsed && typeof parsed.int === "number" && parsed.int > 0) {
            root.activeCornerStrokeWidth = parsed.int
          }
        } catch (e) {}
      }
    }
  }

  function updateTopLeftWindowState() {
    if (!root.isMidnightDoll) return

    var activeTop = Hyprland.activeToplevel
    if (!activeTop) {
      root.topLeftWindowActive = false
      root.topLeftWindowPresent = false
      return
    }

    var ws = Hyprland.focusedWorkspace
    var activeIpc = activeTop.lastIpcObject

    // Fullscreen window active on the focused workspace always occupies the top-left corner
    var isFullscreen = Boolean(activeTop.fullscreen || (activeIpc && activeIpc.fullscreen && activeIpc.fullscreen !== 0))
    if (isFullscreen) {
      var actWsId = (activeTop.workspace && activeTop.workspace.id) || (activeIpc && activeIpc.workspace && activeIpc.workspace.id)
      var curWsId = ws ? ws.id : null
      if (curWsId === null || actWsId === undefined || actWsId === null || actWsId === curWsId) {
        root.topLeftWindowActive = true
        root.topLeftWindowPresent = true
        return
      }
    }

    var isFloating = Boolean(activeTop.floating || (activeIpc && activeIpc.floating && (!activeIpc.fullscreen || activeIpc.fullscreen === 0)))
    if (isFloating) {
      root.topLeftWindowActive = false
    }

    var toplevels = (ws && ws.toplevels && ws.toplevels.values) ? ws.toplevels.values : []
    if (toplevels.length === 0) {
      root.topLeftWindowActive = false
      root.topLeftWindowPresent = false
      return
    }

    var minX = Infinity
    var minY = Infinity
    var hasTiled = false

    for (var i = 0; i < toplevels.length; i++) {
      var top = toplevels[i]
      var ipc = top ? top.lastIpcObject : null
      var ipcFloating = Boolean((top && top.floating) || (ipc && ipc.floating && (!ipc.fullscreen || ipc.fullscreen === 0)))
      if (ipc && !ipcFloating && ipc.at && ipc.at.length >= 2) {
        var x = Number(ipc.at[0])
        var y = Number(ipc.at[1])
        if (!isNaN(x) && !isNaN(y)) {
          if (x < minX) minX = x
          if (y < minY) minY = y
          hasTiled = true
        }
      }
    }

    if (!hasTiled || minX === Infinity || minY === Infinity) {
      root.topLeftWindowActive = false
      root.topLeftWindowPresent = false
      return
    }

    root.topLeftWindowPresent = true

    if (!isFloating && activeIpc && activeIpc.at && activeIpc.at.length >= 2) {
      var ax = Number(activeIpc.at[0])
      var ay = Number(activeIpc.at[1])
      if (!isNaN(ax) && !isNaN(ay)) {
        root.topLeftWindowActive = (Math.abs(ax - minX) <= 3 && Math.abs(ay - minY) <= 3)
        return
      }
    }

    root.topLeftWindowActive = false
  }

  property bool fullscreenModeActive: false

  function updateFullscreenState() {
    root.syncFullscreenFromStateFile()
    root.triggerFullscreenSync()
  }

  property var urgentAddresses: ({})
  property int urgentTick: 0
  property var rawNotifications: []
  property var workspaceVisitedTimes: ({})

  function markWorkspaceVisited(wsId) {
    var id = parseInt(wsId, 10)
    if (isNaN(id) || id <= 0) return
    var visited = Object.assign({}, root.workspaceVisitedTimes)
    visited[id] = Date.now()
    root.workspaceVisitedTimes = visited
    root.urgentTick = (root.urgentTick + 1) % 1000
  }

  function isBrowserClass(cls) {
    if (!cls) return false
    var c = String(cls).toLowerCase().trim()
    return c === "chromium" || c === "google-chrome" || c === "chrome" ||
           c === "brave" || c === "brave-browser" || c === "firefox" ||
           c === "vivaldi" || c === "opera" || c === "microsoft-edge" ||
           c.indexOf("chrome-") === 0
  }

  function matchesApp(notifOrApp, ipc) {
    if (!notifOrApp || !ipc) return false
    var isObj = (typeof notifOrApp === "object" && notifOrApp !== null)
    var app = isObj ? (notifOrApp.app || "") : notifOrApp
    var a = String(app).toLowerCase().trim()
    if (!a || a === "notify-send") return false

    var c = String(ipc.class || "").toLowerCase().trim()
    var ic = String(ipc.initialClass || "").toLowerCase().trim()

    // Browser notification discrimination:
    // When notification comes from a browser, only match browser windows whose
    // webapp class, domain, or title specifically corresponds to the site/content.
    if (root.isBrowserClass(a)) {
      if (!root.isBrowserClass(c) && !root.isBrowserClass(ic)) return false

      var body = isObj ? String(notifOrApp.body || "") : ""
      var summary = isObj ? String(notifOrApp.summary || "") : ""
      var title = String(ipc.title || "").toLowerCase()
      var initialTitle = String(ipc.initialTitle || "").toLowerCase()

      // 1. Direct class match for PWAs/WebApps (e.g. chrome-teams.microsoft.com__-Default or chrome-chess.com__-Default)
      var urlMatch = body.match(/https?:\/\/([^\/\s"'>]+)/i)
      var host = urlMatch ? urlMatch[1].toLowerCase() : ""
      if (host && (c.indexOf(host) !== -1 || ic.indexOf(host) !== -1)) return true

      // 2. Extract significant domain keywords from notification body URL/anchor
      var keywords = []
      var generic = ["com", "org", "net", "edu", "gov", "cloud", "app", "io", "co", "uk", "de", "ca", "www", "web", "https", "http"]

      if (host) {
        var hostParts = host.split(".")
        for (var i = 0; i < hostParts.length; i++) {
          var hp = hostParts[i].trim()
          if (hp.length > 2 && generic.indexOf(hp) === -1) keywords.push(hp)
        }
      }

      var anchorMatch = body.match(/<a\b[^>]*>([^<]+)<\/a>/i)
      if (anchorMatch && anchorMatch[1]) {
        var anchorParts = anchorMatch[1].toLowerCase().split(/[.\s\-_/]+/)
        for (var j = 0; j < anchorParts.length; j++) {
          var ap = anchorParts[j].trim()
          if (ap.length > 2 && generic.indexOf(ap) === -1 && keywords.indexOf(ap) === -1) keywords.push(ap)
        }
      }

      // Check keywords against window title or PWA class
      for (var k = 0; k < keywords.length; k++) {
        var kw = keywords[k]
        if (title.indexOf(kw) !== -1 || initialTitle.indexOf(kw) !== -1 || c.indexOf(kw) !== -1 || ic.indexOf(kw) !== -1) {
          return true
        }
      }

      // Also check summary if specific enough (e.g. sender name or channel)
      var sumLower = summary.trim().toLowerCase()
      if (sumLower.length > 3 && (title.indexOf(sumLower) !== -1 || initialTitle.indexOf(sumLower) !== -1)) {
        return true
      }

      // If notification came from a browser and didn't match this browser window's web app, REJECT.
      return false
    }

    // Standard non-browser desktop application identity matching
    if (c === a || ic === a) return true
    if (c && (c.indexOf(a) !== -1 || a.indexOf(c) !== -1)) return true
    if (ic && (ic.indexOf(a) !== -1 || a.indexOf(ic) !== -1)) return true
    var cParts = c.split(".")
    var cLast = cParts[cParts.length - 1]
    if (cLast && (cLast === a || cLast.indexOf(a) !== -1 || a.indexOf(cLast) !== -1)) return true
    var icParts = ic.split(".")
    var icLast = icParts[icParts.length - 1]
    if (icLast && (icLast === a || icLast.indexOf(a) !== -1 || a.indexOf(icLast) !== -1)) return true
    return false
  }

  Process {
    id: notifProc
    command: ["python3", "-c", "import glob, json, os\nnotifs = []\nfor p in glob.glob(os.path.expanduser('~/.local/state/omarchy/notifications/*.json')):\n    try:\n        with open(p) as f:\n            d = json.load(f)\n            notifs.append({'app': str(d.get('app','')).lower(), 'ts': int(d.get('timestamp',0)), 'active': True, 'summary': str(d.get('summary','')), 'body': str(d.get('body',''))})\n    except: pass\nfor p in glob.glob(os.path.expanduser('~/.local/state/omarchy/notifications/history/*.json')):\n    try:\n        with open(p) as f:\n            d = json.load(f)\n            notifs.append({'app': str(d.get('app','')).lower(), 'ts': int(d.get('timestamp',0)), 'active': False, 'summary': str(d.get('summary','')), 'body': str(d.get('body',''))})\n    except: pass\nprint(json.dumps(notifs))"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var str = String(text || "").trim()
        if (!str) {
          root.rawNotifications = []
          return
        }
        try {
          var parsed = JSON.parse(str)
          if (Array.isArray(parsed)) {
            root.rawNotifications = parsed
            root.urgentTick = (root.urgentTick + 1) % 1000
          }
        } catch (e) {}
      }
    }
  }

  Timer {
    id: notifTimer
    interval: 800
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!notifProc.running) {
        notifProc.running = true
      }
    }
  }

  function workspaceNotificationCount(workspaceId, workspaceObj) {
    if (!workspaceObj) return 0
    var total = 0

    var toplevels = (workspaceObj.toplevels && workspaceObj.toplevels.values) ? workspaceObj.toplevels.values : []
    var visitedTime = (root.workspaceVisitedTimes && root.workspaceVisitedTimes[workspaceId]) || 0

    // 1. Native Wayland / X11 window urgency or Hyprland urgent event
    for (var i = 0; i < toplevels.length; i++) {
      var top = toplevels[i]
      if (!top) continue
      var ipc = top.lastIpcObject
      var isUrgent = (top.urgent === true) || (ipc && ipc.address && root.urgentAddresses && root.urgentAddresses[ipc.address])
      if (isUrgent) {
        total += 1
      }
    }

    // 2. Desktop notification popups & unread notifications matching windows on this workspace
    if (root.rawNotifications && root.rawNotifications.length > 0 && toplevels.length > 0) {
      for (var n = 0; n < root.rawNotifications.length; n++) {
        var notif = root.rawNotifications[n]
        if (!notif || !notif.app) continue

        var isUnread = notif.ts && notif.ts > visitedTime

        if (!isUnread) continue

        for (var t = 0; t < toplevels.length; t++) {
          var tipc = toplevels[t] ? toplevels[t].lastIpcObject : null
          if (!tipc) continue
          if (root.matchesApp(notif, tipc)) {
            total += 1
            break
          }
        }
      }
    }

    return total
  }

  function hasAnyUrgentWorkspaces() {
    var _ = root.urgentTick
    var focusedId = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : null
    var wsList = Hyprland.workspaces ? Hyprland.workspaces.values : []
    for (var i = 0; i < wsList.length; i++) {
      var ws = wsList[i]
      if (!ws || ws.id === focusedId || ws.id <= 0) continue
      if (root.workspaceNotificationCount(ws.id, ws) > 0) return true
    }
    return false
  }

  readonly property bool hasUrgentWorkspaceNotification: {
    var _ = root.urgentTick
    return root.hasAnyUrgentWorkspaces()
  }

  Connections {
    target: Hyprland
    function onActiveToplevelChanged() {
      root.updateTopLeftWindowState()
      root.triggerFullscreenSync()
    }
    function onFocusedWorkspaceChanged() {
      var ws = Hyprland.focusedWorkspace
      if (ws && ws.id) {
        root.markWorkspaceVisited(ws.id)
      }
      Hyprland.refreshToplevels()
      root.updateTopLeftWindowState()
      root.syncFullscreenFromStateFile()
      root.triggerFullscreenSync()
    }
    function onRawEvent(event) {
      if (!event) return
      if (event.name === "fullscreen") {
        var val = String(event.data || "").trim()
        if (val === "0" || val === "false") {
          root.fullscreenModeActive = false
        }
        root.triggerFullscreenSync()
        Hyprland.refreshWorkspaces()
        Hyprland.refreshToplevels()
        root.updateTopLeftWindowState()
      } else if (event.name === "openwindow" || event.name === "closewindow" ||
                 event.name === "movewindow" || event.name === "changefloatingmode") {
        if (event.name === "changefloatingmode") {
          var fData = String(event.data || "")
          var fParts = fData.split(",")
          if (fParts.length >= 2 && fParts[1].trim() === "1") {
            var act = Hyprland.activeToplevel
            var actAddr = (act && act.lastIpcObject) ? act.lastIpcObject.address : ""
            if (!actAddr || actAddr === fParts[0].trim() || root.topLeftWindowActive) {
              root.topLeftWindowActive = false
            }
          }
        }
        Hyprland.refreshWorkspaces()
        Hyprland.refreshToplevels()
        root.updateTopLeftWindowState()
        root.triggerFullscreenSync()
      } else if (event.name === "activewindow" || event.name === "activewindowv2" ||
                 event.name === "workspace" || event.name === "focusedmon") {
        if (event.name === "workspace") {
          root.markWorkspaceVisited(event.data)
        }
        Hyprland.refreshWorkspaces()
        Hyprland.refreshToplevels()
        root.updateTopLeftWindowState()
        root.triggerFullscreenSync()
      } else if (event.name === "configreloaded") {
        if (!hyprBorderSizeProc.running) {
          hyprBorderSizeProc.running = true
        }
      }
      if (event.name === "urgent") {
        var addr = String(event.data || "").trim()
        if (addr) {
          var map = Object.assign({}, root.urgentAddresses)
          map[addr] = true
          root.urgentAddresses = map
          root.urgentTick = (root.urgentTick + 1) % 1000
        }
      } else if (event.name === "activewindow" || event.name === "activewindowv2") {
        var activeTop = Hyprland.activeToplevel
        var activeAddr = (activeTop && activeTop.lastIpcObject) ? activeTop.lastIpcObject.address : null
        if (activeAddr && root.urgentAddresses[activeAddr]) {
          var map = Object.assign({}, root.urgentAddresses)
          delete map[activeAddr]
          root.urgentAddresses = map
          root.urgentTick = (root.urgentTick + 1) % 1000
        }
      }
    }
  }

  Connections {
    target: Hyprland.activeToplevel
    function onLastIpcObjectChanged() {
      root.updateTopLeftWindowState()
    }
  }

  Timer {
    interval: (root.isMidnightDoll && (root.topLeftWindowActive || root.topLeftWindowPresent)) ? 150 : 1000
    running: true
    repeat: true
    onTriggered: {
      if (root.isMidnightDoll && (root.topLeftWindowActive || root.topLeftWindowPresent)) {
        Hyprland.refreshToplevels()
      }
      root.updateTopLeftWindowState()
      root.syncFullscreenFromStateFile()
      root.urgentTick = (root.urgentTick + 1) % 1000
    }
  }
  property QtObject leftBarContext: QtObject {
    id: leftBarCtx
    property string position: "left"
    property bool vertical: true
    property int barSize: 36
    property bool isMidnightDoll: root.isMidnightDoll
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
    property bool transparent: root.transparent

    function run(cmd) { root.run(cmd) }
    function requestPopout(owner) { root.requestPopout(owner) }
    function releasePopout(owner) { root.releasePopout(owner) }
    function showTooltip(target, text) { root.showTooltip(target, text) }
    function hideTooltip(target) { root.hideTooltip(target) }
    function moduleWidgets(name) { return root.moduleWidgets(name) }
    function canonicalWidgetId(id) { return root.canonicalWidgetId(id) }
    function registerClickTarget(target) { root.registerClickTarget(target) }
    function unregisterClickTarget(target) { root.unregisterClickTarget(target) }
    function switchPanelFrom(owner, dir) { return root.switchPanelFrom(owner, dir) }
  }
  property string stateHome: home + "/.local/state"
  property string omarchyConfigDir: home + "/.config/omarchy"
  property var fallbackBarConfig: ({
    position: "top",
    transparent: false,
    centerAnchor: "omarchy.clock",
    layout: { left: [], center: [], right: [], status: [] }
  })
  property var layoutConfig: fallbackBarConfig.layout
  property string centerAnchor: ""
  property bool requestedTransparent: false
  property bool useTransparentForeground: false
  property bool transparent: false

  property real barAnimProgress: root.barHidden ? 0.0 : 1.0
  Behavior on barAnimProgress {
    NumberAnimation {
      duration: root.barHidden ? Style.duration(200) : Style.duration(260)
      easing.type: root.barHidden ? Easing.InCubic : Easing.OutCubic
    }
  }
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

    var isLeftWindow = window.WlrLayershell && window.WlrLayershell.namespace === "omarchy-midnight-left-bar"
    if (!isLeftWindow) {
      if (root.position === "bottom")
        y += Math.max(0, window.screen.height - window.height)
      else if (root.position === "right")
        x += Math.max(0, window.screen.width - window.width)
    }

    return { x: x, y: y }
  }

  function slotScreenPoint(slot) {
    if (!slot) return { x: 0, y: 0 }
    var win = root.slotWindow(slot)
    var slotLocal = { x: 0, y: 0 }
    try {
      slotLocal = slot.mapToItem(null, 0, 0)
    } catch (e) {
      slotLocal = { x: slot.x, y: slot.y }
    }
    return windowScreenPoint(slotLocal, win)
  }

  function barDragScreenPoint(scenePoint) {
    return windowScreenPoint(scenePoint, barDragWindow)
  }

  function dropMarkerRect(slot, after) {
    if (!slot) return null

    try {
      var screenPoint = root.slotScreenPoint(slot)
      var thickness = Style.spacing.xs
      var isVertical = root.vertical || (slot.isLeftPanel === true) || (slot.region === "status")
      if (isVertical) {
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

    if (root.isMidnightDoll) {
      return ny < 0.5 ? "top" : "bottom"
    }

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

  function isStatusWidget(id) {
    if (!id) return false
    var base = id.replace(/^[a-zA-Z0-9_-]+\./, "")
    var statusBases = [
      "agents", "tray", "audio", "bluetooth", "network", "monitor", "power",
      "battery", "microphone", "tailscale", "dropbox"
    ]
    return statusBases.indexOf(base) !== -1 || id.endsWith(".agents")
  }

  function isMidnightOnlyWidget(id) {
    if (!id) return false
    var base = id.replace(/^[a-zA-Z0-9_-]+\./, "")
    return base === "sys-hud" || base === "system-hud" || base === "hud" ||
           base === "visualizer" || base === "cava" ||
           id === "midnight-doll.sys-hud" || id === "midnight-doll.system-hud" ||
           id === "midnight-doll.hud" || id === "midnight-doll.visualizer" ||
           id === "midnight-doll.cava"
  }

  function deduplicateEntries(entries) {
    if (!Array.isArray(entries)) return []
    var seen = {}
    var out = []
    for (var i = 0; i < entries.length; i++) {
      var id = root.entryId(entries[i])
      if (id) {
        var canon = root.canonicalWidgetId(id)
        if (seen[canon]) continue
        seen[canon] = true
      }
      out.push(entries[i])
    }
    return out
  }

  function filterMidnightWidgets(entries) {
    if (!Array.isArray(entries)) return []
    var out = []
    for (var i = 0; i < entries.length; i++) {
      var id = root.entryId(entries[i])
      if (!isMidnightOnlyWidget(id)) out.push(entries[i])
    }
    return out
  }

  // Apply tray-pinning on top of the shared layout normalization so the
  // bar host and scriptable config helpers can't drift on entry shape.
  function normalizeLayout(layout) {
    var raw = Util.isPlainObject(layout) ? layout : fallbackBarConfig.layout
    var normalized = Util.normalizeLayout(raw)
    var res = {
      left:   pinTrayToInner(normalized.left,   "left"),
      center: pinTrayToInner(normalized.center, "center"),
      right:  pinTrayToInner(normalized.right,  "right"),
      status: []
    }

    if (root.isMidnightDoll) {
      res.status = res.right

      if (Array.isArray(raw.midnightRight) && raw.midnightRight.length > 0) {
        res.right = deduplicateEntries(raw.midnightRight)
      } else {
        res.right = [
          { id: "midnight-doll.sys-hud" },
          { id: "midnight-doll.visualizer" }
        ]
      }

      // In Midnight Doll, sys-hud and visualizer belong exclusively in the
      // right section (midnightRight). Filter them out of left and center to
      // prevent duplicate rendering if shell.json carries stray entries.
      res.left = filterMidnightWidgets(res.left)
      res.center = filterMidnightWidgets(res.center)
    } else {
      res.left = filterMidnightWidgets(res.left)
      res.center = filterMidnightWidgets(res.center)
      res.right = filterMidnightWidgets(res.right)
      res.status = []
    }

    return res
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

  Component.onCompleted: {
    applyBarConfig()
    root.triggerFullscreenSync()
    var currentWs = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
    var initVisited = {}
    initVisited[currentWs] = Date.now()
    root.workspaceVisitedTimes = initVisited
    notifProc.running = true
    if (root.isMidnightDoll) {
      Hyprland.refreshToplevels()
      root.updateTopLeftWindowState()
    }
  }

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
    var target = region
    if (root.isMidnightDoll) {
      if (region === "status") target = "right"
      else if (region === "right") {
        target = "midnightRight"
        if (!Array.isArray(config.bar.layout.midnightRight) || config.bar.layout.midnightRight.length === 0) {
          config.bar.layout.midnightRight = [
            { id: "midnight-doll.sys-hud" },
            { id: "midnight-doll.visualizer" }
          ]
        }
      }
    }
    if (!Array.isArray(config.bar.layout[target])) config.bar.layout[target] = []

    return config.bar.layout[target]
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
    var screenPoint = root.windowScreenPoint(scenePoint, sourceWindow)
    return root.moduleDropAtScreen(screenPoint, sourceSlot)
  }

  function moduleDropAtScreen(screenPoint, sourceSlot) {
    if (!screenPoint || !sourceSlot) return null

    var screenH = (root.barDragScreen && root.barDragScreen.height) ? root.barDragScreen.height : 1080
    var inTopBarZone = (root.position === "top") && (screenPoint.y <= (root.barSize + 15))
    var inBottomBarZone = (root.position === "bottom") && (screenPoint.y >= (screenH - root.barSize - 15))
    var inHorizontalBarZone = inTopBarZone || inBottomBarZone
    var overLeftPanel = root.isMidnightDoll && (screenPoint.x <= 55) && !inHorizontalBarZone

    var candidates = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || slot === sourceSlot || !slot.visible || slot.width <= 0 || slot.height <= 0) continue

      var slotIsLeft = (slot.isLeftPanel === true) || (slot.region === "status")

      // sys-hud and visualizer are wide horizontal monitors; prevent dropping them onto the 35px left bar
      if (slotIsLeft && (sourceSlot.isSysHud || sourceSlot.isVisualizer)) continue

      if (overLeftPanel && !slotIsLeft) continue
      if (!overLeftPanel && slotIsLeft) continue

      var slotScreen = root.slotScreenPoint(slot)

      candidates.push({
        slot: slot,
        x: slotScreen.x,
        y: slotScreen.y,
        width: slot.width,
        height: slot.height
      })
    }

    if (candidates.length === 0) {
      for (var j = 0; j < moduleSlots.length; j++) {
        var fSlot = moduleSlots[j]
        if (!fSlot || fSlot === sourceSlot || !fSlot.visible || fSlot.width <= 0 || fSlot.height <= 0) continue
        var fSlotIsLeft = (fSlot.isLeftPanel === true) || (fSlot.region === "status")
        if (fSlotIsLeft && (sourceSlot.isSysHud || sourceSlot.isVisualizer)) continue
        var fScreen = root.slotScreenPoint(fSlot)
        candidates.push({
          slot: fSlot,
          x: fScreen.x,
          y: fScreen.y,
          width: fSlot.width,
          height: fSlot.height
        })
      }
    }

    if (candidates.length === 0) return null

    var isVertical = overLeftPanel || root.vertical
    return BarModel.nearestDropTarget(candidates, screenPoint, isVertical)
  }

  function visibleModuleSlot(region, name, sourceSlot) {
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || slot === sourceSlot || slot.region !== region || slot.moduleName !== name ||
          !slot.visible || slot.width <= 0 || slot.height <= 0) continue
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
    if (root.isMidnightDoll) {
      transparent = nextTransparent
    }
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
  ShellIpc {
    target: "omarchy.bar"

    // Start rather than restart: a probe already in flight was launched by the
    // directory watch after the flag flipped, so its answer is current, and
    // killing it here can swallow the result entirely.
    function syncHidden(): void {
      barHiddenProbe.running = true
    }
  }

  ShellIpc {
    target: "midnight-doll.bar"

    function toggleTransparency(): void {
      root.toggleTransparency()
    }

    function triggerWidget(id: string): string {
      for (var i = 0; i < moduleSlots.length; i++) {
        var slot = moduleSlots[i]
        if (slot && slot.moduleName === id) {
          var ai = slot.activeItem
          var hi = slot.hostItem
          var res = "slot: ai=" + (ai ? "yes" : "no") + " hi=" + (hi ? "yes" : "no")
          if (ai) {
            res += " ai.open=" + typeof ai.open + " ai.opened=" + ai.opened + " ai.visible=" + ai.visible
          }
          if (hi) {
            res += " hi.open=" + typeof hi.open + " hi.opened=" + hi.opened
          }
          if (ai && typeof ai.open === "function") {
            ai.open()
            res += " -> called ai.open()"
          } else if (ai && typeof ai.togglePanel === "function") {
            ai.togglePanel()
            res += " -> called ai.togglePanel()"
          } else if (hi && typeof hi.open === "function") {
            hi.open()
            res += " -> called hi.open()"
          }
          return res
        }
      }
      return "not found"
    }

    function closeWidget(id: string): string {
      for (var i = 0; i < moduleSlots.length; i++) {
        var slot = moduleSlots[i]
        if (slot && slot.moduleName === id) {
          var ai = slot.activeItem
          if (ai && typeof ai.close === "function") {
            ai.close()
            return "closed"
          }
        }
      }
      return "not found"
    }

    function toggleWidget(id: string): string {
      for (var i = 0; i < moduleSlots.length; i++) {
        var slot = moduleSlots[i]
        if (slot && slot.moduleName === id) {
          var ai = slot.activeItem
          if (ai) {
            if (ai.opened) {
              if (typeof ai.close === "function") ai.close()
              return "closed"
            } else {
              if (typeof ai.open === "function") ai.open()
              return "opened"
            }
          }
        }
      }
      return "not found"
    }

    function getBarGeometry(): string {
      return JSON.stringify(root.debugBarGeometry())
    }

    function getTransparencyState(): string {
      return "transparent=" + root.transparent + " requested=" + root.requestedTransparent
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
          color: Qt.rgba(1, 1, 1, 0.12)
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
          color: Qt.rgba(1, 1, 1, 0.12)
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

    visible: root.isMidnightDoll && (!root.barHidden || root.barAnimProgress > 0.001) && !remapGuardLeft.remapping
    exclusionMode: (root.isMidnightDoll && !root.barHidden) ? ExclusionMode.Normal : ExclusionMode.Ignore
    exclusiveZone: (root.isMidnightDoll && !root.barHidden) ? 36 : 0

    ScreenMoveRemap {
      id: remapGuardLeft
      window: leftBarWindow
    }

    margins {
      top: 0
      bottom: 0
      left: 0
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
    color: "transparent"
    surfaceFormat.opaque: false
    WlrLayershell.namespace: "omarchy-midnight-left-bar"
    WlrLayershell.layer: WlrLayer.Top

    mask: Region {
      Region {
        x: 0
        y: 0
        width: root.barHidden ? 0 : 36
        height: root.barHidden ? 0 : Math.max(leftBarWindow.height, modelData ? modelData.height : 1080)
      }
    }

    Item {
      id: leftBarContentHolder
      anchors.fill: parent
      transform: Translate {
        x: Math.round(-36 * (1.0 - root.barAnimProgress))
      }
      opacity: root.barAnimProgress

      Item {
        id: leftBarBody
        anchors {
          top: parent.top
          bottom: parent.bottom
          left: parent.left
        }
        width: 36
        opacity: root.transparent ? 0.0 : 1.0
        Behavior on opacity { NumberAnimation { duration: 380; easing.type: Easing.InOutCubic } }

        Rectangle {
          id: leftBarBackground
          anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
          }
          width: 35
          color: "#010101"
        }

        Rectangle {
          id: leftBarRightBorder
          anchors {
            top: parent.top
            topMargin: (root.isMidnightDoll && root.position === "top") ? (root.midnightCornerRadius - 1) : 0
            bottomMargin: (root.isMidnightDoll && root.position === "bottom") ? (root.midnightCornerRadius - 1) : 0
            bottom: parent.bottom
            right: parent.right
          }
          width: 1
          color: Color.accent
        }
      }

      MouseArea {
        id: leftBarMouseArea
        anchors {
          top: parent.top
          bottom: parent.bottom
          left: parent.left
        }
        width: 36
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) {
            root.midnightShortcutEditorOpen = !root.midnightShortcutEditorOpen
          }
        }
        onDoubleClicked: function(mouse) {
          if (mouse.button === Qt.LeftButton) {
            root.toggleTransparency()
            mouse.accepted = true
          }
        }
      }

      Column {
        id: launcherColumn
        anchors {
          top: parent.top
          topMargin: 6
          left: parent.left
        }
        width: 35
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
          bottomMargin: (root.isMidnightDoll && root.position === "bottom") ? (root.barSize + 6) : 6
          left: parent.left
        }
        width: 35
        spacing: 2

        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          width: 18
          height: 1
          color: Qt.rgba(1, 1, 1, 0.2)
        }

        Column {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 0

          Repeater {
            model: root.layoutEntries("status")

            ModuleSlot {
              required property var modelData
              entry: modelData
              region: "status"
              isLeftPanel: true
            }
          }
        }
      }

    }

    PopupWindow {
      id: leftTooltipWindow

      visible: root.tooltipShown && root.tooltipTarget !== null && root.tooltipText !== "" && root.targetBelongsToWindow(root.tooltipTarget, leftBarWindow)
      color: "transparent"
      implicitWidth: Math.ceil(leftTooltipBubble.implicitWidth)
      implicitHeight: Math.ceil(leftTooltipBubble.implicitHeight)

      anchor {
        id: leftTooltipAnchor
        window: leftBarWindow
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.width: 1
        rect.height: 1

        onAnchoring: {
          var target = root.tooltipTarget
          if (!root.targetBelongsToWindow(target, leftBarWindow)) return

          var popupWidth = leftTooltipWindow.implicitWidth
          var popupHeight = leftTooltipWindow.implicitHeight
          var localX = target.width + 6
          var localY = target.height / 2 - popupHeight / 2

          var point = leftBarWindow.contentItem.mapFromItem(target, localX, localY)
          leftTooltipAnchor.rect.x = Math.round(point.x)
          leftTooltipAnchor.rect.y = Math.round(point.y)
        }
      }

      BorderSurface {
        id: leftTooltipBubble
        implicitWidth: leftTooltipLabel.implicitWidth + 20
        implicitHeight: leftTooltipLabel.implicitHeight + 14
        color: Color.tooltip.background
        borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
        radius: Style.cornerRadius

        Text {
          id: leftTooltipLabel
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

    // Unmap the layer surface while hidden so that revealing it (via
    // Super+Shift+Space) remaps a fresh surface that draws over active
    // fullscreen windows in Hyprland, matching the sidebar behavior.
    visible: (!root.barHidden || root.barAnimProgress > 0.001) && !remapGuard.remapping
    exclusionMode: root.barHidden ? ExclusionMode.Ignore : ExclusionMode.Normal
    exclusiveZone: root.barHidden ? 0 : root.barSize

    ScreenMoveRemap {
      id: remapGuard
      window: barWindow
    }

    margins {
      top: 0
      bottom: 0
      left: 0
      right: 0
    }

    anchors {
      top: root.position === "top" || root.vertical
      bottom: root.position === "bottom" || root.vertical
      left: root.position === "left" || !root.vertical
      right: root.position === "right" || !root.vertical
    }

    implicitWidth: root.vertical ? root.barSize : 0
    implicitHeight: (root.isMidnightDoll && root.position === "top") ? (root.barSize + root.midnightCornerRadius + 6) : (root.vertical ? 0 : root.barSize)
    color: "transparent"
    surfaceFormat.opaque: false
    WlrLayershell.namespace: "omarchy-bar"
    WlrLayershell.layer: WlrLayer.Top

    mask: Region {
      Region {
        x: 0
        y: root.position === "bottom" ? (barWindow.height - root.barSize) : 0
        width: root.barHidden ? 0 : Math.max(barWindow.width, modelData ? modelData.width : 1920)
        height: root.barHidden ? 0 : root.barSize
      }
      Region {
        item: (root.isMidnightDoll && !root.transparent && root.position === "top" && !root.barHidden) ? midnightCornerFillet : null
      }
      Region {
        item: (root.isMidnightDoll && root.position === "top" && midnightWorkspacesChamferStrip.visible && !root.barHidden) ? midnightWorkspacesChamferStrip : null
      }
    }

    Item {
      id: barContentHolder
      anchors.fill: parent
      transform: Translate {
        y: Math.round(-(root.barSize + (root.isMidnightDoll ? (root.midnightCornerRadius + 6) : 0)) * (1.0 - root.barAnimProgress))
      }
      opacity: root.barAnimProgress

      Rectangle {
        id: barBackgroundRect
      anchors.top: root.position === "bottom" ? undefined : parent.top
      anchors.bottom: root.position === "bottom" ? parent.bottom : undefined
      anchors.left: parent.left
      anchors.right: parent.right
      height: root.barSize
      color: root.isMidnightDoll ? "#010101" : root.background
      opacity: root.transparent ? 0.0 : 1.0
      Behavior on opacity { NumberAnimation { duration: 380; easing.type: Easing.InOutCubic } }
      z: -1
    }

    Item {
      id: midnightCornerFillet
      x: 34
      y: root.barSize
      width: root.midnightCornerRadius + 6
      height: root.midnightCornerRadius + 6
      visible: root.isMidnightDoll && !root.barHidden && root.position === "top"
    }

    Item {
      id: midnightWorkspacesChamferStrip
      x: 34
      y: root.barSize
      width: 400
      height: 16
      visible: root.isMidnightDoll && !root.barHidden && root.position === "top" && root.hasUrgentWorkspaceNotification
    }

    Shape {
      id: midnightBorderShape
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      height: root.barSize + root.midnightCornerRadius + 6
      visible: root.isMidnightDoll && !root.barHidden && root.position === "top"
      opacity: root.transparent ? 0.0 : 1.0
      Behavior on opacity { NumberAnimation { duration: 380; easing.type: Easing.InOutCubic } }
      asynchronous: false
      preferredRendererType: Shape.CurveRenderer
      z: 999

      ShapePath {
        strokeWidth: 0
        strokeColor: "transparent"
        fillColor: "#010101"

        startX: 34
        startY: root.barSize
        PathLine { x: 35.5 + root.midnightCornerRadius; y: root.barSize }
        PathAngleArc {
          centerX: 35.5 + root.midnightCornerRadius
          centerY: root.barSize - 0.5 + root.midnightCornerRadius
          radiusX: root.midnightCornerRadius
          radiusY: root.midnightCornerRadius
          startAngle: -90
          sweepAngle: -90
        }
        PathLine { x: 34; y: root.barSize + root.midnightCornerRadius }
        PathLine { x: 34; y: root.barSize }
      }

      // Corner fillet outline: adapts to active window border width when top-left window is active
      ShapePath {
        strokeWidth: root.cornerStrokeWidth
        strokeColor: Color.accent
        fillColor: "transparent"
        joinStyle: ShapePath.RoundJoin
        capStyle: ShapePath.FlatCap

        startX: 35.5 + root.cornerStrokeOffset
        startY: root.barSize - 0.5 + root.midnightCornerRadius

        PathAngleArc {
          centerX: 35.5 + root.midnightCornerRadius
          centerY: root.barSize - 0.5 + root.midnightCornerRadius
          radiusX: root.midnightCornerRadius - root.cornerStrokeOffset
          radiusY: root.midnightCornerRadius - root.cornerStrokeOffset
          startAngle: -180
          sweepAngle: 90
        }
      }

      // Top bar bottom border: decoupled from fillet and always 1px
      ShapePath {
        strokeWidth: 1.0
        strokeColor: Color.accent
        fillColor: "transparent"
        joinStyle: ShapePath.MiterJoin
        capStyle: ShapePath.FlatCap

        startX: 35.5 + root.midnightCornerRadius
        startY: root.barSize - 0.5
        PathLine { x: barWindow.width; y: root.barSize - 0.5 }
      }
    }

    Shape {
      id: midnightBottomBorderShape
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      height: root.barSize
      visible: root.isMidnightDoll && !root.barHidden && root.position === "bottom"
      opacity: root.transparent ? 0.0 : 1.0
      Behavior on opacity { NumberAnimation { duration: 380; easing.type: Easing.InOutCubic } }
      asynchronous: false
      preferredRendererType: Shape.CurveRenderer
      z: 999

      ShapePath {
        strokeWidth: 1.0
        strokeColor: Color.accent
        fillColor: "transparent"
        joinStyle: ShapePath.RoundJoin
        capStyle: ShapePath.FlatCap

        startX: 35.5
        startY: 0.5
        PathLine { x: barWindow.width; y: 0.5 }
      }
    }

    Loader {
      id: barLoader
      anchors.top: root.position === "bottom" ? undefined : parent.top
      anchors.bottom: root.position === "bottom" ? parent.bottom : undefined
      anchors.left: parent.left
      anchors.right: parent.right
      height: root.barSize
      sourceComponent: root.vertical ? verticalBar : horizontalBar
      z: 1000

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

        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          LeftModules {}

          FullscreenModeBadge {}
        }

        Row {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: 6

          RightModules {}
        }
      }
    }

    Component {
      id: verticalBar

      Item {
        anchors.fill: parent

        CenterModules { anchors.fill: parent }

        Column {
          anchors.top: parent.top
          anchors.topMargin: Style.space(8)
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(8)

          LeftModules {}

          FullscreenModeBadge {}
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

  component FullscreenModeBadge: Rectangle {
    id: badgeRoot
    visible: root.fullscreenModeActive
    height: 20
    width: visible ? (badgeRow.implicitWidth + 14) : 0
    radius: 3
    color: badgeMouse.containsMouse ? Qt.rgba(1, 0.32, 0.77, 0.28) : Qt.rgba(1, 0.32, 0.77, 0.14)
    border.color: Color.accent
    border.width: 1
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.InOutCubic } }

    Row {
      id: badgeRow
      anchors.centerIn: parent
      spacing: 5

      Text {
        text: "󰊓"
        font.family: root.fontFamily
        font.pixelSize: 11
        color: Color.accent
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        text: "FULLSCREEN"
        font.family: root.fontFamily
        font.pixelSize: 9
        font.bold: true
        font.letterSpacing: 1.0
        color: Color.accent
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      id: badgeMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.run("/home/punch/.local/bin/omarchy-fullscreen-bar-sync --toggle-window")
    }

    HoverHandler {
      onHoveredChanged: {
        if (hovered) {
          root.showTooltip(badgeRoot, "Fullscreen Mode Active (Click to restore window)")
        } else {
          root.hideTooltip(badgeRoot)
        }
      }
    }
  }

  component RightModules: ModuleList {
    entries: root.layoutEntries("right")
    region: "right"
    visible: true
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

          ModuleSlot {
            required property var modelData
            entry: modelData
            region: moduleListRoot.region
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

          ModuleSlot {
            required property var modelData
            entry: modelData
            region: moduleListRoot.region
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
    readonly property bool isSysHud: root.isMidnightDoll && (moduleName === "midnight-doll.sys-hud" || moduleName === "midnight-doll.system-hud" || moduleName === "midnight-doll.hud")
    readonly property bool isVisualizer: root.isMidnightDoll && (moduleName === "midnight-doll.visualizer" || moduleName === "midnight-doll.cava")
    readonly property bool isBlockedInOtherTheme: !root.isMidnightDoll && (root.isMidnightOnlyWidget(moduleName) || isSysHud || isVisualizer)
    readonly property bool isAgents: moduleName === "omarchy.agents" || moduleName.endsWith(".agents")
    readonly property bool isMenu: root.isMidnightDoll && (moduleName === "omarchy.menu" || moduleName === "omarchy-menu")
    readonly property bool isWorkspaces: root.isMidnightDoll && (moduleName === "omarchy.workspaces" || moduleName === "omarchy-workspaces")
    readonly property bool isClock: root.isMidnightDoll && (moduleName === "omarchy.clock" || moduleName === "omarchy-clock")
    readonly property bool qmlCustom: customType === "qml"
    readonly property bool commandCustom: customType === "command"

    // Re-evaluate when the registry mutates (Component reference changes,
    // plugin enabled/disabled, etc.). Reading the `widgets` property creates
    // the binding dependency — the wrapped function call alone wouldn't.
    readonly property var registryComponent: {
      if (isBlockedInOtherTheme) return null
      if (isMenu) return null
      var w = root.barWidgetRegistry.widgets
      if (customType) return null
      var registryName = root.canonicalWidgetId(moduleName)
      if (w[registryName]) return w[registryName].component
      if (moduleName.endsWith(".agents") || moduleName === "omarchy.agents") {
        for (var k in w) {
          if ((k.endsWith(".agents") || k === "omarchy.agents") && w[k] && w[k].component)
            return w[k].component
        }
      }
      return null
    }
    readonly property bool registered: registryComponent !== null
    readonly property var activeItem: {
      if (isBlockedInOtherTheme) return null
      if (isMenu && menuLoader.item) return menuLoader.item
      if (isWorkspaces && workspacesOverlayLoader.item) return workspacesOverlayLoader.item
      if (isClock && clockOverlayLoader.item) return clockOverlayLoader.item
      if (registered) return registryLoader.item
      if (isAgents && agentsFallbackLoader.item) return agentsFallbackLoader.item
      if (isSysHud && sysHudLoader.item) return sysHudLoader.item
      if (isVisualizer && visualizerLoader.item) return visualizerLoader.item
      if (qmlCustom) return qmlLoader.item
      return componentLoader.item
    }
    readonly property bool hovered: moduleHover.hovered
    readonly property bool dragSource: root.barDragSource === slot
    readonly property var hostItem: registryLoader ? registryLoader.item : null
    readonly property bool panelOpen: root.activePopout === slot.activeItem || (hostItem && root.activePopout === hostItem)
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
    implicitWidth: (!isBlockedInOtherTheme && activeItem && activeItem.visible) ? ((root.vertical || isLeftPanel) ? (isLeftPanel ? 35 : root.barSize) : activeItem.implicitWidth) : 0
    implicitHeight: (!isBlockedInOtherTheme && activeItem && activeItem.visible) ? activeItem.implicitHeight : 0
    width: implicitWidth
    height: implicitHeight
    visible: !isBlockedInOtherTheme
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
      active: !slot.isBlockedInOtherTheme && !slot.qmlCustom && !slot.registered
      sourceComponent: slot.isBlockedInOtherTheme ? emptyModuleComponent : (slot.commandCustom ? customCommandModuleComponent : emptyModuleComponent)
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Loader {
      id: registryLoader
      active: !slot.isBlockedInOtherTheme && slot.registered
      sourceComponent: (!slot.isBlockedInOtherTheme && slot.registered) ? slot.registryComponent : null
      anchors.fill: parent
      visible: true
      opacity: (slot.isWorkspaces || slot.isClock) ? 0 : (slot.dragSource ? 0.22 : 1.0)
      enabled: !slot.isWorkspaces && !slot.isClock
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Loader {
      id: qmlLoader
      active: !slot.isBlockedInOtherTheme && slot.qmlCustom
      source: (!slot.isBlockedInOtherTheme && slot.qmlCustom) ? root.customModuleSource(slot.entry) : ""
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Loader {
      id: sysHudLoader
      active: root.isMidnightDoll && slot.isSysHud && !slot.registered
      sourceComponent: root.isMidnightDoll ? midnightSystemHudComponent : null
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Loader {
      id: visualizerLoader
      active: root.isMidnightDoll && slot.isVisualizer && !slot.registered
      sourceComponent: root.isMidnightDoll ? midnightVisualizerComponent : null
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Loader {
      id: agentsFallbackLoader
      active: slot.isAgents && !slot.registered
      source: {
        if (!slot.isAgents || slot.registered) return ""
        var targetId = slot.moduleName || "omarchy.agents"
        if (targetId.indexOf(".") !== -1 && targetId !== "omarchy.agents") {
          return Qt.resolvedUrl("file://" + root.home + "/.config/omarchy/plugins/" + targetId + "/Panel.qml")
        }
        return Qt.resolvedUrl("file:///usr/share/omarchy/shell/plugins/agents/Panel.qml")
      }
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Loader {
      id: menuLoader
      active: slot.isMenu
      sourceComponent: midnightMenuComponent
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Loader {
      id: workspacesOverlayLoader
      active: slot.isWorkspaces
      sourceComponent: midnightWorkspacesOverlayComponent
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Loader {
      id: clockOverlayLoader
      active: slot.isClock
      sourceComponent: midnightClockOverlayComponent
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
      width: (root.vertical || slot.isLeftPanel) ? Style.space(2) : slot.panelIndicatorExtent
      height: (root.vertical || slot.isLeftPanel) ? slot.panelIndicatorExtent : Style.space(2)
      // The mark sits on the module's inner edge — the one facing the
      // desktop — so it underlines a top bar, overlines a bottom one, and
      // points inward from a left or right one. It reads as pointing at the
      // panel that opens on that side.
      x: (root.vertical || slot.isLeftPanel)
        ? ((root.position === "left" || slot.isLeftPanel) ? parent.width - width - inset : inset)
        : Math.round((parent.width - width) / 2)
      y: (root.vertical || slot.isLeftPanel)
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
      if (typeof root === "undefined" || !root) return
      var barCtx = (slot.isLeftPanel ? (root.leftBarContext || root) : root)
      var target = activeItem
      if (target) {
        if ("bar" in target) target.bar = barCtx
        if ("moduleName" in target) target.moduleName = moduleName
        if ("settings" in target) target.settings = moduleSettings
      }
      if (hostItem && hostItem !== target) {
        if ("bar" in hostItem) hostItem.bar = barCtx
        if ("moduleName" in hostItem) hostItem.moduleName = moduleName
        if ("settings" in hostItem) hostItem.settings = moduleSettings
      }
    }

    Component {
      id: customCommandModuleComponent
      CustomCommandModule { entry: slot.entry }
    }

    Component {
      id: midnightSystemHudComponent
      MidnightSystemHud {}
    }

    Component {
      id: midnightVisualizerComponent
      MidnightCavaVisualizer {}
    }

    Component {
      id: midnightClockOverlayComponent

      Item {
        id: clockOverlayRoot
        property var bar: (slot.isLeftPanel ? (root.leftBarContext || root) : root)
        readonly property var hostItem: slot.hostItem
        readonly property bool opened: hostItem ? hostItem.opened === true : false
        readonly property bool isVertical: root.vertical || slot.isLeftPanel
        readonly property real openPanelIndicatorWidth: isVertical ? Style.bar.iconSlot : Math.max(20, clockContentRow.implicitWidth + 8)
        readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))
        readonly property bool popoutSwitchClosing: hostItem ? hostItem.popoutSwitchClosing === true : false

        function open() {
          if (hostItem && typeof hostItem.open === "function") hostItem.open()
        }
        function close() {
          if (hostItem && typeof hostItem.close === "function") hostItem.close()
        }
        function togglePanel() {
          if (hostItem && typeof hostItem.togglePanel === "function") hostItem.togglePanel()
        }
        function toggleWeekStart() {
          if (hostItem && typeof hostItem.toggleWeekStart === "function") hostItem.toggleWeekStart()
        }
        function closeForPopoutSwitch() {
          if (hostItem && typeof hostItem.closeForPopoutSwitch === "function") hostItem.closeForPopoutSwitch()
        }

        // Settings resolution from hostItem or slot
        property var clockSettings: (hostItem && hostItem.settings) ? hostItem.settings : (slot.moduleSettings || ({}))

        property string dateFormat: {
          if (clockSettings && clockSettings.dateFormat) return clockSettings.dateFormat
          return "full"
        }

        property bool is12h: {
          if (clockSettings && clockSettings.timeFormat) return clockSettings.timeFormat === "12h"
          if (clockSettings && clockSettings.format) {
            var f = String(clockSettings.format)
            if (f.indexOf("AP") !== -1 || f.indexOf("ap") !== -1 || f.indexOf("h:") !== -1) return true
          }
          return false
        }

        property bool precision: {
          if (clockSettings && clockSettings.precision !== undefined) return clockSettings.precision === true
          if (clockSettings && clockSettings.format) {
            if (String(clockSettings.format).indexOf(":ss") !== -1) return true
          }
          return false
        }

        function saveSettings(newDateFormat, newIs12h, newPrecision) {
          var entry = { id: "omarchy.clock" }
          if (clockSettings) {
            for (var k in clockSettings) if (k !== "id") entry[k] = clockSettings[k]
          }
          entry.dateFormat = newDateFormat
          entry.timeFormat = newIs12h ? "12h" : "24h"
          entry.precision = newPrecision

          // Keep format synced with canonical omarchy.clock presets
          if (newIs12h) {
            entry.format = newPrecision ? "dddd h:mm:ss AP" : "dddd h:mm AP"
            entry.verticalFormat = "h\n—\nmm\nAP"
          } else {
            entry.format = newPrecision ? "dddd HH:mm:ss" : "dddd HH:mm"
            entry.verticalFormat = "HH\n—\nmm"
          }

          if (hostItem) hostItem.settings = entry
          if (root.shell && typeof root.shell.updateEntryInline === "function") {
            root.shell.updateEntryInline("omarchy.clock", entry)
          }
        }

        function cycleDateFormat() {
          var next = "full"
          if (dateFormat === "full") next = "compact"
          else if (dateFormat === "compact") next = "iso"
          else next = "full"
          saveSettings(next, is12h, precision)
        }

        function toggleTimeFormat() {
          saveSettings(dateFormat, !is12h, precision)
        }

        function togglePrecision() {
          saveSettings(dateFormat, is12h, !precision)
        }

        function dateFormatName() {
          if (dateFormat === "compact") return "Compact"
          if (dateFormat === "iso") return "YYYY-MM-DD"
          return "Full"
        }

        property date currentDate: new Date()
        Timer {
          interval: clockOverlayRoot.precision ? 250 : 1000
          running: true
          repeat: true
          onTriggered: clockOverlayRoot.currentDate = new Date()
        }

        readonly property string dateString: {
          var d = clockOverlayRoot.currentDate
          var months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
          var days = ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"]
          var shortDays = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

          var mon = months[d.getMonth()]
          var dayNum = String(d.getDate()).padStart(2, "0")
          var yr = d.getFullYear()
          var dayName = days[d.getDay()]
          var shortDayName = shortDays[d.getDay()]

          if (dateFormat === "compact") {
            return shortDayName + " " + dayNum + " " + mon
          } else if (dateFormat === "iso") {
            var mNum = String(d.getMonth() + 1).padStart(2, "0")
            return yr + "-" + mNum + "-" + dayNum
          } else {
            return mon + " " + dayNum + " " + yr + " / " + dayName
          }
        }

        readonly property string timeString: {
          var d = clockOverlayRoot.currentDate
          var h = d.getHours()
          var m = String(d.getMinutes()).padStart(2, "0")
          var s = String(d.getSeconds()).padStart(2, "0")

          if (is12h) {
            var ap = h >= 12 ? "PM" : "AM"
            var h12 = h % 12
            if (h12 === 0) h12 = 12
            var hStr = String(h12)
            if (precision) {
              return hStr + ":" + m + ":" + s + " " + ap
            } else {
              return hStr + ":" + m + " " + ap
            }
          } else {
            var hh = String(h).padStart(2, "0")
            if (precision) {
              return hh + m + s
            } else {
              return hh + m
            }
          }
        }

        readonly property var verticalLines: {
          var d = clockOverlayRoot.currentDate
          var h = d.getHours()
          var m = String(d.getMinutes()).padStart(2, "0")
          var s = String(d.getSeconds()).padStart(2, "0")

          if (is12h) {
            var ap = h >= 12 ? "PM" : "AM"
            var h12 = h % 12
            if (h12 === 0) h12 = 12
            if (precision) {
              return [String(h12), m, s, ap]
            } else {
              return [String(h12), "—", m, ap]
            }
          } else {
            var hh = String(h).padStart(2, "0")
            if (precision) {
              return [hh, m, s]
            } else {
              return [hh, "—", m]
            }
          }
        }

        implicitWidth: isVertical ? root.barSize : (clockContentRow.implicitWidth + 18)
        implicitHeight: isVertical ? (verticalLines.length * Style.bar.iconSlot) : root.barSize

        Item {
          id: horizontalContainer
          visible: !clockOverlayRoot.isVertical
          anchors.fill: parent

          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onEntered: root.showTooltip(horizontalContainer, "Left-click: Calendar · Middle-click: Timezone")
            onExited: root.hideTooltip(horizontalContainer)
            onClicked: function(mouse) {
              if (mouse.button === Qt.MiddleButton) {
                root.run("omarchy-menu-timezone")
              } else {
                clockOverlayRoot.togglePanel()
              }
            }
          }

          Row {
            id: clockContentRow
            anchors.centerIn: parent
            spacing: 5

            Text {
              text: "["
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              renderType: Text.NativeRendering
              anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
              id: dateBox
              height: 22
              width: dateLabel.implicitWidth + 8
              radius: 3
              color: dateMouse.containsMouse ? Qt.rgba(1, 0.32, 0.77, 0.16) : "transparent"
              anchors.verticalCenter: parent.verticalCenter

              Behavior on color { ColorAnimation { duration: 120 } }

              Text {
                id: dateLabel
                anchors.centerIn: parent
                text: clockOverlayRoot.dateString
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                renderType: Text.NativeRendering
              }

              MouseArea {
                id: dateMouse
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: {
                  root.showTooltip(dateBox, "Date (" + clockOverlayRoot.dateFormatName() + ") · Right-click: Cycle format (Full / Compact / YYYY-MM-DD)")
                }
                onExited: root.hideTooltip(dateBox)
                onClicked: function(mouse) {
                  if (mouse.button === Qt.RightButton) {
                    clockOverlayRoot.cycleDateFormat()
                  } else if (mouse.button === Qt.MiddleButton) {
                    root.run("omarchy-menu-timezone")
                  } else {
                    clockOverlayRoot.togglePanel()
                  }
                }
              }
            }

            Text {
              text: "/"
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              renderType: Text.NativeRendering
              anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
              id: timeBox
              height: 22
              width: timeLabel.implicitWidth + 8
              radius: 3
              color: timeMouse.containsMouse ? Qt.rgba(1, 0.32, 0.77, 0.16) : "transparent"
              anchors.verticalCenter: parent.verticalCenter

              Behavior on color { ColorAnimation { duration: 120 } }

              Text {
                id: timeLabel
                anchors.centerIn: parent
                text: clockOverlayRoot.timeString
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                renderType: Text.NativeRendering
              }

              MouseArea {
                id: timeMouse
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: {
                  var modeStr = clockOverlayRoot.is12h ? "12-hr" : "24-hr"
                  var secStr = clockOverlayRoot.precision ? "Seconds: ON" : "Seconds: OFF"
                  root.showTooltip(timeBox, "Time (" + modeStr + ") · Right-click: Swap 12h/24h · Middle-click / Double-click: Toggle seconds (" + secStr + ")")
                }
                onExited: root.hideTooltip(timeBox)
                onDoubleClicked: function(mouse) {
                  if (mouse.button === Qt.LeftButton) {
                    clockOverlayRoot.togglePrecision()
                  }
                }
                onClicked: function(mouse) {
                  if (mouse.button === Qt.RightButton) {
                    clockOverlayRoot.toggleTimeFormat()
                  } else if (mouse.button === Qt.MiddleButton) {
                    clockOverlayRoot.togglePrecision()
                  } else {
                    clockOverlayRoot.togglePanel()
                  }
                }
                onWheel: function(wheel) {
                  clockOverlayRoot.togglePrecision()
                }
              }
            }

            Text {
              text: "]"
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              renderType: Text.NativeRendering
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }

        Item {
          id: verticalContent
          visible: clockOverlayRoot.isVertical
          anchors.fill: parent

          MouseArea {
            id: vertMouse
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: {
              var modeStr = clockOverlayRoot.is12h ? "12-hr" : "24-hr"
              var secStr = clockOverlayRoot.precision ? "Seconds: ON" : "Seconds: OFF"
              root.showTooltip(verticalContent, "Left-click: Calendar · Right-click: Swap 12h/24h (" + modeStr + ") · Middle-click / Double-click: Toggle seconds (" + secStr + ")")
            }
            onExited: root.hideTooltip(verticalContent)
            onClicked: function(mouse) {
              if (mouse.button === Qt.RightButton) {
                clockOverlayRoot.toggleTimeFormat()
              } else if (mouse.button === Qt.MiddleButton) {
                clockOverlayRoot.togglePrecision()
              } else {
                clockOverlayRoot.togglePanel()
              }
            }
            onDoubleClicked: function(mouse) {
              if (mouse.button === Qt.LeftButton) {
                clockOverlayRoot.togglePrecision()
              }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: 0

            Repeater {
              model: clockOverlayRoot.verticalLines

              Text {
                required property string modelData
                anchors.horizontalCenter: parent.horizontalCenter
                text: modelData
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                renderType: Text.NativeRendering
              }
            }
          }
        }
      }
    }

    Component {
      id: midnightWorkspacesOverlayComponent

      Item {
        id: overlayRoot
        property var bar: (slot.isLeftPanel ? (root.leftBarContext || root) : root)
        readonly property var hostItem: registryLoader ? registryLoader.item : null
        readonly property var workspaceIds: {
          if (hostItem && typeof hostItem.workspaceIds === "function") {
            return hostItem.workspaceIds()
          }
          var ids = [1, 2, 3, 4, 5]
          var values = Hyprland.workspaces ? Hyprland.workspaces.values : []
          for (var i = 0; i < values.length; i++) {
            var id = values[i].id
            if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
          }
          ids.sort(function(a, b) { return a - b })
          return ids
        }

        readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)
        implicitWidth: grid.implicitWidth + trailingGap
        implicitHeight: grid.implicitHeight

        GridLayout {
          id: grid
          anchors.fill: parent
          anchors.rightMargin: overlayRoot.trailingGap
          columns: root.vertical ? 1 : overlayRoot.workspaceIds.length
          columnSpacing: 2
          rowSpacing: root.vertical ? Style.space(2) : 0

          Repeater {
            model: overlayRoot.workspaceIds

            Item {
              required property int modelData

              readonly property var workspace: {
                if (hostItem && typeof hostItem.workspaceById === "function") {
                  return hostItem.workspaceById(modelData)
                }
                var values = Hyprland.workspaces ? Hyprland.workspaces.values : []
                for (var i = 0; i < values.length; i++) {
                  if (values[i].id === modelData) return values[i]
                }
                return null
              }
              readonly property bool occupied: workspace !== null && workspace.toplevels && workspace.toplevels.values.length > 0
              readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
              readonly property int notificationCount: {
                var _ = root.urgentTick
                return root.workspaceNotificationCount(modelData, workspace)
              }
              readonly property bool hasNotification: notificationCount > 0

              implicitWidth: btn.labelWidth + 8
              implicitHeight: root.barSize

              // Accent background fill for focused workspace
              Rectangle {
                visible: focused
                anchors.centerIn: parent
                width: parent.width
                height: root.barSize - 6
                color: Color.accent
                radius: 0
              }

              // Cyber chamfer notification tab hanging just below the bar border (visible in normal non-transparent mode)
              Item {
                id: chamferTab
                visible: hasNotification && !focused && !root.vertical && !root.transparent
                z: 1000
                anchors.top: parent.bottom
                anchors.topMargin: -1
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(20, chamferCountText.implicitWidth + 10)
                height: 10

                readonly property real chamfer: 3.5

                Shape {
                  anchors.fill: parent
                  asynchronous: false
                  preferredRendererType: Shape.CurveRenderer

                  // 1. Dark fill matching the bar background, extending slightly upward to seamlessly mask the bar's bottom border
                  ShapePath {
                    strokeWidth: 0
                    strokeColor: "transparent"
                    fillColor: "#010101"

                    startX: 0
                    startY: -2
                    PathLine { x: chamferTab.width; y: -2 }
                    PathLine { x: chamferTab.width; y: 0.5 }
                    PathLine { x: chamferTab.width - chamferTab.chamfer; y: chamferTab.height }
                    PathLine { x: chamferTab.chamfer; y: chamferTab.height }
                    PathLine { x: 0; y: 0.5 }
                    PathLine { x: 0; y: -2 }
                  }

                  // 2. Accent border outline on angled sides and bottom (top remains open to flow seamlessly from the bar)
                  ShapePath {
                    strokeWidth: 1.0
                    strokeColor: Color.accent
                    fillColor: "transparent"
                    capStyle: ShapePath.FlatCap
                    joinStyle: ShapePath.MiterJoin

                    startX: 0
                    startY: 0.5
                    PathLine { x: chamferTab.chamfer; y: chamferTab.height }
                    PathLine { x: chamferTab.width - chamferTab.chamfer; y: chamferTab.height }
                    PathLine { x: chamferTab.width; y: 0.5 }
                  }
                }

                Text {
                  id: chamferCountText
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.verticalCenterOffset: 0.5
                  text: notificationCount > 99 ? "99+" : String(notificationCount)
                  font.family: root.fontFamily
                  font.pixelSize: 8
                  font.bold: true
                  color: Color.accent
                  renderType: Text.NativeRendering
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.markWorkspaceVisited(modelData)
                    if (hostItem && typeof hostItem.focusWorkspace === "function") {
                      hostItem.focusWorkspace(modelData)
                    } else {
                      root.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + modelData + "\" })"))
                    }
                  }
                }

                HoverHandler {
                  onHoveredChanged: {
                    if (hovered && root.bar) {
                      root.bar.showTooltip(chamferTab, "Workspace " + modelData + " (" + notificationCount + (notificationCount === 1 ? " notification)" : " notifications)") + " — click to focus")
                    } else if (!hovered && root.bar) {
                      root.bar.hideTooltip(chamferTab)
                    }
                  }
                }
              }

              // Notification count badge directly under workspace with a small 1-px bordered circle (visible when bar background is transparent)
              Rectangle {
                id: circleBadge
                visible: hasNotification && !focused && !root.vertical && root.transparent
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.bottom
                anchors.topMargin: 1
                height: 12
                width: Math.max(height, circleCountText.implicitWidth + 6)
                radius: height / 2
                color: "#010101"
                border.width: 1
                border.color: Color.accent
                z: 1000

                Text {
                  id: circleCountText
                  anchors.centerIn: parent
                  text: notificationCount > 99 ? "99+" : String(notificationCount)
                  font.family: root.fontFamily
                  font.pixelSize: 8
                  font.bold: true
                  color: Color.accent
                  renderType: Text.NativeRendering
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.markWorkspaceVisited(modelData)
                    if (hostItem && typeof hostItem.focusWorkspace === "function") {
                      hostItem.focusWorkspace(modelData)
                    } else {
                      root.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + modelData + "\" })"))
                    }
                  }
                }

                HoverHandler {
                  onHoveredChanged: {
                    if (hovered && root.bar) {
                      root.bar.showTooltip(circleBadge, "Workspace " + modelData + " (" + notificationCount + (notificationCount === 1 ? " notification)" : " notifications)") + " — click to focus")
                    } else if (!hovered && root.bar) {
                      root.bar.hideTooltip(circleBadge)
                    }
                  }
                }
              }

              WidgetButton {
                id: btn
                anchors.fill: parent
                bar: overlayRoot.bar
                text: "[" + (modelData === 10 ? "0" : String(modelData)) + "]"
                foreground: focused ? "#010101" : Color.accent
                active: false
                useActiveColor: false
                fontFamily: root.fontFamily
                opacity: 1.0
                horizontalMargin: 2
                verticalPadding: 2
                fixedWidth: -1
                fixedHeight: root.barSize
                onPressed: function() {
                  root.markWorkspaceVisited(modelData)
                  if (hostItem && typeof hostItem.focusWorkspace === "function") {
                    hostItem.focusWorkspace(modelData)
                  } else {
                    root.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + modelData + "\" })"))
                  }
                }
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
    }

    Component {
      id: midnightMenuComponent

      Item {
        id: menuContainer
        implicitHeight: root.barSize
        implicitWidth: menuRow.implicitWidth
        height: root.barSize
        width: implicitWidth

        Row {
          id: menuRow
          spacing: 0
          anchors.verticalCenter: parent.verticalCenter
          height: root.barSize

        WidgetButton {
          id: menuBtn
          bar: root
          text: root.menuIcon
          fontFamily: "JetBrainsMono Nerd Font"
          fontSize: 18
          foreground: Color.accent
          horizontalMargin: 6
          fixedWidth: (root.vertical || slot.isLeftPanel) ? root.barSize : 28
          fixedHeight: (root.vertical || slot.isLeftPanel) ? 28 : root.barSize
          onPressed: function(button) {
            if (button === Qt.RightButton) root.run("xdg-terminal-exec")
            else root.run("omarchy-shell shell toggle omarchy.menu '{\"menu\":\"root\"}'")
          }
        }

        Row {
          id: hudTitleRow
          visible: !root.vertical && !slot.isLeftPanel && slot.region === "left"
          spacing: 0
          anchors.verticalCenter: parent.verticalCenter
          leftPadding: 6
          rightPadding: 8

          Text {
            visible: root.hudTitle !== ""
            text: root.hudTitle
            font.family: root.fontFamily
            font.bold: true
            font.pixelSize: 12
            color: root.secondaryColor
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            visible: root.hudTitle !== "" && root.hudSubtitle !== ""
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
              color: (hudSubMouse.enabled && hudSubMouse.containsMouse) ? "#ffffff" : Color.accent

              Behavior on color {
                ColorAnimation { duration: 120 }
              }
            }

            MouseArea {
              id: hudSubMouse
              anchors.centerIn: parent
              width: parent.width + 8
              height: root.barSize
              enabled: root.hudCommand !== ""
              hoverEnabled: enabled
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              property bool tooltipHovered: containsMouse
              onEntered: {
                var tip = root.hudTooltipText()
                if (tip) root.showTooltip(hudSubMouse, tip)
              }
              onExited: root.hideTooltip(hudSubMouse)
              onClicked: {
                if (root.hudCommand) root.run(root.hudCommand)
              }
            }
          }
        }
      }
    }
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

  component MidnightSystemHud: Item {
    id: sysHudRoot
    visible: root.isMidnightDoll && !root.barHidden
    height: root.barSize
    implicitWidth: sysHudRow.implicitWidth
    implicitHeight: root.barSize
    width: implicitWidth

    property bool pressable: true
    function triggerPress(button) {
      if (root.hudCommand) root.run(root.hudCommand)
    }

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
          if (root.hudCommand) root.run(root.hudCommand)
        }
        Component.onCompleted: if (typeof root.registerClickTarget === "function") root.registerClickTarget(this)
        Component.onDestruction: if (typeof root.unregisterClickTarget === "function") root.unregisterClickTarget(this)

        // CPU Gauge
        Row {
          spacing: 4
          anchors.verticalCenter: parent.verticalCenter
          Text {
            text: "CPU"
            font.family: root.fontFamily
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
            horizontalAlignment: Text.AlignLeft
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            visible: sysHudRoot.cpuTemp > 0
            text: sysHudRoot.cpuTemp + "°C"
            font.family: root.fontFamily
            font.pixelSize: 8
            color: sysHudRoot.cpuTemp > 80 ? root.urgent : Color.foreground
            width: visible ? 24 : 0
            horizontalAlignment: Text.AlignLeft
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        // Divider
        Text {
          text: "|"
          font.family: root.fontFamily
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
            font.family: root.fontFamily
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
              model: sysHudRoot.fanList
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
                  color: modelData > 80 ? root.urgent : Color.accent
                }
              }
            }
          }
          Text {
            text: sysHudRoot.fanVal > 0 ? (sysHudRoot.fanVal >= 10000 ? (sysHudRoot.fanVal / 1000).toFixed(1) + "k" : String(sysHudRoot.fanVal)) : "OFF"
            font.family: root.fontFamily
            font.pixelSize: 8
            color: sysHudRoot.fanPct > 80 ? root.urgent : Color.foreground
            width: 24
            horizontalAlignment: Text.AlignLeft
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        // Divider
        Text {
          text: "|"
          font.family: root.fontFamily
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
            font.family: root.fontFamily
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
              width: Math.max(1, Math.round(parent.width * (sysHudRoot.memVal / 100.0)))
              color: sysHudRoot.memVal > 85 ? root.urgent : Color.accent
            }
          }
          Text {
            text: sysHudRoot.memVal + "%"
            font.family: root.fontFamily
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
          font.family: root.fontFamily
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
            font.family: root.fontFamily
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
            horizontalAlignment: Text.AlignLeft
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }

      // Divider
      Text {
        text: "|"
        font.family: root.fontFamily
        font.pixelSize: 8
        color: Qt.rgba(1, 1, 1, 0.22)
        anchors.verticalCenter: parent.verticalCenter
      }

      // Comms Telemetry Group (CONNS, NET) -> Launches smart comms inspector
      Row {
        id: commsGroup
        spacing: 6
        width: implicitWidth
        height: root.barSize
        anchors.verticalCenter: parent.verticalCenter
        property bool pressable: true
        function triggerPress(button) {
          root.run("omarchy-launch-or-focus-tui --app-id=TUI.float " + root.home + "/.config/omarchy/launch-comms.sh")
        }
        Component.onCompleted: if (typeof root.registerClickTarget === "function") root.registerClickTarget(this)
        Component.onDestruction: if (typeof root.unregisterClickTarget === "function") root.unregisterClickTarget(this)

        // Connections Indicator
        Row {
          spacing: 4
          anchors.verticalCenter: parent.verticalCenter
          Text {
            text: "CONNS"
            font.family: root.fontFamily
            font.pixelSize: 8
            font.bold: true
            color: root.secondaryColor
            rightPadding: 2
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            text: String(sysHudRoot.connsVal)
            font.family: root.fontFamily
            font.pixelSize: 8
            color: sysHudRoot.connsVal > 100 ? root.urgent : Color.accent
            width: 18
            horizontalAlignment: Text.AlignLeft
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        // Divider
        Text {
          text: "|"
          font.family: root.fontFamily
          font.pixelSize: 8
          color: Qt.rgba(1, 1, 1, 0.22)
          anchors.verticalCenter: parent.verticalCenter
        }

        // NET Rates
        Row {
          spacing: 4
          anchors.verticalCenter: parent.verticalCenter
          Text {
            text: "NET"
            font.family: root.fontFamily
            font.pixelSize: 8
            font.bold: true
            color: root.secondaryColor
            rightPadding: 2
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
    }
  }

  component MidnightCavaVisualizer: Item {
    id: cavaRoot
    visible: root.isMidnightDoll && !root.barHidden
    height: root.barSize
    implicitWidth: cavaRow.implicitWidth
    implicitHeight: root.barSize
    width: implicitWidth

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

    property Timer cavaRestartTimer: Timer {
      interval: 1000
      onTriggered: {
        if (cavaRoot.visible) cavaProc.running = true
      }
    }

    Process {
      id: cavaProc
      command: ["cava", "-p", root.home + "/.config/omarchy/cava.conf"]
      running: cavaRoot.visible
      onExited: function(exitCode, exitStatus) {
        cavaRoot.spectrum = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        cavaRoot.bassLevel = 0
        cavaRoot.midLevel = 0
        cavaRoot.airLevel = 0
        waveCanvas.requestPaint()
        cavaRestartTimer.restart()
      }
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

    Row {
      id: cavaRow
      anchors.verticalCenter: parent.verticalCenter
      spacing: 2

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
          color: cavaRoot.airLevel > 0.6 ? root.urgent : root.secondaryColor
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
          color: cavaRoot.midLevel > 0.6 ? root.urgent : root.secondaryColor
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
          color: cavaRoot.bassLevel > 0.6 ? root.urgent : root.secondaryColor
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
            width: Math.max(1, Math.round(parent.width * cavaRoot.bassLevel))
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
                ctx.fillStyle = root.secondaryColor // Complimentary accent active LED
              }
            } else {
              ctx.fillStyle = Qt.rgba(root.secondaryColor.r, root.secondaryColor.g, root.secondaryColor.b, 0.28) // Base glowing LED
            }
            ctx.fill()
          }
        }
      }
    }
  }
}
}
