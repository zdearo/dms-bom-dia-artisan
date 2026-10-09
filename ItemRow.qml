import QtQuick
import qs.Common
import "Glyphs.js" as Glyphs
import "Model.js" as Model

// One piece of news: status chip and repository, the headline, a one-line
// "why it matters", and — expanded — the editors' full note.
//
// Click (or Space) expands in place; the link button (or Enter) opens the
// source. Reading the note is the main thing this panel is for; leaving for
// GitHub is the second.
//
// Paints from the panel's cursor, never from its own hover: mouse hover moves
// the cursor, so keyboard and mouse can never show two highlights at once.
Item {
  id: root

  property var item: null
  property string cursorKey: ""
  property bool expanded: false
  property color foreground: Theme.surfaceText
  property string fontFamily: Theme.defaultFontFamily
  property color codeColor: Theme.primary
  // The panel's pointer gate. Hover takes the cursor only on REAL pointer
  // movement: when the list scrolls under a resting pointer (End, an arrow key
  // revealing a row), the row that slides beneath it must not steal the
  // keyboard's selection.
  property var pointerGate: null

  readonly property bool hasCursor: root.item !== null && root.cursorKey === root.item.key
  readonly property bool hasDetails: root.item !== null && root.item.details !== ""
  readonly property real pad: Theme.spacingS

  signal cursorRequested(string key)
  signal toggleRequested()
  signal openRequested()
  signal linkRequested(string url)
  signal revealRequested(var target)

  width: parent ? parent.width : implicitWidth
  implicitHeight: body.implicitHeight + root.pad * 2
  height: implicitHeight

  onHasCursorChanged: if (root.hasCursor) root.revealRequested(root)
  // Expanding near the bottom grows the row below the fold; follow it. On the
  // height change, not on `expanded`: when `expanded` flips the row has not
  // been laid out at its new height yet.
  onHeightChanged: if (root.expanded && root.hasCursor) root.revealRequested(root)

  // The cursor's highlight. Drawn from the cursor, not from the hover.
  Rectangle {
    anchors.fill: parent
    radius: Theme.cornerRadius
    color: root.hasCursor ? Theme.withAlpha(Theme.primary, root.expanded ? 0.14 : 0.08) : "transparent"
  }

  function pointerMoved(area, mouse) {
    if (!root.item) return;
    if (!root.pointerGate || root.pointerGate.moved(area, mouse))
      root.cursorRequested(root.item.key);
  }

  MouseArea {
    id: rowMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.hasDetails ? Qt.PointingHandCursor : Qt.ArrowCursor
    onPositionChanged: function (mouse) { root.pointerMoved(rowMouse, mouse); }
    onClicked: root.hasDetails ? root.toggleRequested() : root.openRequested()
  }

  Column {
    id: body
    x: root.pad
    y: root.pad
    width: root.width - root.pad * 2
    spacing: Theme.spacingXS

    // -- chip · source ............................................ [link] --
    Item {
      width: parent.width
      height: Math.max(chip.implicitHeight, link.implicitHeight)

      StatusChip {
        id: chip
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        status: root.item ? root.item.status : "note"
      }

      Text {
        anchors.left: chip.right
        anchors.leftMargin: Theme.spacingXS
        anchors.right: link.left
        anchors.rightMargin: Theme.spacingXS
        anchors.verticalCenter: parent.verticalCenter
        text: root.item ? root.item.source : ""
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: root.foreground
        opacity: 0.5
        font.family: Theme.defaultMonoFontFamily
        font.pixelSize: Theme.fontSizeSmall
      }

      // The way out. Its own hit target, above the row's, so opening a link
      // never also toggles the row underneath it.
      Text {
        id: link
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: root.item !== null && root.item.url !== ""
        text: Glyphs.icon("external")
        textFormat: Text.PlainText
        color: root.foreground
        opacity: linkMouse.containsMouse ? 1.0 : (root.hasCursor ? 0.7 : 0.35)
        font.family: root.fontFamily
        font.pixelSize: Theme.fontSizeSmall

        Behavior on opacity { NumberAnimation { duration: 100 } }

        MouseArea {
          id: linkMouse
          anchors.fill: parent
          anchors.margins: -Theme.spacingXS
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onPositionChanged: function (mouse) { root.pointerMoved(linkMouse, mouse); }
          onClicked: root.openRequested()
        }
      }
    }

    Text {
      width: parent.width
      text: root.item ? Model.richText(root.item.title, root.codeColor) : ""
      textFormat: Text.StyledText
      wrapMode: Text.Wrap
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Theme.fontSizeMedium
      font.bold: true
      lineHeight: 1.1
    }

    Text {
      width: parent.width
      visible: text !== ""
      text: root.item ? Model.richText(root.item.description, root.codeColor) : ""
      textFormat: Text.StyledText
      wrapMode: Text.Wrap
      maximumLineCount: root.expanded ? 100 : 2
      elide: Text.ElideRight
      color: root.foreground
      opacity: 0.7
      font.family: root.fontFamily
      font.pixelSize: Theme.fontSizeSmall
      lineHeight: 1.15
    }

    // The editors' full note. Revealed in place: a left rule in the status
    // colour ties it to the chip above it.
    Item {
      width: parent.width
      height: root.expanded ? note.implicitHeight + Theme.spacingXS : 0
      visible: root.expanded && root.hasDetails
      clip: true

      Rectangle {
        x: 0
        y: Theme.spacingXS
        width: 2
        height: note.implicitHeight
        radius: width / 2
        color: Glyphs.colorFor(root.item ? root.item.status : "note")
        opacity: 0.8
      }

      Text {
        id: note
        x: Theme.spacingM
        y: Theme.spacingXS
        width: parent.width - Theme.spacingM
        text: root.item ? Model.markdown(root.item.details, root.codeColor) : ""
        textFormat: Text.StyledText
        linkColor: root.codeColor
        // A link takes its own click, so following one never also folds the
        // note underneath it.
        onLinkActivated: function (link) { root.linkRequested(link); }
        wrapMode: Text.Wrap
        color: root.foreground
        opacity: 0.88
        font.family: root.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        lineHeight: 1.25
      }
    }
    // No "press space to read more" line under the cursor row: anything that
    // appears with the cursor changes the row's height, and the whole list
    // below it would jump on every arrow key. The footer carries the hint.
  }
}
