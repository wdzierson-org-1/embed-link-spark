import { saveItem } from "./itemOperations";
import { generateEmbeddings } from "./aiOperations";
import { supabase } from "@/integrations/supabase/client";

vi.mock("@/integrations/supabase/client", () => ({
  supabase: { from: vi.fn() },
}));

vi.mock("./aiOperations", () => ({
  generateEmbeddings: vi.fn().mockResolvedValue(undefined),
}));

const makeBuilder = (singleResult: { data: unknown; error: unknown }) => {
  const builder: Record<string, ReturnType<typeof vi.fn>> = {};
  for (const method of ["update", "eq", "select", "delete", "insert"]) {
    builder[method] = vi.fn(() => builder);
  }
  builder.single = vi.fn(() => Promise.resolve(singleResult));
  return builder;
};

// The embedding refresh runs on a fire-and-forget idle debounce after the
// save resolves; drain the timer plus the promise chain behind it.
const drainEmbeddingQueue = async () => {
  await vi.advanceTimersByTimeAsync(4000);
  for (let i = 0; i < 10; i++) await Promise.resolve();
};

describe("saveItem", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("resolves without waiting on embeddings, then regenerates from the full merged row", async () => {
    const mergedRow = {
      id: "item-merge",
      title: "New title",
      description: "Existing description",
      content: "Existing body text",
      supplemental_note: "Existing note",
      url: null,
    };
    const itemsBuilder = makeBuilder({ data: mergedRow, error: null });
    const embeddingsBuilder = makeBuilder({ data: null, error: null });
    (supabase.from as ReturnType<typeof vi.fn>).mockImplementation(
      (table: string) => (table === "items" ? itemsBuilder : embeddingsBuilder)
    );

    await saveItem("item-merge", { title: "New title" }, vi.fn(), vi.fn(), {
      showSuccessToast: false,
      refreshItems: false,
    });

    // The save itself is done — no embedding work has run yet
    expect(generateEmbeddings).not.toHaveBeenCalled();

    await drainEmbeddingQueue();

    expect(generateEmbeddings).toHaveBeenCalledTimes(1);
    const [itemId, text] = (generateEmbeddings as ReturnType<typeof vi.fn>).mock
      .calls[0];
    expect(itemId).toBe("item-merge");
    expect(text).toContain("New title");
    expect(text).toContain("Existing description");
    expect(text).toContain("Existing body text");
    expect(text).toContain("Existing note");
  });

  it("coalesces rapid saves into one embeddings refresh built from the latest row", async () => {
    const rowA = { id: "item-coalesce", title: "Title A", url: null };
    const rowB = { id: "item-coalesce", title: "Title B", url: null };
    const itemsBuilder = makeBuilder({ data: rowA, error: null });
    itemsBuilder.single = vi
      .fn()
      .mockResolvedValueOnce({ data: rowA, error: null })
      .mockResolvedValueOnce({ data: rowB, error: null });
    const embeddingsBuilder = makeBuilder({ data: null, error: null });
    (supabase.from as ReturnType<typeof vi.fn>).mockImplementation(
      (table: string) => (table === "items" ? itemsBuilder : embeddingsBuilder)
    );

    await saveItem("item-coalesce", { title: "Title A" }, vi.fn(), vi.fn(), {
      showSuccessToast: false,
      refreshItems: false,
    });
    await saveItem("item-coalesce", { title: "Title B" }, vi.fn(), vi.fn(), {
      showSuccessToast: false,
      refreshItems: false,
    });

    await drainEmbeddingQueue();

    expect(generateEmbeddings).toHaveBeenCalledTimes(1);
    const [, text] = (generateEmbeddings as ReturnType<typeof vi.fn>).mock
      .calls[0];
    expect(text).toContain("Title B");
  });

  it("leaves embeddings untouched when only non-text fields change", async () => {
    const mergedRow = { id: "item-nontext", title: "Unchanged", url: null };
    const itemsBuilder = makeBuilder({ data: mergedRow, error: null });
    const embeddingsBuilder = makeBuilder({ data: null, error: null });
    (supabase.from as ReturnType<typeof vi.fn>).mockImplementation(
      (table: string) => (table === "items" ? itemsBuilder : embeddingsBuilder)
    );

    await saveItem("item-nontext", { is_public: true }, vi.fn(), vi.fn(), {
      showSuccessToast: false,
      refreshItems: false,
    });

    await drainEmbeddingQueue();

    expect(embeddingsBuilder.delete).not.toHaveBeenCalled();
    expect(generateEmbeddings).not.toHaveBeenCalled();
  });
});
