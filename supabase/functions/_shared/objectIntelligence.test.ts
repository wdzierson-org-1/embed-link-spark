import { describe, expect, it } from 'vitest';
import {
  buildObjectIntelligenceSource, objectIntelligenceFingerprint, parseObjectIntelligenceOutput,
  readObjectIntelligence, objectIntelligenceSearchText, OBJECT_INTELLIGENCE_VERSION,
  OBJECT_INTELLIGENCE_OUTPUT_SCHEMA,
  validateObjectIntelligenceOutput, OBJECT_INTELLIGENCE_VALIDATION_REASONS,
} from './objectIntelligence';
import { extractObjectFacts } from './objectFacts';

const recipeItem = () => ({ type: 'link', url: 'https://www.tiktok.com/@supper/video/123', file_path: null,
  page_body: 'Tomato and mozzarella pasta. Ingredients: penne, cherry tomatoes, mozzarella, basil, olive oil. Blister cherry tomatoes in olive oil. Toss with penne and pasta water. Finish with mozzarella and basil. Ready in 20 minutes.',
  attributes: { enrichment: { evidence: { transcript: true, author: '@supper' } } } });
const value = (text: string, evidence = 'e1') => ({ value: text, evidence_ids: [evidence] });
const recipeOutput = () => ({ interpretation: { kind: 'recipe', summary: 'A quick tomato and mozzarella pasta.', topics: ['pasta', 'weeknight dinner'] },
  facts: { creator: value('@supper', 'e2'), recipe: {
    name: value('Tomato and mozzarella pasta'), ingredients: ['penne', 'cherry tomatoes', 'mozzarella', 'basil', 'olive oil'].map(x => value(x)),
    steps: [value('Blister cherry tomatoes in olive oil'), value('Toss with penne and pasta water'), value('Finish with mozzarella and basil')],
    duration: value('20 minutes'),
  } }, evidence: [{ id: 'e1', source_id: 'page_body', quote: recipeItem().page_body }, { id: 'e2', source_id: 'creator_metadata', quote: '@supper' }] });
async function extract(item = recipeItem(), output: unknown = recipeOutput()) {
  const source = buildObjectIntelligenceSource(item)!;
  const fingerprint = await objectIntelligenceFingerprint(source);
  return { source, fingerprint, result: parseObjectIntelligenceOutput(output, source, fingerprint, '2026-10-10T10:00:00Z') };
}

