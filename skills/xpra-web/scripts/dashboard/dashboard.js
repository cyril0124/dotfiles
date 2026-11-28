const status = document.querySelector('#status');
const sessions = document.querySelector('#sessions');
const refreshButton = document.querySelector('#refresh');
const closeButton = document.querySelector('#close-all');
const stopButton = document.querySelector('#close-and-stop');
const closeStatus = document.querySelector('#close-status');
let hasWindows = false;
let previousInventory;
let refreshTimer;
let refreshing = false;
let changingWindow = false;
const compactLayout = matchMedia('(max-width: 38rem)');

function windowTitle(session, window) {
  const title = document.createElement(window.closed ? 'span' : 'a');
  title.textContent = window.title || `Window ${window.id}`;
  if (window.closed) {
    title.className = 'closed-title';
    title.append(' (Closed)');
  } else {
    title.href = `view/${session.uuid}/${window.id}/`;
    title.target = '_blank';
    title.rel = 'noopener noreferrer';
  }
  return title;
}

function windowActions(session, window) {
  const actions = document.createElement('div');
  actions.className = 'actions';
  for (const [action, label] of [['close', 'Close'], ['reopen', 'Reopen']]) {
    const button = document.createElement('button');
    button.type = 'button';
    button.dataset.action = action;
    button.textContent = action === 'reopen' && !window.closed ? 'Restart' : label;
    if (action === 'close' || !window.closed) button.classList.add('destructive');
    button.disabled = action === 'close' ? !!window.closed : !window.can_reopen;
    if (action === 'reopen' && !window.can_reopen) button.title = 'Original launch command unavailable';
    button.addEventListener('click', () => changeWindow(session.uuid, window.id, action));
    actions.append(button);
  }
  return actions;
}

const startTimeFormat = new Intl.DateTimeFormat(undefined, {dateStyle: 'medium', timeStyle: 'medium'});

const durationUnits = [[86400, 'd'], [3600, 'h'], [60, 'm'], [1, 's']];

function formatDuration(seconds) {
  let remaining = seconds;
  const parts = [];
  for (const [size, label] of durationUnits) {
    const count = Math.floor(remaining / size);
    if (count) parts.push(count + label);
    remaining %= size;
  }
  return parts.join(' ') || '0s';
}

function updateElapsed() {
  const now = Date.now() / 1000;
  for (const elapsed of sessions.querySelectorAll('[data-started-at]')) {
    const closedAt = elapsed.dataset.closedAt;
    const end = closedAt ? Number(closedAt) : now;
    const seconds = Math.max(0, Math.floor(end - Number(elapsed.dataset.startedAt)));
    const text = (closedAt ? 'Ran ' : 'Running for ') + formatDuration(seconds);
    if (elapsed.textContent !== text) elapsed.textContent = text;
  }
}

function windowTiming(window) {
  const timing = document.createElement('div');
  timing.className = 'window-timing';
  if (!Number.isFinite(window.started_at)) {
    timing.textContent = 'Start time unavailable';
    return timing;
  }

  const started = new Date(window.started_at * 1000);
  const timestamp = document.createElement('time');
  timestamp.dateTime = started.toISOString();
  timestamp.textContent = startTimeFormat.format(started);
  const elapsed = document.createElement('span');
  elapsed.dataset.startedAt = window.started_at;
  if (Number.isFinite(window.closed_at)) elapsed.dataset.closedAt = window.closed_at;
  const label = document.createElement('span');
  label.append('Started ', timestamp);
  timing.append(label, elapsed);
  return timing;
}

