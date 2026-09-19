import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "monitorMenu"

    ToggleSetting {
        settingKey: "forceBarPadding"
        label: "Padding en la barra"
        description: "Añade espacio alrededor del icono para separarlo de los widgets vecinos."
        defaultValue: true
    }

    SliderSetting {
        settingKey: "barPadding"
        label: "Espaciado"
        description: "Padding lateral en barras horizontales y vertical en barras laterales."
        defaultValue: 6
        minimum: 0
        maximum: 20
        unit: " px"
        leftIcon: "compress"
        rightIcon: "expand"
    }
}
