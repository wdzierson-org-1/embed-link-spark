
import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Avatar, AvatarFallback } from "@/components/ui/avatar"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { LogOut, Settings } from 'lucide-react';
import { useAuth } from '@/hooks/useAuth';
import SettingsModal from '@/components/SettingsModal';

const Navbar = () => {
  const { user, signOut } = useAuth();
  const navigate = useNavigate();
  const [showSettings, setShowSettings] = useState(false);

  const handleSignOut = async () => {
    await signOut();
    navigate('/auth');
  };

  const getUserInitials = (email: string) => {
    return email?.charAt(0).toUpperCase() || 'U';
  };

  return (
    <>
      <nav className="bg-white shadow-sm border-b">
        <div className="container mx-auto px-4">
          <div className="flex justify-between items-center h-16">
            <div className="flex items-center space-x-4">
              <h1 className="text-xl font-bold text-primary">Stash</h1>
            </div>

            <div className="flex items-center space-x-4">
              {user ? (
                <DropdownMenu>
                  <DropdownMenuTrigger asChild>
                    <Button variant="ghost" className="relative h-10 w-10 rounded-full p-0">
                      <Avatar className="h-10 w-10 bg-purple-400">
                        <AvatarFallback className="bg-purple-400 text-white font-medium">
                          {getUserInitials(user.email || '')}
                        </AvatarFallback>
                      </Avatar>
                    </Button>
                  </DropdownMenuTrigger>
                  <DropdownMenuContent className="w-56" align="end" forceMount>
                    <DropdownMenuLabel className="font-normal">
                      <div className="flex flex-col space-y-1">
                        <p className="text-sm font-medium leading-none">
                          {user.email}
                        </p>
                      </div>
                    </DropdownMenuLabel>
                    <DropdownMenuSeparator />
                    <DropdownMenuItem onClick={() => setShowSettings(true)}>
                      <Settings className="mr-2 h-4 w-4" />
                      Settings
                    </DropdownMenuItem>
                    <DropdownMenuItem onClick={handleSignOut}>
                      <LogOut className="mr-2 h-4 w-4" />
                      Sign out
                    </DropdownMenuItem>
                  </DropdownMenuContent>
                </DropdownMenu>
              ) : (
                <Button onClick={() => navigate('/auth')}>
                  Sign In
                </Button>
              )}
            </div>
          </div>
        </div>
      </nav>

      <SettingsModal 
        open={showSettings} 
        onOpenChange={setShowSettings}
      />
    </>
  );
};

export default Navbar;
