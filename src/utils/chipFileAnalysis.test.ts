import { analyzeDroppedFile, ChipAnalysisUpdate } from "./chipFileAnalysis";

const { analyzeLocallyMock, uploadMock, invokeMock } = vi.hoisted(() => ({
  analyzeLocallyMock: vi.fn(),
  uploadMock: vi.fn(),
  invokeMock: vi.fn(),
}));

vi.mock("./localFileAnalysis", () => ({ analyzeFileLocally: analyzeLocallyMock }));
vi.mock("./stagedUploader", () => ({ uploadToStaging: uploadMock }));
vi.mock("@/integrations/supabase/client", () => ({
  supabase: {
    functions: { invoke: invokeMock },
    storage: {
      from: vi.fn(() => ({
        getPublicUrl: vi.fn((path: string) => ({ data: { publicUrl: `https://cdn.example/${path}` } })),
      })),
    },
  },
}));

const collectUpdates = () => {
  const updates: ChipAnalysisUpdate[] = [];
  return { updates, onUpdate: (update: ChipAnalysisUpdate) => updates.push(update) };
};

describe("analyzeDroppedFile", () => {
  beforeEach(() => {
    analyzeLocallyMock.mockReset().mockResolvedValue({ factsLine: "PDF · 3 pages", snippet: "First page text" });
    uploadMock.mockReset().mockResolvedValue("user-1/staging/123-abc.pdf");
    invokeMock.mockReset();
  });

  it("emits local facts, upload completion, and document summary in order", async () => {
    invokeMock.mockResolvedValue({ data: { title: "Kahn Cert", description: "A certificate" }, error: null });
    const { updates, onUpdate } = collectUpdates();
    const file = new File(["%PDF"], "kahn-cerf-88.pdf", { type: "application/pdf" });

    const handle = analyzeDroppedFile(file, "document", "user-1", onUpdate);
    const result = await handle.done;

    expect(invokeMock).toHaveBeenCalledWith("quick-pdf-summary", {
      body: { fileName: "kahn-cerf-88.pdf", snippet: "First page text" },
    });
    expect(result.uploadedFilePath).toBe("user-1/staging/123-abc.pdf");
    expect(result.title).toBe("Kahn Cert");
    expect(result.description).toBe("A certificate");

    const states = updates.map((u) => u.analysisState).filter(Boolean);
    expect(states).toEqual(["local", "analyzing", "ready"]);
    const factsIndex = updates.findIndex((u) => u.analysis?.factsLine);
    const summaryIndex = updates.findIndex((u) => u.analysis?.title);
    expect(factsIndex).toBeGreaterThanOrEqual(0);
    expect(summaryIndex).toBeGreaterThan(factsIndex);
  });

  it("forwards upload progress and marks upload done", async () => {
    uploadMock.mockImplementation(async (_f, _u, onProgress) => {
      onProgress(40);
      onProgress(90);
      return "user-1/staging/123-abc.pdf";
    });
    invokeMock.mockResolvedValue({ data: { title: "T", description: "D" }, error: null });
    const { updates, onUpdate } = collectUpdates();

    await analyzeDroppedFile(new File(["x"], "a.pdf", { type: "application/pdf" }), "document", "user-1", onUpdate).done;

    const progress = updates.map((u) => u.uploadProgress).filter((p) => p !== undefined);
    expect(progress).toContain(40);
    expect(progress).toContain(90);
    expect(updates.some((u) => u.uploadState === "done")).toBe(true);
  });

  it("calls analyze-image without itemId and normalizes 'none' detected text", async () => {
    invokeMock.mockResolvedValue({
      data: { success: true, description: "A whiteboard", detected_text: "none", tags: ["sketch"] },
      error: null,
    });

    const result = await analyzeDroppedFile(
      new File(["img"], "photo.jpg", { type: "image/jpeg" }), "image", "user-1", vi.fn()
    ).done;

    expect(invokeMock).toHaveBeenCalledWith("analyze-image", {
      body: { imageUrl: "https://cdn.example/user-1/staging/123-abc.pdf" },
    });
    expect(result.description).toBe("A whiteboard");
    expect(result.detectedText).toBeUndefined();
    expect(result.tags).toEqual(["sketch"]);
  });

  it("keeps transcript and summary for audio", async () => {
    invokeMock.mockResolvedValue({
      data: { transcription: "full transcript here", description: "Voice memo about a contract" },
      error: null,
    });

    const result = await analyzeDroppedFile(
      new File(["a"], "memo.m4a", { type: "audio/mp4" }), "audio", "user-1", vi.fn()
    ).done;

    expect(invokeMock).toHaveBeenCalledWith("transcribe-audio", {
      body: { audioUrl: expect.stringContaining("https://cdn.example/"), fileName: "memo.m4a" },
    });
    expect(result.transcription).toBe("full transcript here");
    expect(result.description).toBe("Voice memo about a contract");
  });

  it("skips server analysis for video and still resolves ready", async () => {
    const { updates, onUpdate } = collectUpdates();
    await analyzeDroppedFile(new File(["v"], "clip.mp4", { type: "video/mp4" }), "video", "user-1", onUpdate).done;
    expect(invokeMock).not.toHaveBeenCalled();
    expect(updates.at(-1)?.analysisState).toBe("ready");
  });

  it("marks upload failed, skips server analysis, and still resolves with local facts", async () => {
    uploadMock.mockRejectedValue(new Error("network down"));
    const { updates, onUpdate } = collectUpdates();

    const result = await analyzeDroppedFile(
      new File(["x"], "a.pdf", { type: "application/pdf" }), "document", "user-1", onUpdate
    ).done;

    expect(invokeMock).not.toHaveBeenCalled();
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
    expect(invokeMock).not.toHaveBeenCalled();
  });
});
