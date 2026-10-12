// src/components/auth/HandleStep.test.tsx
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { HandleStep } from './HandleStep';

const db = vi.hoisted(() => ({
  taken: null as null | { id: string },
  profile: null as null | { display_name: string | null },
  readError: null as null | { message: string },
  hold: null as null | Promise<void>,
  reads: [] as string[][],
  update: vi.fn(async () => ({ error: null as null | { code: string; message: string } })),
  updated: null as null | Record<string, unknown>,
}));
vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: () => ({
      // Two kinds of read: the profile's display name (on Continue) and the availability probe (while typing)
      select: (columns: string) => ({
        eq: (column: string, value: string) => ({
          maybeSingle: async () => {
            db.reads.push([columns, column, value]);
            if (columns === 'display_name') return { data: db.profile, error: db.readError };
            const answer = db.taken; // the answer as of asking, however long the probe is held open
            await db.hold;
            return { data: answer, error: null };
          },
        }),
      }),
      update: (row: Record<string, unknown>) => { db.updated = row; return { eq: db.update }; },
    }),
  },
}));
const toast = vi.fn();
vi.mock('@/hooks/use-toast', () => ({ useToast: () => ({ toast }) }));

// The server named this person stash3; the parent suggests willdzierson from their provider name
const setup = (initial = 'willdzierson', email?: string, server = 'stash3') => {
  const onClaimed = vi.fn();
  render(<HandleStep userId="u1" serverUsername={server} initialUsername={initial} email={email} onClaimed={onClaimed} />);
  return { onClaimed, input: screen.getByLabelText('Username') as HTMLInputElement, button: screen.getByRole('button', { name: /continue/i }) };
};

// Fake timers only: let time pass (the probe debounces for 300 ms) and settle what it set off
const elapse = (ms: number) => act(async () => { await vi.advanceTimersByTimeAsync(ms); });

