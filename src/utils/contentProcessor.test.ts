import { processAndInsertContent } from "./contentProcessor";

const {
  fromMock,
  invokeMock,
  itemsUpdateEqMock,
  attachmentsUpdateEqMock,
  generateEmbeddingsMock,
  fetchItemsMock,
  insertedItemSingle,
  insertedCollectionSingle,
  insertedAttachmentSingle,
  itemsInsertPayloads,
  attachmentInsertPayloads,
} = vi.hoisted(() => {
  const fetchItems = vi.fn().mockResolvedValue(undefined);
  const invoke = vi.fn();
  const itemsUpdateEq = vi.fn().mockResolvedValue({ error: null });
  const attachmentsUpdateEq = vi.fn().mockResolvedValue({ error: null });
  const generateEmbeddings = vi.fn().mockResolvedValue(undefined);
  const itemsSelectEqSingle = vi.fn().mockResolvedValue({
    data: {
      title: "Collection title",
      content: "Collection body",
      description: "Collection description",
    },
    error: null,
  });
  const itemsSelectEq = vi.fn(() => ({ single: itemsSelectEqSingle }));
  const attachmentsSelectEq = vi.fn().mockResolvedValue({
    data: [
      {
        title: "Attachment title",
        description: "Attachment description",
        url: "https://example.com/video",
        metadata: { siteName: "YouTube", processedContent: "Transcript text" },
      },
    ],
    error: null,
  });

  const insertedItem = vi.fn().mockResolvedValue({
    data: {
      id: "item-link-1",
      title: "Initial title",
      description: "Initial description",
      file_path: null,
    },
    error: null,
  });

  const insertedCollection = vi.fn().mockResolvedValue({
    data: {
      id: "collection-1",
      title: "Collection title",
      description: "Collection description",
      file_path: null,
    },
    error: null,
  });

  const insertedAttachment = vi.fn().mockResolvedValue({
    data: {
      id: "attachment-1",
      title: "https://example.com/video",
      description: null,
      metadata: { siteName: undefined, image: undefined },
    },
    error: null,
  });

  const insertPayloads: any[] = [];
  const attachmentPayloads: any[] = [];

  const from = vi.fn((table: string) => {
    if (table === "items") {
      return {
        select: vi.fn(() => ({
          eq: itemsSelectEq,
        })),
        insert: vi.fn((payload: any) => {
          const record = Array.isArray(payload) ? payload[0] : payload;
          insertPayloads.push(record);
          const singleResolver = record?.type === "collection" ? insertedCollection : insertedItem;
          return {
            select: vi.fn(() => ({
              single: singleResolver,
            })),
          };
        }),
        update: vi.fn(() => ({
          eq: itemsUpdateEq,
        })),
      };
    }

    if (table === "item_attachments") {
      return {
        select: vi.fn(() => ({
          eq: attachmentsSelectEq,
        })),
        insert: vi.fn((payload: any) => {
          const record = Array.isArray(payload) ? payload[0] : payload;
          attachmentPayloads.push(record);
          return {
            select: vi.fn(() => ({
              single: insertedAttachment,
            })),
          };
        }),
        update: vi.fn(() => ({
          eq: attachmentsUpdateEq,
        })),
      };
    }

    return {
      insert: vi.fn(() => ({
        select: vi.fn(() => ({
          single: insertedCollection,
        })),
      })),
    };
  });

  return {
    fromMock: from,
    invokeMock: invoke,
    itemsUpdateEqMock: itemsUpdateEq,
    attachmentsUpdateEqMock: attachmentsUpdateEq,
    generateEmbeddingsMock: generateEmbeddings,
    fetchItemsMock: fetchItems,
    insertedItemSingle: insertedItem,
    insertedCollectionSingle: insertedCollection,
    insertedAttachmentSingle: insertedAttachment,
    itemsInsertPayloads: insertPayloads,
    attachmentInsertPayloads: attachmentPayloads,
  };
});

