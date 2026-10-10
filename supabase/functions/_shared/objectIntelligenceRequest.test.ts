// @vitest-environment node
import { describe, expect, it } from 'vitest';
import { OBJECT_INTELLIGENCE_OUTPUT_SCHEMA, OBJECT_INTELLIGENCE_VERSION, validateObjectIntelligenceOutput, type ObjectIntelligenceSource } from './objectIntelligence.ts';
import { buildObjectIntelligenceRequest } from './objectIntelligenceRequest.ts';

function source(blocks: Array<{ id: string; kind: ObjectIntelligenceSource['sources'][number]['kind']; text: string }>): ObjectIntelligenceSource {
  return { version: OBJECT_INTELLIGENCE_VERSION, identity: { type: 'link', url: 'https://example.com/recipe', file_path: null, mime_type: null },
    sources: blocks.map(block => ({ ...block, truncated: false })), fingerprint_input: 'test source' };
}
const fingerprint = 'a'.repeat(64);
const recipeSource = source([
  { id: 'page_body', kind: 'transcript', text: 'Tomato salad. Slice tomatoes and add olive oil. Serve with basil.' },
  { id: 'creator_metadata', kind: 'creator_metadata', text: '{"author":"Recipe Author","handle":"recipe.author","platform":"tiktok"}' },
]);
const output = () => ({ interpretation: { kind: 'recipe', summary: 'A tomato salad.', topics: ['salad'] }, facts: {
  recipe: { name: { value: 'Tomato salad', evidence_ids: ['e1'] }, ingredients: [{ value: 'tomatoes', evidence_ids: ['e1'] }] },
  creator: { value: 'Recipe Author', evidence_ids: ['e2'] },
} });

