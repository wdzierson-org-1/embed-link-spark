import { render, screen } from "@testing-library/react";
import InputChip from "./InputChip";

vi.mock("@/integrations/supabase/client", () => ({
  SUPABASE_URL: "https://example.supabase.co",
}));

describe("InputChip file rendering", () => {
  beforeEach(() => {
    vi.stubGlobal("URL", Object.assign(Object.create(URL), {
      createObjectURL: vi.fn(() => "blob:mock"),
      revokeObjectURL: vi.fn(),
    }));
  });

  afterEach(() => vi.unstubAllGlobals());

  const baseContent = { name: "kahn-cerf-88.pdf", size: 0.3 * 1024 * 1024, type: "application/pdf" };

  it("shows filename, size, and analyzing state before any facts arrive", () => {
    render(
      <InputChip type="document" content={baseContent} onRemove={vi.fn()} analysisState="local" />
    );
    expect(screen.getByText("kahn-cerf-88.pdf")).toBeInTheDocument();
    expect(screen.getByText("0.3 MB")).toBeInTheDocument();
    expect(screen.getByText("Analyzing...")).toBeInTheDocument();
  });

  it("shows the facts line instead of bare size once local analysis lands", () => {
    render(
      <InputChip
        type="document"
        content={baseContent}
        onRemove={vi.fn()}
        analysisState="analyzing"
        fileAnalysis={{ factsLine: "PDF · 12 pages · 0.3 MB" }}
      />
    );
    expect(screen.getByText("PDF · 12 pages · 0.3 MB")).toBeInTheDocument();
    expect(screen.queryByText("0.3 MB")).not.toBeInTheDocument();
  });

  it("shows percentage progress for large uploads", () => {
    render(
      <InputChip
        type="video"
        content={{ name: "clip.mp4", size: 50 * 1024 * 1024, type: "video/mp4" }}
        onRemove={vi.fn()}
        analysisState="local"
        uploadState="uploading"
        uploadProgress={45}
      />
    );
    expect(screen.getByText("Uploading · 45%")).toBeInTheDocument();
  });

  it("shows spinner-only uploading text for small files", () => {
    render(
      <InputChip
        type="document"
        content={baseContent}
        onRemove={vi.fn()}
        analysisState="local"
        uploadState="uploading"
        uploadProgress={45}
      />
    );
    expect(screen.getByText("Uploading...")).toBeInTheDocument();
    expect(screen.queryByText("Uploading · 45%")).not.toBeInTheDocument();
  });

  it("renders AI title, description, and thumbnail when analysis is ready", () => {
    render(
      <InputChip
        type="document"
        content={baseContent}
        onRemove={vi.fn()}
        analysisState="ready"
        uploadState="done"
        fileAnalysis={{
          title: "Kahn-Cerf Internet Certificate",
          description: "A 1988 certificate signed by Vint Cerf.",
          factsLine: "PDF · 2 pages · 0.3 MB",
          thumbnailDataUrl: "data:image/png;base64,thumb",
        }}
      />
    );
    expect(screen.getByText("Kahn-Cerf Internet Certificate")).toBeInTheDocument();
    expect(screen.getByText("A 1988 certificate signed by Vint Cerf.")).toBeInTheDocument();
    expect(screen.queryByText("kahn-cerf-88.pdf")).not.toBeInTheDocument();
    expect(screen.queryByText("Analyzing...")).not.toBeInTheDocument();
    const thumb = document.querySelector('img[src="data:image/png;base64,thumb"]');
    expect(thumb).not.toBeNull();
  });

  it("notes save-time fallback when the staged upload failed", () => {
    render(
      <InputChip
        type="document"
        content={baseContent}
        onRemove={vi.fn()}
        analysisState="ready"
        uploadState="failed"
      />
    );
    expect(screen.getByText("Will upload when you save")).toBeInTheDocument();
  });
});