describe('HandleStep', () => {
  beforeEach(() => {
    db.taken = null;
    db.profile = { display_name: 'Will Dzierson' }; // a name the person already has: the claim leaves it be
    db.readError = null;
    db.hold = null;
    db.reads = [];
    db.updated = null;
    db.update.mockResolvedValue({ error: null });
    toast.mockClear();
  });
  afterEach(() => { vi.restoreAllMocks(); vi.useRealTimers(); });

  it('prefills the handle and shows the address it makes', () => {
    const { input } = setup();
    expect(input.value).toBe('willdzierson');
    expect(screen.getByText('gostash.it/feed/willdzierson')).toBeInTheDocument();
  });

  it('sanitizes pasted text and refuses a short handle', async () => {
    const { input, button } = setup();
    fireEvent.change(input, { target: { value: '@Will Dzierson!' } });
    expect(input.value).toBe('willdzierson');
    fireEvent.change(input, { target: { value: 'ab' } });
    expect(button).toBeDisabled(); // Continue waits for three characters
    fireEvent.submit(input.closest('form')!); // the handler holds the line on its own, whatever the button says
    expect(await screen.findByText(/3–20 letters and numbers/)).toBeInTheDocument();
    expect(db.updated).toBeNull();
    expect(db.reads).toEqual([]); // the format check comes before any network
  });

  it('claims the handle and reports back', async () => {
    const { onClaimed, button } = setup();
    fireEvent.click(button);
    await waitFor(() => expect(onClaimed).toHaveBeenCalled());
    expect(db.updated).toEqual({ username: 'willdzierson', handle_confirmed: true });
  });

  it('turns a unique violation into the field error', async () => {
    db.update.mockResolvedValue({ error: { code: '23505', message: 'duplicate key' } });
    const { onClaimed, button } = setup();
    fireEvent.click(button);
    expect(await screen.findByText(/that username is taken/)).toBeInTheDocument();
    expect(onClaimed).not.toHaveBeenCalled();
  });

  it('warns live when a typed handle belongs to someone else', async () => {
    db.taken = { id: 'someone-else' };
    const { input } = setup();
    fireEvent.change(input, { target: { value: 'taken' } });
    expect(await screen.findByText(/that username is taken/)).toBeInTheDocument();
  });

  it("the server's own handle never reads as taken", async () => {
    vi.useFakeTimers();
    db.taken = { id: 'u1' }; // the row stash3 sits on is this person's own
    const { input, button } = setup();
    fireEvent.change(input, { target: { value: 'stash3' } });
    await elapse(400);
    expect(screen.queryByText(/that username is taken/)).not.toBeInTheDocument();
    expect(button).toBeEnabled();
    expect(db.reads).toEqual([]); // not even asked
  });

  it('probes only the handle that settles', async () => {
    vi.useFakeTimers();
    const { input } = setup();
    fireEvent.change(input, { target: { value: 'tak' } });
    await elapse(200); // still typing
    fireEvent.change(input, { target: { value: 'taken' } });
    await elapse(400);
    expect(db.reads).toEqual([['id', 'username', 'taken']]); // not the prefill, not "tak"
  });

  it('drops a probe answer that arrives after the field has moved on', async () => {
    vi.useFakeTimers();
    let release!: () => void;
    db.hold = new Promise<void>((resolve) => { release = resolve; });
    db.taken = { id: 'someone-else' };
    const { input, button } = setup();
    fireEvent.change(input, { target: { value: 'taken' } });
    await elapse(400); // the probe for "taken" is out, held open
    db.taken = null; // the next handle is free
    fireEvent.change(input, { target: { value: 'takenx' } });
    await elapse(400);
    await act(async () => { release(); }); // the old answer finally lands
    expect(screen.queryByText(/that username is taken/)).not.toBeInTheDocument();
    expect(button).toBeEnabled();
  });

  it("a taken prefill falls back to the server's handle without an error", async () => {
    vi.useFakeTimers();
    db.taken = { id: 'someone-else' }; // johnsmith is someone else's, which is why the server named this person johnsmith2
    const { input, button } = setup('johnsmith', undefined, 'johnsmith2');
    await elapse(400);
    expect(input.value).toBe('johnsmith2');
    expect(screen.queryByText(/that username is taken/)).not.toBeInTheDocument();
    expect(screen.getByText('gostash.it/feed/johnsmith2')).toBeInTheDocument();
    expect(button).toBeEnabled();
    expect(db.reads).toEqual([['id', 'username', 'johnsmith']]); // the server's handle is this person's own: never probed
  });

  it('a guest-shaped server handle is never offered', async () => {
    vi.useFakeTimers();
    db.taken = { id: 'someone-else' };
    const { input, button } = setup('will', undefined, 'guest-ab12cd34');
    await elapse(400);
    expect(input.value).toBe('will');
    expect(screen.getByText(/that username is taken/)).toBeInTheDocument();
    expect(button).toBeDisabled();
  });

  it('a typed taken handle still errors', async () => {
    vi.useFakeTimers();
    db.taken = { id: 'someone-else' };
    const { input, button } = setup(); // the server's stash3 could stand in, but never for a handle the person typed
    fireEvent.change(input, { target: { value: 'taken' } });
    await elapse(400);
    expect(input.value).toBe('taken');
    expect(screen.getByText(/that username is taken/)).toBeInTheDocument();
    expect(button).toBeDisabled();
    // typing the prefill back in is typing too
    fireEvent.change(input, { target: { value: 'willdzierso' } });
    fireEvent.change(input, { target: { value: 'willdzierson' } });
    await elapse(400);
    expect(input.value).toBe('willdzierson');
    expect(screen.getByText(/that username is taken/)).toBeInTheDocument();
  });

  it('holds the field still while the claim is in flight', async () => {
    let finish!: () => void;
    db.update.mockImplementation(() => new Promise<{ error: null }>((resolve) => { finish = () => resolve({ error: null }); }));
    const { input, button, onClaimed } = setup();
    expect(input).not.toHaveAttribute('readonly');
    fireEvent.click(button);
    await waitFor(() => expect(input).toHaveAttribute('readonly'));
    await act(async () => { finish(); });
    await waitFor(() => expect(onClaimed).toHaveBeenCalled());
    expect(input).not.toHaveAttribute('readonly');
  });

  it.each<[string, { display_name: string | null } | null]>([
    ['the server fallback', { display_name: 'stash3' }],
    ['empty', { display_name: '' }],
    ['missing', { display_name: null }],
    ['no row', null], // the lookup worked and found nothing: not an error, so not a reason to hold back
  ])('replaces a fallback display name with the claimed handle (%s)', async (_which, profile) => {
    db.profile = profile;
    const { onClaimed, button } = setup();
    fireEvent.click(button);
    await waitFor(() => expect(onClaimed).toHaveBeenCalled());
    expect(db.updated).toEqual({ username: 'willdzierson', handle_confirmed: true, display_name: 'willdzierson' });
  });

  it('never overwrites a chosen display name', async () => {
    db.profile = { display_name: 'Chosen Name' };
    const { onClaimed, button } = setup();
    fireEvent.click(button);
    await waitFor(() => expect(onClaimed).toHaveBeenCalled());
    expect(db.reads).toContainEqual(['display_name', 'id', 'u1']); // asked about this person's own row
    expect(db.updated).not.toHaveProperty('display_name');
  });

  it('replaces a display name that is only the email local part with the claimed handle', async () => {
    db.profile = { display_name: 'kz8f3q2m' };
    const { onClaimed, button } = setup('willdzierson', 'kz8f3q2m@privaterelay.appleid.com');
    fireEvent.click(button);
    await waitFor(() => expect(onClaimed).toHaveBeenCalled());
    expect(db.updated).toEqual({ username: 'willdzierson', handle_confirmed: true, display_name: 'willdzierson' });
  });

  it('claims without touching the display name when its lookup fails', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    db.profile = null;
    db.readError = { message: 'network down' };
    const { onClaimed, button } = setup();
    fireEvent.click(button);
    await waitFor(() => expect(onClaimed).toHaveBeenCalled());
    expect(db.updated).toEqual({ username: 'willdzierson', handle_confirmed: true });
    expect(db.updated).not.toHaveProperty('display_name'); // never guess
    expect(warn).toHaveBeenCalledWith('[handle] display name lookup failed:', 'network down');
    expect(toast).not.toHaveBeenCalled();
  });
});
