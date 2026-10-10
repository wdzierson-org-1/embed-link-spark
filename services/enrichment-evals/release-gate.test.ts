import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { previewImageEvidence } from '../../supabase/functions/_shared/pagePreview';
import { inspectSourceText, QUALITY_VERSION } from '../../supabase/functions/_shared/enrichmentQuality';
import { extractObjectFacts } from '../../supabase/functions/_shared/objectFacts';
import { evaluateCases } from './evaluator';
import { fixtures } from './fixtures';

const observedAt = '2026-10-10T00:00:00.000Z';
const report = evaluateCases(fixtures, {
  images: previewImageEvidence,
  source: input => {
    const { usable, reason } = inspectSourceText(input.url, input.body, input.sourceKind);
    return { usable, reason };
  },
  facts: input => {
    const result = extractObjectFacts({ url: input.url, html: input.html || '', observedAt });
    if (!result) return;
    if (result.version !== 1 || result.beta !== true || result.evidence.method !== 'json-ld' ||
      result.evidence.extraction_version !== 'object-facts-v1' || result.evidence.source_url !== input.url ||
      result.evidence.observed_at !== observedAt) throw new Error('Object facts lost their versioned source evidence');
    // Metadata is checked above; all other leaves must match the explicit fact gold.
    const { version: _version, beta: _beta, evidence: _evidence, ...facts } = result;
    return facts;
  },
});

const implementationFiles = ['pagePreview.ts', 'previewUrl.ts', 'enrichmentQuality.ts', 'objectFacts.ts', 'textHygiene.ts'];
const implementationHashes = Object.fromEntries(implementationFiles.map(name => [name,
  createHash('sha256').update(readFileSync(new URL(`../../supabase/functions/_shared/${name}`, import.meta.url))).digest('hex'),
]));
const artifact = JSON.stringify({ ...report, quality_version: QUALITY_VERSION, implementation_sha256: implementationHashes }, null, 2) + '\n';
if (Buffer.byteLength(artifact) > 300_000) throw new Error('Evaluation artifact exceeded the 300 KB limit');
const directory = fileURLToPath(new URL('./artifacts/', import.meta.url));
mkdirSync(directory, { recursive: true });
// Write before assertions so CI retains failures as well as successful gates.
writeFileSync(`${directory}/enrichment-evaluation.json`, artifact);

describe('Enrichment regression release gate', () => {
  it.each(report.cases)('$kind: $id', result => {
    expect(result.rejection_reasons, JSON.stringify(result.actual)).toEqual([]);
  });
});
