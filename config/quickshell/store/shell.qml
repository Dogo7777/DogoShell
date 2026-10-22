import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

ShellRoot {
    id: root

    FileView {
        path: Quickshell.shellPath("../island/colors.json")
        watchChanges: true
        printErrors: false
        adapter: JsonAdapter {
            id: colorAd
            property string accent: "#3948d9"
        }
    }
    readonly property color accent: colorAd.accent
    readonly property color accentFg: (0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b) > 0.6 ? "#000000" : "#ffffff"

    function accA(a) {
        return Qt.rgba(accent.r, accent.g, accent.b, a);
    }

    property var installedApps: []
    property var popularApps: []
    property var searchResults: []
    property int currentTab: 0 // 0: Mais Baixados, 1: Instalados, 2: Busca
    property string searchText: ""
    property bool isSearching: false

    // Estado da Instalação e Logs do Terminal
    property string installingAppId: ""
    property string installingAppName: ""
    property real installProgress: 0.0
    property var installLogs: []
    property bool showTerminalModal: false

    property bool hideThemes: true
    property bool hidePlugins: true
    property bool showFilterMenu: false
    property real reveal: 0
    property bool closing: false

    Behavior on reveal {
        NumberAnimation {
            duration: root.closing ? 240 : 550
            easing.type: root.closing ? Easing.InCubic : Easing.OutQuint
        }
    }

    Timer {
        running: true
        interval: 30
        onTriggered: {
            root.reveal = 1;
            fetchProc.running = true;
        }
    }

    Timer {
        id: quitTimer
        interval: 250
        onTriggered: Qt.quit()
    }

    Timer {
        id: resetTimer
        interval: 1500
        repeat: false
        onTriggered: {
            root.installingAppId = "";
            root.installingAppName = "";
            root.installProgress = 0.0;
            fetchProc.running = true;
        }
    }

    Timer {
        id: searchDebounce
        interval: 220
        repeat: false
        onTriggered: {
            const q = root.searchText.trim();
            if (q !== "") {
                root.isSearching = true;
                root.currentTab = 2;
                if (searchProc.running) searchProc.running = false;
                searchProc.command = ["python3", Quickshell.shellPath("store_backend.py"), "search", q];
                searchProc.running = true;
            } else {
                root.isSearching = false;
                root.searchResults = [];
                if (root.currentTab === 2) root.currentTab = 0;
            }
        }
    }

    function close() {
        if (closing) return;
        closing = true;
        reveal = 0;
        quitTimer.start();
    }

    function appendLog(text, isError) {
        const prefix = isError ? "[ERRO] " : "[LOG] ";
        let list = root.installLogs.slice();
        list.push(prefix + text);
        if (list.length > 200) list.shift();
        root.installLogs = list;
    }

    Process {
        id: fetchProc
        command: ["python3", Quickshell.shellPath("store_backend.py"), "get"]
        stdout: SplitParser {
            onRead: function(data) {
                try {
                    if (data.trim() !== "") {
                        const parsed = JSON.parse(data.trim());
                        root.installedApps = parsed.installed || [];
                        root.popularApps = parsed.popular || [];
                    }
                } catch(e) {}
            }
        }
    }

    Process {
        id: searchProc
        stdout: SplitParser {
            onRead: function(data) {
                root.isSearching = false;
                try {
                    if (data.trim() !== "") {
                        root.searchResults = JSON.parse(data.trim());
                    }
                } catch(e) {
                    root.searchResults = [];
                }
            }
        }
    }

    // Processo de Instalação com Captura de Progresso e Logs
    Process {
        id: installProc
        stdout: SplitParser {
            onRead: function(data) {
                const line = data.trim();
                if (line !== "") {
                    root.appendLog(line, false);
                    const match = line.match(/(\d+)%/);
                    if (match) {
                        root.installProgress = parseInt(match[1]) / 100.0;
                    }
                }
            }
        }
        stderr: SplitParser {
            onRead: function(data) {
                const line = data.trim();
                if (line !== "") {
                    root.appendLog(line, true);
                }
            }
        }
        onExited: function(exitCode, exitStatus) {
            if (exitCode === 0) {
                root.appendLog(">>> Instalação concluída com sucesso!", false);
                root.installProgress = 1.0;
            } else {
                root.appendLog(">>> Falha na instalação (Código de saída: " + exitCode + ")", true);
                root.showTerminalModal = true;
            }
            resetTimer.restart();
        }
    }

    component T: Text {
        color: "#d8d8d8"
        font.family: "JetBrainsMono Nerd Font, JetBrainsMonoNF, JetBrains Mono, Symbols Nerd Font, sans-serif"
        font.pixelSize: 13
        font.bold: true
        verticalAlignment: Text.AlignVCenter
    }

    PanelWindow {
        id: win
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "store"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: 0.45 * root.reveal
            Behavior on opacity { NumberAnimation { duration: 250 } }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (root.showTerminalModal) root.showTerminalModal = false;
                    else if (root.showFilterMenu) root.showFilterMenu = false;
                    else root.close();
                }
            }
        }

        Item {
            anchors.fill: parent
            focus: true
            Component.onCompleted: forceActiveFocus()
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                    if (root.showTerminalModal) {
                        root.showTerminalModal = false;
                    } else if (root.showFilterMenu) {
                        root.showFilterMenu = false;
                    } else {
                        root.close();
                    }
                    event.accepted = true;
                }
            }
        }

        Rectangle {
            id: card
            width: 880
            height: 600
            anchors.centerIn: parent
            radius: 28
            color: Qt.rgba(0.04, 0.04, 0.06, 0.92)
            border.width: 1
            border.color: root.accA(0.45)
            scale: 0.92 + 0.08 * root.reveal
            opacity: Math.min(1, root.reveal * 2)
            clip: false

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 22
                spacing: 16

                // Cabeçalho e Abas
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    T {
                        text: "Central Flathub"
                        font.pixelSize: 16
                        color: "#ffffff"
                    }

                    Item {
                        implicitWidth: tabRow.implicitWidth
                        implicitHeight: 36
                        Layout.alignment: Qt.AlignVCenter

                        Rectangle {
                            id: pill
                            height: 34
                            radius: 17
                            color: root.accA(0.28)
                            border.width: 1
                            border.color: root.accA(0.65)
                            y: 1

                            x: root.currentTab === 0 ? tab0.x : (root.currentTab === 1 ? tab1.x : tab2.x)
                            width: root.currentTab === 0 ? tab0.width : (root.currentTab === 1 ? tab1.width : tab2.width)

                            Behavior on x { NumberAnimation { duration: 280; easing.type: Easing.OutQuint } }
                            Behavior on width { NumberAnimation { duration: 280; easing.type: Easing.OutQuint } }
                        }

                        Row {
                            id: tabRow
                            spacing: 6

                            Item {
                                id: tab0
                                width: t0Text.implicitWidth + 28
                                height: 36
                                T {
                                    id: t0Text
                                    anchors.centerIn: parent
                                    text: "Mais Baixados"
                                    font.pixelSize: 12
                                    color: root.currentTab === 0 ? "#ffffff" : "#888888"
                                    Behavior on color { ColorAnimation { duration: 180 } }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.currentTab = 0; searchInput.text = ""; }
                                }
                            }

                            Item {
                                id: tab1
                                width: t1Text.implicitWidth + 28
                                height: 36
                                T {
                                    id: t1Text
                                    anchors.centerIn: parent
                                    text: "Instalados (" + root.installedApps.length + ")"
                                    font.pixelSize: 12
                                    color: root.currentTab === 1 ? "#ffffff" : "#888888"
                                    Behavior on color { ColorAnimation { duration: 180 } }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.currentTab = 1; searchInput.text = ""; }
                                }
                            }

                            Item {
                                id: tab2
                                width: t2Text.implicitWidth + 28
                                height: 36
                                visible: root.searchText.trim() !== "" || root.searchResults.length > 0
                                T {
                                    id: t2Text
                                    anchors.centerIn: parent
                                    text: root.isSearching ? "Buscando..." : "Busca (" + grid.count + ")"
                                    font.pixelSize: 12
                                    color: root.currentTab === 2 ? "#ffffff" : "#888888"
                                    Behavior on color { ColorAnimation { duration: 180 } }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.currentTab = 2
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Campo de Busca
                    Rectangle {
                        Layout.preferredWidth: 220
                        Layout.preferredHeight: 36
                        Layout.alignment: Qt.AlignVCenter
                        radius: 18
                        color: Qt.rgba(1, 1, 1, 0.07)
                        border.width: 1
                        border.color: searchInput.activeFocus ? root.accA(0.8) : Qt.rgba(1, 1, 1, 0.15)
                        Behavior on border.color { ColorAnimation { duration: 180 } }

                        Item {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 10

                            T {
                                id: placeholderTxt
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Pesquisar Flathub..."
                                color: "#555555"
                                font.pixelSize: 12
                                visible: searchInput.text === ""
                            }

                            TextInput {
                                id: searchInput
                                anchors.left: parent.left
                                anchors.right: searchClearBtn.visible ? searchClearBtn.left : parent.right
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                color: "#ffffff"
                                font.family: "JetBrainsMono Nerd Font, JetBrainsMonoNF, Symbols Nerd Font, sans-serif"
                                font.pixelSize: 12
                                clip: true

                                onTextChanged: {
                                    root.searchText = text;
                                    searchDebounce.restart();
                                }
                            }

                            T {
                                id: searchClearBtn
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\uf00d"
                                font.pixelSize: 12
                                color: searchClearMa.containsMouse ? "#ffffff" : "#888888"
                                visible: searchInput.text !== ""
                                MouseArea {
                                    id: searchClearMa
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        searchInput.text = "";
                                        root.searchText = "";
                                        root.searchResults = [];
                                        if (root.currentTab === 2) root.currentTab = 0;
                                    }
                                }
                            }
                        }
                    }

                    // Botão Terminal de Logs
                    Rectangle {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        Layout.alignment: Qt.AlignVCenter
                        radius: 18
                        color: root.showTerminalModal ? root.accA(0.4) : (termMa.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.06))
                        border.width: 1
                        border.color: root.showTerminalModal ? root.accent : Qt.rgba(1, 1, 1, 0.15)
                        scale: termMa.containsMouse ? 1.08 : 1.0

                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }

                        T {
                            anchors.centerIn: parent
                            text: "\uf120"
                            font.pixelSize: 14
                            color: root.installLogs.length > 0 ? root.accent : "#ffffff"
                        }
                        MouseArea {
                            id: termMa
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.showTerminalModal = !root.showTerminalModal
                        }
                    }

                    // Botão Configurações
                    Rectangle {
                        id: cfgBtn
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        Layout.alignment: Qt.AlignVCenter
                        radius: 18
                        color: root.showFilterMenu ? root.accA(0.4) : (cfgMa.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.06))
                        border.width: 1
                        border.color: root.showFilterMenu ? root.accent : Qt.rgba(1, 1, 1, 0.15)
                        scale: cfgMa.containsMouse ? 1.08 : 1.0

                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }

                        T {
                            anchors.centerIn: parent
                            text: "\uf013"
                            font.pixelSize: 14
                            color: "#ffffff"
                        }
                        MouseArea {
                            id: cfgMa
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.showFilterMenu = !root.showFilterMenu
                        }
                    }

                    // Botão Recarregar
                    Rectangle {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        Layout.alignment: Qt.AlignVCenter
                        radius: 18
                        color: rma.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.06)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.15)
                        scale: rma.containsMouse ? 1.08 : 1.0

                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }

                        T {
                            anchors.centerIn: parent
                            text: "\uf021"
                            font.pixelSize: 13
                            color: "#ffffff"
                        }
                        MouseArea {
                            id: rma
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: fetchProc.running = true
                        }
                    }

                    // Botão Fechar
                    Rectangle {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        Layout.alignment: Qt.AlignVCenter
                        radius: 18
                        color: cma.containsMouse ? Qt.rgba(1, 0.25, 0.25, 0.35) : Qt.rgba(1, 1, 1, 0.06)
                        border.width: 1
                        border.color: cma.containsMouse ? "#ff4444" : Qt.rgba(1, 1, 1, 0.15)
                        scale: cma.containsMouse ? 1.08 : 1.0

                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }

                        T {
                            anchors.centerIn: parent
                            text: "\uf00d"
                            font.pixelSize: 14
                            color: cma.containsMouse ? "#ff6666" : "#ffffff"
                        }
                        MouseArea {
                            id: cma
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.close()
                        }
                    }
                }

                // Grid de Aplicativos
                GridView {
                    id: grid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    cellWidth: 278
                    cellHeight: 96
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    model: {
                        let source = root.popularApps;
                        if (root.currentTab === 2) source = root.searchResults;
                        else if (root.currentTab === 1) source = root.installedApps;

                        return source.filter(function(app) {
                            if (root.hideThemes && app.is_theme) return false;
                            if (root.hidePlugins && app.is_plugin) return false;
                            return true;
                        });
                    }

                    add: Transition {
                        NumberAnimation { properties: "scale,opacity"; from: 0.85; to: 1.0; duration: 250; easing.type: Easing.OutQuint }
                    }

                    displaced: Transition {
                        NumberAnimation { properties: "x,y"; duration: 250; easing.type: Easing.OutQuint }
                    }

                    delegate: Item {
                        width: 266
                        height: 84

                        readonly property bool isInstallingThis: root.installingAppId === modelData.id

                        Rectangle {
                            id: delegateBg
                            anchors.fill: parent
                            radius: 16
                            color: ma.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.04)
                            border.width: 1
                            border.color: ma.containsMouse ? root.accA(0.65) : Qt.rgba(1, 1, 1, 0.08)
                            scale: ma.containsMouse ? 1.025 : 1.0

                            Behavior on color { ColorAnimation { duration: 180 } }
                            Behavior on border.color { ColorAnimation { duration: 180 } }
                            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutQuint } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 12

                                Rectangle {
                                    Layout.preferredWidth: 46
                                    Layout.preferredHeight: 46
                                    radius: 14
                                    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.2)
                                    border.width: 1
                                    border.color: root.accA(0.4)

                                    Image {
                                        id: appIcon
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        source: modelData.icon || ""
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                        asynchronous: true
                                        visible: status === Image.Ready
                                    }

                                    T {
                                        anchors.centerIn: parent
                                        text: modelData.name ? modelData.name.charAt(0).toUpperCase() : "P"
                                        font.pixelSize: 18
                                        color: root.accent
                                        visible: !appIcon.visible
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        T {
                                            text: modelData.name
                                            color: "#ffffff"
                                            font.pixelSize: 13
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        Rectangle {
                                            visible: !!modelData.is_theme || !!modelData.is_plugin
                                            implicitWidth: badgeTxt.implicitWidth + 8
                                            implicitHeight: 14
                                            radius: 7
                                            color: modelData.is_theme ? Qt.rgba(0.9, 0.5, 0.2, 0.25) : Qt.rgba(1, 1, 1, 0.08)
                                            border.width: 1
                                            border.color: modelData.is_theme ? "#ff9944" : Qt.rgba(1, 1, 1, 0.2)

                                            T {
                                                id: badgeTxt
                                                anchors.centerIn: parent
                                                text: modelData.is_theme ? "TEMA" : "PLUGIN"
                                                color: modelData.is_theme ? "#ffb366" : "#aaaaaa"
                                                font.pixelSize: 7
                                            }
                                        }
                                    }

                                    T {
                                        text: modelData.summary || modelData.id
                                        color: "#777777"
                                        font.pixelSize: 10
                                        font.bold: false
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    RowLayout {
                                        spacing: 6
                                        Rectangle {
                                            implicitWidth: btnText.implicitWidth + 14
                                            implicitHeight: 20
                                            radius: 10
                                            color: modelData.installed ? Qt.rgba(0.2, 0.8, 0.4, 0.2) : (isInstallingThis ? Qt.rgba(0.9, 0.7, 0.2, 0.25) : root.accA(0.35))
                                            border.width: 1
                                            border.color: modelData.installed ? "#44cc77" : (isInstallingThis ? "#ffcc00" : root.accent)

                                            T {
                                                id: btnText
                                                anchors.centerIn: parent
                                                text: modelData.installed ? "Abrir" : (isInstallingThis ? Math.round(root.installProgress * 100) + "%" : "Instalar")
                                                color: modelData.installed ? "#44cc77" : (isInstallingThis ? "#ffcc00" : "#ffffff")
                                                font.pixelSize: 10
                                            }
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: ma
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.installed) {
                                        Quickshell.execDetached(["flatpak", "run", modelData.id]);
                                        root.close();
                                    } else if (!isInstallingThis && root.installingAppId === "") {
                                        root.installingAppId = modelData.id;
                                        root.installingAppName = modelData.name;
                                        root.installProgress = 0.0;
                                        root.installLogs = [">>> Iniciando instalação do " + modelData.name + " (" + modelData.id + ")..."];

                                        installProc.command = [
                                            "sh", "-c",
                                            "flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo && flatpak install --user -y " + modelData.id
                                        ];
                                        installProc.running = true;
                                    }
                                }
                            }
                        }
                    }
                }

                // Painel Inferior de Progresso da Instalação
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    radius: 16
                    color: Qt.rgba(0.08, 0.08, 0.12, 0.95)
                    border.width: 1
                    border.color: root.accA(0.5)
                    visible: root.installingAppId !== ""

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12

                        T {
                            text: "\uf019"
                            font.pixelSize: 15
                            color: root.accent
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            RowLayout {
                                Layout.fillWidth: true
                                T {
                                    text: "Instalando " + root.installingAppName
                                    font.pixelSize: 12
                                    color: "#ffffff"
                                }
                                Item { Layout.fillWidth: true }
                                T {
                                    text: Math.round(root.installProgress * 100) + "%"
                                    font.pixelSize: 11
                                    color: "#aaaaaa"
                                }
                            }

                            // Barra de Progresso
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 6
                                radius: 3
                                color: Qt.rgba(1, 1, 1, 0.1)

                                Rectangle {
                                    height: parent.height
                                    width: Math.max(12, parent.width * Math.min(1.0, Math.max(0.0, root.installProgress)))
                                    radius: 3
                                    color: root.accent

                                    Behavior on width {
                                        NumberAnimation { duration: 150; easing.type: Easing.OutQuint }
                                    }
                                }
                            }
                        }

                        // Botão para ver o Terminal de Erros/Logs
                        Rectangle {
                            Layout.preferredWidth: 100
                            Layout.preferredHeight: 28
                            radius: 14
                            color: logBtnMa.containsMouse ? root.accA(0.4) : Qt.rgba(1, 1, 1, 0.08)
                            border.width: 1
                            border.color: root.accA(0.6)

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6
                                T { text: "\uf120"; font.pixelSize: 11; color: "#ffffff" }
                                T { text: "Terminal"; font.pixelSize: 10; color: "#ffffff" }
                            }

                            MouseArea {
                                id: logBtnMa
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.showTerminalModal = true
                            }
                        }
                    }
                }
            }

            // Popover de Filtros
            Rectangle {
                id: filterPopup
                visible: root.showFilterMenu
                width: 260
                height: 110
                anchors.right: parent.right
                anchors.rightMargin: 60
                anchors.top: parent.top
                anchors.topMargin: 66
                radius: 18
                color: Qt.rgba(0.08, 0.08, 0.1, 0.96)
                border.width: 1
                border.color: root.accA(0.6)
                z: 100

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    T {
                        text: "Filtros de Exibição"
                        font.pixelSize: 12
                        color: "#ffffff"
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        T { text: "Ocultar Temas GTK / Ícones"; font.pixelSize: 11; font.bold: false; color: "#cccccc" }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            width: 38; height: 20; radius: 10
                            color: root.hideThemes ? root.accent : Qt.rgba(1, 1, 1, 0.2)
                            Rectangle {
                                width: 14; height: 14; radius: 7; y: 3
                                x: root.hideThemes ? 21 : 3
                                color: "#ffffff"
                                Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.hideThemes = !root.hideThemes
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        T { text: "Ocultar Plugins / Runtimes"; font.pixelSize: 11; font.bold: false; color: "#cccccc" }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            width: 38; height: 20; radius: 10
                            color: root.hidePlugins ? root.accent : Qt.rgba(1, 1, 1, 0.2)
                            Rectangle {
                                width: 14; height: 14; radius: 7; y: 3
                                x: root.hidePlugins ? 21 : 3
                                color: "#ffffff"
                                Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.hidePlugins = !root.hidePlugins
                            }
                        }
                    }
                }
            }

            // Modal do Terminal de Instalação
            Rectangle {
                id: terminalModal
                anchors.fill: parent
                radius: 28
                color: Qt.rgba(0.05, 0.05, 0.07, 0.97)
                border.width: 1
                border.color: root.accA(0.6)
                visible: root.showTerminalModal
                z: 200

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 12

                    // Cabeçalho do Terminal
                    RowLayout {
                        Layout.fillWidth: true

                        T {
                            text: "\uf120 Terminal de Instalação"
                            font.pixelSize: 14
                            color: root.accent
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            implicitWidth: clearLogsTxt.implicitWidth + 14
                            implicitHeight: 24
                            radius: 12
                            color: clearLogsMa.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.06)

                            T {
                                id: clearLogsTxt
                                anchors.centerIn: parent
                                text: "Limpar Logs"
                                font.pixelSize: 10
                                color: "#888888"
                            }
                            MouseArea {
                                id: clearLogsMa
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.installLogs = []
                            }
                        }

                        Rectangle {
                            width: 28; height: 28; radius: 14
                            color: closeTermMa.containsMouse ? Qt.rgba(1, 0.3, 0.3, 0.3) : Qt.rgba(1, 1, 1, 0.06)

                            T {
                                anchors.centerIn: parent
                                text: "\uf00d"
                                font.pixelSize: 12
                                color: closeTermMa.containsMouse ? "#ff6666" : "#ffffff"
                            }
                            MouseArea {
                                id: closeTermMa
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.showTerminalModal = false
                            }
                        }
                    }

                    // Container de Saída do Terminal
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 14
                        color: "#08080c"
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.1)
                        clip: true

                        ListView {
                            id: logList
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 4
                            model: root.installLogs

                            onCountChanged: {
                                logList.positionViewAtEnd();
                            }

                            delegate: Item {
                                width: logList.width
                                height: logTxt.implicitHeight + 2

                                T {
                                    id: logTxt
                                    width: parent.width
                                    text: modelData
                                    font.pixelSize: 11
                                    font.bold: false
                                    wrapMode: Text.WrapAnywhere
                                    color: modelData.startsWith("[ERRO]") ? "#ff6666" : (modelData.startsWith(">>>") ? root.accent : "#00ff88")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
