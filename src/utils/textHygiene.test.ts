import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import {
  cleanMetaText,
  cleanMetaTitle,
  cleanOptionalMetaText,
  cleanOptionalMetaTitle,
  decodeHtmlEntities,
} from './textHygiene';

describe('decodeHtmlEntities', () => {
  it('decodes the common named entities', () => {
    expect(decodeHtmlEntities('AI, Money &amp; Career: &quot;These 5&quot;')).toBe('AI, Money & Career: "These 5"');
    expect(decodeHtmlEntities('a &lt;b&gt; c&nbsp;d &apos;e&apos;')).toBe('a <b> c d \'e\'');
    expect(decodedTypography()).toBe('“quoted” – dash — em … ellipsis ’');
  });

  it('decodes decimal and hex numeric entities', () => {
    expect(decodeHtmlEntities('I&#x2019;ll DM you &#064;market')).toBe('I’ll DM you @market');
    expect(decodeHtmlEntities('It&#039;s 8&#8243; long')).toBe('It\'s 8″ long');
    expect(decodeHtmlEntities('&#X1F600;')).toBe('😀');
  });

  it('unwraps double-encoded entities the way LinkedIn and Instagram ship them', () => {
    expect(decodeHtmlEntities('I&amp;#39;ve (finally) stopped')).toBe("I've (finally) stopped");
    expect(decodeHtmlEntities('&amp;quot;These 5 things&amp;quot;')).toBe('"These 5 things"');
    expect(decodeHtmlEntities('&amp;amp;amp;')).toBe('&');
  });

  it('leaves unknown or malformed references alone', () => {
    expect(decodeHtmlEntities('AT&T and R&D; &unknownthing; &#99999999;')).toBe('AT&T and R&D; &unknownthing; &#99999999;');
    expect(decodeHtmlEntities('')).toBe('');
  });
});

const decodedTypography = () =>
  decodeHtmlEntities('&ldquo;quoted&rdquo; &ndash; dash &mdash; em &hellip; ellipsis &rsquo;');

describe('cleanMetaText', () => {
  it('decodes entities, strips markdown emphasis, and collapses whitespace', () => {
    expect(
      cleanMetaText('619 likes - davecto: &quot;These 5 things. **1. Terms that cover you.** UGC.  That&#x2019;s it.&quot;')
    ).toBe('619 likes - davecto: "These 5 things. 1. Terms that cover you. UGC. That’s it."');
    expect(cleanMetaText('  __under__ and *star* and `code`  \n next')).toBe('under and star and code next');
  });

  it('keeps ordinary asterisks and underscores that are not emphasis', () => {
    expect(cleanMetaText('5 * 3 = 15, snake_case_name, footnote*')).toBe('5 * 3 = 15, snake_case_name, footnote*');
  });

  it('cleanOptionalMetaText passes through missing values and empties', () => {
    expect(cleanOptionalMetaText(undefined)).toBeUndefined();
    expect(cleanOptionalMetaText(null)).toBeUndefined();
    expect(cleanOptionalMetaText('   ')).toBeUndefined();
    expect(cleanOptionalMetaText(' Plain &amp; simple ')).toBe('Plain & simple');
  });
});

