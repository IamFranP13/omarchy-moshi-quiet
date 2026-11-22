import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Moshi phone notifications switch.
// ON  (moshi-hook.service active): phone icon, always visible.
// OFF (service stopped): hidden like an inactive Omarchy indicator, revealed
//      while the pointer is on the bar; click to turn back on.
// Not installed (no moshi-hook.service unit): revealed on hover like OFF, with
//      a tooltip saying so; click opens the moshi-hook install guide.
// No keybinding is shipped. Bind your own to:
//   omarchy-shell io.github.iamfranp13.moshi-quiet toggle   (also: enable, disable)
BarWidget {
  id: root
  moduleName: "io.github.iamfranp13.moshi-quiet"

  readonly property string service: "moshi-hook.service"
  readonly property string installUrl: "https://getmoshi.app/docs/install-moshi-hook"
  // true: silencing also disables autostart, so it survives a reboot.
  // false: silence lasts until the next reboot (service just stopped).
  readonly property bool persistAcrossReboot: setting("persistAcrossReboot", true) !== false

  property bool installed: false
  property bool pushing: false
  readonly property bool revealed: !!root.bar
    && root.bar.centerSectionRevealHeld === true
    && root.bar.centerHoverRevealSuppressed !== true

  // Join of switchProc exit + stderr, which finish in no guaranteed order.
  property int switchExitCode: 0
  property bool switchExited: false
  property bool switchErrRead: false
  property string switchErr: ""

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function notify(body) {
    Quickshell.execDetached(["notify-send", "-a", "Moshi", "-u", "critical", "Moshi", body])
  }

  function setPushing(on) {
    if (switchProc.running) return
    if (!root.installed) {
      root.notify(strings.t("error.notInstalled"))
      return
    }
    var action = on ? ["enable", "--now"] : (root.persistAcrossReboot ? ["disable", "--now"] : ["stop"])
    root.switchExited = false
    root.switchErrRead = false
    root.switchErr = ""
    switchProc.command = ["systemctl", "--user"].concat(action).concat([root.service])
    switchProc.running = true
  }

  function toggle() { setPushing(!root.pushing) }

  function activate() {
    if (root.installed) root.toggle()
    else Quickshell.execDetached(["xdg-open", root.installUrl])
  }

  function finishSwitch() {
    if (!root.switchExited || !root.switchErrRead) return
    if (root.switchExitCode !== 0) {
      var detail = root.switchErr.trim()
      root.notify(strings.t("error.switchFailed").arg(detail !== "" ? detail : ("exit " + root.switchExitCode)))
    }
    // Every bar (one per monitor) re-reads the state, not only this one.
    root.broadcast("refresh")
  }

  visible: root.pushing || root.revealed
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  ShellIpc {
    target: "io.github.iamfranp13.moshi-quiet"

    function toggle(): void { root.toggle() }
    function enable(): void { root.setPushing(true) }
    function disable(): void { root.setPushing(false) }
    function refresh(): void { root.broadcast("refresh") }
  }

  // Prints LoadState then ActiveState, one per line ("not-found" when the
  // unit does not exist).
  Process {
    id: statusProc
    command: ["systemctl", "--user", "show", "--value", "-p", "LoadState", "-p", "ActiveState", root.service]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = text.trim().split("\n")
        root.installed = lines.length >= 1 && lines[0] !== "" && lines[0] !== "not-found"
        root.pushing = root.installed && lines.length >= 2 && lines[1] === "active"
      }
    }
  }

  Process {
    id: switchProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.switchErr = text
        root.switchErrRead = true
        root.finishSwitch()
      }
    }
    onExited: function(exitCode) {
      root.switchExitCode = exitCode
      root.switchExited = true
      root.finishSwitch()
    }
  }

  Timer {
    interval: 10000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.pushing ? "\u{f011c}" : "\u{f0122}"
    dimmed: !root.pushing
    slotSize: Style.bar.statusSlot
    tooltipText: !root.installed ? strings.t("tooltip.notInstalled")
      : (root.pushing ? strings.t("tooltip.on") : strings.t("tooltip.off"))
    onPressed: root.activate()
  }
}
