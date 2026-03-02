import { act, renderHook } from "@testing-library/react";
import { useEditItemSave } from "./useEditItemSave";

describe("useEditItemSave", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.clearAllMocks();
  });

  it("saves without forcing items refresh during debounced autosave", async () => {
    const onSave = vi.fn().mockResolvedValue(undefined);
    const saveToLocalStorage = vi.fn();
    const titleRef = { current: "Draft title" };
    const descriptionRef = { current: "Draft description" };
    const contentRef = { current: "Draft content" };

    const { result } = renderHook(() =>
      useEditItemSave({
        onSave,
        saveToLocalStorage,
        titleRef,
        descriptionRef,
        contentRef,
      })
    );

    act(() => {
      result.current.debouncedSave("item-1", { title: "Updated title" });
    });

    expect(saveToLocalStorage).toHaveBeenCalledTimes(1);

    await act(async () => {
      vi.advanceTimersByTime(1000);
      await Promise.resolve();
    });

    expect(onSave).toHaveBeenCalledWith(
      "item-1",
      { title: "Updated title" },
      { showSuccessToast: false, refreshItems: false }
    );
  });
});
