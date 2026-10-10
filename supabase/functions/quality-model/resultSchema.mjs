// Provider-enforced structure only. The worker still checks every sampled item,
// public source URL, and exact quote against its immutable evidence snapshot.
// OpenAI Structured Outputs: root object; every object closed; every listed
// property required. Nested anyOf avoids nullable item IDs that our API rejects.
// https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=chat
const text = (max, description) => ({ type: 'string', pattern: `^[\\s\\S]{1,${max}}$`, description });
const object = properties => ({ type: 'object', properties, required: Object.keys(properties), additionalProperties: false });
const array = (items, maxItems, minItems = 0) => ({ type: 'array', items, minItems, maxItems });
const categories = ['identity', 'summary_grounding', 'image_association', 'source_completeness', 'freshness', 'retrieval', 'operations'];

export function qualityResultFormat() {
  const sourceUrl = text(2000, 'Exact public HTTPS URL of the sampled item. Never invent, normalize, or change a source URL.');
  const citation = object({
    url: sourceUrl,
    quote: text(1000, 'One short contiguous VERBATIM excerpt from the cited snapshot page_body or retrieved live observation.text; preserve punctuation and Markdown. No paraphrases. If no quote supports a claim, omit that finding and explain the uncertainty.'),
    source: { type: 'string', enum: ['snapshot', 'live'], description: 'snapshot for saved page_body; live only for the matching retrieved observation.text.' },
  });
  const common = {
    severity: { type: 'string', enum: ['info', 'warning', 'error'] },
    claim: text(1500, 'Specific supported defect; distinguish evidence from interpretation.'),
    evidence: array(citation, 5, 1),
    recommendation: text(1500, 'Proposed reviewable correction; do not claim a change was applied.'),
  };
  const itemFinding = object({
    item_id: { type: 'string', pattern: '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$', description: 'Exact UUID of the sampled item discussed in this finding.' },
    category: { type: 'string', enum: categories },
    ...common,
  });
  // System-wide operations do not have an item URL to cite. The existing result
  // validator accepts an omitted item_id only in this category, never null.
  const operationFinding = object({
    category: { type: 'string', enum: ['operations'] },
    ...common,
    evidence: array(citation, 0),
  });
  const schema = object({
    schema_version: { type: 'integer', enum: [1] },
    summary: text(6000, 'Brief supported audit result. Empty findings and proposals are valid when evidence is insufficient.'),
    findings: array({ anyOf: [itemFinding, operationFinding] }, 20),
    proposals: array(object({
      title: text(200, 'Short proposed improvement.'),
      rationale: text(2000, 'A concrete sampled regression case, proposed strategy, expected effect, acceptance check, and limitations. Label untested ideas as hypotheses.'),
      evidence_urls: array(sourceUrl, 5, 1),
    }), 5),
    uncertainties: array(text(1000, 'Specific evidence limitation or unresolved question.'), 20),
  });
  return { type: 'json_schema', json_schema: { name: 'stash_quality_result_v1', strict: true, schema } };
}
