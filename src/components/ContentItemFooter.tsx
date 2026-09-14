
import React, { useState } from 'react';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuSub, DropdownMenuSubContent, DropdownMenuSubTrigger, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { Button } from '@/components/ui/button';
import { MoreHorizontal, MessageCircle, Eye, EyeOff, MapPin, Flag, Bell, BellOff } from 'lucide-react';
import { format } from 'date-fns';
import { AnimatedCommentCount } from '@/components/AnimatedCommentCount';
import CardFeedbackDialog from '@/components/CardFeedbackDialog';
import { useToast } from '@/hooks/use-toast';
import { useNow } from '@/hooks/useNow';
import { saveItem } from '@/utils/itemOperations';
import { ReminderChip } from '@/components/cards/ReminderChip';
import { REMINDER_PRESETS, clearReminderPatch, remindAtForPreset, reminderLabel, reminderState, setReminderPatch, type ReminderPreset } from '@/utils/reminders';
import { typeChipFor } from '@/components/cards/ItemTypeChip';
import type { ItemAttributes } from '@/types/itemAttributes';

interface ContentItem {
  id: string;
  type: 'text' | 'link' | 'image' | 'audio' | 'video' | 'document' | 'collection';
  title?: string;
  description?: string;
  content?: string;
  url?: string;
  file_path?: string;
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

  return (
    <div className="flex items-center justify-between mt-auto">
      <div className="flex flex-wrap items-center gap-2 min-w-0">
        <p className="text-xs text-muted-foreground whitespace-nowrap">
          {format(new Date(item.created_at), 'MMM d, yyyy')}
        </p>
        <span className="card-hover-control flex shrink-0 items-center">{typeChipFor(item)}</span>
        {!isPublicView && hasActiveReminder && reminderText && item.remind_at && (
          <ReminderChip state={reminder} label={reminderText} remindAt={item.remind_at} onDismiss={removeReminder} />
        )}
        {item.attributes?.location?.label && (
          <p
            className="flex items-center gap-0.5 text-xs text-muted-foreground min-w-0"
            title={`posted from ${item.attributes.location.label}`}
          >
            <MapPin className="h-3 w-3 flex-none" />
            <span className="truncate max-w-[140px]">{item.attributes.location.label}</span>
          </p>
        )}
      </div>
      
      <div className="flex items-center gap-2">
        {/* Comment count with animation */}
        {isPublicView && onCommentClick && (
          <AnimatedCommentCount 
            count={item.comment_count || 0}
            onCommentClick={() => onCommentClick(item.id)}
          />
        )}
        
        {/* Menu dropdown */}
        {hasMenu && (
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button
              aria-label="Card menu"
              variant="ghost"
              size="sm"
              className="h-6 w-6 rounded-full p-0 text-muted-foreground hover:bg-black/5 hover:text-foreground"
            >
              <MoreHorizontal className="h-[15px] w-[15px]" />
            </Button>
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
