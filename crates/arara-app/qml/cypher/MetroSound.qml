import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtMultimedia
import Qt.labs.settings
import AraraCypher
import io.github.arara as Arara

// Som do metrônomo, igual em toda parte do app: tipo de som (batida, madeira,
// chimbal, clique) e volume, guardados nos ajustes. play(true) = tempo forte.
// O próprio item mostra os controles (som e volume) quando visível.
RowLayout {
    id: root
    spacing: 8

    Settings {
        id: prefs
        category: "metronomo"
        property string sound: "batida"
        property real volume: 0.8
    }

    function play(strong) {
        if (prefs.volume <= 0) return
        ;(strong ? forte : fraco).play()
    }

    SoundEffect { id: forte; source: Arara.CypherMusic.beatSound(prefs.sound, true); volume: prefs.volume }
    SoundEffect { id: fraco; source: Arara.CypherMusic.beatSound(prefs.sound, false); volume: prefs.volume * 0.75 }

    SegmentedControl {
        model: [{ value: "batida", label: "Batida" }, { value: "madeira", label: "Madeira" },
                { value: "chimbal", label: "Chimbal" }, { value: "clique", label: "Clique" }]
        current: prefs.sound
        onActivated: (v) => { prefs.sound = v; forte.play() }
    }
    Text {
        text: "Volume"
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
    }
    Slider {
        id: vol
        Layout.preferredWidth: 120
        from: 0; to: 1; stepSize: 0.05
        value: prefs.volume
        onMoved: prefs.volume = value
        onPressedChanged: if (!pressed) forte.play()
    }
    Text {
        text: Math.round(prefs.volume * 100) + "%"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
        Layout.preferredWidth: 36
    }
}
