// Service worker: context menus, toolbar action, badge feedback.

import { NotSignedInError, stashImage, stashNote, stashUrl } from './stash-api.js';
import { isStashableUrl } from './lib.js';

const MENU_SELECTION = 'stash-selection';
const MENU_IMAGE = 'stash-image';

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({ id: MENU_SELECTION, title: 'Stash it', contexts: ['selection'] });
    chrome.contextMenus.create({ id: MENU_IMAGE, title: 'Stash it', contexts: ['image'] });
  });
});

// The "very small, innocuous" confirmation: a short-lived badge on the
// toolbar icon, scoped to the tab the save came from. No page injection.
function badge(tabId, text, color, clearAfterMs) {
  const scope = Number.isInteger(tabId) ? { tabId } : {};
  if (color) chrome.action.setBadgeBackgroundColor({ ...scope, color });
  chrome.action.setBadgeTextColor?.({ ...scope, color: '#ffffff' });
  chrome.action.setBadgeText({ ...scope, text });
  if (clearAfterMs) {
    setTimeout(() => chrome.action.setBadgeText({ ...scope, text: '' }), clearAfterMs);
  }
}

const showBusy = (tabId) => badge(tabId, '…', '#8a8f98');
const showSaved = (tabId) => badge(tabId, '✓', '#1a7f37', 2200);
const showError = (tabId) => badge(tabId, '!', '#c0392b', 4000);
const clearBadge = (tabId) => badge(tabId, '');

async function run(tabId, work) {
  showBusy(tabId);
  try {
    await work();
    showSaved(tabId);
  } catch (error) {
    if (error instanceof NotSignedInError) {
      clearBadge(tabId);
      chrome.tabs.create({ url: chrome.runtime.getURL('signin.html') });
    } else {
      console.error('[stash-it]', error);
      showError(tabId);
    }
  }
}

// Toolbar button: stash the current page's URL.
chrome.action.onClicked.addListener((tab) => {
  if (!isStashableUrl(tab?.url)) {
    showError(tab?.id);
    return;
  }
  run(tab.id, () => stashUrl(tab.url));
});

chrome.contextMenus.onClicked.addListener((info, tab) => {
  const tabId = tab?.id;
  if (info.menuItemId === MENU_IMAGE && info.srcUrl) {
    run(tabId, () => stashImage(info.srcUrl));
  } else if (info.menuItemId === MENU_SELECTION) {
    run(tabId, async () => {
      const text = (await exactSelection(tabId, info.frameId)) ?? info.selectionText?.trim();
      if (!text) throw new Error('Nothing selected');
      await stashNote(text);
    });
  }
});

// info.selectionText collapses newlines, so read the live selection from the
// page when we can; fall back to selectionText where injection is blocked
// (PDF viewer, Chrome Web Store, etc.).
async function exactSelection(tabId, frameId) {
  if (!Number.isInteger(tabId)) return null;
  try {
    const target = { tabId };
    if (Number.isInteger(frameId)) target.frameIds = [frameId];
    const results = await chrome.scripting.executeScript({
      target,
      func: () => window.getSelection()?.toString() ?? '',
    });
    return results?.[0]?.result?.trim() || null;
  } catch {
    return null;
  }
}
