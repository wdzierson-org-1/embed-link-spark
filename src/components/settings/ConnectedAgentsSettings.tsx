// src/components/settings/ConnectedAgentsSettings.tsx
import { formatDistanceToNow } from 'date-fns';
import { Copy } from 'lucide-react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription,
  AlertDialogFooter, AlertDialogHeader, AlertDialogTitle, AlertDialogTrigger,
} from '@/components/ui/alert-dialog';
import { MachineWindow, Spinner, StatusLine } from '@/components/machine/Machine';
import { useToast } from '@/hooks/use-toast';
import { useConnectedAgents } from '@/hooks/useConnectedAgents';
import { MCP_SERVER_URL, describeAgentActivity } from '@/utils/agentActivity';

const relative = (iso: string) => formatDistanceToNow(new Date(iso), { addSuffix: true });

/**
 * Connected agents (DESIGN-v2 §12): the MCP address as the one thing to take away, each
 * connected agent as a window, and every search and read as a log in Departure Mono.
 */
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
          {/* The address is the one thing to take away, so it's big, square and copyable */}
          <div className="flex items-stretch border border-ink bg-white">
            <code className="min-w-0 flex-1 truncate px-3.5 py-3 font-code text-[15px] leading-none text-ink [font-variant-ligatures:none]">
              {MCP_SERVER_URL}
            </code>
            <button
              type="button"
              onClick={copyUrl}
              aria-label="Copy MCP server URL"
              className="flex flex-none items-center gap-1.5 border-l border-ink bg-ink px-3.5 font-pixel text-pixel text-white transition-colors hover:bg-ink-soft"
            >
              <Copy className="h-3.5 w-3.5" /> copy
            </button>
          </div>
          <ol className="space-y-3 text-[15px] leading-[1.45] text-muted-foreground">
            <li><span className="font-medium text-ink">Claude (web or desktop):</span> Settings → Connectors → Add custom connector → paste the URL → Connect. Claude sends you here to approve.</li>
            <li>
              <span className="font-medium text-ink">Claude Code:</span>{' '}
              <code className="break-all bg-fill px-1.5 py-0.5 font-code text-[12.5px] text-ink [font-variant-ligatures:none]">claude mcp add --transport http stash {MCP_SERVER_URL}</code>
            </li>
            <li><span className="font-medium text-ink">Other agents:</span> any client that supports remote MCP servers with OAuth sign-in.</li>
          </ol>
        </CardContent>
      </Card>

      <section aria-labelledby="agents-connected">
        <h2 id="agents-connected" className="text-section-title font-medium text-ink">Connected</h2>
        <p className="mt-1.5 text-[15px] text-muted-foreground">Agents that can search your stash right now.</p>
        <div className="mt-4 space-y-3">
          {loading ? (
            <StatusLine tone="busy">checking for agents…</StatusLine>
          ) : active.length === 0 ? (
            <div className="v2-dots border border-line px-4 py-6 text-center text-[15px] text-muted-foreground">
              No agents connected yet. Paste the address above into one to start.
            </div>
          ) : (
            active.map((g) => (
              <MachineWindow
                key={g.id}
                title={g.client_name}
                aside={<span className="text-spot-on-ink">● connected</span>}
                bodyClassName="flex flex-wrap items-center justify-between gap-3 px-3.5 py-3"
              >
                <p className="font-pixel text-pixel text-muted-foreground">
                  connected {relative(g.created_at)}
                  {g.last_used_at ? ` · last used ${relative(g.last_used_at)}` : ' · not used yet'}
                </p>
                <AlertDialog>
                  <AlertDialogTrigger asChild>
                    <button
                      type="button"
                      disabled={revoking === g.id}
                      className="h-8 border border-ink px-3 text-[14px] font-medium text-ink transition-colors hover:bg-error hover:text-white hover:border-error disabled:opacity-60"
                    >
                      {revoking === g.id ? <Spinner className="font-pixel text-pixel-md leading-none" /> : 'Revoke'}
                    </button>
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
                      <AlertDialogAction onClick={() => revoke(g)} className="bg-error hover:bg-error hover:opacity-90">Revoke access</AlertDialogAction>
                    </AlertDialogFooter>
                  </AlertDialogContent>
                </AlertDialog>
              </MachineWindow>
            ))
          )}
        </div>
      </section>

      <section aria-labelledby="agents-activity">
        <h2 id="agents-activity" className="text-section-title font-medium text-ink">Activity</h2>
        <p className="mt-1.5 text-[15px] text-muted-foreground">Every search and read, newest first.</p>
        {/* The log: what each agent did, in the machine voice, like a terminal's history */}
        <MachineWindow title="activity.log" aside={<span className="text-white/60">{activity.length} {activity.length === 1 ? 'entry' : 'entries'}</span>} className="mt-4" bodyClassName="max-h-[420px] overflow-y-auto">
          {loading ? (
            <div className="px-3.5 py-3"><StatusLine tone="busy">reading the log…</StatusLine></div>
          ) : activity.length === 0 ? (
            <p className="px-3.5 py-4 text-[15px] text-muted-foreground">No activity yet. Once an agent connects, every search and read shows up here.</p>
          ) : (
            <ul className="divide-y divide-line-soft">
              {activity.map((row) => (
                <li key={row.id} className="flex items-start justify-between gap-4 px-3.5 py-2.5">
                  <p className="min-w-0 text-[14px] leading-[1.4] text-ink">{describeAgentActivity(row, clientNameFor(row.client_id))}</p>
                  <p className="shrink-0 font-pixel text-pixel text-muted-foreground">{relative(row.created_at)}</p>
                </li>
              ))}
            </ul>
          )}
        </MachineWindow>
      </section>
    </div>
  );
};

export default ConnectedAgentsSettings;
