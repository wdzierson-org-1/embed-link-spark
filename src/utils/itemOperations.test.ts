import { saveItem } from "./itemOperations";
import { generateEmbeddings } from "./aiOperations";
import { supabase } from "@/integrations/supabase/client";

vi.mock("@/integrations/supabase/client", () => ({
  supabase: { from: vi.fn() },
}));

vi.mock("./aiOperations", () => ({
  generateEmbeddings: vi.fn().mockResolvedValue(undefined),
}));

const mergedRow = {
  id: "item-1",
  title: "New title",
  description: "Existing description",
  content: "Existing body text",
  supplemental_note: "Existing note",
  url: null,
};

const makeBuilder = (singleResult: { data: unknown; error: unknown }) => {
  const builder: Record<string, ReturnType<typeof vi.fn>> = {};
  for (const method of ["update", "eq", "select", "delete", "insert"]) {
    builder[method] = vi.fn(() => builder);
  }
  builder.single = vi.fn(() => Promise.resolve(singleResult));
  return builder;
};

describe("saveItem", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("regenerates embeddings from the full merged row when only the title changes", async () => {
    const itemsBuilder = makeBuilder({ data: mergedRow, error: null });
    const embeddingsBuilder = makeBuilder({ data: null, error: null });
    (supabase.from as ReturnType<typeof vi.fn>).mockImplementation(
      (table: string) => (table === "items" ? itemsBuilder : embeddingsBuilder)
    );

    await saveItem("item-1", { title: "New title" }, vi.fn(), vi.fn(), {
      showSuccessToast: false,
      refreshItems: false,
    });

    expect(generateEmbeddings).toHaveBeenCalledTimes(1);
    const [itemId, text] = (generateEmbeddings as ReturnType<typeof vi.fn>).mock
      .calls[0];
    expect(itemId).toBe("item-1");
    expect(text).toContain("New title");
    expect(text).toContain("Existing description");
    expect(text).toContain("Existing body text");
    expect(text).toContain("Existing note");
  });

  it("leaves embeddings untouched when only non-text fields change", async () => {
    const itemsBuilder = makeBuilder({ data: mergedRow, error: null });
    const embeddingsBuilder = makeBuilder({ data: null, error: null });
    (supabase.from as ReturnType<typeof vi.fn>).mockImplementation(
      (table: string) => (table === "items" ? itemsBuilder : embeddingsBuilder)
    );

    await saveItem("item-1", { is_public: true }, vi.fn(), vi.fn(), {
      showSuccessToast: false,
      refreshItems: false,
    });

    expect(embeddingsBuilder.delete).not.toHaveBeenCalled();
    expect(generateEmbeddings).not.toHaveBeenCalled();
  });
});
