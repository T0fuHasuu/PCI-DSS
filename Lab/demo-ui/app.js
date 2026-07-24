const FLOW_STEP_MS = 620;

const state = {
  report: null,
  presentationInput: null,
  playbackId: 0,
  toastTimer: null,
};

const posView = document.getElementById('pos-view');
const processView = document.getElementById('process-view');
const checkoutFrame = document.getElementById('checkout-frame');
const openProcessButton = document.getElementById('open-process-button');
const backToPosButton = document.getElementById('back-to-pos-button');
const toast = document.getElementById('success-toast');
const toastMessage = document.getElementById('toast-message');
const processStatus = document.getElementById('process-status');
const verificationList = document.getElementById('verification-list');
const verificationResult = document.getElementById('verification-result');
const flowNodes = new Map(
  [...document.querySelectorAll('.flow-node[data-node]')].map((node) => [node.dataset.node, node])
);

function sleep(milliseconds) {
  return new Promise((resolve) => window.setTimeout(resolve, milliseconds));
}

function currency(value) {
  const amount = Number(value);
  return Number.isFinite(amount)
    ? new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(amount)
    : '$0.00';
}

function updateClock() {
  const now = new Date();
  document.getElementById('terminal-time').textContent = now.toLocaleTimeString([], {
    hour: '2-digit',
    minute: '2-digit',
  });
  document.getElementById('terminal-date').textContent = now.toLocaleDateString([], {
    weekday: 'short',
    day: '2-digit',
    month: 'short',
    year: 'numeric',
  });
}

function updateAmountDisplay(value) {
  const formatted = currency(value);
  document.getElementById('item-price').textContent = formatted;
  document.getElementById('subtotal-value').textContent = formatted;
  document.getElementById('total-value').textContent = formatted;
}

function showToast(message) {
  window.clearTimeout(state.toastTimer);
  toastMessage.textContent = message;
  toast.classList.add('visible');
  toast.setAttribute('aria-hidden', 'false');
  state.toastTimer = window.setTimeout(hideToast, 6500);
}

function hideToast() {
  toast.classList.remove('visible');
  toast.setAttribute('aria-hidden', 'true');
}

function setText(id, value) {
  document.getElementById(id).textContent = value ?? '—';
}

function setStageOpen(stage, open) {
  stage.classList.toggle('open', open);
  const heading = stage.querySelector('.data-stage-heading');
  if (heading) heading.setAttribute('aria-expanded', String(open));
}

function resetFlowDisplay() {
  state.playbackId += 1;
  for (const node of flowNodes.values()) {
    node.classList.remove('active', 'complete', 'failed');
    node.querySelector('.node-status').textContent = 'Waiting';
  }

  for (const stage of document.querySelectorAll('.data-stage')) {
    stage.classList.remove('active', 'complete');
    setStageOpen(stage, false);
  }
  const firstStage = document.getElementById('source-stage');
  firstStage.classList.add('active');
  setStageOpen(firstStage, true);

  processStatus.className = 'process-status';
  processStatus.innerHTML = '<span></span>Preparing playback';
  verificationResult.className = 'verification-result';
  verificationResult.textContent = 'Waiting';
  verificationList.replaceChildren(Object.assign(document.createElement('p'), {
    className: 'empty-message',
    textContent: 'Verification details appear as the path completes.',
  }));
}

function reportStep(report, number) {
  return report.steps?.find((step) => Number(step.number) === number);
}

function nodePassed(report, nodeName) {
  const checks = {
    pos: [1, 2],
    vpn: [1],
    perimeter: [1],
    dmz: [1],
    internal: [1],
    app: [1, 2],
    vault: [4],
    db: [3, 5],
  };
  return (checks[nodeName] || []).every((number) => reportStep(report, number)?.status === 'PASS');
}

function fillReportData(report, input) {
  const summary = report.summary || {};
  setText('process-tx-chip', `Transaction #${summary.tx_id ?? '—'}`);
  setText('flow-customer', input?.full_name || 'Submitted customer');
  setText('flow-email', input?.email || 'Submitted email');
  setText('flow-phone', input?.phone_number || 'Submitted phone');
  setText('flow-amount', currency(summary.amount ?? input?.amount));
  setText('flow-card', summary.masked_pan || 'Protected in transit');
  setText('flow-authorization', summary.authorization_status || '—');
  setText('flow-masked-pan', summary.masked_pan || '—');
  setText('flow-key-version', summary.vault_key_version ? `Version ${summary.vault_key_version}` : '—');

  setText('db-tx-id', summary.tx_id ?? '—');
  setText('db-auth', summary.authorization_status || '—');
  setText('db-amount', String(summary.amount ?? input?.amount ?? '—'));
  setText('db-masked-pan', summary.masked_pan || '—');
  setText('db-token', summary.card_token || '—');
  setText('db-ciphertext', summary.encrypted_chd || '—');
  setText('db-key-version', summary.vault_key_version ?? '—');

  setText('raw-pan-check', summary.raw_pan_stored ? 'Yes' : 'No');
  setText('sad-check', summary.sad_stored ? 'Yes' : 'No');
  setText('db-tls-check', summary.storage_protocol || 'Pending');
}

function activateNode(nodeName) {
  const node = flowNodes.get(nodeName);
  if (!node) return;
  node.classList.remove('complete', 'failed');
  node.classList.add('active');
  node.querySelector('.node-status').textContent = 'Processing';
  node.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
}

