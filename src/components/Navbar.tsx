
import { useAuth } from '@/hooks/useAuth';
import { Button } from '@/components/ui/button';
import { LogOut, MessageSquare, Search } from 'lucide-react';

interface NavbarProps {
  onAddContent: () => void; // Keep for compatibility but not used
  onOpenChat: () => void;
  onOpenSearch: () => void;
}

const Navbar = ({ onOpenChat, onOpenSearch }: NavbarProps) => {
  const { user, signOut } = useAuth();

  return (
    <nav className="border-b bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60">
      <div className="container mx-auto px-4 h-16 flex items-center justify-between">
        <div className="flex items-center space-x-4">
          <h1 className="text-xl font-bold">Stash</h1>
          <span className="text-sm text-muted-foreground">
            {user?.email}
          </span>
        </div>
        
        <div className="flex items-center space-x-2">
          <Button
            variant="outline"
            size="sm"
            onClick={onOpenSearch}
            className="hidden sm:flex"
          >
            <Search className="h-4 w-4 mr-2" />
            Search
          </Button>
          
          <Button
            variant="outline"
            size="sm"
            onClick={onOpenChat}
          >
            <MessageSquare className="h-4 w-4 mr-2" />
            Chat
          </Button>
          
          <Button
            variant="ghost"
            size="sm"
            onClick={signOut}
          >
            <LogOut className="h-4 w-4" />
          </Button>
        </div>
      </div>
    </nav>
  );
};

export default Navbar;
