import 'dart:convert';
import 'package:http/http.dart' as http;
import 'secure_token_storage.dart';
import 'api_config.dart';

/// Social API service - mirrors src/lib/api/social.ts
class SocialService {
  static String get _baseUrl => ApiConfig.baseUrl;

  static Future<Map<String, String>> _headers() async {
    final token = await SecureTokenStorage.getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, String>> _authOnlyHeaders() async {
    final token = await SecureTokenStorage.getToken();
    return {
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// GET /posts/feed - ranked or chronological feed
  static Future<Map<String, dynamic>> getFeed({
    int page = 1,
    int limit = 15,
    String mode = 'ranked',
    String? sessionId,
  }) async {
    try {
      final params = <String, String>{
        'page': '$page',
        'limit': '$limit',
        'mode': mode,
      };
      if (sessionId != null) params['session_id'] = sessionId;
      final uri = Uri.parse(
        '$_baseUrl/posts/feed',
      ).replace(queryParameters: params);
      final res = await http.get(uri, headers: await _headers());
      return jsonDecode(res.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to fetch feed',
        'data': null,
      };
    }
  }

  /// GET /posts/explore - trending/explore feed (authenticated)
  static Future<Map<String, dynamic>> getExplore({int limit = 15}) async {
    try {
      final uri = Uri.parse('$_baseUrl/posts/explore?limit=$limit');
      final res = await http.get(uri, headers: await _headers());
      return jsonDecode(res.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to fetch explore',
        'data': null,
      };
    }
  }

  /// GET /posts/public/trending
  static Future<Map<String, dynamic>> getTrending({
    int limit = 15,
    String period = 'week',
  }) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/posts/public/trending?limit=$limit&period=$period',
      );
      final res = await http.get(uri, headers: await _headers());
      return jsonDecode(res.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to fetch trending',
        'data': null,
      };
    }
  }

  /// GET /moments/public/trending - trending glimpses for the rail.
  static Future<Map<String, dynamic>> getTrendingMoments({int limit = 12}) async {
    try {
      final uri = Uri.parse('$_baseUrl/moments/public/trending?limit=$limit');
      final res = await http.get(uri, headers: await _headers());
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Unable to fetch trending glimpses', 'data': null};
    }
  }

  /// POST /posts - create a new post with FormData (multipart).
  /// When [postType] is 'event_share', the [eventId] is attached so the feed
  /// renders the Rich Event Card (parity with web ShareEventToFeed).
  static Future<Map<String, dynamic>> createPost({
    required String content,
    String visibility = 'public',
    String? location,
    List<String>? imagePaths,
    String? postType,
    String? eventId,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/posts');
      final request = http.MultipartRequest('POST', uri);
      final headers = await _authOnlyHeaders();
      request.headers.addAll(headers);

      request.fields['content'] = content;
      request.fields['visibility'] = visibility;
      if (location != null) request.fields['location'] = location;
      if (postType != null) request.fields['post_type'] = postType;
      if (eventId != null) request.fields['event_id'] = eventId;

      if (imagePaths != null) {
        for (final path in imagePaths) {
          request.files.add(await http.MultipartFile.fromPath('images', path));
        }
      }

      final streamedRes = await request.send();
      final body = await streamedRes.stream.bytesToString();
      return jsonDecode(body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to create post',
        'data': null,
      };
    }
  }

