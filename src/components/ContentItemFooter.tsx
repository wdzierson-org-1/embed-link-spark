
import React, { useState } from 'react';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuSub, DropdownMenuSubContent, DropdownMenuSubTrigger, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { MoreHorizontal, MessageCircle, Eye, EyeOff, MapPin, Flag, Bell, BellOff } from 'lucide-react';
import { format } from 'date-fns';
import { AnimatedCommentCount } from '@/components/AnimatedCommentCount';
import CardFeedbackDialog from '@/components/CardFeedbackDialog';
import { useToast } from '@/hooks/use-toast';
import { useNow } from '@/hooks/useNow';
import { saveItem } from '@/utils/itemOperations';
import { domainOfUrl } from '@/utils/linkFlavor';
import { ReminderChip } from '@/components/cards/ReminderChip';
import { formatDurationChip, formatFileSizeChip, mimeExtensionLabel } from '@/components/cards/CardBits';
import { REMINDER_PRESETS, clearReminderPatch, remindAtForPreset, reminderLabel, reminderState, setReminderPatch, type ReminderPreset } from '@/utils/reminders';
import type { ItemAttributes } from '@/types/itemAttributes';

interface ContentItem {
  id: string;
  type: 'text' | 'link' | 'image' | 'audio' | 'video' | 'document' | 'collection';
  title?: string;
  description?: string;
  content?: string;
  url?: string;
  file_path?: string;
  file_size?: number;
  mime_type?: string;
  created_at: string;
  is_public?: boolean;
  user_id?: string;
  comment_count?: number;
  summary?: string;
  attributes?: ItemAttributes;
  remind_at?: string | null;
  reminder_cleared_at?: string | null;
}

interface ContentItemFooterProps {
  item: ContentItem;
  onDeleteItem: (id: string) => void;
  onEditItem: (item: ContentItem) => void;
  onChatWithItem?: (item: ContentItem) => void;
  isPublicView?: boolean;
  currentUserId?: string;
  onTogglePrivacy?: (item: ContentItem) => void;
  onCommentClick?: (itemId: string) => void;
}

/** Where the save came from and the one fact worth knowing at a glance, machine-voiced */
const sourceAndFact = (item: ContentItem): { source: string; fact: string | null } => {
  if (item.type === 'link') {
    const link = item.attributes?.link;
    const fact =
      link?.flavor === 'video'
        ? formatDurationChip(link.duration_s)
        : typeof link?.read_time_min === 'number' && link.read_time_min > 0
          ? `${Math.round(link.read_time_min)} min read`
          : null;
    return { source: domainOfUrl(item.url) || 'link', fact };
  }
  if (item.type === 'text') return { source: 'note', fact: null };
  if (item.type === 'collection') return { source: 'multi-part', fact: null };
  const format = [mimeExtensionLabel(item.mime_type), formatFileSizeChip(item.file_size)].filter(Boolean).join(' · ');
  const duration = item.type === 'audio' || item.type === 'video' ? formatDurationChip(item.attributes?.media?.duration_s) : null;
  return { source: format.toLowerCase() || item.type, fact: duration };
};

