import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginComponent {
    id: root

    pluginId: "intelGpuMonitor"
    layerNamespacePlugin: "intel-gpu-monitor"

    // ---- Live state -------------------------------------------------------
    readonly property var metricKeys: ["usage", "vram", "temp"]

    // From the cheap sysfs sampler (FileView):
    property real freqMHz: -1
    property real tempC: -1
    property bool tempIsDie: false          // true = CPU-die/package fallback (iGPU)
    property real memTotalMB: 0             // system RAM (shared-mem denominator)
    property bool sampled: false

    // From the fdinfo scan (accurate engine-busy, memory, per-process):
    property real usagePercent: -1          // 0..100, -1 unknown
    property real vramUsedMB: 0
    property real vramTotalMB: 0
    property real vramPercent: -1           // -1 unknown
    property bool vramSupported: false
    property bool vramIsDiscrete: false     // local (Arc) vs system (shared) memory
    property var clients: []                // [{name,pid,gpu,vramMB,vramPercent}]
    property var engineBusy: ({})           // {Render/3D: n, ...}
    property bool fdinfoRan: false

    property bool popoutActive: false
    property string popoutMode: "detail"    // "detail" | "menu"

    // sysfs sampler paths (resolved once by discovery)
    property string _pathFreq: ""
    property string _pathTemp: ""
    readonly property string _wantDev: wantDeviceId()
    // fdinfo delta bookkeeping
    property var _prevEng: ({})             // clientId -> {render,copy,video,venh,compute,capv}
    property real _prevScanT: -1

    // ---- Settings helpers -------------------------------------------------
    function pv(key, fallback) {
        return pluginData[key] !== undefined ? pluginData[key] : fallback;
    }
    function pollInterval() { return Math.max(500, Number(pv("pollInterval", 2000))); }
    function commandPrefix() { return String(pv("commandPrefix", "")).trim(); }
    function tempMin() { return Number(pv("tempMin", 30)); }
    function tempMax() { return Number(pv("tempMax", 100)); }
    function vramOverrideMB() { return Number(pv("vramTotalMbOverride", 0)); }
    function wantDeviceId() {
        const pci = String(pv("tempGpuPciId", "")).trim();
        const m = pci.match(/([0-9a-fA-F]{4})$/);
        return m ? m[1].toLowerCase() : "";
    }
    function terminalEnabled() { return pv("terminalEnabled", true); }
    function resolvedTerminal() {
        const configured = String(pv("terminalCommand", "")).trim();
        if (configured.length > 0)
            return configured;
        const envTerm = Quickshell.env("TERMINAL");
        if (envTerm && String(envTerm).trim().length > 0)
            return String(envTerm).trim();
        return "kitty";
    }
    function terminalExecFlag(termCmd) {
        const base = String(termCmd).split("/").pop().split(" ")[0];
        switch (base) {
        case "gnome-terminal": return "--";
        case "wezterm": return "start --";
        default: return "-e";
        }
    }
    function leftClickAction() { return String(pv("leftClickAction", "detail")); }
    function rightClickAction() { return String(pv("rightClickAction", "menu")); }
    function middleClickAction() { return String(pv("middleClickAction", "nothing")); }

    function showValue(m) { return pv(m + "ShowValue", m !== "vram"); }
    function showChart(m) { return pv(m + "ShowChart", m === "usage"); }
    function chartType(m) { return String(pv(m + "ChartType", defaultChartType(m))); }
    function barWidthFraction(m) { return Math.max(0.02, Math.min(1, Number(pv(m + "BarThickness", 35)) / 100)); }
    function showIcon(m) { return pv(m + "ShowIcon", false); }
    function iconName(m) {
        const custom = String(pv(m + "IconName", "")).trim();
        return custom.length > 0 ? custom : defaultIcon(m);
    }

    function defaultChartType(m) {
        switch (m) {
        case "usage": return "gauge";
        case "vram": return "bar";
        case "temp": return "thermometer";
        }
        return "gauge";
    }
    function defaultIcon(m) {
        switch (m) {
        case "usage": return "speed";
        case "vram": return "memory";
        case "temp": return "device_thermostat";
        }
        return "developer_board";
    }
    function metricLabel(m) {
        switch (m) {
        case "usage": return "GPU Usage";
        case "vram": return "VRAM";
        case "temp": return tempIsDie ? "GPU Temp (die)" : "GPU Temp";
        }
        return m;
    }

    // ---- Derived visibility ----------------------------------------------
    function metricVisible(m) { return showValue(m) || showChart(m); }
    function visibleMetrics() {
        const out = [];
        for (const m of metricKeys)
            if (metricVisible(m)) out.push(m);
        return out;
    }
    readonly property var enabledMetrics: visibleMetrics()
    readonly property bool usageVisible: metricVisible("usage")
    readonly property bool vramVisible: metricVisible("vram")
    readonly property bool tempVisible: metricVisible("temp")
    readonly property bool detailOpen: popoutActive && popoutMode === "detail"

    // fdinfo scan feeds usage/vram/process-table. sysfs feeds temp/freq.
    readonly property bool needsFdinfo: usageVisible || vramVisible || detailOpen
    readonly property bool needsSysfs: tempVisible || detailOpen

    // ---- Values -----------------------------------------------------------
    function metricKnown(m) {
        switch (m) {
        case "usage": return usagePercent >= 0;
        case "vram": return vramSupported && vramPercent >= 0;
        case "temp": return tempC > 0;
        }
        return false;
    }
    function metricRawValue(m) {
        switch (m) {
        case "usage": return usagePercent;
        case "vram": return vramPercent;
        case "temp": return tempC;
        }
        return 0;
    }
    function metricProgress(m) {
        if (m === "temp") {
            const lo = tempMin();
            const hi = Math.max(lo + 1, tempMax());
            return Math.max(0, Math.min(1, (tempC - lo) / (hi - lo)));
        }
        return Math.max(0, Math.min(1, metricRawValue(m) / 100));
    }
    function metricValueText(m) {
        if (!metricKnown(m))
            return m === "temp" ? "--°" : "--%";
        if (m === "temp")
            return Math.round(tempC) + "°";
        return Math.round(metricRawValue(m)) + "%";
    }
    function metricColor(m) {
        if (!metricKnown(m))
            return Theme.surfaceVariantText;
        const p = metricProgress(m);
        if (p >= 0.9)
            return Theme.error;
        if (p >= 0.75)
            return (Theme.warning && Theme.warning.toString) ? Theme.warning : Qt.color("#f5a623");
        return Theme.primary;
    }

    // ======================================================================
    // Cheap sysfs sampler (FileView) -> die temp + frequency
    // ======================================================================
    function discoveryScript() {
        const want = wantDeviceId();
        return `
WANT='${want}'
CARD=""
for c in /sys/class/drm/card*; do
  [ -r "$c/device/vendor" ] || continue
  [ "$(cat "$c/device/vendor" 2>/dev/null)" = "0x8086" ] || continue
  [ -d "$c/gt" ] || continue
  if [ -n "$WANT" ]; then
    dev="$(cat "$c/device/device" 2>/dev/null)"
    case "$dev" in *"$WANT") CARD="$c"; break;; esac
  else
    CARD="$c"; break
  fi
done
[ -z "$CARD" ] && { for c in /sys/class/drm/card*; do [ "$(cat "$c/device/vendor" 2>/dev/null)" = "0x8086" ] && [ -d "$c/gt" ] && { CARD="$c"; break; }; done; }
[ -z "$CARD" ] && { echo "ERR=nocard"; exit 0; }
for g in "$CARD"/gt/gt0 "$CARD"/gt/gt*; do
  [ -f "$g/rps_act_freq_mhz" ] && { echo "FREQ=$g/rps_act_freq_mhz"; break; }
done
TEMP=""; TEMPSRC=""
for h in "$CARD"/device/hwmon/hwmon*; do
  [ -d "$h" ] || continue
  for t in "$h"/temp*_input; do [ -r "$t" ] && { TEMP="$t"; TEMPSRC="gpu"; break; }; done
  [ -n "$TEMP" ] && break
done
if [ -z "$TEMP" ]; then
  for h in /sys/class/hwmon/hwmon*; do
    [ "$(cat "$h/name" 2>/dev/null)" = "coretemp" ] || continue
    for l in "$h"/temp*_label; do
      [ "$(cat "$l" 2>/dev/null)" = "Package id 0" ] || continue
      idx="\${l%_label}"; TEMP="\${idx}_input"; TEMPSRC="die"; break
    done
    [ -n "$TEMP" ] && break
  done
fi
echo "TEMP=$TEMP"
echo "TEMPSRC=$TEMPSRC"
echo "MEMTOTAL=$(awk '/MemTotal/{print $2; exit}' /proc/meminfo 2>/dev/null)"
`;
    }

    function _applyDiscovery(text) {
        const kv = {};
        for (const line of String(text).split("\n")) {
            const eq = line.indexOf("=");
            if (eq > 0) kv[line.slice(0, eq)] = line.slice(eq + 1).trim();
        }
        _pathFreq = kv.FREQ || "";
        _pathTemp = kv.TEMP || "";
        tempIsDie = kv.TEMPSRC === "die";
        if (kv.MEMTOTAL) memTotalMB = Number(kv.MEMTOTAL) / 1024;
        sampled = true;
    }

    function runDiscovery() { discoveryProcess.running = true; }
    on_WantDevChanged: Qt.callLater(runDiscovery)

    Process {
        id: discoveryProcess
        command: ["sh", "-c", root.discoveryScript()]
        stdout: StdioCollector {
            onStreamFinished: root._applyDiscovery(text)
        }
    }

    FileView {
        id: freqView
        path: root._pathFreq
        blockLoading: false
        watchChanges: false
        printErrors: false
        onLoaded: { const v = Number(text()); if (v >= 0) root.freqMHz = v; }
    }
    FileView {
        id: tempView
        path: root._pathTemp
        blockLoading: false
        watchChanges: false
        printErrors: false
        onLoaded: { const v = Number(text()); if (v > 0) root.tempC = v / 1000; }
    }
    Timer {
        id: sysfsTimer
        interval: root.pollInterval()
        repeat: true
        running: root.needsSysfs && root._barRevealed
        triggeredOnStart: true
        onTriggered: {
            if (freqView.path) freqView.reload();
            if (tempView.path) tempView.reload();
        }
    }

    // ======================================================================
    // fdinfo scan -> engine busy %, VRAM, per-process (no PMU, no privilege)
    //
    // One awk pass over /proc/*/fdinfo/*, filtered to the Intel driver (i915/xe)
    // so an idle discrete GPU is never counted. Deltas of the per-engine ns
    // counters over wall time give accurate busy % (matching intel_gpu_top).
    // ======================================================================
    function fdinfoScript() {
        return `awk '
BEGINFILE { if (ERRNO) { nextfile } }
function tob(v,u){ if(u=="KiB")return v*1024; if(u=="MiB")return v*1048576; if(u=="GiB")return v*1073741824; return v+0 }
FNR==1 { split(FILENAME,a,"/"); pid=a[3]; cur=""; skip=0; drv="" }
/^drm-driver:/ { drv=$2; next }
/^drm-client-id:/ {
  cur=$2
  if (drv!="i915" && drv!="xe") { skip=1; cur=""; next }
  if (cur in done) { skip=1; next }
  skip=0; done[cur]=1; pidOf[cur]=pid; next
}
skip { next }
cur=="" { next }
/^drm-engine-render:/ { r[cur]=$2+0; next }
/^drm-engine-copy:/ { cp[cur]=$2+0; next }
/^drm-engine-video:/ { vd[cur]=$2+0; next }
/^drm-engine-video-enhance:/ { ve[cur]=$2+0; next }
/^drm-engine-compute:/ { co[cur]=$2+0; next }
/^drm-engine-capacity-video:/ { capv[cur]=$2+0; next }
/^drm-resident-system/ { rs[cur]+=tob($2,$3); next }
/^drm-resident-local/ { rl[cur]+=tob($2,$3); next }
END {
  for (c in pidOf) {
    p=pidOf[c]; nm="?"; cf="/proc/" p "/comm"
    if ((getline line < cf) > 0) nm=line
    close(cf)
    print c, p, r[c]+0, cp[c]+0, vd[c]+0, ve[c]+0, co[c]+0, (capv[c]?capv[c]:1), rs[c]+0, rl[c]+0, nm
  }
}
' /proc/[0-9]*/fdinfo/* 2>/dev/null`;
    }

    function _applyFdinfo(text) {
        const now = Date.now();
        const rows = [];
        const nowEng = {};
        let systemTotal = 0, localTotal = 0, anyLocal = false;

        for (const ln of String(text).split("\n")) {
            if (!ln) continue;
            const f = ln.split(/\s+/);
            if (f.length < 11) continue;
            const cid = f[0];
            const rec = {
                "cid": cid,
                "pid": parseInt(f[1], 10) || 0,
                "render": Number(f[2]) || 0,
                "copy": Number(f[3]) || 0,
                "video": Number(f[4]) || 0,
                "venh": Number(f[5]) || 0,
                "compute": Number(f[6]) || 0,
                "capv": Number(f[7]) || 1,
                "resSys": Number(f[8]) || 0,
                "resLoc": Number(f[9]) || 0,
                "name": f.slice(10).join(" ")
            };
            nowEng[cid] = rec;
            systemTotal += rec.resSys;
            localTotal += rec.resLoc;
            if (rec.resLoc > 0) anyLocal = true;
            rows.push(rec);
        }

        // Aggregate engine busy over the interval.
        if (_prevScanT > 0 && now > _prevScanT) {
            const dtNs = (now - _prevScanT) * 1e6;
            const agg = { render: 0, copy: 0, video: 0, venh: 0, compute: 0 };
            let capVideo = 1;
            for (const c of rows) {
                const p = _prevEng[c.cid];
                if (!p) continue;
                agg.render += Math.max(0, c.render - p.render);
                agg.copy += Math.max(0, c.copy - p.copy);
                agg.video += Math.max(0, c.video - p.video);
                agg.venh += Math.max(0, c.venh - p.venh);
                agg.compute += Math.max(0, c.compute - p.compute);
                capVideo = Math.max(capVideo, c.capv);
            }
            const pct = ns => Math.max(0, Math.min(100, ns / dtNs * 100));
            const busy = {
                "Render/3D": pct(agg.render),
                "Blitter": pct(agg.copy),
                "Video": pct(agg.video / capVideo),
                "VideoEnhance": pct(agg.venh),
                "Compute": pct(agg.compute)
            };
            engineBusy = busy;
            usagePercent = Math.max(busy["Render/3D"], busy["Blitter"], busy["Video"], busy["VideoEnhance"], busy["Compute"]);

            for (const c of rows) {
                const p = _prevEng[c.cid];
                let g = 0;
                if (p) {
                    const d = Math.max(
                        c.render - p.render, c.copy - p.copy,
                        (c.video - p.video) / (c.capv || 1),
                        c.venh - p.venh, c.compute - p.compute);
                    g = pct(d);
                }
                c.gpu = g;
            }
        } else {
            for (const c of rows) c.gpu = 0;
        }
        _prevEng = nowEng;
        _prevScanT = now;

        // VRAM: discrete Arc reports local memory; iGPU reports system memory.
        const discrete = anyLocal;
        vramIsDiscrete = discrete;
        const usedMB = (discrete ? localTotal : systemTotal) / 1048576;
        const overrideMB = vramOverrideMB();
        const totalMB = overrideMB > 0 ? overrideMB : (discrete ? 0 : memTotalMB);
        vramTotalMB = totalMB;
        vramUsedMB = usedMB;
        vramSupported = rows.length > 0;
        vramPercent = (vramSupported && totalMB > 0) ? Math.min(100, usedMB / totalMB * 100) : (vramSupported ? 0 : -1);

        const table = rows.map(c => {
            const mb = (discrete ? c.resLoc : c.resSys) / 1048576;
            return {
                "name": c.name,
                "pid": c.pid,
                "gpu": c.gpu || 0,
                "vramMB": mb,
                "vramPercent": totalMB > 0 ? (mb / totalMB) * 100 : 0
            };
        });
        table.sort((a, b) => (b.gpu - a.gpu) || (b.vramMB - a.vramMB));
        clients = table;
        fdinfoRan = true;
    }

    Process {
        id: fdinfoProcess
        command: ["sh", "-c", root.fdinfoScript()]
        stdout: StdioCollector {
            onStreamFinished: root._applyFdinfo(text)
        }
    }
    Timer {
        id: fdinfoTimer
        interval: root.pollInterval()
        repeat: true
        running: root.needsFdinfo && root._barRevealed
        triggeredOnStart: true
        onTriggered: if (!fdinfoProcess.running) fdinfoProcess.running = true
        onRunningChanged: {
            if (!running) {
                root._prevEng = ({});
                root._prevScanT = -1;
                root.usagePercent = -1;
                root.clients = [];
            }
        }
    }

    Component.onCompleted: root.runDiscovery()

    Process {
        id: terminalProcess
        running: false
    }

    // ---- Actions ----------------------------------------------------------
    // Left/right use BasePill's native, exactly-sized handling so the whole pill
    // (text included) is clickable with the correct cursor. Middle is handled by
    // a middle-only MouseArea in the pill (BasePill only does left/right).
    pillClickAction: () => root.dispatch(root.leftClickAction())
    pillRightClickAction: () => root.dispatch(root.rightClickAction())

    function dispatch(action) {
        switch (action) {
        case "detail": openPopoutMode("detail"); break;
        case "menu": openPopoutMode("menu"); break;
        case "terminal": openInTerminal(); break;
        default: break;
        }
    }
    // Nulling pillClickAction while calling triggerPopout() avoids recursion and
    // lets the base compute the popout position (works for both left and right
    // click). If the popout is already open, just swap its content live.
    function openPopoutMode(mode) {
        if (popoutActive) {
            if (popoutMode === mode)
                closePopout();
            else
                popoutMode = mode;
            return;
        }
        popoutMode = mode;
        const saved = pillClickAction;
        pillClickAction = null;
        triggerPopout();
        pillClickAction = saved;
    }
    function openInTerminal() {
        const term = resolvedTerminal();
        if (term.length === 0)
            return;
        const inner = commandPrefix().length > 0 ? (commandPrefix() + " intel_gpu_top") : "intel_gpu_top";
        const flag = terminalExecFlag(term);
        terminalProcess.command = ["sh", "-c", term + " " + flag + " sh -c '" + inner + "; echo; echo Press Enter to close; read _'"];
        terminalProcess.running = true;
    }

    // ---- Popout content (detail dialog OR menu) --------------------------
    popoutWidth: popoutMode === "menu" ? 260 : 560
    popoutContent: Component {
        Item {
            id: popoutRoot
            property var closePopout
            property var parentPopout: null
            width: root.popoutWidth
            implicitHeight: contentLoader.item ? contentLoader.item.implicitHeight : 200

            // Track the popout's REAL visibility. DankPopout hides (shouldBeVisible
            // = false) without destroying this content, so Component.onDestruction
            // alone is unreliable; watch shouldBeVisible so reopen/close works.
            Component.onCompleted: root.popoutActive = true
            Component.onDestruction: root.popoutActive = false
            onParentPopoutChanged: if (parentPopout) root.popoutActive = (parentPopout.shouldBeVisible === true)
            Connections {
                target: popoutRoot.parentPopout
                function onShouldBeVisibleChanged() {
                    root.popoutActive = (popoutRoot.parentPopout.shouldBeVisible === true);
                }
            }

            Loader {
                id: contentLoader
                width: parent.width
                sourceComponent: root.popoutMode === "menu" ? menuComp : detailComp
            }

            Component {
                id: detailComp
                IntelGpuDetail {
                    width: popoutRoot.width
                    pluginRoot: root
                }
            }
            Component {
                id: menuComp
                IntelGpuMenu {
                    width: popoutRoot.width
                    pluginRoot: root
                    onRequestClose: if (popoutRoot.closePopout) popoutRoot.closePopout()
                }
            }
        }
    }

    horizontalBarPill: Component {
        IntelGpuPill {
            pluginRoot: root
            isVerticalOrientation: false
        }
    }
    verticalBarPill: Component {
        IntelGpuPill {
            pluginRoot: root
            isVerticalOrientation: true
        }
    }
}
