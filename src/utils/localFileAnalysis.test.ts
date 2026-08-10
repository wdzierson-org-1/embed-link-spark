import { analyzeFileLocally, classifyFile } from "./localFileAnalysis";

const { pdfjsMock, exifrParseMock } = vi.hoisted(() => {
  const getTextContent = vi.fn().mockResolvedValue({
    items: [{ str: "Employment" }, { str: "Agreement" }, { str: "between parties" }],
  });
  const render = vi.fn(() => ({ promise: Promise.resolve() }));
  const getViewport = vi.fn(() => ({ width: 600, height: 800 }));
  const page = { getTextContent, render, getViewport };
  const doc = {
    numPages: 12,
    getMetadata: vi.fn().mockResolvedValue({ info: { Title: "Employment Agreement 2026" } }),
    getPage: vi.fn().mockResolvedValue(page),
  };
  return {
    pdfjsMock: {
      GlobalWorkerOptions: { workerSrc: "" },
      getDocument: vi.fn(() => ({ promise: Promise.resolve(doc) })),
    },
    exifrParseMock: vi.fn(),
  };
});

vi.mock("pdfjs-dist", () => pdfjsMock);
vi.mock("pdfjs-dist/build/pdf.worker.min.mjs?url", () => ({ default: "/mock-worker.js" }));
vi.mock("exifr", () => ({ default: { parse: exifrParseMock } }));

describe("classifyFile", () => {
  it("routes by mime type with extension fallback", () => {
    expect(classifyFile(new File([""], "a.pdf", { type: "application/pdf" }))).toBe("pdf");
    expect(classifyFile(new File([""], "a.pdf", { type: "" }))).toBe("pdf");
    expect(classifyFile(new File([""], "a.jpg", { type: "image/jpeg" }))).toBe("image");
    expect(classifyFile(new File([""], "a.m4a", { type: "audio/mp4" }))).toBe("audio");
    expect(classifyFile(new File([""], "a.mov", { type: "video/quicktime" }))).toBe("video");
    expect(classifyFile(new File([""], "notes.md", { type: "" }))).toBe("text");
    expect(classifyFile(new File([""], "a.docx", { type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document" }))).toBe("other");
  });
});

describe("analyzeFileLocally", () => {
  beforeEach(() => {
    exifrParseMock.mockReset();
    vi.stubGlobal("URL", Object.assign(Object.create(URL), {
      createObjectURL: vi.fn(() => "blob:mock"),
      revokeObjectURL: vi.fn(),
    }));
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("extracts word count and snippet from text files", async () => {
    const file = new File(["alpha beta gamma delta"], "notes.txt", { type: "text/plain" });
    const facts = await analyzeFileLocally(file);
    expect(facts.snippet).toBe("alpha beta gamma delta");
    expect(facts.factsLine).toContain("TXT");
    expect(facts.factsLine).toContain("4 words");
  });

  it("extracts page count, metadata title, snippet, and thumbnail from PDFs", async () => {
    const canvasMock = {
      width: 0,
      height: 0,
      getContext: vi.fn(() => ({})),
      toDataURL: vi.fn(() => "data:image/png;base64,thumb"),
    };
    vi.spyOn(document, "createElement").mockImplementation(((tag: string) =>
      canvasMock) as never);

    const file = new File(["%PDF-1.4"], "kahn-cerf-88.pdf", { type: "application/pdf" });
    const facts = await analyzeFileLocally(file);

    expect(facts.pageCount).toBe(12);
    expect(facts.metadataTitle).toBe("Employment Agreement 2026");
    expect(facts.factsLine).toContain("PDF");
    expect(facts.factsLine).toContain("12 pages");
    expect(facts.snippet).toContain("Employment Agreement");
    expect(facts.thumbnailDataUrl).toBe("data:image/png;base64,thumb");
    vi.restoreAllMocks();
  });

  it("reads image dimensions and EXIF summary", async () => {
    exifrParseMock.mockResolvedValue({
      DateTimeOriginal: new Date("2026-04-01T10:00:00Z"),
      Model: "iPhone 15 Pro",
    });
    class FakeImage {
      onload: (() => void) | null = null;
      onerror: (() => void) | null = null;
      naturalWidth = 4032;
      naturalHeight = 3024;
      set src(_v: string) {
        queueMicrotask(() => this.onload?.());
      }
    }
    vi.stubGlobal("Image", FakeImage);

    const file = new File(["img"], "vb1 (3).jpg", { type: "image/jpeg" });
    const facts = await analyzeFileLocally(file);

    expect(facts.dimensions).toEqual({ width: 4032, height: 3024 });
    expect(facts.factsLine).toContain("JPEG");
    expect(facts.factsLine).toContain("4032×3024");
    expect(facts.exifSummary).toContain("iPhone 15 Pro");
  });

  it("reads audio duration via an Audio element", async () => {
    class FakeAudio {
      preload = "";
      duration = 204;
      onloadedmetadata: (() => void) | null = null;
      onerror: (() => void) | null = null;
      set src(_v: string) {
        queueMicrotask(() => this.onloadedmetadata?.());
      }
    }
    vi.stubGlobal("Audio", FakeAudio);

    const file = new File(["aud"], "memo.m4a", { type: "audio/mp4" });
    const facts = await analyzeFileLocally(file);

    expect(facts.durationSeconds).toBe(204);
    expect(facts.factsLine).toContain("3:24");
  });

  it("returns empty facts instead of throwing when extraction fails", async () => {
    pdfjsMock.getDocument.mockImplementationOnce(() => ({ promise: Promise.reject(new Error("bad pdf")) }));
    const file = new File(["%PDF"], "broken.pdf", { type: "application/pdf" });
    await expect(analyzeFileLocally(file)).resolves.toEqual({});
  });
});
