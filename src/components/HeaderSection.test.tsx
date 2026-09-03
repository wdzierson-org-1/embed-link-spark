import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import HeaderSection from "./HeaderSection";

const { navigateMock, authSignOutMock, rawSupabaseSignOutMock } = vi.hoisted(() => ({
  navigateMock: vi.fn(),
  authSignOutMock: vi.fn().mockResolvedValue(undefined),
  rawSupabaseSignOutMock: vi.fn().mockResolvedValue({ error: null }),
}));

vi.mock("react-router-dom", () => ({
  useNavigate: () => navigateMock,
}));

vi.mock("@/hooks/useAuth", () => ({
  useAuth: () => ({ signOut: authSignOutMock }),
}));

vi.mock("@/hooks/useProfile", () => ({
  useProfile: () => ({ profile: { username: "will" } }),
}));

vi.mock("@/integrations/supabase/client", () => ({
  supabase: { auth: { signOut: rawSupabaseSignOutMock } },
}));

vi.mock("@/components/StashWordmark", () => ({
  default: () => <div>Stash</div>,
}));

// Radix popper measures its content; jsdom has no ResizeObserver
beforeAll(() => {
  (globalThis as { ResizeObserver?: unknown }).ResizeObserver = class {
    observe() {}
    unobserve() {}
    disconnect() {}
  };
});

describe("HeaderSection sign out", () => {
  beforeEach(() => vi.clearAllMocks());

  it("signs out through useAuth (local scope) — never the raw global signOut", async () => {
    render(<HeaderSection user={{ email: "will@dzierson.com", id: "u1" }} />);

    // Open the account menu via keyboard (Radix opens on Enter) and pick Sign out
    const trigger = screen.getByRole("button", { name: /w/i, expanded: false });
    fireEvent.keyDown(trigger, { key: "Enter" });
    const item = await screen.findByRole("menuitem", { name: /sign out/i });
    fireEvent.click(item);

    await waitFor(() => expect(authSignOutMock).toHaveBeenCalledTimes(1));
    expect(rawSupabaseSignOutMock).not.toHaveBeenCalled();
    expect(navigateMock).toHaveBeenCalledWith("/");
  });
});

// Guard for the whole web app: a bare supabase.auth.signOut() defaults to
// scope 'global', which deletes every session on the account — the chrome
// extension's, iOS's, every other browser's. The 2026-08-21 fix missed a
// call site precisely because nothing enforced this. Sign-out must go
// through useAuth.signOut (scope: 'local').
describe("no global-scope sign-outs in src/", () => {
  const walk = (dir: string, out: string[] = []): string[] => {
    for (const name of readdirSync(dir)) {
      const full = join(dir, name);
      if (statSync(full).isDirectory()) walk(full, out);
      else if (/\.(ts|tsx)$/.test(name) && !/\.test\.tsx?$/.test(name)) out.push(full);
    }
    return out;
  };

  it("never calls supabase.auth.signOut() without an explicit local scope", () => {
    const offenders = walk(join(__dirname, "..")).filter((file) =>
      /auth\.signOut\(\s*\)/.test(readFileSync(file, "utf8"))
    );
    expect(offenders).toEqual([]);
  });
});
