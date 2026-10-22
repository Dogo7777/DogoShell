import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

ShellRoot {
    id: root

    // Monitoramento reativo em tempo real do style.json
    FileView {
        id: styleFile
        path: Quickshell.env("HOME") + "/.config/quickshell/style.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        adapter: JsonAdapter {
            id: styleAd
            property real scale: 1.0
            property string bar_mode: "island"
            property string bar_position: "top"
            property bool bar_full_width: false
            property bool bar_floating: true
            property int bar_margin: 6
            property real bar_opacity: 0.55
            property bool show_clock_date: false
        }
    }
    readonly property real rs: styleAd.scale
    readonly property real bgAlpha: styleAd.bar_opacity !== undefined ? styleAd.bar_opacity : 0.55

    readonly property int animMs: 550        
    readonly property int minWorkspaces: 4   
    readonly property int panelW: 400        
    readonly property int topH: 36           

    FileView {
        id: colorFile
        path: Quickshell.shellPath("colors.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        adapter: JsonAdapter {
            property string accent: "#3948d9"
            property string accent2: "#d95667"
        }
    }

    readonly property color accentRaw: colorFile.adapter.accent
    property color accent: accentRaw
    Behavior on accent { ColorAnimation { duration: 700 } }
    readonly property color accentFg:
        (0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b) > 0.6 ? "#000000" : "#ffffff"

    property string cpu: "0"
    property string mem: "0"
    property string temp: "0"
    property string disk: "0"
    property string iface: "offline"
    
    property bool dndEnabled: false
    property bool wifiOn: false
    property bool btOn: false
    property bool nightOn: false
    property real brightPct: -1
    property int clearedId: 0
    
    property var notifications: []
    property bool showNotifs: false

    readonly property string notifCmd: "makoctl history | jq -c '[.data[0][]? | {id: (.id.data|tostring), app: (.\"app-name\".data | if type == \"null\" then \"Sistema\" else . end), summary: (.summary.data | if type == \"null\" then \"\" else . end), body: (.body.data | if type == \"null\" then \"\" else . end)}] | reverse | .[0:15]' 2>/dev/null || echo '[]'"

    Process {
        id: notifProc
        command: ["bash", "-c", root.notifCmd]
        stdout: StdioCollector {
            onStreamFinished: function() {
                try {
                    const arr = JSON.parse(text.trim());
                    root.notifications = arr.filter(function(n) { return Number(n.id) > root.clearedId; });
                } catch (e) {}
            }
        }
    }

    Process {
        id: dndProc
        command: ["bash", "-c", "makoctl mode | grep -q dnd && echo true || echo false"]
        stdout: StdioCollector { onStreamFinished: function() { root.dndEnabled = text.trim() === "true"; } }
    }

    Process {
        id: stateProc
        command: ["bash", "-c", "echo \"wifi=$(nmcli -t -f WIFI radio 2>/dev/null | head -1) bt=$(bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && echo on || echo off) night=$(pgrep -x hyprsunset >/dev/null && echo on || echo off) bright=$(brightnessctl -m -c backlight 2>/dev/null | head -1 | cut -d, -f4 | tr -d %)\""]
        stdout: StdioCollector {
            onStreamFinished: function() {
                const m = {};
                text.trim().split(" ").forEach(function(kv) {
                    const i = kv.indexOf("=");
                    if (i > 0) m[kv.slice(0, i)] = kv.slice(i + 1);
                });
                root.wifiOn = m.wifi === "enabled";
                root.btOn = m.bt === "on";
                root.nightOn = m.night === "on";
                root.brightPct = (m.bright && !isNaN(Number(m.bright))) ? Number(m.bright) : -1;
            }
        }
    }

    function fetchNotifs() { if (!notifProc.running) notifProc.running = true; }
    function refreshState() {
        if (!dndProc.running) dndProc.running = true;
        if (!stateProc.running) stateProc.running = true;
    }
    Timer { id: stateSoon; interval: 800; onTriggered: root.refreshState() }

    function brightSet(r) {
        const p = Math.max(1, Math.min(100, Math.round(r * 100)));
        brightPct = p;
        Quickshell.execDetached(["brightnessctl", "-c", "backlight", "set", p + "%"]);
    }
    function toggleWifi() {
        wifiOn = !wifiOn;
        Quickshell.execDetached(["nmcli", "radio", "wifi", wifiOn ? "on" : "off"]);
        stateSoon.restart();
    }
    function toggleBt() {
        btOn = !btOn;
        Quickshell.execDetached(["bluetoothctl", "power", btOn ? "on" : "off"]);
        stateSoon.restart();
    }
    function toggleNight() {
        if (nightOn) Quickshell.execDetached(["pkill", "-x", "hyprsunset"]);
        else Quickshell.execDetached(["hyprsunset", "-t", "4000"]);
        nightOn = !nightOn;
        stateSoon.restart();
    }
    function after(cmd) {
        island.expanded = false;
        Quickshell.execDetached(["sh", "-c", "sleep 0.45; " + cmd]);
    }

    Process {
        running: true
        command: ["bash", Quickshell.shellPath("stats.sh")]
        stdout: SplitParser {
            onRead: function(data) {
                const p = data.trim().split(" ");
                if (p.length < 5) return;
                root.cpu = p[0]; root.mem = p[1]; root.temp = p[2];
                root.disk = p[3]; root.iface = p[4];
            }
        }
    }
    
    Timer {
        interval: 8000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: function() { root.refreshState(); root.fetchNotifs(); }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real vol: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
    
    function setVol(v) {
        if (sink && sink.audio) sink.audio.volume = Math.max(0, Math.min(1, v));
    }

    property var wsIds: {
        const set = {};
        for (let i = 1; i <= root.minWorkspaces; i++) set[i] = true;
        const v = Hyprland.workspaces.values;
        for (let i = 0; i < v.length; i++)
            if (v[i].id > 0) set[v[i].id] = true;
        const f = Hyprland.focusedWorkspace;
        if (f && f.id > 0) set[f.id] = true;
        return Object.keys(set).map(Number).sort(function(a, b) { return a - b; });
    }
    readonly property int wsCount: wsIds.length

    property var player: {
        const v = Mpris.players.values;
        for (let i = 0; i < v.length; i++)
            if (v[i].playbackState === MprisPlaybackState.Playing) return v[i];
        return v.length > 0 ? v[0] : null;
    }
    readonly property bool playing:
        player !== null && player.playbackState === MprisPlaybackState.Playing
    
    readonly property real trackLen: {
        if (!player) return 0;
        if (player.length > 0) return player.length;
        const m = player.metadata;
        const l = m ? Number(m["mpris:length"]) : 0;
        return l > 0 ? l / 1000000 : 0;
    }
    readonly property real ratio:
        trackLen > 0 ? Math.min(1, player.position / trackLen) : 0

    Timer {
        interval: 500
        repeat: true
        running: root.playing && island.expanded
        onTriggered: root.player.positionChanged()
    }

    property real seekHold: -1
    Timer { id: holdTimer; interval: 900; onTriggered: root.seekHold = -1 }
    Timer { id: refreshTimer; interval: 250; onTriggered: if (root.player) root.player.positionChanged() }
    function seekTo(ratio) {
        const p = player;
        if (!p || trackLen <= 0) return;
        const t = Math.max(0, Math.min(trackLen - 1, ratio * trackLen));
        const name = (p.dbusName || "").replace("org.mpris.MediaPlayer2.", "");
        Quickshell.execDetached(["playerctl", "-p", name, "position", t.toFixed(2)]);
        seekHold = t / trackLen;
        holdTimer.restart();
        refreshTimer.restart();
    }

    property bool caffeine: false   
    property int menuOpen: 0        

    function fmt(s) {
        s = Math.max(0, Math.floor(s || 0));
        const m = Math.floor(s / 60), r = s % 60;
        return m + ":" + (r < 10 ? "0" : "") + r;
    }

    component T: Text {
        color: "#d0d0d0"
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 13
        font.bold: true
        verticalAlignment: Text.AlignVCenter
    }

    component IconButton: Rectangle {
        id: btn
        property alias text: lbl.text
        property color fg: "#ffffff"
        property color hoverFg: fg
        property real iconSize: 15
        property bool active: false
        signal clicked()
        radius: (height / 2) * root.rs
        color: active ? root.accent : (ma.containsMouse ? "#26ffffff" : "transparent")
        scale: ma.pressed ? 0.88 : 1
        Behavior on color { ColorAnimation { duration: 180 } }
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        T {
            id: lbl
            anchors.centerIn: parent
            color: active ? root.accentFg : (ma.containsMouse ? btn.hoverFg : btn.fg)
            font.pixelSize: btn.iconSize
            Behavior on color { ColorAnimation { duration: 180 } }
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    component Track: Item {
        id: trk
        property real value: 0          
        property bool animate: true
        signal moved(real ratio)        
        signal committed(real ratio)    
        implicitHeight: 22

        readonly property alias pressed: tma.pressed
        readonly property alias hovered: tma.containsMouse
        readonly property real shown: tma.pressed ? Math.max(0, Math.min(1, tma.mouseX / width)) : value

        Rectangle {
            id: rail
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: tma.containsMouse || tma.pressed ? 7 : 4
            radius: (height / 2) * root.rs
            color: "#2effffff"
            Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

            Rectangle {
                width: rail.width * trk.shown
                height: parent.height
                radius: parent.radius
                color: root.accent
                Behavior on width {
                    enabled: trk.animate && !tma.pressed
                    NumberAnimation { duration: 400 }
                }
            }
        }

        Rectangle {
            width: 12
            height: 12
            radius: (6) * root.rs
            color: "#ffffff"
            anchors.verticalCenter: parent.verticalCenter
            x: rail.width * trk.shown - 6
            opacity: tma.containsMouse || tma.pressed ? 1 : 0
            scale: tma.pressed ? 1.25 : 1
            Behavior on opacity { NumberAnimation { duration: 150 } }
            Behavior on scale { NumberAnimation { duration: 120 } }
        }

        MouseArea {
            id: tma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: function(mouse) { trk.moved(Math.max(0, Math.min(1, mouse.x / width))); }
            onPositionChanged: function(mouse) {
                if (pressed) trk.moved(Math.max(0, Math.min(1, mouse.x / width)));
            }
            onReleased: function(mouse) { trk.committed(Math.max(0, Math.min(1, mouse.x / width))); }
        }
    }

    component Tile: Rectangle {
        id: tile
        property string icon: ""
        property string label: ""
        property bool active: false
        signal clicked()
        Layout.fillWidth: true
        Layout.preferredHeight: 50
        radius: (14) * root.rs
        color: active ? root.accent : (tileMa.containsMouse ? "#26ffffff" : "#14ffffff")
        scale: tileMa.pressed ? 0.93 : 1
        Behavior on color { ColorAnimation { duration: 200 } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
        Column {
            anchors.centerIn: parent
            spacing: 3
            T { anchors.horizontalCenter: parent.horizontalCenter; text: tile.icon; font.pixelSize: 16; color: tile.active ? root.accentFg : "#e0e0e0" }
            T { anchors.horizontalCenter: parent.horizontalCenter; text: tile.label; font.pixelSize: 9; color: tile.active ? root.accentFg : "#9a9a9a" }
        }
        MouseArea {
            id: tileMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.clicked()
        }
    }

    PanelWindow {
        id: win

        anchors.top: styleAd.bar_position !== "bottom"
        anchors.bottom: styleAd.bar_position === "bottom"
        anchors.left: true
        anchors.right: true

        margins.top: (styleAd.bar_position !== "bottom" && styleAd.bar_floating) ? styleAd.bar_margin : 0
        margins.bottom: (styleAd.bar_position === "bottom" && styleAd.bar_floating) ? styleAd.bar_margin : 0
        margins.left: styleAd.bar_floating ? styleAd.bar_margin : 0
        margins.right: styleAd.bar_floating ? styleAd.bar_margin : 0

        implicitHeight: 520
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "island"

        mask: Region { item: island }

        IdleInhibitor {
            enabled: root.caffeine
            window: win
        }

        Rectangle {
            id: island
            property bool expanded: false
            property real reveal: expanded ? 1 : 0
            
            readonly property bool isBarMode: styleAd.bar_mode === "bar" || styleAd.bar_full_width
            readonly property bool isBottom: styleAd.bar_position === "bottom"

            onExpandedChanged: {
                if (!expanded) root.showNotifs = false;
                else fetchNotifs();
            }
            
            Behavior on reveal {
                NumberAnimation {
                    duration: island.expanded ? root.animMs + 150 : 250
                    easing.type: Easing.OutCubic
                }
            }
            function stag(i) {
                return Math.max(0, Math.min(1, (reveal - i * 0.10) / 0.5));
            }

            readonly property real pad: 14
            readonly property real sideW: Math.max(100, root.wsCount * 24 + 16)
            readonly property real collapsedW: 2 * sideW + clockText.implicitWidth + 2 * pad + 12
            readonly property real expandedW: Math.max(root.panelW, collapsedW)

            anchors.top: isBottom ? undefined : parent.top
            anchors.bottom: isBottom ? parent.bottom : undefined
            
            anchors.horizontalCenter: isBarMode ? undefined : parent.horizontalCenter
            anchors.left: isBarMode ? parent.left : undefined
            anchors.right: isBarMode ? parent.right : undefined

            clip: true

            width: isBarMode ? parent.width : (expanded ? expandedW : collapsedW)
            height: expanded ? root.topH + mainContent.height + 16 : root.topH
            
            radius: {
                if (isBarMode) {
                    return styleAd.bar_floating ? Math.round(14 * root.rs) : 0;
                } else {
                    return (expanded ? 26 : root.topH / 2) * root.rs;
                }
            }
            color: Qt.rgba(0, 0, 0, root.bgAlpha)
            
            border.width: styleAd.bar_floating || !isBarMode ? 1 : 0
            border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55)
            Behavior on border.color { ColorAnimation { duration: 300 } }

            Behavior on width {
                NumberAnimation { duration: root.animMs; easing.type: island.expanded ? Easing.OutQuint : Easing.InOutCubic }
            }
            Behavior on height {
                NumberAnimation { duration: root.animMs; easing.type: island.expanded ? Easing.OutQuint : Easing.InOutCubic }
            }
            Behavior on radius {
                NumberAnimation { duration: root.animMs; easing.type: Easing.InOutCubic }
            }

            Item {
                id: topRow
                width: parent.width
                height: root.topH
                anchors.top: island.isBottom ? undefined : parent.top
                anchors.bottom: island.isBottom ? parent.bottom : undefined

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: island.expanded = !island.expanded
                }

                Row {
                    id: wsRow
                    anchors.left: parent.left
                    anchors.leftMargin: island.pad
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    Repeater {
                        model: root.wsIds
                        delegate: Rectangle {
                            id: wsItem
                            required property int modelData
                            readonly property int wsId: modelData
                            readonly property bool active: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === wsId
                            width: active ? 30 : 20
                            height: 22
                            radius: (11) * root.rs
                            color: active ? root.accent : (wsMa.containsMouse ? "#26ffffff" : "transparent")
                            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
                            Behavior on color { ColorAnimation { duration: 230 } }
                            T {
                                anchors.centerIn: parent
                                text: wsItem.wsId
                                color: wsItem.active ? root.accentFg : "#777777"
                                Behavior on color { ColorAnimation { duration: 230 } }
                            }
                            MouseArea {
                                id: wsMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + wsItem.wsId + " })")
                            }
                        }
                    }
                }

                T {
                    id: clockText
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    text: styleAd.show_clock_date ? "  " + Qt.formatDateTime(clock.date, "dd/MM HH:mm") : "  " + Qt.formatDateTime(clock.date, "HH:mm")
                    color: "#ffffff"
                }
                
                IconButton {
                    id: bellBtn
                    anchors.right: volRow.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26
                    height: 26
                    iconSize: 14
                    text: root.notifications.length > 0 ? "" : ""
                    fg: root.showNotifs ? root.accentFg : (root.notifications.length > 0 ? root.accent : "#cccccc")
                    hoverFg: "#ffffff"
                    active: root.showNotifs
                    onClicked: {
                        root.showNotifs = !root.showNotifs;
                        if (root.showNotifs) root.fetchNotifs();
                    }
                }

                Row {
                    id: volRow
                    anchors.right: parent.right
                    anchors.rightMargin: island.pad
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Item {
                        width: 14
                        height: 14
                        visible: root.playing
                        Repeater {
                            model: 3
                            delegate: Rectangle {
                                id: bar
                                required property int index
                                x: index * 5
                                anchors.bottom: parent.bottom
                                width: 3
                                height: 5
                                radius: (1.5) * root.rs
                                color: root.accent
                                SequentialAnimation on height {
                                    running: root.playing
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 14; duration: 380 + bar.index * 130; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 4; duration: 420 + bar.index * 90; easing.type: Easing.InOutSine }
                                }
                            }
                        }
                    }

                    T {
                        id: volText
                        color: root.muted ? "#666666" : "#ffffff"
                        text: {
                            if (root.muted) return "";
                            const icon = root.vol < 0.34 ? "" : (root.vol < 0.67 ? "" : "");
                            return icon + " " + Math.round(root.vol * 100) + "%";
                        }
                        Behavior on color { ColorAnimation { duration: 180 } }
                    }
                }

                MouseArea {
                    anchors.fill: volRow
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: function(mouse) {
                        if (mouse.button === Qt.RightButton)
                            Quickshell.execDetached(["pavucontrol"]);
                        else if (root.sink && root.sink.audio)
                            root.sink.audio.muted = !root.sink.audio.muted;
                    }
                    onWheel: function(wheel) { root.setVol(root.vol + (wheel.angleDelta.y > 0 ? 0.05 : -0.05)); }
                }
            }

            Item {
                id: mainContent
                anchors.top: island.isBottom ? undefined : topRow.bottom
                anchors.bottom: island.isBottom ? topRow.top : undefined
                anchors.bottomMargin: island.isBottom ? 8 : 0
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: island.pad + 4
                anchors.rightMargin: island.pad + 4
                
                height: root.showNotifs ? notifPanel.implicitHeight : panel.implicitHeight

                ColumnLayout {
                    id: panel
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: 10
                    visible: !root.showNotifs && island.reveal > 0.01
                    opacity: root.showNotifs ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: 200 } }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 26
                        spacing: 10
                        opacity: island.stag(0)
                        transform: Translate { y: (1 - island.stag(0)) * 10 }
                        
                        IconButton {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 26
                            iconSize: 14
                            text: root.muted ? "" : (root.vol < 0.34 ? "" : (root.vol < 0.67 ? "" : ""))
                            fg: root.muted ? "#666666" : "#d0d0d0"
                            onClicked: {
                                if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted;
                            }
                        }
                        Track {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 22
                            value: root.vol
                            animate: false
                            onMoved: function(ratio) { root.setVol(ratio); }
                        }
                        T {
                            Layout.preferredWidth: 38
                            horizontalAlignment: Text.AlignRight
                            text: Math.round(root.vol * 100) + "%"
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 26
                        spacing: 10
                        visible: root.brightPct >= 0
                        opacity: island.stag(1)
                        transform: Translate { y: (1 - island.stag(1)) * 10 }
                        T { Layout.preferredWidth: 28; horizontalAlignment: Text.AlignHCenter; text: "\uF185"; color: "#d0d0d0"; font.pixelSize: 14 }
                        Track { Layout.fillWidth: true; Layout.preferredHeight: 22; value: root.brightPct / 100; animate: false; onMoved: function(ratio) { root.brightSet(ratio); } }
                        T { Layout.preferredWidth: 38; horizontalAlignment: Text.AlignRight; text: Math.round(root.brightPct) + "%" }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 26
                        opacity: island.stag(1)
                        transform: Translate { y: (1 - island.stag(1)) * 10 }

                        T { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: " " + root.cpu + "%"; color: parseInt(root.cpu) >= 90 ? "#ff5555" : "#d0d0d0" }
                        T { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: " " + root.mem + "%"; color: parseInt(root.mem) >= 90 ? "#ff5555" : "#d0d0d0" }
                        T { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: " " + root.temp + "°C"; color: parseInt(root.temp) >= 85 ? "#ff5555" : (parseInt(root.temp) >= 70 ? "#ffaa44" : "#d0d0d0") }
                        T { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: root.iface === "offline" ? " off" : (root.iface.startsWith("w") ? " " : " ") + root.iface; color: root.iface === "offline" ? "#ff5555" : "#d0d0d0" }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        spacing: 6
                        opacity: island.stag(2)
                        transform: Translate { y: (1 - island.stag(2)) * 10 }
                        
                        Item { Layout.fillWidth: true } 
                        
                        Row {
                            spacing: 4
                            Repeater {
                                model: SystemTray.items
                                delegate: Item {
                                    id: ti
                                    required property var modelData
                                    width: 26
                                    height: 26

                                    Rectangle { anchors.fill: parent; radius: (13) * root.rs; color: tma.containsMouse ? "#26ffffff" : "transparent"; Behavior on color { ColorAnimation { duration: 160 } } }
                                    IconImage { anchors.centerIn: parent; implicitSize: 16; source: ti.modelData.icon; scale: tma.pressed ? 0.85 : 1; Behavior on scale { NumberAnimation { duration: 120 } } }
                                    QsMenuAnchor {
                                        id: menuAnchor; menu: ti.modelData.menu; anchor.window: win
                                        onOpened: root.menuOpen++; onClosed: root.menuOpen = Math.max(0, root.menuOpen - 1)
                                    }
                                    MouseArea {
                                        id: tma
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                        onClicked: function(mouse) {
                                            if (mouse.button === Qt.MiddleButton) {
                                                ti.modelData.secondaryActivate();
                                            } else if (mouse.button === Qt.LeftButton && !ti.modelData.onlyMenu) {
                                                ti.modelData.activate();
                                            } else if (ti.modelData.hasMenu) {
                                                const p = ti.mapToItem(null, 0, ti.height + 4);
                                                menuAnchor.anchor.rect.x = p.x;
                                                menuAnchor.anchor.rect.y = p.y;
                                                menuAnchor.anchor.rect.width = ti.width;
                                                menuAnchor.anchor.rect.height = 1;
                                                menuAnchor.open();
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 18; color: "#33ffffff"; visible: SystemTray.items.length > 0 }

                        IconButton {
                            Layout.preferredWidth: 30; Layout.preferredHeight: 28; text: root.dndEnabled ? "" : ""; fg: "#cccccc"; active: root.dndEnabled
                            onClicked: { root.dndEnabled = !root.dndEnabled; Quickshell.execDetached(["makoctl", "mode", "-s", root.dndEnabled ? "dnd" : "default"]); }
                        }
                        IconButton {
                            Layout.preferredWidth: 30; Layout.preferredHeight: 28; text: root.caffeine ? "" : ""; fg: "#cccccc"; active: root.caffeine
                            onClicked: root.caffeine = !root.caffeine
                        }
                        IconButton {
                            Layout.preferredWidth: 30; Layout.preferredHeight: 28; text: "\uF013"; fg: "#cccccc"; hoverFg: root.accent
                            onClicked: {
                                island.expanded = false;
                                Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/toggle-qs.sh", "settings"]);
                            }
                        }
                        IconButton {
                            Layout.preferredWidth: 30; Layout.preferredHeight: 28; text: ""; fg: "#cccccc"; hoverFg: "#ff5555"
                            onClicked: Quickshell.execDetached(["qs", "-c", "power"])
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 50
                        spacing: 6
                        opacity: island.stag(3)
                        transform: Translate { y: (1 - island.stag(3)) * 10 }
                        Tile { icon: "\uF1EB"; label: "Wi-Fi"; active: root.wifiOn; onClicked: root.toggleWifi() }
                        Tile { icon: "\uF293"; label: "BT"; active: root.btOn; onClicked: root.toggleBt() }
                        Tile { icon: "\uF186"; label: "Noturno"; active: root.nightOn; onClicked: root.toggleNight() }
                        Tile { icon: "\uF030"; label: "Captura"; onClicked: root.after("hyprshot -m region --clipboard-only") }
                        Tile { icon: "\uF1FB"; label: "Cores"; onClicked: root.after("hyprpicker -a") }
                        Tile { icon: "\uF03E"; label: "Papel"; onClicked: root.after("quickshell -p ~/.config/quickshell/hyprquickpaper") }
                    }

                    ColumnLayout {
                        id: media
                        Layout.fillWidth: true
                        visible: root.player !== null
                        spacing: 6
                        opacity: island.stag(4)
                        transform: Translate { y: (1 - island.stag(4)) * 10 }

                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#1affffff" }

                        RowLayout {
                            Layout.fillWidth: true; Layout.preferredHeight: 50; spacing: 10
                            ClippingRectangle {
                                Layout.preferredWidth: 46; Layout.preferredHeight: 46; radius: (12) * root.rs; color: "#22ffffff"
                                Image { anchors.fill: parent; source: root.player ? root.player.trackArtUrl : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; visible: status === Image.Ready }
                                T { anchors.centerIn: parent; text: ""; color: "#777777"; visible: !(root.player && root.player.trackArtUrl) }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 0
                                T { Layout.fillWidth: true; Layout.minimumWidth: 0; elide: Text.ElideRight; color: "#ffffff"; text: root.player && root.player.trackTitle ? root.player.trackTitle : "Sem título" }
                                T { Layout.fillWidth: true; Layout.minimumWidth: 0; elide: Text.ElideRight; color: "#9a9a9a"; font.pixelSize: 11; text: root.player && root.player.trackArtist ? root.player.trackArtist : "" }
                            }
                            IconButton { Layout.preferredWidth: 32; Layout.preferredHeight: 32; text: ""; onClicked: if (root.player) root.player.previous() }
                            IconButton {
                                Layout.preferredWidth: 38; Layout.preferredHeight: 38; iconSize: 17; text: root.playing ? "" : ""; fg: root.accentFg; hoverFg: root.accentFg
                                onClicked: if (root.player) root.player.togglePlaying()
                                Rectangle { anchors.fill: parent; radius: (width / 2) * root.rs; color: root.accent; z: -1 }
                            }
                            IconButton { Layout.preferredWidth: 32; Layout.preferredHeight: 32; text: ""; onClicked: if (root.player) root.player.next() }
                        }

                        RowLayout {
                            Layout.fillWidth: true; Layout.preferredHeight: 22; spacing: 8
                            T { Layout.preferredWidth: 44; Layout.minimumWidth: 44; horizontalAlignment: Text.AlignRight; color: "#aaaaaa"; font.pixelSize: 12; text: root.fmt(root.player ? root.player.position : 0) }
                            Track { Layout.fillWidth: true; Layout.preferredHeight: 22; value: root.seekHold >= 0 ? root.seekHold : root.ratio; onCommitted: function(ratio) { root.seekTo(ratio); } }
                            T { Layout.preferredWidth: 44; Layout.minimumWidth: 44; color: "#aaaaaa"; font.pixelSize: 12; text: root.trackLen > 0 ? root.fmt(root.trackLen) : "--:--" }
                        }
                    }
                }

                ColumnLayout {
                    id: notifPanel
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: 10
                    visible: root.showNotifs && island.reveal > 0.01
                    opacity: root.showNotifs ? island.stag(0) : 0
                    Behavior on opacity { NumberAnimation { duration: 250 } }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        T {
                            text: "Notificações"
                            font.pixelSize: 14
                            color: root.accent
                            Layout.fillWidth: true
                        }
                        IconButton {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            iconSize: 14
                            text: ""
                            hoverFg: "#ff5555"
                            onClicked: {
                                let mx = root.clearedId;
                                for (let i = 0; i < root.notifications.length; i++)
                                    mx = Math.max(mx, Number(root.notifications[i].id));
                                root.clearedId = mx;
                                Quickshell.execDetached(["makoctl", "dismiss", "-a"]);
                                root.notifications = [];
                                root.showNotifs = false;
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.max(80, Math.min(320, notifList.contentHeight))
                        color: "transparent"
                        clip: true
                        Behavior on Layout.preferredHeight { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                        
                        ListView {
                            id: notifList
                            anchors.fill: parent
                            model: root.notifications
                            spacing: 8
                            boundsBehavior: Flickable.StopAtBounds
                            
                            delegate: Rectangle {
                                width: ListView.view.width
                                height: delCol.implicitHeight + 16
                                radius: (10) * root.rs
                                color: "#1affffff"
                                border.width: 1
                                border.color: "#26ffffff"
                                
                                ColumnLayout {
                                    id: delCol
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 4
                                    RowLayout {
                                        Layout.fillWidth: true
                                        T {
                                            text: modelData.app || "Sistema"
                                            color: root.accent
                                            font.pixelSize: 11
                                            Layout.fillWidth: true
                                            font.bold: true
                                        }
                                    }
                                    T {
                                        text: modelData.summary
                                        font.bold: true
                                        color: "#ffffff"
                                        Layout.fillWidth: true
                                        wrapMode: Text.Wrap
                                    }
                                    T { 
                                        text: modelData.body
                                        font.pixelSize: 12
                                        color: "#cccccc"
                                        Layout.fillWidth: true
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 4
                                        elide: Text.ElideRight
                                        visible: modelData.body !== "" 
                                    }
                                }
                            }
                        }
                        
                        T {
                            anchors.centerIn: parent
                            text: "Nenhuma notificação"
                            visible: root.notifications.length === 0
                            color: "#777777"
                        }
                    }
                }
            }
        }
    }

    HyprlandFocusGrab {
        windows: [win]
        active: island.expanded && root.menuOpen === 0
        onCleared: island.expanded = false
    }
}
