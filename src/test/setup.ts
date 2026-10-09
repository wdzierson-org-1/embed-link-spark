import "@testing-library/jest-dom/vitest";

// jsdom has no ResizeObserver; Radix poppers (menus, tooltips) measure with one as they mount
if (typeof globalThis.ResizeObserver === "undefined") {
  class ResizeObserverStub {
    observe() {}
    unobserve() {}
    disconnect() {}
  }
  globalThis.ResizeObserver = ResizeObserverStub as unknown as typeof ResizeObserver;
}
