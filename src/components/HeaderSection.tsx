
import React from 'react';
import { useNavigate } from 'react-router-dom';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { Settings, LogOut, ExternalLink, Compass, Gauge } from 'lucide-react';
import { useAuth } from '@/hooks/useAuth';
import { useProfile } from '@/hooks/useProfile';
import { useIsAdmin } from '@/hooks/useIsAdmin';
import { St4shWordmark } from '@/components/brand/St4sh';

interface HeaderSectionProps {
  user: { email?: string; id?: string } | null | undefined;
}

const HeaderSection = ({ user }: HeaderSectionProps) => {
  const navigate = useNavigate();
  const { profile } = useProfile();
  // useAuth.signOut is scope:'local'. Calling the client's signOut with no
  // scope defaults to 'global' and deletes every session on the account — it
  // was logging the chrome extension (and any other device) out on each click.
  const { signOut } = useAuth();
  // Temporary admin dashboard — the entry only exists for admin_users rows
  const { isAdmin } = useIsAdmin();

  const getUserInitials = (email: string) => {
    return email?.charAt(0).toUpperCase() || 'U';
  };

  const handleSignOut = async () => {
    await signOut();
    navigate('/');
  };

  // The day, in the machine voice: what a terminal prints at the top of a session
  const currentDate = new Date()
    .toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric', year: 'numeric' })
    .replace(/,/g, '')
    .toLowerCase();

  return (
    // DESIGN-v2 navigation: white paper tabs on the paper, no bar and no shadow
    <div className="relative w-full">
      <div className="container mx-auto flex h-[68px] items-center justify-between px-4">
        <div className="flex items-center gap-3">
          <button
            onClick={() => navigate('/home')}
            aria-label="Stash, home"
            className="inline-flex h-9 items-center bg-white px-3 text-ink shadow-[0_0_0_1px_rgba(0,0,0,0.06)] transition-colors hover:bg-ink hover:text-white"
          >
            <St4shWordmark className="h-[14px]" />
          </button>
          <span className="hidden font-pixel text-pixel text-muted-foreground sm:inline">{currentDate}</span>
        </div>

        <div className="flex items-center gap-[3px]">
          {user && (
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <button
                  type="button"
                  aria-label="Account menu"
                  className="grid h-9 w-9 place-items-center bg-ink text-[15px] font-medium text-white transition-colors hover:bg-ink-soft data-[state=open]:bg-spot data-[state=open]:text-spot-on"
                >
                  {getUserInitials(user.email || '')}
                </button>
              </DropdownMenuTrigger>
              <DropdownMenuContent className="w-60" align="end" forceMount>
                <DropdownMenuLabel>
                  <span className="block truncate">{user.email}</span>
                </DropdownMenuLabel>
                <DropdownMenuSeparator />
                <DropdownMenuItem onClick={() => navigate('/settings')}>
                  <Settings className="mr-2 h-4 w-4" />
                  Settings
                </DropdownMenuItem>
                <DropdownMenuItem onClick={() => navigate('/discover')}>
                  <Compass className="mr-2 h-4 w-4" />
                  Discover
                </DropdownMenuItem>
                {isAdmin && (
                  <DropdownMenuItem onClick={() => navigate('/admin')}>
                    <Gauge className="mr-2 h-4 w-4" />
                    Admin
                  </DropdownMenuItem>
                )}
                <DropdownMenuItem onClick={() => window.open(`/feed/${profile?.username || user.id}`, '_blank')}>
                  <ExternalLink className="mr-2 h-4 w-4" />
                  Preview public feed
                </DropdownMenuItem>
                <DropdownMenuSeparator />
                <DropdownMenuItem onClick={handleSignOut}>
                  <LogOut className="mr-2 h-4 w-4" />
                  Sign out
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          )}
        </div>
      </div>
    </div>
  );
};

export default HeaderSection;
