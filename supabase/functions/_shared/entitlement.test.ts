import { describe, it, expect, vi } from 'vitest';
import { checkEntitlement, isBlockingStatus, isCacheFresh, ENTITLEMENT_DENIED } from './entitlement';

const NOW = Date.parse('2026-09-07T12:00:00Z');
const iso = (msAgo: number) => new Date(NOW - msAgo).toISOString();

const deps = (over: Partial<Parameters<typeof checkEntitlement>[0]> = {}) => ({
  readCache: vi.fn(async () => null),
  writeCache: vi.fn(async () => {}),
  fetchLiveStatus: vi.fn(async () => 'none'),
  now: () => NOW,
  maxAgeMs: 5 * 60_000,
  ...over,
});

describe('isBlockingStatus — mirrors the web client gate', () => {
  it('lets trialing and active through', () => {
    expect(isBlockingStatus('trialing')).toBe(false);
    expect(isBlockingStatus('active')).toBe(false);
  });
  it('treats no-subscription-yet and unknown as permissive (signup → trial race)', () => {
    expect(isBlockingStatus('none')).toBe(false);
    expect(isBlockingStatus(null)).toBe(false);
    expect(isBlockingStatus(undefined)).toBe(false);
  });
  it('blocks every real lapsed state', () => {
    for (const s of ['paused', 'canceled', 'unpaid', 'past_due', 'incomplete', 'incomplete_expired']) {
      expect(isBlockingStatus(s)).toBe(true);
    }
  });
});

describe('isCacheFresh', () => {
  it('is fresh inside the window and stale outside or when unparsable', () => {
    expect(isCacheFresh({ status: 'active', checked_at: iso(60_000) }, NOW, 5 * 60_000)).toBe(true);
    expect(isCacheFresh({ status: 'active', checked_at: iso(6 * 60_000) }, NOW, 5 * 60_000)).toBe(false);
    expect(isCacheFresh({ status: 'active', checked_at: 'garbage' }, NOW, 5 * 60_000)).toBe(false);
    expect(isCacheFresh(null, NOW, 5 * 60_000)).toBe(false);
  });
});

describe('checkEntitlement', () => {
  it('answers from a fresh cache without touching Stripe', async () => {
    const d = deps({ readCache: vi.fn(async () => ({ status: 'paused', checked_at: iso(10_000) })) });
    const r = await checkEntitlement(d);
    expect(r).toEqual({ allowed: false, status: 'paused', source: 'cache' });
    expect(d.fetchLiveStatus).not.toHaveBeenCalled();
  });

  it('asks Stripe when the cache is stale and refreshes it', async () => {
    const d = deps({
      readCache: vi.fn(async () => ({ status: 'trialing', checked_at: iso(60 * 60_000) })),
      fetchLiveStatus: vi.fn(async () => 'canceled'),
    });
    const r = await checkEntitlement(d);
    expect(r).toEqual({ allowed: false, status: 'canceled', source: 'live' });
    expect(d.writeCache).toHaveBeenCalledWith('canceled');
  });

  it('allows a brand-new account with no Stripe customer', async () => {
    const r = await checkEntitlement(deps());
    expect(r).toEqual({ allowed: true, status: 'none', source: 'live' });
  });

  it('fails open to the last known answer when Stripe is unreachable', async () => {
    const stale = { status: 'active', checked_at: iso(60 * 60_000) };
    const d = deps({
      readCache: vi.fn(async () => stale),
      fetchLiveStatus: vi.fn(async () => { throw new Error('stripe down'); }),
    });
    expect(await checkEntitlement(d)).toEqual({ allowed: true, status: 'active', source: 'fallback' });

    const lapsed = deps({
      readCache: vi.fn(async () => ({ status: 'canceled', checked_at: iso(60 * 60_000) })),
      fetchLiveStatus: vi.fn(async () => { throw new Error('stripe down'); }),
    });
    expect(await checkEntitlement(lapsed)).toEqual({ allowed: false, status: 'canceled', source: 'fallback' });
  });

  it('allows when nothing is known and Stripe is unreachable', async () => {
    const d = deps({ fetchLiveStatus: vi.fn(async () => { throw new Error('stripe down'); }) });
    expect(await checkEntitlement(d)).toEqual({ allowed: true, status: null, source: 'fallback' });
  });

  it('never lets a cache read or write failure block the request', async () => {
    const d = deps({
      readCache: vi.fn(async () => { throw new Error('db hiccup'); }),
      fetchLiveStatus: vi.fn(async () => 'active'),
      writeCache: vi.fn(async () => { throw new Error('db hiccup'); }),
    });
    expect(await checkEntitlement(d)).toEqual({ allowed: true, status: 'active', source: 'live' });
  });
});

describe('ENTITLEMENT_DENIED', () => {
  it('is a stable machine-readable error with a human next step', () => {
    expect(ENTITLEMENT_DENIED.error).toBe('subscription_required');
    expect(ENTITLEMENT_DENIED.message).toMatch(/gostash\.it\/settings/);
  });
});
