import { buildStagingPath, removeStagedFile, sweepStagingOrphans, uploadToStaging } from "./stagedUploader";

const { getSessionMock, storageRemoveMock, storageListMock, itemsInMock, attachmentsInMock } = vi.hoisted(() => ({
  getSessionMock: vi.fn(),
  storageRemoveMock: vi.fn().mockResolvedValue({ data: null, error: null }),
  storageListMock: vi.fn(),
  itemsInMock: vi.fn(),
  attachmentsInMock: vi.fn(),
}));

vi.mock("@/integrations/supabase/client", () => ({
  SUPABASE_URL: "https://example.supabase.co",
  SUPABASE_PUBLISHABLE_KEY: "anon-key",
  supabase: {
    auth: { getSession: getSessionMock },
    storage: {
      from: vi.fn(() => ({ remove: storageRemoveMock, list: storageListMock })),
    },
    from: vi.fn((table: string) => ({
      select: vi.fn(() => ({ in: table === "items" ? itemsInMock : attachmentsInMock })),
    })),
  },
}));

class FakeXhr {
  static instances: FakeXhr[] = [];
  upload = { onprogress: null as ((e: { lengthComputable: boolean; loaded: number; total: number }) => void) | null };
  status = 200;
  onload: (() => void) | null = null;
  onerror: (() => void) | null = null;
  onabort: (() => void) | null = null;
  headers: Record<string, string> = {};
  openArgs: string[] = [];
  sent: unknown = null;
  aborted = false;
  open(method: string, url: string) { this.openArgs = [method, url]; }
  setRequestHeader(key: string, value: string) { this.headers[key] = value; }
  send(body: unknown) { this.sent = body; FakeXhr.instances.push(this); }
  abort() { this.aborted = true; this.onabort?.(); }
}

describe("stagedUploader", () => {
  beforeEach(() => {
    FakeXhr.instances = [];
    vi.stubGlobal("XMLHttpRequest", FakeXhr);
    getSessionMock.mockResolvedValue({ data: { session: { access_token: "jwt-token" } }, error: null });
    storageRemoveMock.mockClear().mockResolvedValue({ data: null, error: null });
  });

  afterEach(() => vi.unstubAllGlobals());

  it("builds staging paths under the user's staging folder", () => {
    const path = buildStagingPath("user-1", "report.pdf");
    expect(path).toMatch(/^user-1\/staging\/\d+-[a-z0-9]{6}\.pdf$/);
  });

  it("uploads via XHR with auth headers and reports progress", async () => {
    const onProgress = vi.fn();
    const file = new File(["data"], "report.pdf", { type: "application/pdf" });
    const promise = uploadToStaging(file, "user-1", onProgress);

    await vi.waitFor(() => expect(FakeXhr.instances.length).toBe(1));
    const xhr = FakeXhr.instances[0];
    expect(xhr.openArgs[0]).toBe("POST");
    expect(xhr.openArgs[1]).toContain("https://example.supabase.co/storage/v1/object/stash-media/user-1/staging/");
    expect(xhr.headers.Authorization).toBe("Bearer jwt-token");
    expect(xhr.headers.apikey).toBe("anon-key");

    xhr.upload.onprogress?.({ lengthComputable: true, loaded: 50, total: 100 });
    expect(onProgress).toHaveBeenCalledWith(50);

    xhr.onload?.();
    await expect(promise).resolves.toMatch(/^user-1\/staging\//);
  });

  it("retries once on failure with a fresh path", async () => {
    const file = new File(["data"], "report.pdf", { type: "application/pdf" });
    const promise = uploadToStaging(file, "user-1", vi.fn());

    await vi.waitFor(() => expect(FakeXhr.instances.length).toBe(1));
    FakeXhr.instances[0].status = 500;
    FakeXhr.instances[0].onload?.();

    await vi.waitFor(() => expect(FakeXhr.instances.length).toBe(2));
    FakeXhr.instances[1].onload?.();

    await expect(promise).resolves.toMatch(/^user-1\/staging\//);
    expect(FakeXhr.instances[0].openArgs[1]).not.toBe(FakeXhr.instances[1].openArgs[1]);
  });

  it("rejects with AbortError and does not retry when aborted", async () => {
    const controller = new AbortController();
    const file = new File(["data"], "report.pdf", { type: "application/pdf" });
    const promise = uploadToStaging(file, "user-1", vi.fn(), { signal: controller.signal });

    await vi.waitFor(() => expect(FakeXhr.instances.length).toBe(1));
    controller.abort();

    await expect(promise).rejects.toMatchObject({ name: "AbortError" });
    expect(FakeXhr.instances.length).toBe(1);
  });

  it("removeStagedFile swallows storage errors", async () => {
    storageRemoveMock.mockRejectedValueOnce(new Error("gone"));
    await expect(removeStagedFile("user-1/staging/1.pdf")).resolves.toBeUndefined();
  });

  it("sweeps only stale unreferenced staging files", async () => {
    const staleDate = new Date(Date.now() - 48 * 60 * 60 * 1000).toISOString();
    const freshDate = new Date().toISOString();
    storageListMock.mockResolvedValue({
      data: [
        { name: "old-orphan.pdf", created_at: staleDate },
        { name: "old-referenced.pdf", created_at: staleDate },
        { name: "fresh.pdf", created_at: freshDate },
      ],
      error: null,
    });
    itemsInMock.mockResolvedValue({ data: [{ file_path: "user-1/staging/old-referenced.pdf" }], error: null });
    attachmentsInMock.mockResolvedValue({ data: [], error: null });

    await sweepStagingOrphans("user-1");

    expect(storageRemoveMock).toHaveBeenCalledWith(["user-1/staging/old-orphan.pdf"]);
  });
});
