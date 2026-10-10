import { describe, expect, it } from 'vitest';
import { evaluateCases, compareReports, type EvalCase, type Playbook } from './evaluator';

const cases: EvalCase[] = [
  { id: 'exact-artwork', kind: 'image', provenance: 'Synthetic evaluator control', input: { url: 'https://example.com/object' }, expected: { images: ['https://example.com/object.jpg'] } },
  { id: 'login-page', kind: 'source', provenance: 'Synthetic evaluator control', input: { url: 'https://example.com/login', body: 'Sign in' }, expected: { usable: false, reason: 'login_page' } },
  { id: 'exact-price', kind: 'facts', provenance: 'Synthetic evaluator control', input: { url: 'https://example.com/object', html: '' }, expected: { facts: { kind: 'product', product: { offer: { price: '12.00', currency: 'USD' } } } } },
];
const accurate: Playbook = {
  images: () => [{ url: 'https://example.com/object.jpg', associated: true }],
  source: () => ({ usable: false, reason: 'login_page' }),
  facts: () => ({ kind: 'product', product: { offer: { price: '12.00', currency: 'USD' } } }),
};

describe('release gate evaluates independently labelled outcomes', () => {
  it('fails a higher-fill candidate that selects unrelated art, accepts a login page, and invents a fact', () => {
    const unsafe = evaluateCases(cases, {
      ...accurate,
      images: () => [{ url: 'https://example.com/campaign.jpg', associated: true }],
      source: () => ({ usable: true }),
      facts: () => ({ kind: 'product', product: { offer: { price: '12.00', currency: 'USD' }, discount: '50%' } }),
    });
    expect(unsafe.gate.passed).toBe(false);
    expect(unsafe.metrics.wrong_images).toBe(1);
    expect(unsafe.metrics.unsafe_sources_accepted).toBe(1);
    expect(unsafe.metrics.unsupported_facts).toBe(1);
    expect(unsafe.cases.flatMap(c => c.rejection_reasons)).toEqual(expect.arrayContaining([
      'wrong_image:https://example.com/campaign.jpg', 'unsafe_source_accepted', 'unsupported_fact:product.discount',
    ]));
  });

  it('cannot pass by abstaining from every positive control', () => {
    const report = evaluateCases(cases, { ...accurate, images: () => [], facts: () => undefined });
    expect(report.gate.passed).toBe(false);
    expect(report.metrics.missing_expected_images).toBe(1);
    expect(report.metrics.missing_expected_facts).toBe(3);
  });

  it('records errors as failed cases and continues the remaining corpus', () => {
    const report = evaluateCases(cases, { ...accurate, images: () => { throw new Error('unexpected'); } });
    expect(report.cases).toHaveLength(3);
    expect(report.cases[0].rejection_reasons).toEqual(['evaluator_error:unexpected']);
    expect(report.gate.passed).toBe(false);
  });

  it('compares outcomes by case ID and refuses mismatched corpus comparisons', () => {
    const baseline = evaluateCases(cases, accurate);
    expect(baseline.gate.passed).toBe(true);
    const candidate = evaluateCases(cases, { ...accurate, images: () => [] });
    expect(compareReports(baseline, candidate).regressed_case_ids).toEqual(['exact-artwork']);
    expect(() => compareReports(baseline, evaluateCases(cases.slice(1), accurate))).toThrow(/same corpus/);
  });
});
