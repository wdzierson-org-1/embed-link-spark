import React, { useEffect, useState } from 'react';
import ContentItem from '@/components/ContentItem';
import type { AssemblyPiece } from '@/utils/itemAssembly';

/**
 * Dev-only (/design/cards): the DESIGN-v2 enrichment moment on the real card, looping, so it
 * can be reviewed without saving anything. A link arrives with nothing but its address; the
 * card reads it (the placeholder glyph boils, `| gathering more info…`), the title decrypts in,
 * the description prints, the picture lands and resolves from coarse blocks to the reading
 * lens, then sharpens as the machine line says `✓ filled in`, and settles.
 * The same sequence is the reference for the iOS card.
 */
// The picture lands while Stash is still reading, so the lens has a few seconds on screen
const STEPS = [
  { at: 0, stage: 'arrived' },
  { at: 2600, stage: 'titled' },
  { at: 3600, stage: 'described' },
  { at: 4600, stage: 'pictured' },
  { at: 8200, stage: 'complete' },
] as const;
const LOOP_MS = 11500;

type Stage = (typeof STEPS)[number]['stage'];

const noop = () => {};
const emptySet = new Set<string>();

const itemFor = (stage: Stage, createdAt: string) => {
  const titled = stage !== 'arrived';
  const described = stage === 'described' || stage === 'pictured' || stage === 'complete';
  const pictured = stage === 'pictured' || stage === 'complete';
  return {
    id: 'demo-arriving',
    type: 'link' as const,
    url: 'https://medium.com/@garrethow/how-to-remember-more-of-what-you-read',
    title: titled ? 'How to remember more of what you read' : undefined,
    description: described ? 'Reading once is not remembering. A short case for retrieval practice, with three ways to try it this week.' : undefined,
    file_path: pictured ? 'https://picsum.photos/seed/stash-book/800/450' : undefined,
    created_at: createdAt,
    attributes: {
      link: { flavor: 'article' as const, read_time_min: titled ? 2 : undefined },
      enrichment: { status: stage === 'complete' ? ('complete' as const) : ('pending' as const), updated_at: createdAt },
    },
  };
};

export const ArrivingSaveDemo = ({ paused = false }: { paused?: boolean }) => {
  const [cycle, setCycle] = useState(0);
  const [stage, setStage] = useState<Stage>('arrived');
  const [reveals, setReveals] = useState<Partial<Record<AssemblyPiece, number>>>({});
  const [createdAt, setCreatedAt] = useState(() => new Date().toISOString());

  useEffect(() => {
    if (paused) return;
    setStage('arrived');
    setReveals({});
    setCreatedAt(new Date().toISOString());
    const timers = STEPS.slice(1).map(({ at, stage: next }) =>
      setTimeout(() => {
        setStage(next);
        const now = Date.now();
        if (next === 'titled') setReveals((r) => ({ ...r, title: now }));
        if (next === 'described') setReveals((r) => ({ ...r, description: now }));
        if (next === 'pictured') setReveals((r) => ({ ...r, preview: now }));
      }, at),
    );
    const loop = setTimeout(() => setCycle((c) => c + 1), LOOP_MS);
    return () => {
      timers.forEach(clearTimeout);
      clearTimeout(loop);
    };
  }, [cycle, paused]);

  return (
    <div className="w-full max-w-[420px]">
      {/* Keyed per cycle so the card's arrival (print-in, spot ring) plays each loop */}
      <ContentItem
        key={cycle}
        item={itemFor(stage, createdAt)}
        tags={[]}
        imageErrors={emptySet}
        expandedContent={emptySet}
        onImageError={noop}
        onToggleExpansion={noop}
        onDeleteItem={noop}
        onEditItem={noop}
        onTagsUpdated={noop}
        assemblyReveals={reveals}
      />
      <p className="mt-3 font-pixel text-pixel text-muted-foreground">stage: {stage} · loops every {LOOP_MS / 1000} s</p>
    </div>
  );
};

export default ArrivingSaveDemo;
