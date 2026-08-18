import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import UnifiedInputPanel from "./UnifiedInputPanel";
import type { CaptureEditorHandle } from "@/components/capture/CaptureEditor";
import type { JSONContent } from "novel";

const { invokeMock, analyzeDroppedFileMock, removeStagedFileMock, chipDriver, editorDriver, toastMock } = vi.hoisted(() => {
  const driver: {
    onUpdate?: (update: unknown) => void;
    resolveDone?: (analysis: unknown) => void;
    abort: ReturnType<typeof vi.fn>;
  } = { abort: vi.fn() };
  const editor: {
    /** Set a rich doc that the stub returns from getJSON (emits a change) */
    setDoc?: (doc: unknown, plainText: string) => void;
  } = {};
  return {
    invokeMock: vi.fn(),
    removeStagedFileMock: vi.fn().mockResolvedValue(undefined),
    chipDriver: driver,
    editorDriver: editor,
    toastMock: vi.fn(),
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
  useToast: () => ({ toast: toastMock }),
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

// The real CaptureEditor is a Novel/Tiptap contenteditable, which jsdom can't
// drive through fireEvent. The stub honors the same contract: a textbox that
// reports doc changes, plus an imperative handle the panel reads at submit.
vi.mock("@/components/capture/CaptureEditor", async () => {
  const React = await import("react");

  const textToDoc = (text: string): JSONContent => ({
    type: "doc",
    content: (text ? text.split("\n") : [""]).map((line) => ({
      type: "paragraph",
      content: line ? [{ type: "text", text: line }] : [],
    })),
  });

  interface CaptureEditorStubProps {
    onDocChange: (payload: { plainText: string; isEmpty: boolean }) => void;
  }

  const CaptureEditorStub = React.forwardRef<CaptureEditorHandle, CaptureEditorStubProps>((props, ref) => {
    const [value, setValue] = React.useState("");
    const [docOverride, setDocOverride] = React.useState<JSONContent | null>(null);
    const valueRef = React.useRef(value);
    valueRef.current = value;
    const docOverrideRef = React.useRef(docOverride);
    docOverrideRef.current = docOverride;

    editorDriver.setDoc = (doc: unknown, plainText: string) => {
      setDocOverride(doc as JSONContent);
      setValue(plainText);
      props.onDocChange({ plainText, isEmpty: plainText.trim().length === 0 });
    };

    React.useImperativeHandle(ref, () => ({
      getJSON: () => docOverrideRef.current ?? textToDoc(valueRef.current),
      clear: () => {
        setValue("");
        setDocOverride(null);
        props.onDocChange({ plainText: "", isEmpty: true });
      },
      setJSON: (doc: JSONContent) => {
        setDocOverride(doc);
      },
      insertText: (text: string) => {
        const next = valueRef.current ? `${valueRef.current} ${text}` : text;
        setValue(next);
        props.onDocChange({ plainText: next, isEmpty: next.trim().length === 0 });
      },
      focus: () => {},
      isEmpty: () => valueRef.current.trim().length === 0 && !docOverrideRef.current,
    }));

    return React.createElement("textarea", {
      value,
      onChange: (e: React.ChangeEvent<HTMLTextAreaElement>) => {
        setValue(e.target.value);
        setDocOverride(null);
        props.onDocChange({
          plainText: e.target.value,
          isEmpty: e.target.value.trim().length === 0,
        });
      },
    });
  });
  CaptureEditorStub.displayName = "CaptureEditorStub";

  return { __esModule: true, default: CaptureEditorStub };
});

const renderPanel = (onAddContent = vi.fn().mockResolvedValue(undefined)) => {
  render(
    <UnifiedInputPanel
      onAddContent={onAddContent}
      getSuggestedTags={vi.fn().mockResolvedValue([])}
    />
  );
  return onAddContent;
};

describe("UnifiedInputPanel", () => {
  let fetchSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    vi.clearAllMocks();
    fetchSpy = vi.spyOn(globalThis, "fetch").mockRejectedValue(new Error("network disabled in test"));
  });

  afterEach(() => {
    fetchSpy.mockRestore();
  });

  it("stores the note as content (annotation), keeps og description, and stamps flavor", async () => {
    invokeMock.mockResolvedValue({
      data: { success: true, title: "Example", description: "OG description" },
      error: null,
    });
    const onAddContent = renderPanel();

    const input = screen.getByRole("textbox");
    fireEvent.change(input, { target: { value: "great read https://example.com" } });

    await waitFor(() => expect(invokeMock).toHaveBeenCalled());

    fireEvent.click(screen.getByRole("button", { name: "Add to Stash" }));

    await waitFor(() => expect(onAddContent).toHaveBeenCalled());
    const [type, payload] = onAddContent.mock.calls[0];
    expect(type).toBe("link");
    // URL stripped from the note; note is the annotation in content
    expect(payload.content).toBe("great read");
    expect(payload.description).toBe("OG description");
    expect(payload.attributes.link.flavor).toBe("generic");
  });

  it("sends no content when the note text is only the URL", async () => {
    invokeMock.mockResolvedValue({
      data: { success: true, title: "Example", description: "OG description" },
      error: null,
    });
    const onAddContent = renderPanel();

    const input = screen.getByRole("textbox");
    fireEvent.change(input, { target: { value: "https://example.com" } });

    await waitFor(() => expect(invokeMock).toHaveBeenCalled());

    fireEvent.click(screen.getByRole("button", { name: "Add to Stash" }));

    await waitFor(() => expect(onAddContent).toHaveBeenCalled());
    const [, payload] = onAddContent.mock.calls[0];
    expect(payload.content).toBeUndefined();
    expect(payload.description).toBe("OG description");
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

    renderPanel();

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

    renderPanel();

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

    renderPanel();

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

    const onAddContent = renderPanel();

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

    renderPanel();

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

    renderPanel();

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

    renderPanel();

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

    renderPanel();

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
    renderPanel();

    const panelShell = screen.getByTestId("input-panel-shell");
    expect(panelShell.className).toContain("rounded-[6px]");
  });

  it("has no minimize control on the capture panel", () => {
    renderPanel();

    expect(screen.queryByRole("button", { name: /add something/i })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /minimize/i })).not.toBeInTheDocument();
  });

  it("saves a rich note (task list) as Novel JSON", async () => {
    const onAddContent = renderPanel();

    const richDoc: JSONContent = {
      type: "doc",
      content: [
        {
          type: "taskList",
          content: [
            {
              type: "taskItem",
              attrs: { checked: false },
              content: [{ type: "paragraph", content: [{ type: "text", text: "buy milk" }] }],
            },
          ],
        },
      ],
    };

    act(() => {
      editorDriver.setDoc?.(richDoc, "buy milk");
    });

    fireEvent.click(screen.getByRole("button", { name: "Add to Stash" }));

    await waitFor(() => expect(onAddContent).toHaveBeenCalled());
    const [type, payload] = onAddContent.mock.calls[0];
    expect(type).toBe("text");
    const parsed = JSON.parse(payload.content);
    expect(parsed.type).toBe("doc");
    expect(parsed.content[0].type).toBe("taskList");
  });

  it("keeps a simple note as plain text", async () => {
    const onAddContent = renderPanel();

    const input = screen.getByRole("textbox");
    fireEvent.change(input, { target: { value: "just a quick thought" } });

    fireEvent.click(screen.getByRole("button", { name: "Add to Stash" }));

    await waitFor(() => expect(onAddContent).toHaveBeenCalled());
    const [type, payload] = onAddContent.mock.calls[0];
    expect(type).toBe("text");
    expect(payload.content).toBe("just a quick thought");
  });
});

