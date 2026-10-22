import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Transição estilo Persona 3 Reload: faixas azuis inclinadas cobrem a tela,
// o wallpaper troca por baixo e as faixas saem.
// Disparo:  qs -c p3 ipc call p3 play
ShellRoot {
    id: root

    // ---- Ajustes ----
    readonly property real tilt: -14          // inclinação das faixas (graus)
    readonly property int inMs: 420           // duração da entrada
    readonly property int outMs: 420          // duração da saída
    readonly property int stagger: 40         // atraso entre faixas na entrada
    readonly property int outStagger: 30      // atraso entre faixas na saída
    readonly property int coverMs: 760        // instante em que a tela está toda coberta
    readonly property var colors: [
        "#1f6bff", "#0a2fd8", "#0a1470", "#2b8cff",
        "#071052", "#1a52f0", "#0c1d9a"
    ]

    signal trigger()

    IpcHandler {
        target: "p3"
        function play(): void { root.trigger(); }
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
            WlrLayershell.layer: WlrLayer.Overlay
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

                        // Borda branca no lado que avança
                        Rectangle {
                            width: 8
                            height: parent.height
                            color: "#ffffff"
                            x: band.dir > 0 ? band.width - 8 : 0
                        }

                        SequentialAnimation {
                            id: anim
                            PauseAnimation { duration: band.index * root.stagger }
                            NumberAnimation {
                                target: band; property: "x"
                                from: -band.dir * stage.width; to: 0
                                duration: root.inMs
                                easing.type: Easing.OutExpo
                            }
                            PauseAnimation {
                                duration: Math.max(0, root.coverMs + band.index * root.outStagger
                                                      - (band.index * root.stagger + root.inMs))
                            }
                            NumberAnimation {
                                target: band; property: "x"
                                to: band.dir * stage.width
                                duration: root.outMs
                                easing.type: Easing.InExpo
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
