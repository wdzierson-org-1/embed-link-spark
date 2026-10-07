import { backdropSpheres, stippleSpans } from './PaperBackdrop';

describe('stippleSpans', () => {
  const sphere = { x: 100, y: 100, r: 40 }; // reach 60

  it('covers a row across the sphere’s reach, clipped to the page', () => {
    expect(stippleSpans(100, [sphere], 1000)).toEqual([[40, 160]]);
    expect(stippleSpans(100, [{ x: 10, y: 100, r: 40 }], 1000)).toEqual([[0, 70]]);
  });

  it('skips rows the sphere doesn’t reach', () => {
    expect(stippleSpans(161, [sphere], 1000)).toEqual([]);
  });

  it('merges overlapping reaches so no dot is drawn twice', () => {
    const spans = stippleSpans(100, [sphere, { x: 150, y: 100, r: 40 }], 1000);
    expect(spans).toEqual([[40, 210]]);
  });

  it('frames the page from its corners: the spheres never meet on a desktop or a phone', () => {
    for (const [w, h] of [
      [1440, 900],
      [390, 844],
      [2560, 1440],
    ]) {
      const spheres = backdropSpheres(w, h);
      for (let y = 0; y < h + 160; y += 3) {
        const merged = stippleSpans(y, spheres, w);
        const separate = spheres.flatMap((s) => stippleSpans(y, [s], w));
        expect(merged.length, `${w}x${h} row ${y}`).toBe(separate.length);
      }
    }
  });
});
