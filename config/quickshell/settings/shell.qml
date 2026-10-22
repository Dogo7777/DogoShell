import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

ShellRoot {
    id: root

    readonly property string pyScript: Quickshell.env("HOME") + "/.config/quickshell/settings/settings.py"

    FileView {
        path: Quickshell.env("HOME") + "/.config/hypr/settings.json"
        watchChanges: true
        printErrors: false
        onFileChanged: if (!getProc.running) getProc.running = true
    }

    FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/style.json"
        watchChanges: true
        printErrors: false
    }

    property var st: ({ binds: {} })
    property var sysInfo: ({
        user: "Usuário",
        hostname: "hostname",
        distro: "Linux",
        kernel: "Kernel",
        uptime: "N/A",
        hypr_ver: "Hyprland",
        qs_ver: "Quickshell",
        cpu: "CPU",
        gpu: "GPU",
        ram: "RAM",
        avatar: "",
        dotfiles_ver: "v2.0 (HyprAtomic)"
    })

    readonly property real rs: {
        const shape = (root.st && root.st.shape) ? root.st.shape : "round";
        if (shape === "square") return 0.0;
        if (shape === "soft") return 0.5;
        return 1.0;
    }

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

    property int page: 0
    property string capName: ""
    property real reveal: 0
    property bool closing: false

    Behavior on reveal {
        NumberAnimation {
            duration: root.closing ? 240 : 560
            easing.type: root.closing ? Easing.InCubic : Easing.OutQuint
        }
    }

    Timer {
        running: true
        interval: 30
        onTriggered: root.reveal = 1
    }

    Timer {
        id: quitTimer
        interval: 260
        onTriggered: Qt.quit()
    }

    Timer {
        id: refetch
        interval: 900
        onTriggered: getProc.running = true
    }

    function close() {
        if (closing) return;
        closing = true;
        reveal = 0;
        quitTimer.start();
    }

    Process {
        id: getProc
        running: true
        command: ["python3", root.pyScript, "get"]
        stdout: SplitParser {
            onRead: function(data) {
                try {
                    if (data.trim() !== "") root.st = JSON.parse(data);
                } catch (e) {}
            }
        }
    }

    Process {
        id: sysProc
        running: true
        command: ["python3", root.pyScript, "sysinfo"]
        stdout: SplitParser {
            onRead: function(data) {
                try {
                    if (data.trim() !== "") root.sysInfo = JSON.parse(data);
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 3000
        running: root.page === 7
        repeat: true
        onTriggered: sysProc.running = true
    }

    function applyVal(k, v) {
        const n = Object.assign({}, st);
        n[k] = v;
        st = n;
        Quickshell.execDetached(["python3", root.pyScript, "apply", k, JSON.stringify(v)]);
    }

    function setVal(k, v) {
        const n = Object.assign({}, st);
        n[k] = v;
        st = n;
        Quickshell.execDetached(["python3", root.pyScript, "set", k, JSON.stringify(v)]);
    }

    function resetAll() {
        Quickshell.execDetached(["python3", root.pyScript, "reset"]);
        refetch.restart();
    }

    readonly property var bindDefs: [
        { id: "terminal",    label: "Terminal" },
        { id: "filemanager", label: "Gerenciador de arquivos" },
        { id: "launcher",    label: "Launcher" },
        { id: "launcher2",   label: "Launcher (alternativo)" },
        { id: "wallpaper",   label: "Escolher wallpaper" },
        { id: "power",       label: "Menu de energia" },
        { id: "lock",        label: "Bloquear tela" },
        { id: "settings",    label: "Configurações" },
        { id: "close",       label: "Fechar janela" },
        { id: "float",       label: "Alternar flutuante" }
    ]
    readonly property var modOrder: ["SUPER", "CTRL", "ALT", "SHIFT"]

    function comboOf(id) {
        return (st.binds && st.binds[id]) ? st.binds[id] : "";
    }

    function modsOf(id) {
        const p = comboOf(id).split(" + ");
        return p.slice(0, Math.max(0, p.length - 1));
    }

    function keyOf(id) {
        const p = comboOf(id).split(" + ");
        return p.length ? p[p.length - 1] : "";
    }

    function buildCombo(mods, key) {
        const m = [];
        for (let i = 0; i < modOrder.length; i++) {
            if (mods.indexOf(modOrder[i]) >= 0) m.push(modOrder[i]);
        }
        m.push(key);
        return m.join(" + ");
    }

    function setBind(id, combo) {
        const b = Object.assign({}, st.binds);
        b[id] = combo;
        const n = Object.assign({}, st);
        n.binds = b;
        st = n;
        Quickshell.execDetached(["python3", root.pyScript, "set", "binds", JSON.stringify(b)]);
    }

    function toggleMod(id, mod) {
        const mods = modsOf(id).slice();
        const i = mods.indexOf(mod);
        if (i >= 0) mods.splice(i, 1);
        else mods.push(mod);
        setBind(id, buildCombo(mods, keyOf(id)));
    }

    function dupCount(id) {
        const c = comboOf(id);
        let n = 0;
        for (let i = 0; i < bindDefs.length; i++) {
            if (comboOf(bindDefs[i].id) === c) n++;
        }
        return n;
    }

    function keyName(k) {
        if (k >= Qt.Key_A && k <= Qt.Key_Z) return String.fromCharCode(k);
        if (k >= Qt.Key_0 && k <= Qt.Key_9) return String.fromCharCode(k);
        if (k >= Qt.Key_F1 && k <= Qt.Key_F12) return "F" + (k - Qt.Key_F1 + 1);
        const m = {};
        m[Qt.Key_Space] = "SPACE";
        m[Qt.Key_Return] = "RETURN";
        m[Qt.Key_Enter] = "RETURN";
        m[Qt.Key_Tab] = "TAB";
        m[Qt.Key_Print] = "Print";
        m[Qt.Key_Left] = "left";
        m[Qt.Key_Right] = "right";
        m[Qt.Key_Up] = "up";
        m[Qt.Key_Down] = "down";
        m[Qt.Key_Comma] = "comma";
        m[Qt.Key_Period] = "period";
        m[Qt.Key_Minus] = "minus";
        m[Qt.Key_Equal] = "equal";
        m[Qt.Key_Slash] = "slash";
        m[Qt.Key_Semicolon] = "semicolon";
        m[Qt.Key_Backslash] = "backslash";
        m[Qt.Key_BracketLeft] = "bracketleft";
        m[Qt.Key_BracketRight] = "bracketright";
        m[Qt.Key_Delete] = "Delete";
        m[Qt.Key_Home] = "Home";
        m[Qt.Key_End] = "End";
        m[Qt.Key_PageUp] = "Prior";
        m[Qt.Key_PageDown] = "Next";
        return m[k] || "";
    }

    component T: Text {
        color: "#d8d8d8"
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 13
        font.bold: true
        verticalAlignment: Text.AlignVCenter
    }

    component Opt: Item {
        id: o
        property string label: ""
        property string hint: ""
        default property alias ctrl: slot.data
        width: parent ? parent.width : 400
        height: 50

        Column {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            T { text: o.label; color: "#ffffff"; font.pixelSize: 14 }
            T { text: o.hint; visible: o.hint !== ""; color: "#7a7a7a"; font.pixelSize: 11; font.bold: false }
        }

        RowLayout {
            id: slot
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            spacing: 8
        }
    }

    component Toggle: Rectangle {
        id: tg
        property bool on: false
        signal toggled(bool v)
        implicitWidth: 48
        implicitHeight: 26
        radius: Math.round(13 * root.rs)
        color: on ? root.accent : Qt.rgba(1, 1, 1, 0.2)
        Behavior on color { ColorAnimation { duration: 200 } }

        Rectangle {
            width: 20
            height: 20
            radius: Math.round(10 * root.rs)
            y: 3
            x: tg.on ? tg.width - width - 3 : 3
            color: tg.on ? root.accentFg : "#ffffff"
            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) {
                mouse.accepted = true;
                tg.toggled(!tg.on);
            }
        }
    }

    component Seg: Row {
        id: sg
        property var opts: []
        property string cur: ""
        signal picked(string v)
        spacing: 6

        Repeater {
            model: sg.opts
            delegate: Rectangle {
                id: chip
                required property var modelData
                readonly property bool on: sg.cur === modelData[0]
                width: lbl.implicitWidth + 28
                height: 32
                radius: Math.round(16 * root.rs)
                color: on ? root.accent : (cma.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : "transparent")
                border.width: 1
                border.color: on ? "transparent" : Qt.rgba(1, 1, 1, 0.2)
                scale: cma.pressed ? 0.94 : 1.0
                Behavior on color { ColorAnimation { duration: 180 } }
                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

                T {
                    id: lbl
                    anchors.centerIn: parent
                    text: chip.modelData[1]
                    font.pixelSize: 12
                    color: chip.on ? root.accentFg : "#dddddd"
                }

                MouseArea {
                    id: cma
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) {
                        mouse.accepted = true;
                        sg.picked(chip.modelData[0]);
                    }
                }
            }
        }
    }

    component Sld: Item {
        id: s
        property real from: 0
        property real to: 1
        property real step: 0.1
        property real value: 0
        property real shown: value
        property int decimals: 0
        signal moved(real v)
        signal committed(real v)
        implicitWidth: 270
        implicitHeight: 28

        onValueChanged: {
            if (!sma.pressed) shown = value;
        }

        Rectangle {
            id: track
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 58
            height: 6
            radius: Math.round(3 * root.rs)
            color: Qt.rgba(1, 1, 1, 0.15)

            Rectangle {
                width: Math.max(0, Math.min(1, (s.shown - s.from) / (s.to - s.from))) * track.width
                height: parent.height
                radius: Math.round(3 * root.rs)
                color: root.accent
            }

            Rectangle {
                width: 16
                height: 16
                radius: Math.round(8 * root.rs)
                anchors.verticalCenter: parent.verticalCenter
                x: Math.max(0, Math.min(1, (s.shown - s.from) / (s.to - s.from))) * (track.width - width)
                color: "#ffffff"
                scale: sma.pressed ? 1.2 : 1.0
                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
            }
        }

        T {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 50
            horizontalAlignment: Text.AlignRight
            text: s.shown.toFixed(s.decimals)
            font.pixelSize: 12
            color: "#bbbbbb"
        }

        MouseArea {
            id: sma
            anchors.fill: track
            anchors.topMargin: -10
            anchors.bottomMargin: -10
            cursorShape: Qt.PointingHandCursor

            function upd(xVal) {
                const r = Math.max(0, Math.min(1, xVal / track.width));
                let v = s.from + r * (s.to - s.from);
                v = Math.round(v / s.step) * s.step;
                s.shown = Math.max(s.from, Math.min(s.to, v));
                s.moved(s.shown);
            }

            onPressed: function(mouse) { mouse.accepted = true; upd(mouse.x); }
            onPositionChanged: function(mouse) { if (pressed) { mouse.accepted = true; upd(mouse.x); } }
            onReleased: function(mouse) { mouse.accepted = true; s.committed(s.shown); }
        }
    }

    component Section: T {
        color: root.accent
        font.pixelSize: 11
        font.letterSpacing: 1.5
        topPadding: 10
        bottomPadding: 2
    }

    PanelWindow {
        id: win
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "settings"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: 0.45 * root.reveal
            MouseArea { anchors.fill: parent; onClicked: root.close() }
        }

        Item {
            anchors.fill: parent
            focus: true
            Component.onCompleted: forceActiveFocus()
            Keys.onPressed: function(event) {
                if (root.capName !== "") {
                    if (event.key === Qt.Key_Escape) {
                        root.capName = "";
                        event.accepted = true;
                        return;
                    }
                    if (event.key === Qt.Key_Shift || event.key === Qt.Key_Control || event.key === Qt.Key_Alt || event.key === Qt.Key_Meta || event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R) {
                        event.accepted = true;
                        return;
                    }
                    const kn = root.keyName(event.key);
                    if (kn !== "") {
                        root.setBind(root.capName, root.buildCombo(root.modsOf(root.capName), kn));
                        root.capName = "";
                    }
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Escape) {
                    root.close();
                    event.accepted = true;
                }
            }
        }

        Rectangle {
            id: card
            readonly property real fullW: 880
            readonly property real fullH: 580
            width: 240 + (fullW - 240) * root.reveal
            height: 56 + (fullH - 56) * root.reveal
            anchors.centerIn: parent
            radius: Math.round(30 * root.rs)
            color: Qt.rgba(0.03, 0.03, 0.04, 0.82)
            border.width: 1
            border.color: root.accA(0.55)
            clip: true
            opacity: Math.min(1, root.reveal * 3)

            Behavior on radius { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }

            MouseArea {
                anchors.fill: parent
                onClicked: function(mouse) {
                    mouse.accepted = true;
                    root.capName = "";
                }
            }

            Item {
                id: inner
                x: 0
                y: 0
                width: card.fullW
                height: card.fullH
                opacity: Math.max(0, (root.reveal - 0.5) / 0.5)

                Column {
                    x: 18
                    y: 22
                    width: 190
                    spacing: 6
                    T { text: "  Configurações"; color: "#ffffff"; font.pixelSize: 16; height: 34 }
                    Item { width: 1; height: 4 }
                    Repeater {
                        model: [
                            { n: "Aparência",   g: "" },
                            { n: "Barra & Ilha",g: "" },
                            { n: "Janelas",     g: "" },
                            { n: "Animações",   g: "" },
                            { n: "Entrada",     g: "" },
                            { n: "Atalhos",     g: "" },
                            { n: "Sistema",     g: "" },
                            { n: "Sobre",       g: "" }
                        ]
                        delegate: Rectangle {
                            id: tab
                            required property var modelData
                            required property int index
                            readonly property bool on: root.page === index
                            width: 190
                            height: 38
                            radius: Math.round(12 * root.rs)
                            color: on ? root.accA(0.22) : (tma.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                            border.width: 1
                            border.color: on ? root.accA(0.55) : "transparent"
                            Behavior on color { ColorAnimation { duration: 180 } }

                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 14
                                spacing: 12
                                T { text: tab.modelData.g; color: tab.on ? root.accent : "#999999"; font.pixelSize: 14 }
                                T { text: tab.modelData.n; color: tab.on ? "#ffffff" : "#cccccc"; font.pixelSize: 12 }
                            }

                            MouseArea {
                                id: tma
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: function(mouse) {
                                    mouse.accepted = true;
                                    root.page = tab.index;
                                    root.capName = "";
                                    if (tab.index === 7) sysProc.running = true;
                                }
                            }
                        }
                    }
                }

                Rectangle { x: 226; y: 22; width: 1; height: card.fullH - 44; color: Qt.rgba(1, 1, 1, 0.1) }

                Item {
                    x: 246
                    y: 18
                    width: card.fullW - 246 - 24
                    height: card.fullH - 36

                    // 0 — Aparência
                    Flickable {
                        anchors.fill: parent
                        visible: opacity > 0
                        opacity: root.page === 0 ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 220 } }
                        contentHeight: p0.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: p0
                            width: parent.width
                            spacing: 2
                            Section { text: "FORMATO" }
                            Opt {
                                label: "Cantos"
                                hint: "Janelas, ilha, launcher e menus"
                                Seg {
                                    opts: [["round", "Redondo"], ["soft", "Suave"], ["square", "Quadrado"]]
                                    cur: root.st.shape || "round"
                                    onPicked: function(v) { root.setVal("shape", v); }
                                }
                            }
                            Section { text: "VIDRO" }
                            Opt {
                                label: "Blur nas janelas"
                                Toggle {
                                    on: !!root.st.blur
                                    onToggled: function(v) { root.setVal("blur", v); }
                                }
                            }
                            Opt {
                                label: "Intensidade do blur"
                                hint: "Tamanho do desfoque"
                                Sld {
                                    from: 1; to: 12; step: 1; value: root.st.blur_size || 6
                                    onMoved: function(v) { root.applyVal("blur_size", v); }
                                    onCommitted: function(v) { root.setVal("blur_size", v); }
                                }
                            }
                            Opt {
                                label: "Qualidade do blur"
                                hint: "Mais camadas = mais suave, mais GPU"
                                Sld {
                                    from: 1; to: 4; step: 1; value: root.st.blur_passes || 2
                                    onMoved: function(v) { root.applyVal("blur_passes", v); }
                                    onCommitted: function(v) { root.setVal("blur_passes", v); }
                                }
                            }
                            Opt {
                                label: "Blur nos painéis"
                                hint: "Ilha, launcher, menu de energia, notificações"
                                Toggle {
                                    on: !!root.st.shell_blur
                                    onToggled: function(v) { root.setVal("shell_blur", v); }
                                }
                            }
                            Section { text: "TRANSPARÊNCIA E SOMBRA" }
                            Opt {
                                label: "Opacidade da janela ativa"
                                Sld {
                                    from: 0.5; to: 1; step: 0.05; decimals: 2; value: root.st.opacity_active || 1
                                    onMoved: function(v) { root.applyVal("opacity_active", v); }
                                    onCommitted: function(v) { root.setVal("opacity_active", v); }
                                }
                            }
                            Opt {
                                label: "Opacidade das janelas inativas"
                                Sld {
                                    from: 0.5; to: 1; step: 0.05; decimals: 2; value: root.st.opacity_inactive || 1
                                    onMoved: function(v) { root.applyVal("opacity_inactive", v); }
                                    onCommitted: function(v) { root.setVal("opacity_inactive", v); }
                                }
                            }
                            Opt {
                                label: "Sombras nas janelas"
                                Toggle {
                                    on: !!root.st.shadow
                                    onToggled: function(v) { root.setVal("shadow", v); }
                                }
                            }
                        }
                    }

                    // 1 — Barra & Ilha
                    Flickable {
                        anchors.fill: parent
                        visible: opacity > 0
                        opacity: root.page === 1 ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 220 } }
                        contentHeight: pBar.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: pBar
                            width: parent.width
                            spacing: 2
                            Section { text: "MODO E POSIÇÃO" }
                            Opt {
                                label: "Modo do Painel"
                                hint: "Ilha dinâmica ou barra estendida tradicional"
                                Seg {
                                    opts: [["island", "Ilha Dinâmica"], ["bar", "Barra Normal"]]
                                    cur: root.st.bar_mode || "island"
                                    onPicked: function(v) { root.setVal("bar_mode", v); }
                                }
                            }
                            Opt {
                                label: "Posição na Tela"
                                hint: "Topo da tela ou parte inferior"
                                Seg {
                                    opts: [["top", "Topo"], ["bottom", "Embaixo"]]
                                    cur: root.st.bar_position || "top"
                                    onPicked: function(v) { root.setVal("bar_position", v); }
                                }
                            }
                            Section { text: "DIMENSÕES E ESTILO" }
                            Opt {
                                label: "Largura Total (100%)"
                                hint: "Estende a barra de ponta a ponta na tela"
                                Toggle {
                                    on: !!root.st.bar_full_width
                                    onToggled: function(v) { root.setVal("bar_full_width", v); }
                                }
                            }
                            Opt {
                                label: "Barra Flutuante"
                                hint: "Destaca a barra da borda com margem e cantos suaves"
                                Toggle {
                                    on: root.st.bar_floating !== false
                                    onToggled: function(v) { root.setVal("bar_floating", v); }
                                }
                            }
                            Opt {
                                label: "Margem da Borda"
                                hint: "Distância em pixels (quando flutuante)"
                                Sld {
                                    from: 0; to: 20; step: 1; value: root.st.bar_margin === undefined ? 6 : root.st.bar_margin
                                    onMoved: function(v) { root.applyVal("bar_margin", v); }
                                    onCommitted: function(v) { root.setVal("bar_margin", v); }
                                }
                            }
                            Section { text: "TRANSPARÊNCIA E EXIBIÇÃO" }
                            Opt {
                                label: "Opacidade do Fundo"
                                hint: "Transparência do painel da barra / ilha"
                                Sld {
                                    from: 0.1; to: 1.0; step: 0.05; decimals: 2; value: root.st.bar_opacity === undefined ? 0.55 : root.st.bar_opacity
                                    onMoved: function(v) { root.applyVal("bar_opacity", v); }
                                    onCommitted: function(v) { root.setVal("bar_opacity", v); }
                                }
                            }
                            Opt {
                                label: "Exibir Data no Relógio"
                                hint: "Mostra o dia/mês junto com o horário"
                                Toggle {
                                    on: !!root.st.show_clock_date
                                    onToggled: function(v) { root.setVal("show_clock_date", v); }
                                }
                            }
                        }
                    }

                    // 2 — Janelas
                    Flickable {
                        anchors.fill: parent
                        visible: opacity > 0
                        opacity: root.page === 2 ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 220 } }
                        contentHeight: p1.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: p1
                            width: parent.width
                            spacing: 2
                            Section { text: "COMPORTAMENTO" }
                            Opt {
                                label: "Layout das Janelas"
                                hint: "Dwindle (espiral) ou Master (pilha principal)"
                                Seg {
                                    opts: [["dwindle", "Dwindle"], ["master", "Master"]]
                                    cur: root.st.layout || "dwindle"
                                    onPicked: function(v) { root.setVal("layout", v); }
                                }
                            }
                            Section { text: "ESPAÇAMENTO" }
                            Opt {
                                label: "Entre janelas"
                                Sld {
                                    from: 0; to: 20; step: 1; value: root.st.gaps_in === undefined ? 5 : root.st.gaps_in
                                    onMoved: function(v) { root.applyVal("gaps_in", v); }
                                    onCommitted: function(v) { root.setVal("gaps_in", v); }
                                }
                            }
                            Opt {
                                label: "Margem da tela"
                                hint: "Laterais e embaixo"
                                Sld {
                                    from: 0; to: 40; step: 1; value: root.st.gaps_out === undefined ? 10 : root.st.gaps_out
                                    onMoved: function(v) { root.applyVal("gaps_out", v); }
                                    onCommitted: function(v) { root.setVal("gaps_out", v); }
                                }
                            }
                            Opt {
                                label: "Margem do topo"
                                hint: "Espaço reservado para a ilha"
                                Sld {
                                    from: 0; to: 80; step: 1; value: root.st.gaps_top === undefined ? 45 : root.st.gaps_top
                                    onMoved: function(v) { root.applyVal("gaps_top", v); }
                                    onCommitted: function(v) { root.setVal("gaps_top", v); }
                                }
                            }
                            Section { text: "BORDA" }
                            Opt {
                                label: "Espessura da borda"
                                hint: "A cor vem do wallpaper"
                                Sld {
                                    from: 0; to: 6; step: 1; value: root.st.border === undefined ? 2 : root.st.border
                                    onMoved: function(v) { root.applyVal("border", v); }
                                    onCommitted: function(v) { root.setVal("border", v); }
                                }
                            }
                        }
                    }

                    // 3 — Animações
                    Flickable {
                        anchors.fill: parent
                        visible: opacity > 0
                        opacity: root.page === 3 ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 220 } }
                        contentHeight: p2.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: p2
                            width: parent.width
                            spacing: 2
                            Section { text: "VELOCIDADE" }
                            Opt {
                                label: "Duração das animações"
                                hint: "1.0 normal · maior = mais lento · menor = mais rápido"
                                Sld {
                                    from: 0.4; to: 2.5; step: 0.1; decimals: 1; value: root.st.anim_scale || 1
                                    onMoved: function(v) { root.applyVal("anim_scale", v); }
                                    onCommitted: function(v) { root.setVal("anim_scale", v); }
                                }
                            }
                            Section { text: "EFEITOS" }
                            Opt {
                                label: "Borda girando"
                                hint: "O degradê da borda gira (usa mais GPU)"
                                Toggle {
                                    on: !!root.st.border_spin
                                    onToggled: function(v) { root.setVal("border_spin", v); }
                                }
                            }
                        }
                    }

                    // 4 — Entrada
                    Flickable {
                        anchors.fill: parent
                        visible: opacity > 0
                        opacity: root.page === 4 ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 220 } }
                        contentHeight: p3.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: p3
                            width: parent.width
                            spacing: 2
                            Section { text: "MOUSE E TOUCHPAD" }
                            Opt {
                                label: "Sensibilidade do ponteiro"
                                Sld {
                                    from: -1; to: 1; step: 0.1; decimals: 1; value: root.st.sensitivity || 0
                                    onMoved: function(v) { root.applyVal("sensitivity", v); }
                                    onCommitted: function(v) { root.setVal("sensitivity", v); }
                                }
                            }
                            Opt {
                                label: "Rolagem Natural"
                                hint: "Inverte a direção da rolagem (estilo celular)"
                                Toggle {
                                    on: !!root.st.natural_scroll
                                    onToggled: function(v) { root.setVal("natural_scroll", v); }
                                }
                            }
                            Section { text: "CURSOR E FOCO" }
                            Opt {
                                label: "Tamanho do Cursor"
                                Sld {
                                    from: 16; to: 48; step: 2; value: root.st.cursor_size || 24
                                    onMoved: function(v) { root.applyVal("cursor_size", v); }
                                    onCommitted: function(v) { root.setVal("cursor_size", v); }
                                }
                            }
                            Opt {
                                label: "Foco segue o mouse"
                                hint: "Alterna a janela ativa só de passar o mouse por cima"
                                Toggle {
                                    on: root.st.focus_mouse !== false
                                    onToggled: function(v) { root.setVal("focus_mouse", v); }
                                }
                            }
                        }
                    }

                    // 5 — Atalhos
                    Flickable {
                        anchors.fill: parent
                        visible: opacity > 0
                        opacity: root.page === 5 ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 220 } }
                        contentHeight: p4.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: p4
                            width: parent.width
                            spacing: 2
                            Section { text: "ATALHOS" }
                            T {
                                width: parent.width
                                wrapMode: Text.WordWrap
                                color: "#7a7a7a"
                                font.bold: false
                                font.pixelSize: 11
                                text: "Escolha os modificadores e clique na tecla para trocá-la. Esc cancela. Vermelho = combinação repetida."
                            }
                            Repeater {
                                model: root.bindDefs
                                delegate: Opt {
                                    id: br
                                    required property var modelData
                                    label: modelData.label
                                    readonly property bool dup: root.dupCount(modelData.id) > 1

                                    Row {
                                        spacing: 6
                                        Layout.alignment: Qt.AlignVCenter
                                        Repeater {
                                            model: root.modOrder
                                            delegate: Rectangle {
                                                id: mchip
                                                required property string modelData
                                                readonly property bool on: root.modsOf(br.modelData.id).indexOf(modelData) >= 0
                                                width: mt.implicitWidth + 18
                                                height: 28
                                                radius: Math.round(14 * root.rs)
                                                color: on ? root.accA(0.35) : (mma.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent")
                                                border.width: 1
                                                border.color: on ? root.accA(0.8) : Qt.rgba(1, 1, 1, 0.2)
                                                Behavior on color { ColorAnimation { duration: 160 } }
                                                T { id: mt; anchors.centerIn: parent; text: mchip.modelData; font.pixelSize: 10; color: mchip.on ? "#ffffff" : "#999999" }
                                                MouseArea {
                                                    id: mma
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: function(mouse) {
                                                        mouse.accepted = true;
                                                        root.toggleMod(br.modelData.id, mchip.modelData);
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        readonly property bool cap: root.capName === br.modelData.id
                                        Layout.alignment: Qt.AlignVCenter
                                        implicitWidth: Math.max(96, kt.implicitWidth + 28)
                                        implicitHeight: 30
                                        radius: Math.round(12 * root.rs)
                                        color: cap ? root.accent : (kma.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08))
                                        border.width: 1
                                        border.color: br.dup ? "#ff5a5a" : (cap ? "transparent" : Qt.rgba(1, 1, 1, 0.2))
                                        Behavior on color { ColorAnimation { duration: 160 } }
                                        T {
                                            id: kt
                                            anchors.centerIn: parent
                                            text: parent.cap ? "pressione..." : root.keyOf(br.modelData.id)
                                            color: parent.cap ? root.accentFg : (br.dup ? "#ff8a8a" : "#ffffff")
                                            font.pixelSize: 12
                                        }
                                        MouseArea {
                                            id: kma
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: function(mouse) {
                                                mouse.accepted = true;
                                                root.capName = br.modelData.id;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 6 — Sistema
                    Flickable {
                        anchors.fill: parent
                        visible: opacity > 0
                        opacity: root.page === 6 ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 220 } }
                        contentHeight: p5.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: p5
                            width: parent.width
                            spacing: 6
                            Section { text: "SISTEMA" }
                            Opt {
                                label: "Restaurar padrões"
                                hint: "Volta todas as abas ao original"
                                Rectangle {
                                    implicitWidth: rt.implicitWidth + 32
                                    implicitHeight: 34
                                    radius: Math.round(14 * root.rs)
                                    color: rma.containsMouse ? "#ff5a5a" : Qt.rgba(1, 0.35, 0.35, 0.2)
                                    Behavior on color { ColorAnimation { duration: 160 } }
                                    T { id: rt; anchors.centerIn: parent; text: "Restaurar"; color: "#ffffff" }
                                    MouseArea {
                                        id: rma
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: function(mouse) {
                                            mouse.accepted = true;
                                            root.resetAll();
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 7 — Sobre
                    Flickable {
                        anchors.fill: parent
                        visible: opacity > 0
                        opacity: root.page === 7 ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 220 } }
                        contentHeight: p6.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: p6
                            width: parent.width
                            spacing: 10

                            Rectangle {
                                width: parent.width
                                height: 76
                                radius: Math.round(16 * root.rs)
                                color: Qt.rgba(1, 1, 1, 0.05)
                                border.width: 1
                                border.color: root.accA(0.3)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 14

                                    Rectangle {
                                        width: 52
                                        height: 52
                                        radius: Math.round(26 * root.rs)
                                        color: root.accA(0.2)
                                        border.width: 2
                                        border.color: root.accent
                                        clip: true

                                        Image {
                                            anchors.fill: parent
                                            source: root.sysInfo.avatar || ""
                                            fillMode: Image.PreserveAspectCrop
                                            visible: status === Image.Ready
                                        }

                                        T {
                                            anchors.centerIn: parent
                                            text: ""
                                            font.pixelSize: 24
                                            color: root.accent
                                            visible: !root.sysInfo.avatar || parent.children[0].status !== Image.Ready
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        T {
                                            text: root.sysInfo.user + "@" + root.sysInfo.hostname
                                            font.pixelSize: 15
                                            color: "#ffffff"
                                        }
                                        T {
                                            text: root.sysInfo.distro + " · " + root.sysInfo.dotfiles_ver
                                            font.pixelSize: 11
                                            color: "#aaaaaa"
                                            font.bold: false
                                        }
                                    }
                                }
                            }

                            Section { text: "INFORMAÇÕES DO SISTEMA" }

                            Column {
                                width: parent.width
                                spacing: 4

                                Rectangle {
                                    width: parent.width
                                    height: 38
                                    radius: Math.round(10 * root.rs)
                                    color: Qt.rgba(1, 1, 1, 0.04)
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12; anchors.rightMargin: 12
                                        T { text: "🐧 Kernel & Distro"; font.pixelSize: 12; color: "#cccccc" }
                                        Item { Layout.fillWidth: true }
                                        T { text: root.sysInfo.distro + " (" + root.sysInfo.kernel + ")"; font.pixelSize: 11; color: "#ffffff" }
                                    }
                                }

                                Rectangle {
                                    width: parent.width
                                    height: 38
                                    radius: Math.round(10 * root.rs)
                                    color: Qt.rgba(1, 1, 1, 0.04)
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12; anchors.rightMargin: 12
                                        T { text: "⚙️ Compositor & Shell"; font.pixelSize: 12; color: "#cccccc" }
                                        Item { Layout.fillWidth: true }
                                        T { text: root.sysInfo.hypr_ver + " · " + root.sysInfo.qs_ver; font.pixelSize: 11; color: "#ffffff" }
                                    }
                                }

                                Rectangle {
                                    width: parent.width
                                    height: 38
                                    radius: Math.round(10 * root.rs)
                                    color: Qt.rgba(1, 1, 1, 0.04)
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12; anchors.rightMargin: 12
                                        T { text: "⏱️ Uptime"; font.pixelSize: 12; color: "#cccccc" }
                                        Item { Layout.fillWidth: true }
                                        T { text: root.sysInfo.uptime; font.pixelSize: 11; color: "#ffffff" }
                                    }
                                }

                                Rectangle {
                                    width: parent.width
                                    height: 38
                                    radius: Math.round(10 * root.rs)
                                    color: Qt.rgba(1, 1, 1, 0.04)
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12; anchors.rightMargin: 12
                                        T { text: "🧠 Processador (CPU)"; font.pixelSize: 12; color: "#cccccc" }
                                        Item { Layout.fillWidth: true }
                                        T { text: root.sysInfo.cpu; font.pixelSize: 10; color: "#ffffff" }
                                    }
                                }

                                Rectangle {
                                    width: parent.width
                                    height: 38
                                    radius: Math.round(10 * root.rs)
                                    color: Qt.rgba(1, 1, 1, 0.04)
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12; anchors.rightMargin: 12
                                        T { text: "🎮 Placa de Vídeo (GPU)"; font.pixelSize: 12; color: "#cccccc" }
                                        Item { Layout.fillWidth: true }
                                        T { text: root.sysInfo.gpu; font.pixelSize: 10; color: "#ffffff" }
                                    }
                                }

                                Rectangle {
                                    width: parent.width
                                    height: 38
                                    radius: Math.round(10 * root.rs)
                                    color: Qt.rgba(1, 1, 1, 0.04)
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12; anchors.rightMargin: 12
                                        T { text: "📊 Memória RAM"; font.pixelSize: 12; color: "#cccccc" }
                                        Item { Layout.fillWidth: true }
                                        T { text: root.sysInfo.ram; font.pixelSize: 11; color: root.accent }
                                    }
                                }
                            }

                            Section { text: "AÇÕES RÁPIDAS DE MANUTENÇÃO" }

                            Row {
                                width: parent.width
                                spacing: 8

                                Rectangle {
                                    width: (parent.width - 16) / 3
                                    height: 38
                                    radius: Math.round(12 * root.rs)
                                    color: b1ma.containsMouse ? root.accA(0.4) : Qt.rgba(1, 1, 1, 0.08)
                                    border.width: 1
                                    border.color: root.accA(0.5)

                                    T { anchors.centerIn: parent; text: "🔄 Atualizações"; font.pixelSize: 11 }

                                    MouseArea {
                                        id: b1ma
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: function(mouse) {
                                            mouse.accepted = true;
                                            Quickshell.execDetached(["python3", root.pyScript, "action", "check_updates"]);
                                        }
                                    }
                                }

                                Rectangle {
                                    width: (parent.width - 16) / 3
                                    height: 38
                                    radius: Math.round(12 * root.rs)
                                    color: b2ma.containsMouse ? root.accA(0.4) : Qt.rgba(1, 1, 1, 0.08)
                                    border.width: 1
                                    border.color: root.accA(0.5)

                                    T { anchors.centerIn: parent; text: "🔗 Repositório"; font.pixelSize: 11 }

                                    MouseArea {
                                        id: b2ma
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: function(mouse) {
                                            mouse.accepted = true;
                                            Quickshell.execDetached(["python3", root.pyScript, "action", "open_repo"]);
                                        }
                                    }
                                }

                                Rectangle {
                                    width: (parent.width - 16) / 3
                                    height: 38
                                    radius: Math.round(12 * root.rs)
                                    color: b3ma.containsMouse ? root.accA(0.4) : Qt.rgba(1, 1, 1, 0.08)
                                    border.width: 1
                                    border.color: root.accA(0.5)

                                    T { anchors.centerIn: parent; text: "⚡ Reload Geral"; font.pixelSize: 11 }

                                    MouseArea {
                                        id: b3ma
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: function(mouse) {
                                            mouse.accepted = true;
                                            Quickshell.execDetached(["python3", root.pyScript, "action", "reload_all"]);
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
