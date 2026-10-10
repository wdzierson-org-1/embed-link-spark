import { captureContent, describeFunctionError } from './captureClient';

const { invokeMock, uploadMock } = vi.hoisted(() => ({
  invokeMock: vi.fn(),
  uploadMock: vi.fn(),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { functions: { invoke: invokeMock } },
}));
vi.mock('@/utils/fileUploader', () => ({ uploadFile: uploadMock }));

const answered = (payload: Record<string, unknown>) => ({ data: payload, error: null });

describe('captureContent — the web composer saves through the platform API', () => {
  beforeEach(() => {
    invokeMock.mockReset();
    uploadMock.mockReset().mockResolvedValue('user-1/1700000000000.pdf');
  });

  it('saves a note through add-note with only the words and the structured facts', async () => {
    invokeMock.mockResolvedValue(answered({ success: true, note: { id: 'note-1', type: 'text' } }));
    const doc = JSON.stringify({ type: 'doc', content: [{ type: 'paragraph', content: [{ type: 'text', text: 'Buy milk' }] }] });

    const item = await captureContent('text', { content: doc, attributes: { location: { name: 'Home' } } as never }, 'user-1');

    expect(invokeMock).toHaveBeenCalledWith('add-note', {
      body: { content: doc, is_public: false, attributes: { location: { name: 'Home' } } },
    });
    expect(item.id).toBe('note-1');
  });

  it('saves a link through add-url without any browser-side metadata — the endpoint resolves the page', async () => {
    invokeMock.mockResolvedValue(answered({ success: true, item: { id: 'link-1', type: 'link' } }));

    await captureContent(
      'link',
      { url: 'https://www.tiktok.com/t/ZTygmPyEv/', content: 'watch later', is_public: true, attributes: { link: { flavor: 'video' } } },
      'user-1',
    );

    const [endpoint, { body }] = invokeMock.mock.calls[0];
    expect(endpoint).toBe('add-url');
    expect(body).toEqual({
      url: 'https://www.tiktok.com/t/ZTygmPyEv/',
      content: 'watch later',
      is_public: true,
      attributes: { link: { flavor: 'video' } },
    });
    expect(body).not.toHaveProperty('title');
    expect(body).not.toHaveProperty('description');
  });

  it('saves a file through add-file from its staged upload, with the original name and media facts', async () => {
    invokeMock.mockResolvedValue(answered({ success: true, item: { id: 'file-1', type: 'audio' } }));
    const file = new File(['a'], 'memo.m4a', { type: 'audio/mp4' });

    await captureContent(
      'audio',
      { file, uploadedFilePath: 'user-1/staging/123-abc.m4a', title: 'memo.m4a', attributes: { media: { duration_s: 42, file_name: 'memo.m4a' } } as never },
      'user-1',
    );

    expect(uploadMock).not.toHaveBeenCalled();
    expect(invokeMock).toHaveBeenCalledWith('add-file', {
      body: {
        file_path: 'user-1/staging/123-abc.m4a',
        mime_type: 'audio/mp4',
        file_size: 1,
        title: 'memo.m4a',
        is_public: false,
        attributes: { media: { duration_s: 42, file_name: 'memo.m4a' } },
      },
    });
  });

  it('uploads at save when the chip-time staged upload never landed', async () => {
    invokeMock.mockResolvedValue(answered({ success: true, item: { id: 'file-2' } }));
    const file = new File(['%PDF'], 'paper.pdf', { type: 'application/pdf' });

    await captureContent('document', { file, content: 'read this' }, 'user-1');

    expect(uploadMock).toHaveBeenCalledWith(file, 'user-1');
    expect(invokeMock.mock.calls[0][1].body).toMatchObject({ file_path: 'user-1/1700000000000.pdf', title: 'paper.pdf', content: 'read this' });
  });

  it('surfaces the endpoint’s own message when it refuses', async () => {
    const context = new Response(JSON.stringify({ error: 'subscription_required', message: 'Your trial has ended.' }), { status: 403 });
    invokeMock.mockResolvedValue({ data: null, error: Object.assign(new Error('Edge Function returned a non-2xx status code'), { context }) });

    await expect(captureContent('link', { url: 'https://example.com' }, 'user-1')).rejects.toThrow('Your trial has ended.');
  });

  it('refuses an empty note or a file-less file save before calling anything', async () => {
    await expect(captureContent('text', { content: '   ' }, 'user-1')).rejects.toThrow('A note needs some words');
    await expect(captureContent('image', {}, 'user-1')).rejects.toThrow('A file save needs a file');
    expect(invokeMock).not.toHaveBeenCalled();
  });

  it('treats a 2xx without the saved row as a failure', async () => {
    invokeMock.mockResolvedValue(answered({ success: true }));
    await expect(captureContent('link', { url: 'https://example.com' }, 'user-1')).rejects.toThrow('add-url answered without the saved item');
  });
});

describe('describeFunctionError', () => {
  it('prefers message, then details, then the error code, then the thrown message', async () => {
    const withBody = (body: unknown) => Object.assign(new Error('non-2xx'), { context: new Response(JSON.stringify(body)) });
    expect(await describeFunctionError(withBody({ error: 'x', details: 'd', message: 'm' }))).toBe('m');
    expect(await describeFunctionError(withBody({ error: 'x', details: 'd' }))).toBe('d');
    expect(await describeFunctionError(withBody({ error: 'x' }))).toBe('x');
    expect(await describeFunctionError(new Error('offline'))).toBe('offline');
    expect(await describeFunctionError(Object.assign(new Error('bad'), { context: new Response('not json') }))).toBe('bad');
  });
});
