import { act, renderHook } from "@testing-library/react";
import { useEditItemSave } from "./useEditItemSave";

const makeRefs = () => ({
  titleRef: { current: "Draft title" },
  descriptionRef: { current: "Draft description" },
  contentRef: { current: "Draft content" },
  supplementalNoteRef: { current: "Draft note" },
  itemRef: {
    current: {
      id: "item-1",
      title: "Original title",
      description: "Original description",
      content: "Original content",
      supplemental_note: "",
    },
  },
});

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
    const refs = makeRefs();

    const { result } = renderHook(() =>
      useEditItemSave({ onSave, saveToLocalStorage, ...refs })
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

  it("includes every changed field — supplemental_note too — in the final flush", async () => {
    const onSave = vi.fn().mockResolvedValue(undefined);
    const refs = makeRefs();

    const { result } = renderHook(() =>
      useEditItemSave({ onSave, saveToLocalStorage: vi.fn(), ...refs })
    );

    await act(async () => {
      await result.current.flushAndFinalSave("item-1");
    });

    expect(onSave).toHaveBeenCalledTimes(1);
    expect(onSave).toHaveBeenCalledWith(
      "item-1",
      {
        title: "Draft title",
        description: "Draft description",
        content: "Draft content",
        supplemental_note: "Draft note",
      },
      { showSuccessToast: false, refreshItems: false }
    );
  });

  it("cancels a pending debounced save when flushing, so the close saves once", async () => {
    const onSave = vi.fn().mockResolvedValue(undefined);
    const refs = makeRefs();

    const { result } = renderHook(() =>
      useEditItemSave({ onSave, saveToLocalStorage: vi.fn(), ...refs })
    );

    act(() => {
      result.current.debouncedSave("item-1", { supplemental_note: "Draft note" });
    });

    await act(async () => {
      await result.current.flushAndFinalSave("item-1");
      vi.advanceTimersByTime(1000);
      await Promise.resolve();
    });

    expect(onSave).toHaveBeenCalledTimes(1);
    expect(onSave.mock.calls[0][1]).toMatchObject({ supplemental_note: "Draft note" });
  });

  it("skips the final save entirely when nothing changed", async () => {
    const onSave = vi.fn().mockResolvedValue(undefined);
    const refs = makeRefs();
    refs.titleRef.current = "Original title";
    refs.descriptionRef.current = "Original description";
    refs.contentRef.current = "Original content";
    refs.supplementalNoteRef.current = "";

    const { result } = renderHook(() =>
      useEditItemSave({ onSave, saveToLocalStorage: vi.fn(), ...refs })
    );

    await act(async () => {
      await result.current.flushAndFinalSave("item-1");
    });

    expect(onSave).not.toHaveBeenCalled();
  });
});
