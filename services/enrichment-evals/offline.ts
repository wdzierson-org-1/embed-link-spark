import { vi } from 'vitest';

// A fixture must never quietly turn into a live request for saved user content.
vi.stubGlobal('fetch', () => { throw new Error('Network requests are forbidden in enrichment evaluation'); });
