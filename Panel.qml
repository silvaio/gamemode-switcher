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
      return "Enter starts Steam's Deck UI. Quit Steam to restore the desktop."
    if (root.steamInstalled)
      return "Enter starts Steam Big Picture. Quit Steam to restore the desktop."
    return "Install Steam from Omarchy → Gaming. Quit Steam to restore the desktop."
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(480))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        PanelHero {
          width: parent.width
          title: "Game Mode"
          meta: root.gameModeActive ? "Optimized for play" : "Clean gaming session"
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: root.gameModeActive ? 1.0 : 0.7
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

        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "SESSION"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            width: parent.width
            spacing: Style.space(20)

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.spacing.labelGap
              InfoPair { label: "Notifications"; value: "Silent" }
              InfoPair { label: "Sleep"; value: "Stay awake" }
              InfoPair { label: "Night light"; value: "Off" }
            }

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.spacing.labelGap
              InfoPair { label: "Power"; value: "Performance" }
              InfoPair { label: "Animations"; value: "Off" }
              InfoPair { label: "Gaps"; value: "Off" }
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "STEAM"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Toggle {
            width: parent.width
            label: "Gamescope session"
            description: root.steamDescription
            checked: root.steamGamescope
            foreground: root.foreground
            accent: Color.accent
            fontFamily: root.fontFamily
            onClicked: root.setSteamGamescope(!root.steamGamescope)
          }
        }

        PanelSeparator {
          visible: root.launchers.length > 0
          foreground: root.foreground
        }

        Column {
          visible: root.launchers.length > 0
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "QUICK LAUNCH"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Flow {
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
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    Text {
      text: label
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Item {
      width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2)
      height: 1
    }

    Text {
      text: value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