describe('server-owned object intelligence citation requests', () => {
  it('reconstructs exact source evidence from selected IDs and preserves every claimed fact', () => {
    const request = buildObjectIntelligenceRequest(recipeSource);
    expect(request.sources).toEqual([
      { id: 'e1', kind: 'transcript', text: recipeSource.sources[0].text },
      { id: 'e2', kind: 'creator_metadata', text: recipeSource.sources[1].text },
    ]);
    const candidate = output();
    const materialized = request.materialize(candidate);
    expect(materialized.facts).toEqual(candidate.facts);
    expect(materialized.evidence).toEqual([
      { id: 'e1', source_id: 'page_body', quote: recipeSource.sources[0].text },
      { id: 'e2', source_id: 'creator_metadata', quote: recipeSource.sources[1].text },
    ]);
    expect(validateObjectIntelligenceOutput(materialized, recipeSource, fingerprint).ok).toBe(true);
    expect(candidate).not.toHaveProperty('evidence');
  });

  it('uses a single shared reference enum and keeps all schema objects closed', () => {
    const before = JSON.stringify(OBJECT_INTELLIGENCE_OUTPUT_SCHEMA);
    const { schema, prompt } = buildObjectIntelligenceRequest(recipeSource);
    expect(schema.required).toEqual(['interpretation', 'facts']);
    expect(schema.properties).not.toHaveProperty('evidence');
    expect(schema.$defs).toEqual({ evidence_id: { type: 'string', enum: ['e1', 'e2'] } });
    let references = 0, referenceEnums = 0;
    const visit = (node: any) => {
      if (!node || typeof node !== 'object') return;
      if (node.type === 'object') {
        expect(node.additionalProperties).toBe(false);
        expect(node.required).toEqual(Object.keys(node.properties));
      }
      if (node.properties?.evidence_ids) {
        references++;
        expect(node.properties.evidence_ids.items).toEqual({ $ref: '#/$defs/evidence_id' });
      }
      if (node.enum?.includes('e1')) referenceEnums++;
      Object.values(node).forEach(visit);
    };
    visit(schema);
    expect(references).toBeGreaterThan(20);
    expect(referenceEnums).toBe(1);
    expect(prompt).toContain('Do not output an evidence array');
    expect(prompt).toContain('untrusted data');
    expect(JSON.stringify(OBJECT_INTELLIGENCE_OUTPUT_SCHEMA)).toBe(before);
  });

  it('covers all 40,000 source characters in overlapping exact snippets within both limits', () => {
    const blocks = [
      { id: 'page_body', kind: 'transcript' as const, text: Array.from({ length: 800 }, (_, index) => `Sentence ${index} has complete words and distinct details. `).join('').slice(0, 28_000) },
      { id: 'publisher_facts', kind: 'publisher_facts' as const, text: Array.from({ length: 250 }, (_, index) => `{"name":"Alpha ${index}","details":"product facts"},`).join('').slice(0, 8_000) },
      { id: 'creator_metadata', kind: 'creator_metadata' as const, text: Array.from({ length: 200 }, (_, index) => `Explicit creator record ${index}. `).join('').slice(0, 4_000) },
    ];
    const request = buildObjectIntelligenceRequest(source(blocks));
    expect(request.sources.length).toBeLessThanOrEqual(250);
    expect(request.sources.map(block => block.id)).toEqual(request.sources.map((_, index) => `e${index + 1}`));
    for (const block of blocks) {
      const snippets = request.sources.filter(candidate => candidate.kind === block.kind);
      let previousStart = -1, previousEnd = 0;
      for (const snippet of snippets) {
        expect(snippet.text.length).toBeLessThanOrEqual(400);
        // Search after the prior start because repeated source phrases can occur
        // in earlier excerpts. Each next window must overlap the previous one.
        const start = block.text.indexOf(snippet.text, previousStart + 1);
        expect(start).toBeGreaterThanOrEqual(0);
        expect(start).toBeLessThanOrEqual(previousEnd);
        previousStart = start; previousEnd = start + snippet.text.length;
      }
      expect(previousEnd).toBe(block.text.length);
    }
  });

  it('handles long tokens and surrogate pairs without dropping source characters', () => {
    const text = '🧥'.repeat(14_000);
    const request = buildObjectIntelligenceRequest(source([{ id: 'page_body', kind: 'ocr', text }]));
    expect(request.sources.length).toBeLessThanOrEqual(250);
    for (const snippet of request.sources) {
      expect(snippet.text.length).toBeLessThanOrEqual(400);
      expect(snippet.text).toMatch(/^(?:🧥)+$/u);
    }
    expect(request.sources.at(-1)!.text.endsWith('🧥')).toBe(true);
  });

  it('prefers sentence/word boundaries while keeping nearby text in overlapping windows', () => {
    const text = Array.from({ length: 100 }, (_, index) => `Sentence ${index} has several distinct words.`).join(' ');
    const request = buildObjectIntelligenceRequest(source([{ id: 'page_body', kind: 'page', text }]));
    for (const snippet of request.sources.slice(0, -1)) {
      const start = text.indexOf(snippet.text);
      expect(start === 0 || /\s/.test(text[start - 1])).toBe(true);
      expect(snippet.text).toMatch(/[.!?]\s*$/);
    }
  });

  it.each([
    { ...output(), evidence: [{ id: 'e1', source_id: 'page_body', quote: 'invented quote' }] },
    { ...output(), capabilities: [] },
    { interpretation: output().interpretation },
    null,
  ])('rejects a model-authored or incomplete root instead of silently stripping it', value => {
    expect(() => buildObjectIntelligenceRequest(recipeSource).materialize(value)).toThrow('extraction_evidence_root_shape');
  });

  it('rejects unknown references instead of dropping their claims', () => {
    const value = output(); value.facts.recipe.name.evidence_ids = ['e250'];
    expect(() => buildObjectIntelligenceRequest(recipeSource).materialize(value)).toThrow('extraction_evidence_evidence_reference');
  });

  it('retains unsupported fact values for rejection by the strict core validator', () => {
    const value = output(); value.facts.recipe.ingredients[0].value = 'cinnamon';
    const materialized = buildObjectIntelligenceRequest(recipeSource).materialize(value);
    expect(materialized.facts).toEqual(value.facts);
    expect(validateObjectIntelligenceOutput(materialized, recipeSource, fingerprint)).toEqual({ ok: false, reason: 'value_not_in_quote' });
  });

  it('cannot turn a creator mention into an ingredient or a body mention into the creator', () => {
    const request = buildObjectIntelligenceRequest(recipeSource);
    const wrongIngredient = output(); wrongIngredient.facts.recipe.ingredients = [{ value: 'Recipe Author', evidence_ids: ['e2'] }];
    const wrongCreator = output(); wrongCreator.facts.creator = { value: 'Tomato salad', evidence_ids: ['e1'] };
    for (const value of [wrongIngredient, wrongCreator]) {
      expect(validateObjectIntelligenceOutput(request.materialize(value), recipeSource, fingerprint)).toEqual({ ok: false, reason: 'evidence_lane' });
    }
  });

  it('materializes only cited snippets and never truncates an over-large evidence set', () => {
    const longSource = source([{ id: 'page_body', kind: 'transcript', text: 'This contains the word tomato and exact source details. '.repeat(510) }]);
    const request = buildObjectIntelligenceRequest(longSource);
    expect(request.materialize({ interpretation: output().interpretation, facts: {} }).evidence).toEqual([]);
    const facts = { recipe: { ingredients: request.sources.slice(0, 24).map((block, index) => ({ value: 'tomato', evidence_ids: [block.id, request.sources[index + 24].id, request.sources[index + 48].id] })) } };
    const materialized = request.materialize({ interpretation: output().interpretation, facts });
    expect(materialized.evidence).toHaveLength(72);
    expect(materialized.facts).toEqual(facts);
    expect(validateObjectIntelligenceOutput(materialized, longSource, fingerprint)).toEqual({ ok: false, reason: 'evidence_shape' });
  });

  it('does not let caller mutation change the server-owned quotations', () => {
    const request = buildObjectIntelligenceRequest(recipeSource);
    request.sources[0].text = 'invented text';
    const first = request.materialize(output()); first.evidence[0].quote = 'another invention';
    expect(request.materialize(output()).evidence[0].quote).toBe(recipeSource.sources[0].text);
  });

  it('keeps publisher price pairing and source provenance under the existing strict validator', () => {
    const productSource = source([
      { id: 'page_body', kind: 'page', text: 'A jacket costs 999 USD and is made from wool.' },
      { id: 'publisher_facts', kind: 'publisher_facts', text: '{"kind":"product","product":{"offer":{"price":"748","currency":"USD"}}}' },
    ]);
    const request = buildObjectIntelligenceRequest(productSource);
    const value = { interpretation: { kind: 'product', summary: 'A jacket.', topics: [] }, facts: { product: {
      price: { value: '748', evidence_ids: ['e2'] }, currency: { value: 'USD', evidence_ids: ['e2'] },
    } } };
    expect(validateObjectIntelligenceOutput(request.materialize(value), productSource, fingerprint).ok).toBe(true);
    value.facts.product.price = { value: '999', evidence_ids: ['e1'] };
    expect(validateObjectIntelligenceOutput(request.materialize(value), productSource, fingerprint)).toEqual({ ok: false, reason: 'price_pair' });
  });

  it('rejects source input beyond the capture bound instead of dropping captured context', () => {
    expect(() => buildObjectIntelligenceRequest(source([{ id: 'page_body', kind: 'note', text: 'a'.repeat(40_001) }]))).toThrow('extraction_evidence_input_binding');
    expect(() => buildObjectIntelligenceRequest(source([]))).toThrow('extraction_evidence_input_binding');
    expect(() => buildObjectIntelligenceRequest(source([
      { id: 'page_body', kind: 'page', text: 'first' }, { id: 'page_body', kind: 'page', text: 'second' },
    ]))).toThrow('extraction_evidence_input_binding');
  });
});
