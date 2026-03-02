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

  const from = vi.fn((table: string) => {
    if (table === "items") {
      return {
        select: vi.fn(() => ({
          eq: itemsSelectEq,
        })),
        insert: vi.fn((payload: any) => {
          const record = Array.isArray(payload) ? payload[0] : payload;
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
        insert: vi.fn(() => ({
          select: vi.fn(() => ({
            single: insertedAttachment,
          })),
        })),
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
