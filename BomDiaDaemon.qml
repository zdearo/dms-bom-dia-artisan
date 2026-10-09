import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins
import "Actions.js" as Actions
import "Model.js" as Model
import "Source.js" as Source

// The one fetcher, and the only writer of the cache, the read-marks and the
// toasts. A daemon is instantiated once, so there is no leader to elect: the
// bar and the panel render from the "view" published here, and ask for work by
// writing a "command" the same way. Both go through PluginService.setGlobalVar.
//
// What to fetch, when, and what counts as news is decided in Source.js and
// Model.js, which `node --test` runs directly. This file only moves bytes.
PluginComponent {
  id: root

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/bom-dia-artisan"
  readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/bom-dia-artisan"
  readonly property string checkAt: String(root.pluginData.checkAt || Source.DEFAULT_CHECK_AT)
  readonly property bool notifyEnabled: root.pluginData.notify !== false

  function pathOf(rel) {
    var url = Qt.resolvedUrl(rel).toString();
    return url.indexOf("file://") === 0 ? decodeURIComponent(url.substring(7)) : url;
  }

  QtObject {
    id: internal
    property var editions: []
    property var read: []
    property string notified: ""
    property bool stateKnown: false    // the state file has been tried
    property bool hadState: false      // ...and existed
    property bool dirsReady: false
    property bool cacheKnown: false    // the cache file has been tried
    property double lastAttemptMs: 0
    // Set by a 429: no request, scheduled or clicked, before this time.
    property double notBeforeMs: 0
    // When a full list last came back (the cache's fetchedAt). Also what tells
    // Source.planCheck whether today's list has run, so a late day's retries
    // can be cheap probes.
    property double lastOkMs: 0
    property string error: ""
    property int failures: 0
    property bool inFlight: false
    // What the request in flight asked for: { kind: "list" | "probe", date }.
    property var plan: null
    // Counts requests. A guard that gives up on a request bumps it, so a late
    // answer from that request is ignored instead of being taken for the next.
    property int requestSeq: 0
  }

  property int lastCommandSeq: 0

  // ------------------------------------------------------------ the view --

  // What the bar and the panel draw from. Published on every change; the views
  // keep their own clock for relative times ("há 5 min").
  function publish() {
    PluginService.setGlobalVar(root.pluginId, "view", {
      summary: Model.summarize({
        editions: internal.editions,
        read: internal.read,
        error: internal.error,
        lastOkMs: internal.lastOkMs
      }),
      busy: internal.inFlight
    });
  }

  // Requests from the bar and the panel. A command is a new value of the
  // "command" variable with a fresh seq; the seq stops a repeat from being
  // mistaken for the one already run.
  Connections {
    target: PluginService
    function onGlobalVarChanged(changedPluginId, varName) {
      if (changedPluginId !== root.pluginId || varName !== "command") return;
      var c = PluginService.getGlobalVar(root.pluginId, "command", null);
      if (!c || c.seq === root.lastCommandSeq) return;
      root.lastCommandSeq = c.seq;
      root.command(c.name, c.args || {});
    }
  }

  function command(name, args) {
    if (name === "refresh") root.refresh(true);
    else if (name === "markRead") root.markRead(args.date);
    else if (name === "markAllRead") root.markAllRead();
    else if (name === "openUrl") root.openUrl(args.url);
  }

  // ----------------------------------------------------------------- actions --

  function openUrl(url) {
    var argv = Actions.openUrlArgv(url);
    if (argv.length) Proc.runCommand(root.pluginId + ".open", argv, function () {}, 0);
  }

  function markRead(date) {
    var next = Model.markRead(internal.read, date);
    if (next.length === internal.read.length) return;
    internal.read = next;
    root.saveState();
    root.publish();
  }

  function markAllRead() {
    internal.read = Model.markAllRead(internal.read, internal.editions);
    root.saveState();
    root.publish();
  }

  // ------------------------------------------------------------- the files --

  function saveState() {
    if (!internal.dirsReady) return;
    stateFile.setText(JSON.stringify({ read: internal.read, notified: internal.notified }, null, 2) + "\n");
  }

  function markCacheKnown() {
    if (internal.cacheKnown) return;
    internal.cacheKnown = true;
    root.maybeCheck();
  }

  function applyState(text) {
    try {
      var doc = JSON.parse(String(text || ""));
      internal.read = Model.cleanRead(doc.read);
      internal.notified = typeof doc.notified === "string" ? doc.notified : "";
      internal.hadState = true;
    } catch (e) {
      // A corrupt state file is treated as no state: worst case, one edition
      // shows as unread again.
      internal.hadState = false;
    }
    internal.stateKnown = true;
    root.afterData();
  }

  function applyCache(text) {
    try {
      var doc = JSON.parse(String(text || ""));
      var res = Model.normalize(doc.reports);
      if (!res.ok) return;
      internal.editions = res.editions;
      if (doc.fetchedAt > internal.lastOkMs) internal.lastOkMs = doc.fetchedAt;
      root.afterData();
    } catch (e) {
      // Ignore a half-written or foreign cache; the next fetch replaces it.
    }
  }

  // Runs whenever editions or read-marks change. Then the view is republished.
  function afterData() {
    root.reconcile();
    root.publish();
  }

  // First run seeds the read-marks (one unread edition, not sixteen) without a
  // toast; afterwards, a fresh edition is announced exactly once.
  function reconcile() {
    if (!internal.stateKnown || !internal.editions.length) return;

    if (!internal.hadState) {
      internal.read = Model.seedRead(internal.editions);
      internal.notified = internal.editions[0].date;
      internal.hadState = true;
      root.saveState();
      return;
    }

    if (!root.notifyEnabled) return;
    var e = Model.notifyCandidate(internal.editions, internal.read, internal.notified, Date.now());
    if (!e) return;
    // Persist BEFORE sending, so a restart can never announce the same edition
    // twice.
    internal.notified = e.date;
    root.saveState();
    var body = Model.headline(e) + "\n" + Model.truncate(e.summary, 220);
    var argv = Actions.notifyArgv(e.title, body, root.pathOf("assets/logo.png"));
    if (argv.length) Proc.runCommand(root.pluginId + ".notify", argv, function () {}, 0);
  }

  // ------------------------------------------------------------------- fetch --

  function refresh(force) {
    if (internal.inFlight || !internal.dirsReady) return;
    // Rate limited: a click would only earn another 429.
    if (Date.now() < internal.notBeforeMs) return;
    var now = Date.now();
    var plan = Source.planCheck({
      nowMs: now,
      checkAt: root.checkAt,
      lastListOkMs: internal.lastOkMs,
      failures: internal.failures,
      force: force === true
    });
    var argv = Source.request(plan.kind, plan.date);
    internal.lastAttemptMs = now;
    if (!argv.length) { root.fail("Pedido inválido"); return; }
    internal.plan = plan;
    internal.inFlight = true;
    var id = ++internal.requestSeq;
    root.publish();
    guard.interval = Source.timeoutMs();
    guard.restart();
    Proc.runCommand(root.pluginId + ".fetch", argv, function (stdout, exitCode) {
      root.fetched(id, stdout, exitCode);
    }, 0);
  }

  function fetched(id, stdout, exitCode) {
    if (id !== internal.requestSeq) return;
    guard.stop();
    internal.inFlight = false;
    var res = Source.parse(stdout, exitCode, Date.now(), internal.plan);
    if (!res.ok) root.fail(res.error, res.retryAfterMs || 0);
    else if (res.pending || res.arrived) root.probed(res);
    else root.succeed(res);
    root.publish();
  }

  function succeed(res) {
    var norm = Model.normalize(res.doc);
    if (!norm.ok) { root.fail(norm.error); return; }
    internal.failures = 0;
    internal.error = "";
    internal.lastOkMs = Date.now();
    internal.editions = norm.editions;
    cacheFile.setText(JSON.stringify({ fetchedAt: internal.lastOkMs, reports: res.doc }));
    root.afterData();
  }

  // A probe's answer. Neither one is cached: only a list is.
  function probed(res) {
    internal.failures = 0;
    internal.error = "";
    // Out at last: fetch the whole list now, one request after the probe. On
    // the next tick, so the probe's own completion is not re-entered.
    if (res.arrived) Qt.callLater(function () { root.refresh(true); });
    // Otherwise not out yet: checkDue asks again in an hour.
  }

  function fail(reason, retryAfterMs) {
    internal.failures += 1;
    internal.error = reason;
    if (retryAfterMs > 0) internal.notBeforeMs = Date.now() + retryAfterMs;
    root.publish();
  }

  // Asked once a minute (and at startup): is the day's check due? Only after
  // the cache has been read — otherwise every restart would fetch before
  // finding out that today's edition is already on disk.
  function maybeCheck() {
    if (!internal.dirsReady || !internal.cacheKnown) return;
    var now = Date.now();
    if (Source.checkDue({
      nowMs: now,
      checkAt: root.checkAt,
      newestDate: internal.editions.length > 0 ? internal.editions[0].date : "",
      lastAttemptMs: internal.lastAttemptMs,
      failures: internal.failures,
      notBeforeMs: internal.notBeforeMs
    }))
      root.refresh(false);
  }

  // Every request gets a hard guard, on top of curl's own --max-time.
  Timer {
    id: guard
    repeat: false
    onTriggered: {
      internal.requestSeq += 1;
      internal.inFlight = false;
      root.fail("O site demorou demais para responder");
    }
  }

  // The one clock for "is the day's check due". Wall-clock based, so it is
  // right again one minute after a resume from suspend — see Source.checkDue.
  Timer {
    interval: 60000
    repeat: true
    running: true
    onTriggered: root.maybeCheck()
  }

  FileView {
    id: stateFile
    path: root.stateDir + "/state.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyState(text())
    onLoadFailed: {
      internal.stateKnown = true;
      root.afterData();
    }
  }

  FileView {
    id: cacheFile
    path: root.cacheDir + "/reports.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.applyCache(text());
      root.markCacheKnown();
    }
    onLoadFailed: root.markCacheKnown()
  }

  Component.onCompleted: {
    Proc.runCommand(root.pluginId + ".mkdir", ["mkdir", "-p", root.stateDir, root.cacheDir], function () {
      internal.dirsReady = true;
      root.maybeCheck();
    }, 0);
    root.publish();
  }
}
