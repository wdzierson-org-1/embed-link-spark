// src/components/settings/ConnectedAgentsSettings.tsx
import { formatDistanceToNow } from 'date-fns';
import { Copy, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription,
  AlertDialogFooter, AlertDialogHeader, AlertDialogTitle, AlertDialogTrigger,
} from '@/components/ui/alert-dialog';
import { useToast } from '@/hooks/use-toast';
import { useConnectedAgents } from '@/hooks/useConnectedAgents';
import { MCP_SERVER_URL, describeAgentActivity } from '@/utils/agentActivity';

const relative = (iso: string) => formatDistanceToNow(new Date(iso), { addSuffix: true });

const ConnectedAgentsSettings = () => {
  const { toast } = useToast();
  const { active, activity, loading, revoke, revoking, clientNameFor } = useConnectedAgents();

  const copyUrl = () => {
    navigator.clipboard.writeText(MCP_SERVER_URL);
    toast({ title: 'Copied', description: 'Paste it into your agent as a remote MCP server.' });
  };

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>Connect an agent</CardTitle>
          <CardDescription>
            Let an AI agent you trust search your stash. Agents get answers, never copies: they can search
            and read items one at a time, can't change anything, and every request is logged here.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-5">
          <div className="flex items-center gap-2">
            <code className="flex-1 truncate rounded-xl border border-black/[0.07] bg-[rgba(20,22,30,0.03)] px-3 py-2 text-sm text-[#22262f]">
              {MCP_SERVER_URL}
            </code>
            <Button variant="outline" size="sm" onClick={copyUrl} aria-label="Copy MCP server URL">
              <Copy className="h-4 w-4" />
            </Button>
          </div>
          <div className="space-y-3 text-sm text-muted-foreground">
            <p><span className="font-medium text-foreground">Claude (web or desktop):</span> Settings → Connectors → Add custom connector → paste the URL → Connect. Claude sends you here to approve.</p>
            <p><span className="font-medium text-foreground">Claude Code:</span> <code className="rounded bg-[rgba(20,22,30,0.05)] px-1 py-0.5">claude mcp add --transport http stash {MCP_SERVER_URL}</code></p>
            <p><span className="font-medium text-foreground">Other agents:</span> any client that supports remote MCP servers with OAuth sign-in.</p>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Connected</CardTitle>
          <CardDescription>Agents that can search your stash right now.</CardDescription>
        </CardHeader>
        <CardContent>
          {loading ? (
            <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
          ) : active.length === 0 ? (
            <p className="text-sm text-muted-foreground">No agents connected yet. Paste the URL above into one to start.</p>
          ) : (
            <ul className="divide-y divide-black/[0.06]">
              {active.map((g) => (
                <li key={g.id} className="flex items-center justify-between gap-4 py-3">
                  <div className="min-w-0">
                    <p className="truncate text-sm font-medium text-foreground">{g.client_name}</p>
                    <p className="text-xs text-muted-foreground">
                      Connected {relative(g.created_at)}
                      {g.last_used_at ? ` · last used ${relative(g.last_used_at)}` : ' · not used yet'}
                    </p>
                  </div>
                  <AlertDialog>
                    <AlertDialogTrigger asChild>
                      <Button variant="outline" size="sm" disabled={revoking === g.id}>
                        {revoking === g.id ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Revoke'}
                      </Button>
                    </AlertDialogTrigger>
                    <AlertDialogContent>
                      <AlertDialogHeader>
                        <AlertDialogTitle>Disconnect {g.client_name}?</AlertDialogTitle>
                        <AlertDialogDescription>
                          It loses access immediately. You can connect it again any time.
                        </AlertDialogDescription>
                      </AlertDialogHeader>
                      <AlertDialogFooter>
                        <AlertDialogCancel>Keep connected</AlertDialogCancel>
                        <AlertDialogAction onClick={() => revoke(g)}>Revoke access</AlertDialogAction>
                      </AlertDialogFooter>
                    </AlertDialogContent>
                  </AlertDialog>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Activity</CardTitle>
          <CardDescription>Every search and read, newest first.</CardDescription>
        </CardHeader>
        <CardContent>
          {loading ? (
            <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
          ) : activity.length === 0 ? (
            <p className="text-sm text-muted-foreground">No activity yet. Once an agent connects, every search and read shows up here.</p>
          ) : (
            <ul className="divide-y divide-black/[0.06]">
              {activity.map((row) => (
                <li key={row.id} className="flex items-start justify-between gap-4 py-2.5">
                  <p className="text-sm text-foreground">{describeAgentActivity(row, clientNameFor(row.client_id))}</p>
                  <p className="shrink-0 text-xs text-muted-foreground">{relative(row.created_at)}</p>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>
    </div>
  );
};

export default ConnectedAgentsSettings;
