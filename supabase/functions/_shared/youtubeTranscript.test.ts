import { describe, expect, it } from 'vitest';
import { parseYouTubeMarkdown } from './youtubeTranscript';

const ZOO = `# Me at the zoo

![thumbnail](https://i.ytimg.com/vi/jNQXAC9IVRw/hqdefault.jpg)

**Uploaded by**: [jawed](https://www.youtube.com/@jawed)
**Upload date**: 2005-04-23
**Length**: 0:19
**Views**: 350,000,000

## Description

\`\`\`
The first video on YouTube. Maybe it's time to go back to the zoo?

The name of the music playing in the background is Darude - Sandstorm.
\`\`\`

## Transcript

[00:00] All right, so here we are in front of the elephants.
[00:04] The cool thing about these guys is that they have really, really, really long trunks.
[00:12] And that's cool.
[00:17] And that's pretty much all there is to say.
`;

describe('parseYouTubeMarkdown', () => {
  it('reads the transcript (timestamps dropped), the description’s first paragraph, the length and the uploader', () => {
    const parsed = parseYouTubeMarkdown(ZOO);
    expect(parsed.transcript).toBe(
      'All right, so here we are in front of the elephants.\nThe cool thing about these guys is that they have really, really, really long trunks.\nAnd that\'s cool.\nAnd that\'s pretty much all there is to say.',
    );
    expect(parsed.description).toBe("The first video on YouTube. Maybe it's time to go back to the zoo?");
    expect(parsed.durationS).toBe(19);
    expect(parsed.author).toBe('jawed');
  });

  it('tolerates an unfenced description, HH:MM:SS lengths, a missing uploader and cue-style transcripts', () => {
    const parsed = parseYouTubeMarkdown(`## Description\nA talk about things.\n\nSecond paragraph.\n\n**Length**: 1:02:03\n\n## Transcript\n1\n00:00:01 --> 00:00:04\nHello there\n2\n00:00:04 --> 00:00:09\nGeneral Kenobi\n`);
    expect(parsed.transcript).toBe('Hello there\nGeneral Kenobi');
    expect(parsed.description).toBe('A talk about things.');
    expect(parsed.durationS).toBe(3723);
    expect(parsed.author).toBeNull();
  });

  it('answers null when there is no transcript section, or the section says there is none', () => {
    expect(parseYouTubeMarkdown('# A Short\n\n## Description\n\nNo captions here.').transcript).toBeNull();
    expect(parseYouTubeMarkdown('## Transcript\n\nTranscript unavailable').transcript).toBeNull();
    expect(parseYouTubeMarkdown('').transcript).toBeNull();
    expect(parseYouTubeMarkdown(null)).toEqual({ transcript: null, description: null, durationS: null, author: null });
  });

  it('stops the transcript at the next heading and caps very long ones', () => {
    const parsed = parseYouTubeMarkdown(`## Transcript\nline one\nline two\n\n## Comments\nnot a caption`);
    expect(parsed.transcript).toBe('line one\nline two');
    const long = parseYouTubeMarkdown(`## Transcript\n${'word '.repeat(60_000)}`);
    expect(long.transcript!.length).toBeLessThanOrEqual(200_000);
  });
});
