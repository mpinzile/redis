/**
 * API Types - Complete type definitions for all API responses
 */

// ============================================================================
// COMMON TYPES
// ============================================================================

export interface ApiResponse<T = unknown> {
  success: boolean;
  message: string;
  data: T;
  errors?: Array<{ field: string; message: string }>;
}

export interface PaginationInfo {
  page: number;
  limit: number;
  total_items: number;
  total_pages: number;
  has_next: boolean;
  has_previous: boolean;
}

export interface PaginatedResponse<T> {
  items: T[];
  pagination: PaginationInfo;
}

// ============================================================================
// USER & AUTH TYPES
// ============================================================================

export interface User {
  id: string;
  first_name: string;
  last_name: string;
  username: string;
  email: string;
  phone: string;
  avatar: string | null;
  bio?: string;
  location?: string;
  /** ISO-3166 alpha-2 country code (e.g. "TZ", "KE"). Set during signup or first login. */
  country_code?: string | null;
  /** ISO-4217 currency code matching the country (TZS / KES). Drives wallet & price formatting. */
  currency_code?: string | null;
  /** How the country was determined: ip | phone | locale | manual. */
  country_source?: string | null;
  is_active?: boolean;
  is_suspended?: boolean;
  suspension_reason?: string | null;
  is_identity_verified?: boolean;
  is_email_verified?: boolean;
  is_phone_verified?: boolean;
  is_vendor?: boolean;
  follower_count?: number;
  following_count?: number;
  event_count?: number;
  service_count?: number;
  created_at?: string;
  updated_at?: string;
}

export interface UserProfile extends User {
  date_of_birth?: string;
  gender?: string;
  social_links?: {
    instagram?: string;
    twitter?: string;
    facebook?: string;
    linkedin?: string;
    website?: string;
  };
  vendor_status?: string;
  post_count?: number;
}

export interface SignupData {
  first_name: string;
  last_name: string;
  username?: string;
  email?: string;
  phone: string;
  password: string;
  registered_by?: string;
}

export interface SigninData {
  credential: string;
  password: string;
}

export interface AuthResponse {
  user: User;
  access_token: string;
  refresh_token?: string;
  token_type: string;
  expires_in: number;
}

export interface VerifyOtpData {
  user_id: string;
  verification_type: "email" | "phone";
  otp_code: string;
}

export interface RequestOtpData {
  user_id: string;
  verification_type: "email" | "phone";
}

// ============================================================================
// REFERENCE TYPES
// ============================================================================

export interface EventType {
  id: string;
  name: string;
  description?: string;
  icon?: string;
  color?: string;
  is_active?: boolean;
  display_order?: number;
  created_at?: string;
}

export interface ServiceCategory {
  id: string;
  name: string;
  description?: string;
  icon?: string;
  image_url?: string;
  is_active?: boolean;
  display_order?: number;
  service_count?: number;
  created_at?: string;
}

export interface ServiceType {
  id: string;
  name: string;
  category_id: string;
  description?: string;
  is_active?: boolean;
  display_order?: number;
  service_count?: number;
  created_at?: string;
}

export interface KycRequirement {
  id: string;
  name: string;
  description?: string;
  document_type?: string;
  is_required: boolean;
  accepted_formats?: string[];
  max_file_size_mb?: number;
  display_order?: number;
  created_at?: string;
}

export interface Currency {
  id: string;
  code: string;
  name: string;
  symbol: string;
  is_default: boolean;
  is_active: boolean;
}

export interface Country {
  id: string;
  code: string;
  name: string;
  phone_code: string;
  currency_code: string;
  is_active: boolean;
}

// ============================================================================
// EVENT TYPES
// ============================================================================

export interface EventImage {
  id: string;
  image_url: string;
  caption?: string;
  is_featured?: boolean;
  created_at?: string;
}

