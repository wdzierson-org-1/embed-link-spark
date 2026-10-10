import { createHash } from 'node:crypto';
import manifest from './manifest.json';

export interface EvalCase {
  id: string;
  kind: 'image' | 'source' | 'facts';
  provenance: string;
  input: { url: string; html?: string; text?: string; title?: string; body?: string; sourceKind?: 'page' | 'caption' | 'transcript' | 'ocr' };
  expected: { images?: string[]; usable?: boolean; reason?: string; facts?: Record<string, unknown> | null };
}
export interface Playbook {
  images(input: EvalCase['input']): Array<{ url: string; associated: boolean }>;
  source(input: EvalCase['input']): { usable: boolean; reason?: string };
  facts(input: EvalCase['input']): unknown;
}

const emptyMetrics = () => ({
  wrong_images: 0, missing_expected_images: 0, unsafe_sources_accepted: 0,
  usable_sources_rejected: 0, unsupported_facts: 0, missing_expected_facts: 0,
  incorrect_facts: 0, evaluator_errors: 0,
  returned_images: 0, correct_images: 0, expected_images: 0,
  returned_facts: 0, correct_facts: 0, expected_facts: 0,
});
type Metrics = ReturnType<typeof emptyMetrics>;
export interface CaseResult {
  id: string; kind: EvalCase['kind']; passed: boolean; provenance: string;
  rejection_reasons: string[]; metrics: Metrics; actual: unknown;
}
export interface EvaluationReport {
  evaluator_version: string; playbook_version: string; corpus_version: string;
  corpus_kind: string; held_out: boolean; limits: string; corpus_sha256: string;
  gate: { passed: boolean; failed_case_ids: string[]; rule: string };
  metrics: Metrics & { cases: number; passed_cases: number; image_precision: number | null; image_coverage: number | null; fact_precision: number | null; fact_coverage: number | null };
  cases: CaseResult[];
}

/** Compare literal labelled leaves; extra fields are unsupported, not free enrichment. */
function leaves(value: unknown, path = '', output: Record<string, unknown> = {}): Record<string, unknown> {
  if (value === undefined || value === null) return output;
  if (typeof value === 'object' && !Array.isArray(value)) {
    for (const key of Object.keys(value).sort()) leaves((value as Record<string, unknown>)[key], path ? `${path}.${key}` : key, output);
  } else output[path] = value;
  return output;
}

export function evaluateCases(cases: EvalCase[], playbook: Playbook): EvaluationReport {
  if (!cases.length || new Set(cases.map(c => c.id)).size !== cases.length) throw new Error('A nonempty corpus with unique case IDs is required');
  const results = cases.map((fixture): CaseResult => {
    const metrics = emptyMetrics(), reasons: string[] = [];
    let actual: unknown;
    try {
      if (fixture.kind === 'image') {
        const expected = fixture.expected.images;
        if (!expected) throw new Error('Image gold labels are required');
        const images = playbook.images(fixture.input);
        actual = images;
        const returned = [...new Set(images.map(image => image.url))];
        metrics.returned_images = returned.length; metrics.expected_images = expected.length;
        for (const url of returned) {
          if (expected.includes(url)) metrics.correct_images++;
          else { metrics.wrong_images++; reasons.push(`wrong_image:${url}`); }
        }
        for (const url of expected) {
          if (!returned.includes(url)) { metrics.missing_expected_images++; reasons.push(`missing_expected_image:${url}`); }
        }
      } else if (fixture.kind === 'source') {
        if (typeof fixture.expected.usable !== 'boolean') throw new Error('Source gold labels are required');
        const source = playbook.source(fixture.input); actual = source;
        if (source.usable && !fixture.expected.usable) { metrics.unsafe_sources_accepted++; reasons.push('unsafe_source_accepted'); }
        if (!source.usable && fixture.expected.usable) { metrics.usable_sources_rejected++; reasons.push('usable_source_rejected'); }
        if (fixture.expected.reason && source.reason !== fixture.expected.reason) reasons.push(`incorrect_source_reason:expected_${fixture.expected.reason}:received_${source.reason || 'none'}`);
      } else {
        if (fixture.expected.facts === undefined) throw new Error('Fact gold labels are required');
        const facts = playbook.facts(fixture.input);
        const returned = leaves(facts), expected = leaves(fixture.expected.facts);
        actual = returned;
        metrics.returned_facts = Object.keys(returned).length; metrics.expected_facts = Object.keys(expected).length;
        for (const key of Object.keys(returned)) {
          if (!(key in expected)) { metrics.unsupported_facts++; reasons.push(`unsupported_fact:${key}`); }
          else if (JSON.stringify(returned[key]) !== JSON.stringify(expected[key])) { metrics.incorrect_facts++; reasons.push(`incorrect_fact:${key}`); }
          else metrics.correct_facts++;
        }
        for (const key of Object.keys(expected)) {
          if (!(key in returned)) { metrics.missing_expected_facts++; reasons.push(`missing_expected_fact:${key}`); }
        }
      }
    } catch (error) {
      metrics.evaluator_errors++;
      reasons.push(`evaluator_error:${error instanceof Error ? error.message.slice(0, 200) : 'unknown'}`);
    }
    return { id: fixture.id, kind: fixture.kind, provenance: fixture.provenance, passed: reasons.length === 0, rejection_reasons: reasons, metrics, actual };
  });
  const metrics = emptyMetrics();
  for (const result of results) for (const key of Object.keys(metrics) as Array<keyof Metrics>) metrics[key] += result.metrics[key];
  const ratio = (count: number, total: number) => total ? count / total : null;
  const failed = results.filter(result => !result.passed).map(result => result.id);
  return {
    ...manifest,
    corpus_sha256: createHash('sha256').update(JSON.stringify(cases)).digest('hex'),
    gate: { passed: failed.length === 0, failed_case_ids: failed, rule: 'Every explicit gold expectation must pass; wrong images, unsupported/incorrect facts, unsafe content, and lost positive controls block release.' },
    metrics: {
      ...metrics, cases: results.length, passed_cases: results.length - failed.length,
      image_precision: ratio(metrics.correct_images, metrics.returned_images),
      image_coverage: ratio(metrics.correct_images, metrics.expected_images),
      fact_precision: ratio(metrics.correct_facts, metrics.returned_facts),
      fact_coverage: ratio(metrics.correct_facts, metrics.expected_facts),
    },
    cases: results,
  };
}

export function compareReports(baseline: EvaluationReport, candidate: EvaluationReport) {
  if (baseline.corpus_sha256 !== candidate.corpus_sha256 || baseline.evaluator_version !== candidate.evaluator_version) throw new Error('Comparisons require the same corpus and evaluator version');
  const previous = new Map(baseline.cases.map(result => [result.id, result]));
  return {
    regressed_case_ids: candidate.cases.filter(result => previous.get(result.id)?.passed && !result.passed).map(result => result.id),
    improved_case_ids: candidate.cases.filter(result => !previous.get(result.id)?.passed && result.passed).map(result => result.id),
    candidate_passed: candidate.gate.passed,
  };
}
