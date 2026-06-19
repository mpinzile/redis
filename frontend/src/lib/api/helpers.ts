/**
 * API Helpers - Shared utilities for making API requests
 */

import type { ApiResponse } from "./types";

const LOCAL_API_HOSTS = new Set(["127.0.0.1", "localhost", "0.0.0.0"]);

export function resolveApiBaseUrl(): string {
  const raw = (import.meta.env.VITE_API_BASE_URL as string | undefined)?.trim();
  if (!raw) return "/api/v1";

  const normalizedRaw = raw.replace(/\/$/, "") || "/api/v1";
  if (typeof window === "undefined") return normalizedRaw;

  try {
    const resolved = new URL(normalizedRaw, window.location.origin);
    const currentIsLocal = LOCAL_API_HOSTS.has(window.location.hostname);
    const targetIsLocal = LOCAL_API_HOSTS.has(resolved.hostname);

    if ((resolved.protocol === "http:" || resolved.protocol === "https:") && targetIsLocal && !currentIsLocal) {
      return "/api/v1";
    }

    return /^https?:\/\//i.test(normalizedRaw)
      ? resolved.toString().replace(/\/$/, "")
      : normalizedRaw;
  } catch {
    return normalizedRaw;
  }
}

const BASE_URL = resolveApiBaseUrl();

/**
 * Security headers added to every request
 */
const getSecurityHeaders = (): Record<string, string> => ({
  "X-Client-Id": "nuru-web-v1",
  "X-Request-Time": Date.now().toString(),
  "X-Platform": "web",
});

/**
 * Get authorization headers with token if available
 */
export const getAuthHeaders = (): HeadersInit => {
  const token = localStorage.getItem("access_token") || localStorage.getItem("token");
  return {
    "Content-Type": "application/json",
    ...getSecurityHeaders(),
    ...(token ? { Authorization: `Bearer ${token}` } : {}),
  };
};

/**
 * Generic fetch wrapper with error handling
 */
export async function request<T>(
  endpoint: string,
  options: RequestInit = {}
): Promise<ApiResponse<T>> {
  const url = `${BASE_URL}${endpoint}`;
  
  const config: RequestInit = {
    ...options,
    headers: {
      ...getAuthHeaders(),
      ...options.headers,
    },
    credentials: "include",
  };

  try {
    const response = await fetch(url, config);

    // Handle 429 globally - rate limited
    if (response.status === 429) {
      const retryHeader = response.headers.get("Retry-After");
      const retryAfter = retryHeader ? parseInt(retryHeader, 10) : 60;
      const isAuth = endpoint.startsWith("/auth/") || endpoint.startsWith("/users/signup") || endpoint.startsWith("/users/verify-otp") || endpoint.startsWith("/users/request-otp");
      window.dispatchEvent(new CustomEvent("api:rate-limited", {
        detail: { retryAfter: isNaN(retryAfter) ? 60 : retryAfter, context: isAuth ? "auth" : "general" },
      }));
    }

    // Handle 401 globally - token expired or invalid
    // Skip redirect on public pages (shared posts, photo libraries, RSVP, etc.)
    if (response.status === 401) {
      const currentToken = localStorage.getItem("access_token") || localStorage.getItem("token");
      const publicPaths = ["/shared/", "/s/", "/c/", "/rsvp/", "/ticket/", "/i/", "/u/", "/event/", "/post/", "/moment/", "/services/view/", "/meet/", "/m/", "/contact", "/faqs", "/download", "/register", "/login", "/verify-", "/reset-password", "/set-password/", "/privacy-policy", "/terms", "/vendor-agreement", "/organiser-agreement", "/cancellation-policy", "/cookie-policy", "/features/"];
      const isPublicPage = publicPaths.some(p => window.location.pathname.startsWith(p));
      if (currentToken) {
        localStorage.removeItem("access_token");
        localStorage.removeItem("token");
        localStorage.removeItem("refresh_token");
        // Only redirect on protected pages, not public ones
        if (!isPublicPage) {
          const event = new CustomEvent("auth:session-expired");
          window.dispatchEvent(event);
        }
      }
    }

    // Our backend is not fully consistent:
    // - Most endpoints return { success, message, data }
    // - Some endpoints return just the raw object (e.g. /auth/me)
    // - Some endpoints return { success, message } without data (e.g. /auth/logout)
    // Normalize everything into the ApiResponse<T> shape so the rest of the app stays stable.
    const json = await response.json().catch(() => null);

    if (json && typeof json === "object" && "success" in json) {
      // Ensure data key exists to avoid undefined access downstream
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const normalized = ("data" in (json as any) ? json : { ...(json as any), data: null }) as ApiResponse<T>;
      return normalized;
    }

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const message = (json as any)?.message || (response.ok ? "" : "Something went wrong. Please try again.");

    return {
      success: response.ok,
      message,
      data: json as T,
    };
  } catch (error) {
    // Network error or other fetch failure
    const message = error instanceof TypeError && error.message === "Failed to fetch"
      ? "Unable to connect. Please check your internet connection and try again."
      : error instanceof Error
        ? `Request failed: ${error.message}`
        : "Something went wrong. Please try again.";
    return {
      success: false,
      message,
      data: null as T,
    };
  }
}

