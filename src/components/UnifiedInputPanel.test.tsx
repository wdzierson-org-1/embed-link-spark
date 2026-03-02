import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import UnifiedInputPanel from "./UnifiedInputPanel";

const { invokeMock } = vi.hoisted(() => ({
  invokeMock: vi.fn(),
}));

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

    const input = screen.getByPlaceholderText(
      "What's on your mind? Drop files, paste links, or just start typing..."
    );

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

  it("shows a loading indicator immediately and keeps enriching after fast metadata", async () => {
    let resolveFast: ((value: unknown) => void) | undefined;
    const fastPromise = new Promise((resolve) => {
      resolveFast = resolve;
    });

    let resolveDeep: ((value: unknown) => void) | undefined;
    const deepPromise = new Promise((resolve) => {
      resolveDeep = resolve;
    });

    invokeMock.mockImplementation((_name: string, payload: { body: { fastOnly?: boolean } }) => {
      if (payload.body.fastOnly) {
        return fastPromise;
      }

      return deepPromise;
    });

    render(
      <UnifiedInputPanel
        isInputUICollapsed={false}
        onToggleInputUI={vi.fn()}
        onAddContent={vi.fn().mockResolvedValue(undefined)}
        getSuggestedTags={vi.fn().mockResolvedValue([])}
      />
    );

    const input = screen.getByPlaceholderText(
      "What's on your mind? Drop files, paste links, or just start typing..."
    );

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
    expect(await screen.findByText("Fetching more details...")).toBeInTheDocument();

    resolveDeep?.({
      data: {
        success: true,
        title: "Deep title",
        description: "Deep description",
      },
      error: null,
    });

    await waitFor(() => {
      expect(screen.getByText("Deep title")).toBeInTheDocument();
    });
  });

  it("submits available metadata even while deep enrichment is still pending", async () => {
    const onAddContent = vi.fn().mockResolvedValue(undefined);
    const deepPromise = new Promise(() => {
      // Intentionally never resolves to simulate long-running enrichment.
    });

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
      return deepPromise;
    });

    render(
      <UnifiedInputPanel
        isInputUICollapsed={false}
        onToggleInputUI={vi.fn()}
        onAddContent={onAddContent}
        getSuggestedTags={vi.fn().mockResolvedValue([])}
      />
    );

    const input = screen.getByPlaceholderText(
      "What's on your mind? Drop files, paste links, or just start typing..."
    );

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

    expect(invokeMock).toHaveBeenCalledWith("extract-link-metadata", {
      body: expect.objectContaining({
        url: "https://example.com",
        userId: "user-1",
        fastOnly: false,
      }),
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

    const input = screen.getByPlaceholderText(
      "What's on your mind? Drop files, paste links, or just start typing..."
    );
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

    const input = screen.getByPlaceholderText(
      "What's on your mind? Drop files, paste links, or just start typing..."
    );
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

    const input = screen.getByPlaceholderText(
      "What's on your mind? Drop files, paste links, or just start typing..."
    );
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

    const input = screen.getByPlaceholderText(
      "What's on your mind? Drop files, paste links, or just start typing..."
    );
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
