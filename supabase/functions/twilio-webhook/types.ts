
export interface TwilioWebhookBody {
  Body: string;
  From: string;
  To: string;
  MediaUrl0?: string;
  MediaContentType0?: string;
}

export interface ProcessedContent {
  content: string;
  mediaProcessing?: string;
}
