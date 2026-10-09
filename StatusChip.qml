import QtQuick
import qs.Common
import "Glyphs.js" as Glyphs

// "Release" / "Merged" / "Dica": glyph + word on a tint of the status colour.
// The word is there so the chip still means something in a theme whose
// foreground is that same colour, and to anyone who does not see it.
Rectangle {
  id: root

  property string status: "note"
  property real fontSize: Theme.fontSizeSmall

  readonly property color tone: Glyphs.colorFor(root.status)

  implicitWidth: label.implicitWidth + Theme.spacingS
  implicitHeight: label.implicitHeight + Theme.spacingXS
  radius: height / 2
  color: Qt.rgba(tone.r, tone.g, tone.b, 0.16)
  border.width: 1
  border.color: Qt.rgba(tone.r, tone.g, tone.b, 0.45)

  Text {
    id: label
    anchors.centerIn: parent
    text: Glyphs.glyphFor(root.status) + " " + Glyphs.labelFor(root.status)
    textFormat: Text.PlainText
    color: root.tone
    font.family: Theme.defaultFontFamily
    font.pixelSize: root.fontSize
    font.bold: true
  }
}
