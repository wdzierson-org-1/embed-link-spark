import { render, waitFor } from "@testing-library/react";
import Index from "./Index";

const navigateMock = vi.fn();
const fetchItemsMock = vi.fn();
const itemsLoadingState = { current: false };

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
    items: [],
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
vi.mock("@/components/EditItemSheet", () => ({
  default: () => null,
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
  });

  it("does not trigger manual fetchItems on mount", async () => {
    render(<Index />);

    await waitFor(() => {
      expect(fetchItemsMock).not.toHaveBeenCalled();
    });
  });

  it("shows the loading interstitial while initial items load is in progress", async () => {
    itemsLoadingState.current = true;

    const { findByLabelText } = render(<Index />);

    // The interstitial's stitched-S mark carries aria-label "Loading"; its
    // message copy cycles randomly, so assert on the stable mark instead
    expect(await findByLabelText("Loading")).toBeInTheDocument();
  });

  it("sweeps staging orphans once for the signed-in user", async () => {
    render(<Index />);
    await waitFor(() => expect(sweepMock).toHaveBeenCalledWith("user-1"));
    expect(sweepMock).toHaveBeenCalledTimes(1);
  });
});
