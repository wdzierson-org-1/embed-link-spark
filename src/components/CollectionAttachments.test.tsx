import { render, screen } from "@testing-library/react";
import CollectionAttachments from "./CollectionAttachments";

const { mockFrom } = vi.hoisted(() => ({
  mockFrom: vi.fn(),
}));

vi.mock("@/integrations/supabase/client", () => ({
  supabase: {
    from: mockFrom,
    storage: {
      from: () => ({
        getPublicUrl: () => ({ data: { publicUrl: "https://example.com/file" } }),
      }),
    },
  },
}));

describe("CollectionAttachments", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("uses prefetched attachments without querying item_attachments", () => {
    render(
      <CollectionAttachments
        itemId="collection-1"
        isCompactView={true}
        prefetchedAttachments={[
          {
            id: "att-1",
            type: "link",
            title: "Example link",
          },
        ]}
      />
    );

    expect(screen.getByText("Collection of 1 item:")).toBeInTheDocument();
    expect(mockFrom).not.toHaveBeenCalled();
  });
});
