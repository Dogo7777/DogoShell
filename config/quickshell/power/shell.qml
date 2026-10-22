import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Menu de energia no estilo da ilha.  qs -c power
// Teclas: L bloquear · S suspender · E sair · R reiniciar · P desligar · setas/Enter · Esc
ShellRoot {
    id: root
    // [shellstyle] formato (redondo/quadrado) vem de ~/.config/quickshell/style.json
    FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/style.json"
        watchChanges: true
        printErrors: false
        adapter: JsonAdapter { id: styleAd; property real scale: 1.0 }
    }
    readonly property real rs: styleAd.scale

    FileView {
        path: Quickshell.shellPath("../island/colors.json")
        watchChanges: true
        printErrors: false
        adapter: JsonAdapter { id: ad; property string accent: "#3948d9" }
    }
    readonly property color accent: ad.accent
    readonly property color accentFg:
        (0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b) > 0.6 ? "#000000" : "#ffffff"
    function accA(a) { return Qt.rgba(accent.r, accent.g, accent.b, a); }

    property real reveal: 0
    property bool closing: false
    property int sel: 2
    property int armed: -1

    Behavior on reveal {
        NumberAnimation {
            duration: root.closing ? 220 : 480
            easing.type: root.closing ? Easing.InCubic : Easing.OutQuint
        }
    }
    Timer { running: true; interval: 30; onTriggered: root.reveal = 1 }
    Timer { id: quitTimer; interval: 240; onTriggered: Qt.quit() }
    Timer { id: disarm; interval: 2500; onTriggered: root.armed = -1 }

    readonly property var items: [
        { name: "Bloquear",   key: "L", glyph: "", confirm: false, cmd: ["sh", "-c", "pidof hyprlock || hyprlock"] },
        { name: "Suspender",  key: "S", glyph: "", confirm: false, cmd: ["systemctl", "suspend"] },
        { name: "Sair",       key: "E", glyph: "", confirm: true,  cmd: ["sh", "-c", "loginctl terminate-session $XDG_SESSION_ID"] },
        { name: "Reiniciar",  key: "R", glyph: "", confirm: true,  cmd: ["systemctl", "reboot"] },
        { name: "Desligar",   key: "P", glyph: "", confirm: true,  cmd: ["systemctl", "poweroff"] }
    ]

    function close() {
        if (closing) return;
        closing = true;
        reveal = 0;
        quitTimer.start();
    }

    function trigger(i) {
        const it = items[i];
        if (it.confirm && armed !== i) {
            armed = i;
            sel = i;
            disarm.restart();
            return;
        }
        Quickshell.execDetached(it.cmd);
        close();
    }

    PanelWindow {
        id: win
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "power"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: 0.6 * root.reveal
            MouseArea { anchors.fill: parent; onClicked: root.close() }
        }

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Component.onCompleted: forceActiveFocus()
            Keys.onPressed: event => {
                const n = root.items.length;
                if (event.key === Qt.Key_Escape) { root.close(); }
                else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) { root.sel = (root.sel + 1) % n; root.armed = -1; }
                else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab) { root.sel = (root.sel - 1 + n) % n; root.armed = -1; }
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) { root.trigger(root.sel); }
                else {
                    for (let i = 0; i < n; i++) {
                        if (event.text.toUpperCase() === root.items[i].key) { root.sel = i; root.trigger(i); break; }
                    }
                }
                event.accepted = true;
            }
        }

        // título
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height / 2 - 170 - 10 * (1 - root.reveal)
            opacity: root.reveal
            text: root.armed >= 0 ? "Clique de novo para confirmar" : "O que você quer fazer?"
            color: root.armed >= 0 ? root.accent : "#cccccc"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 16
            font.bold: true
            Behavior on color { ColorAnimation { duration: 180 } }
        }

        // pílula que cresce e vira o painel
        Rectangle {
            id: bar
            readonly property real fullW: root.items.length * 128 + 24 + (root.items.length - 1) * 14
            width: 140 + (fullW - 140) * root.reveal
            height: 56 + (176 - 56) * root.reveal
            anchors.centerIn: parent
            radius: (36) * root.rs
            color: Qt.rgba(0.03, 0.03, 0.04, 0.80)
            border.width: 1
            border.color: root.accA(0.55)
            opacity: Math.min(1, root.reveal * 3)
            clip: true
            MouseArea { anchors.fill: parent }

            Row {
                id: row
                anchors.centerIn: parent
                spacing: 14
                opacity: Math.max(0, (root.reveal - 0.5) / 0.5)

                Repeater {
                    model: root.items
                    delegate: Rectangle {
                        id: btn
                        required property var modelData
                        required property int index
                        readonly property bool on: root.sel === index
                        readonly property bool arm: root.armed === index

                        width: 128
                        height: 152
                        radius: (28) * root.rs
                        color: arm ? root.accent : (on ? root.accA(0.22) : (ma.containsMouse ? "#14ffffff" : "#0cffffff"))
                        border.width: 1
                        border.color: on || arm ? root.accA(0.8) : "#14ffffff"
                        scale: ma.pressed ? 0.94 : (on ? 1.05 : 1.0)

                        property bool shown: false
                        Timer { running: true; interval: 220 + btn.index * 60; onTriggered: btn.shown = true }
                        opacity: shown ? 1 : 0
                        transform: Translate {
                            y: btn.shown ? 0 : 18
                            Behavior on y { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                        }
                        Behavior on opacity { NumberAnimation { duration: 260 } }
                        Behavior on color { ColorAnimation { duration: 180 } }
                        Behavior on border.color { ColorAnimation { duration: 180 } }
                        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }

                        Column {
                            anchors.centerIn: parent
                            spacing: 16
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: btn.modelData.glyph
                                color: btn.arm ? root.accentFg : (btn.on ? root.accent : "#e8e8e8")
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 38
                                Behavior on color { ColorAnimation { duration: 180 } }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: btn.arm ? "Confirmar?" : btn.modelData.name
                                color: btn.arm ? root.accentFg : "#ffffff"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 14
                                font.bold: true
                            }
                        }
                        Text {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 12
                            text: btn.modelData.key
                            color: btn.arm ? root.accentFg : "#666666"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                            font.bold: true
                        }

                        MouseArea {
                            id: ma
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: { root.sel = btn.index; if (root.armed !== btn.index) root.armed = -1; }
                            onClicked: root.trigger(btn.index)
                        }
                    }
                }
            }
        }
    }
}
