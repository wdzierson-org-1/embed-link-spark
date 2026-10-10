import { describe, expect, it } from 'vitest';
import { buildObjectInteractionDraft, type ObjectDraftAction } from './objectInteractionDraft';
import { OBJECT_INTELLIGENCE_VERSION, objectIntelligenceCapabilities, type EvidenceValue, type ObjectIntelligence, type ObjectIntelligenceFacts, type ObjectIntelligenceKind } from './objectIntelligence';

const ITEM_ID = '60a4d902-4af5-4519-b657-c59b88fce27b';
const NOW = '2026-10-10T12:00:00.000Z';
const fact = (value: string, ...evidence_ids: string[]): EvidenceValue => ({ value, evidence_ids });
function intelligence(kind: ObjectIntelligenceKind, facts: ObjectIntelligenceFacts): ObjectIntelligence {
  return { version: 1, beta: true, extraction_version: OBJECT_INTELLIGENCE_VERSION,
    source_fingerprint: 'a'.repeat(64), processed_at: NOW,
    interpretation: { kind, summary: 'Model summary that must not enter a source-backed draft.', topics: ['generated topic'] },
    facts, capabilities: objectIntelligenceCapabilities(kind, facts),
    evidence: Array.from({ length: 12 }, (_, index) => ({ id: `e${index + 1}`, source_id: 'page_body', quote: `Private captured quotation ${index + 1}` })),
  };
}
const recipe = () => intelligence('recipe', {
  creator: fact('@sundaysupper', 'e8'),
  recipe: { name: fact('Tomato & mozzarella penne', 'e1'),
    ingredients: [fact('200 g penne', 'e2'), fact('2 tbsp olive oil', 'e3'), fact('200 g penne', 'e9'), fact('olive oil, to finish', 'e4')],
    steps: [fact('Blister tomatoes in olive oil.', 'e5'), fact('Toss with penne and pasta water.', 'e6'), fact('Finish with mozzarella.', 'e7')],
    servings: fact('Serves 2', 'e10'), duration: fact('20 minutes', 'e11'), cuisine: fact('Italian', 'e12'),
  },
});
const travel = () => intelligence('travel', { creator: fact('@ana.wanders', 'e7'), travel: {
  destination: fact('Lisbon', 'e1'), duration: fact('3 days', 'e2'),
  places: [fact('Miradouro da Graça', 'e3'), fact('Alfama', 'e4'), fact('Miradouro da Graça', 'e8'), fact('Príncipe Real', 'e5')],
  accommodation: [fact('A quiet place to stay in Príncipe Real', 'e6')],
} });

function deepFreeze<T>(value: T): T {
  if (value && typeof value === 'object') { Object.freeze(value); for (const child of Object.values(value)) deepFreeze(child); }
  return value;
}

