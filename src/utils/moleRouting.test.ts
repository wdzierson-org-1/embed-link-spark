import { classifyMoleMessage } from "./moleRouting";

describe("classifyMoleMessage", () => {
  it("routes a bare URL to save-url", () => {
    expect(classifyMoleMessage("https://example.com/article")).toEqual({
      kind: "save-url",
      url: "https://example.com/article",
      note: "",
    });
  });

  it("routes a URL with surrounding text to save-url with the text as note", () => {
    expect(
      classifyMoleMessage("great read on scraping https://example.com/anti-bot")
    ).toEqual({
      kind: "save-url",
      url: "https://example.com/anti-bot",
      note: "great read on scraping",
    });
  });

  it("routes remember:/save:/note: prefixes to save-note", () => {
    expect(classifyMoleMessage("remember: the wifi password is trout123")).toEqual({
      kind: "save-note",
      note: "the wifi password is trout123",
    });
    expect(classifyMoleMessage("Save: pick up dry cleaning Tuesday")).toEqual({
      kind: "save-note",
      note: "pick up dry cleaning Tuesday",
    });
  });

  it("routes plain text to ask", () => {
    expect(classifyMoleMessage("what did I save about browser automation?")).toEqual({
      kind: "ask",
    });
  });

  it("strips trailing punctuation from detected URLs", () => {
    expect(classifyMoleMessage("https://example.com/a,")).toEqual({
      kind: "save-url",
      url: "https://example.com/a",
      note: "",
    });
  });
});
