---

# 📘 NURU - API DOCUMENTATION

## Base Configuration
```
Base URL: ${VITE_API_BASE_URL}
Authentication: Bearer Token (JWT) in Authorization header
Content-Type: application/json (unless multipart/form-data specified)
All timestamps: ISO 8601 format (e.g., "2025-02-05T14:30:00Z")
All UUIDs: Version 4 UUID format
```

## Standard Response Format
```json
{
  "success": true,
  "message": "Operation successful",
  "data": { ... }
}
```

## Standard Error Response
```json
{
  "success": false,
  "message": "Error description",
  "errors": [
    {
      "field": "email",
      "message": "Email is required"
    }
  ]
}
```

## Pagination Standard
All paginated endpoints use the following query parameters and response structure:

**Query Parameters:**
- `page`: integer, default 1, minimum 1
- `limit`: integer, default 20, minimum 1, maximum 100

**Response Structure:**
```json
{
  "success": true,
  "data": {
    "items": [...],
    "pagination": {
      "page": 1,
      "limit": 20,
      "total_items": 150,
      "total_pages": 8,
      "has_next": true,
      "has_previous": false
    }
  }
}
```

---

# 🔐 MODULE 1: AUTHENTICATION

---

## 1.1 Sign Up

Creates a new user account.

```
POST /users/signup
Content-Type: application/json
Authentication: None
```

**Request Body:**

```json
{
  "first_name": "John",
  "last_name": "Doe",
  "username": "johndoe",
  "email": "john@example.com",
  "phone": "+254712345678",
  "password": "SecurePass123!",
  "registered_by": "Jane Smith"
}
```

| Field         | Type   | Required | Validation                                                                                                                                                                                                                                |
| ------------- | ------ | -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| first_name    | string | Yes      | Min 2 chars, max 50 chars, letters only                                                                                                                                                                                                   |
| last_name     | string | Yes      | Min 2 chars, max 50 chars, letters only                                                                                                                                                                                                   |
| username      | string | Yes      | Min 3 chars, max 30 chars, alphanumeric and underscores only, must be unique                                                                                                                                                              |
| email         | string | Yes      | Valid email format, must be unique                                                                                                                                                                                                        |
| phone         | string | Yes      | Valid phone format with country code, must be unique                                                                                                                                                                                      |
| password      | string | Yes      | Min 8 chars, must contain uppercase, lowercase, number                                                                                                                                                                                    |
| registered_by | string | No       | Name of the person registering this user. When provided, a welcome SMS is sent to the new user with the registerer's name, login password, and the Nuru link (https://nuru.tz). Used for inline registration from committee/guest search. |

**Success Response (201 Created):**

```json
{
  "success": true,
  "message": "User created successfully. Please verify your email.",
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000"
  }
}
```

**Error Responses:**

400 Bad Request - Validation Error:

```json
{
  "success": false,
  "message": "Validation failed",
  "errors": [
    {
      "field": "email",
      "message": "Email format is invalid"
    },
    {
      "field": "password",
      "message": "Password must be at least 8 characters"
    }
  ]
}
```

409 Conflict - Duplicate Entry:

```json
{
  "success": false,
  "message": "User already exists",
  "errors": [
    {
      "field": "email",
      "message": "Email is already registered"
    }
  ]
}
```

## 1.1.1 Check Username Availability

Checks if a username is available and returns smart suggestions based on the user's name if taken.

```
GET /users/check-username
Authentication: None (public endpoint)
```

**Query Parameters:**

| Parameter  | Type   | Required | Description                                                     |
| ---------- | ------ | -------- | --------------------------------------------------------------- |
| username   | string | Yes      | The username to check (min 3 chars, alphanumeric + underscores) |
| first_name | string | No       | User's first name — used to generate smarter suggestions        |
| last_name  | string | No       | User's last name — used to generate smarter suggestions         |

**Example Request:**

```
GET /users/check-username?username=johndoe&first_name=John&last_name=Doe
```

**Success Response — Available:**

```json
{
  "success": true,
  "message": "Username is available",
  "data": {
    "available": true,
    "username": "johndoe"
  }
}
```

**Success Response — Taken (with suggestions):**

```json
{
  "success": true,
  "message": "Username is taken",
  "data": {
    "available": false,
    "username": "johndoe",
    "suggestions": ["john_doe", "johnd", "johndoe42", "john_doe3", "johndoe_tz"]
  }
}
```

---

## 1.2 Sign In

Authenticates a user and returns access token.

```
POST /auth/signin
Content-Type: application/json
Authentication: None
```

**Request Body:**

```json
{
  "credential": "john@example.com",
  "password": "SecurePass123!"
}
```

| Field      | Type   | Required | Description                             |
| ---------- | ------ | -------- | --------------------------------------- |
| credential | string | Yes      | Can be email, phone number, or username |
| password   | string | Yes      | User's password                         |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Login successful",
  "data": {
    "user": {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "first_name": "John",
      "last_name": "Doe",
      "username": "johndoe",
      "email": "john@example.com",
      "phone": "+254712345678",
      "avatar": "https://storage.nuru.com/avatars/550e8400.jpg",
      "bio": "Event enthusiast and photographer",
      "location": "Nairobi, Kenya",
      "is_email_verified": true,
      "is_phone_verified": true,
      "created_at": "2025-01-15T10:30:00Z",
      "updated_at": "2025-02-01T14:20:00Z"
    },
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "token_type": "Bearer",
    "expires_in": 3600
  }
}
```

**Error Responses:**

401 Unauthorized - Invalid Credentials:

```json
{
  "success": false,
  "message": "Invalid email or password"
}
```

403 Forbidden - Email Not Verified:

```json
{
  "success": false,
  "message": "Please verify your email before signing in",
  "data": {
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "verification_required": "email"
  }
}
```

403 Forbidden - Account Suspended:

```json
{
  "success": false,
  "message": "Your account has been suspended. Contact support."
}
```

---

## 1.3 Logout

Invalidates the current access token.

```
POST /auth/logout
Content-Type: application/json
Authorization: Bearer {access_token}
```

**Request Body:** None

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Logged out successfully"
}
```

**Error Response (401 Unauthorized):**

```json
{
  "success": false,
  "message": "Invalid or expired token"
}
```

---

## 1.4 Refresh Token

Refreshes an expired access token.

```
POST /auth/refresh
Content-Type: application/json
Authentication: None
```

**Request Body:**

```json
{
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Token refreshed successfully",
  "data": {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "token_type": "Bearer",
    "expires_in": 3600
  }
}
```

**Error Response (401 Unauthorized):**

```json
{
  "success": false,
  "message": "Invalid or expired refresh token"
}
```

---

## 1.5 Get Current User

Returns the authenticated user's profile.

```
GET /auth/me
Authorization: Bearer {access_token}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "User retrieved successfully",
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "first_name": "John",
    "last_name": "Doe",
    "username": "johndoe",
    "email": "john@example.com",
    "phone": "+254712345678",
    "avatar": "https://storage.nuru.com/avatars/550e8400.jpg",
    "bio": "Event enthusiast and photographer",
    "location": "Nairobi, Kenya",
    "is_email_verified": true,
    "is_phone_verified": true,
    "is_vendor": true,
    "follower_count": 245,
    "following_count": 180,
    "event_count": 12,
    "service_count": 2,
    "created_at": "2025-01-15T10:30:00Z",
    "updated_at": "2025-02-01T14:20:00Z"
  }
}
```

---

## 1.6 Verify OTP

Verifies email or phone using OTP code.

```
POST /users/verify-otp
Content-Type: application/json
Authentication: None
```

**Request Body:**

```json
{
  "user_id": "550e8400-e29b-41d4-a716-446655440000",
  "verification_type": "email",
  "otp_code": "123456"
}
```

| Field             | Type   | Required | Description               |
| ----------------- | ------ | -------- | ------------------------- |
| user_id           | uuid   | Yes      | User's unique identifier  |
| verification_type | string | Yes      | Either "email" or "phone" |
| otp_code          | string | Yes      | 6-digit OTP code          |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Email verified successfully",
  "data": {
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "verification_type": "email",
    "verified_at": "2025-02-05T14:30:00Z"
  }
}
```

**Error Responses:**

400 Bad Request - Invalid OTP:

```json
{
  "success": false,
  "message": "Invalid OTP code"
}
```

400 Bad Request - Expired OTP:

```json
{
  "success": false,
  "message": "OTP code has expired. Please request a new one."
}
```

404 Not Found:

```json
{
  "success": false,
  "message": "User not found"
}
```

---

## 1.7 Request OTP

Sends a new OTP code to user's email or phone.

```
POST /users/request-otp
Content-Type: application/json
Authentication: None
```

**Request Body:**

```json
{
  "user_id": "550e8400-e29b-41d4-a716-446655440000",
  "verification_type": "email"
}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "OTP sent successfully",
  "data": {
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "verification_type": "email",
    "expires_in": 300,
    "sent_to": "j***@example.com"
  }
}
```

**Error Responses:**

404 Not Found:

```json
{
  "success": false,
  "message": "User not found"
}
```

429 Too Many Requests:

```json
{
  "success": false,
  "message": "Too many OTP requests. Please wait 60 seconds.",
  "data": {
    "retry_after": 60
  }
}
```

---

## 1.8 Forgot Password

Initiates password reset process.

```
POST /auth/forgot-password
Content-Type: application/json
Authentication: None
```

**Request Body:**

```json
{
  "email": "john@example.com"
}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Password reset instructions sent to your email"
}
```

**Error Response (404 Not Found):**

```json
{
  "success": false,
  "message": "No account found with this email address"
}
```

---

## 1.9 Reset Password

Resets password using reset token.

```
POST /auth/reset-password
Content-Type: application/json
Authentication: None
```

**Request Body:**

```json
{
  "token": "abc123def456...",
  "password": "NewSecurePass123!",
  "password_confirmation": "NewSecurePass123!"
}
```

| Field                 | Type   | Required | Validation                                             |
| --------------------- | ------ | -------- | ------------------------------------------------------ |
| token                 | string | Yes      | Reset token from email link                            |
| password              | string | Yes      | Min 8 chars, must contain uppercase, lowercase, number |
| password_confirmation | string | Yes      | Must match password                                    |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Password reset successfully. You can now sign in."
}
```

**Error Responses:**

400 Bad Request - Invalid Token:

```json
{
  "success": false,
  "message": "Invalid or expired reset token"
}
```

400 Bad Request - Password Mismatch:

```json
{
  "success": false,
  "message": "Passwords do not match"
}
```

---

# 📚 MODULE 2: REFERENCES

---

## 2.1 Get All Event Types

Returns all available event types.

```
GET /references/event-types
Authentication: None
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Event types retrieved successfully",
  "data": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440001",
      "name": "Wedding",
      "description": "Wedding ceremonies and receptions",
      "icon": "rings",
      "color": "#FF6B6B",
      "is_active": true,
      "display_order": 1,
      "created_at": "2025-01-01T00:00:00Z"
    },
    {
      "id": "550e8400-e29b-41d4-a716-446655440002",
      "name": "Birthday",
      "description": "Birthday parties and celebrations",
      "icon": "cake",
      "color": "#4ECDC4",
      "is_active": true,
      "display_order": 2,
      "created_at": "2025-01-01T00:00:00Z"
    },
    {
      "id": "550e8400-e29b-41d4-a716-446655440003",
      "name": "Corporate Event",
      "description": "Business meetings, conferences, and corporate gatherings",
      "icon": "briefcase",
      "color": "#45B7D1",
      "is_active": true,
      "display_order": 3,
      "created_at": "2025-01-01T00:00:00Z"
    },
    {
      "id": "550e8400-e29b-41d4-a716-446655440004",
      "name": "Graduation",
      "description": "Graduation ceremonies and parties",
      "icon": "graduation-cap",
      "color": "#96CEB4",
      "is_active": true,
      "display_order": 4,
      "created_at": "2025-01-01T00:00:00Z"
    },
    {
      "id": "550e8400-e29b-41d4-a716-446655440005",
      "name": "Baby Shower",
      "description": "Baby shower celebrations",
      "icon": "baby",
      "color": "#DDA0DD",
      "is_active": true,
      "display_order": 5,
      "created_at": "2025-01-01T00:00:00Z"
    },
    {
      "id": "550e8400-e29b-41d4-a716-446655440006",
      "name": "Funeral",
      "description": "Memorial services and funeral arrangements",
      "icon": "flower",
      "color": "#708090",
      "is_active": true,
      "display_order": 6,
      "created_at": "2025-01-01T00:00:00Z"
    },
    {
      "id": "550e8400-e29b-41d4-a716-446655440007",
      "name": "Anniversary",
      "description": "Wedding anniversaries and milestone celebrations",
      "icon": "heart",
      "color": "#FF69B4",
      "is_active": true,
      "display_order": 7,
      "created_at": "2025-01-01T00:00:00Z"
    },
    {
      "id": "550e8400-e29b-41d4-a716-446655440008",
      "name": "Religious Event",
      "description": "Religious ceremonies and gatherings",
      "icon": "church",
      "color": "#DAA520",
      "is_active": true,
      "display_order": 8,
      "created_at": "2025-01-01T00:00:00Z"
    },
    {
      "id": "550e8400-e29b-41d4-a716-446655440009",
      "name": "Concert/Music Event",
      "description": "Live music performances and concerts",
      "icon": "music",
      "color": "#9370DB",
      "is_active": true,
      "display_order": 9,
      "created_at": "2025-01-01T00:00:00Z"
    },
    {
      "id": "550e8400-e29b-41d4-a716-446655440010",
      "name": "Other",
      "description": "Other types of events",
      "icon": "calendar",
      "color": "#808080",
      "is_active": true,
      "display_order": 100,
      "created_at": "2025-01-01T00:00:00Z"
    }
  ]
}
```

---

## 2.2 Get All Service Categories

Returns all available service categories.

```
GET /references/service-categories
Authentication: None
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Service categories retrieved successfully",
  "data": [
    {
      "id": "650e8400-e29b-41d4-a716-446655440001",
      "name": "Photography & Videography",
      "description": "Professional photography and videography services",
      "icon": "camera",
      "image_url": "https://storage.nuru.com/categories/photography.jpg",
      "is_active": true,
      "display_order": 1,
      "service_count": 245,
      "created_at": "2025-01-01T00:00:00Z"
    },
    {
      "id": "650e8400-e29b-41d4-a716-446655440002",
      "name": "Catering & Food",
      "description": "Catering services and food vendors",
      "icon": "utensils",
      "image_url": "https://storage.nuru.com/categories/catering.jpg",
      "is_active": true,
      "display_order": 2,
      "service_count": 189,
      "created_at": "2025-01-01T00:00:00Z"
    },
    {
      "id": "650e8400-e29b-41d4-a716-446655440003",
      "name": "Venues",
      "description": "Event venues and spaces",
      "icon": "building",
      "image_url": "https://storage.nuru.com/categories/venues.jpg",
      "is_active": true,
      "display_order": 3,
      "service_count": 156,
      "created_at": "2025-01-01T00:00:00Z"
    },
    {
      "id": "650e8400-e29b-41d4-a716-446655440004",
      "name": "Decoration & Flowers",
      "description": "Event decoration and floral arrangements",
      "icon": "flower",
      "image_url": "https://storage.nuru.com/categories/decoration.jpg",
      "is_active": true,
      "display_order": 4,
      "service_count": 134,
      "created_at": "2025-01-01T00:00:00Z"
    },
    {
      "id": "650e8400-e29b-41d4-a716-446655440005",
      "name": "Entertainment",
      "description": "DJs, bands, MCs, and entertainment services",
      "icon": "music",
      "image_url": "https://storage.nuru.com/categories/entertainment.jpg",
      "is_active": true,
      "display_order": 5,
      "service_count": 178,
      "created_at": "2025-01-01T00:00:00Z"
    },
    {
      "id": "650e8400-e29b-41d4-a716-446655440006",
      "name": "Beauty & Styling",
      "description": "Makeup artists, hair stylists, and beauty services",
      "icon": "sparkles",
      "image_url": "https://storage.nuru.com/categories/beauty.jpg",
      "is_active": true,
      "display_order": 6,
      "service_count": 167,
      "created_at": "2025-01-01T00:00:00Z"
    },
    {
      "id": "650e8400-e29b-41d4-a716-446655440007",
      "name": "Transportation",
      "description": "Event transportation and car hire",
      "icon": "car",
      "image_url": "https://storage.nuru.com/categories/transport.jpg",
      "is_active": true,
      "display_order": 7,
      "service_count": 89,
      "created_at": "2025-01-01T00:00:00Z"
    },
    {
      "id": "650e8400-e29b-41d4-a716-446655440008",
      "name": "Event Planning",
      "description": "Full event planning and coordination services",
      "icon": "clipboard",
      "image_url": "https://storage.nuru.com/categories/planning.jpg",
      "is_active": true,
      "display_order": 8,
      "service_count": 112,
      "created_at": "2025-01-01T00:00:00Z"
    },
    {
      "id": "650e8400-e29b-41d4-a716-446655440009",
      "name": "Equipment Rental",
      "description": "Tents, chairs, tables, sound systems rental",
      "icon": "tent",
      "image_url": "https://storage.nuru.com/categories/equipment.jpg",
      "is_active": true,
      "display_order": 9,
      "service_count": 145,
      "created_at": "2025-01-01T00:00:00Z"
    },
    {
      "id": "650e8400-e29b-41d4-a716-446655440010",
      "name": "Cakes & Desserts",
      "description": "Custom cakes, desserts, and confectionery",
      "icon": "cake",
      "image_url": "https://storage.nuru.com/categories/cakes.jpg",
      "is_active": true,
      "display_order": 10,
      "service_count": 98,
      "created_at": "2025-01-01T00:00:00Z"
    },
    {
      "id": "650e8400-e29b-41d4-a716-446655440011",
      "name": "Security",
      "description": "Event security and crowd management",
      "icon": "shield",
      "image_url": "https://storage.nuru.com/categories/security.jpg",
      "is_active": true,
      "display_order": 11,
      "service_count": 56,
      "created_at": "2025-01-01T00:00:00Z"
    },
    {
      "id": "650e8400-e29b-41d4-a716-446655440012",
      "name": "Printing & Stationery",
      "description": "Invitations, programs, and event stationery",
      "icon": "printer",
      "image_url": "https://storage.nuru.com/categories/printing.jpg",
      "is_active": true,
      "display_order": 12,
      "service_count": 67,
      "created_at": "2025-01-01T00:00:00Z"
    }
  ]
}
```

---

## 2.3 Get Service Types by Category

Returns all service types within a specific category.

```
GET /references/service-types/category/{categoryId}
Authentication: None
```

**Path Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| categoryId | uuid | Yes | Service category ID |

**Example Request:**

```
GET /references/service-types/category/650e8400-e29b-41d4-a716-446655440001
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Service types retrieved successfully",
  "data": [
    {
      "id": "750e8400-e29b-41d4-a716-446655440001",
      "category_id": "650e8400-e29b-41d4-a716-446655440001",
      "name": "Wedding Photography",
      "description": "Professional wedding photography services",
      "is_active": true,
      "display_order": 1,
      "service_count": 89,
      "created_at": "2025-01-01T00:00:00Z"
    },
    {
      "id": "750e8400-e29b-41d4-a716-446655440002",
      "category_id": "650e8400-e29b-41d4-a716-446655440001",
      "name": "Event Photography",
      "description": "Photography for corporate and social events",
      "is_active": true,
      "display_order": 2,
      "service_count": 67,
      "created_at": "2025-01-01T00:00:00Z"
    },
    {
      "id": "750e8400-e29b-41d4-a716-446655440003",
      "category_id": "650e8400-e29b-41d4-a716-446655440001",
      "name": "Videography",
      "description": "Professional video recording and editing",
      "is_active": true,
      "display_order": 3,
      "service_count": 54,
      "created_at": "2025-01-01T00:00:00Z"
    },
    {
      "id": "750e8400-e29b-41d4-a716-446655440004",
      "category_id": "650e8400-e29b-41d4-a716-446655440001",
      "name": "Drone Photography",
      "description": "Aerial photography and videography using drones",
      "is_active": true,
      "display_order": 4,
      "service_count": 23,
      "created_at": "2025-01-01T00:00:00Z"
    },
    {
      "id": "750e8400-e29b-41d4-a716-446655440005",
      "category_id": "650e8400-e29b-41d4-a716-446655440001",
      "name": "Photo Booth",
      "description": "Photo booth rental and services",
      "is_active": true,
      "display_order": 5,
      "service_count": 12,
      "created_at": "2025-01-01T00:00:00Z"
    }
  ]
}
```

**Error Response (404 Not Found):**

```json
{
  "success": false,
  "message": "Service category not found"
}
```

---

## 2.4 Get KYC Requirements for Service Type

Returns all KYC requirements for a specific service type.

```
GET /references/service-types/{serviceTypeId}/kyc
Authentication: None
```

**Path Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| serviceTypeId | uuid | Yes | Service type ID |

**Example Request:**

```
GET /references/service-types/750e8400-e29b-41d4-a716-446655440001/kyc
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "KYC requirements retrieved successfully",
  "data": [
    {
      "id": "850e8400-e29b-41d4-a716-446655440001",
      "service_type_id": "750e8400-e29b-41d4-a716-446655440001",
      "name": "National ID / Passport",
      "description": "A valid government-issued identification document",
      "document_type": "identity",
      "is_required": true,
      "accepted_formats": ["jpg", "jpeg", "png", "pdf"],
      "max_file_size_mb": 5,
      "display_order": 1,
      "created_at": "2025-01-01T00:00:00Z"
    },
    {
      "id": "850e8400-e29b-41d4-a716-446655440002",
      "service_type_id": "750e8400-e29b-41d4-a716-446655440001",
      "name": "Business Registration Certificate",
      "description": "Proof of business registration if operating as a company",
      "document_type": "business",
      "is_required": false,
      "accepted_formats": ["jpg", "jpeg", "png", "pdf"],
      "max_file_size_mb": 5,
      "display_order": 2,
      "created_at": "2025-01-01T00:00:00Z"
    },
    {
      "id": "850e8400-e29b-41d4-a716-446655440003",
      "service_type_id": "750e8400-e29b-41d4-a716-446655440001",
      "name": "Portfolio Samples",
      "description": "At least 5 samples of your previous work",
      "document_type": "portfolio",
      "is_required": true,
      "accepted_formats": ["jpg", "jpeg", "png"],
      "max_file_size_mb": 10,
      "display_order": 3,
      "created_at": "2025-01-01T00:00:00Z"
    },
    {
      "id": "850e8400-e29b-41d4-a716-446655440004",
      "service_type_id": "750e8400-e29b-41d4-a716-446655440001",
      "name": "Professional Certification",
      "description": "Any relevant professional photography certifications",
      "document_type": "certification",
      "is_required": false,
      "accepted_formats": ["jpg", "jpeg", "png", "pdf"],
      "max_file_size_mb": 5,
      "display_order": 4,
      "created_at": "2025-01-01T00:00:00Z"
    },
    {
      "id": "850e8400-e29b-41d4-a716-446655440005",
      "service_type_id": "750e8400-e29b-41d4-a716-446655440001",
      "name": "Tax Compliance Certificate",
      "description": "Valid tax compliance certificate (KRA PIN certificate)",
      "document_type": "tax",
      "is_required": true,
      "accepted_formats": ["pdf"],
      "max_file_size_mb": 5,
      "display_order": 5,
      "created_at": "2025-01-01T00:00:00Z"
    }
  ]
}
```

---

## 2.5 Get All Currencies

Returns all supported currencies.

```
GET /references/currencies
Authentication: None
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Currencies retrieved successfully",
  "data": [
    {
      "id": "950e8400-e29b-41d4-a716-446655440001",
      "code": "KES",
      "name": "Kenyan Shilling",
      "symbol": "KSh",
      "is_default": true,
      "is_active": true
    },
    {
      "id": "950e8400-e29b-41d4-a716-446655440002",
      "code": "USD",
      "name": "US Dollar",
      "symbol": "$",
      "is_default": false,
      "is_active": true
    },
    {
      "id": "950e8400-e29b-41d4-a716-446655440003",
      "code": "EUR",
      "name": "Euro",
      "symbol": "€",
      "is_default": false,
      "is_active": true
    },
    {
      "id": "950e8400-e29b-41d4-a716-446655440004",
      "code": "GBP",
      "name": "British Pound",
      "symbol": "£",
      "is_default": false,
      "is_active": true
    },
    {
      "id": "950e8400-e29b-41d4-a716-446655440005",
      "code": "TZS",
      "name": "Tanzanian Shilling",
      "symbol": "TSh",
      "is_default": false,
      "is_active": true
    },
    {
      "id": "950e8400-e29b-41d4-a716-446655440006",
      "code": "UGX",
      "name": "Ugandan Shilling",
      "symbol": "USh",
      "is_default": false,
      "is_active": true
    }
  ]
}
```

---

## 2.6 Get All Countries

Returns all supported countries.

```
GET /references/countries
Authentication: None
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Countries retrieved successfully",
  "data": [
    {
      "id": "a50e8400-e29b-41d4-a716-446655440001",
      "code": "KE",
      "name": "Kenya",
      "phone_code": "+254",
      "currency_code": "KES",
      "is_active": true
    },
    {
      "id": "a50e8400-e29b-41d4-a716-446655440002",
      "code": "TZ",
      "name": "Tanzania",
      "phone_code": "+255",
      "currency_code": "TZS",
      "is_active": true
    },
    {
      "id": "a50e8400-e29b-41d4-a716-446655440003",
      "code": "UG",
      "name": "Uganda",
      "phone_code": "+256",
      "currency_code": "UGX",
      "is_active": true
    },
    {
      "id": "a50e8400-e29b-41d4-a716-446655440004",
      "code": "RW",
      "name": "Rwanda",
      "phone_code": "+250",
      "currency_code": "RWF",
      "is_active": true
    },
    {
      "id": "a50e8400-e29b-41d4-a716-446655440005",
      "code": "NG",
      "name": "Nigeria",
      "phone_code": "+234",
      "currency_code": "NGN",
      "is_active": true
    },
    {
      "id": "a50e8400-e29b-41d4-a716-446655440006",
      "code": "ZA",
      "name": "South Africa",
      "phone_code": "+27",
      "currency_code": "ZAR",
      "is_active": true
    }
  ]
}
```

---

# 🎉 MODULE 3: USER EVENTS

---

## 3.1 Get All User Events

Returns all events created by the authenticated user.

```
GET /user-events/
Authorization: Bearer {access_token}
```

---

### 3.1.1 GET /user-events/invited — Events User Is Invited To

Returns events the authenticated user has been invited to, with RSVP status and invitation details.

```
GET /user-events/invited
Authorization: Bearer {access_token}
```

**Query Parameters:** `page` (int, default 1), `limit` (int, default 20)

**Success Response:**

```json
{
  "success": true,
  "data": {
    "events": [
      {
        "id": "uuid",
        "title": "Wedding",
        "event_type": { "id": "uuid", "name": "Wedding" },
        "start_date": "2025-08-15",
        "start_time": "14:00",
        "location": "Dar es Salaam",
        "organizer": { "name": "Jane Doe" },
        "invitation": {
          "id": "uuid",
          "rsvp_status": "pending",
          "invitation_code": "ABC123",
          "invited_at": "2025-06-01T10:00:00"
        },
        "attendee_id": "uuid"
      }
    ],
    "pagination": { "page": 1, "limit": 20, "total_items": 3, "total_pages": 1 }
  }
}
```

---

### 3.1.2 GET /user-events/committee — Events User Manages As Committee

Returns events where the authenticated user is a committee member, with role and permissions.

```
GET /user-events/committee
Authorization: Bearer {access_token}
```

**Query Parameters:** `page` (int, default 1), `limit` (int, default 20)

**Success Response:**

```json
{
  "success": true,
  "data": {
    "events": [
      {
        "id": "uuid",
        "title": "Corporate Gala",
        "event_type": { "id": "uuid", "name": "Corporate" },
        "start_date": "2025-09-20",
        "location": "Arusha",
        "organizer": { "name": "John Doe" },
        "committee_membership": {
          "id": "uuid",
          "role": "Coordinator",
          "role_description": "Manages logistics",
          "permissions": {
            "can_view_guests": true,
            "can_manage_guests": true,
            "can_edit_event": false
          }
        },
        "guest_count": 150,
        "confirmed_guest_count": 80
      }
    ],
    "pagination": { "page": 1, "limit": 20, "total_items": 1, "total_pages": 1 }
  }
}
```

---

### 3.1.3 GET /user-events/{eventId}/invitation-card — Digital Invitation Card

Returns all data needed to render and print a digital invitation card with QR code data. Requires the user to have been invited to the event.

```
GET /user-events/{eventId}/invitation-card
Authorization: Bearer {access_token}
```

**Success Response:**

```json
{
  "success": true,
  "data": {
    "event": {
      "id": "uuid",
      "title": "Wedding",
      "event_type": "Wedding",
      "start_date": "2025-08-15",
      "start_time": "14:00",
      "location": "Dar es Salaam",
      "venue": "Serena Hotel",
      "theme_color": "#FF6B6B",
      "dress_code": "Formal"
    },
    "guest": {
      "name": "Alice Smith",
      "attendee_id": "uuid",
      "rsvp_status": "confirmed"
    },
    "organizer": { "name": "Jane Doe" },
    "invitation_code": "ABC123",
    "qr_code_data": "nuru://event/uuid/checkin/uuid",
    "rsvp_deadline": "2025-08-01T23:59:59"
  }
}
```

### 3.1.4 PUT /user-events/invited/{eventId}/rsvp — Respond to Invitation (Authenticated)

Allows an authenticated invited user to accept or decline an event invitation. Updates both the invitation and attendee records.

```
PUT /user-events/invited/{eventId}/rsvp
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:**

```json
{
  "rsvp_status": "confirmed",
  "meal_preference": "Vegetarian",
  "dietary_restrictions": "No nuts",
  "special_requests": "Wheelchair access needed"
}
```

| Field                | Type   | Required | Description                                   |
| -------------------- | ------ | -------- | --------------------------------------------- |
| rsvp_status          | string | Yes      | Response status: confirmed, declined, pending |
| meal_preference      | string | No       | Guest's meal preference                       |
| dietary_restrictions | string | No       | Dietary restrictions                          |
| special_requests     | string | No       | Special requests or notes                     |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "RSVP updated successfully",
  "data": {
    "event_id": "b50e8400-e29b-41d4-a716-446655440001",
    "rsvp_status": "confirmed",
    "rsvp_at": "2025-02-08T14:30:00+03:00",
    "attendee_id": "c50e8400-e29b-41d4-a716-446655440001"
  }
}
```

**Error Responses:**

400 Bad Request - Invalid Status:

```json
{
  "success": false,
  "message": "Invalid rsvp_status. Must be one of: confirmed, declined, pending"
}
```

404 Not Found - No Invitation:

```json
{
  "success": false,
  "message": "You do not have an invitation for this event"
}
```

## 1.1.1 Check Username Availability

Checks if a username is available and returns smart suggestions based on the user's name if taken.

```
GET /users/check-username
Authentication: None (public endpoint)
```

**Query Parameters:**

| Parameter  | Type   | Required | Description                                                     |
| ---------- | ------ | -------- | --------------------------------------------------------------- |
| username   | string | Yes      | The username to check (min 3 chars, alphanumeric + underscores) |
| first_name | string | No       | User's first name — used to generate smarter suggestions        |
| last_name  | string | No       | User's last name — used to generate smarter suggestions         |

**Example Request:**

```
GET /users/check-username?username=johndoe&first_name=John&last_name=Doe
```

**Success Response — Available:**

```json
{
  "success": true,
  "message": "Username is available",
  "data": {
    "available": true,
    "username": "johndoe"
  }
}
```

**Success Response — Taken (with suggestions):**

```json
{
  "success": true,
  "message": "Username is taken",
  "data": {
    "available": false,
    "username": "johndoe",
    "suggestions": ["john_doe", "johnd", "johndoe42", "john_doe3", "johndoe_tz"]
  }
}
```

**Error Response — Invalid username:**

```json
{
  "success": false,
  "message": "Username can only contain letters, numbers, and underscores"
}
```

## 1.1.1 Check Username Availability

Checks if a username is available and returns smart suggestions based on the user's name if taken.

```
GET /users/check-username
Authentication: None (public endpoint)
```

**Query Parameters:**

| Parameter  | Type   | Required | Description                                                     |
| ---------- | ------ | -------- | --------------------------------------------------------------- |
| username   | string | Yes      | The username to check (min 3 chars, alphanumeric + underscores) |
| first_name | string | No       | User's first name — used to generate smarter suggestions        |
| last_name  | string | No       | User's last name — used to generate smarter suggestions         |

**Example Request:**

```
GET /users/check-username?username=johndoe&first_name=John&last_name=Doe
```

**Success Response — Available:**

```json
{
  "success": true,
  "message": "Username is available",
  "data": {
    "available": true,
    "username": "johndoe"
  }
}
```

**Success Response — Taken (with suggestions):**

```json
{
  "success": true,
  "message": "Username is taken",
  "data": {
    "available": false,
    "username": "johndoe",
    "suggestions": ["john_doe", "johnd", "johndoe42", "john_doe3", "johndoe_tz"]
  }
}
```

**Error Response — Invalid username:**

```json
{
  "success": false,
  "message": "Username can only contain letters, numbers, and underscores"
}
```

---

**Query Parameters:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| page | integer | No | 1 | Page number |
| limit | integer | No | 20 | Items per page (max 100) |
| status | string | No | all | Filter by status: draft, published, cancelled, completed, all |
| sort_by | string | No | created_at | Sort field: created_at, start_date, title |
| sort_order | string | No | desc | Sort order: asc, desc |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Events retrieved successfully",
  "data": {
    "events": [
      {
        "id": "b50e8400-e29b-41d4-a716-446655440001",
        "user_id": "550e8400-e29b-41d4-a716-446655440000",
        "title": "John & Jane's Wedding",
        "description": "A beautiful garden wedding ceremony followed by an elegant reception dinner.",
        "event_type_id": "550e8400-e29b-41d4-a716-446655440001",
        "event_type": {
          "id": "550e8400-e29b-41d4-a716-446655440001",
          "name": "Wedding",
          "icon": "rings",
          "color": "#FF6B6B"
        },
        "start_date": "2025-06-15T14:00:00Z",
        "end_date": "2025-06-15T23:00:00Z",
        "location": "Nairobi, Kenya",
        "venue": "The Great Rift Valley Lodge",
        "venue_address": "P.O. Box 12345, Naivasha",
        "venue_coordinates": {
          "latitude": -0.7893,
          "longitude": 36.4344
        },
        "cover_image": "https://storage.nuru.com/events/b50e8400-cover.jpg",
        "images": [
          {
            "id": "img-001",
            "image_url": "https://storage.nuru.com/events/b50e8400-cover.jpg",
            "caption": "Venue entrance",
            "is_featured": true,
            "created_at": "2025-01-20T10:30:00Z"
          },
          {
            "id": "img-002",
            "image_url": "https://storage.nuru.com/events/b50e8400-gallery-1.jpg",
            "caption": null,
            "is_featured": false,
            "created_at": "2025-01-20T10:31:00Z"
          }
        ],
        "theme_color": "#FF6B6B",
        "is_public": true,
        "status": "published",
        "budget": 500000.0,
        "currency": "KES",
        "expected_guests": 200,
        "guest_count": 150,
        "confirmed_guest_count": 89,
        "pending_guest_count": 45,
        "declined_guest_count": 16,
        "checked_in_count": 0,
        "contribution_target": 1000000.0,
        "contribution_total": 456000.0,
        "contribution_count": 34,
        "committee_count": 5,
        "service_booking_count": 8,
        "created_at": "2025-01-20T10:30:00Z",
        "updated_at": "2025-02-01T14:20:00Z"
      },
      {
        "id": "b50e8400-e29b-41d4-a716-446655440002",
        "user_id": "550e8400-e29b-41d4-a716-446655440000",
        "title": "David's 30th Birthday",
        "description": "Celebrating David's milestone birthday with friends and family.",
        "event_type_id": "550e8400-e29b-41d4-a716-446655440002",
        "event_type": {
          "id": "550e8400-e29b-41d4-a716-446655440002",
          "name": "Birthday",
          "icon": "cake",
          "color": "#4ECDC4"
        },
        "start_date": "2025-03-20T18:00:00Z",
        "end_date": "2025-03-20T23:59:00Z",
        "location": "Mombasa, Kenya",
        "venue": "Tamarind Restaurant",
        "venue_address": "Cement Silo Rd, Mombasa",
        "venue_coordinates": {
          "latitude": -4.0435,
          "longitude": 39.6682
        },
        "cover_image": "https://storage.nuru.com/events/b50e8400-002-cover.jpg",
        "images": [],
        "theme_color": "#4ECDC4",
        "is_public": false,
        "status": "draft",
        "budget": 150000.0,
        "currency": "KES",
        "expected_guests": 60,
        "guest_count": 50,
        "confirmed_guest_count": 0,
        "pending_guest_count": 50,
        "declined_guest_count": 0,
        "checked_in_count": 0,
        "contribution_target": 0,
        "contribution_total": 0,
        "contribution_count": 0,
        "committee_count": 2,
        "service_booking_count": 3,
        "created_at": "2025-02-01T08:00:00Z",
        "updated_at": "2025-02-05T09:15:00Z"
      }
    ],
    "pagination": {
      "page": 1,
      "limit": 20,
      "total_items": 2,
      "total_pages": 1,
      "has_next": false,
      "has_previous": false
    }
  }
}
```

---

## 3.2 Get Single Event

Returns detailed information about a specific event.

```
GET /user-events/{eventId}
Authorization: Bearer {access_token}
```

**Path Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| eventId | uuid | Yes | Event unique identifier |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Event retrieved successfully",
  "data": {
    "id": "b50e8400-e29b-41d4-a716-446655440001",
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "title": "John & Jane's Wedding",
    "description": "A beautiful garden wedding ceremony followed by an elegant reception dinner. Join us as we celebrate the union of John and Jane in a day filled with love, laughter, and cherished memories.",
    "event_type_id": "550e8400-e29b-41d4-a716-446655440001",
    "event_type": {
      "id": "550e8400-e29b-41d4-a716-446655440001",
      "name": "Wedding",
      "icon": "rings",
      "color": "#FF6B6B"
    },
    "start_date": "2025-06-15T14:00:00Z",
    "end_date": "2025-06-15T23:00:00Z",
    "location": "Nairobi, Kenya",
    "venue": "The Great Rift Valley Lodge",
    "venue_address": "P.O. Box 12345, Naivasha, Kenya",
    "venue_coordinates": {
      "latitude": -0.7893,
      "longitude": 36.4344
    },
    "cover_image": "https://storage.nuru.com/events/b50e8400-cover.jpg",
    "images": [
      {
        "id": "img-001",
        "image_url": "https://storage.nuru.com/events/b50e8400-cover.jpg",
        "caption": "Venue entrance",
        "is_featured": true,
        "created_at": "2025-01-20T10:30:00Z"
      },
      {
        "id": "img-002",
        "image_url": "https://storage.nuru.com/events/b50e8400-gallery-1.jpg",
        "caption": null,
        "is_featured": false,
        "created_at": "2025-01-20T10:31:00Z"
      },
      {
        "id": "img-003",
        "image_url": "https://storage.nuru.com/events/b50e8400-gallery-2.jpg",
        "caption": null,
        "is_featured": false,
        "created_at": "2025-01-20T10:32:00Z"
      }
    ],
    "gallery_images": [
      "https://storage.nuru.com/events/b50e8400-gallery-1.jpg",
      "https://storage.nuru.com/events/b50e8400-gallery-2.jpg",
      "https://storage.nuru.com/events/b50e8400-gallery-3.jpg"
    ],
    "theme_color": "#FF6B6B",
    "is_public": true,
    "status": "published",
    "budget": 500000.0,
    "currency": "KES",
    "dress_code": "Formal - Black tie optional",
    "special_instructions": "Please arrive 30 minutes before the ceremony starts. Parking is available at the venue.",
    "rsvp_deadline": "2025-06-01T23:59:59Z",
    "contribution_enabled": true,
    "contribution_target": 1000000.0,
    "contribution_description": "Help us start our new life together. Your generous contributions will go towards our honeymoon fund.",
    "expected_guests": 200,
    "guest_count": 150,
    "confirmed_guest_count": 89,
    "pending_guest_count": 45,
    "declined_guest_count": 16,
    "checked_in_count": 0,
    "contribution_total": 456000.0,
    "contribution_count": 34,
    "guests": [
      {
        "id": "c50e8400-e29b-41d4-a716-446655440001",
        "event_id": "b50e8400-e29b-41d4-a716-446655440001",
        "name": "Michael Johnson",
        "email": "michael@example.com",
        "phone": "+254712345679",
        "rsvp_status": "confirmed",
        "table_number": "A1",
        "seat_number": 3,
        "dietary_requirements": "Vegetarian",
        "plus_ones": 1,
        "plus_one_names": ["Sarah Johnson"],
        "notes": "Best friend of the groom",
        "invitation_sent": true,
        "invitation_sent_at": "2025-02-01T10:00:00Z",
        "invitation_method": "email",
        "checked_in": false,
        "checked_in_at": null,
        "created_at": "2025-01-25T10:30:00Z",
        "updated_at": "2025-02-03T14:20:00Z"
      },
      {
        "id": "c50e8400-e29b-41d4-a716-446655440002",
        "event_id": "b50e8400-e29b-41d4-a716-446655440001",
        "name": "Emily Davis",
        "email": "emily@example.com",
        "phone": "+254712345680",
        "rsvp_status": "pending",
        "table_number": null,
        "seat_number": null,
        "dietary_requirements": null,
        "plus_ones": 0,
        "plus_one_names": [],
        "notes": "College friend",
        "invitation_sent": true,
        "invitation_sent_at": "2025-02-01T10:00:00Z",
        "invitation_method": "whatsapp",
        "checked_in": false,
        "checked_in_at": null,
        "created_at": "2025-01-25T10:35:00Z",
        "updated_at": "2025-01-25T10:35:00Z"
      }
    ],
    "committee_members": [
      {
        "id": "d50e8400-e29b-41d4-a716-446655440001",
        "event_id": "b50e8400-e29b-41d4-a716-446655440001",
        "user_id": "550e8400-e29b-41d4-a716-446655440010",
        "name": "Robert Smith",
        "email": "robert@example.com",
        "phone": "+254712345681",
        "avatar": "https://storage.nuru.com/avatars/robert.jpg",
        "role": "Best Man",
        "permissions": ["manage_guests", "send_invitations"],
        "status": "active",
        "invited_at": "2025-01-22T10:00:00Z",
        "accepted_at": "2025-01-22T12:30:00Z",
        "created_at": "2025-01-22T10:00:00Z"
      },
      {
        "id": "d50e8400-e29b-41d4-a716-446655440002",
        "event_id": "b50e8400-e29b-41d4-a716-446655440001",
        "user_id": null,
        "name": "Linda Williams",
        "email": "linda@example.com",
        "phone": "+254712345682",
        "avatar": null,
        "role": "Maid of Honor",
        "permissions": ["manage_guests", "manage_budget", "send_invitations"],
        "status": "active",
        "invited_at": "2025-01-22T10:05:00Z",
        "accepted_at": "2025-01-22T11:00:00Z",
        "created_at": "2025-01-22T10:05:00Z"
      }
    ],
    "contributions": [
      {
        "id": "e50e8400-e29b-41d4-a716-446655440001",
        "event_id": "b50e8400-e29b-41d4-a716-446655440001",
        "contributor_name": "James Wilson",
        "contributor_email": "james@example.com",
        "contributor_phone": "+254712345683",
        "contributor_user_id": "550e8400-e29b-41d4-a716-446655440020",
        "amount": 50000.0,
        "currency": "KES",
        "payment_method": "mpesa",
        "payment_reference": "QK7JH8L9M2",
        "status": "confirmed",
        "message": "Congratulations! Wishing you a lifetime of happiness.",
        "is_anonymous": false,
        "created_at": "2025-02-01T15:30:00Z",
        "confirmed_at": "2025-02-01T15:31:00Z"
      },
      {
        "id": "e50e8400-e29b-41d4-a716-446655440002",
        "event_id": "b50e8400-e29b-41d4-a716-446655440001",
        "contributor_name": "Anonymous",
        "contributor_email": null,
        "contributor_phone": null,
        "contributor_user_id": null,
        "amount": 25000.0,
        "currency": "KES",
        "payment_method": "bank_transfer",
        "payment_reference": "TRF123456789",
        "status": "confirmed",
        "message": "Best wishes!",
        "is_anonymous": true,
        "created_at": "2025-02-02T09:00:00Z",
        "confirmed_at": "2025-02-02T14:00:00Z"
      }
    ],
    "service_bookings": [
      {
        "id": "f50e8400-e29b-41d4-a716-446655440001",
        "event_id": "b50e8400-e29b-41d4-a716-446655440001",
        "service_id": "g50e8400-e29b-41d4-a716-446655440001",
        "service": {
          "id": "g50e8400-e29b-41d4-a716-446655440001",
          "title": "Premium Wedding Photography",
          "category": "Photography & Videography",
          "provider_name": "David Mwangi",
          "provider_avatar": "https://storage.nuru.com/avatars/david.jpg",
          "rating": 4.9,
          "review_count": 156
        },
        "package_id": "h50e8400-e29b-41d4-a716-446655440001",
        "package_name": "Platinum Package",
        "quoted_price": 150000.0,
        "currency": "KES",
        "status": "confirmed",
        "notes": "Full day coverage with 2 photographers",
        "created_at": "2025-01-28T10:00:00Z",
        "confirmed_at": "2025-01-29T14:30:00Z"
      },
      {
        "id": "f50e8400-e29b-41d4-a716-446655440002",
        "event_id": "b50e8400-e29b-41d4-a716-446655440001",
        "service_id": "g50e8400-e29b-41d4-a716-446655440002",
        "service": {
          "id": "g50e8400-e29b-41d4-a716-446655440002",
          "title": "Gourmet Catering Services",
          "category": "Catering & Food",
          "provider_name": "Taste of Africa",
          "provider_avatar": "https://storage.nuru.com/avatars/taste-africa.jpg",
          "rating": 4.7,
          "review_count": 89
        },
        "package_id": null,
        "package_name": null,
        "quoted_price": 200000.0,
        "currency": "KES",
        "status": "pending",
        "notes": "150 guests, buffet style",
        "created_at": "2025-02-03T11:00:00Z",
        "confirmed_at": null
      }
    ],
    "schedule": [
      {
        "id": "i50e8400-e29b-41d4-a716-446655440001",
        "event_id": "b50e8400-e29b-41d4-a716-446655440001",
        "title": "Guest Arrival",
        "description": "Guests arrive and are seated",
        "start_time": "2025-06-15T14:00:00Z",
        "end_time": "2025-06-15T14:30:00Z",
        "location": "Main Entrance",
        "display_order": 1
      },
      {
        "id": "i50e8400-e29b-41d4-a716-446655440002",
        "event_id": "b50e8400-e29b-41d4-a716-446655440001",
        "title": "Wedding Ceremony",
        "description": "The main wedding ceremony",
        "start_time": "2025-06-15T14:30:00Z",
        "end_time": "2025-06-15T15:30:00Z",
        "location": "Garden Pavilion",
        "display_order": 2
      },
      {
        "id": "i50e8400-e29b-41d4-a716-446655440003",
        "event_id": "b50e8400-e29b-41d4-a716-446655440001",
        "title": "Cocktail Hour",
        "description": "Drinks and appetizers",
        "start_time": "2025-06-15T15:30:00Z",
        "end_time": "2025-06-15T17:00:00Z",
        "location": "Terrace",
        "display_order": 3
      },
      {
        "id": "i50e8400-e29b-41d4-a716-446655440004",
        "event_id": "b50e8400-e29b-41d4-a716-446655440001",
        "title": "Reception Dinner",
        "description": "Dinner and speeches",
        "start_time": "2025-06-15T17:00:00Z",
        "end_time": "2025-06-15T20:00:00Z",
        "location": "Main Ballroom",
        "display_order": 4
      },
      {
        "id": "i50e8400-e29b-41d4-a716-446655440005",
        "event_id": "b50e8400-e29b-41d4-a716-446655440001",
        "title": "First Dance & Party",
        "description": "Dancing and celebration",
        "start_time": "2025-06-15T20:00:00Z",
        "end_time": "2025-06-15T23:00:00Z",
        "location": "Main Ballroom",
        "display_order": 5
      }
    ],
    "budget_items": [
      {
        "id": "j50e8400-e29b-41d4-a716-446655440001",
        "event_id": "b50e8400-e29b-41d4-a716-446655440001",
        "category": "Venue",
        "item_name": "Venue Rental",
        "estimated_cost": 100000.0,
        "actual_cost": 95000.0,
        "vendor_name": "The Great Rift Valley Lodge",
        "status": "paid",
        "notes": "Includes setup and cleanup",
        "created_at": "2025-01-20T10:30:00Z"
      },
      {
        "id": "j50e8400-e29b-41d4-a716-446655440002",
        "event_id": "b50e8400-e29b-41d4-a716-446655440001",
        "category": "Photography",
        "item_name": "Wedding Photography",
        "estimated_cost": 150000.0,
        "actual_cost": 150000.0,
        "vendor_name": "David Mwangi Photography",
        "status": "deposit_paid",
        "notes": "50% deposit paid",
        "created_at": "2025-01-28T10:30:00Z"
      },
      {
        "id": "j50e8400-e29b-41d4-a716-446655440003",
        "event_id": "b50e8400-e29b-41d4-a716-446655440001",
        "category": "Catering",
        "item_name": "Food & Beverages",
        "estimated_cost": 200000.0,
        "actual_cost": null,
        "vendor_name": "Taste of Africa",
        "status": "pending",
        "notes": "Awaiting confirmation",
        "created_at": "2025-02-03T11:00:00Z"
      }
    ],
    "created_at": "2025-01-20T10:30:00Z",
    "updated_at": "2025-02-05T09:15:00Z"
  }
}
```

**Error Response (404 Not Found):**

```json
{
  "success": false,
  "message": "Event not found"
}
```

**Error Response (403 Forbidden):**

```json
{
  "success": false,
  "message": "You do not have permission to view this event"
}
```

---

## 3.3 Create Event

Creates a new event.

```
POST /user-events/
Authorization: Bearer {access_token}
Content-Type: multipart/form-data
```

**Form Fields:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| title | string | Yes | Event title (max 100 chars) |
| description | string | No | Event description (max 2000 chars) |
| event_type_id | uuid | Yes | Event type ID from references |
| start_date | datetime | Yes | Event start date and time (ISO 8601) |
| end_date | datetime | No | Event end date and time (ISO 8601) |
| location | string | No | City/region (max 100 chars) |
| venue | string | No | Venue name (max 200 chars) |
| venue_address | string | No | Full venue address (max 500 chars) |
| venue_latitude | number | No | Venue latitude coordinate |
| venue_longitude | number | No | Venue longitude coordinate |
| cover_image | file | No | Cover image (jpg, png, max 10MB) |
| theme_color | string | No | Hex color code (e.g., #FF6B6B) |
| is_public | boolean | No | Whether event is publicly visible (default: false) |
| budget | number | No | Event budget amount |
| currency | string | No | Currency code (default: KES) |
| dress_code | string | No | Dress code instructions (max 200 chars) |
| special_instructions | string | No | Special instructions for guests (max 1000 chars) |
| rsvp_deadline | datetime | No | RSVP deadline (ISO 8601) |
| contribution_enabled | boolean | No | Enable contributions (default: false) |
| contribution_target | number | No | Target contribution amount |
| contribution_description | string | No | Description for contribution page (max 500 chars) |
| expected_guests | integer | No | Expected number of guests |

**Success Response (201 Created):**

```json
{
  "success": true,
  "message": "Event created successfully",
  "data": {
    "id": "b50e8400-e29b-41d4-a716-446655440003",
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "title": "Annual Corporate Gala",
    "description": "Our annual corporate celebration",
    "event_type_id": "550e8400-e29b-41d4-a716-446655440003",
    "event_type": {
      "id": "550e8400-e29b-41d4-a716-446655440003",
      "name": "Corporate Event",
      "icon": "briefcase",
      "color": "#45B7D1"
    },
    "start_date": "2025-12-15T18:00:00Z",
    "end_date": "2025-12-15T23:00:00Z",
    "location": "Nairobi, Kenya",
    "venue": "Kempinski Hotel",
    "venue_address": "Waiyaki Way, Westlands, Nairobi",
    "venue_coordinates": {
      "latitude": -1.2598,
      "longitude": 36.8063
    },
    "cover_image": "https://storage.nuru.com/events/b50e8400-003-cover.jpg",
    "theme_color": "#45B7D1",
    "is_public": false,
    "status": "draft",
    "budget": 1000000.0,
    "currency": "KES",
    "dress_code": "Business Formal",
    "special_instructions": null,
    "rsvp_deadline": null,
    "contribution_enabled": false,
    "contribution_target": null,
    "contribution_description": null,
    "expected_guests": 150,
    "guest_count": 0,
    "confirmed_guest_count": 0,
    "pending_guest_count": 0,
    "declined_guest_count": 0,
    "checked_in_count": 0,
    "contribution_total": 0,
    "contribution_count": 0,
    "committee_count": 0,
    "service_booking_count": 0,
    "created_at": "2025-02-05T14:30:00Z",
    "updated_at": "2025-02-05T14:30:00Z"
  }
}
```

**Error Response (400 Bad Request):**

```json
{
  "success": false,
  "message": "Validation failed",
  "errors": [
    {
      "field": "title",
      "message": "Title is required"
    },
    {
      "field": "start_date",
      "message": "Start date must be in the future"
    }
  ]
}
```

---

## 3.4 Update Event

Updates an existing event.

```
PUT /user-events/{eventId}
Authorization: Bearer {access_token}
Content-Type: multipart/form-data
```

**Path Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| eventId | uuid | Yes | Event unique identifier |

**Form Fields:** (All fields from create, all optional)
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| title | string | No | Event title |
| description | string | No | Event description |
| event_type_id | uuid | No | Event type ID |
| start_date | datetime | No | Start date/time |
| end_date | datetime | No | End date/time |
| location | string | No | City/region |
| venue | string | No | Venue name |
| venue_address | string | No | Full venue address |
| venue_latitude | number | No | Venue latitude |
| venue_longitude | number | No | Venue longitude |
| cover_image | file | No | New cover image |
| remove_cover_image | boolean | No | Remove existing cover image |
| theme_color | string | No | Theme color |
| is_public | boolean | No | Public visibility |
| status | string | No | Event status (draft, published, cancelled) |
| budget | number | No | Budget amount |
| currency | string | No | Currency code |
| dress_code | string | No | Dress code |
| special_instructions | string | No | Special instructions |
| rsvp_deadline | datetime | No | RSVP deadline |
| contribution_enabled | boolean | No | Enable contributions |
| contribution_target | number | No | Target amount |
| contribution_description | string | No | Contribution description |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Event updated successfully",
  "data": {
    "id": "b50e8400-e29b-41d4-a716-446655440001",
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "title": "John & Jane's Wedding - Updated",
    "description": "Updated description for the wedding.",
    "event_type_id": "550e8400-e29b-41d4-a716-446655440001",
    "event_type": {
      "id": "550e8400-e29b-41d4-a716-446655440001",
      "name": "Wedding",
      "icon": "rings",
      "color": "#FF6B6B"
    },
    "start_date": "2025-06-15T14:00:00Z",
    "end_date": "2025-06-15T23:00:00Z",
    "location": "Nairobi, Kenya",
    "venue": "The Great Rift Valley Lodge",
    "venue_address": "P.O. Box 12345, Naivasha, Kenya",
    "venue_coordinates": {
      "latitude": -0.7893,
      "longitude": 36.4344
    },
    "cover_image": "https://storage.nuru.com/events/b50e8400-cover-v2.jpg",
    "theme_color": "#FF6B6B",
    "is_public": true,
    "status": "published",
    "budget": 550000.0,
    "currency": "KES",
    "dress_code": "Formal - Black tie optional",
    "special_instructions": "Please arrive 30 minutes before the ceremony.",
    "rsvp_deadline": "2025-06-01T23:59:59Z",
    "contribution_enabled": true,
    "contribution_target": 1000000.0,
    "contribution_description": "Help us start our new life together.",
    "expected_guests": 200,
    "guest_count": 150,
    "confirmed_guest_count": 89,
    "pending_guest_count": 45,
    "declined_guest_count": 16,
    "checked_in_count": 0,
    "contribution_total": 456000.0,
    "contribution_count": 34,
    "committee_count": 5,
    "service_booking_count": 8,
    "created_at": "2025-01-20T10:30:00Z",
    "updated_at": "2025-02-05T15:00:00Z"
  }
}
```

---

## 3.5 Delete Event

Deletes an event.

```
DELETE /user-events/{eventId}
Authorization: Bearer {access_token}
```

**Path Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| eventId | uuid | Yes | Event unique identifier |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Event deleted successfully"
}
```

**Error Response (404 Not Found):**

```json
{
  "success": false,
  "message": "Event not found"
}
```

**Error Response (403 Forbidden):**

```json
{
  "success": false,
  "message": "You do not have permission to delete this event"
}
```

**Error Response (409 Conflict):**

```json
{
  "success": false,
  "message": "Cannot delete event with confirmed bookings. Please cancel bookings first."
}
```

---

## 3.6 Publish Event

Publishes a draft event.

```
POST /user-events/{eventId}/publish
Authorization: Bearer {access_token}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Event published successfully",
  "data": {
    "id": "b50e8400-e29b-41d4-a716-446655440001",
    "status": "published",
    "published_at": "2025-02-05T15:30:00Z",
    "public_url": "https://nuru.com/events/john-janes-wedding-b50e8400"
  }
}
```

---

## 3.7 Cancel Event

Cancels a published event.

```
POST /user-events/{eventId}/cancel
Authorization: Bearer {access_token}
```

**Request Body:**

```json
{
  "reason": "Due to unforeseen circumstances, we have to postpone the event.",
  "notify_guests": true,
  "notify_vendors": true
}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Event cancelled successfully. Notifications sent to 150 guests and 8 vendors.",
  "data": {
    "id": "b50e8400-e29b-41d4-a716-446655440001",
    "status": "cancelled",
    "cancelled_at": "2025-02-05T15:45:00Z",
    "cancellation_reason": "Due to unforeseen circumstances, we have to postpone the event.",
    "guests_notified": 150,
    "vendors_notified": 8
  }
}
```

---

# 👥 MODULE 4: EVENT GUESTS

---

## 4.1 Get Event Guests

Returns all guests for an event.

```
GET /user-events/{eventId}/guests
Authorization: Bearer {access_token}
```

**Path Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| eventId | uuid | Yes | Event unique identifier |

**Query Parameters:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| page | integer | No | 1 | Page number |
| limit | integer | No | 50 | Items per page (max 100) |
| search | string | No | null | Search by name, email, or phone |
| rsvp_status | string | No | all | Filter: pending, confirmed, declined, maybe, all |
| invitation_status | string | No | all | Filter: sent, not_sent, all |
| checked_in | boolean | No | null | Filter by check-in status |
| table_number | string | No | null | Filter by table number |
| sort_by | string | No | name | Sort: name, created_at, rsvp_status, table_number |
| sort_order | string | No | asc | Sort order: asc, desc |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Guests retrieved successfully",
  "data": {
    "guests": [
      {
        "id": "c50e8400-e29b-41d4-a716-446655440001",
        "event_id": "b50e8400-e29b-41d4-a716-446655440001",
        "name": "Michael Johnson",
        "avatar": "https://storage.nuru.com/avatars/michael.jpg",
        "email": "michael@example.com",
        "phone": "+254712345679",
        "rsvp_status": "confirmed",
        "rsvp_responded_at": "2025-02-03T14:20:00Z",
        "table_number": "A1",
        "seat_number": 3,
        "dietary_requirements": "Vegetarian",
        "allergies": "Peanuts",
        "plus_ones": 1,
        "plus_one_names": ["Sarah Johnson"],
        "notes": "Best friend of the groom",
        "tags": ["VIP", "Family"],
        "invitation_sent": true,
        "invitation_sent_at": "2025-02-01T10:00:00Z",
        "invitation_method": "email",
        "invitation_opened": true,
        "invitation_opened_at": "2025-02-01T12:30:00Z",
        "checked_in": false,
        "checked_in_at": null,
        "checked_in_by": null,
        "qr_code": "https://storage.nuru.com/qr/c50e8400-001.png",
        "created_at": "2025-01-25T10:30:00Z",
        "updated_at": "2025-02-03T14:20:00Z"
      },
      {
        "id": "c50e8400-e29b-41d4-a716-446655440002",
        "event_id": "b50e8400-e29b-41d4-a716-446655440001",
        "name": "Emily Davis",
        "avatar": null,
        "email": "emily@example.com",
        "phone": "+254712345680",
        "rsvp_status": "pending",
        "rsvp_responded_at": null,
        "table_number": null,
        "seat_number": null,
        "dietary_requirements": null,
        "allergies": null,
        "plus_ones": 0,
        "plus_one_names": [],
        "notes": "College friend",
        "tags": ["Friends"],
        "invitation_sent": true,
        "invitation_sent_at": "2025-02-01T10:00:00Z",
        "invitation_method": "whatsapp",
        "invitation_opened": false,
        "invitation_opened_at": null,
        "checked_in": false,
        "checked_in_at": null,
        "checked_in_by": null,
        "qr_code": "https://storage.nuru.com/qr/c50e8400-002.png",
        "created_at": "2025-01-25T10:35:00Z",
        "updated_at": "2025-01-25T10:35:00Z"
      },
      {
        "id": "c50e8400-e29b-41d4-a716-446655440003",
        "event_id": "b50e8400-e29b-41d4-a716-446655440001",
        "name": "James Wilson",
        "avatar": null,
        "email": "james@example.com",
        "phone": "+254712345681",
        "rsvp_status": "declined",
        "rsvp_responded_at": "2025-02-02T09:15:00Z",
        "table_number": null,
        "seat_number": null,
        "dietary_requirements": null,
        "allergies": null,
        "plus_ones": 0,
        "plus_one_names": [],
        "notes": "Will be traveling",
        "tags": ["Work"],
        "invitation_sent": true,
        "invitation_sent_at": "2025-02-01T10:00:00Z",
        "invitation_method": "email",
        "invitation_opened": true,
        "invitation_opened_at": "2025-02-01T18:45:00Z",
        "checked_in": false,
        "checked_in_at": null,
        "checked_in_by": null,
        "qr_code": "https://storage.nuru.com/qr/c50e8400-003.png",
        "created_at": "2025-01-25T10:40:00Z",
        "updated_at": "2025-02-02T09:15:00Z"
      }
    ],
    "summary": {
      "total": 150,
      "confirmed": 89,
      "pending": 45,
      "declined": 14,
      "maybe": 2,
      "checked_in": 0,
      "invitations_sent": 150,
      "invitations_opened": 120
    },
    "pagination": {
      "page": 1,
      "limit": 50,
      "total_items": 150,
      "total_pages": 3,
      "has_next": true,
      "has_previous": false
    }
  }
}
```

---

## 4.2 Get Single Guest

Returns details of a specific guest.

```
GET /user-events/{eventId}/guests/{guestId}
Authorization: Bearer {access_token}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Guest retrieved successfully",
  "data": {
    "id": "c50e8400-e29b-41d4-a716-446655440001",
    "event_id": "b50e8400-e29b-41d4-a716-446655440001",
    "name": "Michael Johnson",
    "avatar": "https://storage.nuru.com/avatars/michael.jpg",
    "email": "michael@example.com",
    "phone": "+254712345679",
    "rsvp_status": "confirmed",
    "rsvp_responded_at": "2025-02-03T14:20:00Z",
    "table_number": "A1",
    "seat_number": 3,
    "dietary_requirements": "Vegetarian",
    "allergies": "Peanuts",
    "plus_ones": 1,
    "plus_one_names": ["Sarah Johnson"],
    "plus_one_details": [
      {
        "name": "Sarah Johnson",
        "dietary_requirements": "None",
        "allergies": null
      }
    ],
    "notes": "Best friend of the groom",
    "tags": ["VIP", "Family"],
    "invitation_sent": true,
    "invitation_sent_at": "2025-02-01T10:00:00Z",
    "invitation_method": "email",
    "invitation_opened": true,
    "invitation_opened_at": "2025-02-01T12:30:00Z",
    "invitation_clicks": 3,
    "checked_in": false,
    "checked_in_at": null,
    "checked_in_by": null,
    "qr_code": "https://storage.nuru.com/qr/c50e8400-001.png",
    "gift_given": false,
    "gift_description": null,
    "activity_log": [
      {
        "action": "created",
        "timestamp": "2025-01-25T10:30:00Z",
        "details": "Guest added to event"
      },
      {
        "action": "invitation_sent",
        "timestamp": "2025-02-01T10:00:00Z",
        "details": "Invitation sent via email"
      },
      {
        "action": "invitation_opened",
        "timestamp": "2025-02-01T12:30:00Z",
        "details": "Invitation opened"
      },
      {
        "action": "rsvp_confirmed",
        "timestamp": "2025-02-03T14:20:00Z",
        "details": "RSVP confirmed with 1 plus one"
      }
    ],
    "created_at": "2025-01-25T10:30:00Z",
    "updated_at": "2025-02-03T14:20:00Z"
  }
}
```

---

## 4.3 Add Guest

Adds a new guest to an event. Supports two guest types: `user` (registered Nuru user) and `contributor` (from user's address book).

```
POST /user-events/{eventId}/guests
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body (User Guest):**

```json
{
  "name": "Robert Brown",
  "guest_type": "user",
  "user_id": "550e8400-e29b-41d4-a716-446655440020",
  "email": "robert@example.com",
  "phone": "+254712345690",
  "dietary_requirements": "Halal",
  "meal_preference": "Vegetarian",
  "special_requests": "Near the stage",
  "plus_one_names": ["Mary Brown"],
  "notes": "Colleague from work"
}
```

**Request Body (Contributor Guest):**

```json
{
  "name": "Jane Doe",
  "guest_type": "contributor",
  "contributor_id": "a50e8400-e29b-41d4-a716-446655440001",
  "dietary_requirements": "None",
  "meal_preference": "Regular",
  "notes": "Family friend"
}
```

| Field                | Type          | Required | Description                                      |
| -------------------- | ------------- | -------- | ------------------------------------------------ |
| name                 | string        | Yes      | Guest full name (max 100 chars)                  |
| guest_type           | string        | No       | `"user"` (default) or `"contributor"`            |
| user_id              | uuid          | No       | For user guests: link to registered Nuru user    |
| contributor_id       | uuid          | Cond.    | Required when `guest_type` is `"contributor"`    |
| email                | string        | No       | Guest email (used for user lookup if no user_id) |
| phone                | string        | No       | Guest phone (used for user lookup if no user_id) |
| dietary_requirements | string        | No       | Dietary requirements                             |
| meal_preference      | string        | No       | Meal preference                                  |
| special_requests     | string        | No       | Special requests                                 |
| plus_one_names       | array[string] | No       | Names of plus ones                               |
| notes                | string        | No       | Internal notes (max 500 chars)                   |

**Success Response (201 Created):**

```json
{
  "success": true,
  "message": "Guest added successfully",
  "data": {
    "id": "c50e8400-e29b-41d4-a716-446655440010",
    "event_id": "b50e8400-e29b-41d4-a716-446655440001",
    "guest_type": "user",
    "name": "Robert Brown",
    "email": "robert@example.com",
    "phone": "+254712345690",
    "rsvp_status": "pending",
    "dietary_requirements": "Halal",
    "meal_preference": "Vegetarian",
    "special_requests": "Near the stage",
    "plus_ones": 1,
    "plus_one_names": ["Mary Brown"],
    "notes": "Colleague from work",
    "invitation_sent": false,
    "invitation_sent_at": null,
    "invitation_method": null,
    "checked_in": false,
    "checked_in_at": null,
    "created_at": "2025-02-05T16:00:00Z"
  }
}
```

**Duplicate Error (400):**

```json
{
  "success": false,
  "message": "Robert Brown is already on the guest list for this event."
}
```

---

## 4.4 Add Multiple Guests (Bulk Import)

Adds multiple guests at once.

```
POST /user-events/{eventId}/guests/bulk
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:**

```json
{
  "guests": [
    {
      "name": "Guest One",
      "email": "guest1@example.com",
      "phone": "+254712345691",
      "plus_ones": 0,
      "tags": ["Family"]
    },
    {
      "name": "Guest Two",
      "email": "guest2@example.com",
      "phone": "+254712345692",
      "plus_ones": 1,
      "plus_one_names": ["Plus One Name"],
      "tags": ["Friends"]
    },
    {
      "name": "Guest Three",
      "email": "guest3@example.com",
      "phone": "+254712345693",
      "plus_ones": 0,
      "tags": ["Work"]
    }
  ],
  "skip_duplicates": true,
  "default_tags": ["Imported"]
}
```

**Success Response (201 Created):**

```json
{
  "success": true,
  "message": "Guests imported successfully",
  "data": {
    "imported": 3,
    "skipped": 0,
    "errors": [],
    "guests": [
      {
        "id": "c50e8400-e29b-41d4-a716-446655440011",
        "name": "Guest One",
        "email": "guest1@example.com",
        "status": "imported"
      },
      {
        "id": "c50e8400-e29b-41d4-a716-446655440012",
        "name": "Guest Two",
        "email": "guest2@example.com",
        "status": "imported"
      },
      {
        "id": "c50e8400-e29b-41d4-a716-446655440013",
        "name": "Guest Three",
        "email": "guest3@example.com",
        "status": "imported"
      }
    ]
  }
}
```

**Partial Success Response (201 Created with errors):**

```json
{
  "success": true,
  "message": "Guests imported with some errors",
  "data": {
    "imported": 2,
    "skipped": 1,
    "errors": [
      {
        "row": 2,
        "name": "Guest Two",
        "error": "Email already exists in guest list"
      }
    ],
    "guests": [
      {
        "id": "c50e8400-e29b-41d4-a716-446655440011",
        "name": "Guest One",
        "email": "guest1@example.com",
        "status": "imported"
      },
      {
        "id": "c50e8400-e29b-41d4-a716-446655440013",
        "name": "Guest Three",
        "email": "guest3@example.com",
        "status": "imported"
      }
    ]
  }
}
```

---

## 4.5 Import Guests from CSV

Imports guests from a CSV file.

```
POST /user-events/{eventId}/guests/import
Authorization: Bearer {access_token}
Content-Type: multipart/form-data
```

**Form Fields:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| file | file | Yes | CSV file (max 5MB) |
| skip_header | boolean | No | Skip first row (default: true) |
| skip_duplicates | boolean | No | Skip duplicate emails/phones (default: true) |
| default_tags | string | No | Comma-separated default tags |

**CSV Format:**

```csv
Name,Email,Phone,Plus Ones,Dietary Requirements,Notes,Tags
Michael Johnson,michael@example.com,+254712345679,1,Vegetarian,Best friend,VIP;Family
Emily Davis,emily@example.com,+254712345680,0,,College friend,Friends
```

**Success Response (201 Created):**

```json
{
  "success": true,
  "message": "CSV imported successfully",
  "data": {
    "imported": 45,
    "skipped": 5,
    "errors": [
      {
        "row": 12,
        "error": "Invalid email format"
      },
      {
        "row": 23,
        "error": "Email already exists"
      }
    ]
  }
}
```

---

## 4.6 Update Guest

Updates a guest's information.

```
PUT /user-events/{eventId}/guests/{guestId}
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:** (All fields optional)

```json
{
  "name": "Michael J. Johnson",
  "email": "michael.j@example.com",
  "phone": "+254712345679",
  "table_number": "A2",
  "seat_number": 1,
  "dietary_requirements": "Vegan",
  "allergies": "Peanuts, Shellfish",
  "plus_ones": 2,
  "plus_one_names": ["Sarah Johnson", "Tim Johnson"],
  "notes": "Updated notes",
  "tags": ["VIP", "Family", "Speaker"]
}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Guest updated successfully",
  "data": {
    "id": "c50e8400-e29b-41d4-a716-446655440001",
    "event_id": "b50e8400-e29b-41d4-a716-446655440001",
    "name": "Michael J. Johnson",
    "email": "michael.j@example.com",
    "phone": "+254712345679",
    "rsvp_status": "confirmed",
    "table_number": "A2",
    "seat_number": 1,
    "dietary_requirements": "Vegan",
    "allergies": "Peanuts, Shellfish",
    "plus_ones": 2,
    "plus_one_names": ["Sarah Johnson", "Tim Johnson"],
    "notes": "Updated notes",
    "tags": ["VIP", "Family", "Speaker"],
    "invitation_sent": true,
    "invitation_sent_at": "2025-02-01T10:00:00Z",
    "checked_in": false,
    "created_at": "2025-01-25T10:30:00Z",
    "updated_at": "2025-02-05T16:30:00Z"
  }
}
```

---

## 4.7 Delete Guest

Removes a guest from the event.

```
DELETE /user-events/{eventId}/guests/{guestId}
Authorization: Bearer {access_token}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Guest removed successfully"
}
```

---

## 4.8 Delete Multiple Guests

Removes multiple guests at once.

```
DELETE /user-events/{eventId}/guests/bulk
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:**

```json
{
  "guest_ids": [
    "c50e8400-e29b-41d4-a716-446655440001",
    "c50e8400-e29b-41d4-a716-446655440002",
    "c50e8400-e29b-41d4-a716-446655440003"
  ]
}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "3 guests removed successfully",
  "data": {
    "deleted": 3
  }
}
```

---

## 4.9 Send Invitation to Guest

Sends an invitation to a specific guest.

```
POST /user-events/{eventId}/guests/{guestId}/invite
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:**

```json
{
  "method": "email",
  "custom_message": "We would be honored to have you join us on our special day!",
  "include_calendar": true,
  "include_map": true
}
```

| Field            | Type    | Required | Description                               |
| ---------------- | ------- | -------- | ----------------------------------------- |
| method           | string  | Yes      | Delivery method: email, sms, whatsapp     |
| custom_message   | string  | No       | Custom message to include (max 500 chars) |
| include_calendar | boolean | No       | Include calendar invite (default: true)   |
| include_map      | boolean | No       | Include venue map link (default: true)    |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Invitation sent successfully",
  "data": {
    "guest_id": "c50e8400-e29b-41d4-a716-446655440001",
    "method": "email",
    "sent_at": "2025-02-05T17:00:00Z",
    "invitation_url": "https://nuru.com/rsvp/abc123def456"
  }
}
```

**Error Response (400 Bad Request):**

```json
{
  "success": false,
  "message": "Cannot send invitation",
  "errors": [
    {
      "field": "email",
      "message": "Guest has no email address. Please add an email or use SMS."
    }
  ]
}
```

---

## 4.10 Send Bulk Invitations

Sends invitations to multiple guests.

```
POST /user-events/{eventId}/guests/invite-all
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:**

```json
{
  "method": "email",
  "guest_ids": [
    "c50e8400-e29b-41d4-a716-446655440001",
    "c50e8400-e29b-41d4-a716-446655440002"
  ],
  "filter": {
    "rsvp_status": "pending",
    "invitation_sent": false
  },
  "custom_message": "We look forward to celebrating with you!",
  "include_calendar": true,
  "include_map": true
}
```

| Field                  | Type          | Required | Description                                |
| ---------------------- | ------------- | -------- | ------------------------------------------ |
| method                 | string        | Yes      | Delivery method: email, sms, whatsapp      |
| guest_ids              | array[uuid]   | No       | Specific guest IDs (if empty, uses filter) |
| filter                 | object        | No       | Filter criteria for guests                 |
| filter.rsvp_status     | string        | No       | Filter by RSVP status                      |
| filter.invitation_sent | boolean       | No       | Filter by invitation sent status           |
| filter.tags            | array[string] | No       | Filter by guest tags                       |
| custom_message         | string        | No       | Custom message (max 500 chars)             |
| include_calendar       | boolean       | No       | Include calendar invite                    |
| include_map            | boolean       | No       | Include venue map                          |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Invitations sent",
  "data": {
    "total_selected": 50,
    "sent_count": 48,
    "failed_count": 2,
    "failures": [
      {
        "guest_id": "c50e8400-e29b-41d4-a716-446655440005",
        "name": "Guest Name",
        "reason": "Invalid email address"
      },
      {
        "guest_id": "c50e8400-e29b-41d4-a716-446655440006",
        "name": "Another Guest",
        "reason": "No contact information"
      }
    ]
  }
}
```

---

## 4.11 Resend Invitation

Resends an invitation to a guest who hasn't responded.

```
POST /user-events/{eventId}/guests/{guestId}/resend-invite
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:**

```json
{
  "method": "whatsapp",
  "custom_message": "Gentle reminder: We'd love to have you join us!"
}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Invitation resent successfully",
  "data": {
    "guest_id": "c50e8400-e29b-41d4-a716-446655440001",
    "method": "whatsapp",
    "sent_at": "2025-02-05T17:30:00Z",
    "resend_count": 2
  }
}
```

---

## 4.12 Check-in Guest

Checks in a guest at the event.

```
POST /user-events/{eventId}/guests/{guestId}/checkin
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:**

```json
{
  "plus_ones_checked_in": 1,
  "notes": "Arrived with spouse"
}
```

| Field                | Type    | Required | Description                     |
| -------------------- | ------- | -------- | ------------------------------- |
| plus_ones_checked_in | integer | No       | Number of plus ones checking in |
| notes                | string  | No       | Check-in notes                  |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Guest checked in successfully",
  "data": {
    "guest_id": "c50e8400-e29b-41d4-a716-446655440001",
    "name": "Michael Johnson",
    "checked_in": true,
    "checked_in_at": "2025-06-15T14:15:00Z",
    "checked_in_by": "550e8400-e29b-41d4-a716-446655440000",
    "plus_ones_checked_in": 1,
    "table_number": "A1",
    "seat_number": 3
  }
}
```

---

## 4.13 Check-in Guest by QR Code

Checks in a guest using their QR code.

```
POST /user-events/{eventId}/guests/checkin-qr
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:**

```json
{
  "qr_code": "NURU-G-c50e8400-e29b-41d4-a716-446655440001",
  "plus_ones_checked_in": 1
}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Guest checked in successfully",
  "data": {
    "guest_id": "c50e8400-e29b-41d4-a716-446655440001",
    "name": "Michael Johnson",
    "checked_in": true,
    "checked_in_at": "2025-06-15T14:15:00Z",
    "table_number": "A1",
    "seat_number": 3,
    "dietary_requirements": "Vegetarian",
    "plus_ones": 1,
    "plus_ones_checked_in": 1
  }
}
```

**Error Response (400 Bad Request):**

```json
{
  "success": false,
  "message": "Guest already checked in",
  "data": {
    "guest_id": "c50e8400-e29b-41d4-a716-446655440001",
    "checked_in_at": "2025-06-15T14:10:00Z"
  }
}
```

---

## 4.14 Undo Check-in

Reverts a guest's check-in status.

```
POST /user-events/{eventId}/guests/{guestId}/undo-checkin
Authorization: Bearer {access_token}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Check-in reverted successfully",
  "data": {
    "guest_id": "c50e8400-e29b-41d4-a716-446655440001",
    "checked_in": false
  }
}
```

---

## 4.15 Public RSVP (No Authentication Required)

Allows guests to respond to their invitation.

```
POST /events/{eventId}/rsvp
Content-Type: application/json
Authentication: None (uses token from invitation link)
```

**Request Body:**

```json
{
  "guest_id": "c50e8400-e29b-41d4-a716-446655440001",
  "token": "abc123def456ghi789",
  "rsvp_status": "confirmed",
  "plus_ones": 1,
  "plus_one_names": ["Sarah Johnson"],
  "plus_one_details": [
    {
      "name": "Sarah Johnson",
      "dietary_requirements": "None",
      "allergies": null
    }
  ],
  "dietary_requirements": "Vegetarian",
  "allergies": "Peanuts",
  "message": "Looking forward to celebrating with you!"
}
```

| Field                | Type          | Required | Description                          |
| -------------------- | ------------- | -------- | ------------------------------------ |
| guest_id             | uuid          | Yes      | Guest unique identifier              |
| token                | string        | Yes      | RSVP token from invitation link      |
| rsvp_status          | string        | Yes      | Response: confirmed, declined, maybe |
| plus_ones            | integer       | No       | Number of plus ones attending        |
| plus_one_names       | array[string] | No       | Names of plus ones                   |
| plus_one_details     | array[object] | No       | Details for each plus one            |
| dietary_requirements | string        | No       | Guest's dietary requirements         |
| allergies            | string        | No       | Guest's food allergies               |
| message              | string        | No       | Message to the host (max 500 chars)  |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "RSVP recorded successfully",
  "data": {
    "event": {
      "id": "b50e8400-e29b-41d4-a716-446655440001",
      "title": "John & Jane's Wedding",
      "start_date": "2025-06-15T14:00:00Z",
      "venue": "The Great Rift Valley Lodge",
      "location": "Nairobi, Kenya"
    },
    "rsvp_status": "confirmed",
    "calendar_link": "https://nuru.com/calendar/add/b50e8400",
    "map_link": "https://maps.google.com/?q=-0.7893,36.4344"
  }
}
```

**Error Response (400 Bad Request):**

```json
{
  "success": false,
  "message": "Invalid or expired RSVP token"
}
```

**Error Response (410 Gone):**

```json
{
  "success": false,
  "message": "RSVP deadline has passed"
}
```

---

## 4.16 Get RSVP Page (Public)

Returns event details for the public RSVP page.

```
GET /events/{eventId}/rsvp/{guestId}?token={token}
Authentication: None
```

**Query Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| token | string | Yes | RSVP token from invitation link |

**Success Response (200 OK):**

```json
{
  "success": true,
  "data": {
    "event": {
      "id": "b50e8400-e29b-41d4-a716-446655440001",
      "title": "John & Jane's Wedding",
      "description": "A beautiful garden wedding ceremony",
      "cover_image": "https://storage.nuru.com/events/b50e8400-cover.jpg",
      "start_date": "2025-06-15T14:00:00Z",
      "end_date": "2025-06-15T23:00:00Z",
      "venue": "The Great Rift Valley Lodge",
      "venue_address": "P.O. Box 12345, Naivasha, Kenya",
      "location": "Nairobi, Kenya",
      "dress_code": "Formal - Black tie optional",
      "special_instructions": "Please arrive 30 minutes before the ceremony.",
      "rsvp_deadline": "2025-06-01T23:59:59Z",
      "host_name": "John Doe"
    },
    "guest": {
      "id": "c50e8400-e29b-41d4-a716-446655440001",
      "name": "Michael Johnson",
      "current_rsvp_status": "pending",
      "max_plus_ones": 2,
      "current_plus_ones": 0
    },
    "rsvp_options": {
      "allow_plus_ones": true,
      "max_plus_ones": 2,
      "require_dietary_info": true,
      "deadline_passed": false
    }
  }
}
```

---

## 4.17 Export Guests

Exports guest list in various formats.

```
GET /user-events/{eventId}/guests/export
Authorization: Bearer {access_token}
```

**Query Parameters:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| format | string | No | csv | Export format: csv, xlsx, pdf |
| fields | string | No | all | Comma-separated field names |
| rsvp_status | string | No | all | Filter by RSVP status |

**Success Response (200 OK):**
Returns file download with appropriate Content-Type header.

For CSV:

```
Content-Type: text/csv
Content-Disposition: attachment; filename="guests-wedding-2025-02-05.csv"

Name,Email,Phone,RSVP Status,Plus Ones,Table,Dietary Requirements,Checked In
Michael Johnson,michael@example.com,+254712345679,Confirmed,1,A1,Vegetarian,No
Emily Davis,emily@example.com,+254712345680,Pending,0,,None,No
```

---

# 🎨 MODULE 4B: INVITATION CARD TEMPLATES

Allows users to upload custom PDF invitation card templates. The system overlays guest name and QR code onto the PDF when generating invitation cards. Each event can optionally be assigned a custom card template — if none is set, the default Nuru digital card is used.

**How it works:**

- Users upload PDF card designs with predefined placeholder areas for guest name and QR code
- When uploading, users specify the X/Y coordinates (as % of page) and styling for name and QR placeholders
- When a guest downloads their invitation card, the system fills in their name and QR code on the PDF
- Templates are per-user and can be reused across multiple events

---

## 4B.1 List My Card Templates

```
GET /card-templates
Authorization: Bearer {access_token}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "data": [
    {
      "id": "uuid",
      "name": "Elegant Wedding Card",
      "description": "Green botanical design with gold text",
      "pdf_url": "https://storage.nuru.com/card-templates/uuid.pdf",
      "thumbnail_url": "https://storage.nuru.com/card-templates/uuid-thumb.jpg",
      "name_placeholder_x": 50,
      "name_placeholder_y": 35,
      "name_font_size": 16,
      "name_font_color": "#2D5016",
      "qr_placeholder_x": 50,
      "qr_placeholder_y": 75,
      "qr_size": 80,
      "is_active": true,
      "created_at": "2026-02-20T10:00:00Z",
      "updated_at": "2026-02-20T10:00:00Z"
    }
  ]
}
```

---

## 4B.2 Get Card Template

```
GET /card-templates/{templateId}
Authorization: Bearer {access_token}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "data": { "id": "uuid", "name": "Elegant Wedding Card", "...": "..." }
}
```

---

## 4B.3 Upload Card Template

```
POST /card-templates
Authorization: Bearer {access_token}
Content-Type: multipart/form-data
```

**Form Fields:**

| Field              | Type   | Required | Default | Description                            |
| ------------------ | ------ | -------- | ------- | -------------------------------------- |
| pdf                | file   | Yes      | —       | PDF file of the card design (max 10MB) |
| name               | string | Yes      | —       | Template name                          |
| description        | string | No       | —       | Description of the design              |
| name_placeholder_x | number | No       | 50      | X position of guest name (% from left) |
| name_placeholder_y | number | No       | 35      | Y position of guest name (% from top)  |
| name_font_size     | number | No       | 16      | Font size for guest name (pt)          |
| name_font_color    | string | No       | #000000 | Color for guest name text              |
| qr_placeholder_x   | number | No       | 50      | X position of QR code (% from left)    |
| qr_placeholder_y   | number | No       | 75      | Y position of QR code (% from top)     |
| qr_size            | number | No       | 80      | QR code size in pixels                 |

**Success Response (201 Created):**

```json
{
  "success": true,
  "message": "Card template uploaded successfully",
  "data": {
    "id": "uuid",
    "name": "Elegant Wedding Card",
    "pdf_url": "...",
    "...": "..."
  }
}
```

---

## 4B.4 Update Card Template

```
PUT /card-templates/{templateId}
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body (all fields optional):**

```json
{
  "name": "Updated Name",
  "description": "Updated description",
  "name_placeholder_x": 48,
  "name_placeholder_y": 33,
  "name_font_size": 18,
  "name_font_color": "#1A3A0A",
  "qr_placeholder_x": 50,
  "qr_placeholder_y": 78,
  "qr_size": 90,
  "is_active": true
}
```

---

## 4B.5 Delete Card Template

```
DELETE /card-templates/{templateId}
Authorization: Bearer {access_token}
```

**Success Response (200 OK):**

```json
{ "success": true, "message": "Card template deleted successfully" }
```

---

## 4B.6 Assign Card Template to Event

Sets (or removes) a custom card template for an event. Pass `null` to revert to the default Nuru card.

```
PUT /events/{eventId}/card-template
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:**

```json
{ "card_template_id": "uuid-or-null" }
```

**Success Response (200 OK):**

```json
{ "success": true, "message": "Card template assigned to event" }
```

---

## 4B.7 Get Event Card Template

```
GET /events/{eventId}/card-template
Authorization: Bearer {access_token}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "name": "Elegant Wedding Card",
    "pdf_url": "...",
    "...": "..."
  }
}
```

Returns `null` in data if no custom template is assigned.

---

## 4B.8 Download Filled Invitation Card

Generates a PDF with the guest's name and QR code overlaid on the custom card template. Falls back to the default Nuru digital card if no template is assigned.

```
GET /events/{eventId}/invitation-card/{attendeeId}/download
Authorization: Bearer {access_token}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "data": {
    "pdf_url": "https://storage.nuru.com/filled-cards/event-uuid/attendee-uuid.pdf"
  }
}
```

---

## Updated: 3.1.3 GET /user-events/{eventId}/invitation-card

Now includes `card_template` field in the response when a custom template is assigned to the event:

```json
{
  "success": true,
  "data": {
    "event": { "...": "..." },
    "guest": { "...": "..." },
    "organizer": { "...": "..." },
    "invitation_code": "ABC123",
    "qr_code_data": "nuru://event/uuid/checkin/uuid",
    "rsvp_deadline": "2025-08-01T23:59:59",
    "card_template": {
      "id": "uuid",
      "pdf_url": "https://storage.nuru.com/card-templates/uuid.pdf",
      "name_placeholder_x": 50,
      "name_placeholder_y": 35,
      "name_font_size": 16,
      "name_font_color": "#2D5016",
      "qr_placeholder_x": 50,
      "qr_placeholder_y": 75,
      "qr_size": 80
    }
  }
}
```

When `card_template` is `null`, the frontend renders the default Nuru themed card.

---

# 👨‍👩‍👧‍👦 MODULE 5: EVENT COMMITTEE

## Committee Permission Enforcement

All event management endpoints enforce committee permissions. Committee members can **view all event details** (event info, guests, contributions, vendors, budget, schedule), but **write/action endpoints** require the specific permission:

| Permission                 | Grants Access To                                              |
| -------------------------- | ------------------------------------------------------------- |
| `can_view_guests`          | View guest list, export guests                                |
| `can_manage_guests`        | Add, update, remove guests (single & bulk)                    |
| `can_send_invitations`     | Send invitations (single & bulk)                              |
| `can_check_in_guests`      | Check in guests (manual, QR, undo)                            |
| `can_view_budget`          | View budget items and summary                                 |
| `can_manage_budget`        | Add, update, delete budget items                              |
| `can_view_contributions`   | View contributions list                                       |
| `can_manage_contributions` | Record payments (pending status), view recorded contributions |
| `can_view_vendors`         | View event service providers                                  |
| `can_manage_vendors`       | Add, update, remove service providers                         |
| `can_approve_bookings`     | Record service payments                                       |
| `can_edit_event`           | Edit event details, settings, images, schedule                |
| `can_manage_committee`     | Add, update, remove committee members                         |

**Important rules:**

- Event **creator** always has full access to all operations
- Bulk upload of contribution targets/contributions is **creator-only**
- Contributions recorded by committee members start as **"pending"** and require creator confirmation
- Committee members cannot see who recorded contributions (only creators see `recorded_by`)

---

## 5.1 Get Committee Members

Returns all committee members for an event.

```
GET /user-events/{eventId}/committee
Authorization: Bearer {access_token}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Committee members retrieved successfully",
  "data": [
    {
      "id": "d50e8400-e29b-41d4-a716-446655440001",
      "event_id": "b50e8400-e29b-41d4-a716-446655440001",
      "user_id": "550e8400-e29b-41d4-a716-446655440010",
      "name": "Robert Smith",
      "email": "robert@example.com",
      "phone": "+254712345681",
      "avatar": "https://storage.nuru.com/avatars/robert.jpg",
      "role": "Best Man",
      "role_description": "Responsible for managing groomsmen and bachelor party",
      "permissions": [
        "view_guests",
        "manage_guests",
        "send_invitations",
        "view_budget"
      ],
      "status": "active",
      "invited_at": "2025-01-22T10:00:00Z",
      "accepted_at": "2025-01-22T12:30:00Z",
      "last_active_at": "2025-02-05T10:00:00Z",
      "created_at": "2025-01-22T10:00:00Z"
    },
    {
      "id": "d50e8400-e29b-41d4-a716-446655440002",
      "event_id": "b50e8400-e29b-41d4-a716-446655440001",
      "user_id": null,
      "name": "Linda Williams",
      "email": "linda@example.com",
      "phone": "+254712345682",
      "avatar": null,
      "role": "Maid of Honor",
      "role_description": "Responsible for bridesmaids and bridal shower",
      "permissions": [
        "view_guests",
        "manage_guests",
        "send_invitations",
        "view_budget",
        "manage_budget"
      ],
      "status": "active",
      "invited_at": "2025-01-22T10:05:00Z",
      "accepted_at": "2025-01-22T11:00:00Z",
      "last_active_at": "2025-02-04T16:30:00Z",
      "created_at": "2025-01-22T10:05:00Z"
    },
    {
      "id": "d50e8400-e29b-41d4-a716-446655440003",
      "event_id": "b50e8400-e29b-41d4-a716-446655440001",
      "user_id": null,
      "name": "David Brown",
      "email": "david.b@example.com",
      "phone": "+254712345683",
      "avatar": null,
      "role": "Treasurer",
      "role_description": "Managing event finances and contributions",
      "permissions": [
        "view_budget",
        "manage_budget",
        "view_contributions",
        "manage_contributions"
      ],
      "status": "invited",
      "invited_at": "2025-02-05T09:00:00Z",
      "accepted_at": null,
      "last_active_at": null,
      "created_at": "2025-02-05T09:00:00Z"
    }
  ]
}
```

---

## 5.2 Add Committee Member

Adds a new committee member to the event.

```
POST /user-events/{eventId}/committee
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:**

```json
{
  "name": "Jane Wilson",
  "email": "jane.wilson@example.com",
  "phone": "+254712345684",
  "role": "Event Coordinator",
  "role_description": "Coordinating vendors and event timeline",
  "permissions": [
    "view_guests",
    "manage_guests",
    "send_invitations",
    "view_budget",
    "manage_vendors",
    "view_schedule",
    "manage_schedule"
  ],
  "send_invitation": true,
  "invitation_message": "We'd love for you to be our Event Coordinator!"
}
```

| Field              | Type          | Required    | Description                                         |
| ------------------ | ------------- | ----------- | --------------------------------------------------- |
| name               | string        | Yes         | Member's full name                                  |
| email              | string        | Conditional | Email address (required if send_invitation is true) |
| phone              | string        | No          | Phone number with country code                      |
| role               | string        | Yes         | Role title (max 50 chars)                           |
| role_description   | string        | No          | Role description (max 200 chars)                    |
| permissions        | array[string] | Yes         | List of permissions                                 |
| send_invitation    | boolean       | No          | Send email invitation (default: true)               |
| invitation_message | string        | No          | Custom invitation message                           |

**Available Permissions:**

- `view_guests` - View guest list
- `manage_guests` - Add, edit, remove guests
- `send_invitations` - Send invitations to guests
- `view_budget` - View budget and expenses
- `manage_budget` - Add and edit budget items
- `view_contributions` - View contributions
- `manage_contributions` - Record and manage contributions
- `view_vendors` - View booked vendors
- `manage_vendors` - Book and manage vendors
- `view_schedule` - View event schedule
- `manage_schedule` - Edit event schedule
- `checkin_guests` - Check in guests at event
- `view_expenses` - View expense records and reports
- `manage_expenses` - Record, edit, and delete expenses (auto-grants view_expenses)

**Success Response (201 Created):**

```json
{
  "success": true,
  "message": "Committee member added successfully",
  "data": {
    "id": "d50e8400-e29b-41d4-a716-446655440004",
    "event_id": "b50e8400-e29b-41d4-a716-446655440001",
    "user_id": null,
    "name": "Jane Wilson",
    "email": "jane.wilson@example.com",
    "phone": "+254712345684",
    "avatar": null,
    "role": "Event Coordinator",
    "role_description": "Coordinating vendors and event timeline",
    "permissions": [
      "view_guests",
      "manage_guests",
      "send_invitations",
      "view_budget",
      "manage_vendors",
      "view_schedule",
      "manage_schedule"
    ],
    "status": "invited",
    "invited_at": "2025-02-05T17:00:00Z",
    "accepted_at": null,
    "invitation_url": "https://nuru.com/committee/join/xyz789",
    "created_at": "2025-02-05T17:00:00Z"
  }
}
```

---

## 5.3 Update Committee Member

Updates a committee member's information and permissions.

```
PUT /user-events/{eventId}/committee/{memberId}
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:**

```json
{
  "role": "Head Coordinator",
  "role_description": "Leading the coordination team",
  "permissions": [
    "view_guests",
    "manage_guests",
    "send_invitations",
    "view_budget",
    "manage_budget",
    "manage_vendors",
    "view_schedule",
    "manage_schedule",
    "checkin_guests"
  ]
}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Committee member updated successfully",
  "data": {
    "id": "d50e8400-e29b-41d4-a716-446655440004",
    "event_id": "b50e8400-e29b-41d4-a716-446655440001",
    "name": "Jane Wilson",
    "email": "jane.wilson@example.com",
    "role": "Head Coordinator",
    "role_description": "Leading the coordination team",
    "permissions": [
      "view_guests",
      "manage_guests",
      "send_invitations",
      "view_budget",
      "manage_budget",
      "manage_vendors",
      "view_schedule",
      "manage_schedule",
      "checkin_guests"
    ],
    "status": "active",
    "updated_at": "2025-02-05T17:30:00Z"
  }
}
```

---

## 5.4 Remove Committee Member

Removes a committee member from the event.

```
DELETE /user-events/{eventId}/committee/{memberId}
Authorization: Bearer {access_token}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Committee member removed successfully"
}
```

---

## 5.5 Resend Committee Invitation

Resends invitation to a pending committee member.

```
POST /user-events/{eventId}/committee/{memberId}/resend-invite
Authorization: Bearer {access_token}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Invitation resent successfully",
  "data": {
    "member_id": "d50e8400-e29b-41d4-a716-446655440003",
    "sent_at": "2025-02-05T18:00:00Z"
  }
}
```

---

## 5.6 Accept Committee Invitation (Public)

Allows invited member to accept the invitation.

```
POST /events/committee/accept
Content-Type: application/json
Authentication: None (uses invitation token)
```

**Request Body:**

```json
{
  "token": "xyz789abc123",
  "user_id": "550e8400-e29b-41d4-a716-446655440015"
}
```

| Field   | Type   | Required | Description                            |
| ------- | ------ | -------- | -------------------------------------- |
| token   | string | Yes      | Invitation token from email link       |
| user_id | uuid   | No       | If logged in, link to existing account |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Invitation accepted successfully",
  "data": {
    "event": {
      "id": "b50e8400-e29b-41d4-a716-446655440001",
      "title": "John & Jane's Wedding"
    },
    "role": "Event Coordinator",
    "permissions": ["view_guests", "manage_guests"],
    "redirect_url": "https://nuru.com/events/b50e8400/manage"
  }
}
```

---

# 📋 MODULE 6A: USER CONTRIBUTORS (Address Book)

Contributors are NOT registered Nuru users. They are stored in a personal address book (`user_contributors`) per user.

---

## 6A.1 `GET /user-contributors/` — List user's contributors (search, paginate)

## 6A.2 `POST /user-contributors/` — Create contributor `{ name, email?, phone?, notes? }`

## 6A.3 `PUT /user-contributors/{id}` — Update contributor

## 6A.4 `DELETE /user-contributors/{id}` — Delete contributor

---

# 💰 MODULE 6B: EVENT CONTRIBUTORS & CONTRIBUTIONS

Event contributors link a `user_contributor` to a specific event with a pledge. Payments are recorded per event contributor.

---

## 6B.1 `GET /user-contributors/events/{eventId}/contributors` — List event contributors with pledge/paid/balance summary

## 6B.2 `POST /user-contributors/events/{eventId}/contributors` — Add contributor (existing `contributor_id` or inline `name/email/phone` + `pledge_amount`)

## 6B.3 `PUT /user-contributors/events/{eventId}/contributors/{ecId}` — Update pledge `{ pledge_amount }`

## 6B.4 `DELETE /user-contributors/events/{eventId}/contributors/{ecId}` — Remove from event

## 6B.5 `POST /user-contributors/events/{eventId}/contributors/{ecId}/payments` — Record payment `{ amount, payment_method, payment_reference }`

## 6B.6 `GET /user-contributors/events/{eventId}/contributors/{ecId}/payments` — Payment history

## 6B.7 `POST /user-contributors/events/{eventId}/contributors/{ecId}/thank-you` — Send thank you SMS `{ custom_message? }`

## 6B.8 `POST /user-contributors/events/{eventId}/contributors/bulk` — Bulk add/update contributors

### 6B.8 Bulk Contributors

**Request Body:**

```json
{
  "contributors": [
    { "name": "John Doe", "phone": "0653750805", "amount": 50000 },
    { "name": "Jane Smith", "phone": "255712345678", "amount": 100000 }
  ],
  "send_sms": false,
  "mode": "targets",
  "payment_method": "other"
}
```

**Fields:**

- `contributors` (required): Array of objects with `name`, `phone`, `amount`
- `send_sms` (optional, default: false): Whether to send SMS notifications to each contributor
- `mode` (optional, default: "targets"): `"targets"` to set/update pledge amounts, `"contributions"` to record actual payments
- `payment_method` (optional, default: "other"): Payment method for contributions mode

**Behavior:**

- Phone numbers are validated and formatted to Tanzanian format (255...)
- Existing contributors are matched by phone number first, then by name
- New contributors are created automatically in the user's address book
- If contributor already linked to event: pledge is updated (targets mode) or payment is recorded (contributions mode)
- If not linked: contributor is added to event
- Maximum 500 contributors per upload

**Response:**

```json
{
  "success": true,
  "data": {
    "processed": 10,
    "errors_count": 2,
    "results": [{ "row": 1, "name": "John Doe", "action": "added" }],
    "errors": [{ "row": 3, "message": "Invalid phone for Ali: 123" }]
  }
}
```

---

# 💰 MODULE 6C: LEGACY CONTRIBUTIONS (backward compat)

---

## 6.1 Get Event Contributions

Returns all contributions for an event.

```
GET /user-events/{eventId}/contributions
Authorization: Bearer {access_token}
```

**Query Parameters:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| page | integer | No | 1 | Page number |
| limit | integer | No | 20 | Items per page |
| status | string | No | all | Filter: pending, confirmed, failed, all |
| sort_by | string | No | created_at | Sort: created_at, amount, contributor_name |
| sort_order | string | No | desc | Sort order: asc, desc |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Contributions retrieved successfully",
  "data": {
    "contributions": [
      {
        "id": "e50e8400-e29b-41d4-a716-446655440001",
        "event_id": "b50e8400-e29b-41d4-a716-446655440001",
        "contributor_name": "James Wilson",
        "contributor_email": "james@example.com",
        "contributor_phone": "+254712345683",
        "contributor_user_id": "550e8400-e29b-41d4-a716-446655440020",
        "contributor_avatar": "https://storage.nuru.com/avatars/james.jpg",
        "amount": 50000.0,
        "currency": "KES",
        "payment_method": "mpesa",
        "payment_reference": "QK7JH8L9M2",
        "mpesa_receipt": "QK7JH8L9M2",
        "status": "confirmed",
        "message": "Congratulations! Wishing you a lifetime of happiness.",
        "is_anonymous": false,
        "thank_you_sent": true,
        "thank_you_sent_at": "2025-02-01T16:00:00Z",
        "created_at": "2025-02-01T15:30:00Z",
        "confirmed_at": "2025-02-01T15:31:00Z"
      },
      {
        "id": "e50e8400-e29b-41d4-a716-446655440002",
        "event_id": "b50e8400-e29b-41d4-a716-446655440001",
        "contributor_name": "Anonymous",
        "contributor_email": null,
        "contributor_phone": null,
        "contributor_user_id": null,
        "contributor_avatar": null,
        "amount": 25000.0,
        "currency": "KES",
        "payment_method": "bank_transfer",
        "payment_reference": "TRF123456789",
        "mpesa_receipt": null,
        "status": "confirmed",
        "message": "Best wishes!",
        "is_anonymous": true,
        "thank_you_sent": true,
        "thank_you_sent_at": "2025-02-02T15:00:00Z",
        "created_at": "2025-02-02T09:00:00Z",
        "confirmed_at": "2025-02-02T14:00:00Z"
      },
      {
        "id": "e50e8400-e29b-41d4-a716-446655440003",
        "event_id": "b50e8400-e29b-41d4-a716-446655440001",
        "contributor_name": "Mary Johnson",
        "contributor_email": "mary@example.com",
        "contributor_phone": "+254712345685",
        "contributor_user_id": null,
        "contributor_avatar": null,
        "amount": 10000.0,
        "currency": "KES",
        "payment_method": "mpesa",
        "payment_reference": null,
        "mpesa_receipt": null,
        "status": "pending",
        "message": "Happy wedding day!",
        "is_anonymous": false,
        "thank_you_sent": false,
        "thank_you_sent_at": null,
        "created_at": "2025-02-05T10:00:00Z",
        "confirmed_at": null
      }
    ],
    "summary": {
      "total_contributions": 34,
      "total_amount": 456000.0,
      "target_amount": 1000000.0,
      "progress_percentage": 45.6,
      "confirmed_count": 32,
      "pending_count": 2,
      "currency": "KES",
      "average_contribution": 14250.0,
      "largest_contribution": 100000.0,
      "smallest_contribution": 1000.0
    },
    "pagination": {
      "page": 1,
      "limit": 20,
      "total_items": 34,
      "total_pages": 2,
      "has_next": true,
      "has_previous": false
    }
  }
}
```

---

## 6.2 Record Contribution or Pledge

Records a contribution (confirmed payment) or pledge (pending commitment) for an event.
Contributors do NOT need to be registered Nuru users — manual entry with name/email/phone is supported.

- **status: "pending"** = Pledge (target/commitment, not yet paid)
- **status: "confirmed"** = Actual payment received

```
POST /user-events/{eventId}/contributions
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:**

```json
{
  "contributor_name": "John Smith",
  "contributor_email": "john.smith@example.com",
  "contributor_phone": "+254712345686",
  "contributor_user_id": null,
  "amount": 30000.0,
  "payment_method": "cash",
  "payment_reference": "CASH-001",
  "status": "confirmed"
}
```

| Field               | Type   | Required | Description                                                        |
| ------------------- | ------ | -------- | ------------------------------------------------------------------ |
| contributor_name    | string | Yes      | Contributor's name                                                 |
| contributor_email   | string | No       | Contributor's email                                                |
| contributor_phone   | string | No       | Contributor's phone                                                |
| contributor_user_id | uuid   | No       | Link to Nuru user (optional, contributors need not be users)       |
| amount              | number | Yes      | Amount (positive number)                                           |
| payment_method      | string | No       | Method: cash, bank_transfer, mobile, card (default: mobile)        |
| payment_reference   | string | No       | Payment reference number                                           |
| status              | string | No       | "pending" for pledge, "confirmed" for payment (default: confirmed) |

**Success Response (201 Created):**

```json
{
  "success": true,
  "message": "Contribution recorded successfully",
  "data": {
    "id": "e50e8400-e29b-41d4-a716-446655440004",
    "event_id": "b50e8400-e29b-41d4-a716-446655440001",
    "contributor_name": "John Smith",
    "contributor_email": "john.smith@example.com",
    "contributor_phone": "+254712345686",
    "contributor_user_id": null,
    "amount": 30000.0,
    "currency": "TZS",
    "payment_method": "cash",
    "payment_reference": "CASH-001",
    "status": "confirmed",
    "is_anonymous": false,
    "thank_you_sent": false,
    "thank_you_sent_at": null,
    "created_at": "2025-02-05T18:00:00Z",
    "confirmed_at": "2025-02-05T18:00:00Z"
  }
}
```

---

## 6.3 Update Contribution

Updates a contribution record.

```
PUT /user-events/{eventId}/contributions/{contributionId}
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:**

```json
{
  "status": "confirmed",
  "payment_reference": "UPDATED-REF-001",
  "notes": "Payment verified via bank statement"
}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Contribution updated successfully",
  "data": {
    "id": "e50e8400-e29b-41d4-a716-446655440003",
    "status": "confirmed",
    "payment_reference": "UPDATED-REF-001",
    "notes": "Payment verified via bank statement",
    "confirmed_at": "2025-02-05T18:30:00Z",
    "updated_at": "2025-02-05T18:30:00Z"
  }
}
```

---

## 6.4 Delete Contribution

Deletes a contribution record.

```
DELETE /user-events/{eventId}/contributions/{contributionId}
Authorization: Bearer {access_token}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Contribution deleted successfully"
}
```

---

## 6.5 Send Thank You

Sends a thank you message to a contributor.

```
POST /user-events/{eventId}/contributions/{contributionId}/thank
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:**

```json
{
  "method": "email",
  "custom_message": "Thank you so much for your generous gift! It means the world to us."
}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Thank you sent successfully",
  "data": {
    "contribution_id": "e50e8400-e29b-41d4-a716-446655440001",
    "thank_you_sent": true,
    "thank_you_sent_at": "2025-02-05T19:00:00Z",
    "method": "email"
  }
}
```

---

## 6.6 Send Bulk Thank You

Sends thank you messages to multiple contributors.

```
POST /user-events/{eventId}/contributions/thank-all
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:**

```json
{
  "contribution_ids": [
    "e50e8400-e29b-41d4-a716-446655440001",
    "e50e8400-e29b-41d4-a716-446655440002"
  ],
  "filter": {
    "thank_you_sent": false,
    "status": "confirmed"
  },
  "method": "email",
  "custom_message": "Thank you for being part of our special day!"
}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Thank you messages sent",
  "data": {
    "sent_count": 15,
    "failed_count": 2,
    "failures": [
      {
        "contribution_id": "e50e8400-e29b-41d4-a716-446655440010",
        "reason": "No email address"
      }
    ]
  }
}
```

---

## 6.7 Public Contribution Page (No Auth)

Returns the public contribution page for an event.

```
GET /events/{eventId}/contribute
Authentication: None
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "data": {
    "event": {
      "id": "b50e8400-e29b-41d4-a716-446655440001",
      "title": "John & Jane's Wedding",
      "cover_image": "https://storage.nuru.com/events/b50e8400-cover.jpg",
      "start_date": "2025-06-15T14:00:00Z",
      "host_names": "John & Jane",
      "host_avatar": "https://storage.nuru.com/avatars/john-jane.jpg"
    },
    "contribution_info": {
      "enabled": true,
      "description": "Help us start our new life together. Your generous contributions will go towards our honeymoon fund.",
      "target_amount": 1000000.0,
      "current_amount": 456000.0,
      "progress_percentage": 45.6,
      "contributor_count": 34,
      "currency": "KES",
      "show_target": true,
      "show_contributors": true,
      "suggested_amounts": [5000, 10000, 25000, 50000]
    },
    "payment_methods": [
      {
        "id": "mpesa",
        "name": "M-PESA",
        "icon": "mpesa",
        "instructions": "Pay to Paybill 123456, Account: WEDDING2025"
      },
      {
        "id": "bank_transfer",
        "name": "Bank Transfer",
        "icon": "bank",
        "instructions": "Account: 1234567890, Bank: KCB, Name: John Doe"
      }
    ],
    "recent_contributions": [
      {
        "contributor_name": "James W.",
        "amount": 50000.0,
        "message": "Congratulations!",
        "created_at": "2025-02-01T15:30:00Z"
      },
      {
        "contributor_name": "Anonymous",
        "amount": 25000.0,
        "message": "Best wishes!",
        "created_at": "2025-02-02T09:00:00Z"
      }
    ]
  }
}
```

---

## 6.8 Submit Public Contribution

Initiates a contribution from the public page.

```
POST /events/{eventId}/contribute
Content-Type: application/json
Authentication: None
```

**Request Body:**

```json
{
  "contributor_name": "Peter Kamau",
  "contributor_email": "peter@example.com",
  "contributor_phone": "+254712345687",
  "amount": 20000.0,
  "payment_method": "mpesa",
  "message": "Congratulations to the happy couple!",
  "is_anonymous": false
}
```

**Success Response (200 OK) - M-PESA:**

```json
{
  "success": true,
  "message": "Payment initiated",
  "data": {
    "contribution_id": "e50e8400-e29b-41d4-a716-446655440005",
    "payment_method": "mpesa",
    "status": "pending",
    "payment_instructions": {
      "type": "stk_push",
      "message": "Please check your phone for the M-PESA prompt and enter your PIN to complete the payment."
    },
    "checkout_request_id": "ws_CO_123456789",
    "expires_at": "2025-02-05T19:05:00Z"
  }
}
```

**Success Response (200 OK) - Bank Transfer:**

```json
{
  "success": true,
  "message": "Contribution recorded",
  "data": {
    "contribution_id": "e50e8400-e29b-41d4-a716-446655440006",
    "payment_method": "bank_transfer",
    "status": "pending",
    "payment_instructions": {
      "type": "manual",
      "bank_name": "KCB Bank",
      "account_number": "1234567890",
      "account_name": "John Doe",
      "reference": "WEDDING-e50e8400",
      "message": "Please transfer to the account above and use the reference number. Your contribution will be confirmed once payment is verified."
    }
  }
}
```

---

## 6.9 Export Contributions

Exports contribution data.

```
GET /user-events/{eventId}/contributions/export
Authorization: Bearer {access_token}
```

**Query Parameters:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| format | string | No | csv | Export format: csv, xlsx, pdf |
| status | string | No | all | Filter by status |
| include_anonymous | boolean | No | true | Include anonymous contributions |

**Success Response (200 OK):**
Returns file download.

Continuing with the complete API documentation for all remaining modules.

---

## 6.10 Get Pending Contributions (Creator Only)

Retrieves all pending contributions awaiting creator confirmation. Contributions recorded by committee members are initially set to "pending" status.

```
GET /user-contributors/events/{eventId}/pending-contributions
Authorization: Bearer {access_token}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Pending contributions fetched",
  "data": {
    "contributions": [
      {
        "id": "e50e8400-e29b-41d4-a716-446655440005",
        "contributor_name": "Jane Smith",
        "contributor_phone": "+254712345687",
        "amount": 25000.0,
        "payment_method": "mobile",
        "transaction_ref": "TXN-2025-001",
        "recorded_by": "David Johnson",
        "created_at": "2025-02-05T15:30:00Z"
      },
      {
        "id": "e50e8400-e29b-41d4-a716-446655440006",
        "contributor_name": "James Brown",
        "contributor_phone": "+254712345688",
        "amount": 15000.0,
        "payment_method": "cash",
        "transaction_ref": null,
        "recorded_by": "Sarah Wilson",
        "created_at": "2025-02-05T14:20:00Z"
      }
    ],
    "count": 2
  }
}
```

**Response Fields:**
| Field | Type | Description |
|-------|------|-------------|
| id | uuid | Contribution ID |
| contributor_name | string | Name of the contributor |
| contributor_phone | string | Contributor's phone number |
| amount | number | Contribution amount |
| payment_method | string | Payment method used |
| transaction_ref | string | Payment reference or transaction ID |
| recorded_by | string | Name of committee member who recorded it |
| created_at | string | When the contribution was recorded (ISO 8601) |

---

## 6.11 Confirm Pending Contributions (Creator Only)

Confirms one or more pending contributions, moving them from "pending" to "confirmed" status. Multiple contributions can be confirmed in a single request.

```
POST /user-contributors/events/{eventId}/confirm-contributions
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:**

```json
{
  "contribution_ids": [
    "e50e8400-e29b-41d4-a716-446655440005",
    "e50e8400-e29b-41d4-a716-446655440006"
  ]
}
```

| Field            | Type  | Required | Description                            |
| ---------------- | ----- | -------- | -------------------------------------- |
| contribution_ids | array | Yes      | Array of contribution UUIDs to confirm |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "2 contributions confirmed",
  "data": {
    "confirmed": 2
  }
}
```

---

## 6.12 Get My Recorded Contributions (Committee Member Only)

Retrieves all contributions recorded by the current committee member, including their confirmation status. Committee members can only use this if they have the "can_manage_contributions" permission.

```
GET /user-contributors/events/{eventId}/my-recorded-contributions
Authorization: Bearer {access_token}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Your recorded contributions fetched",
  "data": {
    "contributions": [
      {
        "id": "e50e8400-e29b-41d4-a716-446655440005",
        "contributor_name": "Jane Smith",
        "contributor_phone": "+254712345687",
        "amount": 25000.0,
        "payment_method": "mobile",
        "transaction_ref": "TXN-2025-001",
        "confirmation_status": "pending",
        "confirmed_at": null,
        "created_at": "2025-02-05T15:30:00Z"
      },
      {
        "id": "e50e8400-e29b-41d4-a716-446655440007",
        "contributor_name": "Alice Green",
        "contributor_phone": "+254712345689",
        "amount": 35000.0,
        "payment_method": "bank_transfer",
        "transaction_ref": "BANK-2025-042",
        "confirmation_status": "confirmed",
        "confirmed_at": "2025-02-05T16:45:00Z",
        "created_at": "2025-02-05T14:15:00Z"
      }
    ],
    "count": 2
  }
}
```

**Response Fields:**
| Field | Type | Description |
|-------|------|-------------|
| id | uuid | Contribution ID |
| contributor_name | string | Name of the contributor |
| contributor_phone | string | Contributor's phone number |
| amount | number | Contribution amount |
| payment_method | string | Payment method used |
| transaction_ref | string | Payment reference or transaction ID |
| confirmation_status | string | Status: "pending" (awaiting creator confirmation) or "confirmed" |
| confirmed_at | string | When the creator confirmed this contribution (ISO 8601, null if pending) |
| created_at | string | When the contribution was recorded (ISO 8601) |

---

## 6.13 Get Contribution Report (Date-Filtered)

Returns contributor payment totals optionally filtered by date range. Only confirmed payments within the date range are summed. Pledges are shown as-is for context. When a date range is applied, the report focuses on showing collections within that period — overall balances reflect only the filtered payments and may differ from full event totals.

```
GET /user-contributors/events/{eventId}/contribution-report
Authorization: Bearer {access_token}
```

**Query Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| date_from | string | No | Start date filter (YYYY-MM-DD). Payments on or after this date. |
| date_to | string | No | End date filter (YYYY-MM-DD). Payments on or before this date. |

**Example Request:**

```
GET /user-contributors/events/{eventId}/contribution-report?date_from=2026-02-01&date_to=2026-02-15
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Report data fetched",
  "data": {
    "contributors": [
      {
        "name": "Jane Smith",
        "phone": "255712345687",
        "pledged": 100000,
        "paid": 50000,
        "balance": 50000
      }
    ],
    "full_summary": {
      "total_pledged": 500000,
      "total_paid": 350000,
      "total_balance": 150000,
      "count": 10,
      "currency": "TZS"
    },
    "filtered_summary": {
      "total_paid": 250000,
      "contributor_count": 5
    },
    "date_from": "2026-02-01",
    "date_to": "2026-02-15",
    "is_filtered": true
  }
}
```

**Response Fields:**
| Field | Type | Description |
|-------|------|-------------|
| contributors | array | List of contributors with payment totals (filtered by date range if specified) |
| contributors[].name | string | Contributor name |
| contributors[].phone | string | Contributor phone number |
| contributors[].pledged | number | Full pledge amount (not date-filtered) |
| contributors[].paid | number | Total payments within the selected date range |
| contributors[].balance | number | Remaining balance (pledge - paid within range) |
| full_summary | object | All-time aggregated totals (always complete, never date-filtered) |
| filtered_summary | object | Totals for only the date-filtered table rows |
| filtered_summary.total_paid | number | Sum of payments within the selected period |
| filtered_summary.contributor_count | number | Number of contributors with activity in the period |
| date_from | string | Applied start date filter (null if not set) |
| date_to | string | Applied end date filter (null if not set) |
| is_filtered | boolean | Whether date filters were applied |

**Notes:**

- `full_summary` always reflects all-time totals regardless of date filters — use for report header cards
- `contributors` table rows show payments filtered by date range when `is_filtered` is `true`
- Pledges are always shown in full regardless of date filters
- Contributors with zero payments in the range but non-zero pledges are still included

---

---

# 🛠️ MODULE 7: USER SERVICES (Vendor Dashboard)

---

## 7.1 Get All My Services

Returns all services created by the authenticated vendor.

```
GET /user-services/
Authorization: Bearer {access_token}
```

**Query Parameters:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| page | integer | No | 1 | Page number |
| limit | integer | No | 20 | Items per page (max 100) |
| status | string | No | all | Filter: active, inactive, suspended, all |
| verification_status | string | No | all | Filter: unverified, pending, verified, rejected, all |
| category_id | uuid | No | null | Filter by service category |
| sort_by | string | No | created_at | Sort: created_at, title, rating, review_count |
| sort_order | string | No | desc | Sort order: asc, desc |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Services retrieved successfully",
  "data": {
    "services": [
      {
        "id": "g50e8400-e29b-41d4-a716-446655440001",
        "user_id": "550e8400-e29b-41d4-a716-446655440000",
        "title": "Premium Wedding Photography",
        "description": "Capturing your special moments with artistic excellence. Over 10 years of experience in wedding photography across East Africa.",
        "service_category_id": "650e8400-e29b-41d4-a716-446655440001",
        "service_category": {
          "id": "650e8400-e29b-41d4-a716-446655440001",
          "name": "Photography & Videography",
          "icon": "camera"
        },
        "service_type_id": "750e8400-e29b-41d4-a716-446655440001",
        "service_type": {
          "id": "750e8400-e29b-41d4-a716-446655440001",
          "name": "Wedding Photography",
          "category_id": "650e8400-e29b-41d4-a716-446655440001"
        },
        "min_price": 50000.0,
        "max_price": 250000.0,
        "currency": "KES",
        "price_type": "range",
        "price_unit": "per_event",
        "location": "Nairobi, Kenya",
        "service_areas": ["Nairobi", "Mombasa", "Nakuru", "Kisumu"],
        "status": "active",
        "verification_status": "verified",
        "verification_progress": 100,
        "verified_at": "2025-01-15T10:00:00Z",
        "images": [
          {
            "id": "img-001",
            "url": "https://storage.nuru.com/services/g50e8400-img1.jpg",
            "thumbnail_url": "https://storage.nuru.com/services/g50e8400-img1-thumb.jpg",
            "alt": "Wedding couple portrait",
            "is_primary": true,
            "display_order": 1
          },
          {
            "id": "img-002",
            "url": "https://storage.nuru.com/services/g50e8400-img2.jpg",
            "thumbnail_url": "https://storage.nuru.com/services/g50e8400-img2-thumb.jpg",
            "alt": "Wedding ceremony shot",
            "is_primary": false,
            "display_order": 2
          },
          {
            "id": "img-003",
            "url": "https://storage.nuru.com/services/g50e8400-img3.jpg",
            "thumbnail_url": "https://storage.nuru.com/services/g50e8400-img3-thumb.jpg",
            "alt": "Reception photography",
            "is_primary": false,
            "display_order": 3
          }
        ],
        "rating": 4.9,
        "review_count": 156,
        "booking_count": 234,
        "completed_events": 198,
        "response_rate": 98.5,
        "response_time_hours": 2,
        "years_experience": 10,
        "team_size": 4,
        "availability": "available",
        "next_available_date": "2025-02-20",
        "featured": true,
        "featured_until": "2025-03-01T00:00:00Z",
        "package_count": 3,
        "views_count": 1250,
        "inquiries_count": 89,
        "created_at": "2024-06-15T10:30:00Z",
        "updated_at": "2025-02-01T14:20:00Z"
      },
      {
        "id": "g50e8400-e29b-41d4-a716-446655440002",
        "user_id": "550e8400-e29b-41d4-a716-446655440000",
        "title": "Drone Aerial Coverage",
        "description": "Stunning aerial photography and videography for events using state-of-the-art drones.",
        "service_category_id": "650e8400-e29b-41d4-a716-446655440001",
        "service_category": {
          "id": "650e8400-e29b-41d4-a716-446655440001",
          "name": "Photography & Videography",
          "icon": "camera"
        },
        "service_type_id": "750e8400-e29b-41d4-a716-446655440004",
        "service_type": {
          "id": "750e8400-e29b-41d4-a716-446655440004",
          "name": "Drone Photography",
          "category_id": "650e8400-e29b-41d4-a716-446655440001"
        },
        "min_price": 30000.0,
        "max_price": 80000.0,
        "currency": "KES",
        "price_type": "range",
        "price_unit": "per_event",
        "location": "Nairobi, Kenya",
        "service_areas": ["Nairobi", "Kiambu", "Machakos"],
        "status": "active",
        "verification_status": "pending",
        "verification_progress": 60,
        "verified_at": null,
        "images": [
          {
            "id": "img-010",
            "url": "https://storage.nuru.com/services/g50e8400-002-img1.jpg",
            "thumbnail_url": "https://storage.nuru.com/services/g50e8400-002-img1-thumb.jpg",
            "alt": "Drone aerial shot",
            "is_primary": true,
            "display_order": 1
          }
        ],
        "rating": 4.7,
        "review_count": 23,
        "booking_count": 45,
        "completed_events": 38,
        "response_rate": 95.0,
        "response_time_hours": 4,
        "years_experience": 3,
        "team_size": 2,
        "availability": "available",
        "next_available_date": "2025-02-15",
        "featured": false,
        "featured_until": null,
        "package_count": 2,
        "views_count": 450,
        "inquiries_count": 34,
        "created_at": "2024-09-20T08:00:00Z",
        "updated_at": "2025-02-03T11:45:00Z"
      }
    ],
    "summary": {
      "total_services": 2,
      "active_services": 2,
      "verified_services": 1,
      "pending_verification": 1,
      "total_bookings": 279,
      "total_reviews": 179,
      "average_rating": 4.8
    },
    "pagination": {
      "page": 1,
      "limit": 20,
      "total_items": 2,
      "total_pages": 1,
      "has_next": false,
      "has_previous": false
    }
  }
}
```

---

## 7.2 Get Single Service

Returns detailed information about a specific service.

```
GET /user-services/{serviceId}
Authorization: Bearer {access_token}
```

**Path Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| serviceId | uuid | Yes | Service unique identifier |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Service retrieved successfully",
  "data": {
    "id": "g50e8400-e29b-41d4-a716-446655440001",
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "title": "Premium Wedding Photography",
    "description": "Capturing your special moments with artistic excellence. Over 10 years of experience in wedding photography across East Africa. We specialize in candid, documentary-style photography that tells your unique love story.\n\nOur team of 4 professional photographers ensures comprehensive coverage of your entire wedding day, from pre-ceremony preparations to the last dance.",
    "short_description": "Professional wedding photography with 10+ years of experience",
    "service_category_id": "650e8400-e29b-41d4-a716-446655440001",
    "service_category": {
      "id": "650e8400-e29b-41d4-a716-446655440001",
      "name": "Photography & Videography",
      "icon": "camera"
    },
    "service_type_id": "750e8400-e29b-41d4-a716-446655440001",
    "service_type": {
      "id": "750e8400-e29b-41d4-a716-446655440001",
      "name": "Wedding Photography",
      "category_id": "650e8400-e29b-41d4-a716-446655440001"
    },
    "min_price": 50000.0,
    "max_price": 250000.0,
    "currency": "KES",
    "price_type": "range",
    "price_unit": "per_event",
    "price_notes": "Prices vary based on coverage duration and package selected",
    "location": "Nairobi, Kenya",
    "full_address": "Westlands, Nairobi, Kenya",
    "service_areas": [
      "Nairobi",
      "Mombasa",
      "Nakuru",
      "Kisumu",
      "Naivasha",
      "Nanyuki"
    ],
    "travel_fee_info": "Travel fee applies for locations outside Nairobi (KES 5,000 - 15,000)",
    "status": "active",
    "verification_status": "verified",
    "verification_progress": 100,
    "verified_at": "2025-01-15T10:00:00Z",
    "verification_badge": "gold",
    "images": [
      {
        "id": "img-001",
        "url": "https://storage.nuru.com/services/g50e8400-img1.jpg",
        "thumbnail_url": "https://storage.nuru.com/services/g50e8400-img1-thumb.jpg",
        "medium_url": "https://storage.nuru.com/services/g50e8400-img1-medium.jpg",
        "alt": "Wedding couple portrait",
        "caption": "Romantic sunset portrait session",
        "is_primary": true,
        "display_order": 1
      },
      {
        "id": "img-002",
        "url": "https://storage.nuru.com/services/g50e8400-img2.jpg",
        "thumbnail_url": "https://storage.nuru.com/services/g50e8400-img2-thumb.jpg",
        "medium_url": "https://storage.nuru.com/services/g50e8400-img2-medium.jpg",
        "alt": "Wedding ceremony shot",
        "caption": "Emotional ceremony moments",
        "is_primary": false,
        "display_order": 2
      },
      {
        "id": "img-003",
        "url": "https://storage.nuru.com/services/g50e8400-img3.jpg",
        "thumbnail_url": "https://storage.nuru.com/services/g50e8400-img3-thumb.jpg",
        "medium_url": "https://storage.nuru.com/services/g50e8400-img3-medium.jpg",
        "alt": "Reception photography",
        "caption": "Vibrant reception celebrations",
        "is_primary": false,
        "display_order": 3
      },
      {
        "id": "img-004",
        "url": "https://storage.nuru.com/services/g50e8400-img4.jpg",
        "thumbnail_url": "https://storage.nuru.com/services/g50e8400-img4-thumb.jpg",
        "medium_url": "https://storage.nuru.com/services/g50e8400-img4-medium.jpg",
        "alt": "Bridal preparation",
        "caption": "Getting ready moments",
        "is_primary": false,
        "display_order": 4
      },
      {
        "id": "img-005",
        "url": "https://storage.nuru.com/services/g50e8400-img5.jpg",
        "thumbnail_url": "https://storage.nuru.com/services/g50e8400-img5-thumb.jpg",
        "medium_url": "https://storage.nuru.com/services/g50e8400-img5-medium.jpg",
        "alt": "Wedding details",
        "caption": "Beautiful wedding details",
        "is_primary": false,
        "display_order": 5
      }
    ],
    "video_urls": [
      {
        "id": "vid-001",
        "url": "https://youtube.com/watch?v=xyz123",
        "thumbnail_url": "https://img.youtube.com/vi/xyz123/hqdefault.jpg",
        "title": "Wedding Highlight Reel",
        "duration_seconds": 180
      }
    ],
    "rating": 4.9,
    "rating_breakdown": {
      "5_star": 145,
      "4_star": 8,
      "3_star": 2,
      "2_star": 1,
      "1_star": 0
    },
    "review_count": 156,
    "booking_count": 234,
    "completed_events": 198,
    "response_rate": 98.5,
    "response_time_hours": 2,
    "years_experience": 10,
    "team_size": 4,
    "team_members": [
      {
        "name": "David Mwangi",
        "role": "Lead Photographer",
        "avatar": "https://storage.nuru.com/avatars/david.jpg",
        "bio": "Award-winning photographer with 10 years experience"
      },
      {
        "name": "Sarah Ochieng",
        "role": "Second Photographer",
        "avatar": "https://storage.nuru.com/avatars/sarah.jpg",
        "bio": "Specializes in candid and documentary photography"
      }
    ],
    "equipment": [
      "Canon EOS R5 (2x)",
      "Sony A7 IV",
      "Professional lighting equipment",
      "DJI Mavic 3 Drone"
    ],
    "languages": ["English", "Swahili"],
    "availability": "available",
    "next_available_date": "2025-02-20",
    "booking_lead_time_days": 14,
    "cancellation_policy": "Full refund up to 30 days before event. 50% refund up to 14 days before. No refund within 14 days.",
    "insurance_info": "Fully insured with Professional Indemnity Insurance",
    "featured": true,
    "featured_until": "2025-03-01T00:00:00Z",
    "highlights": [
      "Award-winning photographer",
      "10+ years experience",
      "Same-day photo preview",
      "Drone coverage included in premium packages"
    ],
    "faqs": [
      {
        "question": "How many photos will we receive?",
        "answer": "You'll receive 400-800 professionally edited photos depending on your package."
      },
      {
        "question": "How long until we get our photos?",
        "answer": "Preview within 48 hours, full gallery within 4-6 weeks."
      },
      {
        "question": "Do you travel for destination weddings?",
        "answer": "Yes! We love destination weddings. Travel costs are quoted separately."
      }
    ],
    "packages": [
      {
        "id": "h50e8400-e29b-41d4-a716-446655440001",
        "service_id": "g50e8400-e29b-41d4-a716-446655440001",
        "name": "Essential Package",
        "description": "Perfect for intimate weddings",
        "price": 50000.0,
        "currency": "KES",
        "duration_hours": 4,
        "photographers_count": 1,
        "features": [
          "4 hours of coverage",
          "1 professional photographer",
          "200+ edited photos",
          "Online gallery",
          "Print release"
        ],
        "deliverables": [
          "High-resolution digital images",
          "Online viewing gallery",
          "USB drive with all photos"
        ],
        "turnaround_days": 30,
        "is_popular": false,
        "is_active": true,
        "display_order": 1,
        "created_at": "2024-06-15T10:30:00Z"
      },
      {
        "id": "h50e8400-e29b-41d4-a716-446655440002",
        "service_id": "g50e8400-e29b-41d4-a716-446655440001",
        "name": "Premium Package",
        "description": "Our most popular wedding package",
        "price": 120000.0,
        "currency": "KES",
        "duration_hours": 8,
        "photographers_count": 2,
        "features": [
          "8 hours of coverage",
          "2 professional photographers",
          "400+ edited photos",
          "Engagement session included",
          "Online gallery",
          "Print release",
          "Same-day preview (20 photos)"
        ],
        "deliverables": [
          "High-resolution digital images",
          "Online viewing gallery",
          "USB drive in premium box",
          "20x30 canvas print"
        ],
        "turnaround_days": 21,
        "is_popular": true,
        "is_active": true,
        "display_order": 2,
        "created_at": "2024-06-15T10:30:00Z"
      },
      {
        "id": "h50e8400-e29b-41d4-a716-446655440003",
        "service_id": "g50e8400-e29b-41d4-a716-446655440001",
        "name": "Platinum Package",
        "description": "The ultimate wedding photography experience",
        "price": 250000.0,
        "currency": "KES",
        "duration_hours": 12,
        "photographers_count": 3,
        "features": [
          "Full day coverage (12 hours)",
          "3 professional photographers",
          "800+ edited photos",
          "Engagement session included",
          "Bridal/Groom preparation coverage",
          "Drone aerial photography",
          "Online gallery",
          "Print release",
          "Same-day slideshow at reception"
        ],
        "deliverables": [
          "High-resolution digital images",
          "Online viewing gallery",
          "Premium USB drive in wooden box",
          "30x40 canvas print",
          "Premium photo album (40 pages)",
          "Parent albums (2x 20 pages)"
        ],
        "turnaround_days": 14,
        "is_popular": false,
        "is_active": true,
        "display_order": 3,
        "created_at": "2024-06-15T10:30:00Z"
      }
    ],
    "reviews": [
      {
        "id": "r50e8400-e29b-41d4-a716-446655440001",
        "service_id": "g50e8400-e29b-41d4-a716-446655440001",
        "user_id": "550e8400-e29b-41d4-a716-446655440030",
        "user_name": "Jane Wanjiku",
        "user_avatar": "https://storage.nuru.com/avatars/jane-w.jpg",
        "rating": 5,
        "title": "Absolutely amazing!",
        "comment": "David and his team exceeded all our expectations. The photos are stunning and captured every special moment of our wedding day. Highly recommend!",
        "event_type": "Wedding",
        "event_date": "2025-01-20",
        "photos": [
          "https://storage.nuru.com/reviews/r50e8400-001-1.jpg",
          "https://storage.nuru.com/reviews/r50e8400-001-2.jpg"
        ],
        "vendor_response": "Thank you so much, Jane! It was an honor to be part of your special day. Wishing you and Peter a lifetime of happiness!",
        "vendor_response_at": "2025-01-25T10:00:00Z",
        "helpful_count": 12,
        "verified_booking": true,
        "created_at": "2025-01-22T14:30:00Z"
      },
      {
        "id": "r50e8400-e29b-41d4-a716-446655440002",
        "service_id": "g50e8400-e29b-41d4-a716-446655440001",
        "user_id": "550e8400-e29b-41d4-a716-446655440031",
        "user_name": "Michael Omondi",
        "user_avatar": "https://storage.nuru.com/avatars/michael-o.jpg",
        "rating": 5,
        "title": "Professional and creative",
        "comment": "We loved working with this team. They were professional, creative, and made us feel so comfortable in front of the camera. The photos are works of art!",
        "event_type": "Wedding",
        "event_date": "2024-12-15",
        "photos": [],
        "vendor_response": null,
        "vendor_response_at": null,
        "helpful_count": 8,
        "verified_booking": true,
        "created_at": "2024-12-20T09:15:00Z"
      },
      {
        "id": "r50e8400-e29b-41d4-a716-446655440003",
        "service_id": "g50e8400-e29b-41d4-a716-446655440001",
        "user_id": "550e8400-e29b-41d4-a716-446655440032",
        "user_name": "Grace Muthoni",
        "user_avatar": null,
        "rating": 4,
        "title": "Great photos, slight delay",
        "comment": "The photos are beautiful and exactly what we wanted. Only giving 4 stars because delivery took a bit longer than promised, but the quality made up for it.",
        "event_type": "Wedding",
        "event_date": "2024-11-08",
        "photos": [],
        "vendor_response": "Thank you for your feedback, Grace. We apologize for the delay and have since improved our workflow. We're glad you love the photos!",
        "vendor_response_at": "2024-11-20T11:30:00Z",
        "helpful_count": 5,
        "verified_booking": true,
        "created_at": "2024-11-15T16:45:00Z"
      }
    ],
    "past_events": [
      {
        "id": "pe-001",
        "event_type": "Wedding",
        "event_name": "Jane & Peter's Wedding",
        "event_date": "2025-01-20",
        "location": "Nairobi",
        "cover_image": "https://storage.nuru.com/events/pe-001-cover.jpg",
        "rating": 5
      },
      {
        "id": "pe-002",
        "event_type": "Wedding",
        "event_name": "Michael & Sarah's Wedding",
        "event_date": "2024-12-15",
        "location": "Mombasa",
        "cover_image": "https://storage.nuru.com/events/pe-002-cover.jpg",
        "rating": 5
      },
      {
        "id": "pe-003",
        "event_type": "Wedding",
        "event_name": "Grace & John's Wedding",
        "event_date": "2024-11-08",
        "location": "Nakuru",
        "cover_image": "https://storage.nuru.com/events/pe-003-cover.jpg",
        "rating": 4
      }
    ],
    "bookings": [
      {
        "id": "f50e8400-e29b-41d4-a716-446655440010",
        "event_id": "b50e8400-e29b-41d4-a716-446655440050",
        "client_name": "Peter Kimani",
        "client_avatar": "https://storage.nuru.com/avatars/peter-k.jpg",
        "event_type": "Wedding",
        "event_date": "2025-03-15",
        "package_name": "Premium Package",
        "quoted_price": 120000.0,
        "status": "confirmed",
        "created_at": "2025-01-28T10:00:00Z"
      },
      {
        "id": "f50e8400-e29b-41d4-a716-446655440011",
        "event_id": null,
        "client_name": "Mary Akinyi",
        "client_avatar": null,
        "event_type": "Wedding",
        "event_date": "2025-04-20",
        "package_name": null,
        "quoted_price": null,
        "status": "pending",
        "created_at": "2025-02-05T09:30:00Z"
      }
    ],
    "kyc_status": {
      "overall_status": "verified",
      "progress": 100,
      "requirements": [
        {
          "id": "850e8400-e29b-41d4-a716-446655440001",
          "name": "National ID / Passport",
          "status": "approved",
          "submitted_at": "2025-01-10T10:00:00Z",
          "reviewed_at": "2025-01-12T14:00:00Z"
        },
        {
          "id": "850e8400-e29b-41d4-a716-446655440003",
          "name": "Portfolio Samples",
          "status": "approved",
          "submitted_at": "2025-01-10T10:05:00Z",
          "reviewed_at": "2025-01-12T14:30:00Z"
        },
        {
          "id": "850e8400-e29b-41d4-a716-446655440005",
          "name": "Tax Compliance Certificate",
          "status": "approved",
          "submitted_at": "2025-01-10T10:10:00Z",
          "reviewed_at": "2025-01-15T09:00:00Z"
        }
      ]
    },
    "analytics": {
      "views_today": 15,
      "views_this_week": 89,
      "views_this_month": 312,
      "inquiries_this_month": 12,
      "booking_conversion_rate": 45.5,
      "average_response_time_hours": 2.3
    },
    "created_at": "2024-06-15T10:30:00Z",
    "updated_at": "2025-02-01T14:20:00Z"
  }
}
```

---

## 7.3 Create Service

Creates a new service listing.

```
POST /user-services/
Authorization: Bearer {access_token}
Content-Type: multipart/form-data
```

**Form Fields:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| title | string | Yes | Service title (max 100 chars) |
| description | string | Yes | Full description (max 5000 chars) |
| short_description | string | No | Brief description (max 200 chars) |
| service_category_id | uuid | Yes | Service category ID |
| service_type_id | uuid | Yes | Service type ID |
| min_price | number | Yes | Minimum price |
| max_price | number | No | Maximum price (if range pricing) |
| currency | string | No | Currency code (default: KES) |
| price_type | string | No | Pricing type: fixed, range, starting_from, custom |
| price_unit | string | No | Unit: per_event, per_hour, per_day, per_person |
| price_notes | string | No | Additional pricing notes (max 500 chars) |
| location | string | Yes | Primary location/city |
| full_address | string | No | Full address |
| service_areas | string | No | Comma-separated list of service areas |
| travel_fee_info | string | No | Travel fee information |
| years_experience | integer | No | Years of experience |
| team_size | integer | No | Team size |
| languages | string | No | Comma-separated languages |
| booking_lead_time_days | integer | No | Minimum days advance booking required |
| cancellation_policy | string | No | Cancellation policy description |
| insurance_info | string | No | Insurance information |
| highlights | string | No | JSON array of highlights |
| images | file[] | No | Service images (max 10, each max 10MB) |

**Success Response (201 Created):**

```json
{
  "success": true,
  "message": "Service created successfully",
  "data": {
    "id": "g50e8400-e29b-41d4-a716-446655440003",
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "title": "Professional DJ Services",
    "description": "High-energy DJ services for weddings, corporate events, and parties.",
    "service_category_id": "650e8400-e29b-41d4-a716-446655440005",
    "service_category": {
      "id": "650e8400-e29b-41d4-a716-446655440005",
      "name": "Entertainment",
      "icon": "music"
    },
    "service_type_id": "750e8400-e29b-41d4-a716-446655440020",
    "service_type": {
      "id": "750e8400-e29b-41d4-a716-446655440020",
      "name": "DJ Services",
      "category_id": "650e8400-e29b-41d4-a716-446655440005"
    },
    "min_price": 25000.0,
    "max_price": 80000.0,
    "currency": "KES",
    "price_type": "range",
    "price_unit": "per_event",
    "location": "Nairobi, Kenya",
    "service_areas": ["Nairobi", "Kiambu"],
    "status": "active",
    "verification_status": "unverified",
    "verification_progress": 0,
    "images": [
      {
        "id": "img-020",
        "url": "https://storage.nuru.com/services/g50e8400-003-img1.jpg",
        "thumbnail_url": "https://storage.nuru.com/services/g50e8400-003-img1-thumb.jpg",
        "is_primary": true,
        "display_order": 1
      }
    ],
    "rating": null,
    "review_count": 0,
    "booking_count": 0,
    "years_experience": 5,
    "created_at": "2025-02-05T20:00:00Z",
    "updated_at": "2025-02-05T20:00:00Z"
  }
}
```

---

## 7.4 Update Service

Updates an existing service.

```
PUT /user-services/{serviceId}
Authorization: Bearer {access_token}
Content-Type: multipart/form-data
```

**Form Fields:** (All optional - same fields as create)
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| title | string | No | Service title |
| description | string | No | Full description |
| min_price | number | No | Minimum price |
| max_price | number | No | Maximum price |
| location | string | No | Primary location |
| service_areas | string | No | Comma-separated service areas |
| status | string | No | Service status: active, inactive |
| images | file[] | No | New images to add |
| remove_images | string | No | JSON array of image IDs to remove |
| primary_image_id | string | No | ID of image to set as primary |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Service updated successfully",
  "data": {
    "id": "g50e8400-e29b-41d4-a716-446655440001",
    "title": "Premium Wedding Photography - Updated",
    "min_price": 55000.0,
    "max_price": 280000.0,
    "status": "active",
    "updated_at": "2025-02-05T20:30:00Z"
  }
}
```

---

## 7.5 Delete Service

Deletes a service listing.

```
DELETE /user-services/{serviceId}
Authorization: Bearer {access_token}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Service deleted successfully"
}
```

**Error Response (409 Conflict):**

```json
{
  "success": false,
  "message": "Cannot delete service with active bookings. Please cancel or complete all bookings first.",
  "data": {
    "active_bookings": 3
  }
}
```

---

## 7.6 Get Service KYC Status

Returns KYC verification status for a service.

```
GET /user-services/{serviceId}/kyc
Authorization: Bearer {access_token}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "KYC status retrieved successfully",
  "data": {
    "service_id": "g50e8400-e29b-41d4-a716-446655440002",
    "overall_status": "pending",
    "progress": 60,
    "submitted_at": "2025-02-01T10:00:00Z",
    "last_updated_at": "2025-02-03T14:30:00Z",
    "estimated_review_time_days": 3,
    "requirements": [
      {
        "id": "850e8400-e29b-41d4-a716-446655440001",
        "kyc_requirement_id": "850e8400-e29b-41d4-a716-446655440001",
        "name": "National ID / Passport",
        "description": "A valid government-issued identification document",
        "document_type": "identity",
        "is_required": true,
        "accepted_formats": ["jpg", "jpeg", "png", "pdf"],
        "max_file_size_mb": 5,
        "status": "approved",
        "document_url": "https://storage.nuru.com/kyc/g50e8400-002-id.pdf",
        "document_name": "national_id.pdf",
        "submitted_at": "2025-02-01T10:00:00Z",
        "reviewed_at": "2025-02-02T09:00:00Z",
        "reviewed_by": "Admin",
        "rejection_reason": null,
        "notes": null
      },
      {
        "id": "850e8400-e29b-41d4-a716-446655440003",
        "kyc_requirement_id": "850e8400-e29b-41d4-a716-446655440003",
        "name": "Portfolio Samples",
        "description": "At least 5 samples of your previous work",
        "document_type": "portfolio",
        "is_required": true,
        "accepted_formats": ["jpg", "jpeg", "png"],
        "max_file_size_mb": 10,
        "status": "pending",
        "document_url": "https://storage.nuru.com/kyc/g50e8400-002-portfolio.zip",
        "document_name": "portfolio_samples.zip",
        "submitted_at": "2025-02-01T10:05:00Z",
        "reviewed_at": null,
        "reviewed_by": null,
        "rejection_reason": null,
        "notes": null
      },
      {
        "id": "850e8400-e29b-41d4-a716-446655440005",
        "kyc_requirement_id": "850e8400-e29b-41d4-a716-446655440005",
        "name": "Tax Compliance Certificate",
        "description": "Valid tax compliance certificate (KRA PIN certificate)",
        "document_type": "tax",
        "is_required": true,
        "accepted_formats": ["pdf"],
        "max_file_size_mb": 5,
        "status": "not_submitted",
        "document_url": null,
        "document_name": null,
        "submitted_at": null,
        "reviewed_at": null,
        "reviewed_by": null,
        "rejection_reason": null,
        "notes": null
      },
      {
        "id": "850e8400-e29b-41d4-a716-446655440002",
        "kyc_requirement_id": "850e8400-e29b-41d4-a716-446655440002",
        "name": "Business Registration Certificate",
        "description": "Proof of business registration if operating as a company",
        "document_type": "business",
        "is_required": false,
        "accepted_formats": ["jpg", "jpeg", "png", "pdf"],
        "max_file_size_mb": 5,
        "status": "not_submitted",
        "document_url": null,
        "document_name": null,
        "submitted_at": null,
        "reviewed_at": null,
        "reviewed_by": null,
        "rejection_reason": null,
        "notes": "Optional - only required for registered businesses"
      }
    ]
  }
}
```

---

## 7.7 Upload KYC Document

Uploads a KYC document for verification.

```
POST /user-services/{serviceId}/kyc
Authorization: Bearer {access_token}
Content-Type: multipart/form-data
```

**Form Fields:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| kyc_requirement_id | uuid | Yes | KYC requirement ID |
| document | file | Yes | Document file |
| notes | string | No | Additional notes for reviewer |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Document uploaded successfully",
  "data": {
    "id": "850e8400-e29b-41d4-a716-446655440005",
    "kyc_requirement_id": "850e8400-e29b-41d4-a716-446655440005",
    "name": "Tax Compliance Certificate",
    "status": "pending",
    "document_url": "https://storage.nuru.com/kyc/g50e8400-002-tax.pdf",
    "document_name": "kra_certificate.pdf",
    "submitted_at": "2025-02-05T21:00:00Z"
  }
}
```

**Error Response (400 Bad Request):**

```json
{
  "success": false,
  "message": "Invalid document",
  "errors": [
    {
      "field": "document",
      "message": "File type not accepted. Please upload a PDF file."
    }
  ]
}
```

---

## 7.8 Delete KYC Document

Removes a submitted KYC document.

```
DELETE /user-services/{serviceId}/kyc/{kycId}
Authorization: Bearer {access_token}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Document removed successfully"
}
```

**Error Response (400 Bad Request):**

```json
{
  "success": false,
  "message": "Cannot remove approved document. Please contact support."
}
```

---

## 7.9 Resubmit KYC Document

Resubmits a rejected KYC document.

```
PUT /user-services/{serviceId}/kyc/{kycId}
Authorization: Bearer {access_token}
Content-Type: multipart/form-data
```

**Form Fields:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| document | file | Yes | New document file |
| notes | string | No | Notes addressing rejection reason |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Document resubmitted successfully",
  "data": {
    "id": "850e8400-e29b-41d4-a716-446655440003",
    "name": "Portfolio Samples",
    "status": "pending",
    "resubmit_count": 1,
    "submitted_at": "2025-02-05T21:30:00Z"
  }
}
```

---

# 📦 MODULE 8: SERVICE PACKAGES

---

## 8.1 Get Service Packages

Returns all packages for a service.

```
GET /user-services/{serviceId}/packages
Authorization: Bearer {access_token}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Packages retrieved successfully",
  "data": [
    {
      "id": "h50e8400-e29b-41d4-a716-446655440001",
      "service_id": "g50e8400-e29b-41d4-a716-446655440001",
      "name": "Essential Package",
      "description": "Perfect for intimate weddings with core coverage essentials.",
      "price": 50000.0,
      "currency": "KES",
      "compare_at_price": null,
      "duration_hours": 4,
      "photographers_count": 1,
      "features": [
        "4 hours of coverage",
        "1 professional photographer",
        "200+ edited photos",
        "Online gallery",
        "Print release"
      ],
      "deliverables": [
        "High-resolution digital images",
        "Online viewing gallery",
        "USB drive with all photos"
      ],
      "turnaround_days": 30,
      "max_revisions": 2,
      "is_popular": false,
      "is_active": true,
      "booking_count": 45,
      "display_order": 1,
      "created_at": "2024-06-15T10:30:00Z",
      "updated_at": "2024-06-15T10:30:00Z"
    },
    {
      "id": "h50e8400-e29b-41d4-a716-446655440002",
      "service_id": "g50e8400-e29b-41d4-a716-446655440001",
      "name": "Premium Package",
      "description": "Our most popular wedding package with comprehensive coverage.",
      "price": 120000.0,
      "currency": "KES",
      "compare_at_price": 150000.0,
      "duration_hours": 8,
      "photographers_count": 2,
      "features": [
        "8 hours of coverage",
        "2 professional photographers",
        "400+ edited photos",
        "Engagement session included",
        "Online gallery",
        "Print release",
        "Same-day preview (20 photos)"
      ],
      "deliverables": [
        "High-resolution digital images",
        "Online viewing gallery",
        "USB drive in premium box",
        "20x30 canvas print"
      ],
      "turnaround_days": 21,
      "max_revisions": 3,
      "is_popular": true,
      "is_active": true,
      "booking_count": 156,
      "display_order": 2,
      "created_at": "2024-06-15T10:30:00Z",
      "updated_at": "2025-01-15T09:00:00Z"
    },
    {
      "id": "h50e8400-e29b-41d4-a716-446655440003",
      "service_id": "g50e8400-e29b-41d4-a716-446655440001",
      "name": "Platinum Package",
      "description": "The ultimate wedding photography experience with all premium features.",
      "price": 250000.0,
      "currency": "KES",
      "compare_at_price": null,
      "duration_hours": 12,
      "photographers_count": 3,
      "features": [
        "Full day coverage (12 hours)",
        "3 professional photographers",
        "800+ edited photos",
        "Engagement session included",
        "Bridal/Groom preparation coverage",
        "Drone aerial photography",
        "Online gallery",
        "Print release",
        "Same-day slideshow at reception"
      ],
      "deliverables": [
        "High-resolution digital images",
        "Online viewing gallery",
        "Premium USB drive in wooden box",
        "30x40 canvas print",
        "Premium photo album (40 pages)",
        "Parent albums (2x 20 pages)"
      ],
      "turnaround_days": 14,
      "max_revisions": 5,
      "is_popular": false,
      "is_active": true,
      "booking_count": 33,
      "display_order": 3,
      "created_at": "2024-06-15T10:30:00Z",
      "updated_at": "2025-01-20T14:00:00Z"
    }
  ]
}
```

---

## 8.2 Create Package

Creates a new service package.

```
POST /user-services/{serviceId}/packages
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:**

```json
{
  "name": "Budget Package",
  "description": "Affordable option for small events and gatherings.",
  "price": 30000.0,
  "compare_at_price": 40000.0,
  "duration_hours": 2,
  "photographers_count": 1,
  "features": [
    "2 hours of coverage",
    "1 photographer",
    "100+ edited photos",
    "Digital delivery"
  ],
  "deliverables": ["High-resolution digital images", "Online gallery link"],
  "turnaround_days": 45,
  "max_revisions": 1,
  "is_popular": false,
  "is_active": true,
  "display_order": 0
}
```

| Field               | Type          | Required | Description                          |
| ------------------- | ------------- | -------- | ------------------------------------ |
| name                | string        | Yes      | Package name (max 50 chars)          |
| description         | string        | No       | Package description (max 500 chars)  |
| price               | number        | Yes      | Package price (positive number)      |
| compare_at_price    | number        | No       | Original/compare price for discounts |
| duration_hours      | number        | No       | Service duration in hours            |
| photographers_count | number        | No       | Number of photographers/staff        |
| features            | array[string] | Yes      | List of included features (min 1)    |
| deliverables        | array[string] | No       | List of deliverables                 |
| turnaround_days     | integer       | No       | Delivery time in days                |
| max_revisions       | integer       | No       | Number of included revisions         |
| is_popular          | boolean       | No       | Mark as popular/recommended          |
| is_active           | boolean       | No       | Package availability (default: true) |
| display_order       | integer       | No       | Display order (lower = first)        |

**Success Response (201 Created):**

```json
{
  "success": true,
  "message": "Package created successfully",
  "data": {
    "id": "h50e8400-e29b-41d4-a716-446655440004",
    "service_id": "g50e8400-e29b-41d4-a716-446655440001",
    "name": "Budget Package",
    "description": "Affordable option for small events and gatherings.",
    "price": 30000.0,
    "compare_at_price": 40000.0,
    "features": [
      "2 hours of coverage",
      "1 photographer",
      "100+ edited photos",
      "Digital delivery"
    ],
    "is_active": true,
    "display_order": 0,
    "created_at": "2025-02-05T22:00:00Z"
  }
}
```

---

## 8.3 Update Package

Updates an existing package.

```
PUT /user-services/{serviceId}/packages/{packageId}
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:** (All fields optional)

```json
{
  "name": "Budget Package - Updated",
  "price": 35000.0,
  "is_popular": true
}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Package updated successfully",
  "data": {
    "id": "h50e8400-e29b-41d4-a716-446655440004",
    "name": "Budget Package - Updated",
    "price": 35000.0,
    "is_popular": true,
    "updated_at": "2025-02-05T22:30:00Z"
  }
}
```

---

## 8.4 Delete Package

Deletes a service package.

```
DELETE /user-services/{serviceId}/packages/{packageId}
Authorization: Bearer {access_token}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Package deleted successfully"
}
```

**Error Response (409 Conflict):**

```json
{
  "success": false,
  "message": "Cannot delete package with active bookings"
}
```

---

## 8.5 Reorder Packages

Updates the display order of packages.

```
PUT /user-services/{serviceId}/packages/reorder
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:**

```json
{
  "order": [
    {
      "package_id": "h50e8400-e29b-41d4-a716-446655440004",
      "display_order": 1
    },
    {
      "package_id": "h50e8400-e29b-41d4-a716-446655440001",
      "display_order": 2
    },
    {
      "package_id": "h50e8400-e29b-41d4-a716-446655440002",
      "display_order": 3
    },
    {
      "package_id": "h50e8400-e29b-41d4-a716-446655440003",
      "display_order": 4
    }
  ]
}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Packages reordered successfully"
}
```

---

# 🔍 MODULE 9: PUBLIC SERVICES DISCOVERY

---

## 9.1 Search Services

Searches and filters public service listings.

```
GET /services
Authentication: Optional (provides personalization if authenticated)
```

**Query Parameters:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| page | integer | No | 1 | Page number |
| limit | integer | No | 20 | Items per page (max 50) |
| q | string | No | null | Search query (searches title, description) |
| category_id | uuid | No | null | Filter by category |
| type_id | uuid | No | null | Filter by service type |
| location | string | No | null | Filter by location |
| min_price | number | No | null | Minimum price filter |
| max_price | number | No | null | Maximum price filter |
| min_rating | number | No | null | Minimum rating (1-5) |
| verified | boolean | No | null | Only verified services |
| available | boolean | No | null | Only currently available |
| event_type_id | uuid | No | null | Services suitable for event type |
| sort_by | string | No | relevance | Sort: relevance, price_low, price_high, rating, reviews, newest |
| lat | number | No | null | Latitude for distance sorting |
| lng | number | No | null | Longitude for distance sorting |
| radius_km | number | No | 50 | Search radius in kilometers |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Services retrieved successfully",
  "data": {
    "services": [
      {
        "id": "g50e8400-e29b-41d4-a716-446655440001",
        "title": "Premium Wedding Photography",
        "short_description": "Professional wedding photography with 10+ years of experience",
        "provider": {
          "id": "550e8400-e29b-41d4-a716-446655440000",
          "name": "David Mwangi",
          "avatar": "https://storage.nuru.com/avatars/david.jpg",
          "verified": true,
          "response_time": "Usually responds within 2 hours"
        },
        "service_category": {
          "id": "650e8400-e29b-41d4-a716-446655440001",
          "name": "Photography & Videography",
          "icon": "camera"
        },
        "service_type": {
          "id": "750e8400-e29b-41d4-a716-446655440001",
          "name": "Wedding Photography"
        },
        "min_price": 50000.0,
        "max_price": 250000.0,
        "currency": "KES",
        "price_display": "KES 50,000 - 250,000",
        "location": "Nairobi, Kenya",
        "distance_km": null,
        "primary_image": {
          "url": "https://storage.nuru.com/services/g50e8400-img1.jpg",
          "thumbnail_url": "https://storage.nuru.com/services/g50e8400-img1-thumb.jpg",
          "alt": "Wedding couple portrait"
        },
        "images_count": 5,
        "rating": 4.9,
        "review_count": 156,
        "verified": true,
        "verification_badge": "gold",
        "featured": true,
        "availability": "available",
        "years_experience": 10,
        "completed_events": 198,
        "tags": ["Award-winning", "Same-day preview", "Drone coverage"],
        "created_at": "2024-06-15T10:30:00Z"
      },
      {
        "id": "g50e8400-e29b-41d4-a716-446655440010",
        "title": "Creative Event Photography",
        "short_description": "Capturing moments that tell your story",
        "provider": {
          "id": "550e8400-e29b-41d4-a716-446655440040",
          "name": "Jane Kamau",
          "avatar": "https://storage.nuru.com/avatars/jane-k.jpg",
          "verified": true,
          "response_time": "Usually responds within 4 hours"
        },
        "service_category": {
          "id": "650e8400-e29b-41d4-a716-446655440001",
          "name": "Photography & Videography",
          "icon": "camera"
        },
        "service_type": {
          "id": "750e8400-e29b-41d4-a716-446655440002",
          "name": "Event Photography"
        },
        "min_price": 25000.0,
        "max_price": 100000.0,
        "currency": "KES",
        "price_display": "KES 25,000 - 100,000",
        "location": "Nairobi, Kenya",
        "distance_km": null,
        "primary_image": {
          "url": "https://storage.nuru.com/services/g50e8400-010-img1.jpg",
          "thumbnail_url": "https://storage.nuru.com/services/g50e8400-010-img1-thumb.jpg",
          "alt": "Event photography"
        },
        "images_count": 8,
        "rating": 4.7,
        "review_count": 89,
        "verified": true,
        "verification_badge": "silver",
        "featured": false,
        "availability": "available",
        "years_experience": 5,
        "completed_events": 120,
        "tags": ["Corporate events", "Birthdays", "Fast delivery"],
        "created_at": "2024-08-20T14:00:00Z"
      },
      {
        "id": "g50e8400-e29b-41d4-a716-446655440020",
        "title": "Budget-Friendly Photography",
        "short_description": "Quality photography at affordable prices",
        "provider": {
          "id": "550e8400-e29b-41d4-a716-446655440050",
          "name": "Peter Ochieng",
          "avatar": null,
          "verified": false,
          "response_time": "Usually responds within 24 hours"
        },
        "service_category": {
          "id": "650e8400-e29b-41d4-a716-446655440001",
          "name": "Photography & Videography",
          "icon": "camera"
        },
        "service_type": {
          "id": "750e8400-e29b-41d4-a716-446655440002",
          "name": "Event Photography"
        },
        "min_price": 10000.0,
        "max_price": 40000.0,
        "currency": "KES",
        "price_display": "From KES 10,000",
        "location": "Nakuru, Kenya",
        "distance_km": null,
        "primary_image": {
          "url": "https://storage.nuru.com/services/g50e8400-020-img1.jpg",
          "thumbnail_url": "https://storage.nuru.com/services/g50e8400-020-img1-thumb.jpg",
          "alt": "Photography sample"
        },
        "images_count": 3,
        "rating": 4.2,
        "review_count": 15,
        "verified": false,
        "verification_badge": null,
        "featured": false,
        "availability": "available",
        "years_experience": 2,
        "completed_events": 25,
        "tags": ["Affordable", "Quick turnaround"],
        "created_at": "2024-11-10T09:00:00Z"
      }
    ],
    "filters": {
      "categories": [
        {
          "id": "650e8400-e29b-41d4-a716-446655440001",
          "name": "Photography & Videography",
          "count": 245
        },
        {
          "id": "650e8400-e29b-41d4-a716-446655440002",
          "name": "Catering & Food",
          "count": 189
        }
      ],
      "locations": [
        {
          "name": "Nairobi",
          "count": 456
        },
        {
          "name": "Mombasa",
          "count": 123
        },
        {
          "name": "Nakuru",
          "count": 67
        }
      ],
      "price_range": {
        "min": 5000,
        "max": 500000,
        "currency": "KES"
      }
    },
    "pagination": {
      "page": 1,
      "limit": 20,
      "total_items": 245,
      "total_pages": 13,
      "has_next": true,
      "has_previous": false
    }
  }
}
```

---

## 9.1.1 Event Service Recommendations

Returns service providers recommended for a specific event type. This is a convenience use of the Search Services endpoint (`GET /services`) with event-specific filters pre-applied.

**Usage Pattern:**

```
GET /services?event_type_id={eventTypeId}&sort_by=rating&limit=6&available=true
GET /services?event_type_id={eventTypeId}&location={location}&max_price={budget}&sort_by=rating&limit=6&available=true
Authentication: Optional (provides personalization if authenticated)
```

**Purpose:**
Used during event creation to suggest top-rated, available service providers that are suitable for the selected event type (e.g., wedding photographers, birthday caterers). Optionally filters by the event's location and budget.

**Query Parameters (recommended combination):**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| event_type_id | uuid | Yes | The selected event type ID to match suitable services |
| sort_by | string | No | Use `rating` to surface top-rated providers first |
| limit | integer | No | Use `6` for a compact recommendations grid |
| available | boolean | No | Use `true` to only show currently available providers |
| location | string | No | Event location to find nearby providers |
| max_price | number | No | Event budget to filter affordable providers |

**Response:** Same as 9.1 Search Services response format.

**Example Request:**

```
GET /services?event_type_id=abc123&sort_by=rating&limit=6&available=true&location=Nairobi&max_price=500000
```

**Frontend Integration:**
The Create Event page includes a "Service Recommendations" section that calls this endpoint when the user clicks "Get Recommendations". Results are displayed as service cards with provider info, ratings, pricing, and a link to view full details.

---

---

# 🪪 MODULE 21: IDENTITY VERIFICATION

---

## 21.1 Submit Identity Verification

Submit documents for identity verification.

```
POST /users/verify-identity
Content-Type: multipart/form-data
Authorization: Bearer {access_token}
```

**Form Fields:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id_front | file | Yes | Front side of government-issued ID (jpg, png, pdf) |
| id_back | file | No | Back side of ID document |
| selfie | file | No | Clear selfie photo for face matching |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Verification documents submitted successfully",
  "data": {
    "status": "submitted",
    "submitted_at": "2025-02-05T14:30:00Z"
  }
}
```

**Error Response (400 Bad Request):**

```json
{
  "success": false,
  "message": "ID front document is required"
}
```

---

## 21.2 Get Verification Status

Returns the current identity verification status.

```
GET /users/verify-identity/status
Authorization: Bearer {access_token}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Verification status retrieved",
  "data": {
    "status": "verified",
    "submitted_at": "2025-02-05T14:30:00Z",
    "verified_at": "2025-02-07T10:15:00Z",
    "rejection_reason": null
  }
}
```

**Possible status values:** `not_submitted`, `submitted`, `verified`, `rejected`

---

Returns detailed information about a public service.

```
GET /services/{serviceId}
Authentication: Optional (tracks view if authenticated)
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Service retrieved successfully",
  "data": {
    "id": "g50e8400-e29b-41d4-a716-446655440001",
    "title": "Premium Wedding Photography",
    "description": "Capturing your special moments with artistic excellence. Over 10 years of experience in wedding photography across East Africa. We specialize in candid, documentary-style photography that tells your unique love story.\n\nOur team of 4 professional photographers ensures comprehensive coverage of your entire wedding day, from pre-ceremony preparations to the last dance.",
    "short_description": "Professional wedding photography with 10+ years of experience",
    "provider": {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "name": "David Mwangi",
      "username": "davidmwangi",
      "avatar": "https://storage.nuru.com/avatars/david.jpg",
      "bio": "Award-winning photographer passionate about capturing love stories",
      "location": "Nairobi, Kenya",
      "verified": true,
      "member_since": "2024-06-15",
      "total_services": 2,
      "total_reviews": 179,
      "average_rating": 4.85,
      "response_rate": 98.5,
      "response_time": "Usually responds within 2 hours"
    },
    "service_category": {
      "id": "650e8400-e29b-41d4-a716-446655440001",
      "name": "Photography & Videography",
      "icon": "camera"
    },
    "service_type": {
      "id": "750e8400-e29b-41d4-a716-446655440001",
      "name": "Wedding Photography"
    },
    "min_price": 50000.0,
    "max_price": 250000.0,
    "currency": "KES",
    "price_display": "KES 50,000 - 250,000",
    "price_type": "range",
    "price_unit": "per_event",
    "price_notes": "Prices vary based on coverage duration and package selected",
    "location": "Nairobi, Kenya",
    "service_areas": [
      "Nairobi",
      "Mombasa",
      "Nakuru",
      "Kisumu",
      "Naivasha",
      "Nanyuki"
    ],
    "travel_fee_info": "Travel fee applies for locations outside Nairobi (KES 5,000 - 15,000)",
    "images": [
      {
        "id": "img-001",
        "url": "https://storage.nuru.com/services/g50e8400-img1.jpg",
        "thumbnail_url": "https://storage.nuru.com/services/g50e8400-img1-thumb.jpg",
        "medium_url": "https://storage.nuru.com/services/g50e8400-img1-medium.jpg",
        "alt": "Wedding couple portrait",
        "caption": "Romantic sunset portrait session",
        "is_primary": true
      },
      {
        "id": "img-002",
        "url": "https://storage.nuru.com/services/g50e8400-img2.jpg",
        "thumbnail_url": "https://storage.nuru.com/services/g50e8400-img2-thumb.jpg",
        "medium_url": "https://storage.nuru.com/services/g50e8400-img2-medium.jpg",
        "alt": "Wedding ceremony shot",
        "caption": "Emotional ceremony moments",
        "is_primary": false
      },
      {
        "id": "img-003",
        "url": "https://storage.nuru.com/services/g50e8400-img3.jpg",
        "thumbnail_url": "https://storage.nuru.com/services/g50e8400-img3-thumb.jpg",
        "medium_url": "https://storage.nuru.com/services/g50e8400-img3-medium.jpg",
        "alt": "Reception photography",
        "caption": "Vibrant reception celebrations",
        "is_primary": false
      },
      {
        "id": "img-004",
        "url": "https://storage.nuru.com/services/g50e8400-img4.jpg",
        "thumbnail_url": "https://storage.nuru.com/services/g50e8400-img4-thumb.jpg",
        "medium_url": "https://storage.nuru.com/services/g50e8400-img4-medium.jpg",
        "alt": "Bridal preparation",
        "caption": "Getting ready moments",
        "is_primary": false
      },
      {
        "id": "img-005",
        "url": "https://storage.nuru.com/services/g50e8400-img5.jpg",
        "thumbnail_url": "https://storage.nuru.com/services/g50e8400-img5-thumb.jpg",
        "medium_url": "https://storage.nuru.com/services/g50e8400-img5-medium.jpg",
        "alt": "Wedding details",
        "caption": "Beautiful wedding details",
        "is_primary": false
      }
    ],
    "video_urls": [
      {
        "id": "vid-001",
        "url": "https://youtube.com/watch?v=xyz123",
        "thumbnail_url": "https://img.youtube.com/vi/xyz123/hqdefault.jpg",
        "title": "Wedding Highlight Reel",
        "duration_seconds": 180
      }
    ],
    "rating": 4.9,
    "rating_breakdown": {
      "5_star": 145,
      "4_star": 8,
      "3_star": 2,
      "2_star": 1,
      "1_star": 0
    },
    "review_count": 156,
    "verified": true,
    "verification_badge": "gold",
    "years_experience": 10,
    "team_size": 4,
    "languages": ["English", "Swahili"],
    "availability": "available",
    "next_available_date": "2025-02-20",
    "booking_lead_time_days": 14,
    "cancellation_policy": "Full refund up to 30 days before event. 50% refund up to 14 days before. No refund within 14 days.",
    "highlights": [
      "Award-winning photographer",
      "10+ years experience",
      "Same-day photo preview",
      "Drone coverage included in premium packages"
    ],
    "faqs": [
      {
        "question": "How many photos will we receive?",
        "answer": "You'll receive 400-800 professionally edited photos depending on your package."
      },
      {
        "question": "How long until we get our photos?",
        "answer": "Preview within 48 hours, full gallery within 4-6 weeks."
      },
      {
        "question": "Do you travel for destination weddings?",
        "answer": "Yes! We love destination weddings. Travel costs are quoted separately."
      }
    ],
    "packages": [
      {
        "id": "h50e8400-e29b-41d4-a716-446655440001",
        "name": "Essential Package",
        "description": "Perfect for intimate weddings",
        "price": 50000.0,
        "currency": "KES",
        "duration_hours": 4,
        "features": [
          "4 hours of coverage",
          "1 professional photographer",
          "200+ edited photos",
          "Online gallery",
          "Print release"
        ],
        "is_popular": false
      },
      {
        "id": "h50e8400-e29b-41d4-a716-446655440002",
        "name": "Premium Package",
        "description": "Our most popular wedding package",
        "price": 120000.0,
        "currency": "KES",
        "compare_at_price": 150000.0,
        "duration_hours": 8,
        "features": [
          "8 hours of coverage",
          "2 professional photographers",
          "400+ edited photos",
          "Engagement session included",
          "Online gallery",
          "Print release",
          "Same-day preview (20 photos)"
        ],
        "is_popular": true
      },
      {
        "id": "h50e8400-e29b-41d4-a716-446655440003",
        "name": "Platinum Package",
        "description": "The ultimate wedding photography experience",
        "price": 250000.0,
        "currency": "KES",
        "duration_hours": 12,
        "features": [
          "Full day coverage (12 hours)",
          "3 professional photographers",
          "800+ edited photos",
          "Engagement session included",
          "Drone aerial photography",
          "Same-day slideshow at reception"
        ],
        "is_popular": false
      }
    ],
    "reviews_preview": [
      {
        "id": "r50e8400-e29b-41d4-a716-446655440001",
        "user_name": "Jane Wanjiku",
        "user_avatar": "https://storage.nuru.com/avatars/jane-w.jpg",
        "rating": 5,
        "title": "Absolutely amazing!",
        "comment": "David and his team exceeded all our expectations. The photos are stunning!",
        "event_type": "Wedding",
        "verified_booking": true,
        "created_at": "2025-01-22T14:30:00Z"
      },
      {
        "id": "r50e8400-e29b-41d4-a716-446655440002",
        "user_name": "Michael Omondi",
        "user_avatar": "https://storage.nuru.com/avatars/michael-o.jpg",
        "rating": 5,
        "title": "Professional and creative",
        "comment": "We loved working with this team. They were professional and creative!",
        "event_type": "Wedding",
        "verified_booking": true,
        "created_at": "2024-12-20T09:15:00Z"
      },
      {
        "id": "r50e8400-e29b-41d4-a716-446655440003",
        "user_name": "Grace Muthoni",
        "user_avatar": null,
        "rating": 4,
        "title": "Great photos, slight delay",
        "comment": "The photos are beautiful. Only giving 4 stars because delivery took a bit longer.",
        "event_type": "Wedding",
        "verified_booking": true,
        "created_at": "2024-11-15T16:45:00Z"
      }
    ],
    "similar_services": [
      {
        "id": "g50e8400-e29b-41d4-a716-446655440010",
        "title": "Creative Event Photography",
        "provider_name": "Jane Kamau",
        "min_price": 25000.0,
        "rating": 4.7,
        "review_count": 89,
        "primary_image": "https://storage.nuru.com/services/g50e8400-010-img1-thumb.jpg"
      },
      {
        "id": "g50e8400-e29b-41d4-a716-446655440011",
        "title": "Cinematic Wedding Films",
        "provider_name": "FilmCraft Studios",
        "min_price": 80000.0,
        "rating": 4.8,
        "review_count": 67,
        "primary_image": "https://storage.nuru.com/services/g50e8400-011-img1-thumb.jpg"
      }
    ],
    "is_saved": false,
    "view_count": 1250,
    "created_at": "2024-06-15T10:30:00Z",
    "updated_at": "2025-02-01T14:20:00Z"
  }
}
```

---

## 9.3 Get Service Reviews

Returns reviews for a service with pagination.

```
GET /services/{serviceId}/reviews
Authentication: None
```

**Query Parameters:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| page | integer | No | 1 | Page number |
| limit | integer | No | 10 | Items per page (max 50) |
| rating | integer | No | null | Filter by rating (1-5) |
| sort_by | string | No | newest | Sort: newest, oldest, highest, lowest, helpful |
| with_photos | boolean | No | null | Only reviews with photos |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Reviews retrieved successfully",
  "data": {
    "reviews": [
      {
        "id": "r50e8400-e29b-41d4-a716-446655440001",
        "service_id": "g50e8400-e29b-41d4-a716-446655440001",
        "user_id": "550e8400-e29b-41d4-a716-446655440030",
        "user_name": "Jane Wanjiku",
        "user_avatar": "https://storage.nuru.com/avatars/jane-w.jpg",
        "rating": 5,
        "title": "Absolutely amazing!",
        "comment": "David and his team exceeded all our expectations. The photos are stunning and captured every special moment of our wedding day. From the pre-wedding consultation to the final delivery, everything was handled professionally. The same-day preview was a wonderful surprise for our guests. Highly recommend!",
        "event_type": "Wedding",
        "event_date": "2025-01-20",
        "package_used": "Premium Package",
        "photos": [
          {
            "url": "https://storage.nuru.com/reviews/r50e8400-001-1.jpg",
            "thumbnail_url": "https://storage.nuru.com/reviews/r50e8400-001-1-thumb.jpg"
          },
          {
            "url": "https://storage.nuru.com/reviews/r50e8400-001-2.jpg",
            "thumbnail_url": "https://storage.nuru.com/reviews/r50e8400-001-2-thumb.jpg"
          }
        ],
        "vendor_response": {
          "content": "Thank you so much, Jane! It was an honor to be part of your special day. Wishing you and Peter a lifetime of happiness!",
          "responded_at": "2025-01-25T10:00:00Z"
        },
        "helpful_count": 12,
        "not_helpful_count": 0,
        "user_marked_helpful": null,
        "verified_booking": true,
        "created_at": "2025-01-22T14:30:00Z"
      },
      {
        "id": "r50e8400-e29b-41d4-a716-446655440002",
        "service_id": "g50e8400-e29b-41d4-a716-446655440001",
        "user_id": "550e8400-e29b-41d4-a716-446655440031",
        "user_name": "Michael Omondi",
        "user_avatar": "https://storage.nuru.com/avatars/michael-o.jpg",
        "rating": 5,
        "title": "Professional and creative",
        "comment": "We loved working with this team. They were professional, creative, and made us feel so comfortable in front of the camera. The photos are works of art! Communication was excellent throughout the process.",
        "event_type": "Wedding",
        "event_date": "2024-12-15",
        "package_used": "Platinum Package",
        "photos": [],
        "vendor_response": null,
        "helpful_count": 8,
        "not_helpful_count": 1,
        "user_marked_helpful": null,
        "verified_booking": true,
        "created_at": "2024-12-20T09:15:00Z"
      },
      {
        "id": "r50e8400-e29b-41d4-a716-446655440003",
        "service_id": "g50e8400-e29b-41d4-a716-446655440001",
        "user_id": "550e8400-e29b-41d4-a716-446655440032",
        "user_name": "Grace Muthoni",
        "user_avatar": null,
        "rating": 4,
        "title": "Great photos, slight delay",
        "comment": "The photos are beautiful and exactly what we wanted. Only giving 4 stars because delivery took about 2 weeks longer than promised. However, when we received them, the quality definitely made up for the wait.",
        "event_type": "Wedding",
        "event_date": "2024-11-08",
        "package_used": "Premium Package",
        "photos": [],
        "vendor_response": {
          "content": "Thank you for your feedback, Grace. We apologize for the delay - we had an unusually busy season. We've since hired additional editors to prevent this. We're glad you love the photos!",
          "responded_at": "2024-11-20T11:30:00Z"
        },
        "helpful_count": 5,
        "not_helpful_count": 0,
        "user_marked_helpful": null,
        "verified_booking": true,
        "created_at": "2024-11-15T16:45:00Z"
      }
    ],
    "summary": {
      "total_reviews": 156,
      "average_rating": 4.9,
      "rating_breakdown": {
        "5_star": {
          "count": 145,
          "percentage": 93
        },
        "4_star": {
          "count": 8,
          "percentage": 5
        },
        "3_star": {
          "count": 2,
          "percentage": 1
        },
        "2_star": {
          "count": 1,
          "percentage": 1
        },
        "1_star": {
          "count": 0,
          "percentage": 0
        }
      },
      "reviews_with_photos": 34,
      "verified_reviews": 156
    },
    "pagination": {
      "page": 1,
      "limit": 10,
      "total_items": 156,
      "total_pages": 16,
      "has_next": true,
      "has_previous": false
    }
  }
}
```

---

## 9.4 Submit Review

Submits a review for a service.

```
POST /services/{serviceId}/reviews
Authorization: Bearer {access_token}
Content-Type: multipart/form-data
```

**Form Fields:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| rating | integer | Yes | Rating from 1 to 5 |
| title | string | Yes | Review title (max 100 chars) |
| comment | string | Yes | Review content (max 2000 chars) |
| event_id | uuid | No | Link to booked event |
| booking_id | uuid | No | Link to service booking |
| event_type | string | No | Type of event (if not linked) |
| event_date | date | No | Date of event |
| photos | file[] | No | Review photos (max 5, each max 5MB) |

**Success Response (201 Created):**

```json
{
  "success": true,
  "message": "Review submitted successfully",
  "data": {
    "id": "r50e8400-e29b-41d4-a716-446655440010",
    "service_id": "g50e8400-e29b-41d4-a716-446655440001",
    "user_id": "550e8400-e29b-41d4-a716-446655440033",
    "user_name": "Sarah Njeri",
    "rating": 5,
    "title": "Exceeded expectations!",
    "comment": "Amazing service from start to finish.",
    "event_type": "Wedding",
    "event_date": "2025-02-01",
    "photos": [
      {
        "url": "https://storage.nuru.com/reviews/r50e8400-010-1.jpg",
        "thumbnail_url": "https://storage.nuru.com/reviews/r50e8400-010-1-thumb.jpg"
      }
    ],
    "verified_booking": true,
    "created_at": "2025-02-05T23:00:00Z"
  }
}
```

**Error Response (400 Bad Request):**

```json
{
  "success": false,
  "message": "Cannot submit review",
  "errors": [
    {
      "field": "general",
      "message": "You must have a completed booking with this service to leave a review"
    }
  ]
}
```

---

## 9.5 Mark Review Helpful

Marks a review as helpful or not helpful.

```
POST /services/{serviceId}/reviews/{reviewId}/helpful
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:**

```json
{
  "helpful": true
}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Thank you for your feedback",
  "data": {
    "review_id": "r50e8400-e29b-41d4-a716-446655440001",
    "helpful_count": 13,
    "not_helpful_count": 0
  }
}
```

---

## 9.6 Save/Unsave Service

Saves or removes a service from user's saved list.

```
POST /services/{serviceId}/save
Authorization: Bearer {access_token}
```

**Success Response (200 OK) - Saved:**

```json
{
  "success": true,
  "message": "Service saved",
  "data": {
    "service_id": "g50e8400-e29b-41d4-a716-446655440001",
    "is_saved": true
  }
}
```

**Success Response (200 OK) - Unsaved:**

```json
{
  "success": true,
  "message": "Service removed from saved",
  "data": {
    "service_id": "g50e8400-e29b-41d4-a716-446655440001",
    "is_saved": false
  }
}
```

---

## 9.7 Get Saved Services

Returns user's saved services.

```
GET /services/saved
Authorization: Bearer {access_token}
```

**Query Parameters:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| page | integer | No | 1 | Page number |
| limit | integer | No | 20 | Items per page |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Saved services retrieved",
  "data": {
    "services": [
      {
        "id": "g50e8400-e29b-41d4-a716-446655440001",
        "title": "Premium Wedding Photography",
        "provider_name": "David Mwangi",
        "min_price": 50000.0,
        "max_price": 250000.0,
        "currency": "KES",
        "rating": 4.9,
        "review_count": 156,
        "primary_image": "https://storage.nuru.com/services/g50e8400-img1-thumb.jpg",
        "saved_at": "2025-02-01T10:00:00Z"
      },
      {
        "id": "g50e8400-e29b-41d4-a716-446655440015",
        "title": "Elegant Catering Services",
        "provider_name": "Taste of Africa",
        "min_price": 100000.0,
        "max_price": 500000.0,
        "currency": "KES",
        "rating": 4.7,
        "review_count": 89,
        "primary_image": "https://storage.nuru.com/services/g50e8400-015-img1-thumb.jpg",
        "saved_at": "2025-01-28T14:30:00Z"
      }
    ],
    "pagination": {
      "page": 1,
      "limit": 20,
      "total_items": 2,
      "total_pages": 1,
      "has_next": false,
      "has_previous": false
    }
  }
}
```

---

# 📅 MODULE 10: SERVICE BOOKINGS

---

## 10.1 Request Service Booking

Requests a booking from a service provider.

```
POST /services/{serviceId}/book
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:**

```json
{
  "event_id": "b50e8400-e29b-41d4-a716-446655440001",
  "package_id": "h50e8400-e29b-41d4-a716-446655440002",
  "event_date": "2025-06-15",
  "event_type": "Wedding",
  "event_name": "John & Jane's Wedding",
  "location": "Naivasha, Kenya",
  "venue": "The Great Rift Valley Lodge",
  "start_time": "14:00",
  "end_time": "23:00",
  "guest_count": 150,
  "message": "Hi David, we love your work and would like to book you for our wedding. We're particularly interested in the Premium Package with the engagement session. Please let us know your availability.",
  "special_requirements": "We would like drone coverage for outdoor shots",
  "budget": 150000.0,
  "flexible_date": false,
  "alternate_dates": []
}
```

| Field                | Type        | Required | Description                              |
| -------------------- | ----------- | -------- | ---------------------------------------- |
| event_id             | uuid        | No       | Link to existing event                   |
| package_id           | uuid        | No       | Selected package ID                      |
| event_date           | date        | Yes      | Date of the event                        |
| event_type           | string      | Yes      | Type of event                            |
| event_name           | string      | No       | Name of the event                        |
| location             | string      | Yes      | Event location                           |
| venue                | string      | No       | Venue name                               |
| start_time           | string      | No       | Event start time (HH:MM)                 |
| end_time             | string      | No       | Event end time (HH:MM)                   |
| guest_count          | integer     | No       | Expected number of guests                |
| message              | string      | Yes      | Message to the provider (max 1000 chars) |
| special_requirements | string      | No       | Special requirements (max 500 chars)     |
| budget               | number      | No       | Budget amount                            |
| flexible_date        | boolean     | No       | Whether date is flexible                 |
| alternate_dates      | array[date] | No       | Alternative dates if flexible            |

**Success Response (201 Created):**

```json
{
  "success": true,
  "message": "Booking request sent successfully",
  "data": {
    "id": "f50e8400-e29b-41d4-a716-446655440020",
    "service_id": "g50e8400-e29b-41d4-a716-446655440001",
    "service": {
      "title": "Premium Wedding Photography",
      "provider_name": "David Mwangi"
    },
    "client_id": "550e8400-e29b-41d4-a716-446655440000",
    "event_id": "b50e8400-e29b-41d4-a716-446655440001",
    "package_id": "h50e8400-e29b-41d4-a716-446655440002",
    "package_name": "Premium Package",
    "event_date": "2025-06-15",
    "event_type": "Wedding",
    "event_name": "John & Jane's Wedding",
    "location": "Naivasha, Kenya",
    "venue": "The Great Rift Valley Lodge",
    "message": "Hi David, we love your work...",
    "status": "pending",
    "quoted_price": null,
    "conversation_id": "conv-001-002",
    "created_at": "2025-02-05T23:30:00Z"
  }
}
```

---

## 10.2 Get My Booking Requests (as Client)

Returns booking requests sent by the authenticated user.

```
GET /bookings/sent
Authorization: Bearer {access_token}
```

**Query Parameters:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| page | integer | No | 1 | Page number |
| limit | integer | No | 20 | Items per page |
| status | string | No | all | Filter: pending, accepted, rejected, cancelled, completed, all |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Booking requests retrieved",
  "data": {
    "bookings": [
      {
        "id": "f50e8400-e29b-41d4-a716-446655440020",
        "service": {
          "id": "g50e8400-e29b-41d4-a716-446655440001",
          "title": "Premium Wedding Photography",
          "primary_image": "https://storage.nuru.com/services/g50e8400-img1-thumb.jpg"
        },
        "provider": {
          "id": "550e8400-e29b-41d4-a716-446655440000",
          "name": "David Mwangi",
          "avatar": "https://storage.nuru.com/avatars/david.jpg"
        },
        "event_id": "b50e8400-e29b-41d4-a716-446655440001",
        "event_name": "John & Jane's Wedding",
        "package_name": "Premium Package",
        "event_date": "2025-06-15",
        "location": "Naivasha, Kenya",
        "status": "pending",
        "quoted_price": null,
        "currency": "KES",
        "provider_message": null,
        "conversation_id": "conv-001-002",
        "unread_messages": 0,
        "created_at": "2025-02-05T23:30:00Z",
        "updated_at": "2025-02-05T23:30:00Z"
      },
      {
        "id": "f50e8400-e29b-41d4-a716-446655440015",
        "service": {
          "id": "g50e8400-e29b-41d4-a716-446655440015",
          "title": "Elegant Catering Services",
          "primary_image": "https://storage.nuru.com/services/g50e8400-015-img1-thumb.jpg"
        },
        "provider": {
          "id": "550e8400-e29b-41d4-a716-446655440060",
          "name": "Taste of Africa",
          "avatar": "https://storage.nuru.com/avatars/taste-africa.jpg"
        },
        "event_id": "b50e8400-e29b-41d4-a716-446655440001",
        "event_name": "John & Jane's Wedding",
        "package_name": null,
        "event_date": "2025-06-15",
        "location": "Naivasha, Kenya",
        "status": "accepted",
        "quoted_price": 200000.0,
        "currency": "KES",
        "provider_message": "We'd be delighted to cater your wedding! Here's our quote for 150 guests.",
        "conversation_id": "conv-001-060",
        "unread_messages": 2,
        "created_at": "2025-02-03T11:00:00Z",
        "updated_at": "2025-02-04T09:30:00Z"
      }
    ],
    "summary": {
      "total": 5,
      "pending": 2,
      "accepted": 2,
      "rejected": 0,
      "completed": 1,
      "cancelled": 0
    },
    "pagination": {
      "page": 1,
      "limit": 20,
      "total_items": 5,
      "total_pages": 1,
      "has_next": false,
      "has_previous": false
    }
  }
}
```

---

## 10.3 Get Booking Requests (as Vendor)

Returns booking requests received by the authenticated vendor.

```
GET /bookings/received
Authorization: Bearer {access_token}
```

**Query Parameters:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| page | integer | No | 1 | Page number |
| limit | integer | No | 20 | Items per page |
| status | string | No | all | Filter: pending, accepted, rejected, cancelled, completed, all |
| service_id | uuid | No | null | Filter by specific service |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Booking requests retrieved",
  "data": {
    "bookings": [
      {
        "id": "f50e8400-e29b-41d4-a716-446655440020",
        "service": {
          "id": "g50e8400-e29b-41d4-a716-446655440001",
          "title": "Premium Wedding Photography"
        },
        "client": {
          "id": "550e8400-e29b-41d4-a716-446655440080",
          "name": "John Doe",
          "avatar": "https://storage.nuru.com/avatars/john.jpg",
          "phone": "+254712345678",
          "email": "john@example.com"
        },
        "event_name": "John & Jane's Wedding",
        "package_name": "Premium Package",
        "package_price": 120000.0,
        "event_date": "2025-06-15",
        "event_type": "Wedding",
        "location": "Naivasha, Kenya",
        "venue": "The Great Rift Valley Lodge",
        "guest_count": 150,
        "message": "Hi David, we love your work and would like to book you for our wedding...",
        "special_requirements": "We would like drone coverage for outdoor shots",
        "budget": 150000.0,
        "status": "pending",
        "quoted_price": null,
        "conversation_id": "conv-080-001",
        "unread_messages": 1,
        "days_until_event": 130,
        "created_at": "2025-02-05T23:30:00Z",
        "updated_at": "2025-02-05T23:30:00Z"
      },
      {
        "id": "f50e8400-e29b-41d4-a716-446655440021",
        "service": {
          "id": "g50e8400-e29b-41d4-a716-446655440001",
          "title": "Premium Wedding Photography"
        },
        "client": {
          "id": "550e8400-e29b-41d4-a716-446655440081",
          "name": "Mary Akinyi",
          "avatar": null,
          "phone": "+254712345690",
          "email": "mary@example.com"
        },
        "event_name": "Mary's Wedding",
        "package_name": null,
        "package_price": null,
        "event_date": "2025-04-20",
        "event_type": "Wedding",
        "location": "Mombasa, Kenya",
        "venue": null,
        "guest_count": 200,
        "message": "Hello, I'm interested in your photography services for my wedding.",
        "special_requirements": null,
        "budget": null,
        "status": "pending",
        "quoted_price": null,
        "conversation_id": "conv-081-001",
        "unread_messages": 0,
        "days_until_event": 74,
        "created_at": "2025-02-05T09:30:00Z",
        "updated_at": "2025-02-05T09:30:00Z"
      }
    ],
    "summary": {
      "total": 15,
      "pending": 3,
      "accepted": 8,
      "rejected": 1,
      "completed": 3,
      "cancelled": 0
    },
    "pagination": {
      "page": 1,
      "limit": 20,
      "total_items": 15,
      "total_pages": 1,
      "has_next": false,
      "has_previous": false
    }
  }
}
```

---

## 10.4 Get Booking Detail

Returns detailed information about a specific booking.

```
GET /bookings/{bookingId}
Authorization: Bearer {access_token}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Booking retrieved",
  "data": {
    "id": "f50e8400-e29b-41d4-a716-446655440020",
    "service": {
      "id": "g50e8400-e29b-41d4-a716-446655440001",
      "title": "Premium Wedding Photography",
      "primary_image": "https://storage.nuru.com/services/g50e8400-img1.jpg",
      "category": "Photography & Videography"
    },
    "provider": {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "name": "David Mwangi",
      "avatar": "https://storage.nuru.com/avatars/david.jpg",
      "phone": "+254712345000",
      "email": "david@example.com",
      "rating": 4.9
    },
    "client": {
      "id": "550e8400-e29b-41d4-a716-446655440080",
      "name": "John Doe",
      "avatar": "https://storage.nuru.com/avatars/john.jpg",
      "phone": "+254712345678",
      "email": "john@example.com"
    },
    "event": {
      "id": "b50e8400-e29b-41d4-a716-446655440001",
      "title": "John & Jane's Wedding",
      "type": "Wedding",
      "date": "2025-06-15",
      "start_time": "14:00",
      "end_time": "23:00",
      "location": "Naivasha, Kenya",
      "venue": "The Great Rift Valley Lodge",
      "venue_address": "P.O. Box 12345, Naivasha",
      "guest_count": 150
    },
    "package": {
      "id": "h50e8400-e29b-41d4-a716-446655440002",
      "name": "Premium Package",
      "price": 120000.0,
      "features": [
        "8 hours of coverage",
        "2 professional photographers",
        "400+ edited photos"
      ]
    },
    "booking_details": {
      "message": "Hi David, we love your work and would like to book you for our wedding. We're particularly interested in the Premium Package with the engagement session. Please let us know your availability.",
      "special_requirements": "We would like drone coverage for outdoor shots",
      "budget": 150000.0,
      "flexible_date": false,
      "alternate_dates": []
    },
    "status": "pending",
    "status_history": [
      {
        "status": "pending",
        "timestamp": "2025-02-05T23:30:00Z",
        "note": "Booking request created"
      }
    ],
    "quoted_price": null,
    "final_price": null,
    "currency": "KES",
    "deposit_required": null,
    "deposit_paid": false,
    "deposit_paid_at": null,
    "provider_message": null,
    "conversation_id": "conv-080-001",
    "contract_url": null,
    "contract_signed": false,
    "contract_signed_at": null,
    "cancellation_policy": "Full refund up to 30 days before event",
    "can_cancel": true,
    "cancel_deadline": "2025-05-16T00:00:00Z",
    "days_until_event": 130,
    "created_at": "2025-02-05T23:30:00Z",
    "updated_at": "2025-02-05T23:30:00Z"
  }
}
```

---

## 10.5 Respond to Booking (Vendor)

Accepts or rejects a booking request.

```
PUT /bookings/{bookingId}/respond
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body - Accept:**

```json
{
  "status": "accepted",
  "quoted_price": 140000.0,
  "message": "Thank you for choosing us for your special day! I'm excited to work with you. The quoted price includes the Premium Package plus drone coverage as requested. A 30% deposit (KES 42,000) is required to confirm the booking.",
  "deposit_required": 42000.0,
  "deposit_deadline": "2025-02-20",
  "notes": "Will include extra photographer for drone shots"
}
```

**Request Body - Reject:**

```json
{
  "status": "rejected",
  "message": "Thank you for your interest, but unfortunately I'm already booked for that date. I would recommend checking out [Alternative Photographer] who does excellent work.",
  "reason": "date_unavailable"
}
```

| Field            | Type   | Required    | Description                        |
| ---------------- | ------ | ----------- | ---------------------------------- |
| status           | string | Yes         | Response: accepted, rejected       |
| quoted_price     | number | Conditional | Required if accepting              |
| message          | string | Yes         | Message to client (max 1000 chars) |
| deposit_required | number | No          | Deposit amount required            |
| deposit_deadline | date   | No          | Deadline for deposit payment       |
| notes            | string | No          | Internal notes                     |
| reason           | string | Conditional | Rejection reason (if rejecting)    |

**Rejection Reasons:**

- `date_unavailable` - Already booked for that date
- `outside_service_area` - Location not serviced
- `budget_mismatch` - Budget too low
- `short_notice` - Not enough lead time
- `other` - Other reason (explain in message)

**Success Response (200 OK) - Accepted:**

```json
{
  "success": true,
  "message": "Booking accepted",
  "data": {
    "id": "f50e8400-e29b-41d4-a716-446655440020",
    "status": "accepted",
    "quoted_price": 140000.0,
    "deposit_required": 42000.0,
    "deposit_deadline": "2025-02-20",
    "updated_at": "2025-02-06T10:00:00Z"
  }
}
```

---

## 10.6 Cancel Booking

Cancels a booking request.

```
POST /bookings/{bookingId}/cancel
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:**

```json
{
  "reason": "Event has been postponed",
  "notify_other_party": true
}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Booking cancelled",
  "data": {
    "id": "f50e8400-e29b-41d4-a716-446655440020",
    "status": "cancelled",
    "cancelled_at": "2025-02-06T11:00:00Z",
    "cancelled_by": "client",
    "refund_amount": 42000.0,
    "refund_status": "processing"
  }
}
```

---

## 10.7 Mark Booking Complete

Marks a booking as completed after the event.

```
POST /bookings/{bookingId}/complete
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:**

```json
{
  "completion_notes": "Event went smoothly. Delivered 450 photos.",
  "final_amount": 140000.0
}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Booking marked as complete",
  "data": {
    "id": "f50e8400-e29b-41d4-a716-446655440020",
    "status": "completed",
    "completed_at": "2025-06-16T10:00:00Z",
    "can_review": true,
    "review_deadline": "2025-07-16T10:00:00Z"
  }
}
```

---

# 💬 MODULE 11: MESSAGES

---

## 11.1 Get Conversations

Returns all conversations for the authenticated user. Each conversation includes a `type` field (`user_to_user` or `user_to_service`). The `participant` display is **perspective-aware**: service owners see the customer's name/avatar, while customers see the service's branding (title and image). The `service` object (when present) always includes `provider_id` for reference.

```
GET /messages/conversations
Authorization: Bearer {access_token}
```

**Query Parameters:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| page | integer | No | 1 | Page number |
| limit | integer | No | 20 | Items per page |
| filter | string | No | all | Filter: all, unread, service, event |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Conversations retrieved",
  "data": {
    "conversations": [
      {
        "id": "conv-001-002",
        "type": "user_to_service",
        "participant": {
          "id": "550e8400-e29b-41d4-a716-446655440000",
          "name": "David Mwangi",
          "avatar": "https://storage.nuru.com/avatars/david.jpg",
          "is_online": true,
          "last_seen": null,
          "verified": true
        },
        "context": {
          "type": "service",
          "id": "g50e8400-e29b-41d4-a716-446655440001",
          "title": "Premium Wedding Photography"
        },
        "booking": {
          "id": "f50e8400-e29b-41d4-a716-446655440020",
          "status": "pending"
        },
        "last_message": {
          "id": "msg-001",
          "content": "Hi David, we love your work and would like to book you...",
          "sender_id": "550e8400-e29b-41d4-a716-446655440080",
          "is_mine": true,
          "created_at": "2025-02-05T23:30:00Z"
        },
        "unread_count": 0,
        "muted": false,
        "archived": false,
        "created_at": "2025-02-05T23:30:00Z",
        "updated_at": "2025-02-05T23:30:00Z"
      },
      {
        "id": "conv-001-060",
        "participant": {
          "id": "550e8400-e29b-41d4-a716-446655440060",
          "name": "Taste of Africa",
          "avatar": "https://storage.nuru.com/avatars/taste-africa.jpg",
          "is_online": false,
          "last_seen": "2025-02-06T08:00:00Z",
          "verified": true
        },
        "context": {
          "type": "service",
          "id": "g50e8400-e29b-41d4-a716-446655440015",
          "title": "Elegant Catering Services"
        },
        "booking": {
          "id": "f50e8400-e29b-41d4-a716-446655440015",
          "status": "accepted"
        },
        "last_message": {
          "id": "msg-050",
          "content": "We've prepared a custom menu proposal for your wedding. Please review and let us know if you'd like any changes.",
          "sender_id": "550e8400-e29b-41d4-a716-446655440060",
          "is_mine": false,
          "created_at": "2025-02-06T09:30:00Z"
        },
        "unread_count": 2,
        "muted": false,
        "archived": false,
        "created_at": "2025-02-03T11:00:00Z",
        "updated_at": "2025-02-06T09:30:00Z"
      },
      {
        "id": "conv-003-001",
        "participant": {
          "id": "550e8400-e29b-41d4-a716-446655440090",
          "name": "Jane Wanjiku",
          "avatar": "https://storage.nuru.com/avatars/jane-w.jpg",
          "is_online": false,
          "last_seen": "2025-02-05T18:00:00Z",
          "verified": false
        },
        "context": {
          "type": "general",
          "id": null,
          "title": null
        },
        "booking": null,
        "last_message": {
          "id": "msg-100",
          "content": "Thanks for the recommendation!",
          "sender_id": "550e8400-e29b-41d4-a716-446655440090",
          "is_mine": false,
          "created_at": "2025-02-04T15:00:00Z"
        },
        "unread_count": 0,
        "muted": false,
        "archived": false,
        "created_at": "2025-02-01T10:00:00Z",
        "updated_at": "2025-02-04T15:00:00Z"
      }
    ],
    "summary": {
      "total_conversations": 8,
      "total_unread": 3
    },
    "pagination": {
      "page": 1,
      "limit": 20,
      "total_items": 8,
      "total_pages": 1,
      "has_next": false,
      "has_previous": false
    }
  }
}
```

---

## 11.2 Get Messages

Returns messages in a conversation.

```
GET /messages/{conversationId}
Authorization: Bearer {access_token}
```

**Query Parameters:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| page | integer | No | 1 | Page number |
| limit | integer | No | 50 | Items per page |
| before | string | No | null | Get messages before this message ID |
| after | string | No | null | Get messages after this message ID |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Messages retrieved",
  "data": {
    "conversation": {
      "id": "conv-001-060",
      "participant": {
        "id": "550e8400-e29b-41d4-a716-446655440060",
        "name": "Taste of Africa",
        "avatar": "https://storage.nuru.com/avatars/taste-africa.jpg",
        "is_online": false,
        "last_seen": "2025-02-06T08:00:00Z"
      },
      "context": {
        "type": "service",
        "id": "g50e8400-e29b-41d4-a716-446655440015",
        "title": "Elegant Catering Services"
      }
    },
    "messages": [
      {
        "id": "msg-040",
        "conversation_id": "conv-001-060",
        "sender_id": "550e8400-e29b-41d4-a716-446655440080",
        "sender": {
          "name": "John Doe",
          "avatar": "https://storage.nuru.com/avatars/john.jpg"
        },
        "content": "Hi, I'm interested in your catering services for my wedding on June 15th. We're expecting about 150 guests.",
        "message_type": "text",
        "attachments": [],
        "is_mine": true,
        "is_read": true,
        "read_at": "2025-02-03T11:05:00Z",
        "created_at": "2025-02-03T11:00:00Z"
      },
      {
        "id": "msg-041",
        "conversation_id": "conv-001-060",
        "sender_id": "550e8400-e29b-41d4-a716-446655440060",
        "sender": {
          "name": "Taste of Africa",
          "avatar": "https://storage.nuru.com/avatars/taste-africa.jpg"
        },
        "content": "Hello John! Thank you for reaching out. We'd be delighted to cater your wedding. Could you tell me more about your preferences? Are you looking for a buffet or plated service?",
        "message_type": "text",
        "attachments": [],
        "is_mine": false,
        "is_read": true,
        "read_at": "2025-02-03T12:00:00Z",
        "created_at": "2025-02-03T11:30:00Z"
      },
      {
        "id": "msg-042",
        "conversation_id": "conv-001-060",
        "sender_id": "550e8400-e29b-41d4-a716-446655440080",
        "sender": {
          "name": "John Doe",
          "avatar": "https://storage.nuru.com/avatars/john.jpg"
        },
        "content": "We're thinking buffet style would work best. We'd like a mix of Kenyan and continental cuisine. Our budget is around KES 200,000.",
        "message_type": "text",
        "attachments": [],
        "is_mine": true,
        "is_read": true,
        "read_at": "2025-02-03T14:00:00Z",
        "created_at": "2025-02-03T13:00:00Z"
      },
      {
        "id": "msg-050",
        "conversation_id": "conv-001-060",
        "sender_id": "550e8400-e29b-41d4-a716-446655440060",
        "sender": {
          "name": "Taste of Africa",
          "avatar": "https://storage.nuru.com/avatars/taste-africa.jpg"
        },
        "content": "We've prepared a custom menu proposal for your wedding. Please review and let us know if you'd like any changes.",
        "message_type": "text",
        "attachments": [
          {
            "id": "att-001",
            "type": "document",
            "name": "Wedding_Menu_Proposal_John_Jane.pdf",
            "url": "https://storage.nuru.com/messages/att-001.pdf",
            "size_bytes": 245000,
            "mime_type": "application/pdf"
          }
        ],
        "is_mine": false,
        "is_read": false,
        "read_at": null,
        "created_at": "2025-02-06T09:30:00Z"
      }
    ],
    "pagination": {
      "page": 1,
      "limit": 50,
      "total_items": 4,
      "total_pages": 1,
      "has_next": false,
      "has_previous": false
    }
  }
}
```

---

## 11.3 Send Message

Sends a message in a conversation.

```
POST /messages/{conversationId}
Authorization: Bearer {access_token}
Content-Type: multipart/form-data
```

**Form Fields:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| content | string | Yes | Message content (max 5000 chars) |
| attachments | file[] | No | File attachments (max 5, each max 10MB) |
| reply_to | uuid | No | ID of message being replied to |

**Success Response (201 Created):**

```json
{
  "success": true,
  "message": "Message sent",
  "data": {
    "id": "msg-051",
    "conversation_id": "conv-001-060",
    "sender_id": "550e8400-e29b-41d4-a716-446655440080",
    "content": "This looks great! I love the menu options. Can we add a vegetarian station as well?",
    "message_type": "text",
    "attachments": [],
    "reply_to": {
      "id": "msg-050",
      "content": "We've prepared a custom menu proposal..."
    },
    "is_read": false,
    "created_at": "2025-02-06T10:00:00Z"
  }
}
```

---

## 11.4 Start Conversation

Starts a new conversation with a user.

```
POST /messages/start
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:**

```json
{
  "recipient_id": "550e8400-e29b-41d4-a716-446655440095",
  "content": "Hi! I saw your service listing and I'm interested in learning more.",
  "context": {
    "type": "service",
    "id": "g50e8400-e29b-41d4-a716-446655440025"
  }
}
```

| Field        | Type   | Required | Description                           |
| ------------ | ------ | -------- | ------------------------------------- |
| recipient_id | uuid   | Yes      | User ID to message                    |
| content      | string | Yes      | Initial message (max 5000 chars)      |
| context      | object | No       | Context for the conversation          |
| context.type | string | No       | Context type: service, event, general |
| context.id   | uuid   | No       | ID of the service or event            |

**Success Response (201 Created):**

```json
{
  "success": true,
  "message": "Conversation started",
  "data": {
    "conversation_id": "conv-001-095",
    "message": {
      "id": "msg-200",
      "content": "Hi! I saw your service listing and I'm interested in learning more.",
      "created_at": "2025-02-06T10:30:00Z"
    }
  }
}
```

---

## 11.5 Mark Messages as Read

Marks messages in a conversation as read.

```
PUT /messages/{conversationId}/read
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:**

```json
{
  "message_ids": ["msg-050", "msg-049"]
}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Messages marked as read",
  "data": {
    "marked_count": 2
  }
}
```

---

## 11.6 Delete Message

Deletes a message (soft delete - marks as deleted).

```
DELETE /messages/{conversationId}/messages/{messageId}
Authorization: Bearer {access_token}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Message deleted"
}
```

---

## 11.7 Archive Conversation

Archives a conversation.

```
POST /messages/{conversationId}/archive
Authorization: Bearer {access_token}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Conversation archived"
}
```

---

## 11.8 Mute/Unmute Conversation

Mutes or unmutes notifications for a conversation.

```
POST /messages/{conversationId}/mute
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:**

```json
{
  "muted": true,
  "duration": "24h"
}
```

| Field    | Type    | Required | Description                             |
| -------- | ------- | -------- | --------------------------------------- |
| muted    | boolean | Yes      | Whether to mute                         |
| duration | string  | No       | Mute duration: 1h, 8h, 24h, 7d, forever |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Conversation muted",
  "data": {
    "muted": true,
    "muted_until": "2025-02-07T10:30:00Z"
  }
}
```

---

# 🔔 MODULE 12: NOTIFICATIONS

---

## 12.1 Get Notifications

Returns notifications for the authenticated user.

```
GET /notifications/
Authorization: Bearer {access_token}
```

**Query Parameters:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| page | integer | No | 1 | Page number |
| limit | integer | No | 20 | Items per page |
| unread_only | boolean | No | false | Only unread notifications |
| type | string | No | all | Filter by type |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Notifications retrieved",
  "data": {
    "notifications": [
      {
        "id": "n50e8400-e29b-41d4-a716-446655440001",
        "user_id": "550e8400-e29b-41d4-a716-446655440080",
        "type": "booking_request",
        "title": "New Booking Request",
        "message": "You have a new booking request from Mary Akinyi for Premium Wedding Photography",
        "data": {
          "booking_id": "f50e8400-e29b-41d4-a716-446655440021",
          "service_id": "g50e8400-e29b-41d4-a716-446655440001",
          "client_name": "Mary Akinyi",
          "event_date": "2025-04-20"
        },
        "action_url": "/bookings/f50e8400-e29b-41d4-a716-446655440021",
        "action_text": "View Request",
        "image_url": null,
        "is_read": false,
        "read_at": null,
        "created_at": "2025-02-05T09:30:00Z"
      },
      {
        "id": "n50e8400-e29b-41d4-a716-446655440002",
        "user_id": "550e8400-e29b-41d4-a716-446655440080",
        "type": "message",
        "title": "New Message",
        "message": "Taste of Africa sent you a message",
        "data": {
          "conversation_id": "conv-001-060",
          "sender_id": "550e8400-e29b-41d4-a716-446655440060",
          "sender_name": "Taste of Africa",
          "preview": "We've prepared a custom menu proposal..."
        },
        "action_url": "/messages/conv-001-060",
        "action_text": "View Message",
        "image_url": "https://storage.nuru.com/avatars/taste-africa.jpg",
        "is_read": false,
        "read_at": null,
        "created_at": "2025-02-06T09:30:00Z"
      },
      {
        "id": "n50e8400-e29b-41d4-a716-446655440003",
        "user_id": "550e8400-e29b-41d4-a716-446655440080",
        "type": "contribution",
        "title": "New Contribution",
        "message": "James Wilson contributed KES 50,000 to John & Jane's Wedding",
        "data": {
          "event_id": "b50e8400-e29b-41d4-a716-446655440001",
          "contribution_id": "e50e8400-e29b-41d4-a716-446655440001",
          "contributor_name": "James Wilson",
          "amount": 50000,
          "currency": "KES"
        },
        "action_url": "/events/b50e8400-e29b-41d4-a716-446655440001/contributions",
        "action_text": "View Contribution",
        "image_url": null,
        "is_read": true,
        "read_at": "2025-02-01T16:00:00Z",
        "created_at": "2025-02-01T15:31:00Z"
      },
      {
        "id": "n50e8400-e29b-41d4-a716-446655440004",
        "user_id": "550e8400-e29b-41d4-a716-446655440080",
        "type": "rsvp",
        "title": "RSVP Received",
        "message": "Michael Johnson confirmed attendance for John & Jane's Wedding with 1 plus one",
        "data": {
          "event_id": "b50e8400-e29b-41d4-a716-446655440001",
          "guest_id": "c50e8400-e29b-41d4-a716-446655440001",
          "guest_name": "Michael Johnson",
          "rsvp_status": "confirmed",
          "plus_ones": 1
        },
        "action_url": "/events/b50e8400-e29b-41d4-a716-446655440001/guests",
        "action_text": "View Guest",
        "image_url": null,
        "is_read": true,
        "read_at": "2025-02-03T15:00:00Z",
        "created_at": "2025-02-03T14:20:00Z"
      },
      {
        "id": "n50e8400-e29b-41d4-a716-446655440005",
        "user_id": "550e8400-e29b-41d4-a716-446655440080",
        "type": "kyc_approved",
        "title": "KYC Document Approved",
        "message": "Your National ID has been verified for Premium Wedding Photography",
        "data": {
          "service_id": "g50e8400-e29b-41d4-a716-446655440001",
          "kyc_requirement": "National ID / Passport"
        },
        "action_url": "/services/g50e8400-e29b-41d4-a716-446655440001/kyc",
        "action_text": "View Status",
        "image_url": null,
        "is_read": true,
        "read_at": "2025-01-12T15:00:00Z",
        "created_at": "2025-01-12T14:00:00Z"
      },
      {
        "id": "n50e8400-e29b-41d4-a716-446655440006",
        "user_id": "550e8400-e29b-41d4-a716-446655440080",
        "type": "review",
        "title": "New Review",
        "message": "Jane Wanjiku left a 5-star review for Premium Wedding Photography",
        "data": {
          "service_id": "g50e8400-e29b-41d4-a716-446655440001",
          "review_id": "r50e8400-e29b-41d4-a716-446655440001",
          "reviewer_name": "Jane Wanjiku",
          "rating": 5
        },
        "action_url": "/services/g50e8400-e29b-41d4-a716-446655440001/reviews",
        "action_text": "View Review",
        "image_url": "https://storage.nuru.com/avatars/jane-w.jpg",
        "is_read": true,
        "read_at": "2025-01-22T16:00:00Z",
        "created_at": "2025-01-22T14:30:00Z"
      }
    ],
    "summary": {
      "total": 25,
      "unread": 2
    },
    "pagination": {
      "page": 1,
      "limit": 20,
      "total_items": 25,
      "total_pages": 2,
      "has_next": true,
      "has_previous": false
    }
  }
}
```

### 12.1.1 Referential Navigation Scheme

Notifications in Nuru are **referential** — clicking a notification navigates the user to the relevant entity's detail page. The frontend resolves navigation targets using `reference_id`, `reference_type`, and `type` fields from the API response.

**Navigation Mapping:**

| Notification Type                                                                                | reference_type | Navigates To               |
| ------------------------------------------------------------------------------------------------ | -------------- | -------------------------- |
| `event_invite`, `committee_invite`, `rsvp_received`, `contribution_received`, `expense_recorded` | `event`        | `/event/{reference_id}`    |
| `booking_request`, `booking_accepted`, `booking_rejected`                                        | `booking`      | `/bookings/{reference_id}` |
| `glow`, `comment`, `echo`, `mention`                                                             | `post`         | `/post/{reference_id}`     |
| `follow`, `circle_add`                                                                           | `user`         | `/u/{actor.username}`      |
| `content_removed`, `post_removed`, `moment_removed`                                              | —              | `/removed-content`         |
| `service_approved`, `service_rejected`, `kyc_approved`                                           | `service`      | `/service/{reference_id}`  |
| `identity_verified`                                                                              | —              | `/profile`                 |
| `password_changed`, `password_reset`                                                             | —              | `/settings`                |
| `moment_view`, `moment_reaction`                                                                 | —              | `/u/{actor.username}`      |
| `broadcast`, `system`, `general`                                                                 | —              | Non-navigable              |

**Actor Object (returned in each notification):**

```json
{
  "id": "uuid",
  "first_name": "John",
  "last_name": "Doe",
  "username": "johndoe",
  "avatar": "https://..."
}
```

System notifications (broadcast, system) use the Nuru logo avatar and "Nuru" as actor name.

**Notification Type Enum Values:**
`glow`, `echo`, `spark`, `follow`, `event_invite`, `service_approved`, `service_rejected`, `account_created`, `system`, `general`, `broadcast`, `contribution_received`, `booking_request`, `booking_accepted`, `booking_rejected`, `rsvp_received`, `committee_invite`, `moment_view`, `moment_reaction`, `comment`, `mention`, `circle_add`, `expense_recorded`, `content_removed`, `post_removed`, `moment_removed`, `identity_verified`, `kyc_approved`, `password_changed`, `password_reset`

---

## 12.2 Mark Notification as Read

Marks a specific notification as read.

```
PATCH /notifications/{notificationId}/read
Authorization: Bearer {access_token}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Notification marked as read",
  "data": {
    "id": "n50e8400-e29b-41d4-a716-446655440001",
    "is_read": true,
    "read_at": "2025-02-06T11:00:00Z"
  }
}
```

---

## 12.3 Mark All Notifications as Read

Marks all unread notifications as read.

```
PATCH /notifications/read-all
Authorization: Bearer {access_token}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "All notifications marked as read",
  "data": {
    "marked_count": 2
  }
}
```

---

## 12.4 Delete Notification

Deletes a notification.

```
DELETE /notifications/{notificationId}
Authorization: Bearer {access_token}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Notification deleted"
}
```

---

## 12.5 Get Notification Preferences

Returns user's notification preferences.

```
GET /notifications/preferences
Authorization: Bearer {access_token}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Preferences retrieved",
  "data": {
    "email": {
      "enabled": true,
      "booking_requests": true,
      "messages": true,
      "contributions": true,
      "rsvp": true,
      "reviews": true,
      "marketing": false,
      "digest": "daily"
    },
    "push": {
      "enabled": true,
      "booking_requests": true,
      "messages": true,
      "contributions": true,
      "rsvp": true,
      "reviews": true
    },
    "sms": {
      "enabled": false,
      "booking_requests": false,
      "contributions": false
    },
    "quiet_hours": {
      "enabled": true,
      "start": "22:00",
      "end": "07:00",
      "timezone": "Africa/Nairobi"
    }
  }
}
```

---

## 12.6 Update Notification Preferences

Updates user's notification preferences.

```
PUT /notifications/preferences
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:**

```json
{
  "email": {
    "messages": false,
    "marketing": false,
    "digest": "weekly"
  },
  "push": {
    "reviews": false
  },
  "quiet_hours": {
    "enabled": true,
    "start": "21:00",
    "end": "08:00"
  }
}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Preferences updated"
}
```

---

Continuing with the complete API documentation for all remaining modules.

---

## MODULE 13: USER PROFILE

### 13.1 Get Current User Profile

```
GET /users/profile
Authorization: Bearer {token}

Response 200:
{
  "success": true,
  "message": "Profile retrieved successfully",
  "data": {
    "id": "uuid-string",
    "first_name": "John",
    "last_name": "Doe",
    "username": "johndoe",
    "email": "john@example.com",
    "phone": "+254712345678",
    "avatar": "https://storage.example.com/avatars/uuid.jpg",
    "bio": "Event enthusiast and planner",
    "date_of_birth": "1990-05-15",
    "gender": "male",
    "location": {
      "city": "Nairobi",
      "country": "Kenya",
      "country_code": "KE"
    },
    "social_links": {
      "instagram": "johndoe",
      "twitter": "johndoe",
      "facebook": "john.doe",
      "linkedin": "johndoe",
      "website": "https://johndoe.com"
    },
    "is_email_verified": true,
    "is_phone_verified": true,
    "is_vendor": true,
    "vendor_status": "approved",
    "follower_count": 1250,
    "following_count": 340,
    "post_count": 45,
    "event_count": 12,
    "created_at": "2024-01-15T10:30:00Z",
    "updated_at": "2024-06-20T14:22:00Z"
  }
}
```

### 13.2 Get User Profile by ID (Public)

```
GET /users/:userId
Authorization: Bearer {token} (optional)

Path Parameters:
- userId (required): UUID of the user

Response 200:
{
  "success": true,
  "message": "User profile retrieved successfully",
  "data": {
    "id": "uuid-string",
    "first_name": "Jane",
    "last_name": "Smith",
    "username": "janesmith",
    "avatar": "https://storage.example.com/avatars/uuid.jpg",
    "bio": "Professional photographer | Capturing moments",
    "location": {
      "city": "Mombasa",
      "country": "Kenya",
      "country_code": "KE"
    },
    "social_links": {
      "instagram": "janesmithphoto",
      "twitter": null,
      "facebook": null,
      "linkedin": null,
      "website": "https://janesmithphotography.com"
    },
    "is_vendor": true,
    "vendor_status": "approved",
    "follower_count": 5420,
    "following_count": 890,
    "post_count": 234,
    "event_count": 56,
    "is_following": true,
    "is_followed_by": false,
    "mutual_followers_count": 12,
    "mutual_followers_preview": [
      {
        "id": "uuid-string",
        "username": "mutualfriend1",
        "avatar": "https://storage.example.com/avatars/uuid.jpg"
      },
      {
        "id": "uuid-string",
        "username": "mutualfriend2",
        "avatar": "https://storage.example.com/avatars/uuid.jpg"
      }
    ],
    "created_at": "2023-06-10T08:00:00Z"
  }
}

Response 404:
{
  "success": false,
  "message": "User not found",
  "data": null
}
```

### 13.3 Update User Profile

```
PUT /users/profile
Authorization: Bearer {token}
Content-Type: multipart/form-data

Form Fields:
- first_name (optional): string, max 50 characters
- last_name (optional): string, max 50 characters
- username (optional): string, 3-30 characters, alphanumeric and underscores only
- bio (optional): string, max 500 characters
- date_of_birth (optional): string, format YYYY-MM-DD
- gender (optional): string, one of "male", "female", "other", "prefer_not_to_say"
- city (optional): string, max 100 characters
- country_code (optional): string, ISO 3166-1 alpha-2 code
- instagram (optional): string, username only without @
- twitter (optional): string, username only without @
- facebook (optional): string, username or profile ID
- linkedin (optional): string, username only
- website (optional): string, valid URL
- avatar (optional): file, max 5MB, formats: jpg, jpeg, png, webp

Response 200:
{
  "success": true,
  "message": "Profile updated successfully",
  "data": {
    "id": "uuid-string",
    "first_name": "John",
    "last_name": "Doe",
    "username": "johndoe_updated",
    "email": "john@example.com",
    "phone": "+254712345678",
    "avatar": "https://storage.example.com/avatars/new-uuid.jpg",
    "bio": "Updated bio text here",
    "date_of_birth": "1990-05-15",
    "gender": "male",
    "location": {
      "city": "Nairobi",
      "country": "Kenya",
      "country_code": "KE"
    },
    "social_links": {
      "instagram": "johndoe_new",
      "twitter": "johndoe",
      "facebook": "john.doe",
      "linkedin": "johndoe",
      "website": "https://johndoe.com"
    },
    "is_email_verified": true,
    "is_phone_verified": true,
    "updated_at": "2024-06-25T16:45:00Z"
  }
}

Response 400:
{
  "success": false,
  "message": "Validation failed",
  "data": {
    "errors": {
      "username": "Username is already taken",
      "avatar": "File size exceeds maximum allowed (5MB)"
    }
  }
}
```

### 13.4 Change Password

```
POST /users/change-password
Authorization: Bearer {token}
Content-Type: application/json

Request Body:
{
  "current_password": "OldPassword123!",
  "new_password": "NewSecurePassword456!",
  "confirm_password": "NewSecurePassword456!"
}

Validation Rules:
- current_password: required, must match existing password
- new_password: required, min 8 characters, must contain uppercase, lowercase, number, special character
- confirm_password: required, must match new_password

Response 200:
{
  "success": true,
  "message": "Password changed successfully",
  "data": null
}

Response 400:
{
  "success": false,
  "message": "Current password is incorrect",
  "data": null
}

Response 422:
{
  "success": false,
  "message": "Validation failed",
  "data": {
    "errors": {
      "new_password": "Password must contain at least one special character",
      "confirm_password": "Passwords do not match"
    }
  }
}
```

### 13.5 Update Email

```
PUT /users/email
Authorization: Bearer {token}
Content-Type: application/json

Request Body:
{
  "new_email": "newemail@example.com",
  "password": "CurrentPassword123!"
}

Response 200:
{
  "success": true,
  "message": "Verification email sent to new address",
  "data": {
    "pending_email": "newemail@example.com",
    "verification_expires_at": "2024-06-25T17:30:00Z"
  }
}

Response 400:
{
  "success": false,
  "message": "Email is already in use",
  "data": null
}
```

### 13.6 Update Phone

```
PUT /users/phone
Authorization: Bearer {token}
Content-Type: application/json

Request Body:
{
  "new_phone": "+254798765432",
  "password": "CurrentPassword123!"
}

Response 200:
{
  "success": true,
  "message": "Verification code sent to new phone number",
  "data": {
    "pending_phone": "+254798765432",
    "verification_expires_at": "2024-06-25T16:50:00Z"
  }
}
```

### 13.7 Follow User

```
POST /users/:userId/follow
Authorization: Bearer {token}

Path Parameters:
- userId (required): UUID of user to follow

Response 200:
{
  "success": true,
  "message": "You are now following this user",
  "data": {
    "following_id": "uuid-string",
    "follower_id": "uuid-current-user",
    "followed_id": "uuid-target-user",
    "created_at": "2024-06-25T16:00:00Z"
  }
}

Response 400:
{
  "success": false,
  "message": "You are already following this user",
  "data": null
}

Response 400:
{
  "success": false,
  "message": "You cannot follow yourself",
  "data": null
}
```

### 13.8 Unfollow User

```
DELETE /users/:userId/follow
Authorization: Bearer {token}

Path Parameters:
- userId (required): UUID of user to unfollow

Response 200:
{
  "success": true,
  "message": "You have unfollowed this user",
  "data": null
}

Response 400:
{
  "success": false,
  "message": "You are not following this user",
  "data": null
}
```

### 13.9 Get User Followers

```
GET /users/:userId/followers
Authorization: Bearer {token} (optional)

Path Parameters:
- userId (required): UUID of user

Query Parameters:
- page (optional): integer, default 1
- limit (optional): integer, default 20, max 50
- search (optional): string, search by name or username

Response 200:
{
  "success": true,
  "message": "Followers retrieved successfully",
  "data": {
    "followers": [
      {
        "id": "uuid-string",
        "first_name": "Alice",
        "last_name": "Johnson",
        "username": "alicejohnson",
        "avatar": "https://storage.example.com/avatars/uuid.jpg",
        "bio": "Music lover and event organizer",
        "is_following": true,
        "is_followed_by": true,
        "followed_at": "2024-05-10T12:30:00Z"
      },
      {
        "id": "uuid-string",
        "first_name": "Bob",
        "last_name": "Williams",
        "username": "bobwilliams",
        "avatar": "https://storage.example.com/avatars/uuid.jpg",
        "bio": "Professional DJ",
        "is_following": false,
        "is_followed_by": true,
        "followed_at": "2024-04-22T09:15:00Z"
      }
    ],
    "pagination": {
      "current_page": 1,
      "per_page": 20,
      "total_items": 1250,
      "total_pages": 63,
      "has_next": true,
      "has_previous": false
    }
  }
}
```

### 13.10 Get User Following

```
GET /users/:userId/following
Authorization: Bearer {token} (optional)

Path Parameters:
- userId (required): UUID of user

Query Parameters:
- page (optional): integer, default 1
- limit (optional): integer, default 20, max 50
- search (optional): string, search by name or username

Response 200:
{
  "success": true,
  "message": "Following list retrieved successfully",
  "data": {
    "following": [
      {
        "id": "uuid-string",
        "first_name": "Carol",
        "last_name": "Davis",
        "username": "caroldavis",
        "avatar": "https://storage.example.com/avatars/uuid.jpg",
        "bio": "Wedding planner extraordinaire",
        "is_vendor": true,
        "is_following": true,
        "is_followed_by": false,
        "followed_at": "2024-06-01T14:20:00Z"
      }
    ],
    "pagination": {
      "current_page": 1,
      "per_page": 20,
      "total_items": 340,
      "total_pages": 17,
      "has_next": true,
      "has_previous": false
    }
  }
}
```

### 13.11 Get User's Public Events

```
GET /users/:userId/events
Authorization: Bearer {token} (optional)

Path Parameters:
- userId (required): UUID of user

Query Parameters:
- page (optional): integer, default 1
- limit (optional): integer, default 10, max 20
- status (optional): string, one of "upcoming", "past", "all"

Response 200:
{
  "success": true,
  "message": "User events retrieved successfully",
  "data": {
    "events": [
      {
        "id": "uuid-string",
        "title": "Summer Music Festival",
        "event_type": {
          "id": "uuid-string",
          "name": "Concert",
          "icon": "music"
        },
        "cover_image": "https://storage.example.com/events/uuid.jpg",
        "start_date": "2024-08-15",
        "start_time": "16:00:00",
        "end_date": "2024-08-15",
        "end_time": "23:00:00",
        "venue_name": "Uhuru Gardens",
        "city": "Nairobi",
        "privacy": "public",
        "guest_count": 500,
        "is_attending": true,
        "attendance_status": "going"
      }
    ],
    "pagination": {
      "current_page": 1,
      "per_page": 10,
      "total_items": 12,
      "total_pages": 2,
      "has_next": true,
      "has_previous": false
    }
  }
}
```

### 13.12 Get User's Posts

```
GET /users/:userId/posts
Authorization: Bearer {token} (optional)

Path Parameters:
- userId (required): UUID of user

Query Parameters:
- page (optional): integer, default 1
- limit (optional): integer, default 10, max 20

Response 200:
{
  "success": true,
  "message": "User posts retrieved successfully",
  "data": {
    "posts": [
      {
        "id": "uuid-string",
        "content": "Amazing wedding ceremony yesterday! The couple looked stunning.",
        "media": [
          {
            "id": "uuid-string",
            "type": "image",
            "url": "https://storage.example.com/posts/uuid.jpg",
            "thumbnail_url": "https://storage.example.com/posts/uuid-thumb.jpg",
            "width": 1920,
            "height": 1080
          }
        ],
        "event": {
          "id": "uuid-string",
          "title": "John & Mary's Wedding"
        },
        "glow_count": 234,
        "echo_count": 45,
        "comment_count": 23,
        "has_glowed": true,
        "has_echoed": false,
        "created_at": "2024-06-20T18:30:00Z"
      }
    ],
    "pagination": {
      "current_page": 1,
      "per_page": 10,
      "total_items": 45,
      "total_pages": 5,
      "has_next": true,
      "has_previous": false
    }
  }
}
```

### 13.13 Get User's Services (Vendor)

```
GET /users/:userId/services
Authorization: Bearer {token} (optional)

Path Parameters:
- userId (required): UUID of vendor user

Query Parameters:
- page (optional): integer, default 1
- limit (optional): integer, default 10, max 20

Response 200:
{
  "success": true,
  "message": "User services retrieved successfully",
  "data": {
    "services": [
      {
        "id": "uuid-string",
        "title": "Wedding Photography",
        "description": "Capturing your special moments with artistic flair",
        "service_category": {
          "id": "uuid-string",
          "name": "Photography",
          "icon": "camera"
        },
        "service_type": {
          "id": "uuid-string",
          "name": "Wedding Photography"
        },
        "min_price": 50000,
        "max_price": 200000,
        "currency": "KES",
        "images": [
          "https://storage.example.com/services/uuid-1.jpg",
          "https://storage.example.com/services/uuid-2.jpg"
        ],
        "rating": 4.8,
        "review_count": 156,
        "verification_status": "verified",
        "location": "Nairobi, Kenya"
      }
    ],
    "pagination": {
      "current_page": 1,
      "per_page": 10,
      "total_items": 3,
      "total_pages": 1,
      "has_next": false,
      "has_previous": false
    }
  }
}

Response 400:
{
  "success": false,
  "message": "User is not a vendor",
  "data": null
}
```

### 13.14 Block User

```
POST /users/:userId/block
Authorization: Bearer {token}

Path Parameters:
- userId (required): UUID of user to block

Response 200:
{
  "success": true,
  "message": "User blocked successfully",
  "data": {
    "block_id": "uuid-string",
    "blocked_user_id": "uuid-string",
    "created_at": "2024-06-25T17:00:00Z"
  }
}

Response 400:
{
  "success": false,
  "message": "You cannot block yourself",
  "data": null
}
```

### 13.15 Unblock User

```
DELETE /users/:userId/block
Authorization: Bearer {token}

Path Parameters:
- userId (required): UUID of user to unblock

Response 200:
{
  "success": true,
  "message": "User unblocked successfully",
  "data": null
}
```

### 13.16 Get Blocked Users

```
GET /users/blocked
Authorization: Bearer {token}

Query Parameters:
- page (optional): integer, default 1
- limit (optional): integer, default 20, max 50

Response 200:
{
  "success": true,
  "message": "Blocked users retrieved successfully",
  "data": {
    "blocked_users": [
      {
        "id": "uuid-string",
        "first_name": "Spam",
        "last_name": "Account",
        "username": "spamaccount",
        "avatar": "https://storage.example.com/avatars/uuid.jpg",
        "blocked_at": "2024-06-20T10:00:00Z"
      }
    ],
    "pagination": {
      "current_page": 1,
      "per_page": 20,
      "total_items": 5,
      "total_pages": 1,
      "has_next": false,
      "has_previous": false
    }
  }
}
```

### 13.17 Delete Account

```
DELETE /users/account
Authorization: Bearer {token}
Content-Type: application/json

Request Body:
{
  "password": "CurrentPassword123!",
  "reason": "No longer using the service",
  "feedback": "Great app, just don't need it anymore"
}

Response 200:
{
  "success": true,
  "message": "Account deletion scheduled. You have 30 days to reactivate.",
  "data": {
    "deletion_scheduled_at": "2024-07-25T17:00:00Z",
    "final_deletion_at": "2024-07-25T17:00:00Z"
  }
}

Response 400:
{
  "success": false,
  "message": "Incorrect password",
  "data": null
}
```

---

## MODULE 14: FEED / POSTS

### 14.1 Get Feed

```
GET /feed
Authorization: Bearer {token}

Query Parameters:
- page (optional): integer, default 1
- limit (optional): integer, default 10, max 20
- type (optional): string, one of "all", "following", "trending", "nearby"
- event_id (optional): UUID, filter by specific event

Response 200:
{
  "success": true,
  "message": "Feed retrieved successfully",
  "data": {
    "posts": [
      {
        "id": "uuid-string",
        "user": {
          "id": "uuid-string",
          "first_name": "Sarah",
          "last_name": "Johnson",
          "username": "sarahjohnson",
          "avatar": "https://storage.example.com/avatars/uuid.jpg",
          "is_verified": true,
          "is_following": true
        },
        "content": "What an incredible experience at the corporate gala last night! The decorations were breathtaking 🌟",
        "media": [
          {
            "id": "uuid-string",
            "type": "image",
            "url": "https://storage.example.com/posts/uuid-1.jpg",
            "thumbnail_url": "https://storage.example.com/posts/uuid-1-thumb.jpg",
            "width": 1920,
            "height": 1080,
            "blurhash": "LGF5]+Yk^6#M@-5c,1J5@[or[Q6."
          },
          {
            "id": "uuid-string",
            "type": "image",
            "url": "https://storage.example.com/posts/uuid-2.jpg",
            "thumbnail_url": "https://storage.example.com/posts/uuid-2-thumb.jpg",
            "width": 1080,
            "height": 1920,
            "blurhash": "L6PZfSjE.AyE_3t7t7R**0teleE"
          }
        ],
        "event": {
          "id": "uuid-string",
          "title": "Annual Corporate Gala 2024",
          "event_type": {
            "id": "uuid-string",
            "name": "Corporate",
            "icon": "briefcase"
          }
        },
        "tagged_users": [
          {
            "id": "uuid-string",
            "username": "michaelchen",
            "avatar": "https://storage.example.com/avatars/uuid.jpg"
          }
        ],
        "location": {
          "name": "Kempinski Hotel",
          "city": "Nairobi",
          "country": "Kenya"
        },
        "glow_count": 156,
        "echo_count": 23,
        "comment_count": 45,
        "share_count": 12,
        "has_glowed": true,
        "has_echoed": false,
        "has_saved": false,
        "is_pinned": false,
        "privacy": "public",
        "created_at": "2024-06-24T20:30:00Z",
        "updated_at": "2024-06-24T20:30:00Z"
      },
      {
        "id": "uuid-string",
        "user": {
          "id": "uuid-string",
          "first_name": "David",
          "last_name": "Wilson",
          "username": "davidwilson",
          "avatar": "https://storage.example.com/avatars/uuid.jpg",
          "is_verified": false,
          "is_following": false
        },
        "content": "Check out this amazing video from my sister's graduation ceremony! So proud of her 🎓",
        "media": [
          {
            "id": "uuid-string",
            "type": "video",
            "url": "https://storage.example.com/posts/uuid-video.mp4",
            "thumbnail_url": "https://storage.example.com/posts/uuid-video-thumb.jpg",
            "width": 1920,
            "height": 1080,
            "duration": 45,
            "blurhash": "LKO2?U%2Tw=w]~RBVZRi};RPxuwH"
          }
        ],
        "event": null,
        "tagged_users": [],
        "location": null,
        "glow_count": 89,
        "echo_count": 5,
        "comment_count": 12,
        "share_count": 3,
        "has_glowed": false,
        "has_echoed": false,
        "has_saved": true,
        "is_pinned": false,
        "privacy": "public",
        "created_at": "2024-06-24T18:15:00Z",
        "updated_at": "2024-06-24T18:15:00Z"
      }
    ],
    "pagination": {
      "current_page": 1,
      "per_page": 10,
      "total_items": 500,
      "total_pages": 50,
      "has_next": true,
      "has_previous": false
    }
  }
}
```

### 14.2 Get Single Post

```
GET /posts/:postId
Authorization: Bearer {token} (optional for public posts)

Path Parameters:
- postId (required): UUID of the post

Response 200:
{
  "success": true,
  "message": "Post retrieved successfully",
  "data": {
    "id": "uuid-string",
    "user": {
      "id": "uuid-string",
      "first_name": "Sarah",
      "last_name": "Johnson",
      "username": "sarahjohnson",
      "avatar": "https://storage.example.com/avatars/uuid.jpg",
      "is_verified": true,
      "is_following": true
    },
    "content": "What an incredible experience at the corporate gala last night!",
    "media": [
      {
        "id": "uuid-string",
        "type": "image",
        "url": "https://storage.example.com/posts/uuid-1.jpg",
        "thumbnail_url": "https://storage.example.com/posts/uuid-1-thumb.jpg",
        "width": 1920,
        "height": 1080,
        "blurhash": "LGF5]+Yk^6#M@-5c,1J5@[or[Q6."
      }
    ],
    "event": {
      "id": "uuid-string",
      "title": "Annual Corporate Gala 2024",
      "event_type": {
        "id": "uuid-string",
        "name": "Corporate",
        "icon": "briefcase"
      }
    },
    "tagged_users": [
      {
        "id": "uuid-string",
        "username": "michaelchen",
        "avatar": "https://storage.example.com/avatars/uuid.jpg",
        "first_name": "Michael",
        "last_name": "Chen"
      }
    ],
    "location": {
      "name": "Kempinski Hotel",
      "city": "Nairobi",
      "country": "Kenya",
      "latitude": -1.2921,
      "longitude": 36.8219
    },
    "glow_count": 156,
    "echo_count": 23,
    "comment_count": 45,
    "share_count": 12,
    "has_glowed": true,
    "has_echoed": false,
    "has_saved": false,
    "is_pinned": false,
    "privacy": "public",
    "created_at": "2024-06-24T20:30:00Z",
    "updated_at": "2024-06-24T20:30:00Z"
  }
}

Response 404:
{
  "success": false,
  "message": "Post not found",
  "data": null
}

Response 403:
{
  "success": false,
  "message": "You do not have permission to view this post",
  "data": null
}
```

### 14.3 Create Post

```
POST /posts
Authorization: Bearer {token}
Content-Type: multipart/form-data

Form Fields:
- content (optional): string, max 2000 characters (required if no images)
- images (optional): files, max 10 image files, each max 10MB
  - Supported: jpg, jpeg, png, webp, gif
- location (optional): string, location name (reverse geocoded)
- visibility (optional): string, enum "public" | "circle", default "public"
  - "public": Visible to everyone
  - "circle": Visible only to the user's circle members

Response 201:
{
  "success": true,
  "message": "Post created successfully",
  "data": {
    "id": "uuid-string",
    "author": {
      "id": "uuid-string",
      "name": "John Doe",
      "username": "johndoe",
      "avatar": "https://storage.example.com/avatars/uuid.jpg"
    },
    "content": "Just created my first post on Nuru! 🎉",
    "images": [
      "https://storage.example.com/posts/uuid.jpg"
    ],
    "location": "Dar es Salaam",
    "visibility": "public",
    "glow_count": 0,
    "echo_count": 0,
    "spark_count": 0,
    "comment_count": 0,
    "has_glowed": false,
    "has_echoed": false,
    "is_pinned": false,
    "created_at": "2025-02-10T12:00:00Z"
  }
}

Response 400:
{
  "success": false,
  "message": "Validation failed",
  "data": {
    "errors": {
      "content": "Content or media is required",
      "media": "Maximum 10 files allowed"
    }
  }
}
```

### 14.4 Update Post

```
PUT /posts/:postId
Authorization: Bearer {token}
Content-Type: application/json

Path Parameters:
- postId (required): UUID of the post

Request Body:
{
  "content": "Updated post content here",   // optional
  "visibility": "circle"                     // optional, "public" | "circle"
}

Note: Media cannot be updated. To change media, delete and recreate the post.
Visibility "circle" restricts the post to users who have the author in their circle.
Visibility "public" makes the post visible to everyone.

Response 200:
{
  "success": true,
  "message": "Post updated successfully",
  "data": {
    "id": "uuid-string",
    "content": "Updated post content here",
    "visibility": "circle",
    "glow_count": 5,
    "echo_count": 2,
    "...": "full post object"
  }
}

Response 404:
{
  "success": false,
  "message": "Post not found"
}
```

### 14.5 Delete Post

```
DELETE /posts/:postId
Authorization: Bearer {token}

Path Parameters:
- postId (required): UUID of the post

Response 200:
{
  "success": true,
  "message": "Post deleted successfully",
  "data": null
}

Response 403:
{
  "success": false,
  "message": "You can only delete your own posts",
  "data": null
}
```

### 14.6 Glow (Like) Post

```
POST /posts/:postId/glow
Authorization: Bearer {token}

Path Parameters:
- postId (required): UUID of the post

Response 200:
{
  "success": true,
  "message": "Post glowed successfully",
  "data": {
    "glow_id": "uuid-string",
    "post_id": "uuid-string",
    "user_id": "uuid-string",
    "created_at": "2024-06-25T12:30:00Z"
  }
}

Response 400:
{
  "success": false,
  "message": "You have already glowed this post",
  "data": null
}
```

### 14.7 Remove Glow from Post

```
DELETE /posts/:postId/glow
Authorization: Bearer {token}

Path Parameters:
- postId (required): UUID of the post

Response 200:
{
  "success": true,
  "message": "Glow removed successfully",
  "data": null
}
```

### 14.8 Get Post Glows

```
GET /posts/:postId/glows
Authorization: Bearer {token} (optional)

Path Parameters:
- postId (required): UUID of the post

Query Parameters:
- page (optional): integer, default 1
- limit (optional): integer, default 20, max 50

Response 200:
{
  "success": true,
  "message": "Post glows retrieved successfully",
  "data": {
    "glows": [
      {
        "id": "uuid-string",
        "user": {
          "id": "uuid-string",
          "first_name": "Alice",
          "last_name": "Johnson",
          "username": "alicejohnson",
          "avatar": "https://storage.example.com/avatars/uuid.jpg",
          "is_following": true
        },
        "created_at": "2024-06-25T12:30:00Z"
      }
    ],
    "pagination": {
      "current_page": 1,
      "per_page": 20,
      "total_items": 156,
      "total_pages": 8,
      "has_next": true,
      "has_previous": false
    }
  }
}
```

### 14.9 Echo (Repost) Post

```
POST /posts/:postId/echo
Authorization: Bearer {token}
Content-Type: application/json

Path Parameters:
- postId (required): UUID of the post

Request Body:
{
  "comment": "This is amazing! Everyone should see this"
}

- comment (optional): string, max 500 characters

Response 201:
{
  "success": true,
  "message": "Post echoed successfully",
  "data": {
    "echo_id": "uuid-string",
    "original_post_id": "uuid-string",
    "echoed_by": {
      "id": "uuid-string",
      "username": "johndoe"
    },
    "comment": "This is amazing! Everyone should see this",
    "created_at": "2024-06-25T13:00:00Z"
  }
}

Response 400:
{
  "success": false,
  "message": "You have already echoed this post",
  "data": null
}
```

### 14.10 Remove Echo

```
DELETE /posts/:postId/echo
Authorization: Bearer {token}

Path Parameters:
- postId (required): UUID of the post

Response 200:
{
  "success": true,
  "message": "Echo removed successfully",
  "data": null
}
```

### 14.11 Get Post Comments

```
GET /posts/:postId/comments
Authorization: Bearer {token} (optional)

Path Parameters:
- postId (required): UUID of the post

Query Parameters:
- page (optional): integer, default 1
- limit (optional): integer, default 20, max 50
- sort (optional): string, one of "newest", "oldest", "popular", default "newest"
- parent_id (optional): UUID, get replies to specific comment

Response 200:
{
  "success": true,
  "message": "Comments retrieved successfully",
  "data": {
    "comments": [
      {
        "id": "uuid-string",
        "author": {
          "id": "uuid-string",
          "name": "Alice Johnson",
          "username": "alicejohnson",
          "avatar": "https://storage.example.com/avatars/uuid.jpg"
        },
        "content": "This looks absolutely stunning! Where was this venue?",
        "glow_count": 12,
        "reply_count": 3,
        "has_glowed": false,
        "is_edited": false,
        "is_pinned": false,
        "parent_id": null,
        "replies_preview": [
          {
            "id": "uuid-string",
            "author": {
              "id": "uuid-string",
              "name": "Sarah Johnson",
              "username": "sarahjohnson",
              "avatar": "https://storage.example.com/avatars/uuid.jpg"
            },
            "content": "Thank you! It was at Kempinski Hotel 😊",
            "glow_count": 2,
            "reply_count": 0,
            "has_glowed": true,
            "is_edited": false,
            "parent_id": "uuid-string",
            "created_at": "2024-06-24T21:00:00Z",
            "updated_at": "2024-06-24T21:00:00Z"
          }
        ],
        "created_at": "2024-06-24T20:45:00Z",
        "updated_at": "2024-06-24T20:45:00Z"
      }
    ],
    "pagination": {
      "current_page": 1,
      "per_page": 20,
      "total_items": 45,
      "total_pages": 3,
      "has_next": true,
      "has_previous": false
    }
  }
}

Notes:
- Without `parent_id` query param, returns only top-level comments (where parent_comment_id IS NULL)
- With `parent_id` query param, returns replies to that specific comment
- `replies_preview` contains the first 2 replies for top-level comments
- `has_glowed` indicates whether the current user has glowed this comment
- Use 14.17 (Get Comment Replies) to load all replies for a comment
```

### 14.12 Create Comment

```
POST /posts/:postId/comments
Authorization: Bearer {token}
Content-Type: multipart/form-data

Path Parameters:
- postId (required): UUID of the post

Form Fields:
- content (required if no media): string, max 1000 characters
- media (optional): file, max 1 file, max 10MB
  - Images: jpg, jpeg, png, webp, gif
- parent_id (optional): UUID, for reply to another comment
- mentioned_user_ids (optional): JSON array of user UUIDs

Response 201:
{
  "success": true,
  "message": "Comment added successfully",
  "data": {
    "id": "uuid-string",
    "user": {
      "id": "uuid-string",
      "first_name": "John",
      "last_name": "Doe",
      "username": "johndoe",
      "avatar": "https://storage.example.com/avatars/uuid.jpg",
      "is_verified": false
    },
    "content": "Great event! Wish I could have been there.",
    "media": null,
    "glow_count": 0,
    "reply_count": 0,
    "has_glowed": false,
    "is_edited": false,
    "parent_id": null,
    "created_at": "2024-06-25T14:30:00Z",
    "updated_at": "2024-06-25T14:30:00Z"
  }
}
```

### 14.13 Update Comment

```
PUT /posts/:postId/comments/:commentId
Authorization: Bearer {token}
Content-Type: application/json

Path Parameters:
- postId (required): UUID of the post
- commentId (required): UUID of the comment

Request Body:
{
  "content": "Updated comment text"
}

Response 200:
{
  "success": true,
  "message": "Comment updated successfully",
  "data": {
    "id": "uuid-string",
    "content": "Updated comment text",
    "is_edited": true,
    "updated_at": "2024-06-25T15:00:00Z"
  }
}
```

### 14.14 Delete Comment

```
DELETE /posts/:postId/comments/:commentId
Authorization: Bearer {token}

Path Parameters:
- postId (required): UUID of the post
- commentId (required): UUID of the comment

Response 200:
{
  "success": true,
  "message": "Comment deleted successfully",
  "data": null
}
```

### 14.15 Glow Comment

```
POST /posts/:postId/comments/:commentId/glow
Authorization: Bearer {token}

Path Parameters:
- postId (required): UUID of the post
- commentId (required): UUID of the comment

Response 200:
{
  "success": true,
  "message": "Comment glowed successfully",
  "data": {
    "glow_id": "uuid-string",
    "created_at": "2024-06-25T15:30:00Z"
  }
}
```

### 14.16 Remove Comment Glow

```
DELETE /posts/:postId/comments/:commentId/glow
Authorization: Bearer {token}

Path Parameters:
- postId (required): UUID of the post
- commentId (required): UUID of the comment

Response 200:
{
  "success": true,
  "message": "Comment glow removed successfully",
  "data": null
}
```

### 14.17 Get Comment Replies (Threaded Echoes)

```
GET /posts/:postId/comments/:commentId/replies
Authorization: Bearer {token}

Path Parameters:
- postId (required): UUID of the post
- commentId (required): UUID of the parent comment

Query Parameters:
- page (optional): integer, default 1
- limit (optional): integer, default 20

Response 200:
{
  "success": true,
  "message": "Replies retrieved",
  "data": {
    "comments": [
      {
        "id": "uuid-string",
        "content": "I agree, great venue!",
        "author": {
          "id": "uuid-string",
          "name": "Sarah Johnson",
          "username": "sarahjohnson",
          "avatar": "https://storage.example.com/avatars/uuid.jpg"
        },
        "glow_count": 3,
        "reply_count": 0,
        "has_glowed": false,
        "is_edited": false,
        "parent_id": "uuid-string",
        "created_at": "2024-06-25T15:00:00Z",
        "updated_at": "2024-06-25T15:00:00Z"
      }
    ],
    "pagination": {
      "current_page": 1,
      "per_page": 20,
      "total_items": 5,
      "total_pages": 1,
      "has_next": false,
      "has_previous": false
    }
  }
}

Notes:
- Returns replies sorted by oldest first (chronological thread order)
- Each reply includes the `parent_id` referencing the parent comment
- Replies can also be glowed using the existing 14.15/14.16 endpoints
- Creating a reply uses the existing 14.12 endpoint with `parent_id` in the body
```

### 14.18 Save Post

```
POST /posts/:postId/save
Authorization: Bearer {token}

Path Parameters:
- postId (required): UUID of the post

Request Body (optional):
{
  "collection_id": "uuid-string"
}

Response 200:
{
  "success": true,
  "message": "Post saved successfully",
  "data": {
    "save_id": "uuid-string",
    "post_id": "uuid-string",
    "collection_id": "uuid-string",
    "created_at": "2024-06-25T16:00:00Z"
  }
}
```

### 14.18 Unsave Post

```
DELETE /posts/:postId/save
Authorization: Bearer {token}

Path Parameters:
- postId (required): UUID of the post

Response 200:
{
  "success": true,
  "message": "Post unsaved successfully",
  "data": null
}
```

### 14.19 Get Saved Posts

```
GET /posts/saved
Authorization: Bearer {token}

Query Parameters:
- page (optional): integer, default 1
- limit (optional): integer, default 20, max 50
- collection_id (optional): UUID, filter by collection

Response 200:
{
  "success": true,
  "message": "Saved posts retrieved successfully",
  "data": {
    "posts": [
      {
        "id": "uuid-string",
        "user": {
          "id": "uuid-string",
          "first_name": "Sarah",
          "last_name": "Johnson",
          "username": "sarahjohnson",
          "avatar": "https://storage.example.com/avatars/uuid.jpg"
        },
        "content": "Saved post content...",
        "media": [
          {
            "id": "uuid-string",
            "type": "image",
            "url": "https://storage.example.com/posts/uuid.jpg",
            "thumbnail_url": "https://storage.example.com/posts/uuid-thumb.jpg"
          }
        ],
        "glow_count": 234,
        "comment_count": 45,
        "saved_at": "2024-06-24T10:00:00Z",
        "created_at": "2024-06-20T18:30:00Z"
      }
    ],
    "pagination": {
      "current_page": 1,
      "per_page": 20,
      "total_items": 50,
      "total_pages": 3,
      "has_next": true,
      "has_previous": false
    }
  }
}
```

> **Database Note:** The saved posts feature uses the `user_feed_saved` table with columns:
>
> - `id` (UUID, PK), `user_id` (UUID, FK → users.id), `feed_id` (UUID, FK → user_feeds.id), `created_at` (timestamp)
> - Unique constraint on `(user_id, feed_id)` named `uq_feed_saved`
>
> **CREATE TABLE SQL:**
>
> ```sql
> CREATE TABLE IF NOT EXISTS user_feed_saved (
>   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
>   user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
>   feed_id UUID NOT NULL REFERENCES user_feeds(id) ON DELETE CASCADE,
>   created_at TIMESTAMPTZ DEFAULT now(),
>   CONSTRAINT uq_feed_saved UNIQUE (user_id, feed_id)
> );
> ```

### 14.20 Report Post

```
POST /posts/:postId/report
Authorization: Bearer {token}
Content-Type: application/json

Path Parameters:
- postId (required): UUID of the post

Request Body:
{
  "reason": "inappropriate_content",
  "description": "Contains offensive language targeting a specific group"
}

Reason Options:
- "spam"
- "inappropriate_content"
- "harassment"
- "violence"
- "hate_speech"
- "misinformation"
- "intellectual_property"
- "other"

Response 200:
{
  "success": true,
  "message": "Report submitted successfully",
  "data": {
    "report_id": "uuid-string",
    "status": "pending",
    "created_at": "2024-06-25T17:00:00Z"
  }
}
```

### 14.21 Pin Post (on own profile)

```
POST /posts/:postId/pin
Authorization: Bearer {token}

Path Parameters:
- postId (required): UUID of the post

Response 200:
{
  "success": true,
  "message": "Post pinned to profile",
  "data": {
    "post_id": "uuid-string",
    "pinned_at": "2024-06-25T17:30:00Z"
  }
}

Response 400:
{
  "success": false,
  "message": "You can only pin up to 3 posts",
  "data": null
}
```

### 14.22 Unpin Post

```
DELETE /posts/:postId/pin
Authorization: Bearer {token}

Path Parameters:
- postId (required): UUID of the post

Response 200:
{
  "success": true,
  "message": "Post unpinned successfully",
  "data": null
}
```

---

## MODULE 15: MOMENTS (Stories)

### 15.1 Get Moments Feed

```
GET /moments
Authorization: Bearer {token}

Query Parameters:
- page (optional): integer, default 1
- limit (optional): integer, default 20, max 50

Response 200:
{
  "success": true,
  "message": "Moments retrieved successfully",
  "data": {
    "moments": [
      {
        "user": {
          "id": "uuid-string",
          "first_name": "Sarah",
          "last_name": "Johnson",
          "username": "sarahjohnson",
          "avatar": "https://storage.example.com/avatars/uuid.jpg",
          "is_verified": true
        },
        "has_unseen": true,
        "moment_count": 3,
        "latest_moment_at": "2024-06-25T16:00:00Z",
        "preview": {
          "type": "image",
          "thumbnail_url": "https://storage.example.com/moments/uuid-thumb.jpg"
        }
      },
      {
        "user": {
          "id": "uuid-string",
          "first_name": "Michael",
          "last_name": "Chen",
          "username": "michaelchen",
          "avatar": "https://storage.example.com/avatars/uuid.jpg",
          "is_verified": false
        },
        "has_unseen": true,
        "moment_count": 5,
        "latest_moment_at": "2024-06-25T14:30:00Z",
        "preview": {
          "type": "video",
          "thumbnail_url": "https://storage.example.com/moments/uuid-thumb.jpg"
        }
      },
      {
        "user": {
          "id": "uuid-string",
          "first_name": "Emily",
          "last_name": "Davis",
          "username": "emilydavis",
          "avatar": "https://storage.example.com/avatars/uuid.jpg",
          "is_verified": false
        },
        "has_unseen": false,
        "moment_count": 2,
        "latest_moment_at": "2024-06-25T10:00:00Z",
        "preview": {
          "type": "image",
          "thumbnail_url": "https://storage.example.com/moments/uuid-thumb.jpg"
        }
      }
    ],
    "my_moments": {
      "has_active": true,
      "moment_count": 2,
      "latest_moment_at": "2024-06-25T12:00:00Z"
    },
    "pagination": {
      "current_page": 1,
      "per_page": 20,
      "total_items": 45,
      "total_pages": 3,
      "has_next": true,
      "has_previous": false
    }
  }
}
```

### 15.2 Get User Moments

```
GET /moments/user/:userId
Authorization: Bearer {token}

Path Parameters:
- userId (required): UUID of the user

Response 200:
{
  "success": true,
  "message": "User moments retrieved successfully",
  "data": {
    "user": {
      "id": "uuid-string",
      "first_name": "Sarah",
      "last_name": "Johnson",
      "username": "sarahjohnson",
      "avatar": "https://storage.example.com/avatars/uuid.jpg",
      "is_verified": true
    },
    "moments": [
      {
        "id": "uuid-string",
        "type": "image",
        "media_url": "https://storage.example.com/moments/uuid.jpg",
        "thumbnail_url": "https://storage.example.com/moments/uuid-thumb.jpg",
        "width": 1080,
        "height": 1920,
        "duration": null,
        "caption": "Getting ready for the event! ✨",
        "caption_position": {
          "x": 50,
          "y": 80
        },
        "background_color": null,
        "text_color": "#FFFFFF",
        "stickers": [
          {
            "id": "uuid-string",
            "type": "poll",
            "position": {
              "x": 50,
              "y": 60
            },
            "data": {
              "question": "Which outfit should I wear?",
              "options": [
                {
                  "id": "1",
                  "text": "Blue dress",
                  "vote_count": 45,
                  "vote_percentage": 60
                },
                {
                  "id": "2",
                  "text": "Red dress",
                  "vote_count": 30,
                  "vote_percentage": 40
                }
              ],
              "total_votes": 75,
              "user_vote": "1"
            }
          }
        ],
        "music": null,
        "location": {
          "name": "Nairobi, Kenya"
        },
        "event": {
          "id": "uuid-string",
          "title": "Annual Corporate Gala"
        },
        "view_count": 234,
        "reply_count": 12,
        "is_seen": true,
        "can_reply": true,
        "created_at": "2024-06-25T16:00:00Z",
        "expires_at": "2024-06-26T16:00:00Z"
      },
      {
        "id": "uuid-string",
        "type": "video",
        "media_url": "https://storage.example.com/moments/uuid.mp4",
        "thumbnail_url": "https://storage.example.com/moments/uuid-thumb.jpg",
        "width": 1080,
        "height": 1920,
        "duration": 15,
        "caption": null,
        "caption_position": null,
        "background_color": null,
        "text_color": null,
        "stickers": [],
        "music": {
          "id": "uuid-string",
          "title": "Happy",
          "artist": "Pharrell Williams",
          "start_time": 30,
          "duration": 15
        },
        "location": null,
        "event": null,
        "view_count": 189,
        "reply_count": 5,
        "is_seen": true,
        "can_reply": true,
        "created_at": "2024-06-25T14:00:00Z",
        "expires_at": "2024-06-26T14:00:00Z"
      }
    ]
  }
}
```

### 15.3 Get My Moments

```
GET /moments/me
Authorization: Bearer {token}

Response 200:
{
  "success": true,
  "message": "My moments retrieved successfully",
  "data": {
    "moments": [
      {
        "id": "uuid-string",
        "type": "image",
        "media_url": "https://storage.example.com/moments/uuid.jpg",
        "thumbnail_url": "https://storage.example.com/moments/uuid-thumb.jpg",
        "width": 1080,
        "height": 1920,
        "caption": "My moment caption",
        "view_count": 156,
        "reply_count": 8,
        "viewers": [
          {
            "id": "uuid-string",
            "username": "viewer1",
            "avatar": "https://storage.example.com/avatars/uuid.jpg",
            "viewed_at": "2024-06-25T16:30:00Z"
          }
        ],
        "created_at": "2024-06-25T12:00:00Z",
        "expires_at": "2024-06-26T12:00:00Z"
      }
    ],
    "total_views_today": 450,
    "total_replies_today": 23
  }
}
```

### 15.4 Create Moment

```
POST /moments
Authorization: Bearer {token}
Content-Type: multipart/form-data

Form Fields:
- media (required): file, max 1 file
  - Images: jpg, jpeg, png, webp, max 10MB
  - Videos: mp4, mov, max 30 seconds, max 50MB
- caption (optional): string, max 200 characters
- caption_position_x (optional): integer, 0-100 (percentage)
- caption_position_y (optional): integer, 0-100 (percentage)
- text_color (optional): string, hex color code
- event_id (optional): UUID
- location_name (optional): string, max 100 characters
- stickers (optional): JSON array of sticker objects
- music_id (optional): UUID of music track
- music_start_time (optional): integer, seconds
- privacy (optional): string, one of "followers", "close_friends", default "followers"
- allow_replies (optional): boolean, default true

Sticker Object Format:
{
  "type": "poll",
  "position": { "x": 50, "y": 60 },
  "data": {
    "question": "Which one?",
    "options": ["Option A", "Option B"]
  }
}

Sticker Types:
- "poll": question with 2-4 options
- "question": open question for replies
- "countdown": event countdown with date
- "mention": @username mention
- "hashtag": #hashtag
- "location": location tag
- "link": URL link (verified accounts only)
- "emoji_slider": emoji with slider for rating

Response 201:
{
  "success": true,
  "message": "Moment created successfully",
  "data": {
    "id": "uuid-string",
    "type": "image",
    "media_url": "https://storage.example.com/moments/uuid.jpg",
    "thumbnail_url": "https://storage.example.com/moments/uuid-thumb.jpg",
    "width": 1080,
    "height": 1920,
    "caption": "Just posted!",
    "caption_position": {
      "x": 50,
      "y": 80
    },
    "stickers": [],
    "view_count": 0,
    "reply_count": 0,
    "created_at": "2024-06-25T17:00:00Z",
    "expires_at": "2024-06-26T17:00:00Z"
  }
}
```

### 15.5 Delete Moment

```
DELETE /moments/:momentId
Authorization: Bearer {token}

Path Parameters:
- momentId (required): UUID of the moment

Response 200:
{
  "success": true,
  "message": "Moment deleted successfully",
  "data": null
}
```

### 15.6 Mark Moment as Seen

```
POST /moments/:momentId/seen
Authorization: Bearer {token}

Path Parameters:
- momentId (required): UUID of the moment

Response 200:
{
  "success": true,
  "message": "Moment marked as seen",
  "data": {
    "moment_id": "uuid-string",
    "seen_at": "2024-06-25T17:30:00Z"
  }
}
```

### 15.7 Get Moment Viewers

```
GET /moments/:momentId/viewers
Authorization: Bearer {token}

Path Parameters:
- momentId (required): UUID of the moment (must be own moment)

Query Parameters:
- page (optional): integer, default 1
- limit (optional): integer, default 50, max 100

Response 200:
{
  "success": true,
  "message": "Moment viewers retrieved successfully",
  "data": {
    "viewers": [
      {
        "id": "uuid-string",
        "first_name": "Alice",
        "last_name": "Johnson",
        "username": "alicejohnson",
        "avatar": "https://storage.example.com/avatars/uuid.jpg",
        "is_following": true,
        "viewed_at": "2024-06-25T17:30:00Z"
      }
    ],
    "pagination": {
      "current_page": 1,
      "per_page": 50,
      "total_items": 234,
      "total_pages": 5,
      "has_next": true,
      "has_previous": false
    }
  }
}

Response 403:
{
  "success": false,
  "message": "You can only view viewers of your own moments",
  "data": null
}
```

### 15.8 Reply to Moment

```
POST /moments/:momentId/replies
Authorization: Bearer {token}
Content-Type: multipart/form-data

Path Parameters:
- momentId (required): UUID of the moment

Form Fields:
- content (optional): string, max 500 characters
- media (optional): file, max 1 file
  - Images: jpg, jpeg, png, webp, max 5MB
  - Videos: mp4, mov, max 10 seconds, max 20MB

At least one of content or media is required.

Response 201:
{
  "success": true,
  "message": "Reply sent successfully",
  "data": {
    "reply_id": "uuid-string",
    "moment_id": "uuid-string",
    "content": "This looks amazing!",
    "media": null,
    "created_at": "2024-06-25T18:00:00Z"
  }
}

Response 403:
{
  "success": false,
  "message": "This moment does not allow replies",
  "data": null
}
```

### 15.9 Get Moment Replies (for moment owner)

```
GET /moments/:momentId/replies
Authorization: Bearer {token}

Path Parameters:
- momentId (required): UUID of the moment (must be own moment)

Query Parameters:
- page (optional): integer, default 1
- limit (optional): integer, default 20, max 50

Response 200:
{
  "success": true,
  "message": "Moment replies retrieved successfully",
  "data": {
    "replies": [
      {
        "id": "uuid-string",
        "user": {
          "id": "uuid-string",
          "first_name": "Bob",
          "last_name": "Williams",
          "username": "bobwilliams",
          "avatar": "https://storage.example.com/avatars/uuid.jpg"
        },
        "content": "Love this! Where was this taken?",
        "media": null,
        "created_at": "2024-06-25T18:00:00Z"
      }
    ],
    "pagination": {
      "current_page": 1,
      "per_page": 20,
      "total_items": 12,
      "total_pages": 1,
      "has_next": false,
      "has_previous": false
    }
  }
}
```

### 15.10 Vote on Poll Sticker

```
POST /moments/:momentId/poll/:stickerId/vote
Authorization: Bearer {token}
Content-Type: application/json

Path Parameters:
- momentId (required): UUID of the moment
- stickerId (required): UUID of the poll sticker

Request Body:
{
  "option_id": "1"
}

Response 200:
{
  "success": true,
  "message": "Vote recorded successfully",
  "data": {
    "poll_results": {
      "options": [
        {
          "id": "1",
          "text": "Blue dress",
          "vote_count": 46,
          "vote_percentage": 60.5
        },
        {
          "id": "2",
          "text": "Red dress",
          "vote_count": 30,
          "vote_percentage": 39.5
        }
      ],
      "total_votes": 76,
      "user_vote": "1"
    }
  }
}
```

### 15.11 Highlight Moment

```
POST /moments/:momentId/highlight
Authorization: Bearer {token}
Content-Type: application/json

Path Parameters:
- momentId (required): UUID of the moment

Request Body:
{
  "highlight_id": "uuid-string"
}

- highlight_id (optional): UUID, add to existing highlight. If not provided, creates new highlight.

Response 200:
{
  "success": true,
  "message": "Moment added to highlight",
  "data": {
    "highlight_id": "uuid-string",
    "moment_id": "uuid-string"
  }
}
```

### 15.12 Get Highlights

```
GET /users/:userId/highlights
Authorization: Bearer {token} (optional)

Path Parameters:
- userId (required): UUID of the user

Response 200:
{
  "success": true,
  "message": "Highlights retrieved successfully",
  "data": {
    "highlights": [
      {
        "id": "uuid-string",
        "title": "Wedding Season",
        "cover_image": "https://storage.example.com/highlights/uuid.jpg",
        "moment_count": 15,
        "created_at": "2024-05-01T10:00:00Z",
        "updated_at": "2024-06-20T14:00:00Z"
      },
      {
        "id": "uuid-string",
        "title": "Corporate Events",
        "cover_image": "https://storage.example.com/highlights/uuid.jpg",
        "moment_count": 8,
        "created_at": "2024-03-15T12:00:00Z",
        "updated_at": "2024-06-10T09:00:00Z"
      }
    ]
  }
}
```

### 15.13 Create Highlight

```
POST /highlights
Authorization: Bearer {token}
Content-Type: multipart/form-data

Form Fields:
- title (required): string, max 50 characters
- cover_image (optional): file, max 5MB, jpg, jpeg, png, webp
- moment_ids (required): JSON array of moment UUIDs

Response 201:
{
  "success": true,
  "message": "Highlight created successfully",
  "data": {
    "id": "uuid-string",
    "title": "My New Highlight",
    "cover_image": "https://storage.example.com/highlights/uuid.jpg",
    "moment_count": 5,
    "created_at": "2024-06-25T18:00:00Z"
  }
}
```

### 15.14 Update Highlight

```
PUT /highlights/:highlightId
Authorization: Bearer {token}
Content-Type: multipart/form-data

Path Parameters:
- highlightId (required): UUID of the highlight

Form Fields:
- title (optional): string, max 50 characters
- cover_image (optional): file, max 5MB

Response 200:
{
  "success": true,
  "message": "Highlight updated successfully",
  "data": {
    "id": "uuid-string",
    "title": "Updated Highlight Title",
    "cover_image": "https://storage.example.com/highlights/uuid.jpg",
    "updated_at": "2024-06-25T19:00:00Z"
  }
}
```

### 15.15 Delete Highlight

```
DELETE /highlights/:highlightId
Authorization: Bearer {token}

Path Parameters:
- highlightId (required): UUID of the highlight

Response 200:
{
  "success": true,
  "message": "Highlight deleted successfully",
  "data": null
}
```

### 15.16 Get Highlight Moments

```
GET /highlights/:highlightId/moments
Authorization: Bearer {token} (optional)

Path Parameters:
- highlightId (required): UUID of the highlight

Response 200:
{
  "success": true,
  "message": "Highlight moments retrieved successfully",
  "data": {
    "highlight": {
      "id": "uuid-string",
      "title": "Wedding Season",
      "user": {
        "id": "uuid-string",
        "username": "sarahjohnson",
        "avatar": "https://storage.example.com/avatars/uuid.jpg"
      }
    },
    "moments": [
      {
        "id": "uuid-string",
        "type": "image",
        "media_url": "https://storage.example.com/moments/uuid.jpg",
        "thumbnail_url": "https://storage.example.com/moments/uuid-thumb.jpg",
        "caption": "Beautiful ceremony",
        "created_at": "2024-05-15T14:00:00Z"
      }
    ]
  }
}
```

### 15.17 Remove Moment from Highlight

```
DELETE /highlights/:highlightId/moments/:momentId
Authorization: Bearer {token}

Path Parameters:
- highlightId (required): UUID of the highlight
- momentId (required): UUID of the moment

Response 200:
{
  "success": true,
  "message": "Moment removed from highlight",
  "data": null
}
```

---

## MODULE 16: SOCIAL / CIRCLES

### 16.1 Get My Circles

```
GET /circles
Authorization: Bearer {token}

Query Parameters:
- page (optional): integer, default 1
- limit (optional): integer, default 20, max 50
- type (optional): string, one of "owned", "member", "all"

Response 200:
{
  "success": true,
  "message": "Circles retrieved successfully",
  "data": {
    "circles": [
      {
        "id": "uuid-string",
        "name": "College Friends",
        "description": "My university classmates from 2015",
        "cover_image": "https://storage.example.com/circles/uuid.jpg",
        "privacy": "private",
        "member_count": 25,
        "post_count": 156,
        "is_owner": true,
        "role": "owner",
        "last_activity_at": "2024-06-25T16:00:00Z",
        "unread_count": 3,
        "members_preview": [
          {
            "id": "uuid-string",
            "avatar": "https://storage.example.com/avatars/uuid.jpg"
          },
          {
            "id": "uuid-string",
            "avatar": "https://storage.example.com/avatars/uuid.jpg"
          },
          {
            "id": "uuid-string",
            "avatar": "https://storage.example.com/avatars/uuid.jpg"
          }
        ],
        "created_at": "2024-01-15T10:00:00Z"
      },
      {
        "id": "uuid-string",
        "name": "Wedding Planning Group",
        "description": "For Sarah's wedding preparations",
        "cover_image": "https://storage.example.com/circles/uuid.jpg",
        "privacy": "private",
        "member_count": 12,
        "post_count": 89,
        "is_owner": false,
        "role": "admin",
        "last_activity_at": "2024-06-25T14:30:00Z",
        "unread_count": 0,
        "members_preview": [
          {
            "id": "uuid-string",
            "avatar": "https://storage.example.com/avatars/uuid.jpg"
          }
        ],
        "created_at": "2024-03-01T08:00:00Z"
      }
    ],
    "pagination": {
      "current_page": 1,
      "per_page": 20,
      "total_items": 8,
      "total_pages": 1,
      "has_next": false,
      "has_previous": false
    }
  }
}
```

### 16.2 Get Circle Details

```
GET /circles/:circleId
Authorization: Bearer {token}

Path Parameters:
- circleId (required): UUID of the circle

Response 200:
{
  "success": true,
  "message": "Circle retrieved successfully",
  "data": {
    "id": "uuid-string",
    "name": "College Friends",
    "description": "My university classmates from 2015. We graduated together and stay in touch!",
    "cover_image": "https://storage.example.com/circles/uuid.jpg",
    "privacy": "private",
    "join_approval_required": true,
    "member_count": 25,
    "post_count": 156,
    "event_count": 5,
    "is_owner": true,
    "role": "owner",
    "owner": {
      "id": "uuid-string",
      "first_name": "John",
      "last_name": "Doe",
      "username": "johndoe",
      "avatar": "https://storage.example.com/avatars/uuid.jpg"
    },
    "settings": {
      "allow_member_posts": true,
      "allow_member_events": true,
      "allow_member_invites": false,
      "post_approval_required": false
    },
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-06-20T12:00:00Z"
  }
}

Response 403:
{
  "success": false,
  "message": "You are not a member of this circle",
  "data": null
}
```

### 16.3 Create Circle

```
POST /circles
Authorization: Bearer {token}
Content-Type: multipart/form-data

Form Fields:
- name (required): string, 3-100 characters
- description (optional): string, max 500 characters
- cover_image (optional): file, max 5MB, jpg, jpeg, png, webp
- privacy (optional): string, one of "private", "invite_only", default "private"
- join_approval_required (optional): boolean, default true
- allow_member_posts (optional): boolean, default true
- allow_member_events (optional): boolean, default true
- allow_member_invites (optional): boolean, default false
- post_approval_required (optional): boolean, default false

Response 201:
{
  "success": true,
  "message": "Circle created successfully",
  "data": {
    "id": "uuid-string",
    "name": "New Circle Name",
    "description": "Description of the circle",
    "cover_image": "https://storage.example.com/circles/uuid.jpg",
    "privacy": "private",
    "member_count": 1,
    "is_owner": true,
    "role": "owner",
    "created_at": "2024-06-25T18:00:00Z"
  }
}
```

### 16.4 Update Circle

```
PUT /circles/:circleId
Authorization: Bearer {token}
Content-Type: multipart/form-data

Path Parameters:
- circleId (required): UUID of the circle

Form Fields:
- name (optional): string, 3-100 characters
- description (optional): string, max 500 characters
- cover_image (optional): file, max 5MB
- privacy (optional): string
- join_approval_required (optional): boolean
- allow_member_posts (optional): boolean
- allow_member_events (optional): boolean
- allow_member_invites (optional): boolean
- post_approval_required (optional): boolean

Response 200:
{
  "success": true,
  "message": "Circle updated successfully",
  "data": {
    "id": "uuid-string",
    "name": "Updated Circle Name",
    "description": "Updated description",
    "updated_at": "2024-06-25T19:00:00Z"
  }
}

Response 403:
{
  "success": false,
  "message": "Only circle owner or admin can update settings",
  "data": null
}
```

### 16.5 Delete Circle

```
DELETE /circles/:circleId
Authorization: Bearer {token}

Path Parameters:
- circleId (required): UUID of the circle

Response 200:
{
  "success": true,
  "message": "Circle deleted successfully",
  "data": null
}

Response 403:
{
  "success": false,
  "message": "Only the circle owner can delete the circle",
  "data": null
}
```

### 16.6 Get Circle Members

```
GET /circles/:circleId/members
Authorization: Bearer {token}

Path Parameters:
- circleId (required): UUID of the circle

Query Parameters:
- page (optional): integer, default 1
- limit (optional): integer, default 20, max 50
- role (optional): string, one of "owner", "admin", "member"
- search (optional): string, search by name or username

Response 200:
{
  "success": true,
  "message": "Circle members retrieved successfully",
  "data": {
    "members": [
      {
        "id": "uuid-string",
        "user": {
          "id": "uuid-string",
          "first_name": "John",
          "last_name": "Doe",
          "username": "johndoe",
          "avatar": "https://storage.example.com/avatars/uuid.jpg",
          "is_verified": false
        },
        "role": "owner",
        "joined_at": "2024-01-15T10:00:00Z"
      },
      {
        "id": "uuid-string",
        "user": {
          "id": "uuid-string",
          "first_name": "Alice",
          "last_name": "Johnson",
          "username": "alicejohnson",
          "avatar": "https://storage.example.com/avatars/uuid.jpg",
          "is_verified": false
        },
        "role": "admin",
        "joined_at": "2024-01-16T14:00:00Z"
      },
      {
        "id": "uuid-string",
        "user": {
          "id": "uuid-string",
          "first_name": "Bob",
          "last_name": "Williams",
          "username": "bobwilliams",
          "avatar": "https://storage.example.com/avatars/uuid.jpg",
          "is_verified": false
        },
        "role": "member",
        "joined_at": "2024-02-01T09:00:00Z"
      }
    ],
    "pagination": {
      "current_page": 1,
      "per_page": 20,
      "total_items": 25,
      "total_pages": 2,
      "has_next": true,
      "has_previous": false
    }
  }
}
```

### 16.7 Invite Members to Circle

```
POST /circles/:circleId/invite
Authorization: Bearer {token}
Content-Type: application/json

Path Parameters:
- circleId (required): UUID of the circle

Request Body:
{
  "user_ids": ["uuid-1", "uuid-2", "uuid-3"],
  "message": "Hey! Join our circle for event planning."
}

- user_ids (required): array of user UUIDs, max 50
- message (optional): string, max 500 characters

Response 200:
{
  "success": true,
  "message": "Invitations sent successfully",
  "data": {
    "invited_count": 3,
    "already_member_count": 0,
    "already_invited_count": 0,
    "invitations": [
      {
        "id": "uuid-string",
        "user_id": "uuid-1",
        "status": "pending",
        "invited_at": "2024-06-25T18:00:00Z"
      },
      {
        "id": "uuid-string",
        "user_id": "uuid-2",
        "status": "pending",
        "invited_at": "2024-06-25T18:00:00Z"
      },
      {
        "id": "uuid-string",
        "user_id": "uuid-3",
        "status": "pending",
        "invited_at": "2024-06-25T18:00:00Z"
      }
    ]
  }
}

Response 403:
{
  "success": false,
  "message": "You do not have permission to invite members",
  "data": null
}
```

### 16.8 Get Circle Invitations (Pending)

```
GET /circles/:circleId/invitations
Authorization: Bearer {token}

Path Parameters:
- circleId (required): UUID of the circle

Query Parameters:
- page (optional): integer, default 1
- limit (optional): integer, default 20, max 50
- status (optional): string, one of "pending", "expired", "all"

Response 200:
{
  "success": true,
  "message": "Circle invitations retrieved successfully",
  "data": {
    "invitations": [
      {
        "id": "uuid-string",
        "user": {
          "id": "uuid-string",
          "first_name": "Carol",
          "last_name": "Davis",
          "username": "caroldavis",
          "avatar": "https://storage.example.com/avatars/uuid.jpg"
        },
        "invited_by": {
          "id": "uuid-string",
          "username": "johndoe"
        },
        "message": "Join our planning circle!",
        "status": "pending",
        "invited_at": "2024-06-25T18:00:00Z",
        "expires_at": "2024-07-02T18:00:00Z"
      }
    ],
    "pagination": {
      "current_page": 1,
      "per_page": 20,
      "total_items": 5,
      "total_pages": 1,
      "has_next": false,
      "has_previous": false
    }
  }
}
```

### 16.9 Get My Circle Invitations

```
GET /circles/invitations
Authorization: Bearer {token}

Query Parameters:
- page (optional): integer, default 1
- limit (optional): integer, default 20, max 50

Response 200:
{
  "success": true,
  "message": "My circle invitations retrieved successfully",
  "data": {
    "invitations": [
      {
        "id": "uuid-string",
        "circle": {
          "id": "uuid-string",
          "name": "Wedding Planning Group",
          "cover_image": "https://storage.example.com/circles/uuid.jpg",
          "member_count": 12
        },
        "invited_by": {
          "id": "uuid-string",
          "first_name": "Sarah",
          "last_name": "Johnson",
          "username": "sarahjohnson",
          "avatar": "https://storage.example.com/avatars/uuid.jpg"
        },
        "message": "Help us plan the wedding!",
        "invited_at": "2024-06-25T14:00:00Z",
        "expires_at": "2024-07-02T14:00:00Z"
      }
    ],
    "pagination": {
      "current_page": 1,
      "per_page": 20,
      "total_items": 2,
      "total_pages": 1,
      "has_next": false,
      "has_previous": false
    }
  }
}
```

### 16.10 Respond to Circle Invitation

```
PUT /circles/invitations/:invitationId
Authorization: Bearer {token}
Content-Type: application/json

Path Parameters:
- invitationId (required): UUID of the invitation

Request Body:
{
  "action": "accept"
}

- action (required): string, one of "accept", "decline"

Response 200 (accept):
{
  "success": true,
  "message": "You have joined the circle",
  "data": {
    "circle_id": "uuid-string",
    "circle_name": "Wedding Planning Group",
    "role": "member",
    "joined_at": "2024-06-25T19:00:00Z"
  }
}

Response 200 (decline):
{
  "success": true,
  "message": "Invitation declined",
  "data": null
}
```

### 16.11 Cancel Circle Invitation

```
DELETE /circles/:circleId/invitations/:invitationId
Authorization: Bearer {token}

Path Parameters:
- circleId (required): UUID of the circle
- invitationId (required): UUID of the invitation

Response 200:
{
  "success": true,
  "message": "Invitation cancelled",
  "data": null
}
```

### 16.12 Update Member Role

```
PUT /circles/:circleId/members/:memberId/role
Authorization: Bearer {token}
Content-Type: application/json

Path Parameters:
- circleId (required): UUID of the circle
- memberId (required): UUID of the member record

Request Body:
{
  "role": "admin"
}

- role (required): string, one of "admin", "member"

Response 200:
{
  "success": true,
  "message": "Member role updated successfully",
  "data": {
    "member_id": "uuid-string",
    "user_id": "uuid-string",
    "role": "admin",
    "updated_at": "2024-06-25T19:30:00Z"
  }
}

Response 403:
{
  "success": false,
  "message": "Only circle owner can change member roles",
  "data": null
}
```

### 16.13 Remove Member from Circle

```
DELETE /circles/:circleId/members/:memberId
Authorization: Bearer {token}

Path Parameters:
- circleId (required): UUID of the circle
- memberId (required): UUID of the member record

Response 200:
{
  "success": true,
  "message": "Member removed from circle",
  "data": null
}

Response 403:
{
  "success": false,
  "message": "You do not have permission to remove members",
  "data": null
}
```

### 16.14 Leave Circle

```
DELETE /circles/:circleId/leave
Authorization: Bearer {token}

Path Parameters:
- circleId (required): UUID of the circle

Response 200:
{
  "success": true,
  "message": "You have left the circle",
  "data": null
}

Response 400:
{
  "success": false,
  "message": "Owner cannot leave the circle. Transfer ownership first or delete the circle.",
  "data": null
}
```

### 16.15 Transfer Circle Ownership

```
PUT /circles/:circleId/transfer-ownership
Authorization: Bearer {token}
Content-Type: application/json

Path Parameters:
- circleId (required): UUID of the circle

Request Body:
{
  "new_owner_id": "uuid-string"
}

Response 200:
{
  "success": true,
  "message": "Ownership transferred successfully",
  "data": {
    "new_owner": {
      "id": "uuid-string",
      "username": "alicejohnson"
    },
    "transferred_at": "2024-06-25T20:00:00Z"
  }
}

Response 400:
{
  "success": false,
  "message": "New owner must be an existing member of the circle",
  "data": null
}
```

### 16.16 Get Circle Feed/Posts

```
GET /circles/:circleId/posts
Authorization: Bearer {token}

Path Parameters:
- circleId (required): UUID of the circle

Query Parameters:
- page (optional): integer, default 1
- limit (optional): integer, default 20, max 50

Response 200:
{
  "success": true,
  "message": "Circle posts retrieved successfully",
  "data": {
    "posts": [
      {
        "id": "uuid-string",
        "user": {
          "id": "uuid-string",
          "first_name": "Alice",
          "last_name": "Johnson",
          "username": "alicejohnson",
          "avatar": "https://storage.example.com/avatars/uuid.jpg",
          "role": "admin"
        },
        "content": "Found a great venue option! Check out the attached photos.",
        "media": [
          {
            "id": "uuid-string",
            "type": "image",
            "url": "https://storage.example.com/posts/uuid.jpg",
            "thumbnail_url": "https://storage.example.com/posts/uuid-thumb.jpg"
          }
        ],
        "glow_count": 8,
        "comment_count": 5,
        "has_glowed": true,
        "is_pinned": false,
        "created_at": "2024-06-25T15:00:00Z"
      }
    ],
    "pagination": {
      "current_page": 1,
      "per_page": 20,
      "total_items": 156,
      "total_pages": 8,
      "has_next": true,
      "has_previous": false
    }
  }
}
```

### 16.17 Create Circle Post

```
POST /circles/:circleId/posts
Authorization: Bearer {token}
Content-Type: multipart/form-data

Path Parameters:
- circleId (required): UUID of the circle

Form Fields:
- content (optional): string, max 2000 characters
- media (optional): files, max 10 files, each max 50MB

Response 201:
{
  "success": true,
  "message": "Post created successfully",
  "data": {
    "id": "uuid-string",
    "content": "New circle post content",
    "media": [],
    "glow_count": 0,
    "comment_count": 0,
    "created_at": "2024-06-25T20:00:00Z"
  }
}

Response 403:
{
  "success": false,
  "message": "This circle does not allow member posts",
  "data": null
}
```

### 16.18 Pin Circle Post

```
POST /circles/:circleId/posts/:postId/pin
Authorization: Bearer {token}

Path Parameters:
- circleId (required): UUID of the circle
- postId (required): UUID of the post

Response 200:
{
  "success": true,
  "message": "Post pinned successfully",
  "data": {
    "post_id": "uuid-string",
    "pinned_at": "2024-06-25T20:30:00Z"
  }
}

Response 400:
{
  "success": false,
  "message": "Maximum 3 posts can be pinned",
  "data": null
}
```

### 16.19 Get Circle Events

```
GET /circles/:circleId/events
Authorization: Bearer {token}

Path Parameters:
- circleId (required): UUID of the circle

Query Parameters:
- page (optional): integer, default 1
- limit (optional): integer, default 10, max 20
- status (optional): string, one of "upcoming", "past", "all"

Response 200:
{
  "success": true,
  "message": "Circle events retrieved successfully",
  "data": {
    "events": [
      {
        "id": "uuid-string",
        "title": "Venue Scouting Trip",
        "event_type": {
          "id": "uuid-string",
          "name": "Meeting",
          "icon": "users"
        },
        "start_date": "2024-07-01",
        "start_time": "10:00:00",
        "venue_name": "Various Locations",
        "created_by": {
          "id": "uuid-string",
          "username": "alicejohnson"
        },
        "rsvp_count": {
          "going": 8,
          "maybe": 2,
          "not_going": 1
        },
        "my_rsvp": "going"
      }
    ],
    "pagination": {
      "current_page": 1,
      "per_page": 10,
      "total_items": 5,
      "total_pages": 1,
      "has_next": false,
      "has_previous": false
    }
  }
}
```

### 16.20 Create Circle Event

```
POST /circles/:circleId/events
Authorization: Bearer {token}
Content-Type: multipart/form-data

Path Parameters:
- circleId (required): UUID of the circle

Form Fields (same as regular event creation):
- title (required): string
- event_type_id (required): UUID
- start_date (required): YYYY-MM-DD
- start_time (required): HH:MM:SS
- end_date (optional): YYYY-MM-DD
- end_time (optional): HH:MM:SS
- venue_name (optional): string
- description (optional): string
- cover_image (optional): file

Response 201:
{
  "success": true,
  "message": "Circle event created successfully",
  "data": {
    "id": "uuid-string",
    "title": "Group Dinner",
    "circle_id": "uuid-string",
    "created_at": "2024-06-25T21:00:00Z"
  }
}
```

---

## MODULE 17: NURU CARDS

### 17.1 Get My Nuru Cards

```
GET /nuru-cards
Authorization: Bearer {token}

Response 200:
{
  "success": true,
  "message": "Cards retrieved",
  "data": [
    {
      "id": "uuid-string",
      "card_number": "NURU-2025-001234",
      "card_type": "standard",
      "status": "active",
      "holder_name": "John Doe",
      "nfc_enabled": false,
      "template": "standard_blue",
      "valid_from": "2025-01-01T00:00:00+03:00",
      "valid_until": "2025-12-31T23:59:59+03:00",
      "created_at": "2025-01-01T10:00:00+03:00"
    }
  ]
}

Card Types (enum): "standard", "premium", "custom"
```

### 17.1b Get My Card Orders

```
GET /nuru-cards/my-orders
Authorization: Bearer {token}

Response 200:
{
  "success": true,
  "message": "Orders retrieved",
  "data": [
    {
      "id": "uuid-string",
      "card_type": "standard",
      "status": "pending",
      "amount": 0,
      "delivery_name": "John Doe",
      "delivery_city": "Arusha",
      "payment_ref": "cash",
      "created_at": "2025-01-01T10:00:00+03:00"
    }
  ]
}

Order Statuses (enum): "pending", "processing", "shipped", "delivered", "cancelled"
```

### 17.2 Get Single Nuru Card

```
GET /nuru-cards/:cardId
Authorization: Bearer {token}

Path Parameters:
- cardId (required): UUID of the card

Response 200:
{
  "success": true,
  "message": "Nuru card retrieved successfully",
  "data": {
    "id": "uuid-string",
    "card_number": "NURU-2024-001234",
    "type": "premium",
    "status": "active",
    "holder_name": "John Doe",
    "qr_code_url": "https://storage.example.com/qr/uuid.png",
    "qr_code_data": "NURU:uuid-string:signature",
    "nfc_enabled": true,
    "nfc_tag_id": "04:A2:B3:C4:D5:E6:F7",
    "design": {
      "template": "gold_premium",
      "background_color": "#FFD700",
      "text_color": "#000000",
      "custom_image": null
    },
    "benefits": {
      "priority_entry": true,
      "vip_lounge_access": true,
      "discount_percentage": 15,
      "free_drinks": 2,
      "reserved_seating": true
    },
    "usage_stats": {
      "total_check_ins": 45,
      "events_attended": 12,
      "last_used_at": "2024-06-20T22:30:00Z"
    },
    "check_in_history": [
      {
        "id": "uuid-string",
        "event": {
          "id": "uuid-string",
          "title": "Summer Music Festival",
          "venue_name": "Uhuru Gardens"
        },
        "checked_in_at": "2024-06-20T22:30:00Z",
        "checked_in_by": "QR Scan",
        "benefits_used": ["priority_entry", "free_drinks"]
      }
    ],
    "valid_from": "2024-01-01T00:00:00Z",
    "valid_until": "2024-12-31T23:59:59Z",
    "created_at": "2024-01-01T10:00:00Z"
  }
}
```

### 17.3 Order New Nuru Card

```
POST /nuru-cards/order
Authorization: Bearer {token}
Content-Type: application/json

Request Body:
{
  "type": "premium",
  "holder_name": "John Doe",
  "template": "gold_premium",
  "nfc_enabled": true,
  "delivery_address": {
    "street": "123 Main Street",
    "city": "Nairobi",
    "postal_code": "00100",
    "country": "Kenya",
    "phone": "+254712345678"
  },
  "payment_method": "mpesa"
}

Card Types (enum):
- "standard": Basic card with standard benefits (FREE)
- "premium": Premium card with VIP benefits and NFC (TZS 50,000)

Note: Duplicate pending orders of the same card type are rejected.

Templates:
- "standard_blue"
- "standard_black"
- "standard_white"
- "gold_premium"
- "platinum_premium"
- "diamond_premium"

Response 201:
{
  "success": true,
  "message": "Card order placed successfully",
  "data": {
    "order_id": "uuid-string",
    "card_id": "uuid-string",
    "card_number": "NURU-2024-009999",
    "type": "premium",
    "status": "pending_payment",
    "amount": 2500,
    "currency": "KES",
    "payment": {
      "method": "mpesa",
      "checkout_request_id": "ws_CO_123456789",
      "phone": "+254712345678",
      "status": "pending"
    },
    "delivery": {
      "address": {
        "street": "123 Main Street",
        "city": "Nairobi",
        "postal_code": "00100",
        "country": "Kenya"
      },
      "estimated_delivery": "2024-07-01",
      "tracking_number": null
    },
    "created_at": "2024-06-25T21:00:00Z"
  }
}
```

### 17.4 Get Card Order Status

```
GET /nuru-cards/orders/:orderId
Authorization: Bearer {token}

Path Parameters:
- orderId (required): UUID of the order

Response 200:
{
  "success": true,
  "message": "Order status retrieved successfully",
  "data": {
    "order_id": "uuid-string",
    "card_id": "uuid-string",
    "card_number": "NURU-2024-009999",
    "status": "shipped",
    "payment": {
      "status": "completed",
      "amount": 2500,
      "currency": "KES",
      "paid_at": "2024-06-25T21:15:00Z",
      "transaction_id": "MPK123456789"
    },
    "delivery": {
      "status": "in_transit",
      "courier": "DHL",
      "tracking_number": "DHL1234567890",
      "tracking_url": "https://www.dhl.com/track?num=DHL1234567890",
      "shipped_at": "2024-06-26T10:00:00Z",
      "estimated_delivery": "2024-06-28"
    },
    "timeline": [
      {
        "status": "order_placed",
        "timestamp": "2024-06-25T21:00:00Z"
      },
      {
        "status": "payment_completed",
        "timestamp": "2024-06-25T21:15:00Z"
      },
      {
        "status": "card_printed",
        "timestamp": "2024-06-26T09:00:00Z"
      },
      {
        "status": "shipped",
        "timestamp": "2024-06-26T10:00:00Z"
      }
    ]
  }
}
```

### 17.5 Activate Nuru Card

```
POST /nuru-cards/:cardId/activate
Authorization: Bearer {token}
Content-Type: application/json

Path Parameters:
- cardId (required): UUID of the card

Request Body:
{
  "activation_code": "ABCD1234"
}

Response 200:
{
  "success": true,
  "message": "Card activated successfully",
  "data": {
    "card_id": "uuid-string",
    "status": "active",
    "activated_at": "2024-06-28T14:00:00Z",
    "valid_until": "2025-06-28T23:59:59Z"
  }
}

Response 400:
{
  "success": false,
  "message": "Invalid activation code",
  "data": null
}
```

### 17.6 Suspend Nuru Card

```
POST /nuru-cards/:cardId/suspend
Authorization: Bearer {token}
Content-Type: application/json

Path Parameters:
- cardId (required): UUID of the card

Request Body:
{
  "reason": "lost"
}

Reason Options:
- "lost"
- "stolen"
- "damaged"
- "temporary"

Response 200:
{
  "success": true,
  "message": "Card suspended successfully",
  "data": {
    "card_id": "uuid-string",
    "status": "suspended",
    "suspended_at": "2024-06-25T22:00:00Z",
    "reason": "lost"
  }
}
```

### 17.7 Reactivate Nuru Card

```
POST /nuru-cards/:cardId/reactivate
Authorization: Bearer {token}

Path Parameters:
- cardId (required): UUID of the card

Response 200:
{
  "success": true,
  "message": "Card reactivated successfully",
  "data": {
    "card_id": "uuid-string",
    "status": "active",
    "reactivated_at": "2024-06-26T10:00:00Z"
  }
}

Response 400:
{
  "success": false,
  "message": "Cannot reactivate a card that was reported lost or stolen. Please order a replacement.",
  "data": null
}
```

### 17.8 Order Replacement Card

```
POST /nuru-cards/:cardId/replace
Authorization: Bearer {token}
Content-Type: application/json

Path Parameters:
- cardId (required): UUID of the card to replace

Request Body:
{
  "reason": "damaged",
  "keep_benefits": true,
  "delivery_address": {
    "street": "456 New Street",
    "city": "Nairobi",
    "postal_code": "00100",
    "country": "Kenya",
    "phone": "+254712345678"
  }
}

Response 201:
{
  "success": true,
  "message": "Replacement card ordered successfully",
  "data": {
    "old_card_id": "uuid-string",
    "old_card_status": "replaced",
    "new_order_id": "uuid-string",
    "new_card_id": "uuid-string",
    "new_card_number": "NURU-2024-010000",
    "amount": 500,
    "currency": "KES",
    "benefits_transferred": true
  }
}
```

### 17.9 Verify Card for Check-in (Event Organizer)

```
POST /nuru-cards/verify
Authorization: Bearer {token}
Content-Type: application/json

Request Body:
{
  "card_data": "NURU:uuid-string:signature",
  "event_id": "uuid-string"
}

- card_data (required): QR code data or NFC tag data
- event_id (required): UUID of the event

Response 200:
{
  "success": true,
  "message": "Card verified successfully",
  "data": {
    "card": {
      "id": "uuid-string",
      "card_number": "NURU-2024-001234",
      "type": "premium",
      "status": "active"
    },
    "holder": {
      "id": "uuid-string",
      "first_name": "John",
      "last_name": "Doe",
      "avatar": "https://storage.example.com/avatars/uuid.jpg"
    },
    "guest_record": {
      "id": "uuid-string",
      "rsvp_status": "confirmed",
      "already_checked_in": false
    },
    "benefits": {
      "priority_entry": true,
      "vip_lounge_access": true,
      "discount_percentage": 15,
      "free_drinks": 2,
      "reserved_seating": true
    },
    "can_check_in": true
  }
}

Response 400:
{
  "success": false,
  "message": "Card is suspended",
  "data": {
    "card_status": "suspended",
    "can_check_in": false
  }
}

Response 404:
{
  "success": false,
  "message": "Guest not found for this event",
  "data": {
    "can_check_in": false
  }
}
```

### 17.10 Check-in with Nuru Card

```
POST /nuru-cards/check-in
Authorization: Bearer {token}
Content-Type: application/json

Request Body:
{
  "card_data": "NURU:uuid-string:signature",
  "event_id": "uuid-string",
  "benefits_to_use": ["priority_entry", "free_drinks"]
}

Response 200:
{
  "success": true,
  "message": "Check-in successful",
  "data": {
    "check_in_id": "uuid-string",
    "card_id": "uuid-string",
    "guest_id": "uuid-string",
    "event_id": "uuid-string",
    "checked_in_at": "2024-06-25T22:30:00Z",
    "benefits_used": ["priority_entry", "free_drinks"],
    "remaining_benefits": {
      "free_drinks": 1
    }
  }
}

Response 400:
{
  "success": false,
  "message": "Guest has already checked in",
  "data": {
    "previous_check_in_at": "2024-06-25T20:00:00Z"
  }
}
```

### 17.11 Get Card Check-in History

```
GET /nuru-cards/:cardId/check-ins
Authorization: Bearer {token}

Path Parameters:
- cardId (required): UUID of the card

Query Parameters:
- page (optional): integer, default 1
- limit (optional): integer, default 20, max 50

Response 200:
{
  "success": true,
  "message": "Check-in history retrieved successfully",
  "data": {
    "check_ins": [
      {
        "id": "uuid-string",
        "event": {
          "id": "uuid-string",
          "title": "Summer Music Festival",
          "cover_image": "https://storage.example.com/events/uuid.jpg",
          "start_date": "2024-06-20",
          "venue_name": "Uhuru Gardens"
        },
        "checked_in_at": "2024-06-20T22:30:00Z",
        "benefits_used": ["priority_entry", "free_drinks"],
        "check_in_method": "qr_scan"
      }
    ],
    "pagination": {
      "current_page": 1,
      "per_page": 20,
      "total_items": 45,
      "total_pages": 3,
      "has_next": true,
      "has_previous": false
    }
  }
}
```

### 17.12 Update Card Design

```
PUT /nuru-cards/:cardId/design
Authorization: Bearer {token}
Content-Type: multipart/form-data

Path Parameters:
- cardId (required): UUID of the card

Form Fields:
- template (optional): string, available template name
- custom_image (optional): file, max 2MB, jpg, jpeg, png

Response 200:
{
  "success": true,
  "message": "Card design updated successfully",
  "data": {
    "card_id": "uuid-string",
    "design": {
      "template": "custom",
      "background_color": null,
      "text_color": "#FFFFFF",
      "custom_image": "https://storage.example.com/cards/custom-uuid.jpg"
    },
    "updated_at": "2024-06-25T23:00:00Z"
  }
}
```

---

## MODULE 18: SUPPORT

### 18.1 Get Support Tickets

```
GET /support/tickets
Authorization: Bearer {token}

Query Parameters:
- page (optional): integer, default 1
- limit (optional): integer, default 10, max 20
- status (optional): string, one of "open", "in_progress", "resolved", "closed", "all"

Response 200:
{
  "success": true,
  "message": "Support tickets retrieved successfully",
  "data": {
    "tickets": [
      {
        "id": "uuid-string",
        "ticket_number": "TKT-2024-001234",
        "subject": "Unable to complete payment",
        "category": "payments",
        "priority": "high",
        "status": "in_progress",
        "last_message": {
          "content": "We are looking into this issue...",
          "sender": "support",
          "created_at": "2024-06-25T15:00:00Z"
        },
        "unread_count": 1,
        "created_at": "2024-06-25T10:00:00Z",
        "updated_at": "2024-06-25T15:00:00Z"
      }
    ],
    "pagination": {
      "current_page": 1,
      "per_page": 10,
      "total_items": 3,
      "total_pages": 1,
      "has_next": false,
      "has_previous": false
    }
  }
}
```

### 18.2 Get Single Support Ticket

```
GET /support/tickets/:ticketId
Authorization: Bearer {token}

Path Parameters:
- ticketId (required): UUID of the ticket

Response 200:
{
  "success": true,
  "message": "Support ticket retrieved successfully",
  "data": {
    "id": "uuid-string",
    "ticket_number": "TKT-2024-001234",
    "subject": "Unable to complete payment",
    "category": "payments",
    "priority": "high",
    "status": "in_progress",
    "description": "I tried to make a payment for my event but the transaction failed. The amount was deducted from my M-PESA but the payment shows as pending.",
    "attachments": [
      {
        "id": "uuid-string",
        "filename": "screenshot.png",
        "url": "https://storage.example.com/support/uuid.png",
        "size": 245000,
        "uploaded_at": "2024-06-25T10:00:00Z"
      }
    ],
    "related_to": {
      "type": "event",
      "id": "uuid-string",
      "title": "My Wedding Event"
    },
    "messages": [
      {
        "id": "uuid-string",
        "sender": "user",
        "sender_name": "John Doe",
        "sender_avatar": "https://storage.example.com/avatars/uuid.jpg",
        "content": "I tried to make a payment for my event but the transaction failed. The amount was deducted from my M-PESA but the payment shows as pending.",
        "attachments": [],
        "created_at": "2024-06-25T10:00:00Z"
      },
      {
        "id": "uuid-string",
        "sender": "support",
        "sender_name": "Nuru Support",
        "sender_avatar": "https://nuru.com/support-avatar.png",
        "content": "Hello John, thank you for reaching out. We apologize for the inconvenience. We are looking into this issue and will get back to you shortly with an update.",
        "attachments": [],
        "created_at": "2024-06-25T15:00:00Z"
      }
    ],
    "assigned_to": {
      "id": "uuid-string",
      "name": "Sarah - Support Agent"
    },
    "created_at": "2024-06-25T10:00:00Z",
    "updated_at": "2024-06-25T15:00:00Z",
    "resolved_at": null
  }
}
```

### 18.3 Create Support Ticket

```
POST /support/tickets
Authorization: Bearer {token}
Content-Type: multipart/form-data

Form Fields:
- subject (required): string, 5-200 characters
- category (required): string, one of:
  - "account"
  - "payments"
  - "events"
  - "services"
  - "nuru_cards"
  - "technical"
  - "feedback"
  - "other"
- priority (optional): string, one of "low", "medium", "high", default "medium"
- description (required): string, 20-5000 characters
- attachments (optional): files, max 5 files, each max 10MB
- related_type (optional): string, one of "event", "service", "booking", "card"
- related_id (optional): UUID of related entity

Response 201:
{
  "success": true,
  "message": "Support ticket created successfully",
  "data": {
    "id": "uuid-string",
    "ticket_number": "TKT-2024-001235",
    "subject": "Question about service verification",
    "category": "services",
    "priority": "medium",
    "status": "open",
    "created_at": "2024-06-25T23:00:00Z"
  }
}
```

### 18.4 Reply to Support Ticket

```
POST /support/tickets/:ticketId/messages
Authorization: Bearer {token}
Content-Type: multipart/form-data

Path Parameters:
- ticketId (required): UUID of the ticket

Form Fields:
- content (required): string, 1-5000 characters
- attachments (optional): files, max 5 files, each max 10MB

Response 201:
{
  "success": true,
  "message": "Reply sent successfully",
  "data": {
    "id": "uuid-string",
    "content": "Thank you for the update. I have attached the transaction receipt.",
    "attachments": [
      {
        "id": "uuid-string",
        "filename": "receipt.pdf",
        "url": "https://storage.example.com/support/uuid.pdf",
        "size": 125000
      }
    ],
    "created_at": "2024-06-25T23:30:00Z"
  }
}

Response 400:
{
  "success": false,
  "message": "Cannot reply to a closed ticket",
  "data": null
}
```

### 18.5 Close Support Ticket

```
PUT /support/tickets/:ticketId/close
Authorization: Bearer {token}
Content-Type: application/json

Path Parameters:
- ticketId (required): UUID of the ticket

Request Body:
{
  "rating": 5,
  "feedback": "Great support, issue resolved quickly!"
}

- rating (optional): integer, 1-5
- feedback (optional): string, max 1000 characters

Response 200:
{
  "success": true,
  "message": "Ticket closed successfully",
  "data": {
    "id": "uuid-string",
    "status": "closed",
    "closed_at": "2024-06-26T10:00:00Z",
    "rating": 5,
    "feedback": "Great support, issue resolved quickly!"
  }
}
```

### 18.6 Reopen Support Ticket

```
PUT /support/tickets/:ticketId/reopen
Authorization: Bearer {token}
Content-Type: application/json

Path Parameters:
- ticketId (required): UUID of the ticket

Request Body:
{
  "reason": "The issue has occurred again"
}

Response 200:
{
  "success": true,
  "message": "Ticket reopened successfully",
  "data": {
    "id": "uuid-string",
    "status": "open",
    "reopened_at": "2024-06-27T09:00:00Z"
  }
}

Response 400:
{
  "success": false,
  "message": "Ticket can only be reopened within 7 days of closure",
  "data": null
}
```

### 18.7 Get FAQ Categories

```
GET /support/faqs/categories
Authorization: Not required

Response 200:
{
  "success": true,
  "message": "FAQ categories retrieved successfully",
  "data": {
    "categories": [
      {
        "id": "uuid-string",
        "name": "Getting Started",
        "icon": "rocket",
        "faq_count": 12,
        "order": 1
      },
      {
        "id": "uuid-string",
        "name": "Events",
        "icon": "calendar",
        "faq_count": 18,
        "order": 2
      },
      {
        "id": "uuid-string",
        "name": "Payments",
        "icon": "credit-card",
        "faq_count": 15,
        "order": 3
      },
      {
        "id": "uuid-string",
        "name": "Services & Vendors",
        "icon": "briefcase",
        "faq_count": 20,
        "order": 4
      },
      {
        "id": "uuid-string",
        "name": "Nuru Cards",
        "icon": "id-card",
        "faq_count": 10,
        "order": 5
      },
      {
        "id": "uuid-string",
        "name": "Account & Privacy",
        "icon": "shield",
        "faq_count": 14,
        "order": 6
      }
    ]
  }
}
```

### 18.8 Get FAQs

```
GET /support/faqs
Authorization: Not required

Query Parameters:
- category_id (optional): UUID, filter by category
- search (optional): string, search in questions and answers
- page (optional): integer, default 1
- limit (optional): integer, default 20, max 50

Response 200:
{
  "success": true,
  "message": "FAQs retrieved successfully",
  "data": {
    "faqs": [
      {
        "id": "uuid-string",
        "category": {
          "id": "uuid-string",
          "name": "Getting Started"
        },
        "question": "How do I create my first event on Nuru?",
        "answer": "To create your first event on Nuru, follow these steps:\n\n1. Log in to your Nuru account\n2. Click on 'Create Event' in the navigation menu\n3. Fill in the event details including title, date, time, and venue\n4. Add a cover image to make your event attractive\n5. Set your guest list and RSVP settings\n6. Publish your event\n\nYour event will be live and you can start inviting guests!",
        "helpful_count": 156,
        "not_helpful_count": 12,
        "order": 1,
        "updated_at": "2024-06-01T10:00:00Z"
      }
    ],
    "pagination": {
      "current_page": 1,
      "per_page": 20,
      "total_items": 89,
      "total_pages": 5,
      "has_next": true,
      "has_previous": false
    }
  }
}
```

### 18.9 Mark FAQ as Helpful

```
POST /support/faqs/:faqId/helpful
Authorization: Bearer {token} (optional)
Content-Type: application/json

Path Parameters:
- faqId (required): UUID of the FAQ

Request Body:
{
  "helpful": true
}

- helpful (required): boolean

Response 200:
{
  "success": true,
  "message": "Feedback recorded",
  "data": {
    "faq_id": "uuid-string",
    "helpful_count": 157,
    "not_helpful_count": 12
  }
}
```

### 18.10 Get Live Chat Status

```
GET /support/chat/status
Authorization: Bearer {token}

Response 200:
{
  "success": true,
  "message": "Chat status retrieved",
  "data": {
    "available": true,
    "estimated_wait_time": 120,
    "agents_online": 5,
    "current_queue_position": null,
    "active_chat": null,
    "operating_hours": {
      "timezone": "Africa/Nairobi",
      "monday": { "open": "08:00", "close": "22:00" },
      "tuesday": { "open": "08:00", "close": "22:00" },
      "wednesday": { "open": "08:00", "close": "22:00" },
      "thursday": { "open": "08:00", "close": "22:00" },
      "friday": { "open": "08:00", "close": "22:00" },
      "saturday": { "open": "09:00", "close": "18:00" },
      "sunday": { "open": "10:00", "close": "16:00" }
    }
  }
}
```

### 18.11 Start Live Chat

```
POST /support/chat/start
Authorization: Bearer {token}
Content-Type: application/json

Request Body:
{
  "category": "payments",
  "initial_message": "I need help with a failed payment"
}

Response 200:
{
  "success": true,
  "message": "Chat started successfully",
  "data": {
    "chat_id": "uuid-string",
    "queue_position": 3,
    "estimated_wait_time": 180,
    "websocket_url": "wss://chat.nuru.com/support/uuid-string"
  }
}

Response 400:
{
  "success": false,
  "message": "Live chat is currently unavailable. Please try again during operating hours or create a support ticket.",
  "data": {
    "available": false,
    "next_available": "2024-06-26T08:00:00+03:00"
  }
}
```

### 18.12 End Live Chat

```
POST /support/chat/:chatId/end
Authorization: Bearer {token}
Content-Type: application/json

Path Parameters:
- chatId (required): UUID of the chat

Request Body:
{
  "rating": 5,
  "feedback": "Very helpful agent!"
}

Response 200:
{
  "success": true,
  "message": "Chat ended successfully",
  "data": {
    "chat_id": "uuid-string",
    "transcript_id": "uuid-string",
    "ended_at": "2024-06-25T23:45:00Z"
  }
}
```

### 18.13 Get Chat Transcript

```
GET /support/chat/:chatId/transcript
Authorization: Bearer {token}

Path Parameters:
- chatId (required): UUID of the chat

Response 200:
{
  "success": true,
  "message": "Chat transcript retrieved",
  "data": {
    "chat_id": "uuid-string",
    "started_at": "2024-06-25T23:00:00Z",
    "ended_at": "2024-06-25T23:45:00Z",
    "agent": {
      "name": "Sarah",
      "avatar": "https://nuru.com/agents/sarah.jpg"
    },
    "messages": [
      {
        "sender": "system",
        "content": "You are now connected with Sarah. How can we help you today?",
        "timestamp": "2024-06-25T23:02:00Z"
      },
      {
        "sender": "user",
        "content": "I need help with a failed payment",
        "timestamp": "2024-06-25T23:02:30Z"
      },
      {
        "sender": "agent",
        "content": "Hello! I'd be happy to help you with that. Could you please provide the transaction reference or the date of the payment?",
        "timestamp": "2024-06-25T23:03:00Z"
      }
    ],
    "rating": 5,
    "feedback": "Very helpful agent!"
  }
}
```

---

## MODULE 19: SETTINGS

### 19.1 Get All Settings

```
GET /settings
Authorization: Bearer {token}

Response 200:
{
  "success": true,
  "message": "Settings retrieved successfully",
  "data": {
    "notifications": {
      "email": {
        "enabled": true,
        "event_invitations": true,
        "event_updates": true,
        "rsvp_updates": true,
        "contributions": true,
        "messages": true,
        "marketing": false,
        "weekly_digest": true
      },
      "push": {
        "enabled": true,
        "event_invitations": true,
        "event_updates": true,
        "rsvp_updates": true,
        "contributions": true,
        "messages": true,
        "glows_and_echoes": true,
        "new_followers": true,
        "mentions": true
      },
      "sms": {
        "enabled": true,
        "event_reminders": true,
        "payment_confirmations": true,
        "security_alerts": true
      },
      "quiet_hours": {
        "enabled": true,
        "start_time": "22:00",
        "end_time": "07:00",
        "timezone": "Africa/Nairobi"
      }
    },
    "privacy": {
      "profile_visibility": "public",
      "show_email": false,
      "show_phone": false,
      "show_location": true,
      "allow_tagging": true,
      "allow_mentions": true,
      "show_activity_status": true,
      "show_read_receipts": true,
      "allow_message_requests": true,
      "blocked_users_count": 2
    },
    "security": {
      "two_factor_enabled": false,
      "two_factor_method": null,
      "login_alerts": true,
      "active_sessions_count": 3,
      "last_password_change": "2024-03-15T10:00:00Z"
    },
    "preferences": {
      "language": "en",
      "currency": "KES",
      "timezone": "Africa/Nairobi",
      "date_format": "DD/MM/YYYY",
      "time_format": "24h",
      "theme": "system",
      "compact_mode": false
    },
    "connected_accounts": {
      "google": {
        "connected": true,
        "email": "john@gmail.com",
        "connected_at": "2024-01-15T10:00:00Z"
      },
      "facebook": {
        "connected": false,
        "email": null,
        "connected_at": null
      },
      "apple": {
        "connected": false,
        "email": null,
        "connected_at": null
      }
    },
    "payment_methods": {
      "mpesa": {
        "enabled": true,
        "phone": "+254712345678",
        "is_default": true
      },
      "bank": {
        "enabled": false,
        "account_number": null,
        "bank_name": null
      },
      "card": {
        "enabled": true,
        "last_four": "4242",
        "brand": "visa",
        "is_default": false
      }
    }
  }
}
```

### 19.2 Update Notification Settings

```
PUT /settings/notifications
Authorization: Bearer {token}
Content-Type: application/json

Request Body:
{
  "email": {
    "enabled": true,
    "event_invitations": true,
    "marketing": false
  },
  "push": {
    "glows_and_echoes": false
  },
  "quiet_hours": {
    "enabled": true,
    "start_time": "23:00",
    "end_time": "08:00"
  }
}

Response 200:
{
  "success": true,
  "message": "Notification settings updated successfully",
  "data": {
    "notifications": {
      "email": {
        "enabled": true,
        "event_invitations": true,
        "event_updates": true,
        "rsvp_updates": true,
        "contributions": true,
        "messages": true,
        "marketing": false,
        "weekly_digest": true
      },
      "push": {
        "enabled": true,
        "event_invitations": true,
        "event_updates": true,
        "rsvp_updates": true,
        "contributions": true,
        "messages": true,
        "glows_and_echoes": false,
        "new_followers": true,
        "mentions": true
      },
      "sms": {
        "enabled": true,
        "event_reminders": true,
        "payment_confirmations": true,
        "security_alerts": true
      },
      "quiet_hours": {
        "enabled": true,
        "start_time": "23:00",
        "end_time": "08:00",
        "timezone": "Africa/Nairobi"
      }
    },
    "updated_at": "2024-06-25T23:00:00Z"
  }
}
```

### 19.3 Update Privacy Settings

```
PUT /settings/privacy
Authorization: Bearer {token}
Content-Type: application/json

Request Body:
{
  "profile_visibility": "followers",
  "show_email": false,
  "show_phone": false,
  "allow_tagging": false,
  "show_activity_status": false
}

Response 200:
{
  "success": true,
  "message": "Privacy settings updated successfully",
  "data": {
    "privacy": {
      "profile_visibility": "followers",
      "show_email": false,
      "show_phone": false,
      "show_location": true,
      "allow_tagging": false,
      "allow_mentions": true,
      "show_activity_status": false,
      "show_read_receipts": true,
      "allow_message_requests": true
    },
    "updated_at": "2024-06-25T23:30:00Z"
  }
}
```

### 19.4 Update Preferences

```
PUT /settings/preferences
Authorization: Bearer {token}
Content-Type: application/json

Request Body:
{
  "language": "sw",
  "currency": "USD",
  "timezone": "Africa/Nairobi",
  "theme": "dark"
}

Supported Languages:
- "en" (English)
- "sw" (Swahili)
- "fr" (French)

Supported Themes:
- "light"
- "dark"
- "system"

Response 200:
{
  "success": true,
  "message": "Preferences updated successfully",
  "data": {
    "preferences": {
      "language": "sw",
      "currency": "USD",
      "timezone": "Africa/Nairobi",
      "date_format": "DD/MM/YYYY",
      "time_format": "24h",
      "theme": "dark",
      "compact_mode": false
    },
    "updated_at": "2024-06-26T00:00:00Z"
  }
}
```

### 19.5 Enable Two-Factor Authentication

```
POST /settings/security/2fa/enable
Authorization: Bearer {token}
Content-Type: application/json

Request Body:
{
  "method": "authenticator",
  "password": "CurrentPassword123!"
}

Methods:
- "authenticator": TOTP-based (Google Authenticator, Authy, etc.)
- "sms": SMS-based verification

Response 200 (authenticator):
{
  "success": true,
  "message": "2FA setup initiated",
  "data": {
    "method": "authenticator",
    "secret": "JBSWY3DPEHPK3PXP",
    "qr_code_url": "data:image/png;base64,iVBORw0KGgo...",
    "backup_codes": [
      "a1b2c3d4e5",
      "f6g7h8i9j0",
      "k1l2m3n4o5",
      "p6q7r8s9t0",
      "u1v2w3x4y5",
      "z6a7b8c9d0",
      "e1f2g3h4i5",
      "j6k7l8m9n0"
    ],
    "expires_at": "2024-06-26T00:15:00Z"
  }
}

Response 200 (sms):
{
  "success": true,
  "message": "Verification code sent to your phone",
  "data": {
    "method": "sms",
    "phone": "+254712***678",
    "expires_at": "2024-06-26T00:05:00Z"
  }
}
```

### 19.6 Verify and Complete 2FA Setup

```
POST /settings/security/2fa/verify
Authorization: Bearer {token}
Content-Type: application/json

Request Body:
{
  "code": "123456"
}

Response 200:
{
  "success": true,
  "message": "Two-factor authentication enabled successfully",
  "data": {
    "two_factor_enabled": true,
    "method": "authenticator",
    "enabled_at": "2024-06-26T00:10:00Z"
  }
}

Response 400:
{
  "success": false,
  "message": "Invalid verification code",
  "data": null
}
```

### 19.7 Disable Two-Factor Authentication

```
POST /settings/security/2fa/disable
Authorization: Bearer {token}
Content-Type: application/json

Request Body:
{
  "password": "CurrentPassword123!",
  "code": "123456"
}

Response 200:
{
  "success": true,
  "message": "Two-factor authentication disabled",
  "data": {
    "two_factor_enabled": false,
    "disabled_at": "2024-06-26T01:00:00Z"
  }
}
```

### 19.8 Get Active Sessions

```
GET /settings/security/sessions
Authorization: Bearer {token}

Response 200:
{
  "success": true,
  "message": "Active sessions retrieved",
  "data": {
    "sessions": [
      {
        "id": "uuid-string",
        "device": {
          "type": "mobile",
          "name": "iPhone 14 Pro",
          "os": "iOS 17.0",
          "browser": "Safari"
        },
        "location": {
          "city": "Nairobi",
          "country": "Kenya",
          "ip": "197.248.xxx.xxx"
        },
        "is_current": true,
        "last_active_at": "2024-06-26T01:00:00Z",
        "created_at": "2024-06-25T08:00:00Z"
      },
      {
        "id": "uuid-string",
        "device": {
          "type": "desktop",
          "name": "MacBook Pro",
          "os": "macOS Sonoma",
          "browser": "Chrome 125"
        },
        "location": {
          "city": "Nairobi",
          "country": "Kenya",
          "ip": "197.248.xxx.xxx"
        },
        "is_current": false,
        "last_active_at": "2024-06-25T18:00:00Z",
        "created_at": "2024-06-20T10:00:00Z"
      }
    ],
    "total_sessions": 3
  }
}
```

### 19.9 Revoke Session

```
DELETE /settings/security/sessions/:sessionId
Authorization: Bearer {token}

Path Parameters:
- sessionId (required): UUID of the session

Response 200:
{
  "success": true,
  "message": "Session revoked successfully",
  "data": null
}

Response 400:
{
  "success": false,
  "message": "Cannot revoke current session. Use logout instead.",
  "data": null
}
```

### 19.10 Revoke All Other Sessions

```
DELETE /settings/security/sessions
Authorization: Bearer {token}
Content-Type: application/json

Request Body:
{
  "password": "CurrentPassword123!"
}

Response 200:
{
  "success": true,
  "message": "All other sessions revoked",
  "data": {
    "revoked_count": 2
  }
}
```

### 19.11 Connect Social Account

```
POST /settings/accounts/connect/:provider
Authorization: Bearer {token}

Path Parameters:
- provider (required): string, one of "google", "facebook", "apple"

Response 200:
{
  "success": true,
  "message": "Redirect to authorization",
  "data": {
    "redirect_url": "https://accounts.google.com/oauth/authorize?client_id=...&redirect_uri=..."
  }
}
```

### 19.12 Disconnect Social Account

```
DELETE /settings/accounts/disconnect/:provider
Authorization: Bearer {token}
Content-Type: application/json

Path Parameters:
- provider (required): string, one of "google", "facebook", "apple"

Request Body:
{
  "password": "CurrentPassword123!"
}

Response 200:
{
  "success": true,
  "message": "Account disconnected successfully",
  "data": {
    "provider": "google",
    "disconnected_at": "2024-06-26T02:00:00Z"
  }
}

Response 400:
{
  "success": false,
  "message": "Cannot disconnect the only login method. Please set a password or connect another account first.",
  "data": null
}
```

### 19.13 Add Payment Method - M-PESA

```
POST /settings/payments/mpesa
Authorization: Bearer {token}
Content-Type: application/json

Request Body:
{
  "phone": "+254798765432"
}

Response 200:
{
  "success": true,
  "message": "Verification code sent to your phone",
  "data": {
    "phone": "+254798765432",
    "verification_expires_at": "2024-06-26T02:15:00Z"
  }
}
```

### 19.14 Verify M-PESA Number

```
POST /settings/payments/mpesa/verify
Authorization: Bearer {token}
Content-Type: application/json

Request Body:
{
  "phone": "+254798765432",
  "code": "123456"
}

Response 200:
{
  "success": true,
  "message": "M-PESA number verified and added",
  "data": {
    "mpesa": {
      "enabled": true,
      "phone": "+254798765432",
      "is_default": false,
      "verified_at": "2024-06-26T02:10:00Z"
    }
  }
}
```

### 19.15 Add Payment Method - Card

```
POST /settings/payments/card
Authorization: Bearer {token}
Content-Type: application/json

Request Body:
{
  "card_token": "tok_visa_4242",
  "set_as_default": true
}

Note: card_token is obtained from payment processor (Stripe/Flutterwave) client-side

Response 200:
{
  "success": true,
  "message": "Card added successfully",
  "data": {
    "card": {
      "id": "uuid-string",
      "last_four": "4242",
      "brand": "visa",
      "exp_month": 12,
      "exp_year": 2025,
      "is_default": true,
      "added_at": "2024-06-26T02:30:00Z"
    }
  }
}
```

### 19.16 Remove Payment Method

```
DELETE /settings/payments/:type/:id
Authorization: Bearer {token}

Path Parameters:
- type (required): string, one of "mpesa", "card", "bank"
- id (required): UUID or identifier of the payment method

Response 200:
{
  "success": true,
  "message": "Payment method removed",
  "data": null
}

Response 400:
{
  "success": false,
  "message": "Cannot remove the only payment method",
  "data": null
}
```

### 19.17 Set Default Payment Method

```
PUT /settings/payments/default
Authorization: Bearer {token}
Content-Type: application/json

Request Body:
{
  "type": "card",
  "id": "uuid-string"
}

Response 200:
{
  "success": true,
  "message": "Default payment method updated",
  "data": {
    "default_payment_method": {
      "type": "card",
      "id": "uuid-string",
      "last_four": "4242",
      "brand": "visa"
    }
  }
}
```

### 19.18 Export User Data

```
POST /settings/data/export
Authorization: Bearer {token}
Content-Type: application/json

Request Body:
{
  "format": "json",
  "include": ["profile", "events", "posts", "messages", "services"]
}

Format Options:
- "json"
- "csv"
- "pdf"

Include Options:
- "profile"
- "events"
- "posts"
- "messages"
- "services"
- "nuru_cards"
- "payments"
- "settings"

Response 200:
{
  "success": true,
  "message": "Data export started. You will receive an email when it's ready.",
  "data": {
    "export_id": "uuid-string",
    "status": "processing",
    "estimated_completion": "2024-06-26T04:00:00Z"
  }
}
```

### 19.19 Get Data Export Status

```
GET /settings/data/export/:exportId
Authorization: Bearer {token}

Path Parameters:
- exportId (required): UUID of the export

Response 200:
{
  "success": true,
  "message": "Export status retrieved",
  "data": {
    "export_id": "uuid-string",
    "status": "completed",
    "format": "json",
    "file_size": 15728640,
    "download_url": "https://storage.example.com/exports/uuid.zip",
    "download_expires_at": "2024-06-29T04:00:00Z",
    "created_at": "2024-06-26T02:00:00Z",
    "completed_at": "2024-06-26T02:30:00Z"
  }
}
```

---

## MODULE 20: FILE UPLOAD

### 20.1 Request Upload URL

```
POST /uploads/request
Authorization: Bearer {token}
Content-Type: application/json

Request Body:
{
  "filename": "event-cover.jpg",
  "content_type": "image/jpeg",
  "size": 2456789,
  "context": "event_cover",
  "context_id": "uuid-string"
}

Context Options:
- "avatar"
- "event_cover"
- "event_gallery"
- "post_media"
- "moment_media"
- "service_image"
- "kyc_document"
- "message_attachment"
- "support_attachment"
- "circle_cover"

Response 200:
{
  "success": true,
  "message": "Upload URL generated",
  "data": {
    "upload_id": "uuid-string",
    "upload_url": "https://storage.example.com/upload?signature=...",
    "method": "PUT",
    "headers": {
      "Content-Type": "image/jpeg",
      "x-amz-acl": "private"
    },
    "expires_at": "2024-06-26T03:15:00Z",
    "max_size": 10485760,
    "allowed_types": ["image/jpeg", "image/png", "image/webp"]
  }
}

Response 400:
{
  "success": false,
  "message": "File size exceeds maximum allowed",
  "data": {
    "max_size": 10485760,
    "provided_size": 52428800
  }
}
```

### 20.2 Confirm Upload

```
POST /uploads/:uploadId/confirm
Authorization: Bearer {token}

Path Parameters:
- uploadId (required): UUID of the upload

Response 200:
{
  "success": true,
  "message": "Upload confirmed",
  "data": {
    "upload_id": "uuid-string",
    "file_url": "https://storage.example.com/files/uuid.jpg",
    "thumbnail_url": "https://storage.example.com/files/uuid-thumb.jpg",
    "file_size": 2456789,
    "content_type": "image/jpeg",
    "dimensions": {
      "width": 1920,
      "height": 1080
    },
    "created_at": "2024-06-26T03:00:00Z"
  }
}

Response 400:
{
  "success": false,
  "message": "Upload not found or expired",
  "data": null
}
```

### 20.3 Direct Upload (for smaller files)

```
POST /uploads/direct
Authorization: Bearer {token}
Content-Type: multipart/form-data

Form Fields:
- file (required): file, max size depends on context
- context (required): string, context type
- context_id (optional): UUID of related entity

Response 200:
{
  "success": true,
  "message": "File uploaded successfully",
  "data": {
    "file_id": "uuid-string",
    "file_url": "https://storage.example.com/files/uuid.jpg",
    "thumbnail_url": "https://storage.example.com/files/uuid-thumb.jpg",
    "file_size": 1234567,
    "content_type": "image/jpeg",
    "dimensions": {
      "width": 1080,
      "height": 1080
    },
    "created_at": "2024-06-26T03:30:00Z"
  }
}
```

### 20.4 Get Upload Status

```
GET /uploads/:uploadId
Authorization: Bearer {token}

Path Parameters:
- uploadId (required): UUID of the upload

Response 200:
{
  "success": true,
  "message": "Upload status retrieved",
  "data": {
    "upload_id": "uuid-string",
    "status": "processing",
    "progress": 75,
    "file_url": null,
    "created_at": "2024-06-26T03:00:00Z"
  }
}

Status Values:
- "pending": Upload URL generated, waiting for upload
- "uploading": File being uploaded
- "processing": Processing (thumbnails, optimization)
- "completed": Ready for use
- "failed": Upload or processing failed
- "expired": Upload URL expired
```

### 20.5 Delete Upload

```
DELETE /uploads/:uploadId
Authorization: Bearer {token}

Path Parameters:
- uploadId (required): UUID of the upload

Response 200:
{
  "success": true,
  "message": "File deleted successfully",
  "data": null
}

Response 403:
{
  "success": false,
  "message": "You can only delete your own uploads",
  "data": null
}

Response 400:
{
  "success": false,
  "message": "File is in use and cannot be deleted",
  "data": {
    "used_by": [
      {
        "type": "event_cover",
        "id": "uuid-string",
        "title": "My Event"
      }
    ]
  }
}
```

### 20.6 Get My Uploads

```
GET /uploads
Authorization: Bearer {token}

Query Parameters:
- page (optional): integer, default 1
- limit (optional): integer, default 20, max 50
- context (optional): string, filter by context type
- content_type (optional): string, filter by MIME type prefix (e.g., "image/", "video/")

Response 200:
{
  "success": true,
  "message": "Uploads retrieved successfully",
  "data": {
    "uploads": [
      {
        "id": "uuid-string",
        "file_url": "https://storage.example.com/files/uuid.jpg",
        "thumbnail_url": "https://storage.example.com/files/uuid-thumb.jpg",
        "filename": "event-cover.jpg",
        "file_size": 2456789,
        "content_type": "image/jpeg",
        "context": "event_cover",
        "context_id": "uuid-string",
        "status": "completed",
        "created_at": "2024-06-26T03:00:00Z"
      }
    ],
    "storage_used": 156789012,
    "storage_limit": 5368709120,
    "pagination": {
      "current_page": 1,
      "per_page": 20,
      "total_items": 45,
      "total_pages": 3,
      "has_next": true,
      "has_previous": false
    }
  }
}
```

---

## ERROR CODES REFERENCE

| HTTP Code | Error Type            | Description                                                      |
| --------- | --------------------- | ---------------------------------------------------------------- |
| 400       | Bad Request           | Invalid request body, missing required fields, validation errors |
| 401       | Unauthorized          | Missing or invalid authentication token                          |
| 403       | Forbidden             | Valid token but insufficient permissions                         |
| 404       | Not Found             | Resource does not exist                                          |
| 409       | Conflict              | Resource already exists (duplicate)                              |
| 422       | Unprocessable Entity  | Request understood but cannot be processed                       |
| 429       | Too Many Requests     | Rate limit exceeded                                              |
| 500       | Internal Server Error | Server-side error                                                |

---

# 📋 CHANGELOG (2026-02-10)

## Backend Changes

### New Enum: `feed_visibility_enum`

- Values: `public`, `circle`
- Used by `user_feeds.visibility` column

### New Column: `user_feeds.visibility`

- Type: `feed_visibility_enum`, default `public`
- Controls post audience: `public` (everyone) or `circle` (close friends only)
- **SQL migration required:**

```sql
CREATE TYPE feed_visibility_enum AS ENUM ('public', 'circle');
ALTER TABLE user_feeds ADD COLUMN visibility feed_visibility_enum DEFAULT 'public';
```

### SMS Notification Integration

- `backend/utils/sms.py` — Fire-and-forget SMS helpers using `SewmrSmsClient`
- Wired into guest additions, committee invites, contributions, target updates, thank-you messages, and provider bookings in `/user-events/` routes

### Community Posts Endpoint

- `GET /communities/{id}/posts` — Returns community posts created by the community creator
- `POST /communities/{id}/posts` — Creator-only: create a community post (multipart: `content`, `images[]`)
- `POST /communities/{id}/posts/{post_id}/glow` — Glow a community post
- `DELETE /communities/{id}/posts/{post_id}/glow` — Remove glow from a community post

### Public Post Guest View

- `GET /posts/{id}/public` — Public endpoint (no auth) returns post data for public posts only
- Frontend route: `/shared/post/:id` — Guest view with sign-in prompt, interactions disabled

### Password Reset

- `POST /auth/forgot-password` — Sends reset email via API
- `POST /auth/reset-password` — Accepts token + new password
- Frontend `ResetPassword` page wired to these endpoints

### Post Visibility

- `POST /posts` now accepts `visibility` form field (`public` | `circle`)
- `GET /posts/feed` and `GET /posts/{id}` return `visibility` in response

### Default Currency

- All service and event endpoints default to `TZS` instead of `KES`

## Frontend Changes

### Feed Image Fix

- Fixed image extraction: handles both string URLs and `{image_url}` objects from backend
- `Moment.tsx` now supports multi-image grid display

### Event Edit Fixes

- Service providers now re-fetch when event type changes on edit
- Event images now load from `images[]` array (not just `gallery_images`)

### OTP Input Consistency

- VerifyEmail and VerifyPhone pages use `InputOTP` component with 6 box slots

### Dark Mode

- Theme toggle in Settings persists to `localStorage('nuru-ui-theme')`
- Applied via `document.documentElement.classList.toggle('dark')`

### Autocomplete Prevention

- `autoComplete="off"` default on shared `Input` component

# 📋 CHANGELOG (2026-02-11)

## Backend Changes

### Community Member Management

- `POST /communities/{id}/members` — Creator can add a member by `user_id`
- `DELETE /communities/{id}/members/{user_id}` — Creator can remove a member

### Service Booking Notification

- When a service provider is assigned to an event, an in-app notification + SMS is sent to the provider

## Frontend Changes

### Avatar Two-Initials Consistency

- All avatar fallbacks (MomentDetail, BookingList, BookingDetail, CommunityDetail) now use two-letter initials (e.g., "JD" for John Doe) instead of a single letter

### Feed Silent Refetch

- Returning from MomentDetail no longer triggers skeleton loaders; data is refetched silently in the background

### Booking Page Fixes

- Invalid dates handled gracefully (shows "TBD" when event_date is null/invalid)
- Service image fallback: shows initials when no image available
- My Bookings tab defaults to showing "Accepted" status bookings
- Incoming Requests tab defaults to showing "Pending" status bookings

### Community Members Fix

- Members count now reads from actual fetched members array instead of stale `member_count` field
- Creator can add members via user search dialog (name, phone, email lookup)
- Creator can remove members (hover to reveal remove button)
- Community post author avatars use two-letter initials

### Booking API Response Enrichment (2026-02-11)

- `_booking_dict` now returns full service data: `primary_image` (resolved from images relation, cover_image_url fallbacks), `category`
- `client` and `provider` objects now include `avatar` (from user profile `profile_picture_url`), `phone`, and `email`
- `event` object now includes `date`, `start_time`, `end_time`, `location`, `venue`, `guest_count`
- Top-level `event_name`, `event_date`, `location`, `venue`, `guest_count` fields populated from event relation

### Booking Respond → Calendar Price Sync (2026-02-11)

- When vendor accepts a booking via `POST /bookings/{bookingId}/respond`, the `quoted_price` is synced to `EventService.agreed_price`
- `EventService.service_status` is also updated to `confirmed` on acceptance
- This ensures the service calendar (`GET /services/{id}/calendar`) shows the actual quoted price, not the service min_price

### Public Service Detail Page (2026-02-11)

- New frontend page `PublicServiceDetail` at route `/services/view/:id` — any authenticated user can view service details in read-only mode
- Calendar shows booked/available dates without event names, locations, or agreed prices (those are owner-only in the existing `/service/:id` page)
- Reviews section displays all client reviews with pagination
- Review submission form: star rating + comment (min 10 chars, max 2000 chars)

### Submit Service Review Endpoint (2026-02-11)

- `POST /services/{service_id}/reviews` — Authenticated endpoint
- **Eligibility**: Only users whose events had this service provider assigned (confirmed/completed/accepted status) can review
- **Once only**: Each user can review a service only once
- **Cannot review own service**
- **Validation**: rating (1-5 integer, required), comment (10-2000 chars, required)
- **Request Body:**

```json
{
  "rating": 5,
  "comment": "Excellent service, very professional and timely."
}
```

- **Success Response:**

```json
{
  "success": true,
  "message": "Review submitted successfully",
  "data": {
    "id": "uuid",
    "user_name": "John Doe",
    "rating": 5,
    "comment": "Excellent service...",
    "created_at": "2026-02-11T10:00:00Z"
  }
}
```

- **Error responses**: "You cannot review your own service", "You can only review services that were assigned to your events", "You have already reviewed this service", validation errors for rating/comment

---

# 📋 MODULE: EVENT TEMPLATES & CHECKLISTS

## Overview

Pre-built planning templates per event type with default tasks, timelines, and budget suggestions. Users can browse templates, apply them to events, and manage checklists with custom tasks.

---

## List Templates

```
GET /templates
Authentication: None
Query: ?event_type_id={uuid}
```

**Success Response (200):**

```json
{
  "success": true,
  "data": [
    {
      "id": "uuid",
      "event_type_id": "uuid",
      "name": "Classic Wedding",
      "description": "Complete wedding planning template",
      "estimated_budget_min": 5000000,
      "estimated_budget_max": 20000000,
      "estimated_timeline_days": 90,
      "guest_range_min": 50,
      "guest_range_max": 500,
      "tips": ["Book venue 3 months ahead", "..."],
      "task_count": 15,
      "tasks": [
        {
          "id": "uuid",
          "title": "Book venue",
          "description": "Research and reserve event venue",
          "category": "Venue",
          "priority": "high",
          "days_before_event": 90,
          "display_order": 1
        }
      ],
      "display_order": 1
    }
  ]
}
```

---

## Get Template Detail

```
GET /templates/{template_id}
Authentication: None
```

---

## Get Event Checklist

```
GET /user-events/{event_id}/checklist
Authorization: Bearer {token}
```

**Success Response (200):**

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "uuid",
        "event_id": "uuid",
        "template_task_id": "uuid|null",
        "title": "Book venue",
        "description": "...",
        "category": "Venue",
        "priority": "high",
        "status": "completed",
        "due_date": "2026-03-01T00:00:00",
        "completed_at": "2026-02-20T10:00:00",
        "assigned_to": "John",
        "notes": "Confirmed with deposit",
        "display_order": 1,
        "created_at": "...",
        "updated_at": "..."
      }
    ],
    "summary": {
      "total": 15,
      "completed": 5,
      "in_progress": 3,
      "pending": 7,
      "progress_percentage": 33.3
    }
  }
}
```

---

## Add Checklist Item

```
POST /user-events/{event_id}/checklist
Authorization: Bearer {token}
```

**Request Body:**

```json
{
  "title": "Book photographer",
  "description": "Find and book event photographer",
  "category": "Photography",
  "priority": "high",
  "due_date": "2026-03-15",
  "assigned_to": "Sarah",
  "notes": "Check portfolio first"
}
```

| Field       | Type                  | Required             |
| ----------- | --------------------- | -------------------- |
| title       | string                | Yes                  |
| description | string                | No                   |
| category    | string                | No                   |
| priority    | enum(high,medium,low) | No (default: medium) |
| due_date    | ISO date              | No                   |
| assigned_to | string                | No                   |
| notes       | string                | No                   |

---

## Update Checklist Item

```
PUT /user-events/{event_id}/checklist/{item_id}
Authorization: Bearer {token}
```

**Request Body:** Any fields from Add (all optional) + `status` (pending|in_progress|completed|skipped)

---

## Delete Checklist Item

```
DELETE /user-events/{event_id}/checklist/{item_id}
Authorization: Bearer {token}
```

---

## Apply Template to Event

```
POST /user-events/{event_id}/checklist/from-template
Authorization: Bearer {token}
```

**Request Body:**

```json
{
  "template_id": "uuid",
  "clear_existing": false
}
```

**Success Response:**

```json
{
  "success": true,
  "message": "Template applied — 15 tasks added to checklist",
  "data": { "added": 15, "template_name": "Classic Wedding" }
}
```

---

## Reorder Checklist Items

```
PUT /user-events/{event_id}/checklist/reorder
Authorization: Bearer {token}
```

**Request Body:**

```json
{
  "items": [
    { "id": "uuid", "display_order": 1 },
    { "id": "uuid", "display_order": 2 }
  ]
}
```

---

# 💰 MODULE: CONTRIBUTION MANAGEMENT (Extended)

---

## Reject Pending Contributions

Rejects one or more pending contributions. Deletes the records and sends SMS notification to each contributor informing them the payment record was removed because the amount could not be verified.

```
POST /user-contributors/events/{event_id}/reject-contributions
Authorization: Bearer {token}
```

**Request Body:**

```json
{
  "contribution_ids": ["uuid", "uuid"]
}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "2 contributions rejected and removed",
  "data": { "rejected": 2 }
}
```

**Access:** Event creator only.

**SMS Notification:** Each rejected contributor receives:

> "Hello {name}, your contribution record of {currency} {amount} for {event} recorded by {recorder} has been removed by the event organizer because the amount could not be verified. If you believe this is an error, please contact the organizer directly."

---

## Delete a Specific Transaction

Permanently deletes a specific payment/transaction from a contributor's history. Creator only.

```
DELETE /user-contributors/events/{event_id}/contributors/{ec_id}/payments/{payment_id}
Authorization: Bearer {token}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Transaction deleted successfully"
}
```

**Access:** Event creator only.

---

## Contribution Report — Date Filtering Behavior

When a date range is specified (`date_from`, `date_to`), the report only includes contributors who have **paid > 0** within the selected period. Contributors with pledges but no payments in that range are excluded from the filtered report. All-time summary totals remain unchanged in `full_summary`.

---

# 💰 MODULE: EVENT EXPENSES

Event expense tracking allows organizers and authorized committee members to record, categorize, and manage event costs. Deductions are tracked against money raised via contributions.

## Permissions

- **`can_view_expenses`** — View expense records and reports
- **`can_manage_expenses`** — Record, edit, delete expenses (auto-grants `can_view_expenses`)
- **Event creator** — Full access to all expense operations

When an expense is recorded with `notify_committee: true`, all committee members with `can_view_expenses` or `can_manage_expenses` permission (and the event creator) receive an `expense_recorded` notification.

---

## Get Event Expenses

```
GET /user-events/{eventId}/expenses
Authorization: Bearer {access_token}
```

**Query Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| page | integer | 1 | Page number |
| limit | integer | 100 | Items per page |
| category | string | — | Filter by category |
| search | string | — | Search description, vendor, or category |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Expenses retrieved",
  "data": {
    "expenses": [
      {
        "id": "uuid",
        "event_id": "uuid",
        "category": "Catering",
        "description": "Food for 200 guests",
        "amount": 1500000,
        "payment_method": "mobile",
        "payment_reference": "MP-12345",
        "vendor_name": "Mama Ntilie Catering",
        "receipt_url": null,
        "expense_date": "2025-06-01T00:00:00",
        "notes": "Paid in full",
        "recorded_by_id": "uuid",
        "recorded_by_name": "John Doe",
        "created_at": "2025-06-01T10:00:00",
        "updated_at": "2025-06-01T10:00:00"
      }
    ],
    "summary": {
      "total_expenses": 3500000,
      "count": 5,
      "currency": "TZS",
      "category_breakdown": [
        { "category": "Catering", "total": 1500000, "count": 1 },
        { "category": "Venue", "total": 2000000, "count": 4 }
      ]
    },
    "pagination": {
      "page": 1,
      "limit": 100,
      "total_items": 5,
      "total_pages": 1,
      "has_next": false,
      "has_previous": false
    }
  }
}
```

**Access:** Event creator, or committee member with `can_view_expenses` or `can_manage_expenses`.

---

## Record an Expense

```
POST /user-events/{eventId}/expenses
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:**

```json
{
  "category": "Catering",
  "description": "Food for 200 guests",
  "amount": 1500000,
  "payment_method": "mobile",
  "payment_reference": "MP-12345",
  "vendor_name": "Mama Ntilie Catering",
  "expense_date": "2025-06-01",
  "notes": "Paid in full",
  "notify_committee": true
}
```

| Field             | Type    | Required | Description                                                                      |
| ----------------- | ------- | -------- | -------------------------------------------------------------------------------- |
| category          | string  | Yes      | Expense category (e.g., Venue, Catering, Decorations)                            |
| description       | string  | Yes      | What the expense was for                                                         |
| amount            | number  | Yes      | Amount spent                                                                     |
| payment_method    | string  | No       | cash, mobile, bank_transfer, card, cheque, other                                 |
| payment_reference | string  | No       | Receipt or reference number                                                      |
| vendor_name       | string  | No       | Vendor or supplier name                                                          |
| expense_date      | string  | No       | Date of expense (YYYY-MM-DD), defaults to today                                  |
| notes             | string  | No       | Additional notes                                                                 |
| notify_committee  | boolean | No       | Send notification to committee members with expense permissions (default: false) |

**Success Response (201):**

```json
{
  "success": true,
  "message": "Expense recorded successfully",
  "data": { "id": "uuid", "category": "Catering", "amount": 1500000, ... }
}
```

**Access:** Event creator, or committee member with `can_manage_expenses`.

**Notification:** When `notify_committee` is true, an `expense_recorded` notification is sent to all committee members with `can_view_expenses` or `can_manage_expenses`, and to the event creator (if not the recorder).

---

## Update an Expense

```
PUT /user-events/{eventId}/expenses/{expenseId}
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:** (all fields optional)

```json
{
  "category": "Venue",
  "description": "Updated description",
  "amount": 2000000,
  "payment_method": "bank_transfer",
  "vendor_name": "New Venue Ltd",
  "expense_date": "2025-06-05",
  "notes": "Updated notes"
}
```

**Access:** Event creator, or committee member with `can_manage_expenses`.

---

## Delete an Expense

```
DELETE /user-events/{eventId}/expenses/{expenseId}
Authorization: Bearer {access_token}
```

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Expense deleted successfully"
}
```

**Access:** Event creator, or committee member with `can_manage_expenses`.

---

## Get Expense Report

Generates a detailed expense report with optional date range filtering. Summary always reflects all-time totals regardless of date filter.

```
GET /user-events/{eventId}/expenses/report
Authorization: Bearer {access_token}
```

**Query Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| date_from | string | Start date (YYYY-MM-DD) |
| date_to | string | End date (YYYY-MM-DD) |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Expense report generated",
  "data": {
    "expenses": [
      {
        "category": "Catering",
        "description": "Food for guests",
        "amount": 1500000,
        "vendor_name": "Mama Ntilie",
        "expense_date": "2025-06-01T00:00:00",
        "payment_method": "mobile",
        "recorded_by_name": "John Doe"
      }
    ],
    "summary": {
      "total_expenses": 3500000,
      "count": 5,
      "currency": "TZS",
      "category_breakdown": [
        { "category": "Catering", "total": 1500000, "count": 1 }
      ]
    }
  }
}
```

**Access:** Event creator, or committee member with `can_view_expenses` or `can_manage_expenses`.

---

## Expense Categories (Frontend Standard)

The following categories are used in the UI:

- Venue
- Catering
- Decorations
- Entertainment
- Photography
- Transport
- Printing
- Gifts & Favors
- Equipment Rental
- Marketing
- Staffing
- Miscellaneous

---

# 🛡️ MODULE 20: ADMIN PANEL

All admin endpoints require authentication (Bearer token) from a user with `is_admin = true`.

---

## 20.1 Dashboard Stats

```
GET /admin/stats
Authentication: Required (Admin)
```

**Response 200:**

```json
{
  "success": true,
  "data": {
    "total_users": 1240,
    "total_events": 450,
    "total_services": 180,
    "pending_kyc": 12,
    "open_tickets": 7,
    "active_chats": 3,
    "waiting_chats": 2
  }
}
```

---

## 20.2 Extended Dashboard Stats

```
GET /admin/stats/extended
Authentication: Required (Admin)
```

**Response 200:**

```json
{
  "success": true,
  "data": {
    "total_posts": 5200,
    "total_moments": 3100,
    "total_communities": 45,
    "total_bookings": 320,
    "pending_bookings": 18,
    "pending_card_orders": 6
  }
}
```

---

## 20.3 User Management

### List Users

```
GET /admin/users
Authentication: Required (Admin)
Query Parameters:
  - page (int, default 1)
  - limit (int, default 20)
  - q (string, search by name/email/username/phone)
  - is_active (bool, filter by active status)
```

**Response 200:**

```json
{
  "success": true,
  "data": [
    {
      "id": "uuid",
      "first_name": "Jane",
      "last_name": "Doe",
      "username": "janedoe",
      "email": "jane@example.com",
      "phone": "+254700000000",
      "avatar": "https://...",
      "is_active": true,
      "is_email_verified": true,
      "is_phone_verified": true,
      "is_identity_verified": false,
      "created_at": "2025-01-01T00:00:00Z"
    }
  ]
}
```

### Get User Detail

```
GET /admin/users/{user_id}
Authentication: Required (Admin)
```

### Activate User

```
PUT /admin/users/{user_id}/activate
Authentication: Required (Admin)
```

### Deactivate User

```
PUT /admin/users/{user_id}/deactivate
Authentication: Required (Admin)
```

---

## 20.4 KYC / Service Verification

### List KYC Submissions

```
GET /admin/kyc
Authentication: Required (Admin)
Query Parameters:
  - page, limit
  - status (string: "pending" | "verified" | "rejected")
```

**Response 200:**

```json
{
  "success": true,
  "data": [
    {
      "id": "uuid",
      "service_id": "uuid",
      "service_name": "Elite Photography",
      "status": "pending",
      "notes": null,
      "submitted_at": "2025-02-01T10:00:00Z",
      "user": {
        "id": "uuid",
        "name": "John Doe",
        "email": "john@example.com",
        "avatar": "https://..."
      }
    }
  ]
}
```

### Get KYC Detail

```
GET /admin/kyc/{verification_id}
Authentication: Required (Admin)
```

**Response 200:**

```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "service_name": "Elite Photography",
    "status": "pending",
    "notes": null,
    "submitted_at": "2025-02-01T10:00:00Z",
    "files": [
      {
        "id": "uuid",
        "file_url": "https://...",
        "kyc_requirement_id": "uuid",
        "uploaded_at": "2025-02-01T10:00:00Z"
      }
    ],
    "user": { "id": "uuid", "name": "John Doe", "email": "john@example.com" }
  }
}
```

### Approve KYC

```
PUT /admin/kyc/{verification_id}/approve
Authentication: Required (Admin)
```

**Request Body:**

```json
{ "notes": "All documents verified successfully." }
```

### Reject KYC

```
PUT /admin/kyc/{verification_id}/reject
Authentication: Required (Admin)
```

**Request Body:**

```json
{ "notes": "Business registration document is expired." }
```

---

## 20.5 Event Types Management

### List Event Types

```
GET /admin/event-types
Authentication: Required (Admin)
```

### Create Event Type

```
POST /admin/event-types
Authentication: Required (Admin)
```

**Request Body:**

```json
{ "name": "Cultural Festival", "description": "...", "icon": "🎭" }
```

### Update Event Type

```
PUT /admin/event-types/{type_id}
Authentication: Required (Admin)
```

### Delete Event Type

```
DELETE /admin/event-types/{type_id}
Authentication: Required (Admin)
```

---

## 20.6 Events (Read-Only)

```
GET /admin/events
Authentication: Required (Admin)
Query Parameters: page, limit, q (search), status
```

---

## 20.7 Services (Read-Only)

```
GET /admin/services
Authentication: Required (Admin)
Query Parameters: page, limit, q (search), status
```

---

## 20.8 Posts / Feed Moderation

### List Posts

```
GET /admin/posts
Authentication: Required (Admin)
Query Parameters: page, limit, q (search content)
```

**Response 200:**

```json
{
  "success": true,
  "data": [
    {
      "id": "uuid",
      "content": "Had an amazing time at...",
      "is_active": true,
      "glow_count": 24,
      "echo_count": 5,
      "location": "Nairobi",
      "created_at": "2025-02-10T12:00:00Z",
      "images": [{ "url": "https://..." }],
      "user": {
        "id": "uuid",
        "name": "Jane Doe",
        "username": "janedoe",
        "avatar": "https://..."
      }
    }
  ]
}
```

### Remove Post (Soft Delete)

```
DELETE /admin/posts/{post_id}
Authentication: Required (Admin)
```

Sets `is_active = false` — does not permanently delete.

---

## 20.9 Moments Moderation

### List Moments

```
GET /admin/moments
Authentication: Required (Admin)
Query Parameters: page, limit, q (search caption)
```

### Remove Moment (Soft Delete)

```
DELETE /admin/moments/{moment_id}
Authentication: Required (Admin)
```

---

## 20.10 Communities

### List Communities

```
GET /admin/communities
Authentication: Required (Admin)
Query Parameters: page, limit, q (search name)
```

### Delete Community

```
DELETE /admin/communities/{community_id}
Authentication: Required (Admin)
```

Permanently deletes the community and all associated members/posts (CASCADE).

---

## 20.11 Bookings (Read-Only)

```
GET /admin/bookings
Authentication: Required (Admin)
Query Parameters: page, limit, status (pending|accepted|rejected|completed)
```

---

## 20.12 NuruCard Orders

### List Orders

```
GET /admin/nuru-cards
Authentication: Required (Admin)
Query Parameters: page, limit, status (pending|processing|shipped|delivered|cancelled)
```

### Update Order Status

```
PUT /admin/nuru-cards/{order_id}/status
Authentication: Required (Admin)
```

**Request Body:**

```json
{ "status": "shipped", "tracking_number": "KE123456789" }
```

---

## 20.13 Live Chat (Admin)

### List Chat Sessions

```
GET /admin/chats
Authentication: Required (Admin)
Query Parameters: page, limit, status (waiting|active|ended|abandoned)
```

**Response 200:**

```json
{
  "success": true,
  "data": [
    {
      "id": "uuid",
      "status": "waiting",
      "last_message": "Hi, I need help with my booking",
      "last_message_at": "2025-02-10T14:00:00Z",
      "created_at": "2025-02-10T13:55:00Z",
      "user": {
        "id": "uuid",
        "name": "John Doe",
        "email": "john@example.com",
        "avatar": "https://..."
      }
    }
  ]
}
```

### Get Chat Messages

```
GET /admin/chats/{chat_id}/messages
Authentication: Required (Admin)
Query Parameters:
  - after (ISO timestamp, for polling only new messages)
```

**Response 200:**

```json
{
  "success": true,
  "data": {
    "session_status": "active",
    "messages": [
      {
        "id": "uuid",
        "content": "Hi, I need help",
        "sender": "user",
        "sender_name": "John Doe",
        "sent_at": "2025-02-10T14:00:00Z"
      },
      {
        "id": "uuid",
        "content": "Sure, I can help with that.",
        "sender": "agent",
        "sender_name": "Support Team",
        "sent_at": "2025-02-10T14:01:00Z"
      }
    ]
  }
}
```

### Reply to Chat

```
POST /admin/chats/{chat_id}/reply
Authentication: Required (Admin)
```

**Request Body:**

```json
{ "content": "Sure, I can help with that." }
```

Automatically assigns the replying admin as the session agent and sets status to `active`.

### Close Chat

```
PUT /admin/chats/{chat_id}/close
Authentication: Required (Admin)
```

---

## 20.14 Support Tickets (Admin)

### List Tickets

```
GET /admin/tickets
Authentication: Required (Admin)
Query Parameters: page, limit, status (open|closed)
```

### Get Ticket Detail

```
GET /admin/tickets/{ticket_id}
Authentication: Required (Admin)
```

### Reply to Ticket

```
POST /admin/tickets/{ticket_id}/reply
Authentication: Required (Admin)
```

**Request Body:**

```json
{ "message": "We have resolved your issue. Please check again." }
```

### Close Ticket

```
PUT /admin/tickets/{ticket_id}/close
Authentication: Required (Admin)
```

---

## 20.15 FAQs Management

### List FAQs

```
GET /admin/faqs
Authentication: Required (Admin)
```

### Create FAQ

```
POST /admin/faqs
Authentication: Required (Admin)
```

**Request Body:**

```json
{
  "question": "How do I verify my service?",
  "answer": "Go to My Services → Verify → Upload required documents.",
  "category": "Services",
  "display_order": 1,
  "is_active": true
}
```

### Update FAQ

```
PUT /admin/faqs/{faq_id}
Authentication: Required (Admin)
```

### Delete FAQ

```
DELETE /admin/faqs/{faq_id}
Authentication: Required (Admin)
```

---

## 20.16 Service Categories Management

### List Categories

```
GET /admin/service-categories
Authentication: Required (Admin)
```

### Create Category

```
POST /admin/service-categories
Authentication: Required (Admin)
```

**Request Body:**

```json
{ "name": "Photography", "description": "Photo and video services" }
```

### Update Category

```
PUT /admin/service-categories/{cat_id}
Authentication: Required (Admin)
```

### Delete Category

```
DELETE /admin/service-categories/{cat_id}
Authentication: Required (Admin)
```

---

## 20.17 Broadcast Notifications

```
POST /admin/notifications/broadcast
Authentication: Required (Admin)
```

**Request Body:**

```json
{
  "title": "Platform Update",
  "message": "We've added new features to Nuru. Check them out!"
}
```

Sends a `system` type notification to **all active users**.

**Response 200:**

```json
{
  "success": true,
  "message": "Notification sent to 1240 users"
}
```

---

## Admin Panel Routes (Frontend)

| Path                        | Page                      |
| --------------------------- | ------------------------- |
| `/admin/login`              | Admin login               |
| `/admin`                    | Dashboard                 |
| `/admin/users`              | User management           |
| `/admin/kyc`                | KYC verification          |
| `/admin/services`           | Services overview         |
| `/admin/service-categories` | Service categories CRUD   |
| `/admin/events`             | Events overview           |
| `/admin/event-types`        | Event types CRUD          |
| `/admin/posts`              | Post/feed moderation      |
| `/admin/moments`            | Moments moderation        |
| `/admin/communities`        | Community moderation      |
| `/admin/bookings`           | Bookings overview         |
| `/admin/nuru-cards`         | NuruCard order management |
| `/admin/chats`              | Live chat sessions        |
| `/admin/chats/:chatId`      | Chat detail + reply       |
| `/admin/tickets`            | Support tickets           |
| `/admin/faqs`               | FAQ management            |
| `/admin/notifications`      | Broadcast notifications   |

---

# 🔐 MODULE: ADMIN AUTHENTICATION

Admin authentication is **completely separate** from Nuru user authentication. Admin users are stored in the `admin_users` table and have no relation to the regular `users` table.

## Admin Users Table (`admin_users`)

| Column        | Type       | Description                             |
| ------------- | ---------- | --------------------------------------- |
| id            | UUID       | Primary key                             |
| full_name     | text       | Admin's full name                       |
| email         | text       | Unique email address                    |
| username      | text       | Unique username                         |
| password_hash | text       | SHA-256 hashed password                 |
| role          | admin_role | One of: `admin`, `moderator`, `support` |
| is_active     | boolean    | Whether account is active               |
| last_login_at | timestamp  | Timestamp of last successful login      |
| created_at    | timestamp  | Account creation timestamp              |
| updated_at    | timestamp  | Last update timestamp                   |

**Roles:** `admin` (full control), `moderator` (content moderation), `support` (tickets & chat)

**Creating the first admin (SQL):**

```sql
INSERT INTO admin_users (full_name, email, username, password_hash, role)
VALUES ('Admin Name', 'admin@nuru.tz', 'admin', encode(sha256('yourpassword'::bytea), 'hex'), 'admin');
```

---

## Admin Login

```
POST /admin/auth/login
Content-Type: application/json
Authentication: None
```

**Request Body:**

```json
{
  "username": "admin",
  "password": "yourpassword"
}
```

**Success Response (200):**

```json
{
  "success": true,
  "message": "Login successful",
  "data": {
    "access_token": "eyJ...",
    "refresh_token": "eyJ...",
    "token_type": "bearer",
    "admin": {
      "id": "uuid",
      "full_name": "Admin Name",
      "email": "admin@nuru.tz",
      "username": "admin",
      "role": "admin"
    }
  }
}
```

**Frontend Storage:** Tokens stored in `localStorage` as `admin_token`, `admin_refresh_token`, `admin_user` (isolated from user session).

---

## Admin Token Refresh

```
POST /admin/auth/refresh
Content-Type: application/json
Authentication: None
```

**Request Body:**

```json
{ "refresh_token": "eyJ..." }
```

**Success Response (200):**

```json
{
  "success": true,
  "message": "Token refreshed",
  "data": { "access_token": "eyJ...", "token_type": "bearer" }
}
```

---

## Admin Authorization

All admin-protected routes require `Authorization: Bearer {admin_token}`. Admin JWTs carry an `is_admin: true` claim. The `require_admin` dependency validates:

1. JWT signature and expiry
2. `is_admin` claim is `true`
3. Admin exists and `is_active = true` in `admin_users`

Regular Nuru user tokens are **rejected** by all `/admin/*` endpoints.

---

# 🛡️ MODULE: ADMIN PANEL ENDPOINTS

All endpoints below require `Authorization: Bearer {admin_token}`.

**Frontend client:** `src/lib/api/admin.ts` — `adminApi` object  
**Backend guard:** `require_admin` dependency (AdminUser returned, NOT User)  
**Pagination:** Backend returns `pagination` at root level alongside `data`:

```json
{ "success": true, "data": [...], "pagination": { "page": 1, "total_pages": 5, "total_items": 98 } }
```

---

## Dashboard

### GET /admin/stats

Core counters: `total_users`, `total_events`, `total_services`, `pending_kyc`, `open_tickets`, `active_chats`, `waiting_chats`

### GET /admin/stats/extended

Extended counters: `total_posts`, `total_moments`, `total_communities`, `total_bookings`, `pending_bookings`, `pending_card_orders`

---

## User Management

### GET /admin/users — Query: `page`, `limit`, `q` (name/email/phone), `is_active`

### GET /admin/users/{user_id} — Full detail + `event_count`, `service_count`, `bio`, `location`

### PUT /admin/users/{user_id}/activate — Sets `is_active = true`

### PUT /admin/users/{user_id}/deactivate — Sets `is_active = false`

---

## KYC / Service Verification

### GET /admin/kyc — Query: `page`, `limit`, `status` (`pending`|`verified`|`rejected`)

### GET /admin/kyc/{verification_id} — Includes `files: [{ id, file_url, uploaded_at }]`

### PUT /admin/kyc/{verification_id}/approve — Body: `{ "notes": "..." }` (optional)

### PUT /admin/kyc/{verification_id}/reject — Body: `{ "notes": "..." }` (required)

---

## Event Types

### GET /admin/event-types

### POST /admin/event-types — Body: `{ name, description, icon }`

### PUT /admin/event-types/{type_id} — Body: any of `{ name, description, icon, is_active }`

### DELETE /admin/event-types/{type_id}

---

## Live Chats

### GET /admin/chats — Query: `status` (`waiting`|`active`|`ended`)

Response items include: `id`, `status`, `last_message`, `last_message_at`, `user`

### GET /admin/chats/{chat_id}/messages?after={iso}

Returns `{ messages: [...], session_status }`. Poll with `?after=` for real-time updates.
Message shape: `{ id, content, sender: "agent"|"user"|"system", sender_name, sent_at }`

### POST /admin/chats/{chat_id}/reply — Body: `{ "content": "..." }`

Uses `admin.id` and `admin.full_name` for sender attribution.

### PUT /admin/chats/{chat_id}/close — Sets session to `ended`

---

## Support Tickets

### GET /admin/tickets — Query: `status` (`open`|`closed`)

### GET /admin/tickets/{ticket_id} — Includes `messages: [{ id, content, is_agent, sender_name, created_at }]`

### POST /admin/tickets/{ticket_id}/reply — Body: `{ "message": "..." }` — Uses `admin.id` as `sender_id`

### PUT /admin/tickets/{ticket_id}/close — Sets `status = closed`

---

## FAQs

### GET /admin/faqs — Sorted by `display_order asc`

### POST /admin/faqs — Body: `{ question, answer, category, display_order, is_active }`

### PUT /admin/faqs/{faq_id}

### DELETE /admin/faqs/{faq_id}

---

## Events (Read-only)

### GET /admin/events — Query: `q` (name search), `status`

Response: `{ id, name, status, date, location, organizer: { id, name } }`

---

## Services (Read-only)

### GET /admin/services — Query: `q`, `status` (verification_status)

Response: `{ id, name, category, verification_status, is_active, user: { id, name, avatar } }`

---

## Notifications Broadcast

### POST /admin/notifications/broadcast

Body: `{ "title": "...", "message": "..." }` — Sends system notification to **all active users**

---

## Posts / Moments / Communities

### GET /admin/posts — Query: `q` (content search) — Response includes `images[]`, `user`

### DELETE /admin/posts/{post_id} — Soft-delete (`is_active = false`)

### GET /admin/moments — Query: `q` (caption search)

### DELETE /admin/moments/{moment_id} — Soft-delete (`is_active = false`)

### GET /admin/communities — Query: `q`

### DELETE /admin/communities/{community_id} — Hard-delete

---

## Bookings (Read-only)

### GET /admin/bookings — Query: `status`

Response: `{ id, status, proposed_price, quoted_price, message, service, requester }`

---

## NuruCard Orders

### GET /admin/nuru-cards — Query: `status`

Response: `{ id, card_type, quantity, status, payment_status, amount, delivery_city, tracking_number, user }`

### PUT /admin/nuru-cards/{order_id}/status — Body: `{ "status": "shipped", "tracking_number": "TZ123" }`

---

## Service Categories & KYC Management

### GET /admin/service-categories — Sorted by name

### POST /admin/service-categories — Body: `{ name, description, icon }`

### PUT /admin/service-categories/{cat_id}

### DELETE /admin/service-categories/{cat_id}

### GET /admin/service-categories/{cat_id}/service-types

Returns service types (sub-categories) within a category.
Response: `[ { id, name, description, requires_kyc } ]`

> **KYC is managed at the service type level, not the category level.**
> The `service_kyc_mapping` table links `service_type_id → kyc_requirement_id`.

### GET /admin/service-types/{type_id}/kyc-requirements

Returns KYC requirements mapped to a specific service type.
Response: `[ { mapping_id, id, name, description, is_mandatory } ]`

### POST /admin/service-types/{type_id}/kyc-requirements

Body: `{ "kyc_requirement_id": "<uuid>", "is_mandatory": true }`
Inserts a row into `service_kyc_mapping`.

### DELETE /admin/service-types/{type_id}/kyc-requirements/{mapping_id}

Removes the mapping from `service_kyc_mapping` by the mapping row id.

### GET /admin/kyc-definitions

Returns all available KYC requirement definitions from `kyc_requirements` table.
Used to populate the dropdown when adding KYC to a service type.
Response: `[ { id, name, description } ]`

---

## Content Appeals

### POST /posts/{post_id}/appeal

Submit an appeal for a removed post.

- Auth: Bearer token (post owner only)
- Body: `{ "reason": "string (min 10 chars)" }`
- Returns: `{ id, status: "pending" }`
- Errors: 400 if post is still active, already appealed, or reason is too short

### GET /admin/appeals

List all content appeals (admin only).

- Auth: Admin token
- Query: `page`, `limit`, `status` (pending|approved|rejected)
- Returns: paginated list with `content_preview`, `content_type`, `user`, `appeal_reason`, `admin_notes`, `reviewed_at`

### PUT /admin/appeals/{appeal_id}/approve

Approve an appeal — restores the post/moment and notifies the user.

- Auth: Admin token
- Body: `{ "notes": "optional admin note" }`

### PUT /admin/appeals/{appeal_id}/reject

Reject an appeal — content stays removed, user is notified with reason.

- Auth: Admin token
- Body: `{ "notes": "reason for rejection (required)" }`

---

## Admin Posts (Updated)

### GET /admin/posts

Returns live glow and echo counts queried directly from `user_feed_glows` and `user_feed_comments` tables (not stale denormalized columns). Also returns `removal_reason` for removed posts.

### PUT /admin/posts/{post_id}/status

Update post active status and persist removal reason.

- Body: `{ "is_active": bool, "reason": "string (optional, used when removing)" }`
- Removal reason is saved to `user_feeds.removal_reason` and included in user notification.
- Restoring a post clears `removal_reason`.

---

## Seed Data Reference

The following seed data must be applied to a fresh database:

### Service Categories (10)

Entertainment, Catering, Logistics, Photography and Videography, Decor and Setup, Planning, Rentals, Audio Visual, Security, Cleaning

### KYC Requirements (5)

- Government-issued ID
- Business License
- Tax Compliance Certificate
- Professional Certification
- Portfolio/Work Samples

### Service Types (28 sub-types across all categories)

See `database.sql` SEED DATA section for full INSERT statements with `ON CONFLICT DO NOTHING` for idempotent re-runs.

### GET /admin/appeals — Query: `page`, `limit`, `status` (pending|approved|rejected)

Response: `[ { id, content_id, content_type, appeal_reason, status, admin_notes, created_at, user } ]`

### PUT /admin/appeals/{appeal_id}/review

Body: `{ "decision": "approved" | "rejected", "notes": "..." }`

- `approved` → restores the content (`is_active = true`, `removal_reason = null`) and notifies the user
- `rejected` → keeps content removed; notifies user with admin notes

---

## User Appeals (Workspace)

### POST /appeals

Body: `{ "content_id": "<uuid>", "content_type": "post" | "moment", "appeal_reason": "..." }`

- One appeal per content item (409 if already submitted)

---

## Content Removal Fields

### user_feeds — added columns:

- `removal_reason TEXT` — set when admin removes a post; included in notification `message_data`

### user_moments — added columns:

- `removal_reason TEXT` — set when admin removes a moment; included in notification `message_data`

---

## Frontend Admin Client Notes

- **File:** `src/lib/api/admin.ts` — `adminApi` export
- **Token:** Always reads `admin_token` from localStorage (never the regular user `token`)
- **401 handling:** Clears admin session + redirects to `/admin/login`
- **Pagination:** `(res as any).pagination` — preserved at root level by `adminRequest` helper
- **Route guard:** `AdminLayout` checks `admin_token` on mount, redirects to `/admin/login` if absent
- **Auth dependency changed:** All backend admin endpoints use `Depends(require_admin)` returning `AdminUser` — `get_current_user` is NOT used in admin routes

---

# 🧠 MODULE 30: FEED RANKING & RECOMMENDATION SYSTEM

## System Overview

Nuru uses an intelligent, multi-factor feed ranking system that replaces chronological ordering with personalized content delivery. The system is optimized for meaningful event-based content (weddings, birthdays, memorials, corporate events) rather than addictive viral content.

### Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Client App    │────▶│  Feed Endpoint   │────▶│   Candidate     │
│  (React/Vite)   │     │  /posts/feed     │     │   Generation    │
│                 │     │  ?mode=ranked    │     │   (500-1500)    │
└────────┬────────┘     └────────┬─────────┘     └────────┬────────┘
         │                       │                         │
         │  Interactions         │  Scoring                │  Sources:
         │  (batched)            │                         │  - Following
         ▼                       ▼                         │  - Circles
┌─────────────────┐     ┌──────────────────┐              │  - Events
│  Interaction    │     │   Multi-Factor   │              │  - Trending
│  Tracking API   │────▶│   Scoring        │              │  - Platform
│  /feed/interact │     │   Algorithm      │              └──────────────
└─────────────────┘     └────────┬─────────┘
                                 │
                        ┌────────▼─────────┐
                        │  Diversity       │
                        │  Re-Ranking      │
                        └────────┬─────────┘
                                 │
                        ┌────────▼─────────┐
                        │  Paginated       │
                        │  Response        │
                        └──────────────────┘
```

### Data Models

#### user_interaction_logs

Tracks every user interaction with feed content.

| Column           | Type      | Description                                                                                                     |
| ---------------- | --------- | --------------------------------------------------------------------------------------------------------------- |
| id               | UUID      | Primary key                                                                                                     |
| user_id          | UUID      | FK → users.id                                                                                                   |
| post_id          | UUID      | FK → user_feeds.id                                                                                              |
| interaction_type | text      | view, dwell, glow, unglow, comment, echo, spark, save, unsave, click_image, click_profile, hide, report, expand |
| dwell_time_ms    | integer   | Milliseconds user spent viewing (for dwell events)                                                              |
| session_id       | text      | Groups interactions within one feed session                                                                     |
| device_type      | text      | mobile, desktop, tablet                                                                                         |
| created_at       | timestamp | Auto-generated                                                                                                  |

#### user_interest_profiles

Stores per-user interest vectors, updated after each interaction.

| Column           | Type      | Description                                                                 |
| ---------------- | --------- | --------------------------------------------------------------------------- |
| user_id          | UUID      | PK, FK → users.id                                                           |
| interest_vector  | JSONB     | Category interest scores (0.0-1.0) e.g. {"wedding": 0.82, "birthday": 0.45} |
| engagement_stats | JSONB     | Aggregate stats: total_glows, total_comments, total_dwell_ms, etc.          |
| negative_signals | JSONB     | Hidden authors, disliked categories                                         |
| last_computed_at | timestamp | Last recomputation time                                                     |

#### author_affinity_scores

Precomputed relationship strength between viewer and author.

| Column              | Type      | Description                         |
| ------------------- | --------- | ----------------------------------- |
| id                  | UUID      | Primary key                         |
| viewer_id           | UUID      | FK → users.id                       |
| author_id           | UUID      | FK → users.id                       |
| interaction_count   | integer   | Raw count of interactions           |
| weighted_score      | float     | Time-decayed weighted sum (0.0-1.0) |
| is_following        | boolean   | Whether viewer follows author       |
| shared_events_count | integer   | Events both participated in         |
| is_circle_member    | boolean   | Whether in each other's circle      |
| last_interaction_at | timestamp | Most recent interaction             |

#### post_quality_scores

Cached quality score for each post, recomputed every 30 minutes.

| Column              | Type    | Description                                          |
| ------------------- | ------- | ---------------------------------------------------- |
| post_id             | UUID    | PK, FK → user_feeds.id                               |
| engagement_velocity | float   | Engagements per hour since creation                  |
| content_richness    | float   | Score based on text, images, media (0.0-1.0)         |
| author_credibility  | float   | Based on author's engagement history (0.0-1.0)       |
| moderation_flag     | boolean | Flagged by moderation (suppresses ranking)           |
| spam_probability    | float   | Spam likelihood (0.0-1.0)                            |
| category            | text    | Detected category: wedding, birthday, memorial, etc. |
| final_quality_score | float   | Composite quality metric (0.0-1.0)                   |
| total_engagements   | integer | Weighted engagement count                            |
| engagement_rate     | float   | Engagements / impressions                            |
| impression_count    | integer | Times shown in feeds                                 |

#### feed_impressions

Tracks which posts were shown to which users and in what position.

| Column      | Type    | Description                |
| ----------- | ------- | -------------------------- |
| id          | UUID    | Primary key                |
| user_id     | UUID    | FK → users.id              |
| post_id     | UUID    | FK → user_feeds.id         |
| position    | integer | 0-indexed position in feed |
| session_id  | text    | Client session identifier  |
| was_engaged | boolean | Updated after interaction  |

---

## 30.1 Get Ranked Feed

Returns personalized, ranked feed posts.

```
GET /posts/feed
Authorization: Bearer {access_token}
```

**Query Parameters:**

| Param      | Type    | Default  | Description                                        |
| ---------- | ------- | -------- | -------------------------------------------------- |
| page       | integer | 1        | Page number                                        |
| limit      | integer | 20       | Items per page (max 100)                           |
| mode       | string  | "ranked" | "ranked" (intelligent) or "chronological" (legacy) |
| session_id | string  | null     | Client session ID for impression deduplication     |

**Success Response (200 OK):**

```json
{
  "success": true,
  "message": "Feed retrieved",
  "data": {
    "posts": [...],
    "pagination": {
      "page": 1,
      "limit": 20,
      "total_items": 342,
      "total_pages": 18,
      "has_next": true,
      "has_previous": false
    },
    "feed_mode": "ranked"
  }
}
```

**feed_mode values:**

- `ranked` — Full personalized ranking (user has ≥10 interactions)
- `cold_start` — Engagement-based ranking for new users (<10 interactions)
- `chronological` — Legacy mode (requested via mode=chronological)
- `chronological_fallback` — Automatic fallback on ranking error

---

## 30.2 Log Feed Interaction

Logs user interactions with feed content for ranking improvement.

```
POST /posts/feed/interactions
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Single Interaction:**

```json
{
  "post_id": "550e8400-e29b-41d4-a716-446655440000",
  "interaction_type": "glow",
  "dwell_time_ms": 5000,
  "session_id": "abc123",
  "device_type": "mobile"
}
```

**Batch Interactions (max 50):**

```json
{
  "interactions": [
    { "post_id": "uuid-1", "interaction_type": "view" },
    { "post_id": "uuid-1", "interaction_type": "dwell", "dwell_time_ms": 8200 },
    { "post_id": "uuid-2", "interaction_type": "glow" }
  ],
  "session_id": "abc123",
  "device_type": "mobile"
}
```

**Interaction Types:**

| Type          | Weight | Description                         |
| ------------- | ------ | ----------------------------------- |
| view          | 0.1    | Post entered viewport (50% visible) |
| dwell         | 0.3    | User spent >3s viewing              |
| glow          | 1.0    | User liked the post                 |
| unglow        | -0.5   | User unliked                        |
| comment       | 1.5    | User commented                      |
| echo          | 2.0    | User reposted                       |
| spark         | 2.5    | User shared externally              |
| save          | 1.2    | User bookmarked                     |
| unsave        | -0.3   | User removed bookmark               |
| click_image   | 0.4    | User clicked/tapped image           |
| click_profile | 0.6    | User navigated to author profile    |
| hide          | -2.0   | User hid the post                   |
| report        | -5.0   | User reported the post              |
| expand        | 0.3    | User expanded truncated text        |

---

## 30.3 Get User Interests

Returns the current user's computed interest profile.

```
GET /posts/feed/interests
Authorization: Bearer {access_token}
```

**Success Response:**

```json
{
  "success": true,
  "data": {
    "interest_vector": {
      "wedding": 0.82,
      "birthday": 0.45,
      "memorial": 0.12,
      "corporate_event": 0.6,
      "graduation": 0.33,
      "general": 0.5
    },
    "engagement_stats": {
      "total_glows": 142,
      "total_comments": 38,
      "total_dwell_ms": 892000
    },
    "last_computed_at": "2026-02-19T14:30:00",
    "is_default": false
  }
}
```

---

## Ranking Algorithm

### Scoring Formula

```
FinalScore = W1 × EngagementPrediction
           + W2 × RelationshipStrength
           + W3 × InterestMatch
           + W4 × RecencyDecay
           + W5 × ContentQuality
           + W6 × DiversityPenalty
           + W7 × ExplorationBoost
```

### Weight Configuration

| Weight | Value | Component                                                |
| ------ | ----- | -------------------------------------------------------- |
| W1     | 0.25  | Engagement Prediction — P(like, comment, dwell >3s)      |
| W2     | 0.22  | Relationship Strength — Viewer-author affinity           |
| W3     | 0.18  | Interest Match — Post category vs user interest vector   |
| W4     | 0.15  | Recency Decay — Exponential time decay                   |
| W5     | 0.10  | Content Quality — Richness + credibility score           |
| W6     | -0.05 | Diversity Penalty — Penalize repeated authors/categories |
| W7     | 0.05  | Exploration Boost — Inject novel content                 |

### Component Details

**Engagement Prediction:**

- Heuristic model using engagement velocity (engagements/hour)
- Sigmoid normalization: `1 / (1 + exp(-0.5 × (velocity - 2)))`
- Boosted by user's interest match with content category

**Relationship Strength:**

- From `author_affinity_scores.weighted_score`
- Base 0.4 if following, 0.0 if not
- Incrementally updated on each interaction
- Factors: interaction count, follow status, circle membership, shared events

**Interest Match:**

- User interest vector lookup by detected post category
- Categories: wedding, birthday, memorial, graduation, baby_shower, corporate_event, fundraiser, cultural, general
- Category detection via keyword matching in post content
- Updated via exponential moving average (α=0.05) after each interaction

**Recency Decay:**

```
RecencyScore = exp(-λ × age_in_hours)
λ = 0.04
```

- 50% score at ~17 hours
- 25% score at ~35 hours
- 10% score at ~57 hours

**Content Quality:**

```
quality = content_richness × 0.3 + author_credibility × 0.3 + engagement_velocity_norm × 0.4
```

- Content richness: text length, image count, video presence
- Author credibility: historical engagement on author's posts
- Suppressed if moderation_flag=true or spam_probability>0.5

**Diversity Penalty:**

- Max 2 posts from same author in sliding window of 10
- Max 4 posts from same category in sliding window of 10
- Deferred posts re-inserted at appropriate score positions

**Exploration Boost:**

- 8% of feed slots reserved for exploration
- Deterministic per user-post-day (hash-based)
- Exposes new creators and content categories

### Candidate Generation Sources

| Source                                  | Limit | Priority        |
| --------------------------------------- | ----- | --------------- |
| Following users' posts                  | 500   | Highest         |
| Circle members' posts                   | 300   | High            |
| Shared event participants' posts        | 200   | High            |
| Own posts                               | 50    | Always included |
| Trending/high-engagement platform posts | 500   | Fill remaining  |

Total pool: up to 1,500 candidates

### Cold Start Strategy

For new users with <10 interactions:

1. Recent high-quality posts with images (visual appeal)
2. Posts from popular authors (social proof)
3. Round-robin across categories for exploration
4. Chronological tiebreaker within each category
5. 3-day lookback window

### Safeguards

- Moderation-flagged posts suppressed (quality × 0.1)
- Spam-probable posts penalized proportionally
- Hidden/reported authors tracked in negative_signals
- Graceful fallback to chronological on any ranking error
- No pure engagement optimization — meaningful content prioritized

### Background Tasks

- **Quality Score Recomputation:** Every 30 minutes, recomputes `post_quality_scores` for up to 500 recent posts
- **Content Cleanup:** Every 6 hours, permanently deletes removed content with no pending appeal after 7 days

### Frontend Integration

The frontend uses `useFeedTracking.ts` hooks for:

- **Viewport tracking:** `usePostViewTracking(postId)` — IntersectionObserver at 50% threshold
- **Dwell time:** Logged when post leaves viewport after >3s visible
- **Explicit interactions:** `useInteractionLogger()` — logs glow, save, etc.
- **Batching:** Interactions queued and flushed every 5s or at 30 items
- **Session ID:** Generated per page load, sent with all feed requests

### Evaluation Metrics

| Metric                | Description                          | Target     |
| --------------------- | ------------------------------------ | ---------- |
| Feed CTR              | Impressions → Engagements            | >5%        |
| Avg Dwell Time        | Mean time per post view              | >4s        |
| Diversity Score       | Unique authors per 20 posts          | >12        |
| Cold Start Engagement | New user engagement in first session | >3 actions |
| Fallback Rate         | % feeds using chronological fallback | <1%        |
| Feed Latency          | Time to generate ranked feed         | <200ms     |

### Scalability Considerations

- Candidate generation uses indexed queries with limits
- Affinity scores precomputed and cached per viewer
- Quality scores batch-recomputed in background
- Impression logging is best-effort (non-blocking)
- Interaction tracking uses client-side batching (5s intervals)
- Graceful degradation: ranking errors → chronological fallback

### Database Migrations Required

```sql
-- Run these migrations on the external PostgreSQL database

CREATE TABLE user_interaction_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    post_id UUID NOT NULL REFERENCES user_feeds(id) ON DELETE CASCADE,
    interaction_type TEXT NOT NULL,
    dwell_time_ms INTEGER,
    session_id TEXT,
    device_type TEXT,
    created_at TIMESTAMP DEFAULT now()
);
CREATE INDEX idx_interaction_user_post ON user_interaction_logs(user_id, post_id);
CREATE INDEX idx_interaction_user_type ON user_interaction_logs(user_id, interaction_type);
CREATE INDEX idx_interaction_created ON user_interaction_logs(created_at);

CREATE TABLE user_interest_profiles (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    interest_vector JSONB DEFAULT '{}'::jsonb,
    engagement_stats JSONB DEFAULT '{}'::jsonb,
    negative_signals JSONB DEFAULT '{}'::jsonb,
    last_computed_at TIMESTAMP DEFAULT now(),
    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now()
);

CREATE TABLE author_affinity_scores (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    viewer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    interaction_count INTEGER DEFAULT 0,
    weighted_score FLOAT DEFAULT 0.0,
    is_following BOOLEAN DEFAULT false,
    shared_events_count INTEGER DEFAULT 0,
    is_circle_member BOOLEAN DEFAULT false,
    last_interaction_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now()
);
CREATE UNIQUE INDEX idx_affinity_viewer_author ON author_affinity_scores(viewer_id, author_id);
CREATE INDEX idx_affinity_viewer ON author_affinity_scores(viewer_id);

CREATE TABLE post_quality_scores (
    post_id UUID PRIMARY KEY REFERENCES user_feeds(id) ON DELETE CASCADE,
    engagement_velocity FLOAT DEFAULT 0.0,
    content_richness FLOAT DEFAULT 0.0,
    author_credibility FLOAT DEFAULT 0.5,
    moderation_flag BOOLEAN DEFAULT false,
    spam_probability FLOAT DEFAULT 0.0,
    category TEXT DEFAULT 'general',
    final_quality_score FLOAT DEFAULT 0.5,
    total_engagements INTEGER DEFAULT 0,
    engagement_rate FLOAT DEFAULT 0.0,
    impression_count INTEGER DEFAULT 0,
    last_computed_at TIMESTAMP DEFAULT now(),
    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now()
);

CREATE TABLE feed_impressions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    post_id UUID NOT NULL REFERENCES user_feeds(id) ON DELETE CASCADE,
    position INTEGER,
    session_id TEXT,
    was_engaged BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT now()
);
CREATE INDEX idx_impression_user_session ON feed_impressions(user_id, session_id);
CREATE INDEX idx_impression_post ON feed_impressions(post_id);
CREATE INDEX idx_impression_created ON feed_impressions(created_at);
```

---

### Smart Service Discovery & Ranking (2026-02-19)

**Frontend Changes:**

- `FindServices.tsx` completely redesigned with infinite scroll (IntersectionObserver, 20 items per page)
- Removed AI chatbot icon (Sparkles) from the page
- Added **price range filter** with dual-handle slider (min/max TZS)
- Added **location-based ranking** toggle button - uses browser Geolocation API to send `lat`/`lng` to backend
- All filters (category pills, location dropdown, sort select) are fully dynamic and functional
- Categories loaded from `useServiceCategories` hook (API-driven)
- Locations populated dynamically from search response `filters.locations`
- Price range bounds populated from search response `filters.price_range`
- End-of-results indicator shown when all services loaded

**Backend Changes (`services.py` - `GET /services`):**

- New query parameters: `lat`, `lng`, `radius_km` for geo-proximity ranking
- Smart multi-factor relevance algorithm when `sort_by=relevance`:
  - **W1: Rating Quality (0-25 pts)** — normalized average rating
  - **W2: Social Proof (0-20 pts)** — log-scale review count
  - **W3: Event Type Match (0-20 pts)** — boosts services whose type matches event types from user's own events, invitations, or committee memberships
  - **W4: Location Proximity (0-15 pts)** — tiered distance scoring (10km=15, 25km=12, 50km=8, 100km=4)
  - **W5: Verification Trust (0-10 pts)** — verified providers boosted
  - **W6: Profile Completeness (0-10 pts)** — description length, images, pricing, packages
- Authentication is optional — if Bearer token provided, personalization kicks in
- Response now includes `filters` object with dynamic `locations` array and `price_range` object
- Response includes `short_description` field (first 100 chars of description)
- Pagination includes `has_next`/`has_previous` for infinite scroll support

**No database schema changes required** — ranking uses existing tables (events, event_invitations, event_committees, event_type_services, user_services).

---

### WhatsApp Template Integration & UI Updates (2026-02-19)

**WhatsApp Templates (whatsapp-send edge function):**
All outbound WhatsApp messages now use **approved Meta templates** instead of plain text, ensuring production readiness without sandbox restrictions.

| Template Name      | Action Key         | Parameters ({{1}}-{{N}})                                     |
| ------------------ | ------------------ | ------------------------------------------------------------ |
| `event_invitation` | `invite`           | guest_name, event_name, event_date, organizer_name, rsvp_url |
| `event_update`     | `event_update`     | guest_name, event_name, changes                              |
| `event_reminder`   | `reminder`         | guest_name, event_name, event_date, event_time, location     |
| `expense_recorded` | `expense_recorded` | recipient_name, recorder_name, amount, category, event_name  |

- The `text` action remains as a fallback for ad-hoc messages (still sends plain text).
- All templates use language code `en` and utility category.
- Backend helper `wa_expense_recorded()` added to `backend/app/utils/whatsapp.py`.

**Service Verification Badge:**

- Removed the "Verified" text overlay badge from service cards in `FindServices.tsx`.
- Verification is now shown as a ✓ icon inline before the service name (CheckCircle icon in primary color).

**Expense Report Ordering:**

- Backend `GET /user-events/{event_id}/expenses/report` now orders expenses by `expense_date ASC` (chronological) instead of category-first.
- Frontend `generateExpenseReportHtml` sorts expenses by date ascending for consistent report output.

---

### Event Ticketing System (2026-02-21)

**Overview:** Events can now sell tickets with multiple ticket classes (tiers). Organizers create ticket classes with names, prices, and quantities. Users discover ticketed events in the right sidebar and purchase tickets directly on the platform.

#### Endpoints

**Public — Get Ticketed Events**

```
GET /ticketing/events?page=1&limit=10
```

Returns all public events that sell tickets, with `min_price`, `total_available`, and `ticket_class_count`.

**Public — Get Ticket Classes for an Event**

```
GET /ticketing/events/{event_id}/ticket-classes
```

Returns all ticket classes for a public ticketed event with `id`, `name`, `description`, `price`, `quantity`, `sold`, `available`, `is_sold_out`, `status`, `display_order`.

**Organizer — Create Ticket Class** _(Auth required)_

```
POST /ticketing/events/{event_id}/ticket-classes
Body: { "name": "VIP", "description": "Front row", "price": 50000, "quantity": 100 }
```

**Organizer — Update Ticket Class** _(Auth required)_

```
PUT /ticketing/ticket-classes/{class_id}
Body: { "name": "...", "price": ..., "quantity": ..., "status": "..." }
```

**Organizer — Delete Ticket Class** _(Auth required, only if no tickets sold)_

```
DELETE /ticketing/ticket-classes/{class_id}
```

**User — Purchase Ticket** _(Auth required)_

```
POST /ticketing/purchase
Body: { "ticket_class_id": "uuid", "quantity": 1 }
Response: { "ticket_id": "...", "ticket_code": "NTK-XXXXXXXX", "quantity": 1, "total_amount": 50000 }
```

**User — Get My Tickets** _(Auth required)_

```
GET /ticketing/my-tickets?page=1&limit=20
```

**Organizer — Get Event Tickets** _(Auth required)_

```
GET /ticketing/events/{event_id}/tickets?page=1&limit=50
```

#### Frontend Integration

- `EventTicketing` component in Create/Edit Event for organizers to manage ticket classes
- `EventTicketPurchase` component on Event View page showing all available classes with purchase flow
- `TicketEventsSection` in Right Sidebar showing public ticketed events with "From [price]" badges
- Sold-out classes are visually disabled with "Sold Out" badge

---

### Business Phone Number for Services (2026-02-21)

**Overview:** Service providers can add verified business phone numbers and reuse them across multiple services without re-verification.

#### Endpoints

**List Business Phones** _(Auth required)_

```
GET /user-services/business-phones/list
```

**Add Business Phone** _(Auth required)_

```
POST /user-services/business-phones
Body: { "phone_number": "0653750805" }
```

**Verify Business Phone** _(Auth required)_

```
POST /user-services/business-phones/{phone_id}/verify
Body: { "otp": "123456" }
```

#### Frontend Integration

- Business phone selector in Add Service and Edit Service forms
- Inline OTP verification flow matching registration-style inputs
- Verified phones can be reused across multiple services

---

### Share Events to Feed (2026-02-21) — Updated

**Overview:** Event creators can share their events to the feed with visibility (Public/Circle) and duration controls (specific date or lifetime). Shared events render as rich event preview cards in the feed, distinct from regular posts/moments.

#### Backend Changes

- `POST /posts/` now accepts additional form fields:
  - `post_type`: `"post"` (default) or `"event_share"`
  - `event_id`: UUID of the event to share (required when `post_type=event_share`)
  - `expires_at`: ISO 8601 timestamp for timed shares (optional)
- `_post_dict()` now includes `post_type` field in all post responses
- When `post_type == "event_share"`, the response includes a `shared_event` object:
  ```json
  {
    "post_type": "event_share",
    "shared_event": {
      "id": "uuid",
      "title": "Wedding Celebration",
      "description": "Join us for...",
      "start_date": "2026-03-15T00:00:00",
      "end_date": null,
      "start_time": "14:00",
      "location": "Dar es Salaam",
      "cover_image": "https://...",
      "images": ["https://..."],
      "event_type": "Wedding",
      "sells_tickets": false,
      "is_public": true,
      "expected_guests": 200,
      "dress_code": "Smart Casual"
    },
    "share_expires_at": "2026-03-10T23:59:00"
  }
  ```

#### Frontend Integration

- `ShareEventToFeed` component accessible from Event Management header
- Visibility options: Public (all users) or Circle (only circle members)
- Duration options: Until specific date/time or Lifetime (manual removal)
- **Rich Event Card**: `Moment.tsx` detects `post_type === "event_share"` and renders a distinct event card with:
  - Image mosaic (1, 2, or 3+ images with "+N" overlay)
  - Event type and ticket badges
  - Date, time, location, guest count, dress code info
  - "View Event Details" CTA button
- Regular posts continue to render with standard media/text layout

#### Database

- `user_feeds.post_type` — TEXT, default `'post'`
- `user_feeds.shared_event_id` — UUID FK → `events(id)`
- `user_feeds.share_duration` — `event_share_duration_enum` (`'timed'`, `'lifetime'`)
- `user_feeds.share_expires_at` — TIMESTAMP

---

### Video Support for Moments (2026-02-21)

**Overview:** Users can upload videos in addition to images when creating moments. Videos render inline using the `VideoPlayer` component across Feed, My Moments, and Moment Detail views.

---

### OTP Input Standardization (2026-02-21)

All OTP inputs across the platform now use consistent styling: `w-12 h-14 text-xl font-semibold rounded-xl border-2` with `gap-2` spacing. Applied to:

- Registration (phone verification)
- Phone verification page
- Email verification page
- Email OTP in Profile
- Business phone verification in Add/Edit Service

---

### Website Analytics & Page Views Tracking (2026-02-21)

**Overview:** The platform now tracks page views for analytics purposes. A `page_views` table stores visitor data including path, referrer, device type, browser, and location. The admin dashboard at `/admin/analytics` displays traffic metrics, top pages, device/browser breakdowns, and daily trends.

**Table: `page_views`**
| Column | Type | Description |
|---|---|---|
| `id` | UUID | Primary key |
| `path` | TEXT | Page path visited |
| `referrer` | TEXT | Referring URL |
| `user_agent` | TEXT | Browser user agent string |
| `country` | TEXT | Visitor country |
| `city` | TEXT | Visitor city |
| `device_type` | TEXT | mobile / tablet / desktop |
| `browser` | TEXT | Browser name |
| `session_id` | TEXT | Session identifier |
| `visitor_id` | TEXT | Persistent visitor identifier |
| `created_at` | TIMESTAMPTZ | Timestamp of visit |

**Frontend Hook:** `usePageTracking()` — automatically logs page views on route changes, deduplicating within the same session.

**Admin Dashboard:** `/admin/analytics` — displays total views, unique visitors, sessions, top pages, device/browser distribution, daily trend chart, and recent activity log. Data is filterable by time range (24h, 7d, 30d, 90d).

---

### Printable Tickets (2026-02-21)

**Overview:** Confirmed ticket orders can now be printed as modern-styled tickets. The `PrintableTicket` component renders event details, QR code, buyer info, and ticket metadata in a print-optimized layout.

---

### Invitation Card Redesign (2026-02-21)

**Overview:** The invitation card has been redesigned with event-type-specific themes. Each event type (wedding, birthday, corporate, memorial, anniversary, conference, graduation) has a unique color scheme, typography, ornamental decorations, and invitation label. Cards include QR code generation and print/share functionality.

**Supported event type themes:**

- Wedding — Rose/pink palette with elegant serif typography
- Birthday — Amber/orange with playful rounded styling
- Corporate — Slate/blue with professional sans-serif
- Memorial — Gray/muted with respectful understated design
- Anniversary — Purple/violet with refined decorative elements
- Conference — Teal/cyan with modern clean lines
- Graduation — Indigo/blue with academic styling

---

### Events Done Count Fix (2026-02-21)

**Overview:** The "events done" count on public service detail pages now correctly queries only `completed` status from the `event_service_status` enum. Previously used invalid values `confirmed` and `accepted` which caused database errors.

---

### Event Service Status Management (2026-02-21)

**Overview:** Event organizers can now update the status of assigned service providers directly from the event management dashboard. A status dropdown allows setting service status to any valid value: `pending`, `assigned`, `in_progress`, `completed`, `cancelled`.

**Backend endpoint:** `PUT /user-events/{event_id}/services/{service_id}`

- Accepts `status` or `service_status` field in request body
- Validates against the `event_service_status` enum
- Requires `can_manage_vendors` permission or event creator role

**Valid `event_service_status` enum values:**

- `pending` — Service not yet confirmed
- `assigned` — Service provider assigned to event
- `in_progress` — Service currently being delivered
- `completed` — Service fully delivered ✅ (counts toward "events done")
- `cancelled` — Service cancelled

---

### WhatsApp Admin Chat Module (2026-02-21)

**Overview:** Full WhatsApp Web-style chat interface in the admin panel for real-time messaging with contacts via WhatsApp Business Cloud API.

**Database Tables:**

**`wa_conversations`** — Groups messages by phone number
| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| phone | VARCHAR(20) | Unique phone number |
| contact_name | VARCHAR(255) | Contact display name |
| last_message | TEXT | Preview of last message |
| last_activity_at | TIMESTAMPTZ | Timestamp of last activity |
| unread_count | INTEGER | Number of unread messages |
| is_active | BOOLEAN | Whether conversation is active |
| created_at | TIMESTAMPTZ | Created timestamp |
| updated_at | TIMESTAMPTZ | Updated timestamp |

**`wa_messages`** — Individual messages within conversations
| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| conversation_id | UUID | FK to wa_conversations |
| wa_message_id | VARCHAR(255) | WhatsApp message ID (for status tracking) |
| direction | ENUM(inbound, outbound) | Message direction |
| content | TEXT | Message text content |
| status | ENUM(sent, delivered, read, failed) | Delivery status |
| created_at | TIMESTAMPTZ | Created timestamp |

**Admin Endpoints:**

`GET /admin/whatsapp/conversations` — List all conversations sorted by last activity

- Response: `{ success, data: [{ id, phone, contact_name, last_message, last_activity_at, unread_count }] }`

`GET /admin/whatsapp/conversations/{id}/messages?page=1&limit=50` — Paginated message history

- Response: `{ success, data: { items: [{ id, direction, content, status, created_at }], total, page, pages } }`

`POST /admin/whatsapp/conversations/{id}/send` — Send message to conversation

- Body: `{ message: "Hello" }`
- Response: `{ success, data: { id, direction, content, status, created_at } }`

`PUT /admin/whatsapp/conversations/{id}/read` — Mark conversation as read (resets unread_count)

**Internal Webhook Endpoints (called by whatsapp-webhook edge function):**

`POST /whatsapp/incoming` — Store incoming message & update conversation

- Body: `{ phone, name, content, wa_message_id }`

`POST /whatsapp/status-update` — Update message delivery status

- Body: `{ wa_message_id, status }`

**Status Indicators:** ✓ Sent → ✓✓ Delivered → ✓✓ Read (blue)

---

## 📋 Issue Reporting System

### Database Tables

**`issue_categories`** — Predefined categories for issue classification
| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| name | TEXT | Unique category name |
| description | TEXT | Category description |
| icon | TEXT | Lucide icon name |
| display_order | INTEGER | Sort order |
| is_active | BOOLEAN | Whether category is active |
| created_at | TIMESTAMPTZ | Created timestamp |
| updated_at | TIMESTAMPTZ | Updated timestamp |

**`issues`** — User-submitted issues
| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| user_id | UUID | FK to users |
| category_id | UUID | FK to issue_categories |
| subject | TEXT | Issue subject line |
| description | TEXT | Detailed description |
| status | ENUM(open, in_progress, resolved, closed) | Current status |
| priority | ENUM(low, medium, high, critical) | Priority level |
| screenshot_urls | JSONB | Array of screenshot URLs |
| created_at | TIMESTAMPTZ | Created timestamp |
| updated_at | TIMESTAMPTZ | Updated timestamp |

**`issue_responses`** — Threaded responses on issues
| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| issue_id | UUID | FK to issues |
| responder_id | UUID | User or admin ID |
| is_admin | BOOLEAN | Whether response is from admin |
| admin_name | TEXT | Admin display name |
| message | TEXT | Response message |
| attachments | JSONB | Array of attachment URLs |
| created_at | TIMESTAMPTZ | Created timestamp |

### User Endpoints (Auth Required)

`GET /issues/categories` — List active issue categories

- Response: `{ success, data: [{ id, name, description, icon, display_order }] }`

`GET /issues/` — List user's submitted issues

- Query: `?page=1&limit=20&status=open`
- Response: `{ success, data: { issues: [...], summary: { total, open, in_progress, resolved } } }`

`GET /issues/{issue_id}` — Get issue detail with responses

- Response: `{ success, data: { id, subject, description, status, priority, category, screenshot_urls, responses: [...], created_at } }`

`POST /issues/` — Submit a new issue

- Body: `{ category_id, subject, description, priority?, screenshot_urls? }`
- Response: `{ success, data: { id, subject, status } }`

`POST /issues/{issue_id}/reply` — Reply to an issue

- Body: `{ message }`
- Response: `{ success, data: { id } }`

`PUT /issues/{issue_id}/close` — Close an issue

- Response: `{ success, message }`

### Admin Endpoints (Admin Auth Required)

`GET /admin/issues` — List all issues with filtering

- Query: `?page=1&limit=20&status=open&priority=high&search=keyword`
- Response: `{ success, data: { items: [...], total, page, pages, counts: { total, open, in_progress, resolved, closed } } }`

`GET /admin/issues/{issue_id}` — Get issue detail with user info and responses

- Response: `{ success, data: { id, subject, description, status, priority, category, user, responses, screenshot_urls, created_at } }`

`POST /admin/issues/{issue_id}/reply` — Admin reply to an issue

- Body: `{ message }`
- Response: `{ success, data: { id } }`

`PUT /admin/issues/{issue_id}/status` — Update issue status/priority

- Body: `{ status?, priority? }`
- Response: `{ success, message }`

`GET /admin/issue-categories` — List all categories (including inactive)

- Response: `{ success, data: [...] }`

`POST /admin/issue-categories` — Create a new category

- Body: `{ name, description?, icon?, display_order? }`

`PUT /admin/issue-categories/{id}` — Update a category

- Body: `{ name?, description?, icon?, display_order?, is_active? }`

`DELETE /admin/issue-categories/{id}` — Delete a category (fails if issues exist)

---

### Ticketed Event Approval System (2026-02-25)

**Overview:** All events with `sells_tickets = true` must go through admin approval before tickets appear in public browsing. This prevents fraudulent or non-existent events from selling tickets. Organizers see real-time status updates, and admins manage approvals from a dedicated dashboard.

#### Database Changes

**New Enum:**

```sql
CREATE TYPE ticket_approval_status_enum AS ENUM ('pending', 'approved', 'rejected', 'removed');
```

**New Columns on `events` table:**

```sql
ALTER TABLE events ADD COLUMN ticket_approval_status ticket_approval_status_enum DEFAULT 'pending';
ALTER TABLE events ADD COLUMN ticket_rejection_reason TEXT;
ALTER TABLE events ADD COLUMN ticket_removed_reason TEXT;
ALTER TABLE events ADD COLUMN ticket_approved_by UUID;
ALTER TABLE events ADD COLUMN ticket_approved_at TIMESTAMP;
ALTER TABLE events ADD COLUMN ticket_removed_at TIMESTAMP;
```

#### Status Flow

- **pending** - Default when organizer enables `sells_tickets`. Event is not visible in public ticket browsing.
- **approved** - Admin approves. Event becomes visible in `/tickets` browse page and right sidebar.
- **rejected** - Admin rejects with a reason. Organizer sees the reason and can edit and resubmit.
- **removed** - Admin removes from marketplace (soft delete). Event still exists but shows "Removed" label. Not permanently deleted.

#### Admin Endpoints (Admin Auth Required)

`GET /admin/ticketed-events` - List all ticketed events with approval status

- Query: `?page=1&limit=20&status=pending|approved|rejected|removed&search=keyword`
- Response: `{ success, data: { items: [...], total, page, pages } }`

`PUT /admin/ticketed-events/{event_id}/approve` - Approve a ticketed event

- Response: `{ success, message: "Event approved for ticket sales" }`
- Side effect: Sends in-app notification to organizer (`ticket_event_approved`)

`PUT /admin/ticketed-events/{event_id}/reject` - Reject a ticketed event

- Body: `{ "reason": "Event details are incomplete or unverifiable" }`
- Response: `{ success, message: "Event rejected" }`
- Side effect: Sends in-app notification to organizer (`ticket_event_rejected`) with the reason

`PUT /admin/ticketed-events/{event_id}/remove` - Remove a ticketed event from marketplace

- Body: `{ "reason": "Reported as fraudulent" }`
- Response: `{ success, message: "Event removed from ticket marketplace" }`
- Side effect: Sends in-app notification to organizer (`ticket_event_removed`) with the reason

`DELETE /admin/ticketed-events/{event_id}` - Permanently delete a ticketed event (hard delete)

- Response: `{ success, message: "Event permanently deleted" }`

#### Public Endpoint Changes

`GET /ticketing/events` - Now only returns events where `ticket_approval_status = 'approved'`

Right sidebar ticketed events section also filters to `approved` only, with preference-based randomization and fallback for new users.

#### Organizer Experience

- When `sells_tickets` is enabled, `ticket_approval_status` defaults to `pending`
- Organizer sees colored status banners in their ticket management:
  - **Pending** (yellow): "Your event is under review for ticket approval"
  - **Approved** (green): "Your event is approved for ticket sales"
  - **Rejected** (red): "Your event was not approved" with the rejection reason displayed
  - **Removed** (gray): "This event has been removed from the ticket marketplace" with the removal reason
- Organizers receive in-app notifications on every status change

#### Notification Types Added

- `ticket_event_approved`
- `ticket_event_rejected`
- `ticket_event_removed`

---
