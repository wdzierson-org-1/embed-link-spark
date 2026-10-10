import {
  OBJECT_INTELLIGENCE_VERSION,
  type EvidenceValue,
  type ObjectIntelligence,
} from './objectIntelligence.ts';

export type ObjectDraftAction = 'shopping_list' | 'recipe_card' | 'itinerary';
export interface ObjectInteractionDraft {
  version: 1;
  action: ObjectDraftAction;
  title: string;
  content: string;
  source_item_id: string;
  source_fingerprint: string;
  created_at: string;
  evidence_ids: string[];
  notices: string[];
}

const ACTIONS: readonly ObjectDraftAction[] = ['shopping_list', 'recipe_card', 'itinerary'];
const MAX_CONTENT_BYTES = 24_000;
const invalidControls = /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/;
const evidenceId = /^e[1-9][0-9]{0,2}$/;

function validTimestamp(value: string): boolean {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(value)) return false;
  const date = new Date(value);
  return Number.isFinite(date.getTime()) && date.toISOString() === (value.includes('.') ? value : value.replace('Z', '.000Z'));
}

/** A generic title preserves a long/multiline source name in the body without truncation. */
function draftTitle(name: string | undefined, suffix: string, fallback: string): string {
  const title = name ? `${name} ${suffix}` : fallback;
  return title.length <= 160 && !/[\r\n\t]/.test(title) ? title : fallback;
}

/**
 * Build an editable draft solely from already-validated, current-source facts.
 * The caller owns source binding and authorization. No network, model, scaling,
 * route inference, or external action runs here; all used values stay verbatim.
 */
export function buildObjectInteractionDraft(
  intelligence: ObjectIntelligence,
  action: ObjectDraftAction,
  sourceItemId: string,
  createdAt = new Date().toISOString(),
): ObjectInteractionDraft | undefined {
  if (!ACTIONS.includes(action) || !intelligence || intelligence.version !== 1 || intelligence.beta !== true ||
      intelligence.extraction_version !== OBJECT_INTELLIGENCE_VERSION ||
      !/^[a-f0-9]{64}$/.test(intelligence.source_fingerprint) || !validTimestamp(createdAt) ||
      typeof sourceItemId !== 'string' || !sourceItemId.trim() || sourceItemId.length > 128 || /[\s\u0000-\u001f\u007f]/.test(sourceItemId) ||
      !Array.isArray(intelligence.capabilities) || !Array.isArray(intelligence.evidence) || !intelligence.facts) return;
  const matching = intelligence.capabilities.filter(capability => capability?.id === action);
  const capability = matching[0];
  if (matching.length !== 1 || capability.effect !== 'draft' || capability.status !== 'source_ready' ||
      capability.requires_confirmation !== false || !Array.isArray(capability.prerequisites) || capability.prerequisites.length) return;

  const availableEvidence = new Set(intelligence.evidence.map(entry => entry?.id));
  const usedEvidence = new Set<string>();
  let invalid = false;
  const use = (entry: EvidenceValue): string => {
    if (!entry || typeof entry.value !== 'string' || !entry.value.trim() || entry.value.length > 400 || invalidControls.test(entry.value) ||
        !Array.isArray(entry.evidence_ids) || !entry.evidence_ids.length || entry.evidence_ids.length > 4 ||
        new Set(entry.evidence_ids).size !== entry.evidence_ids.length ||
        entry.evidence_ids.some(id => typeof id !== 'string' || !evidenceId.test(id) || !availableEvidence.has(id))) {
      invalid = true; return '';
    }
    entry.evidence_ids.forEach(id => usedEvidence.add(id));
    return entry.value;
  };
  const optional = (entry: EvidenceValue | undefined): string | undefined => entry === undefined ? undefined : use(entry);
  const list = (entries: EvidenceValue[] | undefined, unique: boolean): string[] => {
    if (!Array.isArray(entries) || !entries.length || entries.length > 24) { invalid = true; return []; }
    const seen = new Set<string>();
    const values: string[] = [];
    for (const entry of entries) {
      // Only exact repeated values collapse. Distinct quantities/wording survive;
      // the first occurrence supplies the evidence for the one displayed value.
      if (unique && entry && typeof entry.value === 'string' && seen.has(entry.value)) continue;
      const value = use(entry); seen.add(value); values.push(value);
    }
    return values;
  };
  const blocks: string[] = [];
  let title: string;
  let notices: string[];
  const facts = intelligence.facts;

  if (action === 'shopping_list' || action === 'recipe_card') {
    if (intelligence.interpretation?.kind !== 'recipe' || !facts.recipe?.ingredients?.length ||
        (action === 'recipe_card' && !facts.recipe.steps?.length)) return;
    const recipe = facts.recipe;
    const name = optional(recipe.name);
    const card = action === 'recipe_card';
    title = draftTitle(name, card ? 'recipe card' : 'shopping list', card ? 'Recipe card' : 'Shopping list');
    blocks.push(card ? '# Recipe card' : '# Shopping list');
    const context: string[] = [];
    if (name !== undefined) context.push(`Recipe: ${name}`);
    if (card) {
      const creator = optional(facts.creator), servings = optional(recipe.servings), duration = optional(recipe.duration);
      if (creator !== undefined) context.push(`Creator: ${creator}`);
      if (servings !== undefined) context.push(`Servings: ${servings}`);
      if (duration !== undefined) context.push(`Duration: ${duration}`);
    }
    if (context.length) blocks.push(context.join('\n'));
    const ingredients = list(recipe.ingredients, true);
    blocks.push('## Ingredients', ingredients.map(value => `${card ? '-' : '- [ ]'} ${value}`).join('\n'));
    if (card) blocks.push('## Steps', list(recipe.steps, false).map((value, index) => `${index + 1}. ${value}`).join('\n'));
    notices = ['Quantities are kept as captured; adjust them to your needs before using this draft.'];
  } else {
    if (intelligence.interpretation?.kind !== 'travel' || !facts.travel?.destination || !facts.travel.places?.length) return;
    const travel = facts.travel;
    const destination = use(travel.destination);
    title = draftTitle(destination, 'itinerary', 'Itinerary draft');
    blocks.push('# Itinerary draft');
    const context = [`Destination: ${destination}`];
    const creator = optional(facts.creator), duration = optional(travel.duration);
    if (creator !== undefined) context.push(`Creator: ${creator}`);
    if (duration !== undefined) context.push(`Duration mentioned: ${duration}`);
    blocks.push(context.join('\n'));
    blocks.push('## Places mentioned', list(travel.places, true).map(value => `- ${value}`).join('\n'));
    if (travel.accommodation?.length) blocks.push('## Stays mentioned', list(travel.accommodation, true).map(value => `- ${value}`).join('\n'));
    notices = [
      'This editable outline keeps places in the order captured from the source.',
      'Check the route, opening times, travel dates, availability and travel times when planning.',
    ];
  }
  blocks.push('## Draft notes', notices.map(notice => `- ${notice}`).join('\n'));
  const content = blocks.join('\n\n');
  if (invalid || !usedEvidence.size || usedEvidence.size > 48 || new TextEncoder().encode(content).byteLength > MAX_CONTENT_BYTES) return;
  return { version: 1, action, title, content, source_item_id: sourceItemId,
    source_fingerprint: intelligence.source_fingerprint, created_at: createdAt, evidence_ids: [...usedEvidence], notices };
}
