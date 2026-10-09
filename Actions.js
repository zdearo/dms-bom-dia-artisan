.pragma library

// Fixed argv for the two things this plugin launches. Pure; the daemon hands
// the result to Proc.runCommand, which passes every element as a positional
// argument — nothing from the feed is ever parsed by a shell.

function openUrlArgv(url) {
  var u = typeof url === "string" ? url : "";
  if (!/^https?:\/\/[^\s"'<>]+$/.test(u))
    return [];
  return ["xdg-open", u];
}

// The toast. `dms notify` has no click action, so unlike the omarchy version a
// toast announces the edition and does not open the panel; "--" keeps feed
// text that starts with a dash from being read as a flag.
function notifyArgv(title, body, iconPath) {
  if (!title)
    return [];
  return ["dms", "notify", "--app", "Bom Dia, Artisan",
    "--icon", String(iconPath || "dialog-information"), "--",
    String(title), String(body || "")];
}
