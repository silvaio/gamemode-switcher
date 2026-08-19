import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "silvaio.gamemode"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool gameModeActive: hostWidget && hostWidget.gameModeActive === true
  readonly property bool steamInstalled: hostWidget && hostWidget.steamInstalled === true
  readonly property bool gamescopeInstalled: hostWidget && hostWidget.gamescopeInstalled === true
  readonly property var launchers: hostWidget && hostWidget.launchers ? hostWidget.launchers : []
  function truthy(value) {
    return value === true || value === 1 || value === "true" || value === "1"
  }

  readonly property bool steamGamescope: truthy(setting("steamGamescope", false))

  function open() {
    root.controller.show()
    if (hostWidget && hostWidget.refresh) hostWidget.refresh()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setSteamGamescope(on) {
    persistSettings({ steamGamescope: !!on })
  }

  function setGameMode(on) {
    if (hostWidget && hostWidget.setGameMode) hostWidget.setGameMode(on)
    if (on) root.close()
  }

  function launch(id) {
    if (hostWidget && hostWidget.launch) hostWidget.launch(id)
  }

  readonly property string steamDescription: {
    if (root.gamescopeInstalled && root.steamInstalled)
      return "Enter Game Mode starts a fullscreen Gamescope session with Steam's Deck UI. Quitting Steam restores the desktop."
    if (root.steamInstalled)
      return "Enter Game Mode launches Steam Big Picture. Install Gamescope for a nested session. Quitting Steam restores the desktop."
    return "Install Steam from Omarchy → Install → Gaming, optionally with Gamescope. Quitting Steam restores the desktop."
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(12)
        padding: Style.space(16)

        PanelHero {
          width: parent.width
          title: "Game Mode"
          meta: root.gameModeActive ? "Desktop optimized for play" : "One click to a clean gaming session"
          detail: root.gameModeActive ? "ON" : "OFF"
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              text: "󰊴"
              color: root.foreground
              font.pixelSize: Style.font.display
              font.family: root.fontFamily
            }
          }
          trailingControl: Component {
            ToggleSwitch {
              checked: root.gameModeActive
              foreground: root.foreground
              accent: Color.accent
              onToggled: root.setGameMode(!root.gameModeActive)
            }
          }
        }

        Button {
          width: parent.width
          text: root.gameModeActive ? "Exit Game Mode" : "Enter Game Mode"
          foreground: root.foreground
          fontFamily: root.fontFamily
          bordered: true
          onClicked: root.setGameMode(!root.gameModeActive)
        }

        PanelSeparator { foreground: root.foreground }

        Toggle {
          width: parent.width
          label: "Steam in Gamescope"
          description: root.steamDescription
          checked: root.steamGamescope
          foreground: root.foreground
          accent: Color.accent
          fontFamily: root.fontFamily
          onClicked: root.setSteamGamescope(!root.steamGamescope)
        }

        PanelSeparator {
          visible: root.launchers.length > 0
          foreground: root.foreground
        }

        PanelSectionHeader {
          visible: root.launchers.length > 0
          text: "Quick Launch"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Flow {
          visible: root.launchers.length > 0
          width: parent.width
          spacing: Style.space(8)

          Repeater {
            model: root.launchers

            Button {
              required property var modelData
              text: modelData.name
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.launch(modelData.id)
            }
          }
        }

        Text {
          width: parent.width
          text: root.gameModeActive
            ? "Bar is hidden. Super+Shift+Space shows it again, then exit Game Mode."
            : "Hides the bar, silences notifications, stays awake, and drops Hyprland animations."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