export interface Event {
  id: string;
  user_id: string;
  title: string;
  description?: string;
  event_type_id: string;
  event_type?: EventType;
  start_date: string;
  end_date?: string;
  location?: string;
  venue?: string;
  venue_address?: string;
  venue_coordinates?: {
    latitude: number;
    longitude: number;
  };
  cover_image?: string;
  images?: EventImage[];
  gallery_images?: string[];
  theme_color?: string;
  is_public: boolean;
  status: "draft" | "confirmed" | "published" | "cancelled" | "completed";
  budget?: number;
  currency?: string;
  dress_code?: string;
  special_instructions?: string;
  rsvp_deadline?: string;
  contribution_enabled?: boolean;
  contribution_target?: number;
  contribution_description?: string;
  expected_guests?: number;
  guest_count?: number;
  confirmed_guest_count?: number;
  pending_guest_count?: number;
  declined_guest_count?: number;
  checked_in_count?: number;
  contribution_total?: number;
  contribution_count?: number;
  committee_count?: number;
  service_booking_count?: number;
  created_at: string;
  updated_at: string;
}

export interface EventGuest {
  id: string;
  event_id: string;
  guest_type?: "user" | "contributor";
  user_id?: string;
  contributor_id?: string;
  name: string;
  /** Optional display label used on invitation cards (e.g. "Mr & Mrs Doe").
   *  Falls back to `name` when blank. */
  common_name?: string;
  /** Optional UI-only follow-up label slug (e.g. "not_reachable").
   *  Visual hint for organizer outreach — never used in reports. */
  follow_up_label?: string | null;
  avatar?: string;
  email?: string;
  phone?: string;
  rsvp_status: "pending" | "confirmed" | "declined" | "maybe";
  rsvp_responded_at?: string;
  table_number?: string;
  seat_number?: number;
  dietary_requirements?: string;
  allergies?: string;
  plus_ones: number;
  plus_one_names?: string[];
  plus_one_details?: Array<{
    name: string;
    dietary_requirements?: string;
    allergies?: string;
  }>;
  notes?: string;
  tags?: string[];
  invitation_sent: boolean;
  invitation_sent_at?: string;
  invitation_method?: "email" | "sms" | "whatsapp";
  invitation_opened?: boolean;
  invitation_opened_at?: string;
  checked_in: boolean;
  checked_in_at?: string;
  checked_in_by?: string;
  qr_code?: string;
  /** Backend-resolved QR payload (invitation_code if present, else attendee.id).
   *  Used by the card editor to bake the exact same QR the server would into
   *  browser-rendered invitation PNGs. */
  qr_payload?: string;
  created_at: string;
  updated_at: string;
}

export interface CommitteeMember {
  id: string;
  event_id: string;
  user_id?: string;
  name: string;
  email?: string;
  phone?: string;
  avatar?: string;
  role: string;
  role_description?: string;
  permissions: string[];
  status: "invited" | "active" | "declined" | "removed";
  invited_at: string;
  accepted_at?: string;
  last_active_at?: string;
  created_at: string;
}

export interface EventContribution {
  id: string;
  event_id: string;
  contributor_name: string;
  contributor_email?: string;
  contributor_phone?: string;
  contributor_user_id?: string;
  contributor_avatar?: string;
  amount: number;
  currency: string;
  payment_method: "cash" | "mobile" | "bank_transfer" | "card" | "cheque" | "other";
  payment_reference?: string;
  mpesa_receipt?: string;
  status: "pending" | "confirmed" | "failed";
  message?: string;
  is_anonymous: boolean;
  thank_you_sent: boolean;
  thank_you_sent_at?: string;
  notes?: string;
  created_at: string;
  confirmed_at?: string;
}

export interface EventScheduleItem {
  id: string;
  event_id: string;
  title: string;
  description?: string;
  start_time: string;
  end_time?: string;
  location?: string;
  display_order: number;
}

export interface EventBudgetItem {
  id: string;
  event_id: string;
  category: string;
  item_name: string;
  estimated_cost: number;
  actual_cost?: number;
  vendor_name?: string;
  status: "pending" | "deposit_paid" | "paid";
  notes?: string;
  created_at: string;
}

// ============================================================================
// SERVICE TYPES
// ============================================================================