describe('object intelligence source binding', () => {
  it('uses captured transcript and creator metadata, never generated description or summary', () => {
    const source = buildObjectIntelligenceSource({ ...recipeItem(), description: 'Invented saffron recipe', summary: 'Invented lobster', attributes: {
      ...recipeItem().attributes, object_intelligence: { interpretation: { summary: 'Previous invented facts' } },
    } })!;
    expect(source.sources.map(x => x.id)).toEqual(['page_body', 'creator_metadata']);
    expect(source.fingerprint_input).not.toMatch(/saffron|lobster|Previous invented/);
    expect(source.sources[0].kind).toBe('transcript');
  });
  it('does not treat a title or visual description as factual source', () => {
    expect(buildObjectIntelligenceSource({ type: 'image', file_path: 'owner/photo.jpg', title: 'Recipe photo', description: 'Possibly a bowl of pasta', attributes: { enrichment: { evidence: { visual_text: 'Possibly basil' } } } })).toBeUndefined();
  });
  it('retains the quality gate source kind when an Instagram page becomes a caption', () => {
    const source = buildObjectIntelligenceSource({ type: 'link', url: 'https://www.instagram.com/reel/123/', page_body: 'Instagram More options A three day Lisbon trip: sunset at Graça and dinner in Alfama. Load more comments' })!;
    expect(source.sources[0]).toMatchObject({ id: 'page_body', kind: 'caption', text: 'A three day Lisbon trip: sunset at Graça and dinner in Alfama.' });
  });
  it('preserves an explicitly captured TikTok caption when the generic gate calls it a page', () => {
    const source = buildObjectIntelligenceSource({ type: 'link', url: 'https://www.tiktok.com/@supper/video/123', page_body: 'Tomato pasta for a quick weeknight dinner. Save this recipe for later!', attributes: { enrichment: { evidence: { caption: true } } } })!;
    expect(source.sources[0].kind).toBe('caption');
  });
  it('rejects access walls and waits for incomplete or failed recording transcripts', () => {
    expect(buildObjectIntelligenceSource({ type: 'link', url: 'https://example.org', page_body: 'Access denied. Verify you are human to see this recipe.' })).toBeUndefined();
    expect(buildObjectIntelligenceSource({ type: 'audio', page_body: 'Incomplete spoken recipe so far', attributes: { media: { transcript: { status: 'processing' } } } })).toBeUndefined();
    expect(buildObjectIntelligenceSource({ type: 'video', page_body: 'Only the first chunk was recovered.', attributes: { media: { transcript: { status: 'failed' } } } })).toBeUndefined();
  });
  it.each([
    { type: 'text', content: 'Ingredients: tomatoes and basil. Mix them together.' },
    { type: 'image', page_body: 'Estate sale: Saturday 10 October, 123 Main Street.' },
    { type: 'document', mime_type: 'application/pdf', page_body: 'A study of retrieval augmented generation.' },
    { type: 'audio', page_body: 'Ingredients: tomatoes and basil. Mix them together.', attributes: { media: { transcript: { status: 'done' } } } },
    { type: 'video', page_body: 'Ingredients: tomatoes and basil. Mix them together.' },
  ])('builds factual source for $type', item => {
    expect(buildObjectIntelligenceSource(item)?.sources.length).toBeGreaterThan(0);
  });
  it('fingerprints changed source and file identity but ignores generated and operational data', async () => {
    const item = recipeItem();
    const fingerprint = await objectIntelligenceFingerprint(buildObjectIntelligenceSource(item)!);
    expect(await objectIntelligenceFingerprint(buildObjectIntelligenceSource({ ...item, description: 'new description', summary: 'new summary', attributes: { ...item.attributes, location: { label: 'Home' }, object_intelligence: { processed_at: 'now' } } })!)).toBe(fingerprint);
    expect(await objectIntelligenceFingerprint(buildObjectIntelligenceSource({ ...item, page_body: item.page_body + ' Add salt.' })!)).not.toBe(fingerprint);
    expect(await objectIntelligenceFingerprint(buildObjectIntelligenceSource({ ...item, file_path: 'owner/new.jpg' })!)).not.toBe(fingerprint);
  });
  it('bounds model text while source changes after the window invalidate the fingerprint', async () => {
    const body = 'Recipe source with tomatoes. '.repeat(3000);
    const first = buildObjectIntelligenceSource({ type: 'text', content: body })!;
    const second = buildObjectIntelligenceSource({ type: 'text', content: body + 'Basil' })!;
    expect(first.sources.reduce((sum, x) => sum + x.text.length, 0)).toBeLessThanOrEqual(40_000);
    expect(first.sources[0].truncated).toBe(true);
    expect(await objectIntelligenceFingerprint(first)).not.toBe(await objectIntelligenceFingerprint(second));
  });
  it('binds publisher product identity and variant to the saved URL without recharging for timestamp-only refreshes', async () => {
    const url = 'https://shop.example.org/bag?color=tan';
    const facts = extractObjectFacts({ url, observedAt: '2026-10-10T01:00:00Z', html: `<script type="application/ld+json">${JSON.stringify({ '@type': 'Product', name: 'The Woven Tote', url, color: 'Tan', brand: 'Ines', sku: 'TOTE-TAN', material: 'leather', offers: { '@type': 'Offer', price: '248', priceCurrency: 'USD', url } })}</script>` })!;
    const item = { type: 'link', url, attributes: { object_facts: facts } };
    const source = buildObjectIntelligenceSource(item)!;
    expect(source.sources[0]).toMatchObject({ id: 'publisher_facts', kind: 'publisher_facts' });
    expect(source.sources[0].text).toContain('TOTE-TAN');
    expect(source.fingerprint_input).not.toContain('2026-10-10');
    const refreshed = buildObjectIntelligenceSource({ ...item, attributes: { object_facts: { ...facts, evidence: { ...facts.evidence, observed_at: '2026-10-11T01:00:00Z' } } } })!;
    expect(await objectIntelligenceFingerprint(source)).toBe(await objectIntelligenceFingerprint(refreshed));
    expect(buildObjectIntelligenceSource({ ...item, url: 'https://shop.example.org/other' })).toBeUndefined();
    const result = parseObjectIntelligenceOutput({ interpretation: { kind: 'product', summary: 'A tan woven leather tote.', topics: ['bags'] }, facts: { product: {
      name: value('The Woven Tote'), brand: value('Ines'), sku: value('TOTE-TAN'), color: value('Tan'), price: value('248'), currency: value('USD'),
    } }, evidence: [{ id: 'e1', source_id: 'publisher_facts', quote: source.sources[0].text }] }, source, await objectIntelligenceFingerprint(source));
    expect(result?.facts.product?.price?.value).toBe('248');
    expect(result?.capabilities).toContainEqual(expect.objectContaining({ id: 'price_comparison', status: 'needs_lookup', prerequisites: ['matching_variant', 'current_retailer_offers'] }));
  });
});

