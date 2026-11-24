import Foundation

/// The page a phone opens: one self-contained HTML document with inline CSS and JavaScript and
/// no external resources.
///
/// It does not know the timing rules. It counts down from the `ScheduleSnapshot` the server
/// sends, corrected for the difference between the server's clock and the phone's, and gets a
/// new snapshot over Server-Sent Events whenever the run changes. Commands are POSTs.
public enum PhonePage {
    /// Inline styles and scripts only, and requests back to the Mac only.
    public static let contentSecurityPolicy =
        "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'none'"

    /// The page. With `sample`, the page shows that state and never connects, for previews.
    public static func html(sample: PhoneState? = nil) -> String {
        var sampleScript = ""
        if let sample {
            // `</` would end the script element early.
            let json = String(decoding: sample.json(), as: UTF8.self).replacingOccurrences(of: "</", with: "<\\/")
            sampleScript = "<script>window.SAMPLE = \(json);</script>"
        }
        return template.replacingOccurrences(of: "<!--SAMPLE-->", with: sampleScript)
    }

    static let template = #"""
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="color-scheme" content="dark">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="referrer" content="no-referrer">
<title>Agenda Clock</title>
<style>
:root {
  --bg: #000; --text: #fff; --dim: rgba(255,255,255,.58); --faint: rgba(255,255,255,.18);
  --button: rgba(255,255,255,.12); --button-press: rgba(255,255,255,.24); --over: rgb(255,107,74);
}
* { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
html, body { margin: 0; height: 100%; background: var(--bg); color: var(--text);
  font-family: -apple-system, system-ui, "Helvetica Neue", sans-serif; }
body { display: flex; flex-direction: column; min-height: 100dvh;
  padding: max(16px, env(safe-area-inset-top)) max(18px, env(safe-area-inset-right))
           max(16px, env(safe-area-inset-bottom)) max(18px, env(safe-area-inset-left)); }
[hidden] { display: none !important; }
#banner { align-self: center; font-size: 14px; color: var(--dim); background: var(--button);
  border-radius: 999px; padding: 6px 14px; margin-bottom: 8px; }
main { flex: 1; display: flex; flex-direction: column; min-height: 0; }
#run { justify-content: space-between; gap: 14px; }
.clock { flex: 1; display: flex; flex-direction: column; justify-content: center; align-items: center;
  text-align: center; min-height: 0; }
.time { font-weight: 600; font-variant-numeric: tabular-nums; letter-spacing: -0.02em; line-height: 1;
  font-size: min(27vw, 34vh); white-space: nowrap; }
.time.long { font-size: min(19vw, 26vh); }
.time.over { color: var(--over); }
.time.paused { color: var(--dim); }
.sub { margin-top: 2vh; font-size: min(5.2vw, 4.2vh); color: var(--dim); font-variant-numeric: tabular-nums; }
.section { margin-top: 1.2vh; font-size: min(5vw, 4vh); font-variant-numeric: tabular-nums;
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 100%; }
.bar { display: flex; gap: 6px; height: 10px; }
.segment { position: relative; height: 100%; border-radius: 5px; background: var(--faint); overflow: hidden; min-width: 2px; }
.fill { position: absolute; inset: 0 auto 0 0; background: var(--text); border-radius: 5px; }
.over .fill { background: var(--over); }
.labels { display: flex; gap: 6px; margin-top: 7px; font-size: 13px; color: var(--dim); }
.labels span { overflow: hidden; white-space: nowrap; text-overflow: ellipsis; min-width: 0; }
.labels span.current { color: var(--text); }
.controls { display: grid; grid-template-columns: repeat(2, 1fr); gap: 10px; }
button { font: inherit; font-size: 18px; color: var(--text); background: var(--button); border: 0;
  border-radius: 14px; padding: 16px 10px; min-height: 56px; }
button:active { background: var(--button-press); }
button:disabled { opacity: .35; }
button.end { color: var(--over); }
button.end.confirm { background: var(--over); color: #000; font-weight: 600; }
.note { text-align: center; font-size: 13px; color: var(--dim); margin: 4px 0 0; }
#idle { justify-content: center; gap: 18px; max-width: 560px; width: 100%; align-self: center; }
#idle h1 { font-size: 26px; font-weight: 600; margin: 0; text-align: center; }
#idle ul { list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: 10px; }
#idle li { display: flex; align-items: center; justify-content: space-between; gap: 12px;
  background: rgba(255,255,255,.07); border-radius: 14px; padding: 12px 12px 12px 16px; }
#idle .name { font-size: 18px; }
#idle .summary { font-size: 14px; color: var(--dim); margin-top: 2px; }
#idle button { min-height: 44px; padding: 10px 18px; font-size: 17px; }
#message { flex: 1; display: flex; align-items: center; justify-content: center; text-align: center;
  font-size: 20px; color: var(--dim); padding: 0 12px; }
