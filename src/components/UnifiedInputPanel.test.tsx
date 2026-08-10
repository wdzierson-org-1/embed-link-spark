import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import UnifiedInputPanel from "./UnifiedInputPanel";

const { invokeMock, analyzeDroppedFileMock, removeStagedFileMock, chipDriver } = vi.hoisted(() => {
  const driver: {
    onUpdate?: (update: unknown) => void;
    resolveDone?: (analysis: unknown) => void;
    abort: ReturnType<typeof vi.fn>;
  } = { abort: vi.fn() };
  return {
    invokeMock: vi.fn(),
    removeStagedFileMock: vi.fn().mockResolvedValue(undefined),
    chipDriver: driver,
    analyzeDroppedFileMock: vi.fn((_file, _kind, _userId, onUpdate) => {
      driver.onUpdate = onUpdate;
      return {
        done: new Promise((resolve) => { driver.resolveDone = resolve; }),
        abort: driver.abort,
      };
    }),
  };
});

vi.mock("@/utils/chipFileAnalysis", () => ({ analyzeDroppedFile: analyzeDroppedFileMock }));
vi.mock("@/utils/stagedUploader", () => ({ removeStagedFile: removeStagedFileMock }));

vi.mock("@/hooks/use-toast", () => ({
  useToast: () => ({ toast: vi.fn() }),
}));

vi.mock("@/hooks/useSubscription", () => ({
  useSubscription: () => ({ canAddContent: true }),
}));

vi.mock("@/hooks/useAuth", () => ({
  useAuth: () => ({ user: { id: "user-1" } }),
}));

vi.mock("@/integrations/supabase/client", () => ({
  SUPABASE_URL: "https://example.supabase.co",
  supabase: {
    functions: {
      invoke: invokeMock,
    },
  },
}));