describe("UnifiedInputPanel location tagging", () => {
  let fetchSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    vi.clearAllMocks();
    fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue({
      ok: true,
      json: async () => ({ city: "Brooklyn", principalSubdivision: "New York" }),
    } as Response);
    Object.defineProperty(navigator, "geolocation", {
      configurable: true,
      value: {
        getCurrentPosition: vi.fn((success: PositionCallback) =>
          success({
            coords: { latitude: 40.68, longitude: -73.97, accuracy: 25 },
          } as GeolocationPosition)
        ),
      },
    });
  });

  afterEach(() => {
    fetchSpy.mockRestore();
  });

  it("resolves and previews the location when the pin is toggled on", async () => {
    renderPanel();

    fireEvent.click(screen.getByRole("button", { name: "Include your location" }));

    expect(await screen.findByText("posted from Brooklyn, New York")).toBeInTheDocument();
  });

  it("stores location only as structured attributes — no text line in the note", async () => {
    const onAddContent = renderPanel();

    fireEvent.click(screen.getByRole("button", { name: "Include your location" }));
    await screen.findByText("posted from Brooklyn, New York");

    const input = screen.getByRole("textbox");
    fireEvent.change(input, { target: { value: "morning pages" } });

    fireEvent.click(screen.getByRole("button", { name: "Add to Stash" }));

    await waitFor(() => expect(onAddContent).toHaveBeenCalled());
    const [type, payload] = onAddContent.mock.calls[0];
    expect(type).toBe("text");
    expect(payload.content).toBe("morning pages");
    expect(payload.attributes.location).toEqual(
      expect.objectContaining({
        label: "Brooklyn, New York",
        latitude: 40.68,
        longitude: -73.97,
        accuracy_m: 25,
        city: "Brooklyn",
        region: "New York",
        source: "browser-geolocation",
      })
    );
    expect(payload.attributes.location.captured_at).toEqual(expect.any(String));
  });

  it("does not stamp location when the pin is off", async () => {
    const onAddContent = renderPanel();

    const input = screen.getByRole("textbox");
    fireEvent.change(input, { target: { value: "no location here" } });

    fireEvent.click(screen.getByRole("button", { name: "Add to Stash" }));

    await waitFor(() => expect(onAddContent).toHaveBeenCalled());
    const [, payload] = onAddContent.mock.calls[0];
    expect(payload.content).toBe("no location here");
    expect(payload.attributes).toBeUndefined();
  });
});