/**
 * GET request
 */
export async function get<T>(endpoint: string): Promise<ApiResponse<T>> {
  return request<T>(endpoint, { method: "GET" });
}

/**
 * POST request
 */
export async function post<T>(endpoint: string, body?: unknown): Promise<ApiResponse<T>> {
  return request<T>(endpoint, {
    method: "POST",
    body: body ? JSON.stringify(body) : undefined,
  });
}

/**
 * PUT request
 */
export async function put<T>(endpoint: string, body?: unknown): Promise<ApiResponse<T>> {
  return request<T>(endpoint, {
    method: "PUT",
    body: body ? JSON.stringify(body) : undefined,
  });
}

/**
 * PATCH request
 */
export async function patch<T>(endpoint: string, body?: unknown): Promise<ApiResponse<T>> {
  return request<T>(endpoint, {
    method: "PATCH",
    body: body ? JSON.stringify(body) : undefined,
  });
}

/**
 * DELETE request
 */
export async function del<T>(endpoint: string, body?: unknown): Promise<ApiResponse<T>> {
  return request<T>(endpoint, { 
    method: "DELETE",
    body: body ? JSON.stringify(body) : undefined,
  });
}

/**
 * POST with FormData (for file uploads)
 */
export async function postFormData<T>(endpoint: string, formData: FormData): Promise<ApiResponse<T>> {
  const token = localStorage.getItem("access_token") || localStorage.getItem("token");
  const url = `${BASE_URL}${endpoint}`;
  
  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        ...getSecurityHeaders(),
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      credentials: "include",
      body: formData,
    });

    if (response.status === 429) {
      const retryHeader = response.headers.get("Retry-After");
      const retryAfter = retryHeader ? parseInt(retryHeader, 10) : 60;
      window.dispatchEvent(new CustomEvent("api:rate-limited", {
        detail: { retryAfter: isNaN(retryAfter) ? 60 : retryAfter, context: "general" },
      }));
    }

    const json = await response.json().catch(() => null);
    
    if (json && typeof json === "object" && "success" in json) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const normalized = ("data" in (json as any) ? json : { ...(json as any), data: null }) as ApiResponse<T>;
      return normalized;
    }
    
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const message = (json as any)?.message || (response.ok ? "" : "Something went wrong. Please try again.");
    
    return {
      success: response.ok,
      message,
      data: json as T,
    };
  } catch (error) {
    const message = error instanceof TypeError && error.message === "Failed to fetch"
      ? "Unable to connect. Please check your internet connection and try again."
      : error instanceof Error
        ? `Upload failed: ${error.message}`
        : "Something went wrong. Please try again.";
    return {
      success: false,
      message,
      data: null as T,
    };
  }
}

/**
 * PUT with FormData (for file uploads)
 */
export async function putFormData<T>(endpoint: string, formData: FormData): Promise<ApiResponse<T>> {
  const token = localStorage.getItem("access_token") || localStorage.getItem("token");
  const url = `${BASE_URL}${endpoint}`;
  
  try {
    const response = await fetch(url, {
      method: "PUT",
      headers: {
        ...getSecurityHeaders(),
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      credentials: "include",
      body: formData,
    });

    if (response.status === 429) {
      const retryHeader = response.headers.get("Retry-After");
      const retryAfter = retryHeader ? parseInt(retryHeader, 10) : 60;
      window.dispatchEvent(new CustomEvent("api:rate-limited", {
        detail: { retryAfter: isNaN(retryAfter) ? 60 : retryAfter, context: "general" },
      }));
    }

    const json = await response.json().catch(() => null);
    
    if (json && typeof json === "object" && "success" in json) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const normalized = ("data" in (json as any) ? json : { ...(json as any), data: null }) as ApiResponse<T>;
      return normalized;
    }
    
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const message = (json as any)?.message || (response.ok ? "" : "Something went wrong. Please try again.");
    
    return {
      success: response.ok,
      message,
      data: json as T,
    };
  } catch (error) {
    const message = error instanceof TypeError && error.message === "Failed to fetch"
      ? "Unable to connect. Please check your internet connection and try again."
      : error instanceof Error
        ? `Upload failed: ${error.message}`
        : "Something went wrong. Please try again.";
    return {
      success: false,
      message,
      data: null as T,
    };
  }
}

/**
 * Build query string from params object
 * Accepts any object to avoid strict type checking issues with optional properties
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function buildQueryString(params?: any): string {
  if (!params) return "";
  
  const searchParams = new URLSearchParams();
  
  Object.entries(params).forEach(([key, value]) => {
    if (value !== undefined && value !== null) {
      searchParams.append(key, String(value));
    }
  });
  
  const queryString = searchParams.toString();
  return queryString ? `?${queryString}` : "";
}