describe("UnifiedInputPanel", () => {
  let fetchSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    vi.clearAllMocks();
    fetchSpy = vi.spyOn(globalThis, "fetch").mockRejectedValue(new Error("network disabled in test"));
  });

  afterEach(() => {
    fetchSpy.mockRestore();
  });

  it("strips detected URLs from the note text at submit", async () => {
    invokeMock.mockResolvedValue({
      data: { success: true, title: "Example", description: "OG description" },
      error: null,
    });
    const onAddContent = vi.fn().mockResolvedValue(undefined);

    render(
      <UnifiedInputPanel
        isInputUICollapsed={false}
        onToggleInputUI={vi.fn()}
        onAddContent={onAddContent}
        getSuggestedTags={vi.fn().mockResolvedValue([])}
      />
    );

    const input = screen.getByRole("textbox");
    fireEvent.change(input, { target: { value: "great read https://example.com" } });

    await waitFor(() => expect(invokeMock).toHaveBeenCalled());

    fireEvent.click(screen.getByRole("button", { name: "Add to Stash" }));

    await waitFor(() => expect(onAddContent).toHaveBeenCalled());
    const [type, payload] = onAddContent.mock.calls[0];
    expect(type).toBe("link");
    expect(payload.description).toBe("great read");
  });

  it("uses the link's own description when the note text is only the URL", async () => {
    invokeMock.mockResolvedValue({
      data: { success: true, title: "Example", description: "OG description" },
      error: null,
    });
    const onAddContent = vi.fn().mockResolvedValue(undefined);

    render(
      <UnifiedInputPanel
        isInputUICollapsed={false}
        onToggleInputUI={vi.fn()}
        onAddContent={onAddContent}
        getSuggestedTags={vi.fn().mockResolvedValue([])}
      />
    );

    const input = screen.getByRole("textbox");
    fireEvent.change(input, { target: { value: "https://example.com" } });

    await waitFor(() => expect(invokeMock).toHaveBeenCalled());

    fireEvent.click(screen.getByRole("button", { name: "Add to Stash" }));

    await waitFor(() => expect(onAddContent).toHaveBeenCalled());
    const [, payload] = onAddContent.mock.calls[0];
    expect(payload.description).not.toContain("https://example.com");
  });

  it("requests fast metadata first for detected links", async () => {
    invokeMock.mockResolvedValue({
      data: {
        success: true,
        title: "Example",
        description: "A description",
      },
      error: null,
    });

    render(
      <UnifiedInputPanel
        isInputUICollapsed={false}
        onToggleInputUI={vi.fn()}
        onAddContent={vi.fn().mockResolvedValue(undefined)}
        getSuggestedTags={vi.fn().mockResolvedValue([])}
      />
    );

    const input = screen.getByRole("textbox");

    fireEvent.change(input, { target: { value: "https://example.com" } });

    await waitFor(() => {
      expect(invokeMock).toHaveBeenCalledWith("extract-link-metadata", {
        body: {
          url: "https://example.com",
          userId: "user-1",
          fastOnly: true,
        },
      });
    });
  });

  it("settles the chip on fast metadata without a pre-save deep request", async () => {
    let resolveFast: ((value: unknown) => void) | undefined;
    const fastPromise = new Promise((resolve) => {
      resolveFast = resolve;
    });

    invokeMock.mockImplementation((_name: string, payload: { body: { fastOnly?: boolean } }) => {
      if (payload.body.fastOnly) {
        return fastPromise;
      }
      return Promise.resolve({ data: null, error: null });
    });

    render(
      <UnifiedInputPanel
        isInputUICollapsed={false}
        onToggleInputUI={vi.fn()}
        onAddContent={vi.fn().mockResolvedValue(undefined)}
        getSuggestedTags={vi.fn().mockResolvedValue([])}
      />
    );

    const input = screen.getByRole("textbox");

    fireEvent.change(input, { target: { value: "https://example.com" } });

    expect(await screen.findByText("Fetching more details...")).toBeInTheDocument();

    resolveFast?.({
      data: {
        success: true,
        title: "Fast title",
        description: "Fast description",
      },
      error: null,
    });

    expect(await screen.findByText("Fast title")).toBeInTheDocument();

    await waitFor(() => {
      expect(screen.queryByText("Fetching more details...")).not.toBeInTheDocument();
    });

    const deepCalls = invokeMock.mock.calls.filter(
      ([name, payload]) => name === "extract-link-metadata" && payload.body.fastOnly === false
    );
    expect(deepCalls).toHaveLength(0);
  });

  it("shows an inferred slug title instantly when the site blocks metadata", async () => {
    invokeMock.mockImplementation(() =>
      Promise.resolve({ data: null, error: { message: "blocked" } })
    );

    render(
      <UnifiedInputPanel
        isInputUICollapsed={false}
        onToggleInputUI={vi.fn()}
        onAddContent={vi.fn().mockResolvedValue(undefined)}
        getSuggestedTags={vi.fn().mockResolvedValue([])}
      />
    );

    const input = screen.getByRole("textbox");

    fireEvent.change(input, { target: { value: "https://example.com/how-to-brew-better-coffee" } });

    expect(await screen.findByText("How To Brew Better Coffee")).toBeInTheDocument();
    expect(
      await screen.findByText(/Site blocks previews — got the gist/)
    ).toBeInTheDocument();

    const deepCalls = invokeMock.mock.calls.filter(
      ([name, payload]) => name === "extract-link-metadata" && payload.body.fastOnly === false
    );
    expect(deepCalls).toHaveLength(0);
  });

  it("submits fast metadata immediately after the chip settles", async () => {
    const onAddContent = vi.fn().mockResolvedValue(undefined);

    invokeMock.mockImplementation((_name: string, payload: { body: { fastOnly?: boolean } }) => {
      if (payload.body.fastOnly) {
        return Promise.resolve({
          data: {
            success: true,
            title: "Immediate title",
            description: "Immediate description",
          },
          error: null,
        });
      }
      return Promise.resolve({ data: null, error: null });
    });

    render(
      <UnifiedInputPanel
        isInputUICollapsed={false}
        onToggleInputUI={vi.fn()}
        onAddContent={onAddContent}
        getSuggestedTags={vi.fn().mockResolvedValue([])}
      />
    );

    const input = screen.getByRole("textbox");

    fireEvent.change(input, { target: { value: "https://example.com" } });

    await screen.findByText("Immediate title");

    fireEvent.click(screen.getByRole("button", { name: "Add to Stash" }));

    await waitFor(() => {
      expect(onAddContent).toHaveBeenCalledWith(
        "link",
        expect.objectContaining({
          url: "https://example.com",
          title: "Immediate title",
        })
      );
    });
  });

  it("uses fallback metadata even when the edge response marks success false", async () => {
    invokeMock.mockResolvedValue({
      data: {
        success: false,
        title: "LinkedIn Job Listing",
        description: "LinkedIn may require login to access full preview metadata.",
        siteName: "LinkedIn",
        strategyUsed: "linkedin-authwall-fallback",
      },
      error: null,
    });

    render(
      <UnifiedInputPanel
        isInputUICollapsed={false}
        onToggleInputUI={vi.fn()}
        onAddContent={vi.fn().mockResolvedValue(undefined)}
        getSuggestedTags={vi.fn().mockResolvedValue([])}
      />
    );

    const input = screen.getByRole("textbox");
    fireEvent.change(input, {
      target: { value: "https://www.linkedin.com/jobs/collections/recommended/?currentJobId=4373761967" },
    });

    expect(await screen.findByText("LinkedIn Job Listing")).toBeInTheDocument();
    expect(
      await screen.findByText("LinkedIn may require login to access full preview metadata.")
    ).toBeInTheDocument();
  });

  it("uses client-side YouTube fallback when metadata extraction fails, even with trailing punctuation", async () => {
    invokeMock.mockResolvedValue({
      data: {
        success: false,
        error: "Failed to extract metadata",
      },
      error: null,
    });

    render(
      <UnifiedInputPanel
        isInputUICollapsed={false}
        onToggleInputUI={vi.fn()}
        onAddContent={vi.fn().mockResolvedValue(undefined)}
        getSuggestedTags={vi.fn().mockResolvedValue([])}
      />
    );

    const input = screen.getByRole("textbox");
    fireEvent.change(input, {
      target: { value: "https://www.youtube.com/watch?v=MPTNHrq_4LU|" },
    });

    expect(await screen.findByText("YouTube Video")).toBeInTheDocument();
    expect(await screen.findByText("Video link from YouTube")).toBeInTheDocument();
  });

  it("shows provisional YouTube metadata in chip immediately while metadata is loading", async () => {
    const neverResolvingPromise = new Promise(() => {
      // Keep request pending so we can assert provisional metadata.
    });
    invokeMock.mockReturnValue(neverResolvingPromise);

    render(
      <UnifiedInputPanel
        isInputUICollapsed={false}
        onToggleInputUI={vi.fn()}
        onAddContent={vi.fn().mockResolvedValue(undefined)}
        getSuggestedTags={vi.fn().mockResolvedValue([])}
      />
    );

    const input = screen.getByRole("textbox");
    fireEvent.change(input, {
      target: { value: "https://www.youtube.com/watch?v=MPTNHrq_4LU" },
    });

    expect(await screen.findByText("YouTube Video")).toBeInTheDocument();
    expect(await screen.findByText("Video link from YouTube")).toBeInTheDocument();
    expect(await screen.findByText("Fetching more details...")).toBeInTheDocument();
  });

  it("upgrades YouTube chip text using oEmbed when available", async () => {
    fetchSpy.mockResolvedValue({
      ok: true,
      json: async () => ({
        title: "Full interview: Anthropic CEO responds to Trump order, Pentagon clash",
        author_name: "CBS News",
        thumbnail_url: "https://i.ytimg.com/vi/MPTNHrq_4LU/hqdefault.jpg",
      }),
    } as Response);

    invokeMock.mockResolvedValue({
      data: {
        success: false,
        error: "Failed to extract metadata",
      },
      error: null,
    });

    render(
      <UnifiedInputPanel
        isInputUICollapsed={false}
        onToggleInputUI={vi.fn()}
        onAddContent={vi.fn().mockResolvedValue(undefined)}
        getSuggestedTags={vi.fn().mockResolvedValue([])}
      />
    );

    const input = screen.getByRole("textbox");
    fireEvent.change(input, {
      target: { value: "https://www.youtube.com/watch?v=MPTNHrq_4LU" },
    });

    expect(
      await screen.findByText("Full interview: Anthropic CEO responds to Trump order, Pentagon clash")
    ).toBeInTheDocument();
    expect(await screen.findByText(/by CBS News on YouTube/)).toBeInTheDocument();
  });

  it("uses a 6px corner radius for the input panel shell", () => {
    render(
      <UnifiedInputPanel
        isInputUICollapsed={false}
        onToggleInputUI={vi.fn()}
        onAddContent={vi.fn().mockResolvedValue(undefined)}
        getSuggestedTags={vi.fn().mockResolvedValue([])}
      />
    );

    const panelShell = screen.getByTestId("input-panel-shell");
    expect(panelShell.className).toContain("rounded-[6px]");
  });
});