vi.mock("@/integrations/supabase/client", () => ({
  supabase: {
    auth: {
      getSession: vi.fn().mockResolvedValue({
        data: { session: { access_token: "token" } },
        error: null,
      }),
    },
    from: fromMock,
    functions: {
      invoke: invokeMock,
    },
    storage: {
      from: vi.fn(() => ({
        getPublicUrl: vi.fn(() => ({
          data: { publicUrl: "https://example.com/file.png" },
        })),
      })),
    },
  },
}));

vi.mock("@/utils/aiOperations", () => ({
  generateDescription: vi.fn().mockResolvedValue("Generated description"),
  generateEmbeddings: generateEmbeddingsMock,
}));

vi.mock("@/utils/pdfProcessor", () => ({
  processPdfContent: vi.fn().mockResolvedValue(undefined),
}));

vi.mock("@/utils/fileUploader", () => ({
  uploadFile: vi.fn().mockResolvedValue("uploaded/path"),
}));

vi.mock("@/utils/titleGenerator", () => ({
  generateTitle: vi.fn().mockResolvedValue("Generated title"),
}));

describe("processAndInsertContent link enrichment", () => {
  let fetchSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
    fetchSpy = vi.spyOn(globalThis, "fetch").mockRejectedValue(new Error("network disabled in test"));

    insertedItemSingle.mockResolvedValue({
      data: {
        id: "item-link-1",
        title: "Initial title",
        description: "Initial description",
        file_path: null,
      },
      error: null,
    });

    insertedCollectionSingle.mockResolvedValue({
      data: {
        id: "collection-1",
        title: "Collection title",
        description: "Collection description",
        file_path: null,
      },
      error: null,
    });

    insertedAttachmentSingle.mockResolvedValue({
      data: {
        id: "attachment-1",
        title: "https://example.com/video",
        description: null,
        metadata: { siteName: undefined, image: undefined },
      },
      error: null,
    });
  });

  afterEach(() => {
    fetchSpy.mockRestore();
    vi.useRealTimers();
  });

  it("updates saved link items when deep metadata becomes available", async () => {
    invokeMock.mockResolvedValue({
      data: {
        success: true,
        title: "Deep title",
        description: "Deep description",
        previewImagePath: "user-1/previews/preview.jpg",
        siteName: "YouTube",
      },
      error: null,
    });

    await processAndInsertContent(
      "link",
      {
        url: "https://www.youtube.com/watch?v=MPTNHrq_4LU",
        title: "Initial title",
        description: "Initial description",
      },
      "user-1",
      true,
      fetchItemsMock,
      vi.fn()
    );

    await vi.runOnlyPendingTimersAsync();
    await Promise.resolve();
    await vi.runOnlyPendingTimersAsync();

    expect(invokeMock).toHaveBeenCalledWith("extract-link-metadata", {
      body: {
        url: "https://www.youtube.com/watch?v=MPTNHrq_4LU",
        userId: "user-1",
        fastOnly: false,
      },
    });

    expect(itemsUpdateEqMock).toHaveBeenCalledWith("id", "item-link-1");
  });

  it("updates collection link attachments when deep metadata is available", async () => {
    invokeMock.mockResolvedValue({
      data: {
        success: true,
        title: "Video title",
        description: "Video description",
        image: "https://img.youtube.com/vi/MPTNHrq_4LU/hqdefault.jpg",
        siteName: "YouTube",
      },
      error: null,
    });

    await processAndInsertContent(
      "collection",
      {
        title: "Collection title",
        description: "Collection description",
        attachments: [
          {
            type: "link",
            url: "https://example.com/video",
            title: "https://example.com/video",
          },
        ],
      },
      "user-1",
      true,
      fetchItemsMock,
      vi.fn()
    );

    await vi.runOnlyPendingTimersAsync();

    expect(attachmentsUpdateEqMock).toHaveBeenCalledWith("id", "attachment-1");
    expect(invokeMock).toHaveBeenCalledWith("extract-link-metadata", {
      body: {
        url: "https://example.com/video",
        userId: "user-1",
        fastOnly: false,
      },
    });
  });

  it("inserts a text note immediately even when AI title generation is slow", async () => {
    invokeMock.mockResolvedValue({ data: null, error: null });
    const { generateTitle } = await import("@/utils/titleGenerator");
    (generateTitle as ReturnType<typeof vi.fn>).mockImplementation(
      () => new Promise(() => {}) // hangs forever
    );
    const { generateDescription } = await import("@/utils/aiOperations");
    (generateDescription as ReturnType<typeof vi.fn>).mockImplementation(
      () => new Promise(() => {}) // hangs forever
    );

    const processing = processAndInsertContent(
      "text",
      { content: "A quick thought about pasta recipes", type: "text" } as any,
      "user-1",
      true,
      fetchItemsMock,
      vi.fn()
    );

    await vi.advanceTimersByTimeAsync(50);

    const textInsert = itemsInsertPayloads.find((p) => p.type === "text");
    expect(textInsert).toBeDefined();
    expect(textInsert.content).toBe("A quick thought about pasta recipes");
    expect(textInsert.title).toBeTruthy();

    await Promise.race([processing, Promise.resolve()]);

    // Restore default implementations so the hanging mocks don't leak
    (generateTitle as ReturnType<typeof vi.fn>).mockResolvedValue("Generated title");
    (generateDescription as ReturnType<typeof vi.fn>).mockResolvedValue("Generated description");
  });

  it("includes the visibility flag in the insert payload", async () => {
    invokeMock.mockResolvedValue({ data: null, error: null });

    await processAndInsertContent(
      "text",
      {
        content: "A private thought",
        title: "My note",
        is_public: false,
      },
      "user-1",
      true,
      fetchItemsMock,
      vi.fn()
    );

    const textInsert = itemsInsertPayloads.find((p) => p.type === "text");
    expect(textInsert).toBeDefined();
    expect(textInsert.is_public).toBe(false);
  });

  it("generates a baseline embedding for documents at insert time", async () => {
    invokeMock.mockResolvedValue({ data: null, error: null });

    await processAndInsertContent(
      "document",
      {
        title: "Q3 Report",
        uploadedFilePath: "user-1/uploads/q3-report.pdf",
        isProcessing: true,
      },
      "user-1",
      true,
      fetchItemsMock,
      vi.fn()
    );

    const baselineCall = generateEmbeddingsMock.mock.calls.find(
      ([itemId]) => itemId === "item-link-1"
    );
    expect(baselineCall).toBeDefined();
    expect(baselineCall?.[1]).toContain("Q3 Report");
  });

  it("falls back to YouTube thumbnail metadata when extraction fails", async () => {
    invokeMock.mockResolvedValue({
      data: null,
      error: { message: "Function failed" },
    });

    await processAndInsertContent(
      "link",
      {
        url: "https://www.youtube.com/watch?v=MPTNHrq_4LU",
        title: "Initial title",
        description: "Initial description",
      },
      "user-1",
      true,
      fetchItemsMock,
      vi.fn()
    );

    await vi.runOnlyPendingTimersAsync();

    expect(itemsUpdateEqMock).toHaveBeenCalledWith("id", "item-link-1");
  });
});

