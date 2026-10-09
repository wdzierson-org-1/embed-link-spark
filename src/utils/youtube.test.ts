import { getYouTubeVideoId } from './youtube';

describe('getYouTubeVideoId', () => {
  it('reads a complete id from every YouTube address shape', () => {
    expect(getYouTubeVideoId('https://www.youtube.com/watch?v=jNQXAC9IVRw')).toBe('jNQXAC9IVRw');
    expect(getYouTubeVideoId('https://www.youtube.com/watch?v=s4skNgV8nJM&si=abc')).toBe('s4skNgV8nJM');
    expect(getYouTubeVideoId('https://youtu.be/s4skNgV8nJM?si=xxjN4RE2XBNvfMlb')).toBe('s4skNgV8nJM');
    expect(getYouTubeVideoId('https://www.youtube.com/shorts/dQw4w9WgXcQ')).toBe('dQw4w9WgXcQ');
    expect(getYouTubeVideoId('https://www.youtube.com/embed/dQw4w9WgXcQ')).toBe('dQw4w9WgXcQ');
    expect(getYouTubeVideoId('https://m.youtube.com/live/dQw4w9WgXcQ')).toBe('dQw4w9WgXcQ');
  });

  it('answers null while the id is still being typed, so nothing is fetched for a partial id', () => {
    for (const partial of ['j', 'jNQ', 'jNQXAC9', 'jNQXAC9IVR']) {
      expect(getYouTubeVideoId(`https://www.youtube.com/watch?v=${partial}`), partial).toBeNull();
      expect(getYouTubeVideoId(`https://youtu.be/${partial}`), partial).toBeNull();
    }
    expect(getYouTubeVideoId('https://www.youtube.com/watch?v=jNQXAC9IVRwEXTRA')).toBeNull();
  });

  it('ignores other sites and non-addresses', () => {
    expect(getYouTubeVideoId('https://vimeo.com/12345678901')).toBeNull();
    expect(getYouTubeVideoId('not a url')).toBeNull();
    expect(getYouTubeVideoId('https://www.youtube.com/')).toBeNull();
  });
});