describe("UnifiedInputPanel file chips", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    chipDriver.onUpdate = undefined;
    chipDriver.resolveDone = undefined;
  });

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
    // Transcript is source material (page_body); content stays the user's note
    expect(payload.page_body).toBe("full transcript");
    expect(payload.content).toBeUndefined();
    expect(payload.title).toBe("memo.m4a");
    expect(payload.attributes.media.file_name).toBe("memo.m4a");
  });

  it("keeps a note with a single media item (no collection)", async () => {
    const onAddContent = renderPanel();
    dropFile(new File(["aud"], "memo.m4a", { type: "audio/mp4" }));
    await waitFor(() => expect(analyzeDroppedFileMock).toHaveBeenCalled());

    chipDriver.resolveDone?.({
      uploadedFilePath: "user-1/staging/2-def.m4a",
      description: "Voice memo about the contract",
      transcription: "full transcript",
    });

    const input = screen.getByRole("textbox");
    fireEvent.change(input, { target: { value: "call notes from tuesday" } });

    fireEvent.click(screen.getByRole("button", { name: "Add to Stash" }));

    await waitFor(() => expect(onAddContent).toHaveBeenCalledTimes(1));
    const [type, payload] = onAddContent.mock.calls[0];
    expect(type).toBe("audio");
    expect(payload.content).toBe("call notes from tuesday");
    expect(payload.page_body).toBe("full transcript");
  });
});

describe("UnifiedInputPanel single-object captures", () => {
  let fetchSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    vi.clearAllMocks();
    fetchSpy = vi.spyOn(globalThis, "fetch").mockRejectedValue(new Error("network disabled in test"));
  });

  afterEach(() => {
    fetchSpy.mockRestore();
  });

  it("splits multiple links into individual items with the note on the first", async () => {
    invokeMock.mockResolvedValue({
      data: { success: true, title: "Example", description: "OG description" },
      error: null,
    });
    const onAddContent = renderPanel();

    const input = screen.getByRole("textbox");
    fireEvent.change(input, {
      target: { value: "reading list https://a.example.com https://b.example.com" },
    });

    await waitFor(() => expect(invokeMock).toHaveBeenCalled());

    fireEvent.click(screen.getByRole("button", { name: "Add to Stash" }));

    await waitFor(() => expect(onAddContent).toHaveBeenCalledTimes(2));
    const [firstType, firstPayload] = onAddContent.mock.calls[0];
    const [secondType, secondPayload] = onAddContent.mock.calls[1];
    expect(firstType).toBe("link");
    expect(secondType).toBe("link");
    expect(firstPayload.url).toBe("https://a.example.com");
    expect(firstPayload.content).toBe("reading list");
    expect(secondPayload.url).toBe("https://b.example.com");
    expect(secondPayload.content).toBeUndefined();
    expect(onAddContent.mock.calls.every(([type]) => type !== "collection")).toBe(true);

    expect(toastMock).toHaveBeenCalledWith(
      expect.objectContaining({ title: "Saved as 2 items" })
    );
  });

  it("never creates a collection for mixed link + file captures", async () => {
    invokeMock.mockResolvedValue({
      data: { success: true, title: "Example", description: "OG description" },
      error: null,
    });
    const onAddContent = renderPanel();

    const input = screen.getByRole("textbox");
    fireEvent.change(input, { target: { value: "https://a.example.com" } });
    await waitFor(() => expect(invokeMock).toHaveBeenCalled());

    const dropzone = screen.getByTestId("capture-dropzone");
    fireEvent.drop(dropzone, {
      dataTransfer: { files: [new File(["%PDF"], "notes.pdf", { type: "application/pdf" })] },
    });
    await waitFor(() => expect(analyzeDroppedFileMock).toHaveBeenCalled());
    chipDriver.resolveDone?.({ uploadedFilePath: "user-1/staging/9-xyz.pdf" });

    fireEvent.click(screen.getByRole("button", { name: "Add to Stash" }));

    await waitFor(() => expect(onAddContent).toHaveBeenCalledTimes(2));
    const types = onAddContent.mock.calls.map(([type]) => type);
    expect(types).toEqual(["link", "document"]);
  });
});
