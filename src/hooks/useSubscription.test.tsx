import { act, renderHook, waitFor } from "@testing-library/react";
import { ReactNode } from "react";
import { SubscriptionProvider, useSubscription } from "./useSubscription";

const { invokeMock } = vi.hoisted(() => ({ invokeMock: vi.fn() }));

vi.mock("@/integrations/supabase/client", () => ({
  supabase: { functions: { invoke: invokeMock } },
}));

const stableUser = { id: "user-1", email: "new@example.com" };

vi.mock("@/hooks/useAuth", () => ({
  useAuth: () => ({ user: stableUser }),
}));

vi.mock("@/hooks/use-toast", () => ({
  useToast: () => ({ toast: vi.fn() }),
}));

const wrapper = ({ children }: { children: ReactNode }) => (
  <SubscriptionProvider>{children}</SubscriptionProvider>
);

describe("useSubscription", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("creates the trial and re-checks when a fresh account has no subscription yet", async () => {
    let checkCalls = 0;
    invokeMock.mockImplementation((name: string) => {
      if (name === "check-subscription") {
        checkCalls += 1;
        if (checkCalls === 1) {
          return Promise.resolve({
            data: { subscribed: false, subscriptionStatus: null, hasStripeCustomer: false },
            error: null,
          });
        }
        return Promise.resolve({
          data: {
            subscribed: false,
            subscriptionStatus: "trialing",
            onTrial: true,
            daysLeftInTrial: 14,
            hasStripeCustomer: true,
          },
          error: null,
        });
      }
      if (name === "create-trial-subscription") {
        return Promise.resolve({ data: { success: true, status: "trialing" }, error: null });
      }
      return Promise.resolve({ data: null, error: null });
    });

    const { result } = renderHook(() => useSubscription(), { wrapper });

    await waitFor(() => {
      expect(result.current.subscriptionStatus).toBe("trialing");
    });

    const calledFunctions = invokeMock.mock.calls.map(([name]) => name);
    expect(calledFunctions).toContain("create-trial-subscription");
    expect(result.current.canAddContent).toBe(true);
  });

  it("does not block content actions while the first check is still in flight", () => {
    invokeMock.mockImplementation(() => new Promise(() => {}));

    const { result } = renderHook(() => useSubscription(), { wrapper });

    expect(result.current.loading).toBe(true);
    expect(result.current.canAddContent).toBe(true);
  });

  it("keeps the last known subscription when a later check fails transiently", async () => {
    let failChecks = false;
    invokeMock.mockImplementation((name: string) => {
      if (name === "check-subscription") {
        if (failChecks) {
          return Promise.resolve({ data: null, error: new Error("Edge Function returned a non-2xx status code") });
        }
        return Promise.resolve({
          data: { subscribed: true, subscriptionStatus: "active", hasStripeCustomer: true },
          error: null,
        });
      }
      return Promise.resolve({ data: null, error: null });
    });

    const { result } = renderHook(() => useSubscription(), { wrapper });

    await waitFor(() => {
      expect(result.current.subscriptionStatus).toBe("active");
    });

    failChecks = true;
    await act(async () => {
      await result.current.checkSubscription();
    });

    expect(result.current.subscriptionStatus).toBe("active");
    expect(result.current.canAddContent).toBe(true);
  });

  it("stays permissive when the very first check fails before any definitive answer", async () => {
    invokeMock.mockImplementation((name: string) => {
      if (name === "check-subscription") {
        return Promise.reject(new Error("Failed to fetch"));
      }
      return Promise.resolve({ data: null, error: null });
    });

    const { result } = renderHook(() => useSubscription(), { wrapper });

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    expect(result.current.canAddContent).toBe(true);
  });

  it("still blocks on a definitive not-subscribed answer", async () => {
    invokeMock.mockImplementation((name: string) => {
      if (name === "check-subscription") {
        return Promise.resolve({
          data: { subscribed: false, subscriptionStatus: "canceled", hasStripeCustomer: true },
          error: null,
        });
      }
      if (name === "create-trial-subscription") {
        return Promise.resolve({ data: { success: true }, error: null });
      }
      return Promise.resolve({ data: null, error: null });
    });

    const { result } = renderHook(() => useSubscription(), { wrapper });

    await waitFor(() => {
      expect(result.current.subscriptionStatus).toBe("canceled");
    });

    expect(result.current.canAddContent).toBe(false);
  });
});