export interface UserService {
  id: string;
  user_id?: string;
  title: string;
  description?: string;
  short_description?: string;
  service_category_id?: string;
  service_category?: ServiceCategory;
  service_type_id?: string;
  service_type?: ServiceType;
  /** All linked service types (multi). Backed by user_service_types join table. */
  service_type_ids?: string[];
  service_types?: Array<{ id: string; name: string }>;
  min_price?: number;
  max_price?: number;
  currency?: string;
  price_type?: "fixed" | "range" | "starting_from" | "custom";
  price_unit?: "per_event" | "per_hour" | "per_day" | "per_person";
  price_notes?: string;
  location?: string;
  full_address?: string;
  service_areas?: string[];
  travel_fee_info?: string;
  status?: string;
  verification_status?: "verified" | "pending" | "rejected" | "unverified";
  verification_progress?: number;
  identity_verified?: boolean;
  kyc_all_approved?: boolean;
  images?: Array<{
    id: string;
    url: string;
    thumbnail_url?: string;
    is_primary: boolean;
    display_order?: number;
  }>;
  rating?: number;
  review_count?: number;
  booking_count?: number;
  completed_events?: number;
  response_rate?: number;
  response_time_hours?: number;
  years_experience?: number;
  team_size?: number;
  languages?: string[];
  availability?: "available" | "limited" | "unavailable";
  next_available_date?: string;
  booking_lead_time_days?: number;
  cancellation_policy?: string;
  insurance_info?: string;
  highlights?: string[];
  faqs?: Array<{ question: string; answer: string }>;
  featured?: boolean;
  created_at?: string;
  updated_at?: string;
}

export interface ServicePackage {
  id: string;
  service_id: string;
  name: string;
  description?: string;
  price: number;
  currency?: string;
  compare_at_price?: number;
  duration_hours?: number;
  photographers_count?: number;
  features: string[];
  deliverables?: string[];
  turnaround_days?: number;
  is_popular: boolean;
  is_active: boolean;
  display_order: number;
  created_at?: string;
}

export interface ServiceReview {
  id: string;
  service_id: string;
  user_id: string;
  user_name: string;
  user_avatar?: string;
  rating: number;
  title?: string;
  comment: string;
  event_type?: string;
  event_date?: string;
  photos?: string[];
  vendor_response?: string;
  vendor_response_at?: string;
  helpful_count?: number;
  verified_booking: boolean;
  created_at: string;
}

export interface ServiceKycStatus {
  service_id: string;
  overall_status: "verified" | "pending" | "rejected" | "unverified";
  progress: number;
  submitted_at?: string;
  last_updated_at?: string;
  estimated_review_time_days?: number;
  requirements: Array<{
    id: string;
    kyc_requirement_id: string;
    name: string;
    description?: string;
    document_type?: string;
    is_required: boolean;
    status: "pending" | "submitted" | "approved" | "rejected";
    file_url?: string;
    submitted_at?: string;
    reviewed_at?: string;
    rejection_reason?: string;
  }>;
}

// ============================================================================
// BOOKING TYPES
// ============================================================================

export interface BookingRequest {
  id: string;
  service: {
    id: string;
    title: string;
    primary_image?: string;
    category?: string;
  };
  provider?: {
    id: string;
    name: string;
    avatar?: string;
    phone?: string;
    email?: string;
    rating?: number;
  };
  client: {
    id: string;
    name: string;
    avatar?: string;
    phone?: string;
    email?: string;
  };
  event?: {
    id: string;
    title: string;
    type?: string;
    date?: string;
    start_time?: string;
    end_time?: string;
    location?: string;
    venue?: string;
    venue_address?: string;
    guest_count?: number;
  };
  package?: {
    id: string;
    name: string;
    price: number;
    features?: string[];
  };
  event_name?: string;
  package_name?: string;
  package_price?: number;
  event_date: string;
  event_type?: string;
  location?: string;
  venue?: string;
  guest_count?: number;
  message?: string;
  special_requirements?: string;
  budget?: number;
  status: "pending" | "accepted" | "rejected" | "cancelled" | "completed";
  quoted_price?: number;
  final_price?: number;
  currency?: string;
  deposit_required?: number;
  deposit_paid?: boolean;
  deposit_paid_at?: string;
  provider_message?: string;
  conversation_id?: string;
  unread_messages?: number;
  days_until_event?: number;
  contract_url?: string;
  contract_signed?: boolean;
  contract_signed_at?: string;
  cancellation_policy?: string;
  can_cancel?: boolean;
  cancel_deadline?: string;
  created_at: string;
  updated_at: string;
}

