import { act, renderHook } from "@testing-library/react";
import { useServerSearch } from "./useServerSearch";

const { mockInvoke } = vi.hoisted(() => ({
  mockInvoke: vi.fn(),
}));

vi.mock("@/integrations/supabase/client", () => ({
  supabase: { functions: { invoke: mockInvoke } },
}));

describe("useServerSearch", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("returns null for short queries without calling the server", () => {
    const { result } = renderHook(({ q }) => useServerSearch(q), {
      initialProps: { q: "a" },
    });

    act(() => {
      vi.advanceTimersByTime(1000);
    });

    expect(result.current.serverResultIds).toBeNull();
    expect(mockInvoke).not.toHaveBeenCalled();
  });

  it("debounces, then returns relevance-ordered ids for the current query", async () => {
    mockInvoke.mockResolvedValue({
      data: { results: [{ id: "b" }, { id: "a" }] },
      error: null,
    });

    const { result } = renderHook(({ q }) => useServerSearch(q), {
      initialProps: { q: "typography" },
    });

    expect(result.current.serverResultIds).toBeNull();
    expect(mockInvoke).not.toHaveBeenCalled();

    await act(async () => {
      vi.advanceTimersByTime(300);
    });

    expect(mockInvoke).toHaveBeenCalledWith("search-items", {
      body: { query: "typography", limit: 50 },
    });
    expect(result.current.serverResultIds).toEqual(["b", "a"]);
  });

  it("returns null while a newer query is pending (stale results never apply)", async () => {
    mockInvoke.mockResolvedValue({
      data: { results: [{ id: "old" }] },
      error: null,
    });

    const { result, rerender } = renderHook(({ q }) => useServerSearch(q), {
      initialProps: { q: "first" },
    });

    await act(async () => {
      vi.advanceTimersByTime(300);
    });
    expect(result.current.serverResultIds).toEqual(["old"]);

    rerender({ q: "second" });
    expect(result.current.serverResultIds).toBeNull();
  });

  it("returns null on server error so the client filter takes over", async () => {
    mockInvoke.mockResolvedValue({ data: null, error: { message: "boom" } });

    const { result } = renderHook(({ q }) => useServerSearch(q), {
      initialProps: { q: "typography" },
    });

    await act(async () => {
      vi.advanceTimersByTime(300);
    });

    expect(result.current.serverResultIds).toBeNull();
  });

  it("serves repeat queries from cache without a second request", async () => {
    mockInvoke.mockResolvedValue({
      data: { results: [{ id: "x" }] },
      error: null,
    });

    const { result, rerender } = renderHook(({ q }) => useServerSearch(q), {
      initialProps: { q: "recipes" },
    });

    await act(async () => {
      vi.advanceTimersByTime(300);
    });
    expect(result.current.serverResultIds).toEqual(["x"]);

    rerender({ q: "" });
    expect(result.current.serverResultIds).toBeNull();

    rerender({ q: "recipes" });
    expect(result.current.serverResultIds).toEqual(["x"]);
    expect(mockInvoke).toHaveBeenCalledTimes(1);
  });
});
