import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

// Launcher no estilo da ilha. Abre como uma pílula e cresce até o painel.
//   qs -c launcher            (abre)
//   qs -c launcher kill       (fecha à força)
ShellRoot {
    id: root

    // ---------------- cores (seguem o wallpaper) ----------------
    FileView {
        path: Quickshell.shellPath("../island/colors.json")
        watchChanges: true
        printErrors: false
        adapter: JsonAdapter { id: colorAd; property string accent: "#3948d9" }
    }
    readonly property color accent: colorAd.accent
    readonly property color accentFg:
        (0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b) > 0.6 ? "#000000" : "#ffffff"
    function accA(a) { return Qt.rgba(accent.r, accent.g, accent.b, a); }

    // ---------------- estado ----------------
    property var allApps: []
    property var filteredApps: []
    property int viewMode: 0          // 0 lista, 1 grade, 2 grupos
    property int lastAppView: 0
    property bool showGroups: false
    property string activeGroup: "Todos"
    property var userGroups: []
    property var groupList: []
    property var contextApp: null
    property bool isClosing: false
    property bool introDone: false
    property real reveal: 0

    Behavior on reveal {
        NumberAnimation {
            duration: root.isClosing ? 240 : 560
            easing.type: root.isClosing ? Easing.InCubic : Easing.OutQuint
        }
    }

    Timer { running: true; interval: 30; onTriggered: root.reveal = 1 }
    Timer { running: true; interval: 900; onTriggered: root.introDone = true }
    Timer { id: closeTimer; interval: 260; onTriggered: Qt.quit() }

    Process {
        running: true
        command: ["python3", Quickshell.shellPath("get_apps.py")]
        stdout: SplitParser {
            onRead: data => {
                try {
                    if (data.trim() === "") return;
                    const p = JSON.parse(data);
                    root.userGroups = p.groups;
                    root.groupList = ["Todos", "Favoritos"].concat(p.groups);
                    root.allApps = p.apps;
                    root.filter();
                } catch (e) {}
            }
        }
    }

    function filter() {
        const q = searchInput.text.toLowerCase().trim();
        const out = [];
        for (let i = 0; i < allApps.length; i++) {
            const a = allApps[i];
            const n = a.name.toLowerCase();
            if (q !== "" && n.indexOf(q) < 0) continue;
            if (activeGroup === "Favoritos" && !a.favorite) continue;
            if (activeGroup !== "Todos" && activeGroup !== "Favoritos" && a.category !== activeGroup) continue;
            out.push(a);
        }
        out.sort(function (x, y) {
            if (q !== "") {
                const sx = x.name.toLowerCase().startsWith(q) ? 0 : 1;
                const sy = y.name.toLowerCase().startsWith(q) ? 0 : 1;
                if (sx !== sy) return sx - sy;
            } else if (x.favorite !== y.favorite) {
                return x.favorite ? -1 : 1;
            }
            if (x.uses !== y.uses) return y.uses - x.uses;
            return x.name.toLowerCase() < y.name.toLowerCase() ? -1 : 1;
        });
        filteredApps = out;
        listView.currentIndex = 0;
        gridView.currentIndex = 0;
    }

    function closeLauncher(cmd) {
        if (isClosing) return;
        isClosing = true;
        reveal = 0;
        if (cmd) Quickshell.execDetached(["bash", "-c", cmd]);
        closeTimer.start();
    }

    function launchApp(i) {
        if (i < 0 || i >= filteredApps.length) return;
        const a = filteredApps[i];
        Quickshell.execDetached(["python3", Quickshell.shellPath("get_apps.py"), "used", a.name]);
        closeLauncher(a.exec);
    }

    function toggleFavorite() {
        if (!contextApp) return;
        for (let i = 0; i < allApps.length; i++)
            if (allApps[i].name === contextApp.name) { allApps[i].favorite = !allApps[i].favorite; break; }
        Quickshell.execDetached(["python3", Quickshell.shellPath("get_apps.py"), "fav", contextApp.name]);
        contextApp = null;
        filter();
    }

    function changeGroup(g) {
        if (!contextApp) return;
        for (let i = 0; i < allApps.length; i++)
            if (allApps[i].name === contextApp.name) { allApps[i].category = g; break; }
        Quickshell.execDetached(["python3", Quickshell.shellPath("get_apps.py"), "group", contextApp.name, g]);
        contextApp = null;
        filter();
    }

    function createNewGroup(name) {
        const g = name.trim();
        if (g === "" || userGroups.indexOf(g) >= 0) return;
        userGroups = userGroups.concat([g]);
        groupList = ["Todos", "Favoritos"].concat(userGroups);
        Quickshell.execDetached(["python3", Quickshell.shellPath("get_apps.py"), "new_group", g]);
        newGroupInput.text = "";
    }

    function cycleGroup(dir) {
        const n = groupList.length;
        if (n === 0) return;
        let i = groupList.indexOf(activeGroup);
        if (i < 0) i = 0;
        activeGroup = groupList[(i + dir + n) % n];
        filter();
    }

    function groupIcon(n) {
        switch (n) {
        case "Todos": return "";
        case "Favoritos": return "";
        case "Jogos": return "";
        case "Internet": return "";
        case "Desenvolvimento": return "";
        case "Mídia": return "";
        case "Sistema": return "";
        case "Escritório": return "";
        }
        return "";
    }

    function iconSrc(ic) {
        if (!ic) return "image://icon/application-x-executable";
        if (ic.startsWith("/")) return "file://" + ic;
        if (ic.startsWith("file://")) return ic;
        return "image://icon/" + ic;
    }

    // ---------------- componentes ----------------
    component T: Text {
        color: "#d0d0d0"
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 14
        font.bold: true
        verticalAlignment: Text.AlignVCenter
    }

    component IconButton: Rectangle {
        id: btn
        property string iconStr: ""
        property bool isActive: false
        signal clicked()
        implicitWidth: 34; implicitHeight: 34; radius: 12
        color: btnMa.containsMouse ? "#26ffffff" : "transparent"
        scale: btnMa.pressed ? 0.88 : 1.0
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
        Behavior on color { ColorAnimation { duration: 140 } }
        T {
            anchors.centerIn: parent
            text: btn.iconStr
            font.pixelSize: 16
            color: btn.isActive ? root.accent : (btnMa.containsMouse ? "#ffffff" : "#aaaaaa")
            Behavior on color { ColorAnimation { duration: 140 } }
        }
        MouseArea {
            id: btnMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    // ---------------- janela ----------------
    PanelWindow {
        id: win
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "launcher"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: 0.42 * root.reveal
            MouseArea {
                anchors.fill: parent
                onClicked: root.contextApp ? root.contextApp = null : root.closeLauncher()
            }
        }

        // ---- cartão principal (pílula -> painel) ----
        Rectangle {
            id: box
            readonly property real targetW: root.viewMode === 0 ? 500 : 580
            property real shownW: targetW
            Behavior on shownW { NumberAnimation { duration: 340; easing.type: Easing.OutQuint } }
            readonly property real targetH: mainCol.height + 32

            width: 220 + (shownW - 220) * root.reveal
            height: 46 + (targetH - 46) * root.reveal
            x: (parent.width - width) / 2
            y: parent.height * 0.17

            radius: 26
            color: Qt.rgba(0.03, 0.03, 0.04, 0.78)
            border.width: 1
            border.color: root.accA(0.55)
            clip: true
            opacity: Math.min(1, root.reveal * 3)

            MouseArea { anchors.fill: parent }

            Column {
                id: mainCol
                x: 16
                y: 16
                width: box.shownW - 32
                spacing: 12
                opacity: Math.max(0, (root.reveal - 0.5) / 0.5)

                // ---- busca ----
                Rectangle {
                    width: parent.width
                    height: 48
                    radius: 18
                    color: "#14ffffff"
                    border.width: 1
                    border.color: searchInput.activeFocus ? root.accA(0.8) : "transparent"
                    Behavior on border.color { ColorAnimation { duration: 200 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 8
                        spacing: 10

                        T { text: ""; color: root.accent; font.pixelSize: 17 }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            T {
                                anchors.fill: parent
                                text: "Buscar aplicações..."
                                color: "#666666"
                                font.pixelSize: 16
                                opacity: searchInput.text === "" ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 140 } }
                            }

                            TextInput {
                                id: searchInput
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                color: "#ffffff"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 16
                                font.bold: true
                                clip: true
                                focus: true
                                selectionColor: root.accent
                                selectedTextColor: root.accentFg
                                onTextChanged: root.filter()
                                Component.onCompleted: forceActiveFocus()

                                Keys.onPressed: event => {
                                    const view = root.viewMode === 0 ? listView : (root.viewMode === 1 ? gridView : groupsView);
                                    const cols = root.viewMode === 1 ? 4 : 3;
                                    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                                    const step = root.viewMode > 0 ? cols : 1;

                                    if (event.key === Qt.Key_Escape) {
                                        if (root.contextApp) root.contextApp = null; else root.closeLauncher();
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Down || (ctrl && (event.key === Qt.Key_N || event.key === Qt.Key_J))) {
                                        view.currentIndex = Math.min(view.count - 1, view.currentIndex + step);
                                        view.positionViewAtIndex(view.currentIndex, ListView.Contain);
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Up || (ctrl && (event.key === Qt.Key_P || event.key === Qt.Key_K))) {
                                        view.currentIndex = Math.max(0, view.currentIndex - step);
                                        view.positionViewAtIndex(view.currentIndex, ListView.Contain);
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Right && root.viewMode > 0) {
                                        view.currentIndex = Math.min(view.count - 1, view.currentIndex + 1);
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Left && root.viewMode > 0) {
                                        view.currentIndex = Math.max(0, view.currentIndex - 1);
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Tab) {
                                        root.cycleGroup(1); event.accepted = true;
                                    } else if (event.key === Qt.Key_Backtab) {
                                        root.cycleGroup(-1); event.accepted = true;
                                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                        if (root.viewMode === 2) {
                                            root.activeGroup = root.groupList[view.currentIndex];
                                            root.viewMode = root.lastAppView;
                                            root.filter();
                                        } else {
                                            root.launchApp(view.currentIndex);
                                        }
                                        event.accepted = true;
                                    }
                                }
                            }
                        }

                        IconButton {
                            iconStr: ""
                            isActive: root.showGroups
                            onClicked: { root.showGroups = !root.showGroups; searchInput.forceActiveFocus(); }
                        }
                        IconButton {
                            iconStr: root.viewMode === 0 ? "" : (root.viewMode === 1 ? "" : "")
                            isActive: true
                            onClicked: {
                                root.viewMode = (root.viewMode + 1) % 3;
                                if (root.viewMode !== 2) root.lastAppView = root.viewMode;
                                searchInput.forceActiveFocus();
                            }
                        }
                    }
                }

                // ---- grupos (pílulas) ----
                Item {
                    width: parent.width
                    height: root.showGroups ? groupFlow.implicitHeight : 0
                    opacity: root.showGroups ? 1 : 0
                    visible: height > 0 || opacity > 0
                    clip: true
                    Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                    Behavior on opacity { NumberAnimation { duration: 200 } }

                    Flow {
                        id: groupFlow
                        width: parent.width
                        spacing: 8
                        Repeater {
                            model: root.groupList
                            delegate: Rectangle {
                                id: pill
                                required property string modelData
                                readonly property bool on: root.activeGroup === modelData
                                width: pillText.width + 28
                                height: 30
                                radius: 15
                                color: on ? root.accent : (pillMa.containsMouse ? "#26ffffff" : "transparent")
                                border.width: 1
                                border.color: on ? "transparent" : "#33ffffff"
                                scale: pillMa.pressed ? 0.93 : 1.0
                                Behavior on color { ColorAnimation { duration: 160 } }
                                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                                T {
                                    id: pillText
                                    anchors.centerIn: parent
                                    text: root.groupIcon(pill.modelData) + "  " + pill.modelData
                                    font.pixelSize: 12
                                    color: pill.on ? root.accentFg : "#dddddd"
                                    Behavior on color { ColorAnimation { duration: 160 } }
                                }
                                MouseArea {
                                    id: pillMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.activeGroup = pill.modelData; root.filter(); searchInput.forceActiveFocus(); }
                                }
                            }
                        }
                    }
                }

                // ---- vazio ----
                T {
                    width: parent.width
                    height: (root.filteredApps.length === 0 && root.viewMode !== 2) ? 44 : 0
                    opacity: (root.filteredApps.length === 0 && root.viewMode !== 2) ? 1 : 0
                    visible: opacity > 0
                    text: "Nenhuma aplicação encontrada."
                    color: "#666666"
                    horizontalAlignment: Text.AlignHCenter
                    Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                }

                // ---- modo 0: lista ----
                ListView {
                    id: listView
                    width: parent.width
                    readonly property bool active: root.viewMode === 0 && root.filteredApps.length > 0
                    height: active ? Math.min(6, count) * 50 - 4 : 0
                    opacity: active ? 1 : 0
                    visible: height > 0 || opacity > 0
                    Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    clip: true
                    spacing: 4
                    model: root.filteredApps
                    boundsBehavior: Flickable.StopAtBounds
                    highlightMoveDuration: 190
                    highlightMoveVelocity: -1

                    highlight: Item {
                        width: listView.width
                        height: 46
                        Rectangle {
                            anchors.fill: parent
                            radius: 16
                            color: root.accA(0.20)
                            border.width: 1
                            border.color: root.accA(0.55)
                        }
                    }

                    delegate: Item {
                        id: row
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        height: 46
                        property bool shown: root.introDone
                        Timer {
                            running: !root.introDone
                            interval: 280 + Math.min(row.index, 8) * 40
                            onTriggered: row.shown = true
                        }
                        opacity: shown ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 260 } }
                        transform: Translate {
                            x: row.shown ? 0 : -16
                            Behavior on x { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 14
                            spacing: 14
                            scale: rowMa.containsMouse ? 1.012 : 1.0
                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                            Image {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                source: root.iconSrc(row.modelData.icon)
                                sourceSize.width: 32
                                sourceSize.height: 32
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                onStatusChanged: if (status === Image.Error) source = "image://icon/application-x-executable"
                            }
                            T {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                elide: Text.ElideRight
                                text: row.modelData.name
                                color: "#ffffff"
                            }
                            T {
                                visible: row.modelData.favorite === true
                                text: ""
                                color: "#f1c40f"
                                font.pixelSize: 12
                            }
                            T {
                                text: "↵"
                                color: root.accent
                                font.pixelSize: 16
                                opacity: row.ListView.isCurrentItem ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 160 } }
                            }
                        }

                        MouseArea {
                            id: rowMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onEntered: listView.currentIndex = row.index
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) root.contextApp = row.modelData;
                                else root.launchApp(row.index);
                            }
                        }
                    }
                }

                // ---- modo 1: grade ----
                GridView {
                    id: gridView
                    width: parent.width
                    readonly property bool active: root.viewMode === 1 && root.filteredApps.length > 0
                    height: active ? 380 : 0
                    opacity: active ? 1 : 0
                    visible: height > 0 || opacity > 0
                    Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    clip: true
                    model: root.filteredApps
                    cellWidth: width / 4
                    cellHeight: 110
                    boundsBehavior: Flickable.StopAtBounds
                    highlightMoveDuration: 190
                    highlightMoveVelocity: -1

                    highlight: Item {
                        width: gridView.cellWidth
                        height: gridView.cellHeight
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 5
                            radius: 18
                            color: root.accA(0.20)
                            border.width: 1
                            border.color: root.accA(0.55)
                        }
                    }

                    delegate: Item {
                        id: cell
                        required property var modelData
                        required property int index
                        width: gridView.cellWidth
                        height: gridView.cellHeight
                        property bool shown: root.introDone
                        Timer {
                            running: !root.introDone
                            interval: 280 + Math.min(cell.index, 12) * 30
                            onTriggered: cell.shown = true
                        }
                        opacity: shown ? 1 : 0
                        scale: shown ? 1 : 0.85
                        Behavior on opacity { NumberAnimation { duration: 260 } }
                        Behavior on scale { NumberAnimation { duration: 380; easing.type: Easing.OutBack } }

                        Column {
                            anchors.centerIn: parent
                            spacing: 10
                            scale: cellMa.containsMouse ? 1.06 : 1.0
                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            Image {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 52
                                height: 52
                                source: root.iconSrc(cell.modelData.icon)
                                sourceSize.width: 64
                                sourceSize.height: 64
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                onStatusChanged: if (status === Image.Error) source = "image://icon/application-x-executable"
                            }
                            T {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: cell.width - 20
                                text: cell.modelData.name
                                color: "#ffffff"
                                font.pixelSize: 12
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                        }
                        T {
                            visible: cell.modelData.favorite === true
                            text: ""
                            color: "#f1c40f"
                            font.pixelSize: 11
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 12
                        }
                        MouseArea {
                            id: cellMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onEntered: gridView.currentIndex = cell.index
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) root.contextApp = cell.modelData;
                                else root.launchApp(cell.index);
                            }
                        }
                    }
                }

                // ---- modo 2: grupos ----
                GridView {
                    id: groupsView
                    width: parent.width
                    height: root.viewMode === 2 ? 300 : 0
                    opacity: root.viewMode === 2 ? 1 : 0
                    visible: height > 0 || opacity > 0
                    Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    clip: true
                    model: root.groupList
                    cellWidth: width / 3
                    cellHeight: 96
                    boundsBehavior: Flickable.StopAtBounds
                    highlightMoveDuration: 190
                    highlightMoveVelocity: -1

                    highlight: Item {
                        width: groupsView.cellWidth
                        height: groupsView.cellHeight
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 5
                            radius: 18
                            color: "transparent"
                            border.width: 1
                            border.color: root.accA(0.8)
                        }
                    }

                    delegate: Item {
                        id: gcell
                        required property string modelData
                        required property int index
                        readonly property bool on: root.activeGroup === modelData
                        width: groupsView.cellWidth
                        height: groupsView.cellHeight

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 5
                            radius: 18
                            color: gcell.on ? root.accA(0.35) : (gMa.containsMouse ? "#1effffff" : "#0dffffff")
                            scale: gMa.containsMouse ? 1.04 : 1.0
                            Behavior on color { ColorAnimation { duration: 160 } }
                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            Column {
                                anchors.centerIn: parent
                                spacing: 8
                                T { anchors.horizontalCenter: parent.horizontalCenter; text: root.groupIcon(gcell.modelData); font.pixelSize: 26; color: root.accent }
                                T { anchors.horizontalCenter: parent.horizontalCenter; text: gcell.modelData; font.pixelSize: 12; color: "#ffffff" }
                            }
                        }
                        MouseArea {
                            id: gMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: groupsView.currentIndex = gcell.index
                            onClicked: {
                                root.activeGroup = gcell.modelData;
                                root.viewMode = root.lastAppView;
                                root.filter();
                                searchInput.forceActiveFocus();
                            }
                        }
                    }
                }
            }
        }

        // ---- menu de contexto ----
        Rectangle {
            anchors.fill: parent
            z: 998
            color: "#80000000"
            opacity: root.contextApp !== null ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
            MouseArea { anchors.fill: parent; onClicked: root.contextApp = null }
        }

        Rectangle {
            id: ctxMenu
            z: 999
            width: 340
            height: ctxCol.height + 36
            anchors.centerIn: parent
            radius: 24
            color: Qt.rgba(0.05, 0.05, 0.06, 0.94)
            border.width: 1
            border.color: root.accA(0.6)
            opacity: root.contextApp !== null ? 1 : 0
            scale: root.contextApp !== null ? 1 : 0.88
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            Behavior on scale {
                NumberAnimation {
                    duration: root.contextApp !== null ? 380 : 160
                    easing.type: root.contextApp !== null ? Easing.OutBack : Easing.InCubic
                    easing.overshoot: 1.2
                }
            }
            MouseArea { anchors.fill: parent }

            Column {
                id: ctxCol
                anchors.centerIn: parent
                width: parent.width - 32
                spacing: 14

                T {
                    width: parent.width
                    text: root.contextApp ? root.contextApp.name : ""
                    color: root.accent
                    font.pixelSize: 16
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
                Rectangle { width: parent.width; height: 1; color: "#1affffff" }

                Rectangle {
                    width: parent.width
                    height: 38
                    radius: 12
                    color: favMa.containsMouse ? "#1affffff" : "transparent"
                    border.width: 1
                    border.color: "#33ffffff"
                    scale: favMa.pressed ? 0.97 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    Behavior on color { ColorAnimation { duration: 140 } }
                    T {
                        anchors.centerIn: parent
                        text: (root.contextApp && root.contextApp.favorite) ? "  Remover dos favoritos" : "  Adicionar aos favoritos"
                        color: (root.contextApp && root.contextApp.favorite) ? "#f1c40f" : "#ffffff"
                    }
                    MouseArea { id: favMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleFavorite() }
                }

                T { text: "Mover para o grupo:"; font.pixelSize: 12; color: "#888888" }

                Flow {
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: root.userGroups
                        delegate: Rectangle {
                            id: gp
                            required property string modelData
                            readonly property bool on: root.contextApp !== null && root.contextApp.category === modelData
                            width: gpText.width + 20
                            height: 28
                            radius: 14
                            color: on ? root.accent : (gpMa.containsMouse ? "#26ffffff" : "transparent")
                            border.width: 1
                            border.color: "#33ffffff"
                            scale: gpMa.pressed ? 0.93 : 1.0
                            Behavior on color { ColorAnimation { duration: 140 } }
                            Behavior on scale { NumberAnimation { duration: 120 } }
                            T { id: gpText; anchors.centerIn: parent; text: gp.modelData; font.pixelSize: 12; color: gp.on ? root.accentFg : "#ffffff" }
                            MouseArea { id: gpMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.changeGroup(gp.modelData) }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: "#1affffff" }

                Row {
                    width: parent.width
                    height: 36
                    spacing: 8
                    Rectangle {
                        width: parent.width - 44
                        height: parent.height
                        radius: 12
                        color: "#14ffffff"
                        TextInput {
                            id: newGroupInput
                            anchors.fill: parent
                            anchors.margins: 10
                            color: "#ffffff"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 14
                            verticalAlignment: Text.AlignVCenter
                            clip: true
                            onAccepted: root.createNewGroup(text)
                            Text {
                                text: "Criar novo grupo..."
                                color: "#666666"
                                font: newGroupInput.font
                                visible: newGroupInput.text === ""
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                    Rectangle {
                        width: 36
                        height: 36
                        radius: 12
                        color: addMa.containsMouse ? root.accent : "#26ffffff"
                        scale: addMa.pressed ? 0.9 : 1.0
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Behavior on scale { NumberAnimation { duration: 120 } }
                        T { anchors.centerIn: parent; text: ""; color: addMa.containsMouse ? root.accentFg : "#ffffff" }
                        MouseArea { id: addMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.createNewGroup(newGroupInput.text) }
                    }
                }
            }
        }
    }
}
