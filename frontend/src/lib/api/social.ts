/**
 * Social API - Feed, posts, moments, followers, circles
 */

import { get, post, put, del, postFormData, putFormData, buildQueryString } from "./helpers";
import type { 
  FeedPost, 
  Moment, 
  Circle, 
  UserProfile,
  PaginatedResponse 
} from "./types";

export interface FeedQueryParams {
  page?: number;
  limit?: number;
  type?: "all" | "following" | "events" | "services" | "moments";
  mode?: "ranked" | "chronological";
  session_id?: string;
}

export interface PostQueryParams {
  page?: number;
  limit?: number;
  sort_by?: "created_at" | "likes_count";
  sort_order?: "asc" | "desc";
}

export interface MomentQueryParams {
  page?: number;
  limit?: number;
  type?: "all" | "photo" | "video";
  visibility?: "public" | "followers" | "private";
}

export const socialApi = {
  // ============================================================================
  // FEED
  // ============================================================================

  getFeed: (params?: FeedQueryParams) => 
    get<{ items: FeedPost[]; pagination: PaginatedResponse<FeedPost>["pagination"] }>(`/posts/feed${buildQueryString(params)}`),

  getTrending: (params?: { limit?: number; period?: "day" | "week" | "month" }) => 
    get<FeedPost[]>(`/posts/public/trending${buildQueryString(params)}`),

  getUserPosts: (userId: string, params?: PostQueryParams) => 
    get<{ posts: FeedPost[]; pagination: PaginatedResponse<FeedPost>["pagination"] }>(`/posts/user/${userId}${buildQueryString(params)}`),

  // ============================================================================
  // POSTS
  // ============================================================================

  createPost: (formData: FormData) => postFormData<FeedPost>("/posts", formData),

  getPost: (postId: string) => get<FeedPost>(`/posts/${postId}`),

  updatePost: (postId: string, data: { content?: string; visibility?: string }) => 
    put<FeedPost>(`/posts/${postId}`, data),

  deletePost: (postId: string) => del(`/posts/${postId}`),

  // Glow (like) - aligned with nuru-api-doc 14.6/14.7
  glowPost: (postId: string, data?: { emoji?: string }) =>
    post<any>(`/posts/${postId}/glow`, data),
  unglowPost: (postId: string) => del<any>(`/posts/${postId}/glow`),

  // Echo (repost) - aligned with nuru-api-doc 14.9/14.10
  echoPost: (postId: string, data?: { comment?: string }) => 
    post<any>(`/posts/${postId}/echo`, data),
  unechoPost: (postId: string) => del<any>(`/posts/${postId}/echo`),

  // Comments - aligned with nuru-api-doc 14.11-14.16
  getComments: (postId: string, params?: { page?: number; limit?: number; sort?: string; parent_id?: string }) => 
    get<{ comments: any[]; pagination: any }>(`/posts/${postId}/comments${buildQueryString(params)}`),

  getCommentReplies: (postId: string, commentId: string, params?: { page?: number; limit?: number }) =>
    get<{ comments: any[]; pagination: any }>(`/posts/${postId}/comments/${commentId}/replies${buildQueryString(params)}`),

  addComment: (postId: string, data: { content: string; parent_id?: string }) => 
    post<any>(`/posts/${postId}/comments`, data),

  updateComment: (postId: string, commentId: string, data: { content: string }) =>
    put<any>(`/posts/${postId}/comments/${commentId}`, data),

  deleteComment: (postId: string, commentId: string) => 
    del(`/posts/${postId}/comments/${commentId}`),

  glowComment: (postId: string, commentId: string) =>
    post<any>(`/posts/${postId}/comments/${commentId}/glow`),

  unglowComment: (postId: string, commentId: string) =>
    del<any>(`/posts/${postId}/comments/${commentId}/glow`),

  // Save/unsave
  savePost: (postId: string) => post<any>(`/posts/${postId}/save`),
  unsavePost: (postId: string) => del<any>(`/posts/${postId}/save`),
  getSavedPosts: (params?: { page?: number; limit?: number }) =>
    get<any>(`/posts/saved${buildQueryString(params)}`),

  // ── Feed Interaction Tracking ──
  logInteraction: (data: {
    post_id: string;
    interaction_type: string;
    dwell_time_ms?: number;
    session_id?: string;
    device_type?: string;
  }) => post<any>("/posts/feed/interactions", data),

  logInteractionBatch: (data: {
    interactions: Array<{
      post_id: string;
      interaction_type: string;
      dwell_time_ms?: number;
    }>;
    session_id?: string;
    device_type?: string;
  }) => post<any>("/posts/feed/interactions", data),

  getUserInterests: () => get<any>("/posts/feed/interests"),

  // Pin/unpin
  pinPost: (postId: string) => post<any>(`/posts/${postId}/pin`),
  unpinPost: (postId: string) => del<any>(`/posts/${postId}/pin`),

  // Share/report
  sharePost: (postId: string, data: { content?: string; visibility?: string }) => 
    post<FeedPost>(`/posts/${postId}/share`, data),
  reportPost: (postId: string, data: { reason: string; details?: string }) => 
    post<any>(`/posts/${postId}/report`, data),

  // ============================================================================
  // MOMENTS (Stories)
  // ============================================================================

  getMoments: (params?: MomentQueryParams) => 
    get<{ users: any[]; my_moments: Moment[] }>(`/moments${buildQueryString(params)}`),

  createMoment: (formData: FormData) => postFormData<Moment>("/moments", formData),
  getMoment: (momentId: string) => get<Moment>(`/moments/${momentId}`),
  deleteMoment: (momentId: string) => del(`/moments/${momentId}`),
  viewMoment: (momentId: string) => post<any>(`/moments/${momentId}/view`),
  reactToMoment: (momentId: string, data: { reaction: string }) => 
    post<any>(`/moments/${momentId}/react`, data),
  replyToMoment: (momentId: string, data: { content: string }) => 
    post<any>(`/moments/${momentId}/reply`, data),
  getMomentViewers: (momentId: string) => 
    get<{ viewers: any[] }>(`/moments/${momentId}/viewers`),

  // ============================================================================
  // FOLLOWERS
  // ============================================================================

  getFollowers: (userId: string, params?: { page?: number; limit?: number; search?: string }) => 
    get<{ followers: UserProfile[]; pagination: any }>(`/users/${userId}/followers${buildQueryString(params)}`),

  getFollowing: (userId: string, params?: { page?: number; limit?: number; search?: string }) => 
    get<{ following: UserProfile[]; pagination: any }>(`/users/${userId}/following${buildQueryString(params)}`),

  followUser: (userId: string) => post<any>(`/users/${userId}/follow`),
  unfollowUser: (userId: string) => del<any>(`/users/${userId}/follow`),
  removeFollower: (userId: string) => del<any>(`/users/${userId}/remove-follower`),

  getFollowSuggestions: (params?: { limit?: number }) => 
    get<UserProfile[]>(`/users/search${buildQueryString({ ...params, suggested: true })}`),

  // ============================================================================
  // CIRCLES
  // ============================================================================

  getCircles: () => get<Circle[]>("/circles"),
  createCircle: (data: { name: string; description?: string; color?: string; icon?: string }) => 
    post<Circle>("/circles", data),
  updateCircle: (circleId: string, data: { name?: string; description?: string; color?: string; icon?: string }) => 
    put<Circle>(`/circles/${circleId}`, data),
  deleteCircle: (circleId: string) => del(`/circles/${circleId}`),
  addCircleMember: (circleId: string, userId: string) => 
    post<any>(`/circles/${circleId}/members/${userId}`),
  removeCircleMember: (circleId: string, userId: string) => 
    del<any>(`/circles/${circleId}/members/${userId}`),
  getCircleMembers: (circleId: string) => 
    get<{ members: UserProfile[] }>(`/circles/${circleId}/members`),

  // Circle requests
  getCircleRequests: () => get<any>("/circles/requests"),
  acceptCircleRequest: (requestId: string) => put<any>(`/circles/requests/${requestId}/accept`),
  rejectCircleRequest: (requestId: string) => put<any>(`/circles/requests/${requestId}/reject`),

  // ============================================================================
  // COMMUNITIES
  // ============================================================================

  getCommunities: (params?: { page?: number; limit?: number }) =>
    get<any[]>(`/communities${buildQueryString(params)}`),
  getMyCommunities: () => get<any[]>("/communities/my"),
  getCommunity: (communityId: string) => get<any>(`/communities/${communityId}`),
  getCommunityMembers: (communityId: string, params?: { page?: number; limit?: number }) =>
    get<{ members: any[] }>(`/communities/${communityId}/members${buildQueryString(params)}`),
  getCommunityPosts: (communityId: string, params?: { page?: number; limit?: number }) =>
    get<{ posts: FeedPost[] }>(`/communities/${communityId}/posts${buildQueryString(params)}`),
  createCommunityPost: (communityId: string, formData: FormData) =>
    postFormData<any>(`/communities/${communityId}/posts`, formData),
  glowCommunityPost: (communityId: string, postId: string) =>
    post<any>(`/communities/${communityId}/posts/${postId}/glow`),
  unglowCommunityPost: (communityId: string, postId: string) =>
    del<any>(`/communities/${communityId}/posts/${postId}/glow`),
  createCommunity: (formData: FormData) =>
    postFormData<any>("/communities", formData),
  joinCommunity: (communityId: string) =>
    post<any>(`/communities/${communityId}/join`),
  leaveCommunity: (communityId: string) =>
    post<any>(`/communities/${communityId}/leave`),
  addCommunityMember: (communityId: string, userId: string) =>
    post<any>(`/communities/${communityId}/members`, { user_id: userId }),
  removeCommunityMember: (communityId: string, userId: string) =>
    del<any>(`/communities/${communityId}/members/${userId}`),
  updateCommunityCover: (communityId: string, file: File) => {
    const formData = new FormData();
    formData.append('cover_image', file);
    return putFormData<any>(`/communities/${communityId}/cover`, formData);
  },

  // ============================================================================
  // NOTIFICATIONS
  // ============================================================================

  getNotifications: (params?: { page?: number; limit?: number; filter?: "all" | "unread"; search?: string }) =>
    get<{ notifications: any[]; unread_count: number; pagination: any }>(`/notifications${buildQueryString(params)}`),
  markAllNotificationsRead: () => put<any>("/notifications/read-all"),
  markNotificationRead: (notificationId: string) =>
    put<any>(`/notifications/${notificationId}/read`),

  // ============================================================================
  // CONVERSATIONS (Messages)
  // ============================================================================

  getConversations: (params?: { page?: number; limit?: number; search?: string }) =>
    get<any[]>(`/messages/${buildQueryString(params)}`),
  getMessages: (conversationId: string, params?: { page?: number; limit?: number }) => 
    get<any[]>(`/messages/${conversationId}${buildQueryString(params)}`),
  sendMessage: (conversationId: string, data: { content: string; attachments?: string[] }) => 
    post<any>(`/messages/${conversationId}`, data),
  createConversation: (data: { recipient_id: string; message?: string }) => 
    post<any>("/messages/start", data),

  // ============================================================================
  // APPEALS & REMOVED CONTENT
  // ============================================================================

  /** Get user's own removed posts (for appeal) */
  getMyRemovedPosts: () => get<any[]>("/posts/my-removed"),

  /** Get user's own removed moments (for appeal) */
  getMyRemovedMoments: () => get<any[]>("/moments/my-removed"),

  /** Submit an appeal for a removed post */
  submitPostAppeal: (postId: string, reason: string) =>
    post<any>(`/posts/${postId}/appeal`, { reason }),

  /** Submit an appeal for a removed moment */
  submitMomentAppeal: (momentId: string, reason: string) =>
    post<any>(`/moments/${momentId}/appeal`, { reason }),
};
