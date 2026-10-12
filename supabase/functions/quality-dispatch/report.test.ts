import { describe, expect, it } from 'vitest';
import { reportText } from './report';
it('reports recorded asset structure checks without claiming visual accuracy', () => {
  const text = reportText({ report_day:'2026-10-10',job_count:1,completed:1,failed:0,pending:0,results:[{retrieval:{outcome:'retrieved',item_id:'id',url:'https://example.org',captured_at:'2026-10-10',image_checks:[{outcome:'usable_asset',reason:'raster_structure_valid',duration_ms:120,width:640,height:480,byte_length:20000}]}}] });
  expect(text).toContain('usable_asset (raster_structure_valid; 120 ms); 640 × 480; 20000 bytes');
  expect(text).toContain('visual match and full decoding are unverified');
  expect(text).toContain('09:00 America/New_York');
});

const base = { report_day: '2026-10-12', job_count: 0, completed: 0, failed: 0, pending: 0, results: [] };
const counts = { jobs: 0, completed: 0, failed: 0, pending: 0, checks: 0, exact_match: 0, match: 0, mismatch: 0, missing_image: 0, unavailable: 0, unsupported: 0, inconclusive: 0 };
const visual = { window_start: '2026-10-12T04:00:00Z', window_end: '2026-10-13T04:00:00Z', counts, canaries: [], findings: [], private_findings: 0, limits: [] };

describe('visual monitoring report', () => {
  it('reports an empty monitoring window as unknown, not a success', () => {
    const text = reportText({ ...base, visual });
    expect(text).toContain('VISUAL ACCURACY MONITORING');
    expect(text).toContain('0 surface checks');
    expect(text).toContain('No visual checks completed in this window; visual accuracy is unknown.');
    expect(text).not.toMatch(/100(?:\.0)?%|all images (?:passed|correct)/i);
    expect(text).toContain('0 canary runs');
  });

  it('separates exact bytes, model judgments, suspected mismatches and unknown delivery outcomes', () => {
    const text = reportText({ ...base, visual: { ...visual, counts: {
      ...counts, jobs: 5, completed: 3, failed: 1, pending: 1, checks: 8,
      exact_match: 1, match: 2, mismatch: 1, missing_image: 1, unavailable: 1, unsupported: 1, inconclusive: 1,
    } } });
    expect(text).toContain('Exact reference matches: 1');
    expect(text).toContain('Model-assessed matches: 2');
    expect(text).toContain('Suspected mismatches: 1');
    expect(text).toContain('Missing images: 1; unavailable: 1; unsupported: 1; inconclusive: 1.');
    expect(text).toContain('Delivery failures and unassessed surfaces are not successes.');
    expect(text).toContain('Model judgments are sampled evidence, not a population accuracy rate.');
  });

  it('reports real-save findings separately from live canary runs with baseline provenance', () => {
    const text = reportText({ ...base, visual: { ...visual,
      counts: { ...counts, jobs: 4, completed: 3, failed: 1, checks: 6, mismatch: 2, exact_match: 4 },
      canaries: [{ fixture_id: 'decisions', title: 'Decisions article', url: 'https://community.openai.com/t/1403877', runs: 3, completed: 2, failed: 1, last_outcome: 'mismatch', last_checked_at: '2026-10-12T18:00:00Z' }],
      findings: [
        { kind: 'sample', item_id: 'saved-item', surface: 'card', outcome: 'mismatch', reason: 'unrelated_image', summary: 'A reply reaction replaced the article cover.', checked_at: '2026-10-12T17:00:00Z', display_url: 'https://project.supabase.co/cover.jpg' },
        { kind: 'canary', fixture_id: 'decisions', surface: 'detail', outcome: 'mismatch', reason: 'reference_mismatch', checked_at: '2026-10-12T18:00:00Z', reference_id: 'decisions-cover', reference_version: 2 },
      ], limits: ['Embedded player pixels are not checked.'],
    } });
    expect(text).toContain('LIVE TEST SAVES — 3 canary runs across 1 fixtures; 2 completed; 1 failed.');
    expect(text).toContain('REAL SAVE SAMPLES');
    expect(text).toContain('Item: saved-item; surface: card');
    expect(text).toContain('Fixture: decisions; surface: detail');
    expect(text).toContain('Reference: decisions-cover; version: 2');
    expect(text).toContain('Displayed image: https://project.supabase.co/cover.jpg');
    expect(text).toContain('Embedded player pixels are not checked.');
    expect(text).toContain('Canary runs exercise test saves; they are not real-user saves or a population failure rate.');
  });

  it('retains privacy counts without inventing links or private details', () => {
    const text = reportText({ ...base, visual: { ...visual, private_findings: 4, findings: [
      { kind: 'sample', surface: 'card', outcome: 'unavailable', reason: 'image_timeout', checked_at: '2026-10-12T17:00:00Z' },
    ] } });
    expect(text).toContain('4 other-account visual checks; private details omitted.');
    expect(text).not.toContain('Displayed image:');
    expect(text).not.toContain('Source:');
    expect(text).not.toContain('undefined');
  });
});
