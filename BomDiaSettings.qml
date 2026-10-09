import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
  id: root
  pluginId: "bomDiaArtisan"

  StyledText {
    width: parent.width
    text: "Bom Dia, Artisan"
    font.pixelSize: Theme.fontSizeLarge
    font.weight: Font.Bold
    color: Theme.surfaceText
  }

  StringSetting {
    settingKey: "checkAt"
    label: "Verificar às"
    description: "Horário local (HH:MM) da verificação diária. A edição costuma sair por volta das 09:30. Se ainda não saiu, a verificação repete a cada hora até sair."
    placeholder: "09:30"
    defaultValue: "09:30"
  }

  ToggleSetting {
    settingKey: "notify"
    label: "Aviso para cada nova edição"
    description: "Mostra um aviso uma vez por edição nova. O aviso não abre o painel ao clicar."
    defaultValue: true
  }
}
