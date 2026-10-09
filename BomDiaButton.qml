import QtQuick
import qs.Common
import "Glyphs.js" as Glyphs

// A small text button in the panel's own style. Plain on purpose: it carries
// no dependency on the shell's widget set, so the panel reads the same on any
// DMS version that loads this plugin.
Rectangle {
  id: root

  property string label: ""
  // A name from Glyphs.js, drawn before the label.
  property string iconName: ""
  property bool selected: false
  property bool bordered: false
  // Off: dimmed and takes no clicks. The control keeps its place either way.
  property bool active: true
  property color foreground: Theme.surfaceText

  signal clicked()

  implicitHeight: Math.round(Theme.fontSizeSmall * 2.2)
  implicitWidth: caption.implicitWidth + Theme.spacingM * 2
  radius: height / 2
  color: root.selected ? Theme.withAlpha(root.foreground, 0.16)
    : (area.containsMouse && root.active ? Theme.withAlpha(root.foreground, 0.08) : "transparent")
  border.width: root.bordered ? 1 : 0
  border.color: Theme.withAlpha(root.foreground, 0.3)
  opacity: root.active ? 1 : 0.35

  Text {
    id: caption
    anchors.centerIn: parent
    text: (root.iconName ? Glyphs.icon(root.iconName) + (root.label ? "  " : "") : "") + root.label
    textFormat: Text.PlainText
    color: root.foreground
    font.family: Theme.defaultFontFamily
    font.pixelSize: Theme.fontSizeSmall
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.active
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