describe("chip-analysis reuse at save", () => {
  let fetchSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    vi.clearAllMocks();
    itemsInsertPayloads.length = 0;
    attachmentInsertPayloads.length = 0;
    vi.useFakeTimers();
    fetchSpy = vi.spyOn(globalThis, "fetch").mockRejectedValue(new Error("network disabled in test"));

    insertedItemSingle.mockResolvedValue({
      data: {
        id: "item-media-1",
        title: "Initial title",
        description: "Initial description",
        file_path: null,
      },
      error: null,
    });
    insertedCollectionSingle.mockResolvedValue({
      data: {
        id: "collection-1",
        title: "Collection title",
        description: "Collection description",
        file_path: null,
      },
      error: null,
    });
    insertedAttachmentSingle.mockResolvedValue({
      data: {
        id: "attachment-1",
        title: "Contract voice memo",
        description: "Voice memo about the contract",
        metadata: {},
      },
      error: null,
    });
    invokeMock.mockResolvedValue({ data: { success: true, title: "T", description: "D" }, error: null });
  });

  afterEach(() => {
    fetchSpy.mockRestore();
    vi.useRealTimers();
  });

  it("skips transcription for audio when description and content are provided", async () => {
    await processAndInsertContent(
      "audio",
      {
        file: new File(["a"], "memo.m4a", { type: "audio/mp4" }),
        uploadedFilePath: "user-1/staging/2-def.m4a",
        title: "memo.m4a",
        description: "Voice memo about the contract",
        content: "full transcript",
      },
      "user-1",
      true,
      fetchItemsMock,
      vi.fn()
    );

    const transcribeCalls = invokeMock.mock.calls.filter(([name]) => name === "transcribe-audio");
    expect(transcribeCalls).toHaveLength(0);
    const inserted = itemsInsertPayloads.at(-1);
    expect(inserted.content).toBe("full transcript");
    expect(inserted.description).toBe("Voice memo about the contract");
    expect(inserted.file_path).toBe("user-1/staging/2-def.m4a");
  });

  it("passes precomputed vision results to analyze-image instead of re-running vision", async () => {
    await processAndInsertContent(
      "image",
      {
        file: new File(["i"], "photo.jpg", { type: "image/jpeg" }),
        uploadedFilePath: "user-1/staging/3-ghi.jpg",
        title: "photo.jpg",
        description: "A whiteboard sketch",
        detectedText: "Q3 roadmap",
        tags: ["sketch", "planning"],
      },
      "user-1",
      true,
      fetchItemsMock,
      vi.fn()
    );
    await vi.runOnlyPendingTimersAsync();

    const analyzeCall = invokeMock.mock.calls.find(([name]) => name === "analyze-image");
    expect(analyzeCall).toBeDefined();
    expect(analyzeCall![1].body.itemId).toBe("item-media-1");
    expect(analyzeCall![1].body.precomputed).toEqual({
      description: "A whiteboard sketch",
      detected_text: "Q3 roadmap",
      tags: ["sketch", "planning"],
    });
  });

  it("skips the filename-only quick summary when the chip already described the document", async () => {
    const { processPdfContent } = await import("@/utils/pdfProcessor");

    await processAndInsertContent(
      "document",
      {
        file: new File(["%PDF"], "kahn-cerf-88.pdf", { type: "application/pdf" }),
        uploadedFilePath: "user-1/staging/4-jkl.pdf",
        title: "Kahn-Cerf Certificate",
        description: "A 1988 certificate",
        snippet: "First page text",
      },
      "user-1",
      true,
      fetchItemsMock,
      vi.fn()
    );
    await vi.advanceTimersByTimeAsync(1500);

    const quickCalls = invokeMock.mock.calls.filter(([name]) => name === "quick-pdf-summary");
    expect(quickCalls).toHaveLength(0);
    // Full extraction still runs as the phase-2 safety net
    expect(processPdfContent).toHaveBeenCalledWith(
      "item-media-1",
      "user-1/staging/4-jkl.pdf",
      fetchItemsMock,
      expect.any(Function)
    );
  });

  it("reuses uploaded attachment files and chip analysis in collections", async () => {
    const { uploadFile } = await import("@/utils/fileUploader");

    await processAndInsertContent(
      "collection",
      {
        content: "note",
        attachments: [
          {
            type: "audio",
            name: "memo.m4a",
            size: 1234,
            fileType: "audio/mp4",
            uploadedFilePath: "user-1/staging/5-mno.m4a",
            title: "Contract voice memo",
            description: "Voice memo about the contract",
            processedContent: "full transcript",
          },
        ],
      },
      "user-1",
      true,
      fetchItemsMock,
      vi.fn()
    );

    expect(uploadFile).not.toHaveBeenCalled();
    const attachmentInsert = attachmentInsertPayloads.at(-1);
    expect(attachmentInsert.file_path).toBe("user-1/staging/5-mno.m4a");
    expect(attachmentInsert.title).toBe("Contract voice memo");
    expect(attachmentInsert.description).toBe("Voice memo about the contract");
    expect(attachmentInsert.metadata.processedContent).toBe("full transcript");
  });
});
