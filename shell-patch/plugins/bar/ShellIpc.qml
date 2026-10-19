import QtQuick
import Quickshell.Io

IpcHandler {
  id: handler

  Component.onCompleted: {
    try {
      if (typeof Commons !== "undefined" && Commons.IpcRegistry) {
        Commons.IpcRegistry.register(handler)
      } else if (typeof IpcRegistry !== "undefined") {
        IpcRegistry.register(handler)
      }
    } catch (e) {}
  }
  Component.onDestruction: {
    try {
      if (typeof Commons !== "undefined" && Commons.IpcRegistry) {
        Commons.IpcRegistry.unregister(handler)
      } else if (typeof IpcRegistry !== "undefined") {
        IpcRegistry.unregister(handler)
      }
    } catch (e) {}
  }
}
