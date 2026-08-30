import { render, waitFor } from "@testing-library/react";
import Auth from "./Auth";

const navigateMock = vi.fn();

// Mutable auth state so each test can vary who is "signed in"
const authState: {
  user: { id: string; is_anonymous?: boolean } | null;
} = { user: null };

vi.mock("react-router-dom", () => ({
  useNavigate: () => navigateMock,
  useSearchParams: () => [new URLSearchParams()],
}));

vi.mock("@/hooks/useAuth", () => ({
  useAuth: () => ({
    user: authState.user,
    signIn: vi.fn(),
    signUp: vi.fn(),
  }),
}));

vi.mock("@/hooks/usePhoneNumber", () => ({
  usePhoneNumber: () => ({ registerPhoneNumber: vi.fn() }),
}));

vi.mock("@/hooks/use-toast", () => ({
  useToast: () => ({ toast: vi.fn() }),
}));

vi.mock("@/integrations/supabase/client", () => ({
  supabase: { from: vi.fn() },
}));

describe("Auth already-signed-in redirect", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authState.user = null;
  });

  it("does not redirect when nobody is signed in", () => {
    render(<Auth />);
    expect(navigateMock).not.toHaveBeenCalled();
  });

  it("redirects a real signed-in user to /home", async () => {
    authState.user = { id: "user-1" };
    render(<Auth />);
    await waitFor(() => expect(navigateMock).toHaveBeenCalledWith("/home"));
  });

  it("keeps an anonymous try-stash session on the sign-in form", () => {
    // A lingering signInAnonymously() session must not bounce the visitor:
    // Index sends anonymous users back to "/", so redirecting here loops
    // /auth → /home → / and makes signing in impossible.
    authState.user = { id: "anon-1", is_anonymous: true };
    render(<Auth />);
    expect(navigateMock).not.toHaveBeenCalled();
  });
});
