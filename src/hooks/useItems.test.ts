import { act, renderHook } from "@testing-library/react";
import { useItems } from "./useItems";

const {
  mockUserState,
  mockOrder,
  mockEq,
  mockSelect,
  mockFrom,
} = vi.hoisted(() => {
  const state = { current: null as { id: string } | null };
  const order = vi.fn();
  const eq = vi.fn(() => ({ order }));
  const select = vi.fn(() => ({ eq }));
  const from = vi.fn(() => ({ select }));

  return {
    mockUserState: state,
    mockOrder: order,
    mockEq: eq,
    mockSelect: select,
    mockFrom: from,
  };
});

vi.mock("@/hooks/useAuth", () => ({
  useAuth: () => ({ user: mockUserState.current }),
}));

vi.mock("@/hooks/use-toast", () => ({
  useToast: () => ({ toast: vi.fn() }),
}));

vi.mock("@/integrations/supabase/client", () => ({
  supabase: {
    from: mockFrom,
  },
}));

describe("useItems", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockUserState.current = null;
  });

  it("returns a stable items reference when state has not changed", () => {
    const { result, rerender } = renderHook(() => useItems());
    const firstItemsReference = result.current.items;

    rerender();

    expect(result.current.items).toBe(firstItemsReference);
  });

  it("uses a narrowed select projection for initial fetch", async () => {
    mockUserState.current = { id: "user-1" };
    mockOrder.mockResolvedValue({ data: [], error: null });

    renderHook(() => useItems());
    await act(async () => {
      await Promise.resolve();
    });

    await vi.waitFor(() => {
      expect(mockSelect).toHaveBeenCalledWith(
        "id,type,title,content,url,file_path,description,created_at,mime_type,is_public,supplemental_note"
      );
    });
  });
});