describe('grounded object intelligence output', () => {
  it('extracts supported recipe facts and locally derives draft capabilities', async () => {
    const { result } = await extract();
    expect(result).toMatchObject({ version: 1, beta: true, extraction_version: OBJECT_INTELLIGENCE_VERSION, interpretation: { kind: 'recipe' }, facts: { creator: { value: '@supper' } } });
    expect(result?.capabilities).toContainEqual(expect.objectContaining({ id: 'shopping_list', status: 'source_ready', effect: 'draft' }));
    expect(result?.capabilities).toContainEqual(expect.objectContaining({ id: 'grocery_order', status: 'needs_lookup', effect: 'external_write', requires_confirmation: true }));
  });
  it('does not promise recipe steps or a full recipe from a caption', async () => {
    const source = buildObjectIntelligenceSource({ type: 'link', url: 'https://www.tiktok.com/@supper/video/123', page_body: 'Tomato pasta for a quick weeknight dinner. Save this recipe for later!' })!;
    const result = parseObjectIntelligenceOutput({ interpretation: { kind: 'recipe', summary: 'A tomato pasta video.', topics: [] }, facts: { recipe: { name: value('Tomato pasta') } }, evidence: [{ id: 'e1', source_id: 'page_body', quote: source.sources[0].text }] }, source, await objectIntelligenceFingerprint(source));
    expect(result?.facts.recipe?.ingredients).toBeUndefined();
    expect(result?.capabilities.find(x => x.id === 'recipe_card')?.status).toBe('needs_more_content');
    expect(result?.capabilities.find(x => x.id === 'shopping_list')?.status).toBe('needs_more_content');
  });
  it('preserves Lisbon places without inventing accommodation or packing facts', async () => {
    const source = buildObjectIntelligenceSource({ type: 'text', content: '3 days in Lisbon. Sunset at Miradouro da Graça, then dinner in Alfama. Stay in Príncipe Real.' })!;
    const result = parseObjectIntelligenceOutput({ interpretation: { kind: 'travel', summary: 'A three-day Lisbon trip.', topics: ['Lisbon'] }, facts: { travel: {
      destination: value('Lisbon'), duration: value('3 days'), places: [value('Miradouro da Graça'), value('Alfama'), value('Príncipe Real')],
    } }, evidence: [{ id: 'e1', source_id: 'content', quote: source.sources[0].text }] }, source, await objectIntelligenceFingerprint(source));
    expect(result?.facts.travel?.accommodation).toBeUndefined();
    expect(result?.capabilities).toContainEqual(expect.objectContaining({ id: 'nearby_map', status: 'needs_lookup', effect: 'external_read' }));
    expect(result?.capabilities.find(x => x.id === 'packing_list')?.prerequisites).toContain('travel_dates');
  });
  it('accepts prices only as a pair from the canonical publisher offer, never a recommended product', async () => {
    const url = 'https://shop.example.org/bag?color=tan';
    const publisher = extractObjectFacts({ url, html: `<script type="application/ld+json">${JSON.stringify({ '@type': 'Product', name: 'The Woven Tote', url, sku: 'TOTE-99', offers: { '@type': 'Offer', price: '248', priceCurrency: 'USD', url } })}</script>` })!;
    const item = { type: 'link', url, page_body: 'The Woven Tote costs 248 USD. Recommended different bag costs 99 EUR.', attributes: { object_facts: publisher } };
    const source = buildObjectIntelligenceSource(item)!;
    const fingerprint = await objectIntelligenceFingerprint(source);
    const output: any = { interpretation: { kind: 'product', summary: 'A woven tote.', topics: [] }, facts: { product: { name: value('The Woven Tote'), price: value('248'), currency: value('USD') } }, evidence: [{ id: 'e1', source_id: 'page_body', quote: item.page_body }] };
    // Even a correct-looking body price must cite the separately bound publisher offer.
    expect(parseObjectIntelligenceOutput(output, source, fingerprint)).toBeUndefined();
    output.evidence[0] = { id: 'e1', source_id: 'publisher_facts', quote: source.sources.find(x => x.id === 'publisher_facts')!.text };
    expect(parseObjectIntelligenceOutput(output, source, fingerprint)?.facts.product?.price?.value).toBe('248');
    // 99 occurs in the SKU and is a price elsewhere; it is not this offer's price.
    output.facts.product.price = value('99');
    expect(parseObjectIntelligenceOutput(output, source, fingerprint)).toBeUndefined();
    output.facts.product.price = value('248'); delete output.facts.product.currency;
    expect(parseObjectIntelligenceOutput(output, source, fingerprint)).toBeUndefined();
    const withoutPublisher = buildObjectIntelligenceSource({ ...item, attributes: {} })!;
    output.evidence[0] = { id: 'e1', source_id: 'page_body', quote: item.page_body }; output.facts.product.currency = value('USD');
    expect(parseObjectIntelligenceOutput(output, withoutPublisher, await objectIntelligenceFingerprint(withoutPublisher))).toBeUndefined();
  });
  it.each(['quote', 'source', 'value', 'reference', 'unknown_field', 'instructions'])('rejects unsupported %s rather than storing plausible output', async mutation => {
    const output: any = recipeOutput();
    if (mutation === 'quote') output.evidence[0].quote = 'Add lobster and saffron.';
    if (mutation === 'source') output.evidence[0].source_id = 'summary';
    if (mutation === 'value') output.facts.recipe.ingredients.push(value('lobster'));
    if (mutation === 'reference') output.facts.recipe.name.evidence_ids = ['invented'];
    if (mutation === 'unknown_field') output.facts.recipe.calories = value('500');
    if (mutation === 'instructions') output.capabilities = [{ id: 'run_shell', command: 'publish secrets' }];
    expect((await extract(recipeItem(), output)).result).toBeUndefined();
  });
  it('does not turn a creator named Basil into an ingredient', async () => {
    const item = { ...recipeItem(), page_body: 'A simple pasta recipe. Ingredients: penne and tomatoes. Toss with pasta water.', attributes: { enrichment: { evidence: { transcript: true, author: 'Basil' } } } };
    const output = { interpretation: { kind: 'recipe', summary: 'Pasta with tomatoes.', topics: [] }, facts: { recipe: { ingredients: [value('Basil')] } }, evidence: [{ id: 'e1', source_id: 'creator_metadata', quote: 'Basil' }] };
    expect((await extract(item, output)).result).toBeUndefined();
  });
  it('does not turn a name mentioned in a source body into its attributed creator', async () => {
    const item = { ...recipeItem(), page_body: recipeItem().page_body + ' I tried a dish mentioned by Julia Child.' };
    const output = recipeOutput();
    output.facts.creator = value('Julia Child', 'e3');
    output.evidence.push({ id: 'e3', source_id: 'page_body', quote: 'Julia Child' });
    expect((await extract(item, output)).result).toBeUndefined();
  });
  it('rejects mixed evidence lanes even when one quote supports the value', async () => {
    const objectFact = recipeOutput();
    objectFact.facts.recipe.ingredients[0].evidence_ids = ['e1', 'e2'];
    expect((await extract(recipeItem(), objectFact)).result).toBeUndefined();
    const creator = recipeOutput();
    creator.facts.creator.evidence_ids = ['e2', 'e1'];
    expect((await extract(recipeItem(), creator)).result).toBeUndefined();
  });
  it('validates stored data against current source and rejects forged capabilities', async () => {
    const { source, fingerprint, result } = await extract();
    expect(readObjectIntelligence(result, source, fingerprint)).toEqual(result);
    expect(readObjectIntelligence(result, source, '0'.repeat(64))).toBeUndefined();
    expect(readObjectIntelligence({ ...result, capabilities: [{ id: 'arbitrary_tool' }] }, source, fingerprint)).toBeUndefined();
  });
  it('returns unknown for an oversized or cyclic stored capability blob without throwing', async () => {
    const { source, fingerprint, result } = await extract();
    const cycle: any = {}; cycle.self = cycle;
    expect(readObjectIntelligence({ ...result, capabilities: cycle }, source, fingerprint)).toBeUndefined();
    expect(readObjectIntelligence({ ...result, capabilities: ['x'.repeat(50_000)] }, source, fingerprint)).toBeUndefined();
  });
  it('caps the complete persisted envelope by UTF-8 bytes, not JavaScript characters', async () => {
    const makeCandidate = async (character: string) => {
      const ingredients = Array.from({ length: 24 }, (_, index) => `${index + 1} ${character.repeat(350)}`);
      const source = buildObjectIntelligenceSource({ type: 'text', content: ingredients.join('\n') })!;
      const output = { interpretation: { kind: 'recipe', summary: 'An ingredient list.', topics: [] }, facts: { recipe: { ingredients: ingredients.map((ingredient, index) => value(ingredient, `e${index + 1}`)) } },
        evidence: ingredients.map((ingredient, index) => ({ id: `e${index + 1}`, source_id: 'content', quote: ingredient })) };
      expect(JSON.stringify(output).length).toBeLessThan(40_000);
      return { output, result: parseObjectIntelligenceOutput(output, source, await objectIntelligenceFingerprint(source)) };
    };
    expect((await makeCandidate('a')).result).toBeDefined();
    const multibyte = await makeCandidate('食');
    expect(new TextEncoder().encode(JSON.stringify(multibyte.output)).byteLength).toBeGreaterThan(48_000);
    expect(multibyte.result).toBeUndefined();
  });
  it('rejects source-matching output with wrong category, oversized facts or duplicate evidence ids', async () => {
    const wrongKind = recipeOutput(); wrongKind.interpretation.kind = 'travel';
    expect((await extract(recipeItem(), wrongKind)).result).toBeUndefined();
    const duplicate = recipeOutput(); duplicate.evidence.push(duplicate.evidence[0]);
    expect((await extract(recipeItem(), duplicate)).result).toBeUndefined();
    const oversized = recipeOutput(); oversized.facts.recipe.ingredients = Array.from({ length: 25 }, () => value('penne'));
    expect((await extract(recipeItem(), oversized)).result).toBeUndefined();
  });
  it('accepts strict-provider nulls then returns sparse facts with only cited evidence', async () => {
    const output: any = recipeOutput();
    output.facts = { ...Object.fromEntries(Object.keys(OBJECT_INTELLIGENCE_OUTPUT_SCHEMA.properties.facts.properties).map(key => [key, null])), ...output.facts };
    output.facts.recipe.servings = null;
    output.evidence.push({ id: 'e3', source_id: 'page_body', quote: 'Ready in 20 minutes.' });
    const { result } = await extract(recipeItem(), output);
    expect(Object.keys(result!.facts)).toEqual(['creator', 'recipe']);
    expect(result!.facts.recipe).not.toHaveProperty('servings');
    expect(result!.evidence.map(x => x.id)).toEqual(['e1', 'e2']);
  });
  it('ignores unused invented quotations while preserving every grounded fact', async () => {
    const output = recipeOutput();
    output.evidence.push({ id: 'e3', source_id: 'page_body', quote: 'An invented quotation that is not referenced by any fact.' });
    const { result } = await extract(recipeItem(), output);
    expect(result?.facts.recipe?.ingredients).toHaveLength(5);
    expect(result?.evidence.map(x => x.id)).toEqual(['e1', 'e2']);
    const general = { interpretation: { kind: 'general', summary: 'A saved pasta video.', topics: [] }, facts: {}, evidence: output.evidence.slice(2) };
    expect((await extract(recipeItem(), general)).result?.evidence).toEqual([]);
  });
  it('resolves whitespace-only model quotations and values back to exact original source spans', async () => {
    const content = 'Ingredients: cherry\u00a0tomatoes,\n  olive oil. Cook for 20\r\nminutes.';
    const source = buildObjectIntelligenceSource({ type: 'text', content })!;
    const output = { interpretation: { kind: 'recipe', summary: 'Tomatoes cooked in olive oil.', topics: [] }, facts: { recipe: { ingredients: [value('cherry tomatoes'), value('olive oil')], duration: value('20 minutes') } },
      evidence: [{ id: 'e1', source_id: 'content', quote: 'Ingredients: cherry tomatoes, olive oil. Cook for 20 minutes.' }] };
    const fingerprint = await objectIntelligenceFingerprint(source);
    const result = parseObjectIntelligenceOutput(output, source, fingerprint)!;
    expect(result?.evidence[0].quote).toBe(content);
    expect(result?.facts.recipe?.ingredients?.[0].value).toBe('cherry\u00a0tomatoes');
    expect(result?.facts.recipe?.duration?.value).toBe('20\r\nminutes');
    expect(readObjectIntelligence(result, source, fingerprint)).toEqual(result);
  });
  it.each(['Blister cherry tomatoes IN olive oil', 'Cook cherry tomatoes in olive oil', 'Blister cherry tomatoes; in olive oil'])('still rejects a referenced quote with word/case/punctuation edits: %s', async quote => {
    const output = recipeOutput(); output.evidence[0].quote = quote;
    expect((await extract(recipeItem(), output)).result).toBeUndefined();
  });
  it('rejects a whitespace match whose original span exceeds the existing quote bound', async () => {
    const source = buildObjectIntelligenceSource({ type: 'text', content: `tomatoes${' '.repeat(400)}basil` })!;
    const output = { interpretation: { kind: 'recipe', summary: 'Two ingredients.', topics: [] }, facts: { recipe: { ingredients: [value('tomatoes')] } }, evidence: [{ id: 'e1', source_id: 'content', quote: 'tomatoes basil' }] };
    expect(validateObjectIntelligenceOutput(output, source, await objectIntelligenceFingerprint(source))).toEqual({ ok: false, reason: 'quote_not_in_source' });
  });
  it('provides a closed strict-output schema with nullable unknown facts', () => {
    const visit = (schema: any) => {
      if (!schema || typeof schema !== 'object') return;
      if (schema.type === 'object') {
        expect(schema.additionalProperties).toBe(false);
        expect(schema.required).toEqual(Object.keys(schema.properties));
        Object.values(schema.properties).forEach(visit);
      }
      schema.anyOf?.forEach(visit);
      if (schema.items) visit(schema.items);
    };
    visit(OBJECT_INTELLIGENCE_OUTPUT_SCHEMA);
  });
  it('indexes grounded attributes and interpretation kind without fictional future artifacts', async () => {
    const { result } = await extract();
    const search = objectIntelligenceSearchText(result!);
    expect(search).toContain('penne');
    expect(search).toContain('@supper');
    expect(search).not.toMatch(/shopping_list|grocery_order|2026-10|quick tomato/);
  });
});

