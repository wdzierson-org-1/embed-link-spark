import { render } from '@testing-library/react';
import LibraryLayout from './LibraryLayout';

/**
 * The masonry counts the grid's columns from the computed track list. In Chrome that list
 * includes implicit tracks that stale card placements create, which is how docking Ask (3
 * columns → 2) left every third card in a phantom third column. This emulates Chrome's
 * counting: explicit tracks plus any implicit ones the cards' inline placements imply.
 */
let explicitColumns = 3;

beforeEach(() => {
  const original = window.getComputedStyle.bind(window);
  vi.spyOn(window, 'getComputedStyle').mockImplementation((element, pseudo) => {
    const el = element as HTMLElement;
    if (el.style?.gridAutoRows !== '1px') return original(el, pseudo as string | undefined);
    const implied = Math.max(0, ...Array.from(el.children).map((card) => Number.parseInt((card as HTMLElement).style.gridColumn) || 0));
    const tracks = Math.max(explicitColumns, implied);
    return { gridTemplateColumns: Array(tracks).fill('100px').join(' ') } as CSSStyleDeclaration;
  });
});
afterEach(() => vi.restoreAllMocks());

const cards = Array.from({ length: 6 }, (_, i) => <div key={`card-${i}`}>Card {i}</div>);
const columnsOf = (container: HTMLElement) => Array.from(container.querySelector('[style*="grid-auto-rows"]')!.children).map((card) => (card as HTMLElement).style.gridColumn);

it('places cards left to right across the explicit columns', () => {
  const { container } = render(<LibraryLayout>{cards}</LibraryLayout>);
  expect(columnsOf(container)).toEqual(['1', '2', '3', '1', '2', '3']);
});

it('re-places into the real columns when the grid loses one, not into the phantom column stale placements imply', () => {
  const { container, rerender } = render(<LibraryLayout>{cards}</LibraryLayout>);
  expect(columnsOf(container)).toEqual(['1', '2', '3', '1', '2', '3']);
  explicitColumns = 2; // Ask docks: `compact` drops lg:grid-cols-3
  rerender(<LibraryLayout compact>{cards}</LibraryLayout>);
  expect(columnsOf(container)).toEqual(['1', '2', '1', '2', '1', '2']);
  explicitColumns = 3;
  rerender(<LibraryLayout>{cards}</LibraryLayout>);
  expect(columnsOf(container)).toEqual(['1', '2', '3', '1', '2', '3']);
});
