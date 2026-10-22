import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

ShellRoot {
    id: root

    // TEMA: Se o colors.json não existir, usa uma cor padrão (fallback) para não quebrar.
FileView {
        id: colorFile
        // Retrocede uma pasta e procura na pasta da ilha
        path: Quickshell.shellPath("../island/colors.json") 
        watchChanges: true
        printErrors: false
        adapter: JsonAdapter {
            property string accent: "#3948d9"
        }
    }

    readonly property color accent: colorFile.adapter.accent
    readonly property color accentFg:
        (0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b) > 0.6 ? "#000000" : "#ffffff"

    // ------------------------------------------------------------------
    // Lógica de Busca e Dados
    // ------------------------------------------------------------------
    property var allApps: []
    property var filteredApps: []

    Process {
        running: true
        command: ["python3", Quickshell.shellPath("get_apps.py")]
        stdout: SplitParser {
            onRead: data => {
                try {
                    if (data.trim() !== "") {
                        root.allApps = JSON.parse(data);
                        root.filteredApps = root.allApps;
                    }
                } catch(e) {}
            }
        }
    }

    function filter() {
        const query = searchInput.text.toLowerCase().trim();
        if (query === "") {
            filteredApps = allApps;
        } else {
            filteredApps = allApps.filter(app => app.name.toLowerCase().includes(query));
        }
        appList.currentIndex = 0;
    }

    function launchApp(index) {
        if (index >= 0 && index < filteredApps.length) {
            const cmd = filteredApps[index].exec;
            Quickshell.execDetached(["bash", "-c", cmd]);
            Qt.quit();
        }
    }

    component T: Text {
        color: "#d0d0d0"
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 14
        font.bold: true
        verticalAlignment: Text.AlignVCenter
    }

    // ------------------------------------------------------------------
    // Janela Principal
    // ------------------------------------------------------------------
    PanelWindow {
        id: win
        anchors.top: true; anchors.bottom: true; anchors.left: true; anchors.right: true
        color: Qt.rgba(0, 0, 0, 0.3)
        
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "launcher"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        MouseArea {
            anchors.fill: parent
            onClicked: Qt.quit()
        }

        Rectangle {
            id: box
            width: 440
            
            // CORREÇÃO 1: A altura exata baseada no tamanho real do conteúdo (sem loops)
            height: mainCol.height + 28
            anchors.centerIn: parent
            
            radius: 24
            color: Qt.rgba(0, 0, 0, 0.65)
            border.width: 1
            border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55)
            clip: true

            scale: 0.95
            opacity: 0
            Component.onCompleted: {
                box.scale = 1;
                box.opacity = 1;
                searchInput.forceActiveFocus();
            }
            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 150 } }
            Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent }

            // CORREÇÃO 2: Uso do 'Column' simples para garantir o alinhamento e impedir o "bug" da sobreposição
            Column {
                id: mainCol
                width: parent.width - 28
                anchors.centerIn: parent
                spacing: 10

                // -------------- Barra de Pesquisa --------------
                Row {
                    width: parent.width
                    height: 36
                    spacing: 12

                    T {
                        text: ""
                        color: root.accent
                        font.pixelSize: 18
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Item {
                        width: parent.width - 30
                        height: parent.height

                        T {
                            text: "Pesquisar aplicativos..."
                            color: "#666666"
                            font.pixelSize: 16
                            anchors.fill: parent
                            visible: searchInput.text === ""
                        }

                        TextInput {
                            id: searchInput
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            color: "#ffffff"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 16
                            font.bold: true
                            focus: true
                            clip: true
                            selectionColor: root.accent
                            selectedTextColor: root.accentFg
                            
                            onTextChanged: root.filter()

                            Keys.onPressed: (event) => {
                                if (event.key === Qt.Key_Escape) {
                                    Qt.quit();
                                } else if (event.key === Qt.Key_Down) {
                                    appList.currentIndex = Math.min(appList.count - 1, appList.currentIndex + 1);
                                    appList.positionViewAtIndex(appList.currentIndex, ListView.Contain);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Up) {
                                    appList.currentIndex = Math.max(0, appList.currentIndex - 1);
                                    appList.positionViewAtIndex(appList.currentIndex, ListView.Contain);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
                                    root.launchApp(appList.currentIndex);
                                    event.accepted = true;
                                }
                            }
                        }
                    }
                }

                // -------------- Linha Divisória --------------
                Rectangle {
                    width: parent.width
                    height: 1
                    color: "#2effffff"
                }

                // -------------- Aviso de Vazio --------------
                T {
                    width: parent.width
                    height: 44
                    text: "Nenhum aplicativo encontrado."
                    color: "#666666"
                    horizontalAlignment: Text.AlignHCenter
                    visible: appList.count === 0
                }

                // -------------- Lista --------------
                ListView {
                    id: appList
                    width: parent.width
                    
                    // CORREÇÃO 3: Altura independente ditando o tamanho da caixa
                    property int visibleItems: Math.max(0, Math.min(5, count))
                    height: visibleItems > 0 ? (visibleItems * 48) - 4 : 0
                    
                    clip: true
                    model: root.filteredApps
                    spacing: 4
                    visible: appList.count > 0

                    highlightMoveDuration: 150
                    highlightFollowsCurrentItem: true

                    delegate: Rectangle {
                        width: ListView.view.width
                        height: 44
                        radius: 12
                        color: ListView.isCurrentItem ? root.accent : (ma.containsMouse ? "#26ffffff" : "transparent")
                        Behavior on color { ColorAnimation { duration: 150 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 12

                            Image {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                source: {
                                    var ic = modelData.icon;
                                    if (ic.startsWith("/")) return "file://" + ic;
                                    if (ic.startsWith("file://")) return ic;
                                    return "image://icon/" + ic;
                                }
                                sourceSize.width: 32
                                sourceSize.height: 32
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                
                                onStatusChanged: {
                                    if (status === Image.Error) {
                                        source = "image://icon/application-x-executable"
                                    }
                                }
                            }

                            T {
                                Layout.fillWidth: true
                                text: modelData.name
                                color: parent.parent.ListView.isCurrentItem ? root.accentFg : "#ffffff"
                                font.pixelSize: 14
                            }
                        }

                        MouseArea {
                            id: ma
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.launchApp(index)
                        }
                    }
                }
            }
        }
    }
}
