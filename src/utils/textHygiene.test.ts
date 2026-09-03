import { describe, expect, it } from 'vitest';
import { cleanMetaText, cleanOptionalMetaText, decodeHtmlEntities } from './textHygiene';

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
