import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { TooltipProvider } from '@/components/ui/tooltip';
import EditItemLinkSection, { normalizeWebAddress } from './EditItemLinkSection';

const URL_A = 'https://www.sollishealth.com/locations#northern-california';
const writeText = vi.fn().mockResolvedValue(undefined);

beforeEach(() => {
  // Timers advance with the clock, so Testing Library's polling still works
  vi.useFakeTimers({ shouldAdvanceTime: true });
  Object.assign(navigator, { clipboard: { writeText } });
  writeText.mockClear();
});
afterEach(() => vi.useRealTimers());

const renderStrip = (onUrlSave?: (url: string) => Promise<void>) =>
  render(
    <TooltipProvider>
      <EditItemLinkSection url={URL_A} onUrlSave={onUrlSave} />
    </TooltipProvider>,
  );

describe('normalizeWebAddress', () => {
  it('accepts web addresses, supplying https:// when it is missing', () => {
    expect(normalizeWebAddress('  example.com/path?q=1 ')).toBe('https://example.com/path?q=1');
    expect(normalizeWebAddress('http://example.com')).toBe('http://example.com/');
  });

  it('refuses what is not a web address', () => {
    for (const raw of ['', 'not a url', 'mailto:a@b.com', 'javascript:alert(1)', 'localhost', 'ftp://x.y']) {
      expect(normalizeWebAddress(raw), raw).toBeNull();
    }
  });
});

it('shows the whole address as a link, with copy and open', () => {
  renderStrip();
  const links = screen.getAllByRole('link');
  expect(links[0]).toHaveAttribute('href', URL_A);
  expect(links[0]).toHaveTextContent(URL_A);
  expect(screen.getByRole('link', { name: 'Open link' })).toHaveAttribute('href', URL_A);
  expect(screen.getByRole('button', { name: 'Copy address' })).toBeInTheDocument();
  expect(screen.queryByRole('button', { name: 'Edit address' })).not.toBeInTheDocument();
});

it('copies the address and says so for two seconds', async () => {
  renderStrip();
  fireEvent.click(screen.getByRole('button', { name: 'Copy address' }));
  await waitFor(() => expect(screen.getByRole('button', { name: 'Copied' })).toBeInTheDocument());
  expect(writeText).toHaveBeenCalledWith(URL_A);
  act(() => {
    vi.advanceTimersByTime(2100);
  });
  expect(screen.getByRole('button', { name: 'Copy address' })).toBeInTheDocument();
});

it('edits: the button turns into save, Enter saves the normalized address, and the button turns back', async () => {
  const onUrlSave = vi.fn().mockResolvedValue(undefined);
  renderStrip(onUrlSave);
  fireEvent.click(screen.getByRole('button', { name: 'Edit address' }));
  const input = screen.getByRole('textbox', { name: 'Source address' });
  expect(input).toHaveValue(URL_A);
  const saveButton = screen.getByRole('button', { name: 'Save address' });
  expect(saveButton.className).toContain('bg-spot');
  expect(screen.queryByRole('button', { name: 'Copy address' })).not.toBeInTheDocument();

  fireEvent.change(input, { target: { value: 'sollishealth.com/locations' } });
  fireEvent.keyDown(input, { key: 'Enter' });
  await waitFor(() => expect(onUrlSave).toHaveBeenCalledWith('https://sollishealth.com/locations'));
  await waitFor(() => expect(screen.getByRole('button', { name: 'Edit address' })).toBeInTheDocument());
  expect(screen.queryByRole('textbox')).not.toBeInTheDocument();
});

it('refuses a non-address with a machine line and saves nothing', async () => {
  const onUrlSave = vi.fn().mockResolvedValue(undefined);
  renderStrip(onUrlSave);
  fireEvent.click(screen.getByRole('button', { name: 'Edit address' }));
  const input = screen.getByRole('textbox', { name: 'Source address' });
  fireEvent.change(input, { target: { value: 'not an address' } });
  fireEvent.click(screen.getByRole('button', { name: 'Save address' }));
  expect(await screen.findByRole('alert')).toHaveTextContent("that doesn't look like a web address");
  expect(onUrlSave).not.toHaveBeenCalled();
  expect(input).toHaveAttribute('aria-invalid', 'true');
});

it('Escape cancels an edit and keeps the old address', () => {
  const onUrlSave = vi.fn();
  renderStrip(onUrlSave);
  fireEvent.click(screen.getByRole('button', { name: 'Edit address' }));
  const input = screen.getByRole('textbox', { name: 'Source address' });
  fireEvent.change(input, { target: { value: 'https://elsewhere.com' } });
  fireEvent.keyDown(input, { key: 'Escape' });
  expect(screen.queryByRole('textbox')).not.toBeInTheDocument();
  expect(screen.getAllByRole('link')[0]).toHaveAttribute('href', URL_A);
  expect(onUrlSave).not.toHaveBeenCalled();
});

it('shows a cancel cell only while editing; it leaves edit mode and keeps the old address', () => {
  const onUrlSave = vi.fn();
  renderStrip(onUrlSave);
  expect(screen.queryByRole('button', { name: 'Cancel editing' })).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole('button', { name: 'Edit address' }));
  fireEvent.change(screen.getByRole('textbox', { name: 'Source address' }), { target: { value: 'https://elsewhere.com' } });
  fireEvent.click(screen.getByRole('button', { name: 'Cancel editing' }));
  expect(screen.queryByRole('textbox')).not.toBeInTheDocument();
  expect(screen.queryByRole('button', { name: 'Cancel editing' })).not.toBeInTheDocument();
  expect(screen.getAllByRole('link')[0]).toHaveAttribute('href', URL_A);
  expect(onUrlSave).not.toHaveBeenCalled();
});

it('reports a failed save and stays in edit', async () => {
  const onUrlSave = vi.fn().mockRejectedValue(new Error('offline'));
  renderStrip(onUrlSave);
  fireEvent.click(screen.getByRole('button', { name: 'Edit address' }));
  fireEvent.change(screen.getByRole('textbox', { name: 'Source address' }), { target: { value: 'https://elsewhere.com' } });
  fireEvent.click(screen.getByRole('button', { name: 'Save address' }));
  expect(await screen.findByRole('alert')).toHaveTextContent("couldn't save the address");
  expect(screen.getByRole('textbox', { name: 'Source address' })).toBeInTheDocument();
});
