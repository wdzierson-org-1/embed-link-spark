import { itemMatchesSearchQuery } from "./itemSearch";

describe("itemMatchesSearchQuery", () => {
  const baseItem = {
    title: "Trip planning",
    content: "Pack the tent",
    description: "Camping checklist",
    url: "https://example.com/camping",
    supplemental_note: "Borrow stove from Alex",
  };

  it("matches on title, content, description, and url", () => {
    expect(itemMatchesSearchQuery(baseItem, "trip")).toBe(true);
    expect(itemMatchesSearchQuery(baseItem, "tent")).toBe(true);
    expect(itemMatchesSearchQuery(baseItem, "checklist")).toBe(true);
    expect(itemMatchesSearchQuery(baseItem, "example.com")).toBe(true);
  });

  it("matches on supplemental_note", () => {
    expect(itemMatchesSearchQuery(baseItem, "stove")).toBe(true);
  });

  it("is case-insensitive and returns false for non-matches", () => {
    expect(itemMatchesSearchQuery(baseItem, "TRIP")).toBe(true);
    expect(itemMatchesSearchQuery(baseItem, "submarine")).toBe(false);
  });

  it("treats a blank query as a match and tolerates missing fields", () => {
    expect(itemMatchesSearchQuery({}, "  ")).toBe(true);
    expect(itemMatchesSearchQuery({}, "anything")).toBe(false);
  });
});