describe("UnifiedInputPanel file chips", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    chipDriver.onUpdate = undefined;
    chipDriver.resolveDone = undefined;
  });

  const renderPanel = (onAddContent = vi.fn().mockResolvedValue(undefined)) => {
    render(
      <UnifiedInputPanel
        isInputUICollapsed={false}
        onToggleInputUI={vi.fn()}
        onAddContent={onAddContent}
        getSuggestedTags={vi.fn().mockResolvedValue([])}
      />
    );
    return onAddContent;
  };

  const dropFile = (file: File) => {
    const dropzone = screen.getByTestId("capture-dropzone");
    fireEvent.drop(dropzone, { dataTransfer: { files: [file] } });
  };

  it("starts chip analysis when a file is dropped", async () => {
    renderPanel();
    const file = new File(["%PDF"], "kahn-cerf-88.pdf", { type: "application/pdf" });
    dropFile(file);

    await waitFor(() => expect(analyzeDroppedFileMock).toHaveBeenCalledTimes(1));
    expect(analyzeDroppedFileMock.mock.calls[0][0]).toBe(file);
    expect(analyzeDroppedFileMock.mock.calls[0][1]).toBe("document");
    expect(analyzeDroppedFileMock.mock.calls[0][2]).toBe("user-1");
  });

  it("renders orchestrator updates in the chip", async () => {
    renderPanel();
    dropFile(new File(["%PDF"], "kahn-cerf-88.pdf", { type: "application/pdf" }));
    await waitFor(() => expect(analyzeDroppedFileMock).toHaveBeenCalled());

    act(() => {
      chipDriver.onUpdate?.({ analysis: { factsLine: "PDF · 12 pages · 0.3 MB" }, analysisState: "analyzing" });
      chipDriver.onUpdate?.({ analysis: { title: "Kahn-Cerf Certificate", description: "A 1988 certificate." } });
    });

    expect(await screen.findByText("PDF · 12 pages · 0.3 MB")).toBeInTheDocument();
    expect(screen.getByText("Kahn-Cerf Certificate")).toBeInTheDocument();
  });

  it("aborts analysis and deletes the staged file when a chip is removed", async () => {
    renderPanel();
    dropFile(new File(["%PDF"], "kahn-cerf-88.pdf", { type: "application/pdf" }));
    await waitFor(() => expect(analyzeDroppedFileMock).toHaveBeenCalled());

    act(() => {
      chipDriver.onUpdate?.({ analysis: { uploadedFilePath: "user-1/staging/1-abc.pdf" }, uploadState: "done" });
    });

    fireEvent.click(screen.getByRole("button", { name: "Remove" }));

    await waitFor(() => expect(chipDriver.abort).toHaveBeenCalled());
    expect(removeStagedFileMock).toHaveBeenCalledWith("user-1/staging/1-abc.pdf");
  });

  it("passes chip analysis through to onAddContent for a single media item", async () => {
    const onAddContent = renderPanel();
    dropFile(new File(["aud"], "memo.m4a", { type: "audio/mp4" }));
    await waitFor(() => expect(analyzeDroppedFileMock).toHaveBeenCalled());

    chipDriver.resolveDone?.({
      uploadedFilePath: "user-1/staging/2-def.m4a",
      description: "Voice memo about the contract",
      transcription: "full transcript",
      factsLine: "Audio · 3:24",
    });

    fireEvent.click(screen.getByRole("button", { name: "Add to Stash" }));

    await waitFor(() => expect(onAddContent).toHaveBeenCalled());
    const [type, payload] = onAddContent.mock.calls[0];
    expect(type).toBe("audio");
    expect(payload.uploadedFilePath).toBe("user-1/staging/2-def.m4a");
    expect(payload.description).toBe("Voice memo about the contract");
    expect(payload.content).toBe("full transcript");
    expect(payload.title).toBe("memo.m4a");
  });
});
