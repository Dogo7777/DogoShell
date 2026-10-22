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

    function accA(a) {
        return Qt.rgba(accent.r, accent.g, accent.b, a);
    }

    property var desktopList: []
    property var iconList: []
    property string sidebarSearch: ""
    property string iconModalSearch: ""
    property string targetPath: ""

    property string appName: ""
    property string appExec: ""
    property string appIcon: ""
    property string appComment: ""
    property string appCategories: ""
    property bool appTerminal: false
    property string statusMsg: ""
    property bool showIconPicker: false

    property real reveal: 0
    property bool closing: false

    Behavior on reveal {
        NumberAnimation {
            duration: root.closing ? 200 : 480
            easing.type: root.closing ? Easing.InCubic : Easing.OutQuint
        }
    }

    Timer {
        running: true
        interval: 30
        onTriggered: {
            root.reveal = 1;
            listProc.running = true;
            iconsProc.running = true;
        }
    }

    Timer {
        id: quitTimer
        interval: 220
        onTriggered: Qt.quit()
    }

    Timer {
        id: statusClearTimer
        interval: 2800
        repeat: false
        onTriggered: { root.statusMsg = ""; }
    }

    function close() {
        if (closing) return;
        closing = true;
        reveal = 0;
        quitTimer.start();
    }

    function loadSelected(path) {
        root.targetPath = path;
        loadProc.command = ["python3", Quickshell.shellPath("editor_backend.py"), "load", path];
        loadProc.running = true;
    }

    function createNew() {
        root.targetPath = "~/.local/share/applications/novo-app.desktop";
        root.appName = "Novo Aplicativo";
        root.appExec = "";
        root.appIcon = "application-x-executable";
        root.appComment = "";
        root.appCategories = "Utility;";
        root.appTerminal = false;
        root.statusMsg = "Criando novo atalho...";
        statusClearTimer.restart();
    }

    function saveChanges() {
        if (root.targetPath === "") return;
        const payload = JSON.stringify({
            "name": root.appName,
            "exec": root.appExec,
            "icon": root.appIcon,
            "comment": root.appComment,
            "categories": root.appCategories,
            "terminal": root.appTerminal
        });
        saveProc.command = ["python3", Quickshell.shellPath("editor_backend.py"), "save", root.targetPath, payload];
        saveProc.running = true;
    }

    function resolveIconSource(iconName) {
        if (!iconName) return "";
        if (iconName.startsWith("/") || iconName.startsWith("file://")) {
            return iconName.startsWith("file://") ? iconName : "file://" + iconName;
        }
        return "file:///usr/share/icons/hicolor/48x48/apps/" + iconName + ".png";
    }

    function filteredDesktops() {
        const q = root.sidebarSearch.toLowerCase();
        return root.desktopList.filter(function(item) {
            if (q === "") return true;
            return (item.name && item.name.toLowerCase().indexOf(q) !== -1) ||
                   (item.filename && item.filename.toLowerCase().indexOf(q) !== -1);
        });
    }

    function filteredIcons() {
        const q = root.iconModalSearch.toLowerCase();
        return root.iconList.filter(function(iconName) {
            if (q === "") return true;
            return iconName.toLowerCase().indexOf(q) !== -1;
        });
    }

    Process {
        id: listProc
        command: ["python3", Quickshell.shellPath("editor_backend.py"), "list"]
        stdout: SplitParser {
            onRead: function(data) {
                try {
                    if (data.trim() !== "") {
                        root.desktopList = JSON.parse(data.trim());
                        if (root.desktopList.length > 0 && root.targetPath === "") {
                            root.loadSelected(root.desktopList[0].path);
                        }
                    }
                } catch(e) {}
            }
        }
    }

    Process {
        id: iconsProc
        command: ["python3", Quickshell.shellPath("editor_backend.py"), "icons"]
        stdout: SplitParser {
            onRead: function(data) {
                try {
                    if (data.trim() !== "") {
                        root.iconList = JSON.parse(data.trim());
                    }
                } catch(e) {}
            }
        }
    }

    Process {
        id: loadProc
        stdout: SplitParser {
            onRead: function(data) {
                try {
                    const res = JSON.parse(data.trim());
                    root.appName = res.name || "";
                    root.appExec = res.exec || "";
                    root.appIcon = res.icon || "";
                    root.appComment = res.comment || "";
                    root.appCategories = res.categories || "Utility;";
                    root.appTerminal = !!res.terminal;
                } catch(e) {}
            }
        }
    }

    Process {
        id: saveProc
        stdout: SplitParser {
            onRead: function(data) {
                try {
                    const res = JSON.parse(data.trim());
                    if (res.success) {
                        if (res.path) root.targetPath = res.path;
                        root.statusMsg = "Salvo com sucesso!";
                        listProc.running = true;
                    } else {
                        root.statusMsg = "Erro: " + (res.error || "Falha ao salvar");
                    }
                    statusClearTimer.restart();
                } catch(e) {
                    root.statusMsg = "Erro no salvamento";
                    statusClearTimer.restart();
                }
            }
        }
    }

    component T: Text {
        color: "#d8d8d8"
        font.family: "JetBrainsMono Nerd Font, JetBrainsMonoNF, Symbols Nerd Font, sans-serif"
        font.pixelSize: 12
        font.bold: true
        verticalAlignment: Text.AlignVCenter
    }

    PanelWindow {
        id: win
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "desktop-editor"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: 0.45 * root.reveal
            Behavior on opacity { NumberAnimation { duration: 200 } }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (root.showIconPicker) root.showIconPicker = false;
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
                    if (root.showIconPicker) {
                        root.showIconPicker = false;
                    } else {
                        root.close();
                    }
                    event.accepted = true;
                }
            }
        }

        Rectangle {
            id: card
            width: 820
            height: 540
            anchors.centerIn: parent
            radius: 24
            color: Qt.rgba(0.04, 0.04, 0.06, 0.94)
            border.width: 1
            border.color: root.accA(0.5)
            scale: 0.92 + 0.08 * root.reveal
            opacity: Math.min(1, root.reveal * 2)

            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16

                // BARRA LATERAL (LISTA DE ATALHOS)
                ColumnLayout {
                    Layout.preferredWidth: 260
                    Layout.fillHeight: true
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        T {
                            text: "Atalhos"
                            font.pixelSize: 14
                            color: "#ffffff"
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            width: 28; height: 28; radius: 14
                            color: newBtnMa.containsMouse ? root.accA(0.4) : Qt.rgba(1, 1, 1, 0.08)
                            border.width: 1; border.color: root.accA(0.5)
                            scale: newBtnMa.containsMouse ? 1.08 : 1.0
                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }

                            T { anchors.centerIn: parent; text: "\uf067"; font.pixelSize: 12; color: "#ffffff" }
                            MouseArea {
                                id: newBtnMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: root.createNew()
                            }
                        }
                    }

                    // Busca na Sidebar
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        radius: 12
                        color: Qt.rgba(1, 1, 1, 0.06)
                        border.width: 1
                        border.color: sideSearchIn.activeFocus ? root.accA(0.8) : Qt.rgba(1, 1, 1, 0.12)
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        Item {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10

                            TextInput {
                                id: sideSearchIn
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                color: "#ffffff"
                                font.family: "JetBrainsMono Nerd Font, sans-serif"
                                font.pixelSize: 11
                                onTextChanged: { root.sidebarSearch = text.trim(); }
                            }

                            T {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Filtrar atalhos..."
                                color: "#555555"
                                font.pixelSize: 11
                                visible: sideSearchIn.text === ""
                            }
                        }
                    }

                    // Lista de Aplicativos
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 14
                        color: Qt.rgba(0, 0, 0, 0.25)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.08)
                        clip: true

                        ListView {
                            id: sideList
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 4
                            boundsBehavior: Flickable.StopAtBounds

                            model: root.filteredDesktops()

                            delegate: Rectangle {
                                width: sideList.width
                                height: 38
                                radius: 10
                                readonly property bool isSelected: root.targetPath === modelData.path
                                color: isSelected ? root.accA(0.35) : (itemMa.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                                border.width: isSelected ? 1 : 0
                                border.color: root.accent

                                Behavior on color { ColorAnimation { duration: 150 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 8

                                    T {
                                        text: modelData.name
                                        font.pixelSize: 11
                                        color: isSelected ? "#ffffff" : "#cccccc"
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    Rectangle {
                                        visible: !!modelData.is_user
                                        implicitWidth: 8; implicitHeight: 8; radius: 4
                                        color: root.accent
                                    }
                                }

                                MouseArea {
                                    id: itemMa
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.loadSelected(modelData.path)
                                }
                            }
                        }
                    }
                }

                // Divisória Vertical
                Rectangle {
                    Layout.fillHeight: true
                    width: 1
                    color: Qt.rgba(1, 1, 1, 0.1)
                }

                // PAINEL PRINCIPAL (FORMULÁRIO DE EDIÇÃO)
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 14

                    RowLayout {
                        Layout.fillWidth: true

                        T {
                            text: "\uf013 " + (root.appName || "Editor de Atalhos")
                            font.pixelSize: 14
                            color: "#ffffff"
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            width: 28; height: 28; radius: 14
                            color: closeMa.containsMouse ? Qt.rgba(1, 0.25, 0.25, 0.3) : Qt.rgba(1, 1, 1, 0.06)

                            T {
                                anchors.centerIn: parent
                                text: "\uf00d"
                                font.pixelSize: 12
                                color: closeMa.containsMouse ? "#ff6666" : "#ffffff"
                            }
                            MouseArea {
                                id: closeMa
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.close()
                            }
                        }
                    }

                    // Campos do Formulário
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 10

                        // Nome
                        RowLayout {
                            Layout.fillWidth: true
                            T { text: "Nome:"; Layout.preferredWidth: 90; color: "#aaaaaa" }
                            Rectangle {
                                Layout.fillWidth: true; height: 34; radius: 10
                                color: Qt.rgba(1, 1, 1, 0.06); border.width: 1; border.color: nameIn.activeFocus ? root.accA(0.8) : Qt.rgba(1, 1, 1, 0.15)
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                TextInput {
                                    id: nameIn
                                    anchors.fill: parent; anchors.margins: 8; verticalAlignment: Text.AlignVCenter
                                    color: "#ffffff"; font.pixelSize: 12; text: root.appName
                                    onTextChanged: { root.appName = text; }
                                }
                            }
                        }

                        // Comando (Exec)
                        RowLayout {
                            Layout.fillWidth: true
                            T { text: "Comando:"; Layout.preferredWidth: 90; color: "#aaaaaa" }
                            Rectangle {
                                Layout.fillWidth: true; height: 34; radius: 10
                                color: Qt.rgba(1, 1, 1, 0.06); border.width: 1; border.color: execIn.activeFocus ? root.accA(0.8) : Qt.rgba(1, 1, 1, 0.15)
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                TextInput {
                                    id: execIn
                                    anchors.fill: parent; anchors.margins: 8; verticalAlignment: Text.AlignVCenter
                                    color: "#ffffff"; font.pixelSize: 12; text: root.appExec
                                    onTextChanged: { root.appExec = text; }
                                }
                            }
                        }

                        // Ícone
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            T { text: "Ícone:"; Layout.preferredWidth: 90; color: "#aaaaaa" }

                            Rectangle {
                                Layout.preferredWidth: 36
                                Layout.preferredHeight: 34
                                radius: 10
                                color: iconPickMa.containsMouse ? root.accA(0.4) : Qt.rgba(1, 1, 1, 0.08)
                                border.width: 1
                                border.color: root.accA(0.6)
                                scale: iconPickMa.containsMouse ? 1.08 : 1.0
                                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }

                                Image {
                                    id: iconPrev
                                    anchors.fill: parent
                                    anchors.margins: 5
                                    source: root.resolveIconSource(root.appIcon)
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    asynchronous: true
                                    visible: status === Image.Ready
                                }

                                T {
                                    anchors.centerIn: parent
                                    text: "\uf03e"
                                    font.pixelSize: 14
                                    color: root.accent
                                    visible: !iconPrev.visible
                                }

                                MouseArea {
                                    id: iconPickMa
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.showIconPicker = true
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true; height: 34; radius: 10
                                color: Qt.rgba(1, 1, 1, 0.06); border.width: 1; border.color: iconIn.activeFocus ? root.accA(0.8) : Qt.rgba(1, 1, 1, 0.15)
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                TextInput {
                                    id: iconIn
                                    anchors.fill: parent; anchors.margins: 8; verticalAlignment: Text.AlignVCenter
                                    color: "#ffffff"; font.pixelSize: 12; text: root.appIcon
                                    onTextChanged: { root.appIcon = text; }
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: 80
                                Layout.preferredHeight: 34
                                radius: 10
                                color: iconBtnMa.containsMouse ? root.accA(0.4) : Qt.rgba(1, 1, 1, 0.08)
                                border.width: 1
                                border.color: root.accA(0.5)

                                T { anchors.centerIn: parent; text: "Escolher"; font.pixelSize: 11; color: "#ffffff" }
                                MouseArea {
                                    id: iconBtnMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.showIconPicker = true
                                }
                            }
                        }

                        // Comentário
                        RowLayout {
                            Layout.fillWidth: true
                            T { text: "Comentário:"; Layout.preferredWidth: 90; color: "#aaaaaa" }
                            Rectangle {
                                Layout.fillWidth: true; height: 34; radius: 10
                                color: Qt.rgba(1, 1, 1, 0.06); border.width: 1; border.color: commIn.activeFocus ? root.accA(0.8) : Qt.rgba(1, 1, 1, 0.15)
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                TextInput {
                                    id: commIn
                                    anchors.fill: parent; anchors.margins: 8; verticalAlignment: Text.AlignVCenter
                                    color: "#ffffff"; font.pixelSize: 12; text: root.appComment
                                    onTextChanged: { root.appComment = text; }
                                }
                            }
                        }

                        // Categorias
                        RowLayout {
                            Layout.fillWidth: true
                            T { text: "Categorias:"; Layout.preferredWidth: 90; color: "#aaaaaa" }
                            Rectangle {
                                Layout.fillWidth: true; height: 34; radius: 10
                                color: Qt.rgba(1, 1, 1, 0.06); border.width: 1; border.color: catIn.activeFocus ? root.accA(0.8) : Qt.rgba(1, 1, 1, 0.15)
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                TextInput {
                                    id: catIn
                                    anchors.fill: parent; anchors.margins: 8; verticalAlignment: Text.AlignVCenter
                                    color: "#ffffff"; font.pixelSize: 12; text: root.appCategories
                                    onTextChanged: { root.appCategories = text; }
                                }
                            }
                        }

                        // Executar no Terminal
                        RowLayout {
                            Layout.fillWidth: true
                            T { text: "Executar no Terminal"; color: "#cccccc" }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                width: 38; height: 20; radius: 10
                                color: root.appTerminal ? root.accent : Qt.rgba(1, 1, 1, 0.2)
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Rectangle {
                                    width: 14; height: 14; radius: 7; y: 3
                                    x: root.appTerminal ? 21 : 3
                                    color: "#ffffff"
                                    Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.appTerminal = !root.appTerminal
                                }
                            }
                        }
                    }

                    // Rodapé com Ações
                    RowLayout {
                        Layout.fillWidth: true

                        T {
                            text: root.statusMsg
                            color: root.accent
                            font.pixelSize: 11
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            implicitWidth: 80; implicitHeight: 32; radius: 12
                            color: cancelMa.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
                            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.15)

                            T { anchors.centerIn: parent; text: "Cancelar"; font.pixelSize: 11; color: "#aaaaaa" }
                            MouseArea {
                                id: cancelMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: root.close()
                            }
                        }

                        Rectangle {
                            implicitWidth: 90; implicitHeight: 32; radius: 12
                            color: saveMa.containsMouse ? root.accA(0.7) : root.accent
                            scale: saveMa.containsMouse ? 1.05 : 1.0
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuint } }

                            T { anchors.centerIn: parent; text: "Salvar"; font.pixelSize: 11; color: "#ffffff" }
                            MouseArea {
                                id: saveMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: root.saveChanges()
                            }
                        }
                    }
                }
            }

            // MODAL SELETOR VISUAL DE ÍCONES (GALLERY)
            Rectangle {
                id: iconPickerModal
                anchors.fill: parent
                radius: 24
                color: Qt.rgba(0.05, 0.05, 0.08, 0.96)
                border.width: 1
                border.color: root.accA(0.6)
                visible: root.showIconPicker
                z: 200

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true

                        T {
                            text: "\uf03e Seletor de Ícones do Sistema"
                            font.pixelSize: 14
                            color: root.accent
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            width: 28; height: 28; radius: 14
                            color: closePickerMa.containsMouse ? Qt.rgba(1, 0.25, 0.25, 0.3) : Qt.rgba(1, 1, 1, 0.06)

                            T {
                                anchors.centerIn: parent
                                text: "\uf00d"
                                font.pixelSize: 12
                                color: closePickerMa.containsMouse ? "#ff6666" : "#ffffff"
                            }
                            MouseArea {
                                id: closePickerMa
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.showIconPicker = false
                            }
                        }
                    }

                    // Campo de Pesquisa do Modal
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        radius: 12
                        color: Qt.rgba(1, 1, 1, 0.06)
                        border.width: 1
                        border.color: iconSearchIn.activeFocus ? root.accA(0.8) : Qt.rgba(1, 1, 1, 0.15)

                        Item {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12

                            TextInput {
                                id: iconSearchIn
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                color: "#ffffff"
                                font.family: "JetBrainsMono Nerd Font, sans-serif"
                                font.pixelSize: 12
                                onTextChanged: { root.iconModalSearch = text.trim(); }
                            }

                            T {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Pesquisar nome do ícone..."
                                color: "#555555"
                                font.pixelSize: 12
                                visible: iconSearchIn.text === ""
                            }
                        }
                    }

                    // Grid de Ícones
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 14
                        color: "#08080c"
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.1)
                        clip: true

                        GridView {
                            id: iconGrid
                            anchors.fill: parent
                            anchors.margins: 10
                            cellWidth: 76
                            cellHeight: 76
                            boundsBehavior: Flickable.StopAtBounds

                            model: root.filteredIcons()

                            delegate: Item {
                                width: 70
                                height: 70

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 12
                                    color: iconTileMa.containsMouse ? root.accA(0.35) : Qt.rgba(1, 1, 1, 0.04)
                                    border.width: 1
                                    border.color: iconTileMa.containsMouse ? root.accent : Qt.rgba(1, 1, 1, 0.08)
                                    scale: iconTileMa.containsMouse ? 1.1 : 1.0

                                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuint } }
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        spacing: 2

                                        Item {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true

                                            Image {
                                                id: tileImg
                                                anchors.centerIn: parent
                                                width: 32; height: 32
                                                source: root.resolveIconSource(modelData)
                                                fillMode: Image.PreserveAspectFit
                                                smooth: true
                                                asynchronous: true
                                                visible: status === Image.Ready
                                            }

                                            T {
                                                anchors.centerIn: parent
                                                text: modelData.charAt(0).toUpperCase()
                                                font.pixelSize: 14
                                                color: root.accent
                                                visible: !tileImg.visible
                                            }
                                        }

                                        T {
                                            text: modelData
                                            font.pixelSize: 8
                                            font.bold: false
                                            color: "#aaaaaa"
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                    }

                                    MouseArea {
                                        id: iconTileMa
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.appIcon = modelData;
                                            root.showIconPicker = false;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
