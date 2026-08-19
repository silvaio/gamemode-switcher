import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "silvaio.gamemode"

  readonly property string helperPath: Qt.resolvedUrl("gamemode.sh").toString().replace(/^file:\/\//, "")
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/gamemode"
  function truthy(value) {
    return value === true || value === 1 || value === "true" || value === "1"
  }

  readonly property bool steamGamescope: truthy(setting("steamGamescope", false))

  property bool gameModeActive: false
  property bool steamInstalled: false
  property bool gamescopeInstalled: false
  property var launchers: []

  readonly property string icon: "󰊴"
  readonly property color foreground: bar ? bar.barForeground : Color.foreground

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function ingestStatus(line) {
    var raw = String(line || "").trim()
    if (!raw) return
    try {
      var parsed = JSON.parse(raw)
      root.gameModeActive = parsed.active === true
      root.steamInstalled = parsed.steam === true
      root.gamescopeInstalled = parsed.gamescope === true
    } catch (e) {}
  }

  function ingestLaunchers(line) {
    var raw = String(line || "").trim()
    if (!raw) return
    try {
      var parsed = JSON.parse(raw)
      root.launchers = Array.isArray(parsed) ? parsed : []
    } catch (e) {}
  }

  function refresh() {
    statusProbe.running = false
    statusProbe.running = true
    launcherProbe.running = false
    launcherProbe.running = true
  }

  function enterGameMode() {
    var args = ["bash", root.helperPath, "enter"]
    if (root.steamGamescope) args.push("--steam-gamescope")
    Quickshell.execDetached(args)
    Qt.callLater(root.refresh)
  }

  function exitGameMode() {
    Quickshell.execDetached(["bash", root.helperPath, "exit"])
    Qt.callLater(root.refresh)
  }

  function setGameMode(on) {
    if (on) root.enterGameMode()
    else root.exitGameMode()
  }

  function launch(id) {
    Quickshell.execDetached(["bash", root.helperPath, "launch", String(id)])
    root.close()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Process {
    id: statusProbe
    running: true
    command: ["bash", root.helperPath, "status"]
    stdout: SplitParser {
      onRead: function(line) { root.ingestStatus(line) }
    }
  }

  Process {
    id: launcherProbe
    running: true
    command: ["bash", root.helperPath, "launchers"]
    stdout: SplitParser {
      onRead: function(line) { root.ingestLaunchers(line) }
    }
  }

  FileView {
    path: root.stateDir
    watchChanges: true
    printErrors: false
    onFileChanged: root.refresh()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "silvaio.gamemode"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function enter(): void { root.enterGameMode() }
    function exit(): void { root.exitGameMode() }
    function toggleMode(): void { root.setGameMode(!root.gameModeActive) }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    active: root.gameModeActive
    activeColor: Color.accent
    tooltipText: root.gameModeActive ? "Game Mode on — click to manage" : "Game Mode"
    onPressed: function(b) { root.toggle() }
  }
}
