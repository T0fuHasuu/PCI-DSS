const MINIMUM_TRANSACTION_MS = 3000;

const form = document.getElementById('purchase-form');
const purchaseButton = document.getElementById('purchase-button');
const purchaseButtonLabel = document.getElementById('purchase-button-label');
const feedback = document.getElementById('transaction-feedback');
const feedbackTitle = document.getElementById('feedback-title');
const feedbackMessage = document.getElementById('feedback-message');
const amountInput = document.getElementById('amount-input');
const panInput = document.getElementById('pan-input');
let feedbackTimers = [];

function parentMessage(data) {
  window.parent.postMessage(data, window.location.origin);
}

function reportHeight() {
  parentMessage({ type: 'checkout-height', height: document.documentElement.scrollHeight });
}

function sleep(milliseconds) {
  return new Promise((resolve) => window.setTimeout(resolve, milliseconds));
}

function currency(value) {
  const amount = Number(value);
  return Number.isFinite(amount)
    ? new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(amount)
    : '$0.00';
}

function setFeedback(type, title, message) {
  feedback.className = `transaction-feedback${type ? ` ${type}` : ''}`;
  feedbackTitle.textContent = title;
  feedbackMessage.textContent = message;
}

function clearFeedbackTimers() {
  for (const timer of feedbackTimers) window.clearTimeout(timer);
  feedbackTimers = [];
}

function scheduleProcessingMessages() {
  clearFeedbackTimers();
  const messages = [
    [650, 'Securing connection', 'Opening the approved POS path through the segmented lab.'],
    [1400, 'Processing payment', 'The CDE application is validating and protecting cardholder data.'],
    [2250, 'Verifying storage', 'Checking Vault encryption and the protected PostgreSQL record.'],
  ];
  for (const [delay, title, message] of messages) {
    feedbackTimers.push(window.setTimeout(() => {
      if (purchaseButton.disabled) setFeedback('processing', title, message);
    }, delay));
  }
}

function setBusy(busy) {
  for (const control of form.elements) control.disabled = busy;
  purchaseButton.classList.toggle('processing', busy);
  purchaseButtonLabel.textContent = busy ? 'Processing secure payment…' : `Pay ${currency(amountInput.value)}`;
}

function updateAmount() {
  purchaseButtonLabel.textContent = `Pay ${currency(amountInput.value)}`;
  parentMessage({ type: 'amount-change', amount: Number(amountInput.value) });
}

function formatPanInput() {
  const digits = panInput.value.replace(/\D/g, '').slice(0, 19);
  panInput.value = digits.replace(/(.{4})/g, '$1 ').trim();
  panInput.setCustomValidity(digits.length >= 13 && digits.length <= 19 ? '' : 'Enter a 13 to 19 digit test card number.');
}

function extractRequest() {
  const values = new FormData(form);
  const pan = String(values.get('pan') || '').replace(/\D/g, '');
  const cvv = String(values.get('cvv') || '').replace(/\D/g, '');
  return {
    payload: {
      customer: {
        full_name: String(values.get('full_name') || '').trim(),
        email: String(values.get('email') || '').trim(),
        phone_number: String(values.get('phone_number') || '').trim(),
      },
      card: {
        pan,
        exp_month: Number(values.get('exp_month')),
        exp_year: Number(values.get('exp_year')),
        cvv,
      },
      amount: Number(values.get('amount')),
    },
    presentationInput: {
      full_name: String(values.get('full_name') || '').trim(),
      email: String(values.get('email') || '').trim(),
      phone_number: String(values.get('phone_number') || '').trim(),
      amount: Number(values.get('amount')),
    },
  };
}

async function submitTransaction(event) {
  event.preventDefault();
  formatPanInput();
  if (!form.reportValidity()) return;

  const request = extractRequest();
  parentMessage({ type: 'simulation-reset' });
  setBusy(true);
  setFeedback('processing', 'Starting transaction', 'Submitting the payment through the real lab transaction path.');
  scheduleProcessingMessages();

  try {
    const requestPromise = fetch('/api/simulations', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      cache: 'no-store',
      body: JSON.stringify(request.payload),
    }).then(async (response) => {
      let body;
      try {
        body = await response.json();
      } catch {
        throw new Error(`The transaction service returned HTTP ${response.status}.`);
      }
      if (!response.ok) throw new Error(body.detail || `Transaction failed with HTTP ${response.status}.`);
      return body;
    });

    const [report] = await Promise.all([requestPromise, sleep(MINIMUM_TRANSACTION_MS)]);
    const txId = report.summary?.tx_id ?? '—';
    setFeedback('success', 'Payment approved', `Transaction #${txId} completed and was verified successfully.`);
    parentMessage({ type: 'simulation-report', report, presentationInput: request.presentationInput });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unable to complete the transaction.';
    setFeedback('error', 'Transaction failed', message);
    parentMessage({ type: 'simulation-error', message });
  } finally {
    clearFeedbackTimers();
    setBusy(false);
    request.payload.card.pan = '';
    request.payload.card.cvv = '';
  }
}

function resetForm() {
  clearFeedbackTimers();
  form.reset();
  formatPanInput();
  updateAmount();
  setBusy(false);
  setFeedback('', 'Ready for payment', 'Confirm the values, then submit the test transaction.');
}

form.addEventListener('submit', submitTransaction);
amountInput.addEventListener('input', updateAmount);
panInput.addEventListener('input', formatPanInput);
window.addEventListener('message', (message) => {
  if (message.origin !== window.location.origin) return;
  if (message.data?.type === 'reset-form') resetForm();
});

formatPanInput();
updateAmount();
parentMessage({ type: 'checkout-ready' });
reportHeight();
if ('ResizeObserver' in window) {
  new ResizeObserver(reportHeight).observe(document.body);
}
window.addEventListener('load', reportHeight);
