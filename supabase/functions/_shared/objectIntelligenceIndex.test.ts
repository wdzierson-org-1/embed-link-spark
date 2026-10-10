import { expect, it } from 'vitest';
import { enrichmentIndexedText, searchFingerprint } from './enrichmentStore';
import { buildObjectIntelligenceSource, objectIntelligenceFingerprint, parseObjectIntelligenceOutput } from './objectIntelligence';

it('indexes current grounded facts but never future artifacts or old-source intelligence', async () => {
  const item = { type: 'text', content: 'Penne pasta recipe with tomatoes. Cook the penne, blister the tomatoes and combine.', attributes: {} as Record<string, any> };
  const source = buildObjectIntelligenceSource(item)!;
  item.attributes.object_intelligence = parseObjectIntelligenceOutput({
    interpretation: { kind: 'recipe', summary: 'A quick dinner.', topics: ['weeknight'] },
    facts: { recipe: { ingredients: [{ value: 'tomatoes', evidence_ids: ['e1'] }] } },
    evidence: [{ id: 'e1', source_id: 'content', quote: 'Penne pasta recipe with tomatoes.' }],
  }, source, await objectIntelligenceFingerprint(source));
  const indexed = await enrichmentIndexedText(item);
  expect(indexed).toContain('recipe · tomatoes');
  expect(indexed).not.toContain('shopping_list'); expect(indexed).not.toContain('grocery_order');
  expect(indexed).not.toContain('A quick dinner.');
  const fingerprint = await searchFingerprint(item);
  item.content = 'A note about the quarterly planning meeting.';
  expect(await enrichmentIndexedText(item)).not.toContain('tomatoes');
  expect(await searchFingerprint(item)).not.toBe(fingerprint);
});
