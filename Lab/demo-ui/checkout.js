const form = document.getElementById('purchase-form');
const button = document.getElementById('purchase-button');
const statusText = document.getElementById('form-status');

function parentMessage(data) {
  window.parent.postMessage(data, window.location.origin);
}

function setBusy(busy, message) {
  button.disabled = busy;
  button.textContent = busy ? 'Running transaction test…' : 'Purchase securely';
  statusText.textContent = message;
}

form.addEventListener('submit', async (event) => {
  event.preventDefault();
  if (!form.reportValidity()) return;

  const values = new FormData(form);
  const payload = {
    customer: {
      full_name: values.get('full_name'),
      email: values.get('email'),
      phone_number: values.get('phone_number')
    },
    card: {
      pan: values.get('pan'),
      exp_month: Number(values.get('exp_month')),
      exp_year: Number(values.get('exp_year')),
      cvv: values.get('cvv')
    },
    amount: Number(values.get('amount'))
  };

  parentMessage({ type: 'simulation-reset' });
  setBusy(true, 'Executing the POS transaction and verification test…');

  try {
    const response = await fetch('/api/simulations', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      cache: 'no-store',
      body: JSON.stringify(payload)
    });
    const body = await response.json();
    if (!response.ok) throw new Error(body.detail || `HTTP ${response.status}`);

    parentMessage({ type: 'simulation-report', report: body });
    setBusy(false, `Transaction #${body.summary.tx_id} verified successfully.`);
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unable to execute transaction test.';
    setBusy(false, message);
    parentMessage({ type: 'simulation-error', message });
  } finally {
    payload.card.pan = '';
    payload.card.cvv = '';
  }
});

window.addEventListener('message', (message) => {
  if (message.origin !== window.location.origin) return;
  if (message.data?.type === 'reset-form') {
    setBusy(false, 'Use test data only. Raw PAN and CVV are never cached by the dashboard.');
  }
});
