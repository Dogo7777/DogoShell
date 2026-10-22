import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Transição estilo Persona 3 Reload, só sobre o wallpaper (camada Bottom).
// As faixas usam as cores do wallpaper novo.
//   qs -c p3 ipc call p3 play
//   qs -c p3 ipc call p3 playColors "#3948d9" "#d95667"
ShellRoot {
    id: root

    // ---- Ajustes ----
    readonly property real tilt: -14          // inclinação das faixas (graus)
    readonly property int inMs: 480           // duração da entrada de cada faixa
    readonly property int outMs: 480          // duração da saída
    readonly property int stagger: 35         // atraso entre faixas na entrada
    readonly property int outStagger: 35      // atraso entre faixas na saída
    readonly property int coverMs: 700        // instante da tela toda coberta (use o mesmo valor no sleep do script)

    // Cores base (trocadas a cada playColors)
    property color c1: "#1f6bff"
    property color c2: "#0a2fd8"

    readonly property var colors: [
        root.c1,
        root.c2,
        Qt.darker(root.c1, 2.4),
        Qt.lighter(root.c2, 1.25),
        Qt.darker(root.c2, 2.4),
        Qt.lighter(root.c1, 1.2),
        Qt.darker(root.c1, 1.6)
    ]

    signal trigger()

    IpcHandler {
        target: "p3"
        function play(): void { root.trigger(); }
        function playColors(a: string, b: string): void {
            root.c1 = a;
            root.c2 = b;
            root.trigger();
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "p3-transition"

            // Região vazia: o overlay nunca captura cliques
            mask: Region {}

            Item {
                id: stage
                anchors.centerIn: parent
                width: Math.max(win.width, win.height) * 1.9
                height: width
                rotation: root.tilt

                Repeater {
                    model: root.colors.length

                    delegate: Rectangle {
                        id: band
                        required property int index
                        readonly property int dir: index % 2 === 0 ? 1 : -1

                        width: stage.width
                        height: stage.height / root.colors.length + 2
                        y: index * stage.height / root.colors.length
                        x: -dir * stage.width
                        color: root.colors[index]

                        // Borda clara no lado que avança
                        Rectangle {
                            width: 8
                            height: parent.height
                            color: Qt.lighter(root.c1, 1.9)
                            x: band.dir > 0 ? band.width - 8 : 0
                        }

                        SequentialAnimation {
                            id: anim
                            PauseAnimation { duration: band.index * root.stagger }
                            NumberAnimation {
                                target: band; property: "x"
                                from: -band.dir * stage.width; to: 0
                                duration: root.inMs
                                easing.type: Easing.OutCubic
                            }
                            PauseAnimation {
                                duration: Math.max(0, root.coverMs + band.index * root.outStagger
                                                      - (band.index * root.stagger + root.inMs))
                            }
                            NumberAnimation {
                                target: band; property: "x"
                                to: band.dir * stage.width
                                duration: root.outMs
                                easing.type: Easing.InCubic
                            }
                        }

                        Connections {
                            target: root
                            function onTrigger() { anim.restart(); }
                        }
                    }
                }
            }
        }
    }
}