describe('cleanMetaTitle', () => {
  it('replaces a hashtags-only LinkedIn lead with the first sentence of the post and drops the comment count', () => {
    expect(
      cleanMetaTitle(
        '#aiagents #documentautomation #opensource | André Lindenberg | 13 comments',
        'OfficeCLI gives an AI agent a single binary for Office files. You address it from any agent.'
      )
    ).toBe('OfficeCLI gives an AI agent a single binary for Office files | André Lindenberg');
  });

  it('keeps the author when the lead is only hashtags and there is no description', () => {
    expect(cleanMetaTitle('#aiagents #agentmemory | André Lindenberg')).toBe('André Lindenberg');
    expect(cleanMetaTitle('#aiagents #agentmemory | André Lindenberg', null)).toBe('André Lindenberg');
  });

  it('caps a long derived lead at a word boundary', () => {
    const description = `${'word '.repeat(30)}end. Second sentence.`;
    const out = cleanMetaTitle('#ai | Author', description);
    expect(out.startsWith('word word')).toBe(true);
    expect(out.endsWith('… | Author')).toBe(true);
    expect(out.split(' | ')[0].length).toBeLessThanOrEqual(91);
  });

  it('removes trailing hashtag runs, inside a closing quote too', () => {
    expect(cleanMetaTitle('3 lectures to learn Agentic AI. Link in bio. #maven #ai #llms ')).toBe(
      '3 lectures to learn Agentic AI. Link in bio.'
    );
    expect(
      cleanMetaTitle('Eli Jorgensen on Instagram: "A little tour of my first cyberdeck :) #cyberdeck #elijorgensen"')
    ).toBe('Eli Jorgensen on Instagram: "A little tour of my first cyberdeck :)"');
    expect(cleanMetaTitle('Will Dzierson on LinkedIn: #ai #ml #startups')).toBe('Will Dzierson on LinkedIn');
    expect(
      cleanMetaTitle('Transform your sweater with a silk scarf fold. Which is your favorite? #stylehacks #fashiontips | Open Sky Riders')
    ).toBe('Transform your sweater with a silk scarf fold. Which is your favorite? | Open Sky Riders');
  });

  it('removes a tag block wherever it sits and tightens the closing quote', () => {
    expect(
      cleanMetaTitle('Comparee AI on Instagram: "Full guide: comparee.ai/projects #compareeAI #DIY #Upcycling"')
    ).toBe('Comparee AI on Instagram: "Full guide: comparee.ai/projects"');
    expect(cleanMetaTitle('Wine Glass Lamps at home. #hostinghack #diy #tablescape @amazonhome @wayfair')).toBe(
      'Wine Glass Lamps at home. @amazonhome @wayfair'
    );
  });

  it('does not end the derived lead at an initial, and refuses a bare URL as a lead', () => {
    expect(
      cleanMetaTitle(
        '#aiagents #agentmemory | André Lindenberg',
        'Fabio A. recommended agentmemory, ran it in production a week. Then built ai-memory.'
      )
    ).toBe('Fabio A. recommended agentmemory, ran it in production a week | André Lindenberg');
    expect(cleanOptionalMetaTitle('#scarfstyling', 'https://www.tiktok.com/tag/scarfstyling?lang=en')).toBeUndefined();
  });

  it('de-hashes an inline or single opening tag so the word survives', () => {
    expect(cleanMetaTitle('A disturbing new study from #Stanford examines the psychological impact of AI chatbots.')).toBe(
      'A disturbing new study from Stanford examines the psychological impact of AI chatbots.'
    );
    expect(cleanMetaTitle('#AI is changing work')).toBe('AI is changing work');
  });

  it('drops a multi-tag opener but keeps the sentence after it', () => {
    expect(cleanMetaTitle('#hiring #jobs We are looking for a designer')).toBe('We are looking for a designer');
  });

  it('leaves non-hashtag uses of # alone', () => {
    expect(cleanMetaTitle('Issue #42: C# and F# compared')).toBe('Issue #42: C# and F# compared');
    expect(cleanMetaTitle('Room #7 | Hotel Review')).toBe('Room #7 | Hotel Review');
  });

  it('strips a comments tail on its own and keeps everything else', () => {
    expect(cleanMetaTitle('Scoop: Sword Health to acquire Headspace | Dana Allison | 13 comments')).toBe(
      'Scoop: Sword Health to acquire Headspace | Dana Allison'
    );
    expect(cleanMetaTitle('Plain article title | The Verge')).toBe('Plain article title | The Verge');
  });

  it('still decodes entities and emphasis like cleanMetaText', () => {
    expect(cleanMetaTitle('**Big** news &amp; more #tag')).toBe('Big news & more');
  });

  it('cleanOptionalMetaTitle returns undefined when nothing readable is left', () => {
    expect(cleanOptionalMetaTitle('#scarfstyling')).toBeUndefined();
    expect(cleanOptionalMetaTitle(null)).toBeUndefined();
    expect(cleanOptionalMetaTitle(undefined)).toBeUndefined();
    expect(cleanOptionalMetaTitle('#scarfstyling', 'Silk scarf folds for sweaters. More inside.')).toBe(
      'Silk scarf folds for sweaters'
    );
  });
});

describe('paired Deno copy', () => {
  it('supabase/functions/_shared/textHygiene.ts carries the same helpers byte for byte', () => {
    const read = (relative: string) => readFileSync(new URL(relative, import.meta.url), 'utf8');
    const helpers = (source: string) => source.slice(source.indexOf('const NAMED_ENTITIES'));
    expect(helpers(read('../../supabase/functions/_shared/textHygiene.ts'))).toBe(helpers(read('./textHygiene.ts')));
  });
});