function finishNode(nodeName, passed) {
  const node = flowNodes.get(nodeName);
  if (!node) return;
  node.classList.remove('active');
  node.classList.add(passed ? 'complete' : 'failed');
  node.querySelector('.node-status').textContent = passed ? 'Passed' : 'Failed';
}

function showDataStage(stageId) {
  const current = document.querySelector('.data-stage.active');
  if (current) {
    current.classList.remove('active');
    current.classList.add('complete');
  }
  const next = document.getElementById(stageId);
  next.classList.add('active');
  setStageOpen(next, true);
}

function appendVerification(step) {
  const empty = verificationList.querySelector('.empty-message');
  if (empty) empty.remove();

  const passed = step.status === 'PASS';
  const card = document.createElement('article');
  card.className = `verification-card ${passed ? 'pass' : 'fail'}`;
  card.dataset.step = String(step.number);

  const badge = document.createElement('span');
  badge.textContent = `${step.number}/5 · ${step.status}`;
  const title = document.createElement('strong');
  title.textContent = step.title;
  const protocol = document.createElement('p');
  protocol.textContent = step.protocol;
  card.append(badge, title, protocol);
  verificationList.append(card);
}

async function runPlayback(report, input) {
  resetFlowDisplay();
  const playbackId = state.playbackId;
  fillReportData(report, input);
  processStatus.innerHTML = '<span></span>Transaction moving through the segmented path';

  const route = ['pos', 'vpn', 'perimeter', 'dmz', 'internal', 'app', 'vault', 'db'];
  for (const nodeName of route) {
    if (playbackId !== state.playbackId) return;
    activateNode(nodeName);

    if (nodeName === 'app') showDataStage('application-stage');
    if (nodeName === 'db') showDataStage('database-stage');

    await sleep(FLOW_STEP_MS);
    if (playbackId !== state.playbackId) return;
    finishNode(nodeName, nodePassed(report, nodeName));

    const relatedSteps = (report.steps || []).filter((step) => (step.nodes || []).includes(nodeName));
    for (const step of relatedSteps) {
      if (!verificationList.querySelector(`[data-step="${step.number}"]`)) appendVerification(step);
    }
  }

  document.getElementById('database-stage').classList.remove('active');
  document.getElementById('database-stage').classList.add('complete');
  const completed = report.status === 'completed';
  processStatus.className = `process-status ${completed ? 'complete' : 'failed'}`;
  processStatus.innerHTML = `<span></span>${completed ? 'Transaction path and storage verified' : 'One or more verification checks failed'}`;
  verificationResult.className = `verification-result ${completed ? 'pass' : 'fail'}`;
  verificationResult.textContent = completed ? 'All checks passed' : 'Review failed checks';
}

function openProcessView() {
  if (!state.report) return;
  hideToast();
  posView.hidden = true;
  posView.classList.remove('active');
  processView.hidden = false;
  processView.classList.add('active');
  window.scrollTo({ top: 0, behavior: 'auto' });
  runPlayback(state.report, state.presentationInput);
}

function resetToNewSale() {
  state.playbackId += 1;
  state.report = null;
  state.presentationInput = null;
  hideToast();
  openProcessButton.disabled = true;
  updateAmountDisplay(25.50);
  resetFlowDisplay();

  checkoutFrame.contentWindow?.postMessage({ type: 'reset-form' }, window.location.origin);
  processView.hidden = true;
  processView.classList.remove('active');
  posView.hidden = false;
  posView.classList.add('active');
  window.scrollTo({ top: 0, behavior: 'auto' });
}

window.addEventListener('message', (message) => {
  if (message.origin !== window.location.origin) return;
  const payload = message.data;
  if (!payload || typeof payload !== 'object') return;

  if (payload.type === 'checkout-height') {
    const requestedHeight = Number(payload.height);
    if (Number.isFinite(requestedHeight)) {
      checkoutFrame.style.height = `${Math.max(340, Math.min(requestedHeight + 4, 620))}px`;
    }
    return;
  }

  if (payload.type === 'amount-change') {
    updateAmountDisplay(payload.amount);
    return;
  }

  if (payload.type === 'simulation-reset') {
    state.report = null;
    state.presentationInput = null;
    openProcessButton.disabled = true;
    hideToast();
    return;
  }

  if (payload.type === 'simulation-report') {
    state.report = payload.report;
    state.presentationInput = payload.presentationInput || null;
    openProcessButton.disabled = false;
    const txId = payload.report?.summary?.tx_id ?? '—';
    const status = String(payload.report?.summary?.authorization_status || 'approved').toLowerCase();
    showToast(`Transaction #${txId} was ${status}. Open the background view to replay its path.`);
    return;
  }

  if (payload.type === 'simulation-error') {
    state.report = null;
    state.presentationInput = null;
    openProcessButton.disabled = true;
  }
});

for (const heading of document.querySelectorAll('.data-stage-heading')) {
  heading.addEventListener('click', () => {
    const stage = heading.closest('.data-stage');
    if (stage) setStageOpen(stage, !stage.classList.contains('open'));
  });
}

openProcessButton.addEventListener('click', openProcessView);
backToPosButton.addEventListener('click', resetToNewSale);
document.getElementById('close-toast').addEventListener('click', hideToast);

updateClock();
window.setInterval(updateClock, 30000);
updateAmountDisplay(25.50);
resetFlowDisplay();