// ============================================================================
// MESSAGE TYPES
// ============================================================================

export interface Conversation {
  id: string;
  participant: {
    id: string;
    name: string;
    avatar?: string;
    is_online?: boolean;
    last_seen?: string;
    verified?: boolean;
  };
  context?: {
    type: "service" | "event" | "general";
    id?: string;
    title?: string;
  };
  booking?: {
    id: string;
    status: string;
  };
  last_message?: {
    id: string;
    content: string;
    sender_id: string;
    is_mine: boolean;
    created_at: string;
  };
  unread_count: number;
  muted: boolean;
  archived: boolean;
  created_at: string;
  updated_at: string;
}

export interface Message {
  id: string;
  conversation_id: string;
  sender_id: string;
  sender?: {
    name: string;
    avatar?: string;
  };
  content: string;
  message_type: "text" | "image" | "file" | "audio" | "system";
  attachments?: Array<{
    id: string;
    type: string;
    url: string;
    thumbnail_url?: string;
    filename?: string;
    size?: number;
  }>;
  reply_to?: {
    id: string;
    content: string;
    sender_name: string;
  };
  is_mine: boolean;
  is_read: boolean;
  read_at?: string;
  created_at: string;
}

// ============================================================================
// NOTIFICATION TYPES
// ============================================================================

export interface Notification {
  id: string;
  type: string;
  title: string;
  message: string;
  data?: {
    type?: string;
    id?: string;
    name?: string;
    image?: string;
    action_url?: string;
  };
  actors?: Array<{
    id: string;
    name: string;
    avatar?: string;
  }>;
  is_read: boolean;
  read_at?: string;
  created_at: string;
}

// ============================================================================
// SOCIAL/FEED TYPES
// ============================================================================

export interface FeedPost {
  id: string;
  user: {
    id: string;
    first_name: string;
    last_name: string;
    username: string;
    avatar?: string;
    is_verified?: boolean;
    is_following?: boolean;
  };
  content?: string;
  media?: Array<{
    id: string;
    type: "image" | "video";
    url: string;
    thumbnail_url?: string;
    width?: number;
    height?: number;
    duration_seconds?: number;
  }>;
  event?: {
    id: string;
    title: string;
  };
  tagged_users?: Array<{
    id: string;
    username: string;
  }>;
  location?: {
    name?: string;
    city?: string;
    country?: string;
    latitude?: number;
    longitude?: number;
  };
  glow_count: number;
  echo_count: number;
  comment_count: number;
  share_count?: number;
  has_glowed: boolean;
  has_echoed: boolean;
  has_saved: boolean;
  is_pinned?: boolean;
  privacy: "public" | "followers" | "private";
  echoed_by?: {
    id: string;
    username: string;
    comment?: string;
  };
  created_at: string;
  updated_at: string;
}

export interface FeedComment {
  id: string;
  user: {
    id: string;
    first_name: string;
    last_name: string;
    username: string;
    avatar?: string;
    is_verified?: boolean;
  };
  content: string;
  media?: {
    id: string;
    type: string;
    url: string;
    thumbnail_url?: string;
  };
  glow_count: number;
  reply_count: number;
  has_glowed: boolean;
  is_edited: boolean;
  parent_id?: string;
  replies_preview?: FeedComment[];
  created_at: string;
  updated_at: string;
}

// ============================================================================
// MOMENT/STORY TYPES
// ============================================================================

export interface Moment {
  id: string;
  user: {
    id: string;
    first_name: string;
    last_name: string;
    username: string;
    avatar?: string;
    is_verified?: boolean;
  };
  type: "image" | "video";
  media_url: string;
  thumbnail_url?: string;
  caption?: string;
  duration_seconds?: number;
  background_color?: string;
  stickers?: Array<{
    id: string;
    type: string;
    position: { x: number; y: number };
    data: Record<string, unknown>;
  }>;
  mentions?: Array<{
    user_id: string;
    username: string;
    position: { x: number; y: number };
  }>;
  location?: {
    name: string;
    latitude?: number;
    longitude?: number;
  };
  music?: {
    track_name: string;
    artist: string;
    preview_url?: string;
  };
  link?: {
    url: string;
    title?: string;
  };
  allow_replies: boolean;
  view_count: number;
  has_viewed: boolean;
  expires_at: string;
  created_at: string;
}

