export interface ChatUser {
  id: string;
  name: string;
  username: string;
  avatar: string;
  isOnline?: boolean;
}

export interface ChatMessage {
  id: string;
  content: string;
  timestamp: string;
  senderId: string;
  isFromCurrentUser: boolean;
}

export interface ChatConversation {
  id: string;
  participants: ChatUser[];
  lastMessage: ChatMessage;
  unreadCount: number;
  messages: ChatMessage[];
}

export type ChatState = "collapsed" | "expanded" | "conversation";

export interface ChatData {
  currentUser: ChatUser;
  conversations: ChatConversation[];
}