const ContentItemFooter = ({
  item,
  onChatWithItem,
  isPublicView = false,
  currentUserId,
  onTogglePrivacy,
  onCommentClick
}: ContentItemFooterProps) => {
  const [reportOpen, setReportOpen] = useState(false);

  const now = useNow();
  const { toast } = useToast();
  const reminder = reminderState(item, now);
  const reminderText = reminderLabel(item, now);
  const hasActiveReminder = reminder === 'scheduled' || reminder === 'due';

  // Writes go straight through the items PATCH path; the realtime subscription
  // in useItems refetches the list, so no local refresh is needed.
  const noRefresh = async () => {};
  const setReminder = (days: ReminderPreset) =>
    saveItem(item.id, setReminderPatch(remindAtForPreset(days, new Date())), noRefresh, toast, { showSuccessToast: false, refreshItems: false });
  const removeReminder = () =>
    saveItem(item.id, clearReminderPatch(new Date()), noRefresh, toast, { showSuccessToast: false, refreshItems: false });

  const isOwner = currentUserId && item.user_id === currentUserId;
  const showOwnerControls = isPublicView && isOwner;
  // Read-only views (public feed, admin member view) only get the overflow
  // menu when it would hold something — an empty menu is a dead control
  const hasMenu =
    !isPublicView || Boolean(onCommentClick) || Boolean(showOwnerControls && onTogglePrivacy);

  const { source, fact } = sourceAndFact(item);
  const created = new Date(item.created_at);
  const dateLabel = format(created, created.getFullYear() === new Date(now).getFullYear() ? 'MMM d' : 'MMM d, yyyy').toLowerCase();

  return (
    // The meta row (DESIGN-v2 "Object card"): Departure Mono, the source on the left with one
    // fact; the date, reminder and place after it; the overflow menu on the right
    <div className="mt-auto flex items-center justify-between gap-3 border-t border-line-soft pt-3 font-pixel text-pixel text-muted-foreground">
      <div className="flex min-w-0 flex-wrap items-center gap-x-2.5 gap-y-1">
        {item.type === 'link' && item.url ? (
          <a
            href={item.url}
            target="_blank"
            rel="noreferrer"
            title={item.url}
            onClick={(event) => event.stopPropagation()}
            className="min-w-0 max-w-[180px] truncate text-ink underline-offset-2 hover:underline"
          >
            {source}
          </a>
        ) : (
          <span className="min-w-0 max-w-[180px] truncate">{source}</span>
        )}
        {fact && (
          <>
            <span aria-hidden>·</span>
            <span className="whitespace-nowrap">{fact}</span>
          </>
        )}
        {!isPublicView && hasActiveReminder && reminderText && item.remind_at && (
          <ReminderChip state={reminder} label={reminderText} remindAt={item.remind_at} onDismiss={removeReminder} />
        )}
        {item.attributes?.location?.label && (
          <span
            className="flex min-w-0 items-center gap-1"
            title={`posted from ${item.attributes.location.label}`}
          >
            <MapPin className="h-3 w-3 flex-none" aria-hidden />
            <span className="max-w-[140px] truncate">{item.attributes.location.label}</span>
          </span>
        )}
      </div>

      <div className="flex flex-none items-center gap-2">
        <span className="whitespace-nowrap">{dateLabel}</span>
        {/* Comment count with animation */}
        {isPublicView && onCommentClick && (
          <AnimatedCommentCount
            count={item.comment_count || 0}
            onCommentClick={() => onCommentClick(item.id)}
          />
        )}

        {hasMenu && (
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <button
              type="button"
              aria-label="Card menu"
              className="-mr-1 grid h-6 w-6 place-items-center text-muted-foreground transition-colors hover:bg-ink hover:text-white data-[state=open]:bg-ink data-[state=open]:text-white"
            >
              <MoreHorizontal className="h-[15px] w-[15px]" />
            </button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            {isPublicView && onCommentClick && (
              <DropdownMenuItem onClick={() => onCommentClick(item.id)}>
                <MessageCircle className="h-4 w-4 mr-2" />
                Comments
              </DropdownMenuItem>
            )}
            {showOwnerControls && (
              <>
                {onTogglePrivacy && (
                  <DropdownMenuItem onClick={() => onTogglePrivacy(item)}>
                    {item.is_public ? (
                      <>
                        <EyeOff className="h-4 w-4 mr-2" />
                        Set to Private
                      </>
                    ) : (
                      <>
                        <Eye className="h-4 w-4 mr-2" />
                        Set to Public
                      </>
                    )}
                  </DropdownMenuItem>
                )}
              </>
            )}
            {!isPublicView && (
              <>
                <DropdownMenuSub>
                  <DropdownMenuSubTrigger>
                    <Bell className="h-4 w-4 mr-2" />
                    {hasActiveReminder ? 'Change reminder…' : 'Remind me…'}
                  </DropdownMenuSubTrigger>
                  <DropdownMenuSubContent>
                    {REMINDER_PRESETS.map((days) => (
                      <DropdownMenuItem key={days} onClick={() => setReminder(days)}>
                        {days === 1 ? 'In 1 day' : `In ${days} days`}
                      </DropdownMenuItem>
                    ))}
                  </DropdownMenuSubContent>
                </DropdownMenuSub>
                {hasActiveReminder && (
                  <DropdownMenuItem onClick={removeReminder}>
                    <BellOff className="h-4 w-4 mr-2" />
                    Remove reminder
                  </DropdownMenuItem>
                )}
                <DropdownMenuSeparator />
                <DropdownMenuItem onClick={() => setReportOpen(true)}>
                  <Flag className="h-4 w-4 mr-2" />
                  Report a problem
                </DropdownMenuItem>
              </>
            )}
          </DropdownMenuContent>
        </DropdownMenu>
        )}
      </div>

      {!isPublicView && <CardFeedbackDialog item={item} open={reportOpen} onOpenChange={setReportOpen} />}
    </div>
  );
};

export default ContentItemFooter;