export interface MomentGroup {
  user: {
    id: string;
    first_name: string;
    last_name: string;
    username: string;
    avatar?: string;
    is_verified?: boolean;
  };
  has_unseen: boolean;
  moment_count: number;
  latest_moment_at: string;
  preview?: {
    type: string;
    thumbnail_url: string;
  };
}

export interface Highlight {
  id: string;
  title: string;
  cover_image?: string;
  moment_count: number;
  created_at: string;
  updated_at: string;
}

// ============================================================================
// CIRCLE TYPES
// ============================================================================

export interface Circle {
  id: string;
  name: string;
  description?: string;
  cover_image?: string;
  privacy: "private" | "invite_only";
  join_approval_required?: boolean;
  member_count: number;
  post_count: number;
  event_count?: number;
  is_owner: boolean;
  role: "owner" | "admin" | "member";
  owner?: {
    id: string;
    first_name: string;
    last_name: string;
    username: string;
    avatar?: string;
  };
  settings?: {
    allow_member_posts: boolean;
    allow_member_events: boolean;
    allow_member_invites: boolean;
    post_approval_required: boolean;
  };
  last_activity_at?: string;
  unread_count?: number;
  members_preview?: Array<{
    id: string;
    avatar?: string;
  }>;
  created_at: string;
  updated_at?: string;
}

export interface CircleMember {
  id: string;
  user: {
    id: string;
    first_name: string;
    last_name: string;
    username: string;
    avatar?: string;
    is_verified?: boolean;
  };
  role: "owner" | "admin" | "member";
  joined_at: string;
}

// ============================================================================
// NURU CARD TYPES
// ============================================================================

export interface NuruCardType {
  id: string;
  name: string;
  description?: string;
  price: number;
  currency: string;
  features: string[];
  benefits: string[];
  is_active: boolean;
  display_order: number;
}

export interface NuruCard {
  id: string;
  card_number: string;
  type: "regular" | "premium";
  card_type?: NuruCardType;
  status: "active" | "inactive" | "suspended" | "replaced" | "expired";
  holder_name: string;
  qr_code_url: string;
  qr_code_data?: string;
  nfc_enabled: boolean;
  nfc_tag_id?: string;
  design: {
    template: string;
    background_color: string;
    text_color: string;
    custom_image?: string;
  };
  benefits: {
    priority_entry: boolean;
    vip_lounge_access: boolean;
    discount_percentage: number;
    free_drinks: number;
    reserved_seating: boolean;
  };
  usage_stats: {
    total_check_ins: number;
    events_attended: number;
    last_used_at?: string;
  };
  events_attended?: number;
  check_in_history?: Array<{
    id: string;
    event: {
      id: string;
      title: string;
      venue_name?: string;
    };
    checked_in_at: string;
    checked_in_by: string;
    benefits_used: string[];
  }>;
  valid_from: string;
  valid_until: string;
  expires_at?: string;
  created_at: string;
}

export interface NuruCardOrder {
  order_id: string;
  card_id: string;
  card_number: string;
  type: string;
  status: "pending_payment" | "paid" | "processing" | "printed" | "shipped" | "delivered";
  amount: number;
  currency: string;
  payment?: {
    method: string;
    status: string;
    checkout_request_id?: string;
    phone?: string;
    paid_at?: string;
    transaction_id?: string;
  };
  delivery: {
    address: {
      street: string;
      city: string;
      postal_code: string;
      country: string;
      phone?: string;
    };
    status?: string;
    courier?: string;
    tracking_number?: string;
    tracking_url?: string;
    shipped_at?: string;
    estimated_delivery?: string;
  };
  timeline?: Array<{
    status: string;
    timestamp: string;
  }>;
  created_at: string;
}

// ============================================================================
// SUPPORT TYPES
// ============================================================================