@media (orientation: landscape) {
  #run { flex-direction: row; align-items: stretch; }
  #run .left { flex: 1.7; display: flex; flex-direction: column; min-width: 0; gap: 12px; }
  .time { font-size: min(19vw, 40vh); }
  .time.long { font-size: min(13vw, 30vh); }
  .sub { font-size: min(3vw, 5.5vh); margin-top: 1.5vh; }
  .section { font-size: min(2.9vw, 5.2vh); }
  .controls { flex: 1; grid-template-columns: 1fr; align-content: center; max-width: 280px; }
  button { min-height: 0; padding: 12px 10px; }
}
@media (orientation: portrait) { #run .left { display: contents; } }
</style>
</head>
<body>
<div id="banner" role="status" hidden>Reconnecting…</div>
<main id="run" hidden>
  <div class="left">
    <div class="clock">
      <div id="time" class="time" aria-live="off">0:00</div>
      <div id="sub" class="sub"></div>
      <div id="section" class="section"></div>
    </div>
    <div>
      <div id="bar" class="bar"></div>
      <div id="labels" class="labels"></div>
    </div>
  </div>
  <div class="controls">
    <button id="next" type="button">Next Section</button>
    <button id="plus" type="button">+1 min</button>
    <button id="pause" type="button">Pause</button>
    <button id="end" type="button" class="end">End</button>
  </div>
</main>
<main id="idle" hidden>
  <h1>No agenda running</h1>
  <ul id="agendas"></ul>
</main>
<div id="message" hidden></div>
<p id="wake" class="note" hidden>To keep this screen on, set Auto-Lock to Never.</p>
<!--SAMPLE-->
<script>
"use strict";
const $ = (id) => document.getElementById(id);
const token = new URLSearchParams(location.search).get("t") || "";
let state = null;      // the last PhoneState from the Mac
let offset = 0;        // the Mac's clock minus this phone's clock, in ms
let endArmed = null;   // the timer that disarms End after the first tap
let source = null;

function pad(n) { return String(n).padStart(2, "0"); }
function clock(total) {
  const h = Math.floor(total / 3600), m = Math.floor((total % 3600) / 60), s = total % 60;
  return h > 0 ? h + ":" + pad(m) + ":" + pad(s) : m + ":" + pad(s);
}
function countdown(ms) { return clock(Math.ceil(Math.max(0, ms) / 1000)); }
function overtime(ms) { return "+" + clock(Math.floor(Math.max(0, ms) / 1000)); }
// A time of day as the Mac sees it, so the phone says the same as the Mac's clock window.
function timeOfDay(serverMs) {
  const d = new Date(serverMs);
  return ((d.getHours() % 12) || 12) + ":" + pad(d.getMinutes());
}

function apply(next) {
  state = next;
  if (next.run) offset = next.run.serverNow - Date.now();
  $("banner").hidden = true;
  render();
}

// The Mac's time now, as the snapshot sees it. While paused, the clock holds still.
function serverNow(run) { return run.isPaused ? run.serverNow : Date.now() + offset; }

function render() {
  if (!state) return;
  const run = state.run;
  $("run").hidden = !run;
  $("idle").hidden = !!run;
  if (!run) { renderIdle(); return; }

  const n = serverNow(run);
  const sections = run.sections;
  let current = sections.findIndex((s) => s.end > n && s.end > s.start);
  const isOver = current < 0 && n > run.end;
  const shown = current < 0 ? sections.length - 1 : current;
  // While paused, the end moves later as the pause goes on.
  const end = run.isPaused ? run.end + (Date.now() + offset - run.serverNow) : run.end;

  const time = $("time");
  const text = isOver ? overtime(n - run.end) : countdown(run.end - n);
  time.textContent = text;
  time.classList.toggle("long", text.length > 6);
  time.classList.toggle("over", isOver);
  time.classList.toggle("paused", run.isPaused && !isOver);

  $("sub").textContent = isOver ? "over · ended " + timeOfDay(run.end)
    : run.isPaused ? "paused · ends " + timeOfDay(end) + " if resumed now"
    : "remaining · ends " + timeOfDay(run.end);
  $("section").textContent = current >= 0
    ? sections[current].name + " · " + countdown(sections[current].end - n) + " left"
    : (sections[shown] ? sections[shown].name : "");

  // The bar: widths in proportion to each section's time, filled up to now.
  const widths = sections.map((s) => s.spentSeconds * 1000 + (s.end - s.start));
  const bar = $("bar"), labels = $("labels");
  if (bar.children.length !== sections.length) {
    bar.innerHTML = ""; labels.innerHTML = "";
    sections.forEach(() => {
      const seg = document.createElement("div"); seg.className = "segment";
      const fill = document.createElement("div"); fill.className = "fill";
      seg.appendChild(fill); bar.appendChild(seg);
      labels.appendChild(document.createElement("span"));
    });
  }
  bar.classList.toggle("over", isOver);
  sections.forEach((s, i) => {
    const w = widths[i];
    let filled;
    if (i < shown || isOver) filled = w;
    else if (i === shown) filled = s.spentSeconds * 1000 + Math.min(Math.max(n - s.start, 0), s.end - s.start);
    else filled = s.spentSeconds * 1000;
    const seg = bar.children[i], label = labels.children[i];
    seg.hidden = label.hidden = w <= 0;
    seg.style.flex = label.style.flex = w + " 1 0";
    seg.firstChild.style.width = (w > 0 ? Math.min(100, filled / w * 100) : 0) + "%";
    label.textContent = s.name;
    label.className = i === shown ? "current" : "";
  });

  $("next").disabled = !(current >= 0 && current < sections.length - 1);
  const pause = $("pause");
  pause.hidden = !run.canPause;
  pause.textContent = run.isPaused ? "Resume" : "Pause";
}

function renderIdle() {
  const list = $("agendas");
  list.innerHTML = "";
  for (const agenda of state.agendas) {
    const li = document.createElement("li");
    const text = document.createElement("div");
    const name = document.createElement("div"); name.className = "name"; name.textContent = agenda.name;
    const summary = document.createElement("div"); summary.className = "summary"; summary.textContent = agenda.summary;
    text.append(name, summary);
    const start = document.createElement("button"); start.type = "button"; start.textContent = "Start";
    start.disabled = !agenda.canStart;
    start.addEventListener("click", () => send({ command: "start", agendaID: agenda.id }));
    li.append(text, start);
    list.appendChild(li);
  }
  if (!state.agendas.length) {
    const li = document.createElement("li"); li.textContent = "Make an agenda on the Mac first."; list.appendChild(li);
  }
}

function showMessage(text) {
  $("run").hidden = $("idle").hidden = $("banner").hidden = true;
  $("message").textContent = text;
  $("message").hidden = false;
}

async function send(body) {
  if (window.SAMPLE) return;
  try {
    const response = await fetch("/command?t=" + encodeURIComponent(token), {
      method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body), cache: "no-store"
    });
    if (response.status === 403) { linkReplaced(); return; }
    if (response.headers.get("Content-Type") === "application/json") apply(await response.json());
  } catch (error) {
    $("banner").hidden = false;
  }
}

