const CACHE_KEY = 'pci-lab:transaction-report:v2';
const nodes = new Map([...document.querySelectorAll('[data-node]')].map((node) => [node.dataset.node, node]));
const timeline = document.getElementById('timeline');
const overallStatus = document.getElementById('overall-status');
const evidenceStatus = document.getElementById('evidence-status');
const cacheStatus = document.getElementById('cache-status');
let playbackGeneration = 0;

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function resetDashboard({ clearCache = false } = {}) {
  playbackGeneration += 1;
  for (const node of nodes.values()) {
    node.classList.remove('active', 'complete', 'failed');
    node.querySelector('.node-state').textContent = 'Waiting';
  }
  timeline.replaceChildren(Object.assign(document.createElement('li'), {
    className: 'timeline-empty',
    textContent: 'Submit a purchase to execute the five-phase transaction test.'
  }));
  overallStatus.textContent = 'Ready';
  overallStatus.className = 'status-pill';
  evidenceStatus.textContent = 'No transaction';
  evidenceStatus.className = 'secure-label';
  cacheStatus.textContent = 'Session cache empty';
  document.getElementById('tx-id').textContent = '—';
  document.getElementById('auth-status').textContent = '—';
  document.getElementById('masked-pan').textContent = '—';
  document.getElementById('key-version').textContent = '—';
  document.getElementById('card-token').textContent = 'Waiting for a completed transaction.';
  document.getElementById('ciphertext').textContent = 'Waiting for a completed transaction.';
  document.getElementById('raw-pan-stored').textContent = 'No';
  document.getElementById('sad-stored').textContent = 'No';
  document.getElementById('storage-protocol').textContent = 'TLS pending';
  document.getElementById('decrypted-chd').textContent = 'Controlled verification has not run.';
  if (clearCache) sessionStorage.removeItem(CACHE_KEY);
}

function setNode(nodeName, state) {
  const node = nodes.get(nodeName);
  if (!node) return;
  node.classList.remove('active', 'complete', 'failed');
  node.classList.add(state);
  node.querySelector('.node-state').textContent = state === 'complete' ? 'Passed' : state === 'failed' ? 'Failed' : 'Testing';
}

function appendStep(step) {
  const empty = timeline.querySelector('.timeline-empty');
  if (empty) empty.remove();

  const item = document.createElement('li');
  item.className = `timeline-item ${step.status === 'PASS' ? 'pass' : 'error'}`;

  const header = document.createElement('div');
  header.className = 'timeline-header';
  const title = document.createElement('strong');
  title.textContent = `[${step.number}/5] ${step.title}`;
  const protocol = document.createElement('span');
  protocol.textContent = step.protocol;
  header.append(title, protocol);

  const result = document.createElement('span');
  result.className = `result-badge ${step.status === 'PASS' ? 'pass' : 'fail'}`;
  result.textContent = step.status;

  const output = document.createElement('pre');
  output.className = 'step-output';
  output.textContent = step.lines.join('\n');

  item.append(header, result, output);
  timeline.append(item);
  item.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
}

function showEvidence(report) {
  const summary = report.summary;
  document.getElementById('tx-id').textContent = `#${summary.tx_id}`;
  document.getElementById('auth-status').textContent = summary.authorization_status;
  document.getElementById('masked-pan').textContent = summary.masked_pan;
  document.getElementById('key-version').textContent = `v${summary.vault_key_version}`;
  document.getElementById('card-token').textContent = summary.card_token;
  document.getElementById('ciphertext').textContent = summary.encrypted_chd;
  document.getElementById('raw-pan-stored').textContent = summary.raw_pan_stored ? 'Yes' : 'No';
  document.getElementById('sad-stored').textContent = summary.sad_stored ? 'Yes' : 'No';
  document.getElementById('storage-protocol').textContent = summary.storage_protocol;
  document.getElementById('decrypted-chd').textContent = JSON.stringify(summary.decrypted_chd);
  evidenceStatus.textContent = 'Verified encrypted';
  evidenceStatus.className = 'secure-label verified';
}

async function playReport(report, { instant = false } = {}) {
  resetDashboard({ clearCache: false });
  const generation = ++playbackGeneration;
  overallStatus.textContent = instant ? 'Restored from session' : 'Playing verified test';
  overallStatus.className = 'status-pill running';
  cacheStatus.textContent = instant ? 'Restored from session cache' : 'Saving result to session cache';

  for (const step of report.steps) {
    if (generation !== playbackGeneration) return;
    for (const nodeName of step.nodes || []) setNode(nodeName, 'active');
    appendStep(step);
    if (!instant) await sleep(800);
    for (const nodeName of step.nodes || []) setNode(nodeName, step.status === 'PASS' ? 'complete' : 'failed');
    if (!instant) await sleep(250);
  }

  showEvidence(report);
  overallStatus.textContent = report.status === 'completed' ? 'Transaction verified' : 'Verification failed';
  overallStatus.className = `status-pill ${report.status === 'completed' ? 'success' : 'error'}`;
  cacheStatus.textContent = `Cached for this browser tab · transaction #${report.summary.tx_id}`;
}

window.addEventListener('message', (message) => {
  if (message.origin !== window.location.origin) return;
  const payload = message.data;
  if (!payload || typeof payload !== 'object') return;

  if (payload.type === 'simulation-reset') {
    resetDashboard({ clearCache: false });
    overallStatus.textContent = 'Executing test';
    overallStatus.className = 'status-pill running';
    cacheStatus.textContent = 'Previous result retained until the new test succeeds';
    return;
  }

  if (payload.type === 'simulation-report') {
    sessionStorage.setItem(CACHE_KEY, JSON.stringify(payload.report));
    playReport(payload.report);
    return;
  }

  if (payload.type === 'simulation-error') {
    overallStatus.textContent = 'Transaction test failed';
    overallStatus.className = 'status-pill error';
    const cached = sessionStorage.getItem(CACHE_KEY);
    cacheStatus.textContent = cached ? 'Previous successful result remains cached' : 'No cached result';
  }
});

document.getElementById('reset-button').addEventListener('click', () => {
  resetDashboard({ clearCache: true });
  document.getElementById('checkout-frame').contentWindow.postMessage({ type: 'reset-form' }, window.location.origin);
});

resetDashboard();
const cachedReport = sessionStorage.getItem(CACHE_KEY);
if (cachedReport) {
  try {
    playReport(JSON.parse(cachedReport), { instant: true });
  } catch {
    sessionStorage.removeItem(CACHE_KEY);
  }
}