describe('content-free object intelligence validation diagnostics', () => {
  it('returns the same successful envelope as the compatibility parser', async () => {
    const { source, fingerprint, result } = await extract();
    expect(validateObjectIntelligenceOutput(recipeOutput(), source, fingerprint, '2026-10-10T10:00:00Z')).toEqual({ ok: true, value: result });
  });
  it.each([
    ['root_shape', (output: any) => { output.command = 'private malicious instruction'; }],
    ['interpretation', (output: any) => { output.interpretation.summary = ''; }],
    ['evidence_shape', (output: any) => { output.evidence[0].quote = ''; }],
    ['source_missing', (output: any) => { output.evidence[0].source_id = 'private_missing_source'; }],
    ['quote_not_in_source', (output: any) => { output.evidence[0].quote = 'Private invented quote about lobster.'; }],
    ['fact_shape', (output: any) => { output.facts.recipe.ingredients[0].unknown = 'private value'; }],
    ['evidence_reference', (output: any) => { output.facts.recipe.ingredients[0].evidence_ids = ['private_missing_id']; }],
    ['evidence_lane', (output: any) => { output.facts.recipe.ingredients[0].evidence_ids = ['e1', 'e2']; }],
    ['value_not_in_quote', (output: any) => { output.facts.recipe.ingredients[0].value = 'Private invented lobster.'; }],
    ['fact_group', (output: any) => { output.interpretation.kind = 'travel'; }],
  ] as const)('returns only the closed %s reason for rejected output', async (reason, mutate) => {
    const { source, fingerprint } = await extract();
    const output = recipeOutput(); mutate(output);
    const validation = validateObjectIntelligenceOutput(output, source, fingerprint);
    expect(validation).toEqual({ ok: false, reason });
    expect(OBJECT_INTELLIGENCE_VALIDATION_REASONS).toContain(reason);
    expect(JSON.stringify(validation)).not.toContain('private');
    expect(parseObjectIntelligenceOutput(output, source, fingerprint)).toBeUndefined();
  });
  it('distinguishes invalid binding from an oversized envelope without echoing input', async () => {
    const { source, fingerprint } = await extract();
    expect(validateObjectIntelligenceOutput(recipeOutput(), source, 'invalid')).toEqual({ ok: false, reason: 'input_binding' });
    const output = recipeOutput();
    output.evidence = Array.from({ length: 48 }, (_, index) => ({ id: `e${index + 1}`, source_id: 'page_body', quote: 'x'.repeat(1000) }));
    expect(validateObjectIntelligenceOutput(output, source, fingerprint)).toEqual({ ok: false, reason: 'envelope_size' });
  });
});