  /// GET /posts/:id
  static Future<Map<String, dynamic>> getPost(String postId) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/posts/$postId'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to fetch post',
        'data': null,
      };
    }
  }

  /// DELETE /posts/:id
  static Future<Map<String, dynamic>> deletePost(String postId) async {
    try {
      final res = await http.delete(
        Uri.parse('$_baseUrl/posts/$postId'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to delete post',
        'data': null,
      };
    }
  }

  /// PATCH /posts/:id - update content/visibility
  static Future<Map<String, dynamic>> updatePost(
    String postId, {
    String? content,
    String? visibility,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (content != null) body['content'] = content;
      if (visibility != null) body['visibility'] = visibility;
      final res = await http.patch(
        Uri.parse('$_baseUrl/posts/$postId'),
        headers: await _headers(),
        body: jsonEncode(body),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Failed to update post'};
    }
  }

  // GLOW (Like) - ❤️

  /// POST /posts/:id/glow
  /// Optional [emoji] picks the reaction emoji (defaults to ❤️ server-side).
  static Future<Map<String, dynamic>> glowPost(String postId, {String? emoji}) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/posts/$postId/glow'),
        headers: await _headers(),
        body: emoji != null ? jsonEncode({'emoji': emoji}) : null,
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Failed to glow'};
    }
  }

  /// DELETE /posts/:id/glow
  static Future<Map<String, dynamic>> unglowPost(String postId) async {
    try {
      final res = await http.delete(
        Uri.parse('$_baseUrl/posts/$postId/glow'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Failed to unglow'};
    }
  }

  // SAVE / UNSAVE

  /// POST /posts/:id/save
  static Future<Map<String, dynamic>> savePost(String postId) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/posts/$postId/save'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Failed to save'};
    }
  }

  /// DELETE /posts/:id/save
  static Future<Map<String, dynamic>> unsavePost(String postId) async {
    try {
      final res = await http.delete(
        Uri.parse('$_baseUrl/posts/$postId/save'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Failed to unsave'};
    }
  }

  /// GET /posts/saved
  static Future<Map<String, dynamic>> getSavedPosts({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/posts/saved?page=$page&limit=$limit');
      final res = await http.get(uri, headers: await _headers());
      return jsonDecode(res.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to fetch saved posts',
        'data': null,
      };
    }
  }

  // COMMENTS (Echoes)

  /// GET /posts/:id/comments
  static Future<Map<String, dynamic>> getComments(
    String postId, {
    int page = 1,
    int limit = 20,
    String? parentId,
  }) async {
    try {
      final params = <String, String>{'page': '$page', 'limit': '$limit'};
      if (parentId != null) params['parent_id'] = parentId;
      final uri = Uri.parse(
        '$_baseUrl/posts/$postId/comments',
      ).replace(queryParameters: params);
      final res = await http.get(uri, headers: await _headers());
      return jsonDecode(res.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to fetch comments',
        'data': null,
      };
    }
  }

  /// POST /posts/:id/comments
  static Future<Map<String, dynamic>> addComment(
    String postId,
    String content, {
    String? parentId,
  }) async {
    try {
      final body = <String, dynamic>{'content': content};
      if (parentId != null) body['parent_id'] = parentId;
      final res = await http.post(
        Uri.parse('$_baseUrl/posts/$postId/comments'),
        headers: await _headers(),
        body: jsonEncode(body),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Failed to add comment'};
    }
  }

  /// POST /users/:id/follow
  static Future<Map<String, dynamic>> followUser(String userId) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/users/$userId/follow'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Failed to follow'};
    }
  }

  /// DELETE /users/:id/follow
  static Future<Map<String, dynamic>> unfollowUser(String userId) async {
    try {
      final res = await http.delete(
        Uri.parse('$_baseUrl/users/$userId/follow'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Failed to unfollow'};
    }
  }

  /// GET /users/search?suggested=true - follow suggestions
  static Future<Map<String, dynamic>> getFollowSuggestions({
    int limit = 5,
  }) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/users/search?suggested=true&limit=$limit',
      );
      final res = await http.get(uri, headers: await _headers());
      return jsonDecode(res.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to fetch suggestions',
        'data': null,
      };
    }
  }

  /// GET /notifications
  static Future<Map<String, dynamic>> getNotifications({
    int page = 1,
    int limit = 20,
    String filter = 'all',
    String? search,
  }) async {
    try {
      final qp = <String, String>{'page': '$page', 'limit': '$limit', 'filter': filter};
      if (search != null && search.isNotEmpty) qp['search'] = search;
      final uri = Uri.parse('$_baseUrl/notifications/').replace(queryParameters: qp);
      final res = await http.get(uri, headers: await _headers());
      return jsonDecode(res.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to fetch notifications',
        'data': null,
      };
    }
  }

  /// PUT /notifications/read-all
  static Future<Map<String, dynamic>> markAllNotificationsRead() async {
    try {
      final res = await http.put(
        Uri.parse('$_baseUrl/notifications/read-all'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Failed to mark notifications read'};
    }
  }

  /// PUT /notifications/:id/read
  static Future<Map<String, dynamic>> markNotificationRead(
    String notificationId,
  ) async {
    try {
      final res = await http.put(
        Uri.parse('$_baseUrl/notifications/$notificationId/read'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Failed to mark notification read'};
    }
  }

  // CONVERSATIONS (Messages)

  /// GET /messages/
  static Future<Map<String, dynamic>> getConversations({
    int page = 1,
    int limit = 20,
    String? search,
  }) async {
    try {
      final qp = <String, String>{'page': '$page', 'limit': '$limit'};
      if (search != null && search.isNotEmpty) qp['search'] = search;
      final uri = Uri.parse('$_baseUrl/messages/').replace(queryParameters: qp);
      final res = await http.get(uri, headers: await _headers());
      return jsonDecode(res.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to fetch conversations',
        'data': null,
      };
    }
  }

  /// GET /messages/:conversationId
  static Future<Map<String, dynamic>> getMessages(
    String conversationId, {
    int page = 1,
    int limit = 30,
  }) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/messages/$conversationId?page=$page&limit=$limit',
      );
      final res = await http.get(uri, headers: await _headers());
      return jsonDecode(res.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to fetch messages',
        'data': null,
      };
    }
  }

  /// POST /messages/:conversationId
  static Future<Map<String, dynamic>> sendMessage(
    String conversationId,
    String content,
  ) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/messages/$conversationId'),
        headers: await _headers(),
        body: jsonEncode({'content': content}),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Failed to send message'};
    }
  }

  /// POST /messages/start
  static Future<Map<String, dynamic>> startConversation(
    String recipientId, {
    String? message,
  }) async {
    try {
      final body = <String, dynamic>{'recipient_id': recipientId};
      if (message != null) body['message'] = message;
      final res = await http.post(
        Uri.parse('$_baseUrl/messages/start'),
        headers: await _headers(),
        body: jsonEncode(body),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Failed to start conversation'};
    }
  }

  /// GET /posts/user/:userId
  // static Future<Map<String, dynamic>> getUserPosts(String userId, {int page = 1, int limit = 20}) async {
  //   try {
  //     final uri = Uri.parse('$_baseUrl/posts/user/$userId?page=$page&limit=$limit');
  //     final res = await http.get(uri, headers: await _headers());
  //     return jsonDecode(res.body);
  //   } catch (e) {
  //     return {'success': false, 'message': 'Unable to fetch user posts', 'data': null};
  //   }
  // }

  /// GET /posts/me - current user's posts
  static Future<Map<String, dynamic>> getMyPosts({
    int page = 1,
    int limit = 30,
  }) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/posts/me',
      ).replace(queryParameters: {'page': '$page', 'limit': '$limit'});
      final res = await http.get(uri, headers: await _headers());
      return jsonDecode(res.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to fetch your posts',
        'data': null,
      };
    }
  }

  /// GET /posts/user/:userId - user's posts by ID (same as web getUserPosts)
  static Future<Map<String, dynamic>> getUserPosts(
    String userId, {
    int page = 1,
    int limit = 30,
  }) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/posts/user/$userId',
      ).replace(queryParameters: {'page': '$page', 'limit': '$limit'});
      final res = await http.get(uri, headers: await _headers());
      return jsonDecode(res.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to fetch user posts',
        'data': null,
      };
    }
  }

  static Future<Map<String, dynamic>> search(String query) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/search',
      ).replace(queryParameters: {'q': query});
      final res = await http.get(uri, headers: await _headers());
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Search failed', 'data': null};
    }
  }

  static Future<Map<String, dynamic>> getMyIssues() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/issues/me'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to fetch issues',
        'data': null,
      };
    }
  }

  static Future<Map<String, dynamic>> getIssueCategories() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/issues/categories'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to fetch categories',
        'data': null,
      };
    }
  }

  static Future<Map<String, dynamic>> createIssue({
    required String title,
    String? description,
    String? categoryId,
  }) async {
    try {
      final body = <String, dynamic>{'title': title};
      if (description != null && description.isNotEmpty)
        body['description'] = description;
      if (categoryId != null) body['category_id'] = categoryId;
      final res = await http.post(
        Uri.parse('$_baseUrl/issues'),
        headers: await _headers(),
        body: jsonEncode(body),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to create issue',
        'data': null,
      };
    }
  }

  static Future<Map<String, dynamic>> getCircles() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/circles'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to fetch circles',
        'data': null,
      };
    }
  }

  static Future<Map<String, dynamic>> getCircleRequests() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/circles/requests'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to fetch requests',
        'data': null,
      };
    }
  }

  static Future<Map<String, dynamic>> getCircleInvitations() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/circles/invitations'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to fetch invitations',
        'data': null,
      };
    }
  }

  static Future<Map<String, dynamic>> cancelCircleInvitation(
    String invitationId,
  ) async {
    try {
      final res = await http.delete(
        Uri.parse('$_baseUrl/circles/invitations/$invitationId'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Unable to cancel invitation'};
    }
  }

  static Future<Map<String, dynamic>> createCircle(
    Map<String, dynamic> data,
  ) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/circles'),
        headers: await _headers(),
        body: jsonEncode(data),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Unable to create circle'};
    }
  }

  static Future<Map<String, dynamic>> addCircleMember(
    String circleId,
    String userId,
  ) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/circles/$circleId/members/$userId'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Unable to add member'};
    }
  }

  static Future<Map<String, dynamic>> removeCircleMember(
    String circleId,
    String userId,
  ) async {
    try {
      final res = await http.delete(
        Uri.parse('$_baseUrl/circles/$circleId/members/$userId'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Unable to remove member'};
    }
  }

  static Future<Map<String, dynamic>> acceptCircleRequest(
    String requestId,
  ) async {
    try {
      final res = await http.put(
        Uri.parse('$_baseUrl/circles/requests/$requestId/accept'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Unable to accept request'};
    }
  }

  static Future<Map<String, dynamic>> rejectCircleRequest(
    String requestId,
  ) async {
    try {
      final res = await http.put(
        Uri.parse('$_baseUrl/circles/requests/$requestId/reject'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Unable to reject request'};
    }
  }

  static Future<Map<String, dynamic>> getCommunities({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/communities?page=$page&limit=$limit');
      final res = await http.get(uri, headers: await _headers());
      return jsonDecode(res.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to fetch communities',
        'data': null,
      };
    }
  }

  static Future<Map<String, dynamic>> getMyCommunities() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/communities/my'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to fetch communities',
        'data': null,
      };
    }
  }

  static Future<Map<String, dynamic>> getRecommendedCommunities({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final uri = Uri.parse(
          '$_baseUrl/communities/recommended?page=$page&limit=$limit');
      final res = await http.get(uri, headers: await _headers());
      return jsonDecode(res.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to fetch recommended communities',
        'data': null,
      };
    }
  }

  static Future<Map<String, dynamic>> getCommunityDetail(
    String communityId,
  ) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/communities/$communityId'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to fetch community',
        'data': null,
      };
    }
  }

  static Future<Map<String, dynamic>> joinCommunity(String communityId) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/communities/$communityId/join'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Unable to join community'};
    }
  }

  static Future<Map<String, dynamic>> leaveCommunity(String communityId) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/communities/$communityId/leave'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Unable to leave community'};
    }
  }

  static Future<Map<String, dynamic>> createCommunity({
    required String name,
    String description = '',
    String? tagline,
    String? category,
    bool isPublic = true,
    String? coverImagePath,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/communities/');
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(await _authOnlyHeaders());
      request.fields['name'] = name;
      if (description.isNotEmpty) request.fields['description'] = description;
      if (tagline != null && tagline.trim().isNotEmpty) request.fields['tagline'] = tagline.trim();
      if (category != null && category.trim().isNotEmpty) request.fields['category'] = category.trim();
      request.fields['is_public'] = isPublic ? 'true' : 'false';
      if (coverImagePath != null && coverImagePath.isNotEmpty) {
        request.files.add(await http.MultipartFile.fromPath('cover_image', coverImagePath));
      }
      final streamed = await request.send();
      final body = await streamed.stream.bytesToString();
      return jsonDecode(body);
    } catch (e) {
      return {'success': false, 'message': 'Unable to create community'};
    }
  }

  static Future<Map<String, dynamic>> getCommunityPosts(
    String communityId, {
    int page = 1,
    int limit = 30,
  }) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/communities/$communityId/posts?page=$page&limit=$limit',
      );
      final res = await http.get(uri, headers: await _headers());
      return jsonDecode(res.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to fetch posts',
        'data': null,
      };
    }
  }

  static Future<Map<String, dynamic>> getCommunityMembers(
    String communityId, {
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/communities/$communityId/members?page=$page&limit=$limit',
      );
      final res = await http.get(uri, headers: await _headers());
      return jsonDecode(res.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to fetch members',
        'data': null,
      };
    }
  }

  /// POST /communities/{id}/posts (multipart) - creator-only.
  static Future<Map<String, dynamic>> createCommunityPost({
    required String communityId,
    required String content,
    List<String>? imagePaths,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/communities/$communityId/posts');
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(await _authOnlyHeaders());
      if (content.isNotEmpty) request.fields['content'] = content;
      if (imagePaths != null) {
        for (final p in imagePaths) {
          request.files.add(await http.MultipartFile.fromPath('images', p));
        }
      }
      final streamed = await request.send();
      final body = await streamed.stream.bytesToString();
      return jsonDecode(body);
    } catch (e) {
      return {'success': false, 'message': 'Failed to create post', 'data': null};
    }
  }

  static Future<Map<String, dynamic>> glowCommunityPost(String communityId, String postId) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/communities/$communityId/posts/$postId/glow'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (_) {
      return {'success': false};
    }
  }

  static Future<Map<String, dynamic>> unglowCommunityPost(String communityId, String postId) async {
    try {
      final res = await http.delete(
        Uri.parse('$_baseUrl/communities/$communityId/posts/$postId/glow'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (_) {
      return {'success': false};
    }
  }

  // ── Community post comments / save / share / mute / edit-delete ──

  static Future<Map<String, dynamic>> getCommunityPostComments(String communityId, String postId, {int page = 1, int limit = 50}) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/communities/$communityId/posts/$postId/comments?page=$page&limit=$limit'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (_) {
      return {'success': false, 'data': null};
    }
  }

  static Future<Map<String, dynamic>> addCommunityPostComment(String communityId, String postId, String content, {String? parentId}) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/communities/$communityId/posts/$postId/comments'),
        headers: await _headers(),
        body: jsonEncode({'content': content, if (parentId != null) 'parent_id': parentId}),
      );
      return jsonDecode(res.body);
    } catch (_) {
      return {'success': false};
    }
  }

  static Future<Map<String, dynamic>> deleteCommunityPostComment(String communityId, String postId, String commentId) async {
    try {
      final res = await http.delete(
        Uri.parse('$_baseUrl/communities/$communityId/posts/$postId/comments/$commentId'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (_) {
      return {'success': false};
    }
  }

  static Future<Map<String, dynamic>> saveCommunityPost(String communityId, String postId) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/communities/$communityId/posts/$postId/save'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (_) {
      return {'success': false};
    }
  }

  static Future<Map<String, dynamic>> unsaveCommunityPost(String communityId, String postId) async {
    try {
      final res = await http.delete(
        Uri.parse('$_baseUrl/communities/$communityId/posts/$postId/save'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (_) {
      return {'success': false};
    }
  }

  static Future<Map<String, dynamic>> shareCommunityPost(String communityId, String postId) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/communities/$communityId/posts/$postId/share'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (_) {
      return {'success': false};
    }
  }

  static Future<Map<String, dynamic>> muteCommunity(String communityId) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/communities/$communityId/mute'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (_) {
      return {'success': false};
    }
  }

  static Future<Map<String, dynamic>> updateCommunityPost(String communityId, String postId, String content) async {
    try {
      final res = await http.put(
        Uri.parse('$_baseUrl/communities/$communityId/posts/$postId'),
        headers: await _headers(),
        body: jsonEncode({'content': content}),
      );
      return jsonDecode(res.body);
    } catch (_) {
      return {'success': false};
    }
  }

  static Future<Map<String, dynamic>> deleteCommunityPost(String communityId, String postId) async {
    try {
      final res = await http.delete(
        Uri.parse('$_baseUrl/communities/$communityId/posts/$postId'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (_) {
      return {'success': false};
    }
  }

  static Future<Map<String, dynamic>> getFollowers(
    String userId, {
    int page = 1,
    int limit = 30,
  }) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/users/$userId/followers?page=$page&limit=$limit',
      );
      final res = await http.get(uri, headers: await _headers());
      return jsonDecode(res.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to fetch followers',
        'data': null,
      };
    }
  }

  static Future<Map<String, dynamic>> getFollowing(
    String userId, {
    int page = 1,
    int limit = 30,
  }) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/users/$userId/following?page=$page&limit=$limit',
      );
      final res = await http.get(uri, headers: await _headers());
      return jsonDecode(res.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to fetch following',
        'data': null,
      };
    }
  }

  static Future<Map<String, dynamic>> removeFollower(String userId) async {
    try {
      final res = await http.delete(
        Uri.parse('$_baseUrl/users/$userId/remove-follower'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Unable to remove follower'};
    }
  }

  // REMOVED CONTENT / APPEALS

  static Future<Map<String, dynamic>> getMyRemovedPosts() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/posts/my-removed'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to fetch removed posts',
        'data': null,
      };
    }
  }

  static Future<Map<String, dynamic>> getMyRemovedMoments() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/moments/my-removed'),
        headers: await _headers(),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to fetch removed moments',
        'data': null,
      };
    }
  }

  static Future<Map<String, dynamic>> submitPostAppeal(
    String postId,
    String reason,
  ) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/posts/$postId/appeal'),
        headers: await _headers(),
        body: jsonEncode({'reason': reason}),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Unable to submit appeal'};
    }
  }

  static Future<Map<String, dynamic>> submitMomentAppeal(
    String momentId,
    String reason,
  ) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/moments/$momentId/appeal'),
        headers: await _headers(),
        body: jsonEncode({'reason': reason}),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Unable to submit appeal'};
    }
  }

  /// Get time ago string (YouTube-style) with UTC-to-local conversion.
  /// Server timestamps lack timezone info, so we treat them as UTC
  /// before converting to the client's local time for accurate relative display.
  static String getTimeAgo(String dateStr) {
    try {
      // If no timezone indicator, treat as UTC (append Z)
      final normalized =
          dateStr.endsWith('Z') ||
              dateStr.contains('+') ||
              RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(dateStr)
          ? dateStr
          : '${dateStr}Z';
      final date = DateTime.parse(normalized).toLocal();
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inSeconds < 60) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
      if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
      return '${(diff.inDays / 365).floor()}y ago';
    } catch (_) {
      return 'Recently';
    }
  }
}
