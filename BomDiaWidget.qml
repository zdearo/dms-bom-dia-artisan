import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Plugins
import "Model.js" as Model

// The bar entry: the mug, and the popout that reads today's edition. It draws
// what the daemon publishes and asks it for work. It fetches nothing itself, so
// a bar on every monitor still means one fetch, one toast, one cache.
PluginComponent {
  id: root

  // { summary, busy }, as the daemon last published it. Re-read on every change
  // of the variable, because the binding goes through PluginService.globalVars.
  readonly property var view: PluginService.getGlobalVar(root.pluginId, "view", null)
  readonly property var summary: root.view && root.view.summary ? root.view.summary : Model.empty()
  readonly property bool busy: root.view ? root.view.busy === true : false

  // The clock for relative times ("há 5 min") and the tooltip. The daemon has
  // its own clock for the daily check.
  property double nowMs: Date.now()
  Timer {
    interval: 60000
    repeat: true
    running: true
    onTriggered: root.nowMs = Date.now()
  }

  // Asks the daemon for work: `name` is one of refresh, markRead, markAllRead
  // or openUrl. A fresh seq is what makes the daemon run it.
  function send(name, args) {
    var prev = PluginService.getGlobalVar(root.pluginId, "command", null);
    PluginService.setGlobalVar(root.pluginId, "command", {
      name: name,
      args: args || {},
      seq: (prev ? prev.seq : 0) + 1
    });
  }

  horizontalBarPill: Component {
    Item {
      implicitWidth: mark.implicitWidth + Theme.spacingS * 2
      implicitHeight: root.widgetThickness

      Mark {
        id: mark
        anchors.centerIn: parent
        level: root.summary.level
        unreadCount: root.summary.unread.length
        foreground: Theme.widgetTextColor
        glyphSize: Theme.fontSizeMedium
        stale: root.summary.stale
        busy: root.busy && root.summary.level === "loading"
      }
    }
  }

  popoutWidth: 480
  popoutHeight: 600
  popoutContent: Component {
    BomDiaPanel {
      summary: root.summary
      nowMs: root.nowMs
      busy: root.busy
      send: root.send
      panelHeight: root.popoutHeight
    }
  }
}