export interface SupportTicket {
  id: string;
  ticket_number: string;
  subject: string;
  description: string;
  category: string;
  priority: "low" | "medium" | "high" | "urgent";
  status: "open" | "in_progress" | "waiting_customer" | "resolved" | "closed";
  attachments?: Array<{
    id: string;
    filename: string;
    url: string;
    size: number;
  }>;
  assigned_to?: {
    id: string;
    name: string;
    avatar?: string;
  };
  messages: Array<{
    id: string;
    sender: "user" | "support";
    sender_name?: string;
    sender_avatar?: string;
    content: string;
    attachments?: Array<{
      id: string;
      filename: string;
      url: string;
    }>;
    created_at: string;
  }>;
  created_at: string;
  updated_at: string;
  resolved_at?: string;
}

export interface FAQ {
  id: string;
  category: {
    id: string;
    name: string;
  };
  question: string;
  answer: string;
  helpful_count: number;
  not_helpful_count: number;
  order: number;
  updated_at: string;
}

export interface FAQCategory {
  id: string;
  name: string;
  icon?: string;
  faq_count: number;
  order: number;
}

// ============================================================================
// SETTINGS TYPES
// ============================================================================

export interface UserSettings {
  notifications: {
    email: {
      enabled: boolean;
      event_invitations: boolean;
      event_updates: boolean;
      rsvp_updates: boolean;
      contributions: boolean;
      messages: boolean;
      marketing: boolean;
      weekly_digest: boolean;
    };
    push: {
      enabled: boolean;
      event_invitations: boolean;
      event_updates: boolean;
      rsvp_updates: boolean;
      contributions: boolean;
      messages: boolean;
      glows_and_echoes: boolean;
      new_followers: boolean;
      mentions: boolean;
    };
    sms: {
      enabled: boolean;
      event_reminders: boolean;
      payment_confirmations: boolean;
      security_alerts: boolean;
    };
    quiet_hours: {
      enabled: boolean;
      start_time: string;
      end_time: string;
      timezone: string;
    };
  };
  privacy: {
    profile_visibility: "public" | "followers" | "private";
    show_email: boolean;
    show_phone: boolean;
    show_location: boolean;
    allow_tagging: boolean;
    allow_mentions: boolean;
    show_activity_status: boolean;
    show_read_receipts: boolean;
    allow_message_requests: boolean;
    blocked_users_count?: number;
  };
  security: {
    two_factor_enabled: boolean;
    two_factor_method?: "authenticator" | "sms";
    login_alerts: boolean;
    active_sessions_count: number;
    last_password_change?: string;
  };
  preferences: {
    language: string;
    currency: string;
    timezone: string;
    date_format: string;
    time_format: "12h" | "24h";
    theme: "light" | "dark" | "system";
    compact_mode: boolean;
  };
  connected_accounts: {
    google?: {
      connected: boolean;
      email?: string;
      connected_at?: string;
    };
    facebook?: {
      connected: boolean;
      email?: string;
      connected_at?: string;
    };
    apple?: {
      connected: boolean;
      email?: string;
      connected_at?: string;
    };
  };
  payment_methods: {
    mpesa?: {
      enabled: boolean;
      phone?: string;
      is_default: boolean;
    };
    bank?: {
      enabled: boolean;
      account_number?: string;
      bank_name?: string;
    };
    card?: {
      enabled: boolean;
      last_four?: string;
      brand?: string;
      is_default: boolean;
    };
  };
}

// ============================================================================
// FILE UPLOAD TYPES
// ============================================================================

export interface UploadRequest {
  upload_id: string;
  upload_url: string;
  method: string;
  headers: Record<string, string>;
  expires_at: string;
  max_size: number;
  allowed_types: string[];
}

export interface UploadedFile {
  file_id?: string;
  upload_id?: string;
  file_url: string;
  thumbnail_url?: string;
  file_size: number;
  content_type: string;
  dimensions?: {
    width: number;
    height: number;
  };
  created_at: string;
}

// ============================================================================
// ENUM TYPES
// ============================================================================

export type ChecklistItemStatus = "pending" | "in_progress" | "completed" | "skipped";
export type PriorityLevel = "low" | "medium" | "high" | "critical";
