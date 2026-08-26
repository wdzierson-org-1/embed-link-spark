import { clearSession, getSessionInfo, signIn } from './stash-api.js';

const el = (id) => document.getElementById(id);

async function render() {
  const info = await getSessionInfo();
  el('signed-out').hidden = Boolean(info);
  el('signed-in').hidden = !info;
  if (info) el('who').textContent = info.email ?? 'your account';
}

el('signin-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const error = el('error');
  const submit = el('submit');
  error.hidden = true;
  submit.disabled = true;
  submit.textContent = 'Signing in…';
  try {
    await signIn(el('email').value.trim(), el('password').value);
    await render();
  } catch (e) {
    error.textContent = e.message;
    error.hidden = false;
  } finally {
    submit.disabled = false;
    submit.textContent = 'Sign in';
  }
});

el('signout').addEventListener('click', async () => {
  await clearSession();
  await render();
});

render();
