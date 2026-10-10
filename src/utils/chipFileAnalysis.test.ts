import { analyzeDroppedFile, ChipAnalysisUpdate } from "./chipFileAnalysis";

const { analyzeLocallyMock, uploadMock, invokeMock } = vi.hoisted(() => ({
  analyzeLocallyMock: vi.fn(),
  uploadMock: vi.fn(),
  invokeMock: vi.fn(),
}));

vi.mock("./localFileAnalysis", () => ({ analyzeFileLocally: analyzeLocallyMock }));
vi.mock("./stagedUploader", () => ({ uploadToStaging: uploadMock }));
vi.mock("@/integrations/supabase/client", () => ({
  supabase: { functions: { invoke: invokeMock } },
}));

const collectUpdates = () => {
  const updates: ChipAnalysisUpdate[] = [];
  return { updates, onUpdate: (update: ChipAnalysisUpdate) => updates.push(update) };
};

describe("analyzeDroppedFile", () => {
  beforeEach(() => {
    analyzeLocallyMock.mockReset().mockResolvedValue({ factsLine: "PDF · 3 pages", snippet: "First page text", metadataTitle: "Kahn Cert" });
    uploadMock.mockReset().mockResolvedValue("user-1/staging/123-abc.pdf");
    invokeMock.mockReset();
  });

  it("emits the local facts and the staged upload, then is ready — and never enriches from the browser", async () => {
    const { updates, onUpdate } = collectUpdates();
    const file = new File(["%PDF"], "kahn-cerf-88.pdf", { type: "application/pdf" });

    const result = await analyzeDroppedFile(file, "document", "user-1", onUpdate).done;

    expect(invokeMock).not.toHaveBeenCalled();
    expect(result).toEqual({
      factsLine: "PDF · 3 pages",
      snippet: "First page text",
      metadataTitle: "Kahn Cert",
      uploadedFilePath: "user-1/staging/123-abc.pdf",
    });
    expect(updates.map((u) => u.analysisState).filter(Boolean)).toEqual(["local", "ready"]);
    expect(updates.findIndex((u) => u.analysis?.factsLine)).toBeGreaterThanOrEqual(0);
  });

  it.each([
    ["image", "photo.jpg", "image/jpeg"],
    ["audio", "memo.m4a", "audio/mp4"],
    ["video", "clip.mp4", "video/mp4"],
  ] as const)("asks the server for nothing at chip time for %s files", async (kind, name, type) => {
    const { updates, onUpdate } = collectUpdates();
    const result = await analyzeDroppedFile(new File(["x"], name, { type }), kind, "user-1", onUpdate).done;
    expect(invokeMock).not.toHaveBeenCalled();
    expect(result.uploadedFilePath).toBe("user-1/staging/123-abc.pdf");
    expect(updates.at(-1)?.analysisState).toBe("ready");
  });

  it("forwards upload progress and marks upload done", async () => {
    uploadMock.mockImplementation(async (_f, _u, onProgress) => {
      onProgress(40);
      onProgress(90);
      return "user-1/staging/123-abc.pdf";
    });
    const { updates, onUpdate } = collectUpdates();

    await analyzeDroppedFile(new File(["x"], "a.pdf", { type: "application/pdf" }), "document", "user-1", onUpdate).done;

    const progress = updates.map((u) => u.uploadProgress).filter((p) => p !== undefined);
    expect(progress).toContain(40);
    expect(progress).toContain(90);
    expect(updates.some((u) => u.uploadState === "done")).toBe(true);
  });

  it("marks upload failed and still resolves ready with the local facts (the save uploads instead)", async () => {
    uploadMock.mockRejectedValue(new Error("network down"));
    const { updates, onUpdate } = collectUpdates();

    const result = await analyzeDroppedFile(
      new File(["x"], "a.pdf", { type: "application/pdf" }), "document", "user-1", onUpdate
    ).done;

    expect(updates.some((u) => u.uploadState === "failed")).toBe(true);
    expect(updates.at(-1)?.analysisState).toBe("ready");
    expect(result.factsLine).toBe("PDF · 3 pages");
    expect(result.uploadedFilePath).toBeUndefined();
  });

  it("stops emitting after abort", async () => {
    let resolveUpload: (path: string) => void = () => undefined;
    uploadMock.mockImplementation(() => new Promise((resolve) => { resolveUpload = resolve; }));
    const { updates, onUpdate } = collectUpdates();

    const handle = analyzeDroppedFile(
      new File(["x"], "a.pdf", { type: "application/pdf" }), "document", "user-1", onUpdate
    );
    await vi.waitFor(() => expect(updates.length).toBeGreaterThan(0));
    const countAtAbort = updates.length;
    handle.abort();
    resolveUpload("user-1/staging/late.pdf");
    await handle.done;

    expect(updates.length).toBe(countAtAbort);
  });
});
