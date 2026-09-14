/** Fixed left-to-right assignment, with each column packed independently. */
export function masonryPlacement(heights: number[], columns: number, gap = 24) {
  const count = Math.max(1, Math.floor(columns));
  const nextRows = Array<number>(count).fill(1);
  return heights.map((height, index) => {
    const column = index % count;
    const start = nextRows[column];
    const span = Math.max(1, Math.ceil(height)) + gap;
    nextRows[column] += span;
    return { column: column + 1, start, span };
  });
}