function linkReplaced() {
  if (source) source.close();
  showMessage("This link no longer works. Scan the new code on the Mac.");
}

function connect() {
  if (source) source.close();
  source = new EventSource("/events?t=" + encodeURIComponent(token));
  source.onmessage = (event) => apply(JSON.parse(event.data));
  source.onerror = () => {
    $("banner").hidden = false;
    // The browser retries on its own while it can. When it gives up, find out why.
    if (source.readyState === EventSource.CLOSED) {
      fetch("/state?t=" + encodeURIComponent(token), { cache: "no-store" })
        .then((r) => { if (r.status === 403) linkReplaced(); else setTimeout(connect, 2000); })
        .catch(() => setTimeout(connect, 2000));
    }
  };
}

$("next").addEventListener("click", () => send({ command: "nextSection" }));
$("plus").addEventListener("click", () => send({ command: "addMinute" }));
$("pause").addEventListener("click", () => send({ command: state && state.run && state.run.isPaused ? "resume" : "pause" }));
$("end").addEventListener("click", () => {
  const end = $("end");
  if (endArmed) {
    clearTimeout(endArmed); endArmed = null;
    end.classList.remove("confirm"); end.textContent = "End";
    send({ command: "end" });
    return;
  }
  end.classList.add("confirm"); end.textContent = "Tap again to end";
  endArmed = setTimeout(() => { endArmed = null; end.classList.remove("confirm"); end.textContent = "End"; }, 4000);
});

// Keeping the screen on. Browsers allow the Wake Lock only on secure pages, and this one is
// plain HTTP on the local network, so it is usually refused. Then say how to do it by hand.
async function keepAwake() {
  try {
    if (!("wakeLock" in navigator)) throw new Error("unsupported");
    await navigator.wakeLock.request("screen");
    $("wake").hidden = true;
  } catch (error) {
    $("wake").hidden = false;
  }
}
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState !== "visible") return;
  keepAwake();
  if (!window.SAMPLE && source && source.readyState === EventSource.CLOSED) connect();
});

if (window.SAMPLE) {
  apply(window.SAMPLE);
  $("wake").hidden = false;
} else if (!token) {
  showMessage("Open the link from the Mac: Settings, Phone.");
} else {
  connect();
  keepAwake();
}
setInterval(render, 250);
</script>
</body>
</html>
"""#
}
