import { humanizeUrlSlug, isWeakLinkMetadata } from "./urlInference";

describe("humanizeUrlSlug", () => {
  it("turns an article slug into a readable title", () => {
    expect(
      humanizeUrlSlug("https://www.nytimes.com/2026/08/09/us/politics/bobby-zhou-trump-crypto.html")
    ).toBe("Bobby Zhou Trump Crypto");
  });

  it("strips trailing content ids from Medium-style slugs", () => {
    expect(
      humanizeUrlSlug("https://medium.com/@someone/will-claude-design-replace-designers-f92623f3befe")
    ).toBe("Will Claude Design Replace Designers");
  });

  it("returns null when the URL has no meaningful slug", () => {
    expect(humanizeUrlSlug("https://example.com/")).toBeNull();
    expect(humanizeUrlSlug("https://example.com/a1")).toBeNull();
  });
});

describe("isWeakLinkMetadata", () => {
  it("treats hostname-only titles as weak", () => {
    expect(isWeakLinkMetadata({ title: "www.nytimes.com" }, "https://www.nytimes.com/x")).toBe(true);
    expect(isWeakLinkMetadata({ title: "nytimes.com" }, "https://www.nytimes.com/x")).toBe(true);
  });

  it("treats missing titles as weak and real titles as strong", () => {
    expect(isWeakLinkMetadata(undefined, "https://a.com/x")).toBe(true);
    expect(isWeakLinkMetadata({ title: "A Real Headline", description: "d" }, "https://a.com/x")).toBe(false);
  });

  it("treats a title without description or image as weak", () => {
    expect(isWeakLinkMetadata({ title: "A Real Headline" }, "https://a.com/x")).toBe(true);
  });
});
