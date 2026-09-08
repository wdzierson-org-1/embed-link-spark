import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from '@/components/ui/alert-dialog';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import { useToast } from '@/hooks/use-toast';

// Settings → Your Information → Delete account. The edge function does the
// work (Stripe cancel → storage purge → auth delete, contract in
// docs/PLATFORM_API.md); this is the type-to-confirm gate in front of it.
const CONFIRM_WORD = 'DELETE';

const DeleteAccountSection = () => {
  const [open, setOpen] = useState(false);
  const [confirmation, setConfirmation] = useState('');
  const [deleting, setDeleting] = useState(false);
  const { signOut } = useAuth();
  const { toast } = useToast();
  const navigate = useNavigate();

  const handleOpenChange = (next: boolean) => {
    if (deleting) return;
    setOpen(next);
    if (!next) setConfirmation('');
  };

  const handleDelete = async () => {
    setDeleting(true);
    const { data, error } = await supabase.functions.invoke('delete-account', { method: 'POST' });
    if (error || !data?.deleted) {
      setDeleting(false);
      toast({
        title: "Couldn't delete your account",
        description: error?.message ?? data?.error ?? 'Nothing was removed. Please try again.',
        variant: 'destructive',
      });
      return;
    }
    // The auth user is gone server-side; drop this device's session and leave.
    await signOut();
    toast({
      title: 'Your account has been deleted',
      description: 'Everything you saved is gone. Thanks for trying Stash.',
    });
    navigate('/');
  };

  return (
    <Card className="border-[#c93a3a]/25">
      <CardHeader>
        <CardTitle>Delete account</CardTitle>
        <CardDescription>
          Permanently deletes your account and everything in it: every item, file, transcript, note, and
          conversation. Your phone number is unlinked and any subscription is canceled. This cannot be
          undone.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <AlertDialog open={open} onOpenChange={handleOpenChange}>
          <AlertDialogTrigger asChild>
            <Button variant="destructive">Delete my account</Button>
          </AlertDialogTrigger>
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>Delete your account?</AlertDialogTitle>
              <AlertDialogDescription>
                This removes your whole stash and signs you out everywhere. Type{' '}
                <span className="font-mono font-semibold text-[#22262f]">{CONFIRM_WORD}</span> to confirm.
              </AlertDialogDescription>
            </AlertDialogHeader>
            <Input
              value={confirmation}
              onChange={(e) => setConfirmation(e.target.value)}
              placeholder={CONFIRM_WORD}
              aria-label={`Type ${CONFIRM_WORD} to confirm`}
              autoComplete="off"
              autoCapitalize="characters"
              disabled={deleting}
            />
            <AlertDialogFooter>
              <AlertDialogCancel disabled={deleting}>Cancel</AlertDialogCancel>
              <AlertDialogAction
                disabled={confirmation !== CONFIRM_WORD || deleting}
                onClick={(e) => {
                  // Keep the dialog open while the request runs; success navigates away.
                  e.preventDefault();
                  handleDelete();
                }}
                className="bg-[#c93a3a] text-white hover:bg-[#b23232]"
              >
                {deleting ? 'Deleting…' : 'Delete everything'}
              </AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
      </CardContent>
    </Card>
  );
};

export default DeleteAccountSection;
