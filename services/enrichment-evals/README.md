# Enrichment evaluation release gate

Run from the repository root after installing the root lockfile dependencies:

```sh
npm ci --ignore-scripts --no-audit --no-fund
node node_modules/vitest/vitest.mjs run --config services/enrichment-evals/vitest.config.ts
```

The separate Node test config imports the actual preview-image selector, source-text gate, and typed object-fact extractor. It performs no provider calls, reads no saved Stash items, and needs no credentials. `fetch` is disabled in the test setup. The application-wide test configuration intentionally excludes service directories, so use this command explicitly.

## What blocks a release

Every explicit gold expectation must pass:

- Any image outside the labelled exact artwork set fails, even if it increases the number of filled cards.
- A signup/challenge/footer page accepted as content fails.
- Extra or incorrect factual leaves fail. A price without a currency and a price belonging to another variant must be omitted.
- Missing positive controls also fail, so returning nothing everywhere cannot pass.
- Extractor exceptions and missing source provenance fail.

`fixtures.ts` contains minimized reconstructions of the Peter Millar wrong-campaign/selected-color, Medium byline, LinkedIn signup/profile, and YouTube footer failures, plus synthetic product and place controls. The known Medium article artwork is a public URL; other image paths are labelled synthetic fixtures. No network verification of those paths is required.

**This is a curated regression corpus, not a statistically representative held-out benchmark.** The fixtures are visible to developers and overlap known failures. Their percentages describe these cases only. They cannot establish image visual similarity, overall user accuracy, provider reliability, cost, or content freshness. Later evaluation should add independently reviewed, consent-appropriate samples stratified by source/object type, including unseen cases and manual image review.

## Versioned evidence

`manifest.json` identifies the evaluator, candidate playbook, and corpus versions. Increment the corpus version when labels/input cases change, and the evaluator version when scoring changes. Increment the playbook version for an intended strategy release. The artifact also records a SHA-256 digest of the complete corpus and hashes of the actual shared implementation files; a version label alone is not evidence that the same code was tested.

`artifacts/enrichment-evaluation.json` contains per-case outcomes, rejection reasons, literal extracted results, counts, and precision/coverage for the labelled corpus. It is written before assertions even when the gate fails, capped at 300 KB, and excluded from Git. Empty denominators are `null`, never misleading 100% scores. No generated timestamps are included, making identical code/fixtures produce identical JSON.

`evaluateCases` accepts alternate selector functions, and `compareReports` reports newly failing/improving case IDs. Comparison requires the exact same corpus hash and evaluator version. An improvement never excuses an unrelated new failure.

## CI and deployment

`.github/workflows/enrichment-evals.yml` runs on PRs, `main` pushes, and manual dispatch. It installs locked dependencies, runs the gate, and keeps the JSON artifact for 30 days with read-only repository permissions and no deployment credentials. Action commits were resolved from the official upstream tags when added. The job is named **Enrichment regression gate**.

This job does not deploy anything or auto-edit the playbook. Repository branch protection must require the job to prevent merging a failed PR. Direct backend deployments must explicitly run this gate before publishing; an Actions check alone does not intercept manual Supabase deployments. Promotion still requires review of live evidence, costs, and a rollback plan in addition to this corpus passing.

Workflow reference: [GitHub Node testing documentation](https://docs.github.com/en/actions/tutorials/build-and-test-code/nodejs), [artifact retention and failure uploads](https://github.com/actions/upload-artifact).

Vercel also runs the same regression command before `npm run build`, configured in
`vercel.json`. This blocks a web deployment when a labelled regression fails even
when GitHub Actions cannot start (the organization reported a billing lock during
this release). It does not intercept a manual Supabase deployment. Restore GitHub
Actions billing to receive the separate CI artifact and required-check integration.
