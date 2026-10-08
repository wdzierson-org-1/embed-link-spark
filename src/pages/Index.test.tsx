import { render, waitFor } from "@testing-library/react";
import Index from "./Index";

const navigateMock = vi.fn();
const fetchItemsMock = vi.fn();
const itemsLoadingState = { current: false };
const itemsState = { current: [] as Array<{ id: string; title?: string; type?: string }> };

vi.mock("react-router-dom", () => ({
  useNavigate: () => navigateMock,
}));

vi.mock("@/hooks/useAuth", () => ({
  useAuth: () => ({
    user: { id: "user-1", email: "test@example.com" },
    loading: false,
    session: { access_token: "token" },
  }),
}));

vi.mock("@/hooks/useItems", () => ({
  useItems: () => ({
    items: itemsState.current,
    fetchItems: fetchItemsMock,
    addOptimisticItem: vi.fn(),
    removeOptimisticItem: vi.fn(),
    clearSkeletonItems: vi.fn(),
    isInitialLoadInProgress: itemsLoadingState.current,
  }),
}));

vi.mock("@/hooks/useItemOperations", () => ({
  useItemOperations: () => ({
    handleAddContent: vi.fn(),
    handleSaveItem: vi.fn(),
    handleDeleteItem: vi.fn(),
  }),
}));

vi.mock("@/hooks/useTags", () => ({
  useTags: () => ({ tags: [] }),
}));

vi.mock("@/utils/aiOperations", () => ({
  getSuggestedTags: vi.fn().mockResolvedValue([]),
}));

vi.mock("@/components/HeaderSection", () => ({
  default: () => null,
}));
vi.mock("@/components/SubscriptionBanner", () => ({
  default: () => null,
}));
vi.mock("@/components/UnifiedInputPanel", () => ({
  default: () => null,
}));
vi.mock("@/components/LibraryToolbar", () => ({
  default: () => null,
}));
vi.mock("@/components/ContentGrid", () => ({
  default: () => null,
}));
// The sheet shows the title it's given, so the test can see which row it has
vi.mock("@/components/EditItemSheet", () => ({
  default: ({ item }: { item: { title?: string } | null }) =>
    item ? <div data-testid="sheet">{item.title || "Untitled"}</div> : null,
}));
vi.mock("@/components/ChatMole", () => ({
  default: () => null,
}));

const { sweepMock } = vi.hoisted(() => ({
  sweepMock: vi.fn().mockResolvedValue(undefined),
}));
vi.mock("@/utils/stagedUploader", () => ({
  sweepStagingOrphans: sweepMock,
}));

describe("Index", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    itemsLoadingState.current = false;
    itemsState.current = [];
    window.location.hash = "";
  });

  it("shows the open card's live row, so a save opened mid-read fills in as enrichment lands", async () => {
    const id = "12345678-1234-4123-8123-123456789abc";
    itemsState.current = [{ id, title: "", type: "link" }];
    window.location.hash = `#item=${id}`;

    const { findByTestId, rerender } = render(<Index />);
    expect(await findByTestId("sheet")).toHaveTextContent("Untitled");

    itemsState.current = [{ id, title: "Our Locations", type: "link" }];
    rerender(<Index />);
    expect(await findByTestId("sheet")).toHaveTextContent("Our Locations");
  });

  it("does not trigger manual fetchItems on mount", async () => {
    render(<Index />);

    await waitFor(() => {
      expect(fetchItemsMock).not.toHaveBeenCalled();
    });
  });

  it("shows the loading interstitial while initial items load is in progress", async () => {
    itemsLoadingState.current = true;

    const { findByRole } = render(<Index />);

    // The visible line decrypts and changes from load to load, so assert on the
    // status's one stable accessible name instead
    expect(await findByRole("status", { name: "Opening your stash" })).toBeInTheDocument();
  });

  it("sweeps staging orphans once for the signed-in user", async () => {
    render(<Index />);
    await waitFor(() => expect(sweepMock).toHaveBeenCalledWith("user-1"));
    expect(sweepMock).toHaveBeenCalledTimes(1);
  });
});
