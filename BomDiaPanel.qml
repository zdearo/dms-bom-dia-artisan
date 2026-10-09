import QtQuick
import qs.Common
import qs.Modules.Plugins
import "Glyphs.js" as Glyphs
import "Model.js" as Model

// The popout: today's edition, readable in place.
//
// Header with the refresh button, the edition navigator, the filter chips, the
// editors' summary and "atenção" note, then every item grouped by package — the
// recommendation of the day last. Keyboard-first: arrows walk items and days,
// Space reads the full note, Enter opens the source.
//
// This file draws and keeps view state (which day, which filter, which row).
// It decides nothing about the data: that is Model.js. Everything that reaches
// the outside world goes through `send`, which the daemon carries out.
PopoutComponent {
  id: root

  headerText: "Bom Dia, Artisan"
  detailsText: root.edition ? Model.longDate(root.edition.date) : "Resumo diário do ecossistema Laravel"
  showCloseButton: true

  // Set by the widget. `send(name, args)` asks the daemon for work.
  property var summary: Model.empty()
  property double nowMs: Date.now()
  property bool busy: false
  property var send: null
  // The popout's full height, given by the widget; the body fills what the
  // header and details leave.
  property real panelHeight: 600

  // The popout hosts this content for as long as the widget exists, hidden or
  // not, so "is it on screen" comes from the popout that owns it.
  readonly property bool shown: root.parentPopout ? root.parentPopout.shouldBeVisible === true : false

  readonly property color codeColor: Theme.primary
  readonly property color textColor: Theme.surfaceText
  readonly property string fontFamily: Theme.defaultFontFamily

  headerActions: Component {
    BomDiaButton {
      iconName: "refresh"
      foreground: root.textColor
      active: !root.busy
      onClicked: root.refresh()
    }
  }

  // ------------------------------------------------------------ view state --

  // Which edition is on screen, by DATE rather than index: a refresh that adds
  // tomorrow's edition shifts every index by one, and the page you are reading
  // must not change under you. "" means "the newest".
  property string viewedDate: ""
  property string filter: "all"
  property string cursorKey: ""
  property var expanded: ({})
  // +1 when moving to an older day, -1 to a newer one: which way the content
  // slides in.
  property int slideDir: 0

  readonly property var editions: root.summary.editions || []
  readonly property int editionIndex: {
    if (!root.viewedDate) return 0;
    for (var i = 0; i < root.editions.length; i++)
      if (root.editions[i].date === root.viewedDate) return i;
    return 0;
  }
  readonly property var edition: root.editions.length ? root.editions[root.editionIndex] : null
  readonly property string activeFilter: Model.effectiveFilter(root.edition, root.filter)
  readonly property var sections: Model.sectionsFor(root.edition, root.filter)
  readonly property var navKeys: Model.navKeys(root.sections)
  readonly property var otherUnread: (root.summary.unread || []).filter(function (d) {
    return !root.edition || d !== root.edition.date;
  })

  function resetView() {
    pointerGate.reset();
    root.cursorKey = "";
    root.expanded = ({});
    body.contentY = 0;
  }

  function showDate(date, dir) {
    if (!date || (root.edition && date === root.edition.date)) return;
    root.slideDir = dir;
    root.viewedDate = date;
    root.resetView();
    slideIn.restart();
  }

  function stepEdition(dir) {
    // dir +1 = older (further down the list), -1 = newer.
    var i = root.editionIndex + dir;
    if (i < 0 || i >= root.editions.length) {
      edgeBump.dir = dir;
      edgeBump.restart();
      return;
    }
    root.showDate(root.editions[i].date, dir);
  }

  function jumpToUnread() {
    if (!root.otherUnread.length) return;
    // Newest unread that is not the one on screen.
    var d = root.otherUnread[0];
    root.showDate(d, d < (root.edition ? root.edition.date : "") ? 1 : -1);
  }

  function setFilter(key) {
    if (key === root.activeFilter) return;
    root.filter = key;
    pointerGate.reset();
    root.cursorKey = "";
    body.contentY = 0;
  }

  function toggleExpanded(key) {
    var next = Object.assign({}, root.expanded);
    if (next[key]) delete next[key]; else next[key] = true;
    root.expanded = next;
  }

  function moveCursor(dy) {
    pointerGate.reset();
    root.cursorKey = Model.moveCursor(root.navKeys, root.cursorKey, dy);
  }

  function cursorToEnd(dir) {
    pointerGate.reset();
    var n = root.navKeys.length;
    root.cursorKey = n ? root.navKeys[dir < 0 ? 0 : n - 1] : "";
  }

  function activate() {
    var it = Model.findItem(root.sections, root.cursorKey);
    if (!it) { root.moveCursor(1); return; }
    if (it.details) root.toggleExpanded(it.key); else root.openItem(it);
  }

  function closeSelf() {
    if (root.closePopout) root.closePopout();
  }

  function openItem(it) {
    if (!it || !it.url || !root.send) return;
    root.send("openUrl", { url: it.url });
    root.closeSelf();
  }

  // A link inside an editor's note. The daemon only opens http(s).
  function openLink(url) {
    if (!url || !root.send) return;
    root.send("openUrl", { url: url });
    root.closeSelf();
  }

  function openEdition() {
    if (!root.send) return;
    root.send("openUrl", { url: root.edition ? root.edition.url : Model.SITE });
    root.closeSelf();
  }

  function refresh() {
    if (root.send) root.send("refresh", {});
  }

  function markRead(date) {
    if (root.send) root.send("markRead", { date: date });
  }

  function markAllRead() {
    if (root.send) root.send("markAllRead", {});
  }

  // Keep the cursor row in view, smoothly. Only scrolls when the row is
  // actually outside the viewport, so walking down a visible list stays still.
  //
  // Runs twice: now, and again once layout has settled. A row that just grew
  // (an expanded note) reports its new height before the Column has re-laid
  // out, so on the first pass the content height is still the old one.
  property var revealTarget: null

  function reveal(item) {
    root.revealTarget = item;
    root.revealNow(item);
    revealSettle.restart();
  }

  function revealNow(item) {
    if (!item) return;
    var p = item.mapToItem(content, 0, 0);
    var margin = Theme.spacingS;
    var maxY = Math.max(0, body.contentHeight - body.height);
    var target = body.contentY;
    if (p.y - margin < body.contentY)
      target = p.y - margin;
    else if (p.y + item.height + margin > body.contentY + body.height)
      target = Math.min(p.y - margin, p.y + item.height + margin - body.height);
    target = Math.max(0, Math.min(maxY, target));
    if (target !== body.contentY) {
      scrollAnim.to = target;
      scrollAnim.restart();
    }
  }

  // Every open starts on the newest edition with nothing selected. A panel
  // that reopens on whatever you were last poking at a day ago is a panel
  // that hides today's news.
  onShownChanged: {
    if (root.shown) {
      root.viewedDate = "";
      root.slideDir = 0;
      root.resetView();
      keys.forceActiveFocus();
    }
  }

  Timer {
    id: revealSettle
    interval: 32
    onTriggered: root.revealNow(root.revealTarget)
  }

  // Hover takes the cursor only on real pointer movement. After a keyboard move
  // the list can scroll under a resting pointer; the first event after a reset
  // only records where the pointer is, so that scroll cannot steal the cursor.
  QtObject {
    id: pointerGate
    property point last: Qt.point(-1, -1)

    function reset() {
      last = Qt.point(-1, -1);
    }

    function moved(area, mouse) {
      var p = area.mapToItem(null, mouse.x, mouse.y);
      var changed = last.x >= 0 && (Math.abs(p.x - last.x) + Math.abs(p.y - last.y) > 2);
      last = p;
      return changed;
    }
  }

  // An edition counts as read once it has been on screen for a moment, not the
  // instant it flashes past while you arrow through the week.
  Timer {
    id: dwell
    interval: 1200
    running: root.shown && root.edition !== null
      && (root.summary.unread || []).indexOf(root.edition.date) >= 0
    onTriggered: if (root.edition) root.markRead(root.edition.date)
  }

  // The panel's whole area. Children are placed by anchors, so this is sized
  // explicitly: the popout's height less what its header and details take.
  Item {
    id: keys
    width: parent.width
    height: root.panelHeight - root.headerHeight - root.detailsHeight
    focus: true

    // Escape is left alone: the popout closes on it, as on any other popout.
    Keys.onPressed: function (event) {
      var k = event.key;
      var t = event.text;
      var mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
      if (k === Qt.Key_Escape || mods) { event.accepted = false; return; }
      var handled = true;
      if (k === Qt.Key_Down || t === "j") root.moveCursor(1);
      else if (k === Qt.Key_Up || t === "k") root.moveCursor(-1);
      else if (k === Qt.Key_Left || t === "h") root.stepEdition(1);
      else if (k === Qt.Key_Right || t === "l") root.stepEdition(-1);
      else if (k === Qt.Key_Space) root.activate();
      else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
        var it = Model.findItem(root.sections, root.cursorKey);
        if (it) root.openItem(it); else root.openEdition();
      }
      else if (k === Qt.Key_Home || t === "g") root.cursorToEnd(-1);
      else if (k === Qt.Key_End || t === "G") root.cursorToEnd(1);
      else if (t === "f") root.setFilter(Model.cycleFilter(root.edition, root.filter, 1));
      else if (t === "F") root.setFilter(Model.cycleFilter(root.edition, root.filter, -1));
      else if (t >= "1" && t <= "4") {
        var opts = Model.filterOptions(root.edition);
        var n = Number(t) - 1;
        if (n < opts.length) root.setFilter(opts[n].key);
      }
      else if (t === "n") root.jumpToUnread();
      else if (t === "o") root.openEdition();
      else if (t === "r") root.refresh();
      else if (t === "m") root.markAllRead();
      else handled = false;
      event.accepted = handled;
    }

    // ------------------------------------------------------ day navigator --
    Item {
      id: nav
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      height: Theme.fontSizeLarge * 2.2
      visible: root.edition !== null

      BomDiaButton {
        id: prevBtn
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        iconName: "prev"
        foreground: root.textColor
        active: root.editionIndex < root.editions.length - 1
        onClicked: root.stepEdition(1)
      }

      Item {
        id: dayBox
        anchors.centerIn: parent
        width: dayText.implicitWidth + Theme.spacingM
        height: dayText.implicitHeight

        Text {
          id: dayText
          anchors.centerIn: parent
          text: root.edition ? Model.dayLabel(root.edition.date, root.nowMs) : ""
          textFormat: Text.PlainText
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: Theme.fontSizeMedium
          font.bold: true
        }

        // This day is unread: a brand dot beside its name, which goes out the
        // moment the dwell timer marks it read.
        Rectangle {
          visible: root.edition !== null && (root.summary.unread || []).indexOf(root.edition.date) >= 0
          width: 6
          height: width
          radius: width / 2
          color: Glyphs.BRAND
          anchors.left: dayText.right
          anchors.leftMargin: 3
          anchors.top: dayText.top
        }
      }

      BomDiaButton {
        id: nextBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        iconName: "next"
        foreground: root.textColor
        active: root.editionIndex > 0
        onClicked: root.stepEdition(-1)
      }

      // A nudge at the end of the window: the navigator shakes rather than
      // silently ignoring the key.
      SequentialAnimation {
        id: edgeBump
        property int dir: 0
        NumberAnimation { target: dayBox; property: "x"; to: dayBox.x + edgeBump.dir * 6; duration: 60 }
        NumberAnimation { target: dayBox; property: "x"; to: dayBox.x; duration: 160; easing.type: Easing.OutBack }
      }
    }

    // ------------------------------------------------------- filter chips --
    Item {
      id: chips
      anchors.top: nav.bottom
      anchors.topMargin: Theme.spacingS
      anchors.left: parent.left
      anchors.right: parent.right
      height: root.edition ? chipRow.implicitHeight : 0
      visible: root.edition !== null

      Row {
        id: chipRow
        spacing: Theme.spacingXS

        Repeater {
          model: Model.filterOptions(root.edition)

          BomDiaButton {
            required property var modelData
            label: modelData.label + "  " + modelData.count
            selected: root.activeFilter === modelData.key
            bordered: true
            foreground: modelData.key === "all" ? root.textColor : Glyphs.colorFor(modelData.key)
            onClicked: root.setFilter(modelData.key)
          }
        }
      }

      // "2 não lidas ›" — only when a day other than this one is unread.
      BomDiaButton {
        anchors.right: parent.right
        anchors.verticalCenter: chipRow.verticalCenter
        visible: root.otherUnread.length > 0
        label: root.otherUnread.length === 1 ? "1 não lida" : root.otherUnread.length + " não lidas"
        iconName: "next"
        foreground: root.codeColor
        onClicked: root.jumpToUnread()
      }
    }

    // ------------------------------------------------------------ footer --
    Column {
      id: footer
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Theme.spacingS

      Rectangle {
        width: parent.width
        height: 1
        color: Theme.withAlpha(root.textColor, 0.12)
      }

      Item {
        width: parent.width
        height: Math.max(freshness.implicitHeight, actions.implicitHeight)

        // How current this is, in words. Offline says so, and says that what is
        // on screen is the saved copy rather than pretending.
        Text {
          id: freshness
          anchors.left: parent.left
          anchors.right: actions.left
          anchors.rightMargin: Theme.spacingS
          anchors.verticalCenter: parent.verticalCenter
          text: {
            if (root.busy) return "Atualizando…";
            if (root.summary.stale) return Glyphs.icon("offline") + "  Offline · cópia salva";
            if (root.summary.lastOkMs) return "Atualizado " + Model.relative(root.summary.lastOkMs, root.nowMs);
            return "";
          }
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: root.summary.stale ? Glyphs.colorFor("recommended") : root.textColor
          opacity: root.summary.stale ? 0.9 : 0.5
          font.family: root.fontFamily
          font.pixelSize: Theme.fontSizeSmall
        }

        Row {
          id: actions
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter

          BomDiaButton {
            visible: (root.summary.unread || []).length > 1
            label: "Marcar lidas"
            iconName: "check"
            foreground: root.textColor
            onClicked: root.markAllRead()
          }
        }
      }

      // The keys, once, where they are always visible. Everything here is
      // reachable by mouse too; this line is how anyone finds out it is also
      // reachable without one.
      Text {
        width: parent.width
        visible: root.edition !== null
        horizontalAlignment: Text.AlignHCenter
        text: "↑↓ itens   espaço nota   ↵ abrir   ←→ dias   f filtro   n não lida"
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: root.textColor
        opacity: 0.35
        font.family: root.fontFamily
        font.pixelSize: Theme.fontSizeSmall
      }
    }

    // --------------------------------------------------------------- body --
    Flickable {
      id: body
      anchors.top: chips.bottom
      anchors.topMargin: Theme.spacingS
      anchors.bottom: footer.top
      anchors.bottomMargin: Theme.spacingS
      anchors.left: parent.left
      anchors.right: parent.right
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      contentWidth: width
      contentHeight: content.implicitHeight

      NumberAnimation {
        id: scrollAnim
        target: body
        property: "contentY"
        duration: 140
        easing.type: Easing.OutCubic
      }

      Column {
        id: content
        width: body.width
        spacing: Theme.spacingM

        // Day change: the new page slides in from the side it came from.
        transform: Translate { id: slide; x: 0 }
        ParallelAnimation {
          id: slideIn
          NumberAnimation { target: slide; property: "x"; from: root.slideDir * 18; to: 0; duration: 200; easing.type: Easing.OutCubic }
          NumberAnimation { target: content; property: "opacity"; from: 0.2; to: 1; duration: 200 }
        }

        // ---- loading / offline-with-nothing -------------------------------
        Column {
          width: parent.width
          visible: root.edition === null
          spacing: Theme.spacingS
          topPadding: Theme.spacingL
          bottomPadding: Theme.spacingL

          Mark {
            anchors.horizontalCenter: parent.horizontalCenter
            level: root.summary.level === "offline" ? "offline" : "unread"
            steam: root.summary.level !== "offline"
            unreadCount: 0
            foreground: root.textColor
            glyphSize: Theme.fontSizeXLarge
            showDot: false
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.summary.level === "offline" ? root.summary.error : "Passando o café…"
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: root.textColor
            opacity: 0.75
            font.family: root.fontFamily
            font.pixelSize: Theme.fontSizeMedium
          }

          BomDiaButton {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.summary.level === "offline"
            label: "Tentar de novo"
            iconName: "refresh"
            bordered: true
            foreground: root.textColor
            onClicked: root.refresh()
          }
        }

        // ---- the editors' summary -----------------------------------------
        Text {
          width: parent.width
          visible: root.edition !== null && root.edition.summary !== "" && root.activeFilter === "all"
          text: root.edition ? Model.richText(root.edition.summary, root.codeColor) : ""
          textFormat: Text.StyledText
          wrapMode: Text.Wrap
          color: root.textColor
          opacity: 0.9
          font.family: root.fontFamily
          font.pixelSize: Theme.fontSizeMedium
          lineHeight: 1.25
        }

        // ---- "atenção": what is released vs only merged -------------------
        Rectangle {
          width: parent.width
          visible: root.edition !== null && root.edition.attention !== "" && root.activeFilter === "all"
          height: attentionText.implicitHeight + Theme.spacingM
          radius: Theme.cornerRadius
          color: Theme.withAlpha(root.codeColor, 0.08)
          border.width: 1
          border.color: Theme.withAlpha(root.codeColor, 0.25)

          Text {
            id: bolt
            x: Theme.spacingS
            y: Theme.spacingS
            text: Glyphs.icon("attention")
            textFormat: Text.PlainText
            color: root.codeColor
            font.family: root.fontFamily
            font.pixelSize: Theme.fontSizeSmall
          }

          Text {
            id: attentionText
            anchors.left: bolt.right
            anchors.leftMargin: Theme.spacingS
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingS
            y: Theme.spacingS
            text: root.edition ? Model.richText(root.edition.attention, root.codeColor) : ""
            textFormat: Text.StyledText
            wrapMode: Text.Wrap
            color: root.textColor
            opacity: 0.85
            font.family: root.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            lineHeight: 1.2
          }
        }

        // ---- the news, by package -----------------------------------------
        Repeater {
          model: root.sections

          Column {
            id: sectionCol
            required property var modelData
            width: content.width
            spacing: Theme.spacingXS

            Item {
              width: parent.width
              height: Math.max(secTitle.implicitHeight, secCount.implicitHeight)

              Text {
                id: secTitle
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: (sectionCol.modelData.pick ? Glyphs.glyphFor("recommended") + "  " : "") + sectionCol.modelData.name
                textFormat: Text.PlainText
                color: root.textColor
                font.family: root.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
              }

              Text {
                id: secCount
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: sectionCol.modelData.items.length > 1
                text: String(sectionCol.modelData.items.length)
                textFormat: Text.PlainText
                color: root.textColor
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: Theme.fontSizeSmall
              }
            }

            Rectangle {
              width: parent.width
              height: 1
              color: Theme.withAlpha(root.textColor, 0.12)
            }

            Repeater {
              model: sectionCol.modelData.items

              ItemRow {
                required property var modelData
                width: sectionCol.width
                item: modelData
                cursorKey: root.cursorKey
                expanded: root.expanded[modelData.key] === true
                foreground: root.textColor
                fontFamily: root.fontFamily
                codeColor: root.codeColor
                pointerGate: pointerGate
                onCursorRequested: function (key) { root.cursorKey = key; }
                onToggleRequested: { root.cursorKey = modelData.key; root.toggleExpanded(modelData.key); }
                onOpenRequested: root.openItem(modelData)
                onLinkRequested: function (url) { root.openLink(url); }
                onRevealRequested: function (target) { root.reveal(target); }
              }
            }
          }
        }
      }
    }
  }
}