function render(inventory) {
  const serialized = JSON.stringify(inventory);
  if (serialized === previousInventory) return;
  previousInventory = serialized;
  const expanded = new Map([...sessions.querySelectorAll('details')].map(
    details => [details.dataset.windowKey, details.open],
  ));
  const sections = [];
  for (const session of inventory) {
    const section = document.createElement('section');
    const heading = document.createElement('h2');
    const display = document.createElement('code');
    display.textContent = session.display;
    heading.append('Display ', display);
    const list = document.createElement('ul');
    for (const window of session.windows) {
      const item = document.createElement('li');
      const heading = document.createElement('div');
      heading.className = 'window-heading';
      heading.append(windowTitle(session, window), windowActions(session, window));
      const disclosure = document.createElement('details');
      disclosure.dataset.windowKey = `${session.uuid}/${window.id}`;
      disclosure.open = expanded.get(disclosure.dataset.windowKey) ?? !compactLayout.matches;
      const summary = document.createElement('summary');
      summary.textContent = 'Directory and command';
      const details = document.createElement('dl');
      for (const [label, value] of [['Working directory', window.cwd], ['Command', window.command]]) {
        const term = document.createElement('dt');
        const description = document.createElement('dd');
        term.textContent = label;
        description.textContent = value || 'Unavailable';
        details.append(term, description);
      }
      disclosure.append(summary, details);
      item.append(heading, windowTiming(window), disclosure);
      list.append(item);
    }
    section.append(heading, list);
    sections.push(section);
  }
  sessions.replaceChildren(...sections);
  updateElapsed();
}

async function refresh(manual = false) {
  clearTimeout(refreshTimer);
  refreshing = true;
  refreshButton.disabled = true;
  closeButton.disabled = true;
  stopButton.disabled = true;
  if (manual) status.textContent = 'Refreshing windows…';
  try {
    const url = manual ? 'windows.json?refresh=1' : 'windows.json';
    const response = await fetch(url, {cache: 'no-store'});
    if (!response.ok) throw new Error(response.status);
    const inventory = await response.json();
    render(inventory);
    hasWindows = inventory.some(session => session.windows.some(window => !window.closed));
    status.textContent = hasWindows ? '' : 'No running windows.';
  } catch {
    hasWindows = false;
    status.textContent = 'Could not refresh windows. Retrying…';
  } finally {
    refreshing = false;
    refreshButton.disabled = changingWindow;
    closeButton.disabled = changingWindow || !hasWindows;
    stopButton.disabled = changingWindow;
    if (!changingWindow) refreshTimer = setTimeout(refresh, 2000);
  }
}

async function changeWindow(uuid, id, action) {
  if (changingWindow) return;
  changingWindow = true;
  clearTimeout(refreshTimer);
  refreshButton.disabled = true;
  closeButton.disabled = true;
  stopButton.disabled = true;
  closeStatus.hidden = false;
  closeStatus.textContent = action === 'close' ? 'Force-closing window…' : 'Reopening window…';
  try {
    const response = await fetch(`window/${action}/${uuid}/${id}`, {method: 'POST'});
    if (!response.ok) throw new Error(await response.text() || 'Window action failed.');
    closeStatus.textContent = action === 'close' ? 'Window force-closed.' : 'Application launched.';
  } catch (error) {
    closeStatus.textContent = error.message;
  } finally {
    changingWindow = false;
    if (!refreshing) await refresh(true);
  }
}

async function closeAll(stopDashboard = false) {
  if (changingWindow) return;
  changingWindow = true;
  clearTimeout(refreshTimer);
  refreshButton.disabled = true;
  closeButton.disabled = true;
  stopButton.disabled = true;
  closeStatus.hidden = false;
  closeStatus.textContent = 'Force-closing windows…';
  let stopped = false;
  try {
    const route = stopDashboard ? 'close-windows-and-stop' : 'close-windows';
    const response = await fetch(route, {method: 'POST'});
    if (!response.ok) throw new Error(response.status);
    const {requested, failed} = await response.json();
    const message = requested === 1 ? '1 window force-closed.' : `${requested} windows force-closed.`;
    closeStatus.textContent = failed ? `${message} ${failed} close errors.` : message;
    if (stopDashboard && failed) closeStatus.textContent += ' Dashboard is still running.';
    if (stopDashboard && !failed) {
      stopped = true;
      sessions.replaceChildren();
      status.textContent = 'Dashboard stopped. You can close this tab.';
      window.close();
    }
  } catch {
    closeStatus.textContent = 'Could not complete the close request.';
  } finally {
    if (!stopped) {
      changingWindow = false;
      await refresh(true);
    }
  }
}

compactLayout.addEventListener('change', () => {
  for (const details of sessions.querySelectorAll('details')) {
    details.open = !compactLayout.matches;
  }
});
closeButton.addEventListener('click', () => closeAll());
stopButton.addEventListener('click', () => closeAll(true));
refreshButton.addEventListener('click', () => refresh(true));
setInterval(updateElapsed, 1000);
refresh();