describe('source-backed interaction drafts', () => {
  it('creates a shopping checklist preserving quantities and distinct ingredient variants', () => {
    const result = buildObjectInteractionDraft(recipe(), 'shopping_list', ITEM_ID, NOW)!;
    expect(result).toMatchObject({ version: 1, action: 'shopping_list', title: 'Tomato & mozzarella penne shopping list',
      source_item_id: ITEM_ID, source_fingerprint: 'a'.repeat(64), created_at: NOW });
    expect(result.content).toContain('- [ ] 200 g penne');
    expect(result.content).toContain('- [ ] 2 tbsp olive oil');
    expect(result.content).toContain('- [ ] olive oil, to finish');
    expect(result.content.match(/200 g penne/g)).toHaveLength(1);
    expect(result.content).not.toMatch(/Blister|Serves 2|20 minutes|Italian|Private captured quotation|Model summary|generated topic/);
    expect(result.evidence_ids).toEqual(['e1', 'e2', 'e3', 'e4']);
    expect(result.notices.join(' ')).toMatch(/quantities|amounts/i);
  });

  it('creates a recipe card from exact source steps, context, and creator without summary inference', () => {
    const result = buildObjectInteractionDraft(recipe(), 'recipe_card', ITEM_ID, NOW)!;
    expect(result.title).toBe('Tomato & mozzarella penne recipe card');
    expect(result.content).toContain('Creator: @sundaysupper');
    expect(result.content).toContain('Servings: Serves 2');
    expect(result.content).toContain('Duration: 20 minutes');
    expect(result.content).toContain('1. Blister tomatoes in olive oil.\n2. Toss with penne and pasta water.\n3. Finish with mozzarella.');
    expect(result.content).not.toMatch(/Private captured quotation|Model summary|generated topic|Italian/);
    expect(result.evidence_ids).toEqual(['e1', 'e8', 'e10', 'e11', 'e2', 'e3', 'e4', 'e5', 'e6', 'e7']);
  });

  it('preserves repeated recipe steps because repetition can be meaningful', () => {
    const value = recipe(); value.facts.recipe!.steps!.push(fact('Finish with mozzarella.', 'e7'));
    const result = buildObjectInteractionDraft(value, 'recipe_card', ITEM_ID, NOW)!;
    expect(result.content.match(/Finish with mozzarella\./g)).toHaveLength(2);
  });

  it('creates a travel starter outline in captured order without invented route or day allocation', () => {
    const result = buildObjectInteractionDraft(travel(), 'itinerary', ITEM_ID, NOW)!;
    expect(result.title).toBe('Lisbon itinerary');
    expect(result.content).toContain('Itinerary draft');
    expect(result.content).toContain('Destination: Lisbon');
    expect(result.content).toContain('Duration mentioned: 3 days');
    expect(result.content).toContain('- Miradouro da Graça\n- Alfama\n- Príncipe Real');
    expect(result.content).toContain('- A quiet place to stay in Príncipe Real');
    expect(result.content).toContain('Creator: @ana.wanders');
    expect(result.content).not.toMatch(/Day [123]|9:00|booked|Private captured quotation|Model summary/);
    expect(result.evidence_ids).toEqual(['e1', 'e7', 'e2', 'e3', 'e4', 'e5', 'e6']);
    expect(result.notices.join(' ')).toMatch(/route/i);
    expect(result.notices.join(' ')).toMatch(/opening times/i);
    expect(result.notices.join(' ')).toMatch(/dates/i);
  });

  it('omits unavailable optional facts rather than inventing them', () => {
    const value = intelligence('recipe', { recipe: { ingredients: [fact('tomatoes', 'e1')], steps: [fact('Mix.', 'e2')] } });
    const result = buildObjectInteractionDraft(value, 'recipe_card', ITEM_ID, NOW)!;
    expect(result.title).toBe('Recipe card');
    expect(result.content).toContain('- tomatoes');
    expect(result.content).not.toMatch(/Creator:|Servings:|Duration:|Cuisine:/);
    expect(result.evidence_ids).toEqual(['e1', 'e2']);
  });

  it('uses a bounded generic title without losing a long or multiline source name from the content', () => {
    const value = recipe(); const longName = 'A'.repeat(180) + '\nwith tomatoes'; value.facts.recipe!.name = fact(longName, 'e1');
    const result = buildObjectInteractionDraft(value, 'recipe_card', ITEM_ID, NOW)!;
    expect(result.title).toBe('Recipe card');
    expect(result.content).toContain(longName);
    expect(result.title.length).toBeLessThanOrEqual(160);
  });

  it('is deterministic with an explicit timestamp and never mutates the intelligence envelope', () => {
    const value = deepFreeze(recipe());
    const first = buildObjectInteractionDraft(value, 'recipe_card', ITEM_ID, NOW)!;
    expect(buildObjectInteractionDraft(value, 'recipe_card', ITEM_ID, NOW)).toEqual(first);
    first.evidence_ids.push('changed'); first.notices.push('changed');
    expect(buildObjectInteractionDraft(value, 'recipe_card', ITEM_ID, NOW)!.evidence_ids).not.toContain('changed');
    expect(value.facts.recipe!.ingredients).toHaveLength(4);
  });

  it('uses a valid current ISO timestamp when none is provided', () => {
    const before = Date.now(); const result = buildObjectInteractionDraft(recipe(), 'shopping_list', ITEM_ID)!;
    expect(Date.parse(result.created_at)).toBeGreaterThanOrEqual(before);
    expect(Date.parse(result.created_at)).toBeLessThanOrEqual(Date.now());
  });

  it.each(['not-a-date', '2026-02-30T00:00:00Z', '2026-10-10', '2026-10-10T12:00:00'])('rejects invalid or ambiguous creation time %s', date => {
    expect(buildObjectInteractionDraft(recipe(), 'shopping_list', ITEM_ID, date)).toBeUndefined();
  });

  it('requires the allowlisted draft action to be source-ready with no prerequisites', () => {
    for (const altered of [[], [{ id: 'shopping_list', effect: 'draft', status: 'needs_more_content', prerequisites: [], requires_confirmation: false }],
      [{ id: 'shopping_list', effect: 'external_write', status: 'source_ready', prerequisites: [], requires_confirmation: true }],
      [{ id: 'shopping_list', effect: 'draft', status: 'source_ready', prerequisites: ['servings'], requires_confirmation: false }]]) {
      const value = recipe(); value.capabilities = altered as ObjectIntelligence['capabilities'];
      expect(buildObjectInteractionDraft(value, 'shopping_list', ITEM_ID, NOW)).toBeUndefined();
    }
    expect(buildObjectInteractionDraft(recipe(), 'grocery_order' as ObjectDraftAction, ITEM_ID, NOW)).toBeUndefined();
    expect(buildObjectInteractionDraft(travel(), 'recipe_card', ITEM_ID, NOW)).toBeUndefined();
  });

  it('rechecks actual prerequisites even if the envelope claims a capability is ready', () => {
    const value = recipe(); value.facts.recipe!.ingredients = [];
    expect(buildObjectInteractionDraft(value, 'shopping_list', ITEM_ID, NOW)).toBeUndefined();
    const noSteps = recipe(); delete noSteps.facts.recipe!.steps;
    expect(buildObjectInteractionDraft(noSteps, 'recipe_card', ITEM_ID, NOW)).toBeUndefined();
    const noDestination = travel(); delete noDestination.facts.travel!.destination;
    expect(buildObjectInteractionDraft(noDestination, 'itinerary', ITEM_ID, NOW)).toBeUndefined();
    const noPlaces = travel(); noPlaces.facts.travel!.places = [];
    expect(buildObjectInteractionDraft(noPlaces, 'itinerary', ITEM_ID, NOW)).toBeUndefined();
  });

  it('rejects invalid envelope version and binding rather than producing untraceable drafts', () => {
    const wrongVersion = recipe(); wrongVersion.version = 2 as 1;
    expect(buildObjectInteractionDraft(wrongVersion, 'shopping_list', ITEM_ID, NOW)).toBeUndefined();
    const wrongExtraction = recipe(); wrongExtraction.extraction_version = 'unknown' as typeof OBJECT_INTELLIGENCE_VERSION;
    expect(buildObjectInteractionDraft(wrongExtraction, 'shopping_list', ITEM_ID, NOW)).toBeUndefined();
    const wrongHash = recipe(); wrongHash.source_fingerprint = '';
    expect(buildObjectInteractionDraft(wrongHash, 'shopping_list', ITEM_ID, NOW)).toBeUndefined();
    expect(buildObjectInteractionDraft(recipe(), 'shopping_list', '', NOW)).toBeUndefined();
  });

  it('fails on missing evidence or empty used facts and never includes unused evidence', () => {
    const missing = recipe(); missing.evidence = missing.evidence.filter(entry => entry.id !== 'e2');
    expect(buildObjectInteractionDraft(missing, 'shopping_list', ITEM_ID, NOW)).toBeUndefined();
    const empty = recipe(); empty.facts.recipe!.ingredients![0] = fact('', 'e2');
    expect(buildObjectInteractionDraft(empty, 'shopping_list', ITEM_ID, NOW)).toBeUndefined();
    const noReferences = recipe(); noReferences.facts.recipe!.ingredients![0].evidence_ids = [];
    expect(buildObjectInteractionDraft(noReferences, 'shopping_list', ITEM_ID, NOW)).toBeUndefined();
  });

  it('rejects oversized output instead of silently dropping captured facts', () => {
    const value = recipe(); value.facts.recipe!.ingredients = Array.from({ length: 24 }, (_, n) => fact(`${n} ${'苹'.repeat(390)}`, 'e2'));
    expect(buildObjectInteractionDraft(value, 'shopping_list', ITEM_ID, NOW)).toBeUndefined();
  });
});
