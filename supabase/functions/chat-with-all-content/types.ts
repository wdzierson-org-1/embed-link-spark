
export interface ChatRequest {
  message: string;
  conversationHistory: Array<{
    role: 'user' | 'assistant';
    content: string;
  }>;
}

export interface ContentChunk {
  content: string;
  similarity: number;
  item_id: string;
  item_title: string;
  item_type: string;
  item_url?: string;
}

export interface SourceItem {
  id: string;
  title: string;
  type: string;
  url?: string;
  maxSimilarity: number;
  content: string;
}

export interface ChatResponse {
  response: string;
  sources: Array<{
    id: string;
    title: string;
    type: string;
    url?: string;
  }>;
}
