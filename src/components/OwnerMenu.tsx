import { LogOut, ExternalLink, Globe } from 'lucide-react';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { useAuth } from '@/hooks/useAuth';

interface OwnerMenuProps {
  profile: {
    username: string;
    display_name?: string;
    avatar_url?: string;
  };
}

export const OwnerMenu = ({ profile }: OwnerMenuProps) => {
  const { signOut } = useAuth();

  const handleSignOut = async () => {
    try {
      await signOut();
    } catch (error) {
      console.error('Error signing out:', error);
    }
  };

  const handleViewPublic = () => {
    // Open the public version in a new tab by removing any authentication state
    const publicUrl = `${window.location.origin}/feed/${profile.username}`;
    window.open(publicUrl, '_blank');
  };

  const handleOpenPublicFeed = () => {
    const publicFeedUrl = `${window.location.origin}/public-feed`;
    window.open(publicFeedUrl, '_blank');
  };

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <button className="flex items-center gap-2 p-2 rounded-full hover:bg-accent transition-colors">
          <Avatar className="h-8 w-8">
            <AvatarImage src={profile.avatar_url} />
            <AvatarFallback>
              {(profile.display_name || profile.username).charAt(0).toUpperCase()}
            </AvatarFallback>
          </Avatar>
        </button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-48">
        <div className="px-2 py-1.5 text-sm font-medium">
          {profile.display_name || profile.username}
        </div>
        <div className="px-2 py-1.5 text-xs text-muted-foreground">
          @{profile.username}
        </div>
        <DropdownMenuSeparator />
        <DropdownMenuItem onClick={handleViewPublic}>
          <ExternalLink className="h-4 w-4 mr-2" />
          View public version
        </DropdownMenuItem>
        <DropdownMenuItem onClick={handleOpenPublicFeed}>
          <Globe className="h-4 w-4 mr-2" />
          Open public feed
        </DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuItem onClick={handleSignOut}>
          <LogOut className="h-4 w-4 mr-2" />
          Sign out
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
};