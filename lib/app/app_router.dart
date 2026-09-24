import 'dart:async';

import 'guest_routes.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/app/kitchen_removed_notice.dart';

import '../screens/post_by_id_screen.dart';
import '../features/navigation/presentation/root_shell.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/settings/presentation/profile_auth_screen.dart';
import '../features/subscription/application/flex_purchase_ladder.dart';
import '../features/subscription/presentation/flex_subscription_screen.dart';
import '../features/subscription/presentation/flex_constructor_screen.dart';
import '../features/subscription/presentation/flex_shop_screen.dart';
import '../features/subscription/presentation/admin_flex_features_screen.dart';
import '../features/settings/presentation/stars_wallet_screen.dart';
import '../features/settings/presentation/star_gifts_inventory_screen.dart';
import '../features/settings/presentation/star_gifts_marketplace_screen.dart';
import '../features/settings/presentation/star_invoice_pay_screen.dart';
import '../features/settings/presentation/creator_revenue_screen.dart';
import '../features/channels/presentation/channel_giveaways_screen.dart';
import '../features/channels/presentation/channel_suggested_posts_screen.dart';
import '../features/settings/presentation/stars_checkout_result_screen.dart';
import '../features/settings/presentation/subscription_success_screen.dart';
import '../features/settings/presentation/subscription_cancel_screen.dart';
import '../features/settings/presentation/support_security_screen.dart';
import '../features/settings/backup_page.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/reset_password_screen.dart';
import '../features/auth/presentation/verify_email_screen.dart';
import '../features/auth/presentation/two_factor_verify_screen.dart';
import '../features/legal/presentation/legal_consent_screen.dart';
import '../features/auth/presentation/confirm_email_change_screen.dart';
import '../features/settings/presentation/account_security_screen.dart';
import '../features/settings/presentation/two_factor_setup_screen.dart';
import '../features/settings/presentation/close_friends_screen.dart';
import '../features/settings/presentation/blocked_users_screen.dart';
import '../features/posts/presentation/create_post_screen.dart';
import '../features/community/presentation/community_upload_screen.dart';
import '../features/posts/presentation/edit_profile_post_screen.dart';
import '../models/post_model.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/saved/presentation/saved_posts_screen.dart';
import '../features/miniapps/presentation/miniapps_catalog_screen.dart';
import '../features/stories/presentation/stories_hub_screen.dart';
import '../features/profile/presentation/follow_list_screen.dart';
import '../features/feed/presentation/main_feed_screen.dart';
import '../features/comments/presentation/comments_screen.dart';
import '../features/channels/presentation/channel_detail_screen.dart';
import '../features/channels/presentation/channel_info_screen.dart';
import '../features/channels/presentation/channel_subscribers_screen.dart';
import '../features/channels/presentation/channel_post_detail_screen.dart';
import '../features/channels/presentation/channels_management_screen.dart';
import '../features/channels/presentation/create_channel_screen.dart';
import '../features/channels/presentation/create_channel_post_screen.dart';
import '../features/channels/presentation/channel_settings_screen.dart';
import '../features/creator/presentation/scheduled_posts_screen.dart';
import '../features/creator/presentation/promoted_posts_screen.dart';
import '../features/creator/presentation/creator_tools_screen.dart';
import '../features/ads/presentation/advertiser_hub_screen.dart';
import '../features/referral/presentation/partner_program_screen.dart';
import '../features/ads/presentation/ad_campaign_editor_screen.dart';
import '../features/ads/presentation/ads_review_screen.dart';
import '../features/channels/presentation/channel_management_screen.dart';
import '../features/notifications/presentation/notifications_screen.dart';
import '../features/settings/notification_settings_page.dart';
import '../features/support/presentation/support_screen.dart';
import '../features/analytics/presentation/analytics_screen.dart';
import '../features/moderation/presentation/moderation_dashboard_screen.dart';
import '../features/admin/presentation/admin_refund_queue_screen.dart';
import '../features/admin/presentation/admin_partner_payouts_screen.dart';
import '../features/admin/presentation/admin_creator_payouts_screen.dart';
import '../features/admin/presentation/admin_support_tickets_screen.dart';
import '../features/moderation/presentation/moderation_queue_screen.dart';
import '../features/moderation/presentation/miniapps_moderation_screen.dart';
import '../features/search/application/search_scope.dart';
import '../features/search/presentation/search_screen.dart';
import '../features/reels/presentation/reels_feed_screen.dart';
import '../features/reels/presentation/reels_fullscreen_screen.dart';
import '../features/reels/presentation/reel_by_id_screen.dart';
import '../features/chat/presentation/chats_hub_screen.dart';
import '../features/chat/presentation/chat_archived_screen.dart';
import '../features/chat/presentation/chat_create_group_screen.dart';
import '../features/chat/presentation/chat_people_search_screen.dart';
import '../features/chat/presentation/chat_folder_edit_screen.dart';
import '../features/chat/presentation/chat_group_info_screen.dart';
import '../features/chat/presentation/chat_media_gallery_screen.dart';
import '../features/chat/presentation/sticker_pack_manage_screen.dart';
import '../features/chat/presentation/sticker_pack_preview_screen.dart';
import '../features/stories/presentation/story_camera_screen.dart';
import '../features/stories/presentation/story_viewer_screen.dart';
import '../features/monetization/presentation/donation_screen.dart';
import '../features/channels/presentation/channel_search_screen.dart';
import '../services/channel_service.dart';
import '../features/chat/presentation/chat_group_moderation_log_screen.dart';
import '../features/miniapps/presentation/miniapp_webview_screen.dart';
import '../features/chat/presentation/chat_invite_join_screen.dart';
import '../features/settings/presentation/paid_message_exceptions_screen.dart';
import '../features/chat/application/chat_private_reply.dart';
import '../features/chat/presentation/chat_thread_screen.dart';
import '../features/chat/presentation/username_deep_link_screen.dart';
import '../features/bots/data/bot_models.dart';
import '../features/bots/presentation/bot_detail_screen.dart';
import '../features/bots/presentation/my_bots_screen.dart';
import '../models/chat_models.dart';
import '../features/referral/pending_referral.dart';
import '../services/auth_service.dart';
import '../services/pending_referral_store.dart';
import 'app_bootstrap_state.dart';
import 'auth_route_paths.dart';
import 'boot_screen.dart';
import 'bootstrap.dart';
import 'router_keys.dart';
import 'web_app_path.dart';
import 'web_session_landing_screen.dart';
import 'invalid_link_screen.dart';
import '../widgets/app_empty_state.dart';

bool _isAppHttpHost(String host) {
  final h = host.toLowerCase();
  return h == 'haneat.app' ||
      h == 'www.haneat.app' ||
      h == 'localhost' ||
      h == '127.0.0.1' ||
      h == '0.0.0.0' ||
      h == '[::1]';
}

/// Paid channel screens live under `/channels/:id/...`.
/// Keep `/channel/:id/giveaways` in the same family as info/settings.
/// Telegram-style wrappers: `/go/c/1/info`, `/open/chats/21`.
String unwrapGoOpenPath(String path) {
  var clean = path.split('?').first;
  while (true) {
    if (clean.startsWith('/go/')) {
      clean = clean.substring(3);
    } else if (clean.startsWith('/open/')) {
      clean = clean.substring(5);
    } else {
      break;
    }
    if (clean.isEmpty) return '/';
    if (!clean.startsWith('/')) clean = '/$clean';
  }
  return clean;
}

String? leftoverPathAlias(String path, [String query = '']) {
  final unwrapped = unwrapGoOpenPath(path);
  return channelPaidPathAlias(unwrapped, query) ??
      shortcutPathAlias(unwrapped, query) ??
      botSectionPathAlias(unwrapped, query) ??
      resourcePathAlias(unwrapped, query);
}

/// Leftover Telegram call hashes on a thread start a real voice/video call.
String? leftoverThreadCallMedia(String rest) {
  switch (rest) {
    case 'voice-chat':
    case 'raise-hand':
    case 'redial':
    case 'group-call':
    case 'join-voice-chat':
    case 'call':
    case 'voice':
    case 'audio':
      return 'voice';
    case 'screen-share':
    case 'video-chat':
    case 'video':
    case 'videocall':
      return 'video';
    default:
      return null;
  }
}

String? leftoverResourceCallMedia(String kind) {
  switch (kind) {
    case 'liveid':
    case 'vcid':
    case 'call-id':
    case 'vc-id':
    case 'speakerid':
    case 'livestreamid':
    case 'rtmpid':
    case 'groupcallid':
    case 'callid':
      return 'voice';
    default:
      return null;
  }
}

String pathWithCallQuery(String path, String media, [String query = '']) {
  final parts = <String>[];
  if (query.isNotEmpty) parts.add(query);
  if (!RegExp(r'(^|&)call=').hasMatch(query)) {
    parts.add('call=$media');
  }
  if (parts.isEmpty) return path;
  return '$path?${parts.join('&')}';
}

String leftoverChatOpenPath(int id, String rest, [String query = '']) {
  final media = leftoverThreadCallMedia(rest);
  if (media != null) {
    return pathWithCallQuery('/chats/thread/$id', media, query);
  }
  return '/chats/thread/$id${query.isEmpty ? '' : '?$query'}';
}

String? channelPaidPathAlias(String path, [String query = '']) {
  final clean = path.split('?').first;
  final segs = clean.split('/').where((s) => s.isNotEmpty).toList();
  if (segs.length != 3) return null;
  if (segs[0] != 'channel' && segs[0] != 'c' && segs[0] != 'ch') return null;
  if (int.tryParse(segs[1]) == null) return null;
  if (segs[2] != 'giveaways' && segs[2] != 'suggested-posts') return null;
  final q = query.isEmpty ? '' : '?$query';
  return '/channels/${segs[1]}/${segs[2]}$q';
}

/// ID-bearing leftovers: plural channels, short chats, invoices, join links.
String? resourcePathAlias(String path, [String query = '']) {
  final clean = path.split('?').first;
  final segs = clean.split('/').where((s) => s.isNotEmpty).toList();
  if (segs.isEmpty) return null;
  final q = query.isEmpty ? '' : '?$query';

  if (segs[0] == 'channels' && segs.length >= 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) {
      if (segs.length == 2) return '/channel/$id$q';
      final rest = segs[2];
      if (rest == 'giveaways' || rest == 'suggested-posts') return null;
      const channelPages = {
        'info',
        'settings',
        'subscribers',
        'search',
        'management',
        'create-post',
      };
      if (rest == 'posts' ||
          rest == 'feed' ||
          rest == 'wall' ||
          rest == 'boost' ||
          rest == 'live' ||
          rest == 'stream' ||
          rest == 'discussion' ||
          rest == 'linked' ||
          rest == 'voicechat' ||
          rest == 'stats' ||
          rest == 'insights' ||
          rest == 'analytics' ||
          rest == 'boosts' ||
          rest == 'statistics' ||
          rest == 'reactions' ||
          rest == 'mute' ||
          rest == 'unmute' ||
          rest == 'pin' ||
          rest == 'slowmode' ||
          rest == 'protect' ||
          rest == 'signatures' ||
          rest == 'color' ||
          rest == 'autodelete' ||
          rest == 'permissions' ||
          rest == 'antispam' ||
          rest == 'sign' ||
          rest == 'join-to-send' ||
          rest == 'join-to-comment' ||
          rest == 'default-permissions' ||
          rest == 'approve' ||
          rest == 'hide-members' ||
          rest == 'restrict' ||
          rest == 'topics' ||
          rest == 'forum' ||
          rest == 'export' ||
          rest == 'leave' ||
          rest == 'report' ||
          rest == 'copy-link' ||
          rest == 'title' ||
          rest == 'monetization' ||
          rest == 'suggested' ||
          rest == 'description' ||
          rest == 'photo' ||
          rest == 'owner' ||
          rest == 'qr' ||
          rest == 'clear' ||
          rest == 'type' ||
          rest == 'username' ||
          rest == 'about' ||
          rest == 'rules' ||
          rest == 'welcome' ||
          rest == 'invite-expire' ||
          rest == 'invite-limit' ||
          rest == 'invite-revoke' ||
          rest == 'offer' ||
          rest == 'suggested-settings' ||
          rest == 'transfer' ||
          rest == 'ownership' ||
          rest == 'post-stories' ||
          rest == 'manage-gifts' ||
          rest == 'change-profile' ||
          rest == 'add-admins' ||
          rest == 'voice-chat' ||
          rest == 'stream-live' ||
          rest == 'record-live' ||
          rest == 'group-call' ||
          rest == 'start-livestream' ||
          rest == 'stop-livestream' ||
          rest == 'schedule-live') {
        return '/channel/$id$q';
      }
      if (rest == 'invite' || rest == 'invite-link') {
        return '/channel/$id/info$q';
      }
      if (rest == 'members' || rest == 'admins') {
        return '/channel/$id/subscribers$q';
      }
      if (channelPages.contains(rest) && segs.length == 3) {
        return '/channel/$id/$rest$q';
      }
      if (rest == 'post' && segs.length >= 4) {
        final postId = int.tryParse(segs[3]);
        if (postId != null && postId > 0) {
          if (segs.length == 4) return '/channel/$id/post/$postId$q';
          if (segs.length == 5 && segs[4] == 'edit') {
            return '/channel/$id/post/$postId/edit$q';
          }
          if (segs.length == 5 && segs[4] == 'comments') {
            return '/post/$postId/comments$q';
          }
          if (segs.length == 5 &&
              (segs[4] == 'likes' || segs[4] == 'likers')) {
            return '/channel/$id/post/$postId$q';
          }
        }
      }
    }
  }

  const chatRoots = {
    'chats',
    'chat',
    'dialog',
    'dialogs',
    'dialogues',
    'conversation',
    'dm',
    'messages',
  };
  const chatReserved = {'archived', 'new', 'new-group', 'folders', 'thread'};
  if (chatRoots.contains(segs[0]) && segs.length == 2) {
    if (chatReserved.contains(segs[1])) return null;
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/chats/thread/$id$q';
  }
  if ((chatRoots.contains(segs[0]) ||
          segs[0] == 'group' ||
          segs[0] == 'groups' ||
          segs[0] == 'supergroup' ||
          segs[0] == 'gigagroup' ||
          segs[0] == 'megagroup') &&
      segs.length == 3) {
    if (chatReserved.contains(segs[1])) return null;
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) {
      if (segs[2] == 'info' || segs[2] == 'media' || segs[2] == 'log') {
        return '/chats/thread/$id/${segs[2]}$q';
      }
      if (segs[2] == 'gallery' ||
          segs[2] == 'photos' ||
          segs[2] == 'files' ||
          segs[2] == 'links') {
        return '/chats/thread/$id/media$q';
      }
      if (segs[2] == 'members' || segs[2] == 'admins') {
        return '/chats/thread/$id/info$q';
      }
      if (segs[2] == 'invite' || segs[2] == 'invite-link') {
        return '/chats/thread/$id/info$q';
      }
      if (segs[2] == 'call' || segs[2] == 'voice' || segs[2] == 'video') {
        return leftoverChatOpenPath(id, segs[2], query);
      }
      if (segs[2] == 'mute' ||
          segs[2] == 'pin' ||
          segs[2] == 'secret' ||
          segs[2] == 'search' ||
          segs[2] == 'pinned' ||
          segs[2] == 'archive' ||
          segs[2] == 'unmute' ||
          segs[2] == 'unpin' ||
          segs[2] == 'unread' ||
          segs[2] == 'ttl' ||
          segs[2] == 'theme' ||
          segs[2] == 'slowmode' ||
          segs[2] == 'slow-mode' ||
          segs[2] == 'protect' ||
          segs[2] == 'signatures' ||
          segs[2] == 'wallpaper' ||
          segs[2] == 'autodelete' ||
          segs[2] == 'color' ||
          segs[2] == 'send-as' ||
          segs[2] == 'permissions' ||
          segs[2] == 'effects' ||
          segs[2] == 'reminders' ||
          segs[2] == 'antispam' ||
          segs[2] == 'reactions' ||
          segs[2] == 'translate' ||
          segs[2] == 'seen' ||
          segs[2] == 'default-permissions' ||
          segs[2] == 'approve' ||
          segs[2] == 'join-to-send' ||
          segs[2] == 'join-to-comment' ||
          segs[2] == 'hide-members' ||
          segs[2] == 'restrict' ||
          segs[2] == 'topics' ||
          segs[2] == 'forum' ||
          segs[2] == 'discussion' ||
          segs[2] == 'linked' ||
          segs[2] == 'export' ||
          segs[2] == 'leave' ||
          segs[2] == 'report' ||
          segs[2] == 'copy-link' ||
          segs[2] == 'title' ||
          segs[2] == 'stats' ||
          segs[2] == 'history' ||
          segs[2] == 'description' ||
          segs[2] == 'photo' ||
          segs[2] == 'type' ||
          segs[2] == 'convert' ||
          segs[2] == 'owner' ||
          segs[2] == 'qr' ||
          segs[2] == 'clear' ||
          segs[2] == 'username' ||
          segs[2] == 'about' ||
          segs[2] == 'rules' ||
          segs[2] == 'welcome' ||
          segs[2] == 'invite-expire' ||
          segs[2] == 'invite-limit' ||
          segs[2] == 'invite-revoke' ||
          segs[2] == 'topic-icon' ||
          segs[2] == 'topic-color' ||
          segs[2] == 'transfer' ||
          segs[2] == 'ownership' ||
          segs[2] == 'speaker' ||
          segs[2] == 'slow-seconds' ||
          segs[2] == 'send-photos' ||
          segs[2] == 'restrict-media' ||
          segs[2] == 'manage-topics' ||
          segs[2] == 'add-admins' ||
          segs[2] == 'post-stories' ||
          segs[2] == 'voice-chat' ||
          segs[2] == 'raise-hand' ||
          segs[2] == 'screen-share' ||
          segs[2] == 'redial' ||
          segs[2] == 'group-call' ||
          segs[2] == 'video-chat' ||
          segs[2] == 'join-voice-chat' ||
          segs[2] == 'leave-voice-chat' ||
          segs[2] == 'call' ||
          segs[2] == 'voice' ||
          segs[2] == 'audio' ||
          segs[2] == 'video' ||
          segs[2] == 'videocall') {
        return leftoverChatOpenPath(id, segs[2], query);
      }
      final mid = int.tryParse(segs[2]);
      if (mid != null && mid > 0) {
        return query.isEmpty
            ? '/chats/thread/$id?msg=$mid'
            : '/chats/thread/$id?$query&msg=$mid';
      }
    }
  }
  if (segs.length == 4 && segs[0] == 'chats' && segs[1] == 'thread') {
    final id = int.tryParse(segs[2]);
    if (id != null && id > 0) {
      if (segs[3] == 'members' || segs[3] == 'admins') {
        return '/chats/thread/$id/info$q';
      }
      if (segs[3] == 'gallery' ||
          segs[3] == 'photos' ||
          segs[3] == 'files' ||
          segs[3] == 'links') {
        return '/chats/thread/$id/media$q';
      }
      if (segs[3] == 'call' || segs[3] == 'voice' || segs[3] == 'video') {
        return leftoverChatOpenPath(id, segs[3], query);
      }
      if (segs[3] == 'search' ||
          segs[3] == 'pinned' ||
          segs[3] == 'mute' ||
          segs[3] == 'pin' ||
          segs[3] == 'secret' ||
          segs[3] == 'archive' ||
          segs[3] == 'unmute' ||
          segs[3] == 'unpin' ||
          segs[3] == 'unread' ||
          segs[3] == 'ttl' ||
          segs[3] == 'theme' ||
          segs[3] == 'slowmode' ||
          segs[3] == 'slow-mode' ||
          segs[3] == 'protect' ||
          segs[3] == 'signatures' ||
          segs[3] == 'wallpaper' ||
          segs[3] == 'autodelete' ||
          segs[3] == 'color' ||
          segs[3] == 'send-as' ||
          segs[3] == 'permissions' ||
          segs[3] == 'effects' ||
          segs[3] == 'reminders' ||
          segs[3] == 'antispam' ||
          segs[3] == 'reactions' ||
          segs[3] == 'translate' ||
          segs[3] == 'seen' ||
          segs[3] == 'default-permissions' ||
          segs[3] == 'approve' ||
          segs[3] == 'join-to-send' ||
          segs[3] == 'join-to-comment' ||
          segs[3] == 'hide-members' ||
          segs[3] == 'restrict' ||
          segs[3] == 'topics' ||
          segs[3] == 'forum' ||
          segs[3] == 'discussion' ||
          segs[3] == 'linked' ||
          segs[3] == 'export' ||
          segs[3] == 'leave' ||
          segs[3] == 'report' ||
          segs[3] == 'copy-link' ||
          segs[3] == 'title' ||
          segs[3] == 'stats' ||
          segs[3] == 'history' ||
          segs[3] == 'description' ||
          segs[3] == 'photo' ||
          segs[3] == 'type' ||
          segs[3] == 'convert' ||
          segs[3] == 'owner' ||
          segs[3] == 'qr' ||
          segs[3] == 'clear' ||
          segs[3] == 'username' ||
          segs[3] == 'about' ||
          segs[3] == 'rules' ||
          segs[3] == 'welcome' ||
          segs[3] == 'invite-expire' ||
          segs[3] == 'invite-limit' ||
          segs[3] == 'invite-revoke' ||
          segs[3] == 'topic-icon' ||
          segs[3] == 'topic-color' ||
          segs[3] == 'transfer' ||
          segs[3] == 'ownership' ||
          segs[3] == 'speaker' ||
          segs[3] == 'slow-seconds' ||
          segs[3] == 'send-photos' ||
          segs[3] == 'restrict-media' ||
          segs[3] == 'manage-topics' ||
          segs[3] == 'add-admins' ||
          segs[3] == 'post-stories' ||
          segs[3] == 'voice-chat' ||
          segs[3] == 'raise-hand' ||
          segs[3] == 'screen-share' ||
          segs[3] == 'redial' ||
          segs[3] == 'group-call' ||
          segs[3] == 'video-chat' ||
          segs[3] == 'join-voice-chat' ||
          segs[3] == 'leave-voice-chat' ||
          segs[3] == 'call' ||
          segs[3] == 'voice' ||
          segs[3] == 'audio' ||
          segs[3] == 'video' ||
          segs[3] == 'videocall') {
        return leftoverChatOpenPath(id, segs[3], query);
      }
      if (segs[3] == 'invite' || segs[3] == 'invite-link') {
        return '/chats/thread/$id/info$q';
      }
      final mid = int.tryParse(segs[3]);
      if (mid != null && mid > 0) {
        return query.isEmpty
            ? '/chats/thread/$id?msg=$mid'
            : '/chats/thread/$id?$query&msg=$mid';
      }
    }
  }

  if ((segs[0] == 'invoice' || segs[0] == 'invoices' || segs[0] == 'receipt' || segs[0] == 'bill') && segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/paid/invoices/$id$q';
  }
  if (segs.length == 3 &&
      ((segs[0] == 'paid' &&
              (segs[1] == 'invoice' || segs[1] == 'invoice-pay')) ||
          (segs[0] == 'stars' &&
              (segs[1] == 'invoice' || segs[1] == 'invoices'))) &&
      int.tryParse(segs[2]) != null) {
    final id = int.parse(segs[2]);
    if (id > 0) return '/paid/invoices/$id$q';
  }

  if ((segs[0] == 'join' ||
          segs[0] == 'joinchat' ||
          segs[0] == 'join-chat' ||
          segs[0] == 'addlist') &&
      segs.length == 2 &&
      segs[1].isNotEmpty) {
    return '/chat-invite/${Uri.encodeComponent(segs[1])}$q';
  }

  if ((segs[0] == 'user' || segs[0] == 'users') && segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '${ProfileRoute.path}?userId=$id';
  }
  if (segs[0] == 'profile' && segs.length == 2) {
    if (segs[1] == 'followers' ||
        segs[1] == 'following' ||
        segs[1] == 'edit') {
      return null;
    }
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '${ProfileRoute.path}?userId=$id';
  }
  if (segs[0] == 'profile' && segs.length == 3) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) {
      if (segs[2] == 'followers') return ProfileFollowersRoute.withUserId(id);
      if (segs[2] == 'following') return ProfileFollowingRoute.withUserId(id);
      if (segs[2] == 'posts' ||
          segs[2] == 'feed' ||
          segs[2] == 'stories' ||
          segs[2] == 'moments' ||
          segs[2] == 'highlights') {
        return ProfileRoute.withUserId(id);
      }
    }
  }
  if ((segs[0] == 'user' || segs[0] == 'users') && segs.length == 3) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) {
      if (segs[2] == 'followers') return ProfileFollowersRoute.withUserId(id);
      if (segs[2] == 'following') return ProfileFollowingRoute.withUserId(id);
      if (segs[2] == 'stories' ||
          segs[2] == 'moments' ||
          segs[2] == 'highlights' ||
          segs[2] == 'posts') {
        return ProfileRoute.withUserId(id);
      }
    }
  }
  if ((segs[0] == 'followers' || segs[0] == 'following') && segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) {
      return segs[0] == 'followers'
          ? ProfileFollowersRoute.withUserId(id)
          : ProfileFollowingRoute.withUserId(id);
    }
  }
  if (segs[0] == 'u' && segs.length == 3 && segs[1].isNotEmpty) {
    if (segs[2] == 'followers' ||
        segs[2] == 'following' ||
        segs[2] == 'posts' ||
        segs[2] == 'stories' ||
        segs[2] == 'moments' ||
        segs[2] == 'highlights') {
      return UsernameDeepLinkRoute.pathFor(segs[1]);
    }
  }

  if ((segs[0] == 'c' || segs[0] == 'ch') && segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/channel/$id$q';
  }
  if ((segs[0] == 'c' || segs[0] == 'ch' || segs[0] == 'channel') &&
      segs.length == 3) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) {
      final rest = segs[2];
      if (rest == 'posts' ||
          rest == 'feed' ||
          rest == 'wall' ||
          rest == 'boost' ||
          rest == 'live' ||
          rest == 'stream' ||
          rest == 'discussion' ||
          rest == 'linked' ||
          rest == 'voicechat' ||
          rest == 'stats' ||
          rest == 'insights' ||
          rest == 'analytics' ||
          rest == 'boosts' ||
          rest == 'statistics' ||
          rest == 'reactions' ||
          rest == 'mute' ||
          rest == 'unmute' ||
          rest == 'pin' ||
          rest == 'slowmode' ||
          rest == 'protect' ||
          rest == 'signatures' ||
          rest == 'color' ||
          rest == 'autodelete' ||
          rest == 'permissions' ||
          rest == 'antispam' ||
          rest == 'sign' ||
          rest == 'join-to-send' ||
          rest == 'join-to-comment' ||
          rest == 'default-permissions' ||
          rest == 'approve' ||
          rest == 'hide-members' ||
          rest == 'restrict' ||
          rest == 'topics' ||
          rest == 'forum' ||
          rest == 'export' ||
          rest == 'leave' ||
          rest == 'report' ||
          rest == 'copy-link' ||
          rest == 'title' ||
          rest == 'monetization' ||
          rest == 'suggested' ||
          rest == 'description' ||
          rest == 'photo' ||
          rest == 'owner' ||
          rest == 'qr' ||
          rest == 'clear' ||
          rest == 'type' ||
          rest == 'username' ||
          rest == 'about' ||
          rest == 'rules' ||
          rest == 'welcome' ||
          rest == 'invite-expire' ||
          rest == 'invite-limit' ||
          rest == 'invite-revoke' ||
          rest == 'offer' ||
          rest == 'suggested-settings' ||
          rest == 'transfer' ||
          rest == 'ownership' ||
          rest == 'post-stories' ||
          rest == 'manage-gifts' ||
          rest == 'change-profile' ||
          rest == 'add-admins' ||
          rest == 'voice-chat' ||
          rest == 'stream-live' ||
          rest == 'record-live' ||
          rest == 'group-call' ||
          rest == 'start-livestream' ||
          rest == 'stop-livestream' ||
          rest == 'schedule-live') {
        return '/channel/$id$q';
      }
      if (rest == 'invite' || rest == 'invite-link') {
        return '/channel/$id/info$q';
      }
      if (rest == 'members' || rest == 'admins') {
        return '/channel/$id/subscribers$q';
      }
      const channelPages = {
        'info',
        'settings',
        'subscribers',
        'search',
        'management',
        'create-post',
      };
      if (channelPages.contains(rest)) {
        return '/channel/$id/$rest$q';
      }
      final postId = int.tryParse(rest);
      if (postId != null && postId > 0) {
        return '/channel/$id/post/$postId$q';
      }
    }
  }
  if ((segs[0] == 'c' || segs[0] == 'ch' || segs[0] == 'channel') &&
      segs.length >= 4 &&
      segs[2] == 'post') {
    final id = int.tryParse(segs[1]);
    final postId = int.tryParse(segs[3]);
    if (id != null && id > 0 && postId != null && postId > 0) {
      if (segs.length == 4) return '/channel/$id/post/$postId$q';
      if (segs.length == 5 && segs[4] == 'edit') {
        return '/channel/$id/post/$postId/edit$q';
      }
      if (segs.length == 5 && segs[4] == 'comments') {
        return '/post/$postId/comments$q';
      }
      if (segs.length == 5 &&
          (segs[4] == 'likes' || segs[4] == 'likers')) {
        return '/channel/$id/post/$postId$q';
      }
    }
  }

  if (segs[0] == 'posts' && segs.length >= 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) {
      if (segs.length == 2) return '/post/$id$q';
      if (segs.length == 3 && segs[2] == 'comments') {
        return '/post/$id/comments$q';
      }
      if (segs.length == 3 && segs[2] == 'edit') {
        return '/post/$id/edit$q';
      }
      if (segs.length == 3 &&
          (segs[2] == 'likes' ||
              segs[2] == 'likers' ||
              segs[2] == 'like' ||
              segs[2] == 'react' ||
              segs[2] == 'reactors' ||
              segs[2] == 'tips' ||
              segs[2] == 'tip' ||
              segs[2] == 'via' ||
              segs[2] == 'forwarded' ||
              segs[2] == 'bookmark' ||
              segs[2] == 'save' ||
              segs[2] == 'pin' ||
              segs[2] == 'hide' ||
              segs[2] == 'report' ||
              segs[2] == 'download' ||
              segs[2] == 'embed' ||
              segs[2] == 'permalink' ||
              segs[2] == 'copy' ||
              segs[2] == 'open' ||
              segs[2] == 'full' ||
              segs[2] == 'zoom' ||
              segs[2] == 'offer' ||
              segs[2] == 'accept' ||
              segs[2] == 'reject')) {
        return '/post/$id$q';
      }
      if (segs.length == 3 &&
          (segs[2] == 'share' ||
              segs[2] == 'repost' ||
              segs[2] == 'forward' ||
              segs[2] == 'send')) {
        return '/post/$id$q';
      }
      if (segs.length == 3 &&
          (segs[2] == 'analytics' ||
              segs[2] == 'stats' ||
              segs[2] == 'insights')) {
        return AppAnalyticsRoute.pathWithPostId(id);
      }
      if (segs.length == 3 &&
          (segs[2] == 'views' ||
              segs[2] == 'forwards' ||
              segs[2] == 'view')) {
        return '/post/$id$q';
      }
    }
  }
  if (segs[0] == 'p' && segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/post/$id$q';
  }
  if (segs[0] == 'p' && segs.length == 3) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) {
      if (segs[2] == 'comments') return '/post/$id/comments$q';
      if (segs[2] == 'edit') return '/post/$id/edit$q';
      if (segs[2] == 'likes' ||
          segs[2] == 'likers' ||
          segs[2] == 'like' ||
          segs[2] == 'react' ||
          segs[2] == 'reactors' ||
          segs[2] == 'tips' ||
          segs[2] == 'tip' ||
          segs[2] == 'via' ||
          segs[2] == 'forwarded' ||
          segs[2] == 'bookmark' ||
          segs[2] == 'save' ||
          segs[2] == 'pin' ||
          segs[2] == 'hide' ||
          segs[2] == 'report' ||
          segs[2] == 'download' ||
          segs[2] == 'embed' ||
          segs[2] == 'permalink' ||
          segs[2] == 'copy' ||
          segs[2] == 'open' ||
          segs[2] == 'full' ||
          segs[2] == 'zoom' ||
          segs[2] == 'offer' ||
          segs[2] == 'accept' ||
          segs[2] == 'reject') {
        return '/post/$id$q';
      }
      if (segs[2] == 'share' ||
          segs[2] == 'repost' ||
          segs[2] == 'forward' ||
          segs[2] == 'send') {
        return '/post/$id$q';
      }
      if (segs[2] == 'analytics' ||
          segs[2] == 'stats' ||
          segs[2] == 'insights') {
        return AppAnalyticsRoute.pathWithPostId(id);
      }
      if (segs[2] == 'views' ||
          segs[2] == 'forwards' ||
          segs[2] == 'view') {
        return '/post/$id$q';
      }
    }
  }

  if ((segs[0] == 'bot' || segs[0] == 'bots') && segs.length == 2) {
    if (segs[1] == 'my') return null;
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/bots/$id$q';
  }
  if ((segs[0] == 'bot' || segs[0] == 'bots') && segs.length == 3) {
    final id = int.tryParse(segs[1]);
    if (id != null &&
        id > 0 &&
        (segs[2] == 'edit' ||
            segs[2] == 'profile' ||
            segs[2] == 'start' ||
            segs[2] == 'open' ||
            segs[2] == 'launch')) {
      return '/bots/$id$q';
    }
  }

  const miniRoots = {
    'miniapp',
    'miniapps',
    'mini-apps',
    'mini-app',
    'webapps',
    'web-app',
    'twa',
  };
  if (miniRoots.contains(segs[0]) && segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/webapp/$id$q';
  }

  if ((segs[0] == 'folder' || segs[0] == 'folders') && segs.length == 2) {
    if (segs[1] == 'new') return '${ChatFolderNewRoute.path}$q';
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/chats/folders/$id$q';
  }
  if ((segs[0] == 'folder' || segs[0] == 'folders') && segs.length == 3) {
    final id = int.tryParse(segs[1]);
    if (id != null &&
        id > 0 &&
        (segs[2] == 'edit' || segs[2] == 'settings')) {
      return '/chats/folders/$id$q';
    }
  }

  if ((segs[0] == 'sticker' ||
          segs[0] == 'stickerset' ||
          segs[0] == 'stickerpack' ||
          segs[0] == 'sticker-pack' ||
          segs[0] == 'pack' ||
          segs[0] == 'addsticker' ||
          segs[0] == 'add-stickers') &&
      segs.length == 2 &&
      segs[1].isNotEmpty) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/stickers/$id$q';
    return '/addstickers/${Uri.encodeComponent(segs[1])}$q';
  }

  if ((segs[0] == 'moment' ||
          segs[0] == 'moments' ||
          segs[0] == 'highlight' ||
          segs[0] == 'highlights' ||
          segs[0] == 's') &&
      segs.length == 2) {
    if (segs[1] == 'create') return '${StoryCreateRoute.path}$q';
    if (segs[1] == 'archive') return '${StoriesRoute.path}$q';
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/stories/$id$q';
  }

  if ((segs[0] == 'donate' || segs[0] == 'tip') && segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) {
      return query.isEmpty ? '/donate?to=$id' : '/donate?to=$id&$query';
    }
  }

  if ((segs[0] == 'ad' || segs[0] == 'campaign' || segs[0] == 'campaigns') &&
      segs.length == 2) {
    if (segs[1] == 'new') return '${AdsCampaignEditorRoute.path}$q';
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/ads/$id$q';
  }

  if ((segs[0] == 'group' ||
          segs[0] == 'groups' ||
          segs[0] == 'supergroup' ||
          segs[0] == 'gigagroup' ||
          segs[0] == 'megagroup') &&
      segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/chats/thread/$id$q';
  }

  if ((segs[0] == 'hashtag' || segs[0] == 'tag' || segs[0] == 'h') &&
      segs.length == 2 &&
      segs[1].isNotEmpty) {
    final raw = segs[1].startsWith('#') ? segs[1] : '#${segs[1]}';
    return '${SearchRoute.path}?q=${Uri.encodeQueryComponent(raw)}';
  }

  if ((segs[0] == 'notif' || segs[0] == 'notification') && segs.length == 2) {
    return '${NotificationsRoute.path}$q';
  }

  if (segs[0] == 'post' && segs.length == 3) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) {
      if (segs[2] == 'likes' ||
          segs[2] == 'likers' ||
          segs[2] == 'like' ||
          segs[2] == 'react' ||
          segs[2] == 'reactors' ||
          segs[2] == 'tips' ||
          segs[2] == 'tip' ||
          segs[2] == 'via' ||
          segs[2] == 'forwarded' ||
          segs[2] == 'bookmark' ||
          segs[2] == 'save' ||
          segs[2] == 'pin' ||
          segs[2] == 'hide' ||
          segs[2] == 'report' ||
          segs[2] == 'download' ||
          segs[2] == 'embed' ||
          segs[2] == 'permalink' ||
          segs[2] == 'copy' ||
          segs[2] == 'open' ||
          segs[2] == 'full' ||
          segs[2] == 'zoom' ||
          segs[2] == 'offer' ||
          segs[2] == 'accept' ||
          segs[2] == 'reject') {
        return '/post/$id$q';
      }
      if (segs[2] == 'share' ||
          segs[2] == 'repost' ||
          segs[2] == 'forward' ||
          segs[2] == 'send') {
        return '/post/$id$q';
      }
      if (segs[2] == 'comments') {
        return '/post/$id/comments$q';
      }
      if (segs[2] == 'analytics' ||
          segs[2] == 'stats' ||
          segs[2] == 'insights') {
        return AppAnalyticsRoute.pathWithPostId(id);
      }
      if (segs[2] == 'views' ||
          segs[2] == 'forwards' ||
          segs[2] == 'view') {
        return '/post/$id$q';
      }
    }
  }
  if ((segs[0] == 'comment' || segs[0] == 'comments') && segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/post/$id/comments$q';
  }
  if ((segs[0] == 'video' ||
          segs[0] == 'photo' ||
          segs[0] == 'image' ||
          segs[0] == 'img' ||
          segs[0] == 'pic' ||
          segs[0] == 'media' ||
          segs[0] == 'voice' ||
          segs[0] == 'audio' ||
          segs[0] == 'file' ||
          segs[0] == 'doc' ||
          segs[0] == 'document' ||
          segs[0] == 'poll') &&
      segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/post/$id$q';
  }
  if ((segs[0] == 'video' ||
          segs[0] == 'photo' ||
          segs[0] == 'image' ||
          segs[0] == 'img' ||
          segs[0] == 'pic' ||
          segs[0] == 'media') &&
      segs.length == 3) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) {
      if (segs[2] == 'comments') return '/post/$id/comments$q';
      if (segs[2] == 'likes' ||
          segs[2] == 'share' ||
          segs[2] == 'repost') {
        return '/post/$id$q';
      }
    }
  }
  if ((segs[0] == 'analytics' || segs[0] == 'stats' || segs[0] == 'insights') &&
      segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return AppAnalyticsRoute.pathWithPostId(id);
  }

  if ((segs[0] == 'gift' || segs[0] == 'gifts') && segs.length == 2) {
    if (segs[1] == 'market' || segs[1] == 'shop' || segs[1] == 'marketplace') {
      return null;
    }
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '${StarGiftsInventoryRoute.path}$q';
  }
  if ((segs[0] == 'gift' || segs[0] == 'gifts') && segs.length == 3) {
    if (segs[2] == 'send' || segs[2] == 'view') {
      return '${StarGiftsInventoryRoute.path}$q';
    }
  }

  const extraChatRoots = {
    'direct',
    'im',
    'msg',
    'message',
    'thread',
    'convo',
    'private',
    'm',
    'tg',
  };
  if (extraChatRoots.contains(segs[0]) && segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/chats/thread/$id$q';
  }
  if (extraChatRoots.contains(segs[0]) && segs.length == 3) {
    if (segs[1] == 't' || segs[1] == 'c') {
      final id = int.tryParse(segs[2]);
      if (id != null && id > 0) return '/chats/thread/$id$q';
    }
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) {
      if (segs[2] == 'info' || segs[2] == 'media' || segs[2] == 'log') {
        return '/chats/thread/$id/${segs[2]}$q';
      }
      if (segs[2] == 'gallery' ||
          segs[2] == 'photos' ||
          segs[2] == 'files' ||
          segs[2] == 'links') {
        return '/chats/thread/$id/media$q';
      }
      if (segs[2] == 'members' || segs[2] == 'admins') {
        return '/chats/thread/$id/info$q';
      }
      if (segs[2] == 'invite' || segs[2] == 'invite-link') {
        return '/chats/thread/$id/info$q';
      }
      if (segs[2] == 'call' || segs[2] == 'voice' || segs[2] == 'video') {
        return leftoverChatOpenPath(id, segs[2], query);
      }
      if (segs[2] == 'mute' ||
          segs[2] == 'pin' ||
          segs[2] == 'secret' ||
          segs[2] == 'search' ||
          segs[2] == 'pinned' ||
          segs[2] == 'archive' ||
          segs[2] == 'unmute' ||
          segs[2] == 'unpin' ||
          segs[2] == 'unread' ||
          segs[2] == 'ttl' ||
          segs[2] == 'theme' ||
          segs[2] == 'slowmode' ||
          segs[2] == 'slow-mode' ||
          segs[2] == 'protect' ||
          segs[2] == 'signatures' ||
          segs[2] == 'wallpaper' ||
          segs[2] == 'autodelete' ||
          segs[2] == 'color' ||
          segs[2] == 'send-as' ||
          segs[2] == 'permissions' ||
          segs[2] == 'effects' ||
          segs[2] == 'reminders' ||
          segs[2] == 'antispam' ||
          segs[2] == 'reactions' ||
          segs[2] == 'translate' ||
          segs[2] == 'seen' ||
          segs[2] == 'default-permissions' ||
          segs[2] == 'approve' ||
          segs[2] == 'join-to-send' ||
          segs[2] == 'join-to-comment' ||
          segs[2] == 'hide-members' ||
          segs[2] == 'restrict' ||
          segs[2] == 'topics' ||
          segs[2] == 'forum' ||
          segs[2] == 'discussion' ||
          segs[2] == 'linked' ||
          segs[2] == 'export' ||
          segs[2] == 'leave' ||
          segs[2] == 'report' ||
          segs[2] == 'copy-link' ||
          segs[2] == 'title' ||
          segs[2] == 'stats' ||
          segs[2] == 'history' ||
          segs[2] == 'description' ||
          segs[2] == 'photo' ||
          segs[2] == 'type' ||
          segs[2] == 'convert' ||
          segs[2] == 'owner' ||
          segs[2] == 'qr' ||
          segs[2] == 'clear' ||
          segs[2] == 'username' ||
          segs[2] == 'about' ||
          segs[2] == 'rules' ||
          segs[2] == 'welcome' ||
          segs[2] == 'invite-expire' ||
          segs[2] == 'invite-limit' ||
          segs[2] == 'invite-revoke' ||
          segs[2] == 'topic-icon' ||
          segs[2] == 'topic-color' ||
          segs[2] == 'transfer' ||
          segs[2] == 'ownership' ||
          segs[2] == 'speaker' ||
          segs[2] == 'slow-seconds' ||
          segs[2] == 'send-photos' ||
          segs[2] == 'restrict-media' ||
          segs[2] == 'manage-topics' ||
          segs[2] == 'add-admins' ||
          segs[2] == 'post-stories' ||
          segs[2] == 'voice-chat' ||
          segs[2] == 'raise-hand' ||
          segs[2] == 'screen-share' ||
          segs[2] == 'redial' ||
          segs[2] == 'group-call' ||
          segs[2] == 'video-chat' ||
          segs[2] == 'join-voice-chat' ||
          segs[2] == 'leave-voice-chat' ||
          segs[2] == 'call' ||
          segs[2] == 'voice' ||
          segs[2] == 'audio' ||
          segs[2] == 'video' ||
          segs[2] == 'videocall') {
        return leftoverChatOpenPath(id, segs[2], query);
      }
      final mid = int.tryParse(segs[2]);
      if (mid != null && mid > 0) {
        return query.isEmpty
            ? '/chats/thread/$id?msg=$mid'
            : '/chats/thread/$id?$query&msg=$mid';
      }
    }
  }

  if ((segs[0] == 't' || segs[0] == 'g') && segs.length == 3) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) {
      if (segs[2] == 'info' || segs[2] == 'media' || segs[2] == 'log') {
        return '/chats/thread/$id/${segs[2]}$q';
      }
      if (segs[2] == 'gallery' ||
          segs[2] == 'photos' ||
          segs[2] == 'files' ||
          segs[2] == 'links') {
        return '/chats/thread/$id/media$q';
      }
      if (segs[2] == 'members' || segs[2] == 'admins') {
        return '/chats/thread/$id/info$q';
      }
      if (segs[2] == 'invite' || segs[2] == 'invite-link') {
        return '/chats/thread/$id/info$q';
      }
      if (segs[2] == 'call' || segs[2] == 'voice' || segs[2] == 'video') {
        return leftoverChatOpenPath(id, segs[2], query);
      }
      if (segs[2] == 'mute' ||
          segs[2] == 'pin' ||
          segs[2] == 'secret' ||
          segs[2] == 'search' ||
          segs[2] == 'pinned' ||
          segs[2] == 'archive' ||
          segs[2] == 'unmute' ||
          segs[2] == 'unpin' ||
          segs[2] == 'unread' ||
          segs[2] == 'ttl' ||
          segs[2] == 'theme' ||
          segs[2] == 'slowmode' ||
          segs[2] == 'slow-mode' ||
          segs[2] == 'protect' ||
          segs[2] == 'signatures' ||
          segs[2] == 'wallpaper' ||
          segs[2] == 'autodelete' ||
          segs[2] == 'color' ||
          segs[2] == 'send-as' ||
          segs[2] == 'permissions' ||
          segs[2] == 'effects' ||
          segs[2] == 'reminders' ||
          segs[2] == 'antispam' ||
          segs[2] == 'reactions' ||
          segs[2] == 'translate' ||
          segs[2] == 'seen' ||
          segs[2] == 'default-permissions' ||
          segs[2] == 'approve' ||
          segs[2] == 'join-to-send' ||
          segs[2] == 'join-to-comment' ||
          segs[2] == 'hide-members' ||
          segs[2] == 'restrict' ||
          segs[2] == 'topics' ||
          segs[2] == 'forum' ||
          segs[2] == 'discussion' ||
          segs[2] == 'linked' ||
          segs[2] == 'export' ||
          segs[2] == 'leave' ||
          segs[2] == 'report' ||
          segs[2] == 'copy-link' ||
          segs[2] == 'title' ||
          segs[2] == 'stats' ||
          segs[2] == 'history' ||
          segs[2] == 'description' ||
          segs[2] == 'photo' ||
          segs[2] == 'type' ||
          segs[2] == 'convert' ||
          segs[2] == 'owner' ||
          segs[2] == 'qr' ||
          segs[2] == 'clear' ||
          segs[2] == 'username' ||
          segs[2] == 'about' ||
          segs[2] == 'rules' ||
          segs[2] == 'welcome' ||
          segs[2] == 'invite-expire' ||
          segs[2] == 'invite-limit' ||
          segs[2] == 'invite-revoke' ||
          segs[2] == 'topic-icon' ||
          segs[2] == 'topic-color' ||
          segs[2] == 'transfer' ||
          segs[2] == 'ownership' ||
          segs[2] == 'speaker' ||
          segs[2] == 'slow-seconds' ||
          segs[2] == 'send-photos' ||
          segs[2] == 'restrict-media' ||
          segs[2] == 'manage-topics' ||
          segs[2] == 'add-admins' ||
          segs[2] == 'post-stories' ||
          segs[2] == 'voice-chat' ||
          segs[2] == 'raise-hand' ||
          segs[2] == 'screen-share' ||
          segs[2] == 'redial' ||
          segs[2] == 'group-call' ||
          segs[2] == 'video-chat' ||
          segs[2] == 'join-voice-chat' ||
          segs[2] == 'leave-voice-chat' ||
          segs[2] == 'call' ||
          segs[2] == 'voice' ||
          segs[2] == 'audio' ||
          segs[2] == 'video' ||
          segs[2] == 'videocall') {
        return leftoverChatOpenPath(id, segs[2], query);
      }
      final mid = int.tryParse(segs[2]);
      if (mid != null && mid > 0) {
        return query.isEmpty
            ? '/chats/thread/$id?msg=$mid'
            : '/chats/thread/$id?$query&msg=$mid';
      }
    }
  }
  if (segs[0] == 'f' && segs.length == 3) {
    final id = int.tryParse(segs[1]);
    if (id != null &&
        id > 0 &&
        (segs[2] == 'edit' || segs[2] == 'settings')) {
      return '/chats/folders/$id$q';
    }
  }
  if (segs[0] == 'peer' && segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '${ProfileRoute.path}?userId=$id';
  }
  if ((segs[0] == 'contact' || segs[0] == 'people') && segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '${ProfileRoute.path}?userId=$id';
  }
  if (segs[0] == 'boost' && segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/channel/$id$q';
  }
  if ((segs[0] == 'forward' || segs[0] == 'reply' || segs[0] == 'quote') &&
      segs.length == 3) {
    final cid = int.tryParse(segs[1]);
    final mid = int.tryParse(segs[2]);
    if (cid != null && cid > 0 && mid != null && mid > 0) {
      return query.isEmpty
          ? '/chats/thread/$cid?msg=$mid'
          : '/chats/thread/$cid?$query&msg=$mid';
    }
  }

  if (segs[0] == 'share' && segs.length == 3) {
    final id = int.tryParse(segs[2]);
    if (id != null && id > 0) {
      return switch (segs[1]) {
        'post' => '/post/$id$q',
        'channel' => '/channel/$id$q',
        'chat' || 'thread' || 'dm' => '/chats/thread/$id$q',
        'bot' => '/bots/$id$q',
        'user' => '${ProfileRoute.path}?userId=$id',
        'story' => '/stories/$id$q',
        'reel' => '/reel/$id$q',
        'sticker' || 'pack' => '/stickers/$id$q',
        'gift' => '${StarGiftsInventoryRoute.path}$q',
        'invoice' || 'receipt' || 'bill' => '/paid/invoices/$id$q',
        'miniapp' || 'webapp' => '/webapp/$id$q',
        'folder' => '/chats/folders/$id$q',
        'ad' || 'campaign' => '/ads/$id$q',
        'giveaway' => '/channel/$id$q',
        'startapp' || 'start-app' => '/webapp/$id$q',
        'start-bot' || 'startbot' => '/bots/$id$q',
        'contact' || 'profile' => '${ProfileRoute.path}?userId=$id',
        'media' ||
        'photo' ||
        'video' ||
        'voice' ||
        'file' ||
        'doc' ||
        'gif' ||
        'animation' ||
        'round' ||
        'poll' ||
        'quiz' ||
        'album' ||
        'comment' ||
        'location' ||
        'dice' ||
        'venue' =>
          '/post/$id$q',
        'highlight' || 'moment' => '/stories/$id$q',
        _ => null,
      };
    }
  }
  if ((segs[0] == 'call' || segs[0] == 'calls') && segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/chats/thread/$id$q';
  }
  if ((segs[0] == 'topic' || segs[0] == 'forum') && segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/chats/thread/$id$q';
  }
  if ((segs[0] == 'live' || segs[0] == 'stream') && segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/channel/$id$q';
  }
  if (segs[0] == 'saved' && segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/chats/thread/$id$q';
  }

  if (segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) {
      final short = switch (segs[0]) {
        'b' => '/bots/$id$q',
        'w' => '/webapp/$id$q',
        'd' => query.isEmpty ? '/donate?to=$id' : '/donate?to=$id&$query',
        'i' => '/paid/invoices/$id$q',
        'f' => '/chats/folders/$id$q',
        'g' || 't' || 'm' => '/chats/thread/$id$q',
        'r' => '/reel/$id$q',
        'n' => '${NotificationsRoute.path}$q',
        'l' => '/channel/$id$q',
        'a' => '/ads/$id$q',
        'v' => '/post/$id$q',
        'q' => '/post/$id$q',
        _ => null,
      };
      if (short != null) return short;
    }
  }

  if ((segs[0] == 'voicechat' ||
          segs[0] == 'voice-chat' ||
          segs[0] == 'vc' ||
          segs[0] == 'discussion' ||
          segs[0] == 'linked') &&
      segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/channel/$id$q';
  }
  if (segs[0] == 'saved-messages' && segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/chats/thread/$id$q';
  }
  if ((segs[0] == 'modlog' ||
          segs[0] == 'adminlog' ||
          segs[0] == 'moderation-log') &&
      segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/chats/thread/$id/log$q';
  }
  if (segs[0] == 'subscribers' && segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/channel/$id/subscribers$q';
  }
  if (segs[0] == 'boosts' && segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/channel/$id$q';
  }
  if ((segs[0] == 'reactions' ||
          segs[0] == 'likes' ||
          segs[0] == 'like' ||
          segs[0] == 'repost' ||
          segs[0] == 'send') &&
      segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/post/$id$q';
  }
  if (segs[0] == 'forward' && segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/post/$id$q';
  }
  if (segs[0] == 'edit' && segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/post/$id/edit$q';
  }
  if ((segs[0] == 'block' || segs[0] == 'unblock' || segs[0] == 'report') &&
      segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '${ProfileRoute.path}?userId=$id';
  }
  if ((segs[0] == 'mute' || segs[0] == 'pin' || segs[0] == 'secret') &&
      segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/chats/thread/$id$q';
  }
  if ((segs[0] == 'round' ||
          segs[0] == 'voicenote' ||
          segs[0] == 'voice-note' ||
          segs[0] == 'gif' ||
          segs[0] == 'animation') &&
      segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/post/$id$q';
  }
  if ((segs[0] == 'link' || segs[0] == 'invite-link') &&
      segs.length == 2 &&
      segs[1].isNotEmpty) {
    return '/chat-invite/${Uri.encodeComponent(segs[1])}$q';
  }
  if ((segs[0] == 'q' || segs[0] == 'quiz' || segs[0] == 'iv') &&
      segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/post/$id$q';
  }
  if ((segs[0] == 'j' || segs[0] == 'plus') &&
      segs.length == 2 &&
      segs[1].isNotEmpty) {
    return '/chat-invite/${Uri.encodeComponent(segs[1])}$q';
  }
  if ((segs[0] == 'emoji' ||
          segs[0] == 'addemoji' ||
          segs[0] == 'customemoji') &&
      segs.length == 2 &&
      segs[1].isNotEmpty) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/stickers/$id$q';
    return '/addstickers/${Uri.encodeComponent(segs[1])}$q';
  }
  if ((segs[0] == 'collectible' || segs[0] == 'unique-gift') &&
      segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '${StarGiftsInventoryRoute.path}$q';
  }
  if ((segs[0] == 'theme' || segs[0] == 'bg' || segs[0] == 'wallpaper') &&
      segs.length == 2) {
    return '${SettingsRoute.path}$q';
  }
  if ((segs[0] == 'views' ||
          segs[0] == 'forwards' ||
          segs[0] == 'reactors' ||
          segs[0] == 'tips' ||
          segs[0] == 'likers' ||
          segs[0] == 'viewers' ||
          segs[0] == 'reposts' ||
          segs[0] == 'shares' ||
          segs[0] == 'bookmarks' ||
          segs[0] == 'saves' ||
          segs[0] == 'copies' ||
          segs[0] == 'embeds') &&
      segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/post/$id$q';
  }
  if ((segs[0] == 'filter' ||
          segs[0] == 'dialogfilter' ||
          segs[0] == 'chatfolder') &&
      segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/chats/folders/$id$q';
  }
  if (segs[0] == 'folderinvite' && segs.length == 2 && segs[1].isNotEmpty) {
    return '/chat-invite/${Uri.encodeComponent(segs[1])}$q';
  }
  if ((segs[0] == 'story' || segs[0] == 'status') && segs.length == 2) {
    if (segs[1] == 'create' || segs[1] == 'new') {
      return '${StoryCreateRoute.path}$q';
    }
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/stories/$id$q';
  }
  if ((segs[0] == 'startapp' || segs[0] == 'start-app') && segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/webapp/$id$q';
  }
  if ((segs[0] == 'startbot' || segs[0] == 'start-bot') && segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/bots/$id$q';
  }
  if ((segs[0] == 'linkedchat' || segs[0] == 'linked-chat') &&
      segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/channel/$id$q';
  }
  if ((segs[0] == 'goto-msg' ||
          segs[0] == 'jump-msg' ||
          segs[0] == 'open-msg' ||
          segs[0] == 'show-msg' ||
          segs[0] == 'jump-to' ||
          segs[0] == 'open-message' ||
          segs[0] == 'jump' ||
          segs[0] == 'goto' ||
          segs[0] == 'msg-link' ||
          segs[0] == 'tme' ||
          segs[0] == 'permalink' ||
          segs[0] == 'cmsg' ||
          segs[0] == 'mid' ||
          segs[0] == 'smsg' ||
          segs[0] == 'imsg' ||
          segs[0] == 'dmsg' ||
          segs[0] == 'msgid' ||
          segs[0] == 'msglink' ||
          segs[0] == 'goto-message' ||
          segs[0] == 'open-mid' ||
          segs[0] == 'jump-mid' ||
          segs[0] == 'msg-id' ||
          segs[0] == 'message-id' ||
          segs[0] == 'show-message' ||
          segs[0] == 'tglink' ||
          segs[0] == 'deeplink' ||
          segs[0] == 'permalink-msg' ||
          segs[0] == 'jump-to-msg' ||
          segs[0] == 'show-mid' ||
          segs[0] == 'goto-mid' ||
          segs[0] == 'chatmsg' ||
          segs[0] == 'msgurl' ||
          segs[0] == 'chat-msg' ||
          segs[0] == 'open-permalink' ||
          segs[0] == 'show-permalink' ||
          segs[0] == 'jump-link' ||
          segs[0] == 'tg-msg' ||
          segs[0] == 'han-msg' ||
          segs[0] == 'deep-msg' ||
          segs[0] == 'permalink-id' ||
          segs[0] == 'open-link' ||
          segs[0] == 'tgmsg' ||
          segs[0] == 'hanmsg' ||
          segs[0] == 'deepmsg' ||
          segs[0] == 'permaid' ||
          segs[0] == 'openlnk' ||
          segs[0] == 'permaurl' ||
          segs[0] == 'msgjump' ||
          segs[0] == 'chatjump' ||
          segs[0] == 'tgjump' ||
          segs[0] == 'hanjump' ||
          segs[0] == 'deepjump' ||
          segs[0] == 'calljump' ||
          segs[0] == 'livejump' ||
          segs[0] == 'vcjump' ||
          segs[0] == 'streamjump') &&
      segs.length == 3) {
    final cid = int.tryParse(segs[1]);
    final mid = int.tryParse(segs[2]);
    if (cid != null && cid > 0 && mid != null && mid > 0) {
      return query.isEmpty
          ? '/chats/thread/$cid?msg=$mid'
          : '/chats/thread/$cid?$query&msg=$mid';
    }
  }
  if (segs.length == 3 &&
      segs[0] == 'stars' &&
      (segs[1] == 'pay' || segs[1] == 'invoice') &&
      int.tryParse(segs[2]) != null) {
    final id = int.parse(segs[2]);
    if (id > 0) return '/paid/invoices/$id$q';
  }
  if (segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) {
      final opened = switch (segs[0]) {
        'openpost' || 'open-post' => '/post/$id$q',
        'openchat' || 'open-chat' => '/chats/thread/$id$q',
        'openchannel' || 'open-channel' => '/channel/$id$q',
        'openbot' || 'open-bot' => '/bots/$id$q',
        'openuser' || 'open-user' => '${ProfileRoute.path}?userId=$id',
        'openstory' || 'open-story' => '/stories/$id$q',
        'openreel' || 'open-reel' => '/reel/$id$q',
        'react' || 'view' => '/post/$id$q',
        'unique' || 'nft' => '${StarGiftsInventoryRoute.path}$q',
        'open-media' ||
        'open-file' ||
        'open-voice' ||
        'open-photo' ||
        'open-video' ||
        'open-doc' ||
        'view-post' ||
        'show-post' ||
        'goto-post' ||
        'postid' =>
          '/post/$id$q',
        'goto-chat' || 'show-chat' || 'chatid' => '/chats/thread/$id$q',
        'goto-channel' || 'show-channel' || 'channelid' => '/channel/$id$q',
        'goto-user' ||
        'show-user' ||
        'userid' ||
        'uid' ||
        'add-user' =>
          '${ProfileRoute.path}?userId=$id',
        'goto-bot' || 'add-bot' || 'botid' => '/bots/$id$q',
        'goto-story' || 'storyid' => '/stories/$id$q',
        'packid' => '/stickers/$id$q',
        'giftid' => '${StarGiftsInventoryRoute.path}$q',
        'invid' => '/paid/invoices/$id$q',
        'folderid' => '/chats/folders/$id$q',
        'appid' => '/webapp/$id$q',
        'adid' => '/ads/$id$q',
        'show-media' ||
        'show-file' ||
        'show-voice' ||
        'show-photo' ||
        'show-video' ||
        'show-doc' ||
        'post-id' =>
          '/post/$id$q',
        'peerid' ||
        'convid' ||
        'dialogid' ||
        'threadid' ||
        'chat-id' =>
          '/chats/thread/$id$q',
        'chanid' || 'channel-id' => '/channel/$id$q',
        'reelid' => '/reel/$id$q',
        'bot-id' => '/bots/$id$q',
        'app-id' => '/webapp/$id$q',
        'ad-id' => '/ads/$id$q',
        'gift-id' => '${StarGiftsInventoryRoute.path}$q',
        'pack-id' => '/stickers/$id$q',
        'folder-id' => '/chats/folders/$id$q',
        'inv-id' => '/paid/invoices/$id$q',
        'story-id' => '/stories/$id$q',
        'user-id' => '${ProfileRoute.path}?userId=$id',
        'media-id' ||
        'photo-id' ||
        'video-id' ||
        'file-id' ||
        'voice-id' ||
        'doc-id' ||
        'sticker-id' =>
          '/post/$id$q',
        'edit-bot' || 'bot-settings' => '/bots/$id$q',
        'launch-app' || 'start-webapp' => '/webapp/$id$q',
        'mediaid' ||
        'photoid' ||
        'videoid' ||
        'fileid' ||
        'voiceid' ||
        'docid' ||
        'stickerid' =>
          '/post/$id$q',
        'cid' => '/chats/thread/$id$q',
        'pid' => '/post/$id$q',
        'bid' => '/bots/$id$q',
        'wid' => '/webapp/$id$q',
        'sid' => '/stories/$id$q',
        'aid' => '/ads/$id$q',
        'gid' => '/chats/thread/$id$q',
        'tid' => '/chats/thread/$id$q',
        'fid' => '/chats/folders/$id$q',
        'eid' => '/stickers/$id$q',
        'rid' => '/reel/$id$q',
        'hid' => '/stories/$id$q',
        'qid' => '/post/$id$q',
        'highlightid' || 'momentid' => '/stories/$id$q',
        'webappid' || 'miniappid' => '/webapp/$id$q',
        'invoiceid' => '/paid/invoices/$id$q',
        'campaignid' => '/ads/$id$q',
        'giveawayid' => '/channel/$id$q',
        'topicid' => '/chats/thread/$id$q',
        'reel-id' => '/reel/$id$q',
        'highlight-id' || 'moment-id' => '/stories/$id$q',
        'web-app-id' || 'mini-app-id' => '/webapp/$id$q',
        'invoice-id' => '/paid/invoices/$id$q',
        'campaign-id' => '/ads/$id$q',
        'giveaway-id' => '/channel/$id$q',
        'topic-id' => '/chats/thread/$id$q',
        'boost-id' => '/channel/$id$q',
        'convo-id' => '/chats/thread/$id$q',
        'pack-set' => '/stickers/$id$q',
        'custom-emoji-id' => '/stickers/$id$q',
        'unique-id' || 'collectible-id' => '${StarGiftsInventoryRoute.path}$q',
        'boostid' => '/channel/$id$q',
        'storylink' => '/stories/$id$q',
        'packset' => '/stickers/$id$q',
        'emojiid' => '/stickers/$id$q',
        'uniqueid' || 'collectibleid' => '${StarGiftsInventoryRoute.path}$q',
        'storylnk' => '/stories/$id$q',
        'boostlnk' => '/channel/$id$q',
        'stickersetid' || 'emojisetid' => '/stickers/$id$q',
        'statusid' => '/stories/$id$q',
        'callid' => pathWithCallQuery('/chats/thread/$id', 'voice', query),
        'inviteid' => '/chats/thread/$id$q',
        'adminid' || 'memberid' || 'ownerid' => '${ProfileRoute.path}?userId=$id',
        'topiclnk' => '/chats/thread/$id$q',
        'invite-lnk' => '/chats/thread/$id$q',
        'liveid' || 'vcid' || 'call-id' || 'vc-id' =>
          pathWithCallQuery('/chats/thread/$id', 'voice', query),
        'speakerid' => pathWithCallQuery('/chats/thread/$id', 'voice', query),
        'livestreamid' || 'rtmpid' || 'groupcallid' =>
          pathWithCallQuery('/chats/thread/$id', 'voice', query),
        _ => null,
      };
      if (opened != null) return opened;
    }
  }

  return null;
}

/// `/bots/:id/commands` and sibling BotFather paths.
String? botSectionPathAlias(String path, [String query = '']) {
  final clean = path.split('?').first;
  final segs = clean.split('/').where((s) => s.isNotEmpty).toList();
  if (segs.length != 3 ||
      (segs[0] != 'bots' && segs[0] != 'bot' && segs[0] != 'b')) {
    return null;
  }
  final id = int.tryParse(segs[1]);
  if (id == null || id <= 0) return null;
  final extra = query.trim();
  String withExtra(String dest) {
    if (extra.isEmpty) return dest;
    return dest.contains('?') ? '$dest&$extra' : '$dest?$extra';
  }

  return switch (segs[2]) {
    'commands' || 'command' => withExtra('/bots/$id/commands'),
    'apps' || 'miniapps' || 'mini-apps' => withExtra('/bots/$id/apps'),
    'newapp' || 'new-app' => extra.isEmpty
        ? '/bots/$id/apps?new=1'
        : '/bots/$id/apps?new=1&$extra',
    'token' => extra.isEmpty
        ? '/bots/$id?section=token'
        : '/bots/$id?$extra&section=token',
    'webhook' ||
    'webhooks' ||
    'invoices' ||
    'invoice' ||
    'stats' ||
    'analytics' ||
    'description' ||
    'about' ||
    'payments' ||
    'privacy' ||
    'username' ||
    'name' ||
    'avatar' ||
    'language' ||
    'users' ||
    'group' ||
    'affiliate' ||
    'privacy-policy' ||
    'tos' =>
      withExtra('/bots/$id'),
    _ => null,
  };
}

/// Short leftover paths people type from Telegram muscle memory.
String? shortcutPathAlias(String path, [String query = '']) {
  final clean = path.split('?').first;
  final q = query.isEmpty ? '' : '?$query';
  switch (clean) {
    case '/stars':
    case '/wallet':
      return '${StarsWalletRoute.path}$q';
    case '/gifts':
      return '${StarGiftsInventoryRoute.path}$q';
    case '/premium':
      return '${FlexSubscriptionRoute.path}$q';
    case '/referral':
    case '/partner':
      return '${PartnerProgramRoute.path}$q';
    case '/bots':
      return '${MyBotsRoute.path}$q';
    case '/security':
    case '/settings/security':
    case '/settings/sessions':
      return '${AccountSecurityRoute.path}$q';
    case '/settings/privacy':
      return '${SettingsRoute.path}$q';
    case '/blocked':
      return '${BlockedUsersRoute.path}$q';
    case '/saved':
      return '${ProfileTabRoute.path}$q';
    case '/extra-ads':
      return '${ExtraAdsRoute.path}$q';
    case '/creator':
      return '${CreatorToolsRoute.path}$q';
    case '/scheduled':
      return '${ScheduledPostsRoute.path}$q';
    case '/promoted':
      return '${PromotedPostsRoute.path}$q';
    case '/payouts':
    case '/revenue':
      return '${CreatorRevenueRoute.path}$q';
    case '/2fa':
      return '${TwoFactorSetupRoute.path}$q';
    case '/edit-profile':
    case '/profile/edit':
    case '/me/edit':
      return '${ProfileAuthRoute.path}$q';
    case '/privacy':
      return '${SettingsRoute.path}$q';
    case '/groups':
      return '${ChatsRoute.path}$q';
    case '/archive':
    case '/archived':
      return '${ChatArchivedRoute.path}$q';
    case '/new-group':
      return '${ChatCreateGroupRoute.path}$q';
    case '/new-message':
    case '/people':
    case '/contacts':
      return '${ChatNewMessageRoute.path}$q';
    case '/new-channel':
      return '${CreateChannelRoute.path}$q';
    case '/new-post':
      return '${CreatePostRoute.path}$q';
    case '/new-reel':
      return '${CreateReelRoute.path}$q';
    case '/new-story':
      return '${StoryCreateRoute.path}$q';
    case '/moments':
      return '${StoriesRoute.path}$q';
    case '/constructor':
      return '${FlexConstructorRoute.path}$q';
    case '/shop':
      return '${FlexShopRoute.path}$q';
    case '/admin':
      return '${ModerationDashboardRoute.path}$q';
    case '/help':
    case '/faq':
    case '/tickets':
      return '${SupportContactRoute.path}$q';
    case '/about':
    case '/legal':
    case '/terms':
      return '${SupportSecurityRoute.path}$q';
    case '/inbox':
      return '${NotificationsRoute.path}$q';
    case '/messages':
    case '/dm':
      return '${ChatsRoute.path}$q';
    case '/theme':
    case '/appearance':
      return '${SettingsRoute.path}$q';
    case '/compose':
    case '/write':
      return '${CreatePostRoute.path}$q';
    case '/camera':
      return '${StoryCreateRoute.path}$q';
    case '/folders':
    case '/new-folder':
      return '${ChatFolderNewRoute.path}$q';
    case '/sessions':
    case '/devices':
      return '${AccountSecurityRoute.path}$q';
    case '/language':
    case '/lang':
    case '/data':
    case '/storage':
    case '/themes':
    case '/night':
    case '/proxy':
      return '${SettingsRoute.path}$q';
    case '/saved-messages':
      return '${ProfileTabRoute.path}$q';
    case '/calls':
    case '/stickers':
      return '${ChatsRoute.path}$q';
    case '/blocklist':
      return '${BlockedUsersRoute.path}$q';
    case '/notification-settings':
    case '/notif-settings':
      return '${NotificationSettingsRoute.path}$q';
    case '/export':
      return '${BackupRoute.path}$q';
    case '/marketplace':
      return '${StarGiftsMarketplaceRoute.path}$q';
    case '/qr':
    case '/scan':
      return '${ProfileTabRoute.path}$q';
    case '/gif':
    case '/emoji':
      return '${ChatsRoute.path}$q';
    case '/webapp':
    case '/miniapp':
      return '${MiniAppsRoute.path}$q';
    case '/privacy-policy':
    case '/tos':
    case '/cookies':
      return '${SupportSecurityRoute.path}$q';
    case '/settings/language':
    case '/settings/data':
    case '/settings/storage':
      return '${SettingsRoute.path}$q';
    case '/stats':
    case '/insights':
      return '${AppAnalyticsRoute.path}$q';
    case '/bookmarks':
    case '/likes':
    case '/saved-posts':
      return '${SavedPostsRoute.path}$q';
    case '/mentions':
    case '/activity':
      return '${NotificationsRoute.path}$q';
    case '/settings/backup':
      return '${BackupRoute.path}$q';
    case '/settings/2fa':
      return '${TwoFactorSetupRoute.path}$q';
    case '/settings/devices':
      return '${AccountSecurityRoute.path}$q';
    case '/download':
    case '/licenses':
    case '/changelog':
    case '/version':
      return '${SupportSecurityRoute.path}$q';
    case '/wallpaper':
    case '/autodelete':
    case '/chat-settings':
    case '/data-and-storage':
      return '${SettingsRoute.path}$q';
    case '/giveaway':
    case '/giveaways':
    case '/boost':
      return '${AdsHubRoute.path}$q';
    case '/botfather':
    case '/newbot':
      return '${MyBotsRoute.path}$q';
    case '/gifts/market':
    case '/gifts/shop':
      return '${StarGiftsMarketplaceRoute.path}$q';
    case '/secret':
    case '/passcode':
    case '/passport':
      return '${AccountSecurityRoute.path}$q';
    case '/poll':
    case '/quiz':
      return '${CreatePostRoute.path}$q';
    case '/nearby':
      return '${ChatsRoute.path}$q';
    case '/home':
    case '/explore':
    case '/discover':
    case '/start':
    case '/welcome':
    case '/for-you':
    case '/foryou':
    case '/following':
    case '/subs':
    case '/subscriptions':
      return '${FeedRoute.path}$q';
    case '/signin':
    case '/sign-in':
      return '${LoginRoute.path}$q';
    case '/signup':
    case '/sign-up':
      return '${RegisterRoute.path}$q';
    case '/contact':
    case '/feedback':
    case '/report':
    case '/whats-new':
    case '/tips':
    case '/guide':
    case '/howto':
      return '${SupportContactRoute.path}$q';
    case '/monetization':
    case '/earn':
    case '/studio':
    case '/tools':
    case '/dashboard':
    case '/suggested':
    case '/suggest':
      return '${CreatorToolsRoute.path}$q';
    case '/billing':
    case '/pay':
    case '/pricing':
    case '/plans':
    case '/business':
      return '${FlexSubscriptionRoute.path}$q';
    case '/ai':
      return FlexSubscriptionRoute.pathWithLevel(9);
    case '/pro':
      return FlexSubscriptionRoute.pathWithLevel(18);
    case '/max':
      return FlexSubscriptionRoute.pathWithLevel(79);
    case '/advertiser':
    case '/advertising':
    case '/campaigns':
    case '/ads-hub':
      return '${AdsHubRoute.path}$q';
    case '/queue':
    case '/review':
      return '${ModerationQueueRoute.path}$q';
    case '/refunds':
      return '${AdminRefundQueueRoute.path}$q';
    case '/affiliate':
      return '${PartnerProgramRoute.path}$q';
    case '/collectibles':
    case '/nft':
      return '${StarGiftsMarketplaceRoute.path}$q';
    case '/tip':
      return '${StarsWalletRoute.path}$q';
    case '/features':
    case '/compare':
      return '${FlexConstructorRoute.path}$q';
    case '/publish':
    case '/upload':
      return '${CreatePostRoute.path}$q';
    case '/import':
    case '/restore':
      return '${BackupRoute.path}$q';
    case '/gdpr':
    case '/settings/about':
      return '${SupportSecurityRoute.path}$q';
    case '/last-seen':
    case '/install':
    case '/pwa':
      return '${SettingsRoute.path}$q';
    case '/exceptions':
      return '${PaidMessageExceptionsRoute.path}$q';
    case '/add-contact':
    case '/new-contact':
      return '${ChatNewMessageRoute.path}$q';
    case '/invite-friends':
    case '/share-app':
      return '${PartnerProgramRoute.path}$q';
    case '/qr-login':
    case '/link-device':
    case '/active-sessions':
    case '/connected':
      return '${AccountSecurityRoute.path}$q';
    case '/two-step':
    case '/cloud-password':
    case '/recovery':
      return '${TwoFactorSetupRoute.path}$q';
    case '/email':
    case '/phone':
    case '/change-email':
      return '${ProfileAuthRoute.path}$q';
    case '/highlights':
    case '/stories/archive':
      return '${StoriesRoute.path}$q';
    case '/catalog':
    case '/directory':
    case '/muted':
    case '/topics':
    case '/topic':
    case '/forum':
      return '${ChatsRoute.path}$q';
    case '/find':
    case '/global':
    case '/hashtag':
      return '${SearchRoute.path}$q';
    case '/drafts':
      return '${ScheduledPostsRoute.path}$q';
    case '/comments':
      return '${NotificationsRoute.path}$q';
    case '/bot':
    case '/newapp':
      return '${MyBotsRoute.path}$q';
    case '/settings/flex':
      return '${FlexSubscriptionRoute.path}$q';
    case '/settings/wallet':
      return '${StarsWalletRoute.path}$q';
    case '/settings/bots':
      return '${MyBotsRoute.path}$q';
    case '/settings/ads':
      return '${AdsHubRoute.path}$q';
    case '/settings/creator':
      return '${CreatorToolsRoute.path}$q';
    case '/miniapps':
    case '/webapps':
    case '/apps':
    case '/games':
    case '/twa':
      return '${MiniAppsRoute.path}$q';
    case '/my-bots':
    case '/create-bot':
    case '/new-bot':
    case '/developers':
    case '/botapi':
      return '${MyBotsRoute.path}$q';
    case '/my-channels':
    case '/manage-channels':
      return '${ChannelsManagementRoute.path}$q';
    case '/my-profile':
      return '${ProfileTabRoute.path}$q';
    case '/account':
    case '/settings/account':
    case '/settings/profile':
    case '/settings/username':
    case '/username':
    case '/bio':
    case '/avatar':
      return '${ProfileAuthRoute.path}$q';
    case '/settings/close-friends':
    case '/best-friends':
    case '/besties':
    case '/story-privacy':
    case '/close-friend':
      return '${CloseFriendsRoute.path}$q';
    case '/change-password':
    case '/password':
    case '/settings/password':
    case '/privacy-and-security':
    case '/secret-chat':
      return '${AccountSecurityRoute.path}$q';
    case '/forgot':
      return '${ForgotPasswordRoute.path}$q';
    case '/subscribe':
    case '/upgrade':
    case '/plus':
    case '/vip':
    case '/manage-subscription':
    case '/my-subscription':
    case '/flex-plus':
      return '${FlexSubscriptionRoute.path}$q';
    case '/flex-ai':
      return FlexSubscriptionRoute.pathWithLevel(9);
    case '/flex-pro':
      return FlexSubscriptionRoute.pathWithLevel(18);
    case '/flex-max':
      return FlexSubscriptionRoute.pathWithLevel(79);
    case '/balance':
    case '/buy-stars':
    case '/get-stars':
    case '/star-balance':
      return '${StarsWalletRoute.path}$q';
    case '/my-gifts':
    case '/saved-gifts':
      return '${StarGiftsInventoryRoute.path}$q';
    case '/gift-shop':
      return '${StarGiftsMarketplaceRoute.path}$q';
    case '/earnings':
    case '/withdraw':
    case '/payout':
    case '/sbp':
      return '${CreatorRevenueRoute.path}$q';
    case '/referrals':
    case '/share':
    case '/refer':
    case '/partners':
    case '/invite-link':
      return '${PartnerProgramRoute.path}$q';
    case '/alerts':
    case '/updates':
      return '${NotificationsRoute.path}$q';
    case '/create':
    case '/add-post':
      return '${CreatePostRoute.path}$q';
    case '/add-story':
    case '/create-story':
      return '${StoryCreateRoute.path}$q';
    case '/create-group':
      return '${ChatCreateGroupRoute.path}$q';
    case '/create-channel':
      return '${CreateChannelRoute.path}$q';
    case '/new-chat':
    case '/start-chat':
    case '/write-message':
      return '${ChatNewMessageRoute.path}$q';
    case '/policy':
    case '/eula':
    case '/safety':
    case '/legal-info':
    case '/imprint':
      return '${SupportSecurityRoute.path}$q';
    case '/bug':
    case '/ticket':
    case '/bug-report':
    case '/customer-service':
      return '${SupportContactRoute.path}$q';
    case '/blacklist':
    case '/blocked-users':
    case '/black-list':
    case '/block-list':
      return '${BlockedUsersRoute.path}$q';
    case '/night-mode':
    case '/dark':
    case '/auto-download':
    case '/data-saver':
    case '/settings/chats':
      return '${SettingsRoute.path}$q';
    case '/two-factor':
    case '/authenticator':
      return '${TwoFactorSetupRoute.path}$q';
    case '/admin-panel':
    case '/staff':
      return '${ModerationDashboardRoute.path}$q';
    case '/collections':
    case '/liked':
    case '/later':
    case '/watch-later':
      return '${SavedPostsRoute.path}$q';
    case '/schedule':
    case '/scheduled-posts':
      return '${ScheduledPostsRoute.path}$q';
    case '/promote':
      return '${PromotedPostsRoute.path}$q';
    case '/ads-manager':
      return '${AdsHubRoute.path}$q';
    case '/monetize':
      return '${CreatorToolsRoute.path}$q';
    case '/more-ads':
      return '${ExtraAdsRoute.path}$q';
    case '/store':
    case '/packs':
      return '${FlexShopRoute.path}$q';
    case '/levels':
      return '${FlexConstructorRoute.path}$q';
    case '/chat-folders':
    case '/settings/folders':
      return '${ChatFolderNewRoute.path}$q';
    case '/archived-chats':
      return '${ChatArchivedRoute.path}$q';
    case '/paid-messages':
      return '${PaidMessageExceptionsRoute.path}$q';
    case '/do-not-disturb':
    case '/dnd':
      return '${NotificationSettingsRoute.path}$q';
    case '/trending':
    case '/popular':
      return '${FeedRoute.path}$q';
    case '/export-data':
    case '/takeout':
      return '${BackupRoute.path}$q';
    case '/metrics':
    case '/statistics':
      return '${AppAnalyticsRoute.path}$q';
    case '/search-people':
    case '/hashtags':
      return '${SearchRoute.path}$q';
    case '/settings/stickers':
    case '/settings/calls':
      return '${ChatsRoute.path}$q';
    case '/my-stars':
    case '/stars-wallet':
    case '/wallet-stars':
      return '${StarsWalletRoute.path}$q';
    case '/flex-shop':
      return '${FlexShopRoute.path}$q';
    case '/flex-constructor':
      return '${FlexConstructorRoute.path}$q';
    case '/join-group':
      return '${ChatCreateGroupRoute.path}$q';
    case '/star-gifts':
      return '${StarGiftsInventoryRoute.path}$q';
    case '/invoice':
    case '/invoices':
      return '${StarsWalletRoute.path}$q';
    case '/join':
    case '/join-chat':
    case '/joinchat':
      return '${ChatsRoute.path}$q';
    case '/new-ad':
    case '/create-ad':
    case '/order-ad':
      return '${AdsCampaignEditorRoute.path}$q';
    case '/add-sticker':
    case '/new-sticker':
      return '${ChatsRoute.path}$q';
    case '/direct':
    case '/direct/inbox':
    case '/im':
    case '/msg':
    case '/message':
    case '/thread':
    case '/convo':
    case '/private':
    case '/messenger':
      return '${ChatsRoute.path}$q';
    case '/me':
      return '${ProfileTabRoute.path}$q';
    case '/dialog':
    case '/dialogs':
    case '/dialogues':
    case '/all-chats':
    case '/my-groups':
    case '/supergroups':
    case '/saved-chats':
    case '/recent-chats':
      return '${ChatsRoute.path}$q';
    case '/channel':
    case '/broadcast':
      return '${ChannelsManagementRoute.path}$q';
    case '/new-dm':
    case '/new-dialog':
      return '${ChatNewMessageRoute.path}$q';
    case '/privacy/last-seen':
    case '/privacy/calls':
    case '/privacy/groups':
    case '/privacy/forwards':
    case '/privacy/photo':
    case '/privacy/phone':
    case '/privacy/bio':
    case '/privacy/messages':
      return '${SettingsRoute.path}$q';
    case '/settings/notif':
    case '/notif':
    case '/notification':
      return '${NotificationSettingsRoute.path}$q';
    case '/go':
    case '/open':
    case '/call':
      return '${ChatsRoute.path}$q';
    case '/location':
    case '/live-location':
      return '${ChatsRoute.path}$q';
    case '/live':
    case '/stream':
      return '${ChannelsManagementRoute.path}$q';
    case '/privacy/blocked':
    case '/settings/block':
    case '/settings/blocklist':
    case '/settings/privacy/blocked':
      return '${BlockedUsersRoute.path}$q';
    case '/privacy/profile':
    case '/privacy/birthday':
    case '/privacy/voice':
    case '/privacy/status':
    case '/privacy/online':
    case '/privacy/gifts':
    case '/privacy/lastseen':
    case '/settings/privacy/last-seen':
    case '/settings/appearance':
    case '/settings/theme':
    case '/settings/night':
    case '/settings/wallpaper':
    case '/settings/autodelete':
      return '${SettingsRoute.path}$q';
    case '/extraads':
    case '/extra_ads':
      return '${ExtraAdsRoute.path}$q';
    case '/voice-chats':
    case '/voicechats':
    case '/discussion':
    case '/linked-chat':
      return '${ChatsRoute.path}$q';
    case '/ads-review':
    case '/mod-ads':
      return '${AdsReviewRoute.path}$q';
    case '/admin-tickets':
    case '/support-admin':
      return '${AdminSupportTicketsRoute.path}$q';
    case '/partner-payouts':
      return '${AdminPartnerPayoutsRoute.path}$q';
    case '/creator-payouts':
      return '${AdminCreatorPayoutsRoute.path}$q';
    case '/flex-features':
    case '/flex-admin':
      return '${AdminFlexFeaturesRoute.path}$q';
    case '/saved-stories':
    case '/story-archive':
    case '/my-moments':
      return '${StoriesRoute.path}$q';
    case '/log-in':
      return '${LoginRoute.path}$q';
    case '/setlanguage':
    case '/setemoji':
    case '/bg':
      return '${SettingsRoute.path}$q';
    case '/settings/privacy/calls':
    case '/settings/privacy/groups':
    case '/settings/privacy/forwards':
    case '/settings/privacy/phone':
    case '/settings/privacy/photo':
    case '/settings/privacy/bio':
    case '/settings/privacy/messages':
    case '/privacy/invites':
    case '/privacy/p2p':
    case '/privacy/voice-calls':
    case '/privacy/channels':
    case '/read-receipts':
    case '/typing':
    case '/typing-status':
    case '/hide-read':
      return '${SettingsRoute.path}$q';
    case '/autolock':
    case '/passkey':
    case '/passkeys':
    case '/biometric':
    case '/screen-lock':
      return '${AccountSecurityRoute.path}$q';
    case '/ton':
      return '${StarsWalletRoute.path}$q';
    case '/crypto':
    case '/fragment':
    case '/nft-usernames':
      return '${StarGiftsMarketplaceRoute.path}$q';
    case '/newmessage':
    case '/addcontact':
      return '${ChatNewMessageRoute.path}$q';
    case '/savedmessages':
      return '${ProfileTabRoute.path}$q';
    case '/addstickers':
      return '${ChatsRoute.path}$q';
    case '/username-auction':
      return '${ProfileAuthRoute.path}$q';
    case '/newgroup':
      return '${ChatCreateGroupRoute.path}$q';
    case '/newchannel':
      return '${CreateChannelRoute.path}$q';
    case '/newchat':
      return '${ChatNewMessageRoute.path}$q';
    case '/newpost':
    case '/create-recipe':
      return '${CreatePostRoute.path}$q';
    case '/newstory':
      return '${StoryCreateRoute.path}$q';
    case '/newreel':
      return '${CreateReelRoute.path}$q';
    case '/confirm-email':
      return '${VerifyEmailRoute.path}$q';
    case '/login-code':
      return '${LoginRoute.path}$q';
    case '/reset-pass':
    case '/forgot-pass':
    case '/recover-password':
      return '${ForgotPasswordRoute.path}$q';
    case '/twofa':
    case '/2step':
    case '/activesessions':
      return '${AccountSecurityRoute.path}$q';
    case '/setusername':
    case '/setbio':
    case '/setphoto':
    case '/changenumber':
    case '/myqr':
    case '/shareqr':
      return '${ProfileAuthRoute.path}$q';
    case '/lite-mode':
    case '/power-saving':
    case '/animations':
    case '/text-size':
    case '/large-emoji':
    case '/translate':
    case '/autotranslate':
    case '/socks':
    case '/mtproxy':
    case '/proxy-settings':
    case '/settings/privacy/online':
    case '/settings/privacy/voice':
    case '/settings/privacy/gifts':
    case '/privacy/phone-number':
    case '/privacy/added-by-phone':
    case '/privacy/voice-messages':
    case '/people-nearby':
    case '/emoji-status':
    case '/profile-color':
      return '${SettingsRoute.path}$q';
    case '/success':
      return '${SubscriptionSuccessRoute.path}$q';
    case '/cancel':
      return '${SubscriptionCancelRoute.path}$q';
    case '/checkout':
      return '${FlexSubscriptionRoute.path}$q';
    case '/paid-success':
      return '${StarsCheckoutSuccessRoute.path}$q';
    case '/paid-cancel':
      return '${StarsCheckoutCancelRoute.path}$q';
    case '/buy':
    case '/topup':
    case '/deposit':
      return '${StarsWalletRoute.path}$q';
    case '/ref':
    case '/refs':
    case '/promo':
    case '/shareurl':
      return '${PartnerProgramRoute.path}$q';
    case '/helpdesk':
      return '${SupportContactRoute.path}$q';
    case '/nightmode':
    case '/darkmode':
    case '/lightmode':
      return '${SettingsRoute.path}$q';
    case '/chatlist':
    case '/chat-list':
      return '${ChatsRoute.path}$q';
    case '/newfolder':
    case '/addfolder':
      return '${ChatFolderNewRoute.path}$q';
    case '/consent':
    case '/gdpr-consent':
      return '${LegalConsentRoute.path}$q';
    case '/otp':
      return '${LoginRoute.path}$q';
    case '/changeemail':
    case '/email-change':
      return '${ProfileAuthRoute.path}$q';
    case '/mygifts':
      return '${StarGiftsInventoryRoute.path}$q';
    case '/mybots':
      return '${MyBotsRoute.path}$q';
    case '/mychannels':
      return '${ChannelsManagementRoute.path}$q';
    case '/mystars':
      return '${StarsWalletRoute.path}$q';
    case '/closefriends':
      return '${CloseFriendsRoute.path}$q';
    case '/editprofile':
      return '${ProfileAuthRoute.path}$q';
    case '/notifsettings':
      return '${NotificationSettingsRoute.path}$q';
    case '/flexplus':
      return '${FlexSubscriptionRoute.path}$q';
    case '/tg':
    case '/telegram':
      return '${ChatsRoute.path}$q';
    case '/startapp':
    case '/attachmenu':
      return '${MiniAppsRoute.path}$q';
    case '/status':
    case '/story':
      return '${StoriesRoute.path}$q';
    case '/mtproto':
    case '/terms-of-service':
    case '/user-agreement':
    case '/refund-policy':
    case '/cookie-policy':
    case '/community-guidelines':
    case '/safety-center':
    case '/about-app':
    case '/build':
    case '/ads-policy':
      return '${SupportSecurityRoute.path}$q';
    case '/report-abuse':
    case '/report-spam':
    case '/appeal':
    case '/helpdesk-chat':
      return '${SupportContactRoute.path}$q';
    case '/payout-settings':
    case '/creator-fund':
      return '${CreatorRevenueRoute.path}$q';
    case '/billing-history':
    case '/cancel-sub':
    case '/restore-purchase':
    case '/subscription-manage':
    case '/gift-premium':
    case '/gift-flex':
      return '${FlexSubscriptionRoute.path}$q';
    case '/send-stars':
    case '/give-stars':
    case '/tip-jar':
      return '${StarsWalletRoute.path}$q';
    case '/calllog':
    case '/recentcalls':
    case '/voicemessages':
    case '/secretchats':
    case '/broadcasts':
    case '/imbox':
    case '/savedmsg':
      return '${ChatsRoute.path}$q';
    case '/verify-account':
    case '/business-verify':
      return '${ProfileAuthRoute.path}$q';
    case '/call-log':
    case '/recent-calls':
    case '/secret-chats':
    case '/saved-msg':
    case '/im-box':
    case '/msgbox':
    case '/voice-messages':
      return '${ChatsRoute.path}$q';
    case '/terms-of-use':
    case '/tos-page':
    case '/refunds-policy':
    case '/child-safety':
    case '/copyright-policy':
    case '/copyright':
    case '/dmca':
      return '${SupportSecurityRoute.path}$q';
    case '/ban-appeal':
    case '/unban':
    case '/appeal-ban':
    case '/abuse':
    case '/spam':
      return '${SupportContactRoute.path}$q';
    case '/kyc':
    case '/verify-kyc':
    case '/change-phone':
    case '/change-username':
    case '/set-name':
    case '/my-username':
      return '${ProfileAuthRoute.path}$q';
    case '/invoice-history':
    case '/receipts':
    case '/gift-stars':
      return '${StarsWalletRoute.path}$q';
    case '/start-bot':
      return '${MyBotsRoute.path}$q';
    case '/write-post':
      return '${CreatePostRoute.path}$q';
    case '/promo-code':
      return '${PartnerProgramRoute.path}$q';
    case '/mtproto-proxy':
    case '/socks5':
    case '/settings/advanced':
    case '/advanced':
    case '/settings/chat':
    case '/battery-saver':
    case '/low-data':
    case '/offline-mode':
      return '${SettingsRoute.path}$q';
    case '/authorizations':
    case '/logged-in':
    case '/devices-other':
    case '/passcode-lock':
    case '/login-qr':
      return '${AccountSecurityRoute.path}$q';
    case '/email-verify':
      return '${VerifyEmailRoute.path}$q';
    case '/restore-account':
    case '/recover-account':
      return '${ForgotPasswordRoute.path}$q';
    case '/call-history':
    case '/missed-calls':
    case '/incoming-calls':
    case '/outgoing-calls':
    case '/shared-media':
    case '/media-gallery':
    case '/chat-info':
    case '/group-info':
    case '/sticker-store':
    case '/gif-store':
    case '/tenor':
    case '/giphy':
    case '/emoji-pack':
    case '/join-requests':
    case '/admin-log':
    case '/event-log':
    case '/recent-actions':
    case '/requests':
      return '${ChatsRoute.path}$q';
    case '/chat-archive':
    case '/hidden-chats':
    case '/spam-folder':
    case '/archive-settings':
      return '${ChatArchivedRoute.path}$q';
    case '/qr-code':
    case '/scan-qr':
    case '/user-info':
    case '/notes':
    case '/self-chat':
    case '/me-chat':
      return '${ProfileTabRoute.path}$q';
    case '/clear-cache':
    case '/data-usage':
    case '/lite':
    case '/auto-night':
    case '/self-destruct':
    case '/disappearing':
    case '/ttl':
    case '/peer-to-peer':
    case '/sensitive':
    case '/autoplay':
    case '/add-proxy':
    case '/socks-proxy':
    case '/connection':
    case '/who-can-call':
    case '/hide-phone':
    case '/privacy-lastseen':
    case '/sync':
    case '/switch-account':
    case '/add-account':
      return '${SettingsRoute.path}$q';
    case '/download-data':
    case '/export-contacts':
    case '/cloud-backup':
    case '/chat-backup':
      return '${BackupRoute.path}$q';
    case '/send-gift':
    case '/transfer-gift':
      return '${StarGiftsInventoryRoute.path}$q';
    case '/edit-post':
      return '${CreatePostRoute.path}$q';
    case '/view-story':
    case '/story-view':
      return '${StoriesRoute.path}$q';
    case '/join-channel':
      return '${ChannelsManagementRoute.path}$q';
    case '/add-bot':
      return '${MyBotsRoute.path}$q';
    case '/add-channel':
      return '${CreateChannelRoute.path}$q';
    case '/add-group':
      return '${ChatCreateGroupRoute.path}$q';
    case '/add-user':
    case '/sync-contacts':
    case '/import-contacts':
      return '${ChatNewMessageRoute.path}$q';
    case '/cashout':
    case '/creator-payout':
    case '/tax-id':
    case '/inn':
    case '/self-employed':
    case '/requisites':
      return '${CreatorRevenueRoute.path}$q';
    case '/redeem':
    case '/gift-code':
    case '/ton-space':
    case '/stars-invoice':
    case '/pay-invoice':
    case '/invoice-pay':
      return '${StarsWalletRoute.path}$q';
    case '/authorized-apps':
    case '/freeze':
    case '/unfreeze':
    case '/encryption':
    case '/secret-key':
      return '${AccountSecurityRoute.path}$q';
    case '/scheduled-messages':
      return '${ScheduledPostsRoute.path}$q';
    case '/change-name':
    case '/my-phone':
    case '/my-email':
    case '/verified':
      return '${ProfileAuthRoute.path}$q';
    case '/fragment-username':
    case '/collectible-username':
    case '/nft-username':
    case '/username-buy':
    case '/auction':
      return '${StarGiftsMarketplaceRoute.path}$q';
    case '/boost-channel':
    case '/giveaway-create':
    case '/ads-balance':
    case '/ad-wallet':
      return '${AdsHubRoute.path}$q';
    case '/suggested-post':
    case '/paid-post':
    case '/paid-media':
      return '${CreatorToolsRoute.path}$q';
    case '/partner-payout':
    case '/promo-link':
    case '/ref-link':
    case '/affiliate-link':
    case '/partner-link':
      return '${PartnerProgramRoute.path}$q';
    case '/bot-store':
    case '/web-apps':
      return '${MiniAppsRoute.path}$q';
    case '/blocked-contacts':
      return '${BlockedUsersRoute.path}$q';
    case '/folder-settings':
    case '/dialog-filters':
    case '/filters':
      return '${ChatFolderNewRoute.path}$q';
    case '/phone-calls':
    case '/video-calls':
    case '/callhistory':
    case '/missedcalls':
    case '/phonecalls':
    case '/videocalls':
    case '/chatinfo':
    case '/groupinfo':
    case '/pinned-messages':
    case '/leave-group':
    case '/leave-channel':
    case '/delete-chat':
    case '/clear-chat':
    case '/mark-unread':
    case '/new-topic':
    case '/forum-topic':
    case '/send-location':
    case '/record-voice':
    case '/open-gallery':
    case '/saved-media':
    case '/shared-files':
    case '/shared-links':
    case '/shared-photos':
    case '/add-pack':
    case '/install-pack':
    case '/emoji-store':
    case '/custom-emoji':
    case '/saved-gifs':
    case '/recent-stickers':
    case '/stickerstore':
      return '${ChatsRoute.path}$q';
    case '/starred-messages':
    case '/userinfo':
    case '/selfchat':
    case '/my-qr':
      return '${ProfileTabRoute.path}$q';
    case '/create-poll':
    case '/create-quiz':
    case '/createpoll':
    case '/createquiz':
    case '/editpost':
      return '${CreatePostRoute.path}$q';
    case '/help-center':
    case '/helpcenter':
    case '/faq-page':
    case '/support-chat':
    case '/report-user':
    case '/report-channel':
    case '/report-bot':
    case '/reportuser':
      return '${SupportContactRoute.path}$q';
    case '/block-user':
    case '/unblock-user':
    case '/blockuser':
      return '${BlockedUsersRoute.path}$q';
    case '/create-folder':
    case '/edit-folder':
    case '/share-folder':
    case '/invite-folder':
    case '/createfolder':
      return '${ChatFolderNewRoute.path}$q';
    case '/mute-all':
    case '/quiet-hours':
    case '/muteall':
    case '/quiethours':
    case '/sound-settings':
    case '/in-app-sounds':
    case '/notification-center':
      return '${NotificationSettingsRoute.path}$q';
    case '/mentioned':
    case '/replies':
    case '/comments-feed':
    case '/activity-feed':
      return '${NotificationsRoute.path}$q';
    case '/check-update':
    case '/release-notes':
    case '/version-info':
    case '/build-number':
    case '/open-source':
    case '/third-party':
    case '/acknowledgements':
    case '/about-us':
    case '/aboutus':
    case '/checkupdate':
      return '${SupportSecurityRoute.path}$q';
    case '/people-search':
    case '/global-search':
    case '/chat-search':
      return '${SearchRoute.path}$q';
    case '/chat-theme':
    case '/name-color':
    case '/auto-lock':
    case '/data-saving':
    case '/use-proxy':
    case '/clearcache':
      return '${SettingsRoute.path}$q';
    case '/recovery-email':
    case '/change-number':
    case '/set-password':
    case '/linked-devices':
    case '/other-sessions':
      return '${AccountSecurityRoute.path}$q';
    case '/archive-chat':
    case '/chatarchive':
      return '${ChatArchivedRoute.path}$q';
    case '/open-camera':
      return '${StoryCreateRoute.path}$q';
    case '/share-contact':
      return '${ChatNewMessageRoute.path}$q';
    case '/addbot':
    case '/botstore':
      return '${MyBotsRoute.path}$q';
    case '/addchannel':
      return '${CreateChannelRoute.path}$q';
    case '/joinchannel':
      return '${ChannelsManagementRoute.path}$q';
    case '/addgroup':
      return '${ChatCreateGroupRoute.path}$q';
    case '/sendgift':
      return '${StarGiftsInventoryRoute.path}$q';
    case '/giftcode':
    case '/tonspace':
      return '${StarsWalletRoute.path}$q';
    case '/promolink':
    case '/reflink':
    case '/partnerpayout':
      return '${PartnerProgramRoute.path}$q';
    case '/boostchannel':
      return '${AdsHubRoute.path}$q';
    case '/suggestedpost':
    case '/paidpost':
      return '${CreatorToolsRoute.path}$q';
    case '/scheduledmessages':
      return '${ScheduledPostsRoute.path}$q';
    case '/slow-mode':
    case '/slowmode':
    case '/sign-messages':
    case '/discussion-group':
    case '/linked-discussion':
    case '/broadcast-channel':
    case '/unread-chats':
    case '/muted-chats':
    case '/pinned-chats':
    case '/send-as':
    case '/anonymous-admin':
    case '/hide-members':
    case '/hide-history':
    case '/invite-link-list':
    case '/join-request-list':
    case '/admin-rights':
    case '/group-list':
    case '/sticker-list':
    case '/my-stickers':
    case '/sticker-manager':
    case '/emoji-manager':
      return '${ChatsRoute.path}$q';
    case '/protect-content':
    case '/restrict-saving':
    case '/privacy-settings':
    case '/chat-wallpaper':
    case '/chat-background':
    case '/bubble-style':
    case '/message-style':
    case '/peer-color':
    case '/proxy-list':
      return '${SettingsRoute.path}$q';
    case '/online-contacts':
      return '${ChatNewMessageRoute.path}$q';
    case '/inline-bot':
    case '/attach-bot':
    case '/bot-settings':
    case '/edit-bot':
    case '/bot-profile':
    case '/bot-stats':
    case '/bot-list':
      return '${MyBotsRoute.path}$q';
    case '/launch-app':
    case '/start-webapp':
    case '/mini-app':
    case '/web-app':
    case '/miniapp-list':
      return '${MiniAppsRoute.path}$q';
    case '/upgrade-gift':
    case '/transfer-unique':
    case '/resale-gift':
    case '/gift-resale':
    case '/gift-list':
    case '/gift-send':
      return '${StarGiftsInventoryRoute.path}$q';
    case '/ton-wallet':
    case '/ton-connect':
    case '/crypto-wallet':
    case '/stars-history':
    case '/stars-transactions':
    case '/transaction-history':
    case '/payment-history':
    case '/invoice-list':
    case '/stars-buy':
      return '${StarsWalletRoute.path}$q';
    case '/subscription-history':
    case '/billing-details':
    case '/payment-methods':
    case '/premium-gift':
    case '/give-premium':
      return '${FlexSubscriptionRoute.path}$q';
    case '/flex-levels':
      return '${FlexConstructorRoute.path}$q';
    case '/ads-cabinet':
    case '/campaign-list':
    case '/boost-list':
    case '/giveaway-list':
      return '${AdsHubRoute.path}$q';
    case '/star-reactions':
    case '/paid-reactions':
    case '/paid-message':
    case '/message-fee':
    case '/paid-exceptions':
      return '${PaidMessageExceptionsRoute.path}$q';
    case '/paid-channel':
    case '/subscribe-channel':
    case '/join-paid':
    case '/channel-list':
      return '${ChannelsManagementRoute.path}$q';
    case '/session-list':
    case '/device-list':
      return '${AccountSecurityRoute.path}$q';
    case '/revenue-share':
      return '${ExtraAdsRoute.path}$q';
    case '/archived-stories':
    case '/hidden-stories':
    case '/story-settings':
      return '${StoriesRoute.path}$q';
    case '/folder-order':
      return '${ChatFolderNewRoute.path}$q';
    case '/notification-sounds':
      return '${NotificationSettingsRoute.path}$q';
    case '/auto-delete':
    case '/autodelete-timer':
    case '/ttl-settings':
    case '/disappear':
    case '/data-auto-download':
    case '/auto-download-photos':
    case '/save-to-gallery':
    case '/storage-usage':
    case '/cache-size':
    case '/clear-downloads':
    case '/language-app':
    case '/translate-chats':
    case '/animations-off':
    case '/reduce-motion':
    case '/power-saving-mode':
    case '/lite-settings':
    case '/night-theme':
    case '/day-theme':
    case '/system-theme':
    case '/swipe-actions':
    case '/distance-units':
    case '/time-format':
    case '/chat-themes':
    case '/message-colors':
    case '/accent-color':
    case '/privacy-phone':
    case '/privacy-photo':
    case '/privacy-bio':
    case '/privacy-forwards':
    case '/privacy-calls':
    case '/privacy-groups':
    case '/privacy-voice':
    case '/privacy-birthday':
    case '/privacy-gifts':
    case '/who-can-find':
    case '/peer-to-peer-calls':
    case '/sensitive-content':
    case '/age-restriction':
      return '${SettingsRoute.path}$q';
    case '/archive-folder':
      return '${ChatArchivedRoute.path}$q';
    case '/mute-settings':
    case '/custom-notifications':
    case '/chat-notifications':
    case '/channel-notifications':
    case '/group-notifications':
    case '/mention-notifications':
    case '/reaction-notifications':
    case '/sound-pack':
    case '/in-app-preview':
    case '/quiet-hours-schedule':
      return '${NotificationSettingsRoute.path}$q';
    case '/first-name':
    case '/last-name':
    case '/set-bio':
    case '/set-username':
    case '/username-link':
    case '/linked-email':
      return '${ProfileAuthRoute.path}$q';
    case '/two-step-password':
    case '/cloud-password-hint':
    case '/active-sessions-list':
    case '/terminate-other':
    case '/passcode-lock-settings':
    case '/auto-lock-timer':
    case '/unlock-with-biometrics':
    case '/login-with-qr':
    case '/link-desktop':
    case '/authorizations-list':
      return '${AccountSecurityRoute.path}$q';
    case '/blocked-users-list':
      return '${BlockedUsersRoute.path}$q';
    case '/close-friends-list':
      return '${CloseFriendsRoute.path}$q';
    case '/paid-messages-list':
    case '/exceptions-list':
      return '${PaidMessageExceptionsRoute.path}$q';
    case '/secret-chats-list':
    case '/saved-media-list':
    case '/shared-media-list':
      return '${ChatsRoute.path}$q';
    case '/export-chat':
    case '/import-chat':
    case '/chat-history':
    case '/message-search':
    case '/attach-file':
    case '/record-video-note':
    case '/forward-here':
    case '/pin-message':
    case '/schedule-message':
    case '/silent-send':
    case '/view-once':
    case '/spoiler-media':
    case '/transcribe':
    case '/voice-to-text':
    case '/send-when-online':
    case '/set-reminder':
    case '/caption-above':
    case '/message-effects':
    case '/chat-permissions':
    case '/sticker-settings':
    case '/emoji-settings':
    case '/saved-gifs-list':
    case '/enable-topics':
    case '/new-forum-topic':
    case '/close-topic':
    case '/general-topic':
    case '/make-admin':
    case '/ban-user':
    case '/approve-join':
    case '/invite-via-link':
    case '/leave-and-delete':
    case '/delete-message':
    case '/anti-spam':
    case '/join-to-send':
    case '/join-to-comment':
    case '/sign-posts':
    case '/hidden-members':
    case '/live-location-list':
      return '${ChatsRoute.path}$q';
    case '/people-nearby-list':
    case '/add-people':
      return '${ChatNewMessageRoute.path}$q';
    case '/report-message':
    case '/report-problem':
    case '/support-ticket':
      return '${SupportContactRoute.path}$q';
    case '/block-and-delete':
      return '${BlockedUsersRoute.path}$q';
    case '/gift-upgrade':
    case '/gift-transfer':
      return '${StarGiftsInventoryRoute.path}$q';
    case '/stars-topup':
      return '${StarsWalletRoute.path}$q';
    case '/stars-withdraw':
      return '${CreatorRevenueRoute.path}$q';
    case '/flex-manage':
    case '/flex-cancel':
      return '${FlexSubscriptionRoute.path}$q';
    case '/ads-create':
    case '/campaign-new':
      return '${AdsCampaignEditorRoute.path}$q';
    case '/ads-stats':
    case '/boost-now':
    case '/giveaway-new':
      return '${AdsHubRoute.path}$q';
    case '/suggested-new':
      return '${CreatorToolsRoute.path}$q';
    case '/partner-invite':
    case '/referral-code':
      return '${PartnerProgramRoute.path}$q';
    case '/extra-ads-toggle':
      return '${ExtraAdsRoute.path}$q';
    case '/2fa-setup':
      return '${TwoFactorSetupRoute.path}$q';
    case '/backup-export':
    case '/backup-restore':
      return '${BackupRoute.path}$q';
    case '/legal-terms':
    case '/legal-privacy':
    case '/legal-cookies':
    case '/about-hanwe':
      return '${SupportSecurityRoute.path}$q';
    case '/nighttheme':
    case '/daytheme':
    case '/systemtheme':
    case '/storageusage':
    case '/cachesize':
    case '/languageapp':
    case '/whocanfind':
    case '/sensitivecontent':
      return '${SettingsRoute.path}$q';
    case '/twosteppassword':
    case '/activesessionslist':
    case '/linkdesktop':
      return '${AccountSecurityRoute.path}$q';
    case '/blockeduserslist':
      return '${BlockedUsersRoute.path}$q';
    case '/channel-color':
      return '${ChannelsManagementRoute.path}$q';
    case '/saved-messages-settings':
    case '/default-send-as':
    case '/linked-chat-settings':
    case '/discussion-link':
    case '/sticker-pack-list':
    case '/emoji-pack-list':
    case '/unread-folder':
    case '/personal-chats':
    case '/groups-folder':
    case '/send-as-file':
    case '/sticker-suggestions':
    case '/hold-to-record':
    case '/voice-waveform':
    case '/round-video-notes':
    case '/video-messages':
    case '/photo-editor':
    case '/video-trimmer':
    case '/seen-by':
    case '/message-info':
    case '/silentsend':
    case '/exportchat':
    case '/messageeffects':
      return '${ChatsRoute.path}$q';
    case '/chat-wallpaper-url':
    case '/swipe-to-archive':
    case '/chat-preview':
    case '/link-preview-settings':
    case '/autoplay-gifs':
    case '/in-app-player':
    case '/save-edited-photos':
    case '/reply-with-enter':
    case '/send-with-enter':
    case '/replace-emoji':
    case '/big-emoji':
    case '/quick-reaction':
    case '/double-tap-react':
    case '/swipe-to-reply':
      return '${SettingsRoute.path}$q';
    case '/folder-invite-link':
    case '/chat-folders-list':
    case '/folder-share':
      return '${ChatFolderNewRoute.path}$q';
    case '/bots-folder':
      return '${MyBotsRoute.path}$q';
    case '/channels-folder':
      return '${ChannelsManagementRoute.path}$q';
    case '/push-settings':
    case '/web-push':
    case '/show-preview':
    case '/hide-preview':
      return '${NotificationSettingsRoute.path}$q';
    case '/story-views':
    case '/story-viewers':
    case '/moments-archive':
    case '/hide-story':
    case '/archive-story':
    case '/save-story':
    case '/share-story':
    case '/highlight-story':
      return '${StoriesRoute.path}$q';
    case '/upload-reel':
    case '/community-upload':
      return '${CreateReelRoute.path}$q';
    case '/addpeople':
      return '${ChatNewMessageRoute.path}$q';
    case '/reportproblem':
      return '${SupportContactRoute.path}$q';
    case '/blockanddelete':
      return '${BlockedUsersRoute.path}$q';
    case '/giftupgrade':
    case '/gifttransfer':
      return '${StarGiftsInventoryRoute.path}$q';
    case '/starstopup':
      return '${StarsWalletRoute.path}$q';
    case '/starswithdraw':
      return '${CreatorRevenueRoute.path}$q';
    case '/flexmanage':
      return '${FlexSubscriptionRoute.path}$q';
    case '/adscreate':
      return '${AdsCampaignEditorRoute.path}$q';
    case '/boostnow':
      return '${AdsHubRoute.path}$q';
    case '/partnerinvite':
      return '${PartnerProgramRoute.path}$q';
    case '/extraadstoggle':
      return '${ExtraAdsRoute.path}$q';
    case '/backupexport':
      return '${BackupRoute.path}$q';
    case '/legalterms':
    case '/abouthanwe':
      return '${SupportSecurityRoute.path}$q';
    case '/default-permissions':
    case '/approve-new-members':
    case '/slow-mode-timer':
    case '/forwarded-from':
    case '/inline-result':
    case '/iv-page':
    case '/cached-page':
    case '/invite-links':
    case '/pending-requests':
    case '/member-list':
    case '/banned-users':
    case '/history-for-new':
    case '/chat-admins':
    case '/protected-content':
    case '/no-forwards':
    case '/send-as-channel':
    case '/anonymous-posting':
    case '/mark-all-read':
    case '/read-all':
    case '/all-chats-folder':
    case '/non-contacts':
    case '/keep-archived':
    case '/unarchive-on-new':
      return '${ChatsRoute.path}$q';
    case '/auto-translate':
    case '/show-seconds':
    case '/read-time':
    case '/play-time':
    case '/message-timestamps':
    case '/exact-time':
    case '/date-format':
    case '/12-hour':
    case '/24-hour':
    case '/disable-animations':
    case '/in-app-browser':
    case '/open-links-in-app':
    case '/secret-chat-settings':
    case '/self-destruct-timer':
    case '/screenshot-notify':
    case '/secret-ttl':
      return '${SettingsRoute.path}$q';
    case '/via-bot':
      return '${MyBotsRoute.path}$q';
    case '/post-stats':
      return '${AppAnalyticsRoute.path}$q';
    case '/repost-story':
    case '/stories-stealth':
    case '/stealth-mode':
      return '${StoriesRoute.path}$q';
    case '/close-friends-story':
      return '${CloseFriendsRoute.path}$q';
    case '/channel-admins':
    case '/subscriber-list':
    case '/recent-subscribers':
    case '/boost-level':
    case '/channel-boost':
      return '${ChannelsManagementRoute.path}$q';
    case '/defaultpermissions':
    case '/approvenewmembers':
    case '/slowmodetimer':
    case '/forwardedfrom':
    case '/inlineresult':
    case '/ivpage':
    case '/cachedpage':
    case '/invitelinks':
    case '/pendingrequests':
    case '/memberlist':
    case '/bannedusers':
    case '/markallread':
      return '${ChatsRoute.path}$q';
    case '/showseconds':
    case '/readtime':
    case '/playtime':
    case '/inappbrowser':
    case '/secretttl':
      return '${SettingsRoute.path}$q';
    case '/viabot':
      return '${MyBotsRoute.path}$q';
    case '/poststats':
      return '${AppAnalyticsRoute.path}$q';
    case '/repoststory':
    case '/stealthmode':
      return '${StoriesRoute.path}$q';
    case '/closefriendsstory':
      return '${CloseFriendsRoute.path}$q';
    case '/channeladmins':
    case '/subscriberlist':
    case '/boostlevel':
      return '${ChannelsManagementRoute.path}$q';
    case '/search-messages':
    case '/search-media':
    case '/search-files':
    case '/search-links':
    case '/calendar-search':
    case '/hashtag-suggestions':
      return '${SearchRoute.path}$q';
    case '/jump-to-date':
    case '/scroll-to-date':
    case '/pinned-list':
    case '/unpin-all':
    case '/hide-pinned':
    case '/view-once-media':
    case '/send-as-document':
    case '/caption-below':
    case '/grouped-media':
    case '/album-send':
    case '/suggest-stickers':
    case '/mention-suggestions':
    case '/unread-divider':
    case '/side-menu':
    case '/tag-reactions':
      return '${ChatsRoute.path}$q';
    case '/compact-list':
    case '/chat-list-mode':
    case '/three-lines':
    case '/avatar-size':
    case '/date-headers':
    case '/send-uncompressed':
    case '/auto-night-schedule':
    case '/sticker-loop':
    case '/emoji-loop':
    case '/self-destruct-media':
    case '/quick-react':
    case '/color-tags':
      return '${SettingsRoute.path}$q';
    case '/inline-bots':
    case '/recent-bots':
    case '/command-suggestions':
      return '${MyBotsRoute.path}$q';
    case '/attach-menu-bots':
      return '${MiniAppsRoute.path}$q';
    case '/saved-tags':
    case '/message-tags':
      return '${SavedPostsRoute.path}$q';
    case '/star-react':
    case '/paid-react':
      return '${PaidMessageExceptionsRoute.path}$q';
    case '/my-notes':
      return '${ProfileTabRoute.path}$q';
    case '/folder-tags':
      return '${ChatFolderNewRoute.path}$q';
    case '/searchmessages':
    case '/searchmedia':
    case '/calendarsearch':
      return '${SearchRoute.path}$q';
    case '/jumptodate':
    case '/pinnedlist':
    case '/viewonce':
    case '/sendasdocument':
    case '/groupedmedia':
    case '/suggeststickers':
    case '/sidemenu':
      return '${ChatsRoute.path}$q';
    case '/compactlist':
    case '/chatlistmode':
    case '/senduncompressed':
    case '/stickersloop':
    case '/emojiloop':
    case '/quickreact':
      return '${SettingsRoute.path}$q';
    case '/inlinebots':
    case '/recentbots':
      return '${MyBotsRoute.path}$q';
    case '/attachmenubots':
      return '${MiniAppsRoute.path}$q';
    case '/savedtags':
    case '/messagetags':
      return '${SavedPostsRoute.path}$q';
    case '/starreact':
    case '/paidreact':
      return '${PaidMessageExceptionsRoute.path}$q';
    case '/mynotes':
      return '${ProfileTabRoute.path}$q';
    case '/foldertags':
      return '${ChatFolderNewRoute.path}$q';
    case '/saved-messages-search':
    case '/global-msg-search':
    case '/media-search':
    case '/file-search':
    case '/link-search':
    case '/music-search':
    case '/voice-search':
    case '/gif-search':
    case '/recent-search':
    case '/clear-recent-search':
      return '${SearchRoute.path}$q';
    case '/chat-filter-unread':
    case '/chat-filter-muted':
    case '/chat-filter-contacts':
    case '/chat-filter-groups':
    case '/chat-filter-channels':
    case '/chat-filter-bots':
    case '/new-secret-chat':
    case '/start-secret':
    case '/burn-after-read':
    case '/once-view':
    case '/ttl-media':
    case '/spoiler-caption':
    case '/edit-caption':
    case '/schedule-send':
    case '/send-later':
    case '/remind-me':
    case '/forward-as-copy':
    case '/hide-sender':
    case '/hide-forward':
    case '/no-author':
    case '/quote-reply':
    case '/thread-reply':
    case '/pin-quietly':
    case '/unpin-quietly':
    case '/jump-to-pin':
    case '/pins-list':
    case '/mentions-list':
    case '/seen-list':
    case '/read-by':
    case '/played-by':
      return '${ChatsRoute.path}$q';
    case '/add-to-folder':
    case '/remove-from-folder':
    case '/reorder-folders':
    case '/share-folder-link':
    case '/join-folder':
    case '/leave-folder':
    case '/hide-folder':
      return '${ChatFolderNewRoute.path}$q';
    case '/savedmessagessearch':
    case '/globalmsgsearch':
    case '/mediasearch':
    case '/filesearch':
    case '/gifsearch':
    case '/recentsearch':
      return '${SearchRoute.path}$q';
    case '/chatfilterunread':
    case '/newsecretchat':
    case '/burnafterread':
    case '/onceview':
    case '/schedulesend':
    case '/sendlater':
    case '/forwardascopy':
    case '/hidesender':
    case '/quotereply':
    case '/pinquietly':
    case '/pinslist':
    case '/readby':
      return '${ChatsRoute.path}$q';
    case '/addtofolder':
    case '/reorderfolders':
    case '/joinfolder':
    case '/sharefolderlink':
      return '${ChatFolderNewRoute.path}$q';
    case '/swipe-to-delete':
    case '/chat-list-tabs':
    case '/peer-colors':
    case '/name-colors':
    case '/profile-colors':
    case '/message-translation':
    case '/show-translate':
    case '/do-not-translate':
    case '/always-translate':
    case '/download-path':
    case '/save-to-gallery-videos':
    case '/stream-videos':
    case '/use-less-data':
    case '/adaptive-bitrate':
    case '/hardware-decode':
    case '/pip-player':
    case '/background-playback':
    case '/noise-suppression':
    case '/echo-cancel':
    case '/call-data-saving':
    case '/proxy-for-calls':
    case '/voip-proxy':
    case '/sticker-looping':
    case '/suggest-animated':
    case '/loop-animated':
    case '/preview-links':
    case '/web-preview':
    case '/fahrenheit':
    case '/celsius':
    case '/map-provider':
    case '/location-services':
    case '/people-nearby-visibility':
    case '/who-can-add':
    case '/invite-privacy':
    case '/group-invite-privacy':
    case '/last-seen-except':
    case '/online-except':
    case '/profile-photo-except':
    case '/bio-except':
    case '/messages-except':
    case '/calls-except':
      return '${SettingsRoute.path}$q';
    case '/archive-and-mute':
    case '/hide-archived':
    case '/unhide-archived':
      return '${ChatArchivedRoute.path}$q';
    case '/raise-to-speak':
    case '/hold-to-talk':
    case '/voice-cancel':
    case '/custom-emoji-packs':
    case '/archived-stickers':
    case '/archived-emoji':
    case '/masks':
    case '/instant-previews':
    case '/iv-always':
      return '${ChatsRoute.path}$q';
    case '/swipetodelete':
    case '/chatlisttabs':
    case '/peercolors':
    case '/messagetranslation':
    case '/donottranslate':
    case '/pipplayer':
    case '/backgroundplayback':
    case '/noisesuppression':
    case '/voipproxy':
    case '/previewlinks':
    case '/lastseenexcept':
      return '${SettingsRoute.path}$q';
    case '/archiveandmute':
    case '/hidearchived':
      return '${ChatArchivedRoute.path}$q';
    case '/raisetospeak':
    case '/holdtotalk':
    case '/archivedstickers':
    case '/ivalways':
      return '${ChatsRoute.path}$q';
    case '/featured-stickers':
    case '/trending-stickers':
    case '/export-stickers':
    case '/import-stickers':
    case '/create-sticker-pack':
    case '/edit-sticker-pack':
    case '/sticker-sets-order':
    case '/emoji-sets-order':
    case '/recent-emoji':
    case '/frequent-stickers':
    case '/archived-gifs':
    case '/saved-reactions':
    case '/reaction-order':
    case '/quick-reaction-choose':
    case '/channel-reactions':
    case '/group-reactions':
    case '/restrict-reactions':
    case '/custom-reaction':
    case '/default-emoji-status':
    case '/collectible-status':
    case '/topic-icon':
    case '/topic-color':
    case '/close-all-topics':
    case '/forum-as-messages':
    case '/topics-as-tabs':
    case '/general-topic-hide':
    case '/invite-link-expire':
    case '/invite-link-limit':
    case '/invite-link-revoke':
    case '/invite-expire':
    case '/invite-limit':
    case '/leave-quietly':
    case '/report-spam-and-leave':
      return '${ChatsRoute.path}$q';
    case '/wear-gift':
    case '/unwear-gift':
    case '/pinned-gifts':
    case '/hide-gifts':
    case '/show-gifts':
    case '/gift-profile':
    case '/wear-collectible':
      return '${StarGiftsInventoryRoute.path}$q';
    case '/suggested-posts-settings':
    case '/offer-post':
    case '/accept-suggested':
    case '/reject-suggested':
    case '/ads-revenue':
    case '/channel-ad-revenue':
      return '${AdsHubRoute.path}$q';
    case '/star-ref':
      return '${PartnerProgramRoute.path}$q';
    case '/attach-menu-order':
    case '/remove-attach-bot':
    case '/side-menu-bots':
    case '/webapp-settings':
      return '${MiniAppsRoute.path}$q';
    case '/bot-privacy-policy':
    case '/bot-affiliate':
    case '/affiliate-bot':
      return '${MyBotsRoute.path}$q';
    case '/split-view':
    case '/tablet-mode':
    case '/floating-window':
    case '/multi-window':
      return '${SettingsRoute.path}$q';
    case '/badge-count':
    case '/dock-icon':
    case '/desktop-notifications':
      return '${NotificationSettingsRoute.path}$q';
    case '/delete-channel':
    case '/remove-channel':
      return '${ChannelsManagementRoute.path}$q';
    case '/featuredstickers':
    case '/trendingstickers':
    case '/createstickerpack':
    case '/recentemoji':
    case '/topicicon':
    case '/closealltopics':
    case '/invitelinkexpire':
    case '/leavequietly':
      return '${ChatsRoute.path}$q';
    case '/weargift':
    case '/unweargift':
    case '/pinnedgifts':
    case '/hidegifts':
      return '${StarGiftsInventoryRoute.path}$q';
    case '/offerpost':
    case '/acceptsuggested':
    case '/adsrevenue':
      return '${AdsHubRoute.path}$q';
    case '/starref':
      return '${PartnerProgramRoute.path}$q';
    case '/attachmenuorder':
    case '/removeattachbot':
    case '/webappsettings':
      return '${MiniAppsRoute.path}$q';
    case '/botaffiliate':
    case '/affiliatebot':
      return '${MyBotsRoute.path}$q';
    case '/splitview':
    case '/tabletmode':
      return '${SettingsRoute.path}$q';
    case '/badgecount':
    case '/dockicon':
      return '${NotificationSettingsRoute.path}$q';
    case '/deletechannel':
      return '${ChannelsManagementRoute.path}$q';
    case '/keyboard-shortcuts':
    case '/hotkeys':
    case '/speaker-mode':
    case '/noise-cancel':
    case '/call-settings':
    case '/missed-call':
    case '/slow-mode-seconds':
    case '/transfer-ownership':
    case '/request-admin':
    case '/invite-link-usage':
    case '/primary-invite-reset':
    case '/join-request-approve-all':
    case '/join-request-decline-all':
    case '/hide-general-topic':
    case '/topic-as-chat':
    case '/sticker-permissions':
    case '/default-admin-rights':
    case '/add-emoji-pack':
    case '/install-emoji':
    case '/remove-sticker-set':
    case '/reorder-stickers':
    case '/loop-stickers':
    case '/suggest-by-emoji':
    case '/trending-gifs':
    case '/saved-emoji':
    case '/create-sticker-set':
      return '${ChatsRoute.path}$q';
    case '/call-privacy':
    case '/data-for-calls':
    case '/use-less-data-calls':
    case '/auto-play-videos':
    case '/external-browser':
    case '/link-out':
    case '/cache-database':
    case '/reset-cache':
    case '/rebuild-index':
    case '/sd-card':
    case '/download-folder':
    case '/in-app-browser-always':
    case '/tag-color':
    case '/chat-tag':
      return '${SettingsRoute.path}$q';
    case '/passcode-change':
    case '/auto-lock-screen':
    case '/unlock-pattern':
    case '/session-terminate':
    case '/terminate-all-others':
      return '${AccountSecurityRoute.path}$q';
    case '/login-email':
      return '${ProfileAuthRoute.path}$q';
    case '/recovery-code':
    case '/cloud-password-change':
    case '/disable-2fa':
    case '/enable-2fa':
      return '${TwoFactorSetupRoute.path}$q';
    case '/paid-reaction-privacy':
    case '/star-reaction-privacy':
      return '${PaidMessageExceptionsRoute.path}$q';
    case '/folder-color':
      return '${ChatFolderNewRoute.path}$q';
    case '/story-stealth':
    case '/story-hide-from':
    case '/story-allow':
    case '/reply-to-story':
    case '/story-privacy-list':
    case '/emoji-status-list':
    case '/wear-emoji':
      return '${StoriesRoute.path}$q';
    case '/keyboardshortcuts':
    case '/speakermode':
    case '/callsettings':
    case '/transferownership':
    case '/addemojipack':
    case '/trendinggifs':
      return '${ChatsRoute.path}$q';
    case '/callprivacy':
    case '/autoplayvideos':
    case '/externalbrowser':
    case '/resetcache':
      return '${SettingsRoute.path}$q';
    case '/passcodechange':
    case '/terminateallothers':
      return '${AccountSecurityRoute.path}$q';
    case '/enable2fa':
    case '/disable2fa':
      return '${TwoFactorSetupRoute.path}$q';
    case '/replytostory':
    case '/storystealth':
    case '/wearemoji':
      return '${StoriesRoute.path}$q';
    case '/send-photos':
    case '/send-videos':
    case '/send-files':
    case '/send-music':
    case '/send-voice':
    case '/send-round':
    case '/send-games':
    case '/send-inline':
    case '/send-plain':
    case '/change-info':
    case '/post-messages':
    case '/edit-messages':
    case '/delete-messages':
    case '/ban-users':
    case '/invite-users':
    case '/pin-messages':
    case '/manage-topics':
    case '/manage-video-chats':
    case '/add-admins':
    case '/remain-anonymous':
    case '/post-stories':
    case '/edit-stories':
    case '/delete-stories':
    case '/manage-direct':
    case '/manage-gifts':
    case '/change-profile':
    case '/post-as-channel':
    case '/edit-admins':
    case '/custom-admin-title':
    case '/admin-rank':
    case '/removed-users':
    case '/kicked-list':
    case '/banned-list':
    case '/restricted-list':
    case '/restrict-media':
    case '/restrict-stickers':
    case '/restrict-gifs':
    case '/restrict-polls':
    case '/restrict-embed':
    case '/restrict-invite':
    case '/restrict-pin':
    case '/restrict-info':
    case '/silent-join':
    case '/hide-join':
    case '/show-join':
    case '/captcha-join':
    case '/approve-media':
    case '/mention-all':
    case '/loop-gifs':
    case '/sticker-suggest':
    case '/emoji-suggest':
    case '/inline-suggest':
    case '/saved-gif':
    case '/sendphotos':
    case '/sendvideos':
    case '/deletemessages':
    case '/sendplain':
    case '/changeinfo':
    case '/postmessages':
    case '/banusers':
    case '/inviteusers':
    case '/managetopics':
    case '/addadmins':
    case '/poststories':
    case '/managegifts':
    case '/changeprofile':
    case '/adminrank':
    case '/kickedlist':
    case '/restrictedlist':
    case '/restrictmedia':
    case '/silentjoin':
    case '/mentionall':
    case '/savedgif':
      return '${ChatsRoute.path}$q';
    case '/send-polls':
    case '/send-stickers':
    case '/send-gifs':
    case '/send-embeds':
    case '/send-locations':
    case '/send-contacts':
    case '/change-chat-info':
    case '/delete-others':
    case '/ban-members':
    case '/start-voice-chat':
    case '/end-voice-chat':
    case '/voice-chat-settings':
    case '/record-live':
    case '/stream-live':
    case '/manage-live':
    case '/invite-to-call':
    case '/call-members':
    case '/raise-hand':
    case '/make-speaker':
    case '/mute-all-call':
    case '/call-panel':
    case '/screen-share':
    case '/share-screen':
    case '/noise-suppression-call':
    case '/echo-cancellation':
    case '/video-source':
    case '/camera-flip':
    case '/dual-camera':
    case '/blur-background':
    case '/virtual-background':
    case '/beauty-filter':
    case '/call-rating':
    case '/call-feedback':
    case '/redial':
    case '/call-callback':
    case '/decline-call':
    case '/accept-call':
    case '/ignore-call':
    case '/call-waiting':
    case '/group-call':
    case '/video-chat':
    case '/join-voice-chat':
    case '/leave-voice-chat':
    case '/mute-participant':
    case '/kick-from-call':
    case '/pin-speaker':
    case '/speaker-view':
    case '/grid-view':
    case '/speaker-phone':
    case '/earpiece':
    case '/call-invite':
    case '/call-quality':
    case '/low-data-call':
    case '/toggle-video':
    case '/toggle-mic':
    case '/call-volume':
    case '/call-stats':
    case '/rtmp-stream':
    case '/live-stream-key':
    case '/start-livestream':
    case '/stop-livestream':
    case '/schedule-live':
    case '/live-comments':
    case '/live-reactions':
      return '${ChatsRoute.path}$q';
    case '/sendpolls':
    case '/sendstickers':
    case '/sendgifs':
    case '/sendcontacts':
    case '/startvoicechat':
    case '/endvoicechat':
    case '/raisehand':
    case '/screenshare':
    case '/sharescreen':
    case '/redialcall':
    case '/acceptcall':
    case '/declinecall':
    case '/callwaiting':
    case '/blurbg':
    case '/dualcamera':
    case '/groupcall':
    case '/videochat':
    case '/joinvoicechat':
    case '/leavevoicechat':
    case '/muteparticipant':
    case '/speakerview':
    case '/speakerphone':
    case '/togglevideo':
    case '/togglemic':
    case '/startlivestream':
    case '/stoplivestream':
    case '/schedulelive':
      return '${ChatsRoute.path}$q';
    default:
      return null;
  }
}

/// Преобразует `haneat://...` или `https://haneat.app/...` в путь для [GoRouter].
String? parseDeepLinkToGoPath(String raw) {
  try {
    final uri = Uri.parse(raw);
    if (uri.scheme == 'https' || uri.scheme == 'http') {
      final host = uri.host.toLowerCase();
      if (_isAppHttpHost(host)) {
        // PWA живёт на /app/ — это HTML-шелл, не маршрут GoRouter.
        var path = browserPathToGoPath(uri.path) ?? '';
        var query = routerQueryFromUri(uri);
        // Hash-стратегия: https://haneat.app/app/#/stories
        // и invite: https://haneat.app/app/#/invite?ref=ABC
        if (path.isEmpty && uri.fragment.isNotEmpty) {
          final frag = uri.fragment.trim();
          final fragPath = frag.startsWith('/') ? frag : '/$frag';
          final fragUri = Uri.parse('https://haneat.app$fragPath');
          path = browserPathToGoPath(fragUri.path) ?? '';
          query = routerQueryFromUri(fragUri) ?? query;
        }
        // https://haneat.app/@username → /u/username
        if (path.startsWith('/@') && path.length > 2) {
          final handle = path.substring(2).split('/').first;
          if (handle.isNotEmpty) {
            return UsernameDeepLinkRoute.pathFor(handle);
          }
        }
        if (path == '/invite' || path.startsWith('/invite/')) {
          final fromQuery = PendingReferral.queryRef(uri);
          if (fromQuery != null) {
            return '/invite?ref=${Uri.encodeComponent(fromQuery)}';
          }
          if (path.startsWith('/invite/')) {
            final code = path.substring('/invite/'.length).split('/').first;
            final extracted = PendingReferral.extract(code);
            if (extracted != null) {
              return '/invite?ref=${Uri.encodeComponent(extracted)}';
            }
          }
          return query == null ? '/invite' : '/invite?$query';
        }
        if (path.isNotEmpty && path != '/') {
          path = unwrapGoOpenPath(path);
          final reelPath = ReelByIdRoute.goPathFromBrowserPath(path);
          if (reelPath != null) {
            return reelPath;
          }
          final leftover = leftoverPathAlias(path, query ?? '');
          if (leftover != null) {
            return leftover;
          }
          return query == null ? path : '$path?$query';
        }
        final rootRef = PendingReferral.queryRef(uri);
        if (rootRef != null) {
          return '${RegisterRoute.path}?ref=${Uri.encodeComponent(rootRef)}';
        }
      }
      return null;
    }
    if (uri.scheme != 'haneat') return null;
    if (uri.host == 'reel' && uri.pathSegments.isNotEmpty) {
      return ReelByIdRoute.pathFor(uri.pathSegments.first);
    }
    if (uri.host == 'post' && uri.pathSegments.isNotEmpty) {
      return '/post/${uri.pathSegments.first}';
    }
    if (uri.host == 'channel' && uri.pathSegments.isNotEmpty) {
      return '/channel/${uri.pathSegments.first}';
    }
    if (uri.host == 'chat' && uri.pathSegments.isNotEmpty) {
      final chatPath = '/chats/thread/${uri.pathSegments.first}';
      final msg = uri.queryParameters['msg'];
      if (msg != null && msg.isNotEmpty) {
        return '$chatPath?msg=${Uri.encodeComponent(msg)}';
      }
      return chatPath;
    }
    if (uri.host == 'chat-invite' && uri.pathSegments.isNotEmpty) {
      return '/chat-invite/${uri.pathSegments.first}';
    }
    if (uri.host == 'u' && uri.pathSegments.isNotEmpty) {
      return UsernameDeepLinkRoute.pathFor(uri.pathSegments.first);
    }
    if (uri.host == 'subscription') {
      if (uri.pathSegments.contains('success')) {
        return SubscriptionSuccessRoute.path;
      }
      if (uri.pathSegments.contains('cancel')) {
        return SubscriptionCancelRoute.path;
      }
    }
    if (uri.host == 'paid') {
      if (uri.pathSegments.contains('success')) {
        return StarsCheckoutSuccessRoute.path;
      }
      if (uri.pathSegments.contains('cancel')) {
        return StarsCheckoutCancelRoute.path;
      }
      if (uri.pathSegments.contains('wallet')) {
        return StarsWalletRoute.path;
      }
    }
    if (uri.host == 'invite') {
      final ref = PendingReferral.queryRef(uri);
      if (ref != null && ref.isNotEmpty) {
        return '${RegisterRoute.path}?ref=${Uri.encodeComponent(ref)}';
      }
      return RegisterRoute.path;
    }
    if (uri.host == 'auth' && uri.pathSegments.isNotEmpty) {
      final action = uri.pathSegments.first;
      final token = uri.queryParameters['token'];
      final email = uri.queryParameters['email'];
      if (token != null && token.isNotEmpty) {
        switch (action) {
          case 'verify-email':
            return AuthPaths.verifyEmailWith(token: token, email: email);
          case 'reset-password':
            return AuthPaths.resetPasswordWith(token: token, email: email);
          case 'confirm-email-change':
            return AuthPaths.confirmEmailChangeWith(
              token: token,
              email: email,
            );
        }
      }
    }
  } catch (_) {}
  return null;
}

/// После смены числа вкладок (5→4) старый shell index мог быть вне диапазона → краш IndexedStack.
Widget _safeShellIndexedStack(
  BuildContext context,
  StatefulNavigationShell shell,
  List<Widget> children,
) {
  // Empty children during a GoRouter shell remount must NOT be SizedBox.shrink:
  // on Flutter web/CanvasKit that paints as a blank white frame.
  if (children.isEmpty) {
    return const ColoredBox(
      color: Color(0xFF0F1319),
      child: SizedBox.expand(),
    );
  }
  final last = children.length - 1;
  final raw = shell.currentIndex;
  final idx = raw < 0 || raw > last ? 0 : raw;
  return IndexedStack(
    index: idx,
    sizing: StackFit.expand,
    children: List.generate(children.length, (i) {
      return TickerMode(
        enabled: i == idx,
        child: children[i],
      );
    }),
  );
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final homePath =
      FeedRoute.path;
  // Use the real authenticated home (shell). Temporary /web-session landing
  // and hard reloads after login caused blank Safari pages, not stability.
  final stableHomePath = homePath;
  final initialLoc = () {
    if (initialDeepLink != null) {
      final path = parseDeepLinkToGoPath(initialDeepLink!);
      initialDeepLink = null;
      if (path != null) return path;
    }
    if (kIsWeb) {
      final fromBrowser = parseDeepLinkToGoPath(Uri.base.toString());
      if (fromBrowser != null) return fromBrowser;
      // Сессия уже восстановлена в StartupShell — не мигаем /boot.
      return AuthService.instance.currentUser == null
          ? LoginRoute.path
          : stableHomePath;
    }
    return BootScreen.path;
  }();
  return GoRouter(
    navigatorKey: hanEatRootNavigatorKey,
    initialLocation: initialLoc,
    refreshListenable: Listenable.merge([
      AuthService.sessionRevision,
      AppBootstrapState.authReady,
    ]),
    redirect: (context, state) {
      try {
        final loc = state.matchedLocation;
        final incoming = state.uri.path;
        if (!AppBootstrapState.authReady.value) {
          if (loc == BootScreen.path) return null;
          return BootScreen.path;
        }
        // PWA /app/?go=1 при base-href=/app/ приходит в роутер как `/`.
        // Смотрим uri.path: matchedLocation на промежуточном кадре бывает пустым.
        if (isGoRouterShellLocation(incoming)) {
          if (AuthService.instance.currentUser == null) {
            return LoginRoute.path;
          }
          FeedShellLaunch.skipReelsTab = true;
          return stableHomePath;
        }
        if (loc == BootScreen.path) {
          if (AuthService.instance.currentUser == null) {
            return LoginRoute.path;
          }
          return stableHomePath;
        }
        if (loc == ChannelsListRoute.path) {
          return ChatsRoute.path;
        }
        // Legacy kitchen deep links → feed (+ one-shot notice)
        if (_isRetiredKitchenPath(loc)) {
          KitchenRemovedNotice.markPending();
          return FeedRoute.path;
        }
        final user = AuthService.instance.currentUser;
        final isAuth = user != null;
        if (isAuth &&
            !user.emailVerified &&
            loc != VerifyEmailRoute.path &&
            !loc.startsWith('${VerifyEmailRoute.path}?')) {
          final email = Uri.encodeComponent(user.email);
          return '${VerifyEmailRoute.path}?email=$email';
        }
        if (isAuth &&
            user.legalConsentRequired &&
            loc != LegalConsentRoute.path &&
            !loc.startsWith('${LegalConsentRoute.path}?')) {
          final from = Uri.encodeComponent(state.uri.toString());
          return '${LegalConsentRoute.path}?from=$from';
        }
        if (isAuth &&
            user.emailVerified &&
            (loc == LoginRoute.path || loc == RegisterRoute.path)) {
          final ref = PendingReferral.queryRef(state.uri);
          if (ref != null && ref.isNotEmpty) {
            unawaited(PendingReferralStore.remember(ref));
            return PartnerProgramRoute.path;
          }
          return stableHomePath;
        }
        final aliasQuery = state.uri.query;
        final unwrapped = unwrapGoOpenPath(incoming);
        final aliased = leftoverPathAlias(unwrapped, aliasQuery);
        if (aliased != null) {
          final aliasPath = aliased.split('?').first;
          final here = loc.split('?').first;
          if (aliasPath != here) return aliased;
        }
        if (unwrapped != incoming) {
          return aliasQuery.isEmpty ? unwrapped : '$unwrapped?$aliasQuery';
        }
        if (isAuth) return null;
        final locBase = loc.split('?').first;
        if (locBase == ProfileAuthRoute.path || locBase == SettingsRoute.path) {
          return LoginRoute.path;
        }
        if (routeAllowsGuestAccess(loc)) return null;
        final isAuthRoute = loc == LoginRoute.path ||
            loc == RegisterRoute.path ||
            loc == '/invite' ||
            loc.startsWith(ChatInviteJoinRoute.basePath) ||
            loc == ForgotPasswordRoute.path ||
            loc == ResetPasswordRoute.path ||
            loc.startsWith(VerifyEmailRoute.path) ||
            loc.startsWith(ConfirmEmailChangeRoute.path) ||
            loc == TwoFactorVerifyRoute.path ||
            loc.startsWith('${TwoFactorVerifyRoute.path}?');
        if (isAuthRoute) return null;
        return LoginRoute.path;
      } catch (e, st) {
        debugPrint('router.redirect recover: $e\n$st');
        return AuthService.instance.currentUser == null
            ? LoginRoute.path
            : stableHomePath;
      }
    },
    routes: [
      GoRoute(
        path: '/',
        redirect: (context, state) {
          if (AuthService.instance.currentUser == null) {
            return LoginRoute.path;
          }
          FeedShellLaunch.skipReelsTab = true;
          return FeedRoute.path;
        },
      ),
      GoRoute(
        path: BootScreen.path,
        name: 'boot',
        pageBuilder: (context, state) => const NoTransitionPage(
          key: ValueKey('boot'),
          child: BootScreen(),
        ),
      ),
      if (kIsWeb)
        GoRoute(
          path: WebSocialHomeRoute.path,
          name: WebSocialHomeRoute.name,
          pageBuilder: (context, state) => const MaterialPage(
            child: ChatsHubScreen(),
          ),
        ),
      if (kIsWeb)
        GoRoute(
          path: WebSessionLandingRoute.path,
          name: WebSessionLandingRoute.name,
          pageBuilder: (context, state) => const MaterialPage(
            child: WebSessionLandingScreen(),
          ),
        ),
      StatefulShellRoute(
        navigatorContainerBuilder: _safeShellIndexedStack,
        builder: (context, state, navigationShell) =>
            RootShell(navigationShell: navigationShell),
        branches: [
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: FeedRoute.path,
                      name: FeedRoute.name,
                      pageBuilder: (context, state) => NoTransitionPage(
                        key: const ValueKey('feed_branch'),
                        child: const MainFeedScreen(),
                      ),
                    ),
                  ],
                ),
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: ChatsRoute.path,
                      name: ChatsRoute.name,
                      pageBuilder: (context, state) => NoTransitionPage(
                        key: const ValueKey('chats_branch'),
                        child: const ChatsHubScreen(),
                      ),
                    ),
                  ],
                ),
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: MiniAppsRoute.path,
                      name: MiniAppsRoute.name,
                      pageBuilder: (context, state) => NoTransitionPage(
                        key: const ValueKey('mini_apps_branch'),
                        child: const MiniAppsCatalogScreen(),
                      ),
                    ),
                  ],
                ),
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: ProfileTabRoute.path,
                      name: ProfileTabRoute.name,
                      pageBuilder: (context, state) => NoTransitionPage(
                        key: const ValueKey('profile_branch'),
                        child: const ProfileScreen(),
                      ),
                    ),
                  ],
                ),
              ],
      ),
      GoRoute(
        path: StoriesRoute.path,
        name: StoriesRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: StoriesHubScreen()),
      ),
      GoRoute(
        path: StoryCreateRoute.path,
        name: StoryCreateRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: StoryCameraScreen()),
      ),
      GoRoute(
        path: StoryViewerRoute.path,
        name: StoryViewerRoute.name,
        parentNavigatorKey: hanEatRootNavigatorKey,
        pageBuilder: (context, state) {
          final id = parseRoutePositiveId(state.pathParameters['storyId']);
          if (id == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Момент'),
            );
          }
          final extra = state.extra;
          final seeded = extra is List<StoryItem>
              ? extra
              : extra is List
                  ? extra.whereType<StoryItem>().toList()
                  : null;
          return MaterialPage(
            child: StoryViewerLoaderScreen(
              storyId: id,
              initialStories: seeded,
            ),
          );
        },
      ),
      GoRoute(
        path: '/story/:storyId',
        redirect: (context, state) {
          final id = parseRoutePositiveId(state.pathParameters['storyId']);
          if (id == null) return StoriesRoute.path;
          return StoryViewerRoute.pathFor(id);
        },
      ),
      GoRoute(
        path: DonateRoute.path,
        name: DonateRoute.name,
        pageBuilder: (context, state) {
          final to = parseRoutePositiveId(state.uri.queryParameters['to']);
          if (to == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Донат'),
            );
          }
          return MaterialPage(
            child: DonationScreen(
              recipientId: to,
              recipientName: state.uri.queryParameters['name'] ?? 'пользователь',
              channelId:
                  parseRoutePositiveId(state.uri.queryParameters['channel']),
              postId: parseRoutePositiveId(state.uri.queryParameters['post']),
              channelName: state.uri.queryParameters['channelName'],
            ),
          );
        },
      ),
      GoRoute(
        path: MiniAppOpenRoute.path,
        name: MiniAppOpenRoute.name,
        parentNavigatorKey: hanEatRootNavigatorKey,
        pageBuilder: (context, state) {
          final id = parseRoutePositiveId(state.pathParameters['miniAppId']);
          if (id == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Mini App'),
            );
          }
          return MaterialPage(
            child: MiniAppOpenLoaderScreen(
              miniAppId: id,
              conversationId:
                  parseRoutePositiveId(state.uri.queryParameters['chat']),
              startParam: state.uri.queryParameters['start'],
            ),
          );
        },
      ),
      GoRoute(
        path: ChannelsListRoute.path,
        name: ChannelsListRoute.name,
        redirect: (context, state) => ChatsRoute.path,
      ),
      GoRoute(
        path: SettingsRoute.path,
        name: SettingsRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: SettingsScreen()),
      ),
      GoRoute(
        path: BlockedUsersRoute.path,
        name: BlockedUsersRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: BlockedUsersScreen()),
      ),
      // Маршруты настроек
      GoRoute(
        path: ProfileAuthRoute.path,
        name: ProfileAuthRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: ProfileAuthScreen()),
      ),
      GoRoute(
        path: NotificationsRoute.path,
        name: NotificationsRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: NotificationsScreen()),
      ),
      GoRoute(
        path: NotificationSettingsRoute.path,
        name: NotificationSettingsRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: NotificationSettingsPage()),
      ),
      GoRoute(
        path: CreatorToolsRoute.path,
        name: CreatorToolsRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: CreatorToolsScreen()),
      ),
      GoRoute(
        path: ScheduledPostsRoute.path,
        name: ScheduledPostsRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: ScheduledPostsScreen()),
      ),
      GoRoute(
        path: PromotedPostsRoute.path,
        name: PromotedPostsRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: PromotedPostsScreen()),
      ),
      GoRoute(
        path: AdsHubRoute.path,
        name: AdsHubRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: AdvertiserHubScreen()),
      ),
      GoRoute(
        path: PartnerProgramRoute.path,
        name: PartnerProgramRoute.name,
        pageBuilder: (context, state) => const MaterialPage(
          child: PartnerProgramScreen(),
        ),
      ),
      GoRoute(
        path: ExtraAdsRoute.path,
        name: ExtraAdsRoute.name,
        pageBuilder: (context, state) => const MaterialPage(
          child: PartnerProgramScreen(focusExtraAds: true),
        ),
      ),
      GoRoute(
        path: AdsCampaignEditorRoute.path,
        name: AdsCampaignEditorRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: AdCampaignEditorScreen()),
      ),
      GoRoute(
        path: AdsCampaignEditorRoute.editPath,
        name: AdsCampaignEditorRoute.editName,
        pageBuilder: (context, state) {
          final id = parseRoutePositiveId(state.pathParameters['campaignId']);
          if (id == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Реклама'),
            );
          }
          return MaterialPage(
            child: AdCampaignEditorScreen(campaignId: id),
          );
        },
      ),
      GoRoute(
        path: AdsReviewRoute.path,
        name: AdsReviewRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: AdsReviewScreen()),
      ),
      GoRoute(
        path: SubscriptionRoute.path,
        name: SubscriptionRoute.name,
        pageBuilder: (context, state) {
          final product = state.uri.queryParameters['product'];
          return MaterialPage(
            child: FlexSubscriptionScreen(
              initialLevel: FlexPurchaseLadder.levelForClassicProduct(product),
            ),
          );
        },
      ),
      GoRoute(
        path: '/flex',
        redirect: (context, state) {
          final q = state.uri.query;
          return q.isEmpty
              ? FlexSubscriptionRoute.path
              : '${FlexSubscriptionRoute.path}?$q';
        },
      ),
      GoRoute(
        path: '/stars',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            StarsWalletRoute.path,
      ),
      GoRoute(
        path: '/wallet',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            StarsWalletRoute.path,
      ),
      GoRoute(
        path: '/gifts',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            StarGiftsInventoryRoute.path,
      ),
      GoRoute(
        path: '/premium',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            FlexSubscriptionRoute.path,
      ),
      GoRoute(
        path: '/referral',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            PartnerProgramRoute.path,
      ),
      GoRoute(
        path: '/partner',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            PartnerProgramRoute.path,
      ),
      GoRoute(
        path: '/bots',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            MyBotsRoute.path,
      ),
      GoRoute(
        path: '/security',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            AccountSecurityRoute.path,
      ),
      GoRoute(
        path: '/settings/security',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            AccountSecurityRoute.path,
      ),
      GoRoute(
        path: '/settings/sessions',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            AccountSecurityRoute.path,
      ),
      GoRoute(
        path: '/settings/privacy',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SettingsRoute.path,
      ),
      GoRoute(
        path: '/blocked',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            BlockedUsersRoute.path,
      ),
      GoRoute(
        path: '/saved',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            ProfileTabRoute.path,
      ),
      GoRoute(
        path: '/extra-ads',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            ExtraAdsRoute.path,
      ),
      GoRoute(
        path: '/creator',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            CreatorToolsRoute.path,
      ),
      GoRoute(
        path: '/scheduled',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            ScheduledPostsRoute.path,
      ),
      GoRoute(
        path: '/promoted',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            PromotedPostsRoute.path,
      ),
      GoRoute(
        path: '/payouts',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            CreatorRevenueRoute.path,
      ),
      GoRoute(
        path: '/revenue',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            CreatorRevenueRoute.path,
      ),
      GoRoute(
        path: '/2fa',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            TwoFactorSetupRoute.path,
      ),
      GoRoute(
        path: '/edit-profile',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            ProfileAuthRoute.path,
      ),
      GoRoute(
        path: '/profile/edit',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            ProfileAuthRoute.path,
      ),
      GoRoute(
        path: '/me/edit',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            ProfileAuthRoute.path,
      ),
      GoRoute(
        path: '/privacy',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SettingsRoute.path,
      ),
      GoRoute(
        path: '/groups',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            ChatsRoute.path,
      ),
      GoRoute(
        path: '/archive',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            ChatArchivedRoute.path,
      ),
      GoRoute(
        path: '/archived',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            ChatArchivedRoute.path,
      ),
      GoRoute(
        path: ChatArchivedRoute.path,
        name: ChatArchivedRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: ChatArchivedScreen()),
      ),
      GoRoute(
        path: ChatCreateGroupRoute.path,
        name: ChatCreateGroupRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: ChatCreateGroupScreen()),
      ),
      GoRoute(
        path: ChatNewMessageRoute.path,
        name: ChatNewMessageRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: ChatPeopleSearchScreen()),
      ),
      GoRoute(
        path: ChatFolderNewRoute.path,
        name: ChatFolderNewRoute.name,
        pageBuilder: (context, state) => MaterialPage(
          child: ChatFolderEditScreen(
            initialConversationIds:
                ChatFolderNewRoute.idsFrom(state.uri.queryParameters['c']),
            initialChannelIds:
                ChatFolderNewRoute.idsFrom(state.uri.queryParameters['ch']),
          ),
        ),
      ),
      GoRoute(
        path: ChatFolderEditRoute.path,
        name: ChatFolderEditRoute.name,
        pageBuilder: (context, state) {
          final id = parseRoutePositiveId(state.pathParameters['folderId']);
          if (id == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Папка'),
            );
          }
          return MaterialPage(child: ChatFolderEditScreen(folderId: id));
        },
      ),
      GoRoute(
        path: '/help',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SupportContactRoute.path,
      ),
      GoRoute(
        path: '/faq',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SupportContactRoute.path,
      ),
      GoRoute(
        path: '/tickets',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SupportContactRoute.path,
      ),
      GoRoute(
        path: '/about',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SupportSecurityRoute.path,
      ),
      GoRoute(
        path: '/legal',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SupportSecurityRoute.path,
      ),
      GoRoute(
        path: '/terms',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SupportSecurityRoute.path,
      ),
      GoRoute(
        path: '/inbox',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            NotificationsRoute.path,
      ),
      GoRoute(
        path: '/messages',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            ChatsRoute.path,
      ),
      GoRoute(
        path: '/dm',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            ChatsRoute.path,
      ),
      GoRoute(
        path: '/theme',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SettingsRoute.path,
      ),
      GoRoute(
        path: '/appearance',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SettingsRoute.path,
      ),
      GoRoute(
        path: '/compose',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            CreatePostRoute.path,
      ),
      GoRoute(
        path: '/write',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            CreatePostRoute.path,
      ),
      GoRoute(
        path: '/camera',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            StoryCreateRoute.path,
      ),
      GoRoute(
        path: '/folders',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            ChatFolderNewRoute.path,
      ),
      GoRoute(
        path: '/new-folder',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            ChatFolderNewRoute.path,
      ),
      GoRoute(
        path: '/sessions',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            AccountSecurityRoute.path,
      ),
      GoRoute(
        path: '/devices',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            AccountSecurityRoute.path,
      ),
      GoRoute(
        path: '/language',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SettingsRoute.path,
      ),
      GoRoute(
        path: '/lang',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SettingsRoute.path,
      ),
      GoRoute(
        path: '/data',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SettingsRoute.path,
      ),
      GoRoute(
        path: '/storage',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SettingsRoute.path,
      ),
      GoRoute(
        path: '/themes',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SettingsRoute.path,
      ),
      GoRoute(
        path: '/night',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SettingsRoute.path,
      ),
      GoRoute(
        path: '/proxy',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SettingsRoute.path,
      ),
      GoRoute(
        path: '/saved-messages',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            ProfileTabRoute.path,
      ),
      GoRoute(
        path: '/calls',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            ChatsRoute.path,
      ),
      GoRoute(
        path: '/stickers',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            ChatsRoute.path,
      ),
      GoRoute(
        path: '/blocklist',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            BlockedUsersRoute.path,
      ),
      GoRoute(
        path: '/notification-settings',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            NotificationSettingsRoute.path,
      ),
      GoRoute(
        path: '/notif-settings',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            NotificationSettingsRoute.path,
      ),
      GoRoute(
        path: '/export',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            BackupRoute.path,
      ),
      GoRoute(
        path: '/marketplace',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            StarGiftsMarketplaceRoute.path,
      ),
      GoRoute(
        path: '/qr',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            ProfileTabRoute.path,
      ),
      GoRoute(
        path: '/scan',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            ProfileTabRoute.path,
      ),
      GoRoute(
        path: '/gif',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            ChatsRoute.path,
      ),
      GoRoute(
        path: '/emoji',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            ChatsRoute.path,
      ),
      GoRoute(
        path: '/webapp',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            MiniAppsRoute.path,
      ),
      GoRoute(
        path: '/miniapp',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            MiniAppsRoute.path,
      ),
      GoRoute(
        path: '/privacy-policy',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SupportSecurityRoute.path,
      ),
      GoRoute(
        path: '/tos',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SupportSecurityRoute.path,
      ),
      GoRoute(
        path: '/cookies',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SupportSecurityRoute.path,
      ),
      GoRoute(
        path: '/settings/language',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SettingsRoute.path,
      ),
      GoRoute(
        path: '/settings/data',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SettingsRoute.path,
      ),
      GoRoute(
        path: '/settings/storage',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SettingsRoute.path,
      ),
      GoRoute(
        path: '/stats',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            AppAnalyticsRoute.path,
      ),
      GoRoute(
        path: '/insights',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            AppAnalyticsRoute.path,
      ),
      GoRoute(
        path: '/bookmarks',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SavedPostsRoute.path,
      ),
      GoRoute(
        path: '/likes',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SavedPostsRoute.path,
      ),
      GoRoute(
        path: '/mentions',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            NotificationsRoute.path,
      ),
      GoRoute(
        path: '/activity',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            NotificationsRoute.path,
      ),
      GoRoute(
        path: '/settings/backup',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            BackupRoute.path,
      ),
      GoRoute(
        path: '/settings/2fa',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            TwoFactorSetupRoute.path,
      ),
      GoRoute(
        path: '/settings/devices',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            AccountSecurityRoute.path,
      ),
      GoRoute(
        path: '/download',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SupportSecurityRoute.path,
      ),
      GoRoute(
        path: '/licenses',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SupportSecurityRoute.path,
      ),
      GoRoute(
        path: '/changelog',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SupportSecurityRoute.path,
      ),
      GoRoute(
        path: '/version',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SupportSecurityRoute.path,
      ),
      GoRoute(
        path: '/wallpaper',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SettingsRoute.path,
      ),
      GoRoute(
        path: '/autodelete',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SettingsRoute.path,
      ),
      GoRoute(
        path: '/chat-settings',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SettingsRoute.path,
      ),
      GoRoute(
        path: '/data-and-storage',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            SettingsRoute.path,
      ),
      GoRoute(
        path: '/giveaway',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            AdsHubRoute.path,
      ),
      GoRoute(
        path: '/giveaways',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            AdsHubRoute.path,
      ),
      GoRoute(
        path: '/boost',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            AdsHubRoute.path,
      ),
      GoRoute(
        path: '/botfather',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            MyBotsRoute.path,
      ),
      GoRoute(
        path: '/newbot',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            MyBotsRoute.path,
      ),
      GoRoute(
        path: '/gifts/market',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            StarGiftsMarketplaceRoute.path,
      ),
      GoRoute(
        path: '/gifts/shop',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            StarGiftsMarketplaceRoute.path,
      ),
      GoRoute(
        path: '/secret',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            AccountSecurityRoute.path,
      ),
      GoRoute(
        path: '/passcode',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            AccountSecurityRoute.path,
      ),
      GoRoute(
        path: '/passport',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            AccountSecurityRoute.path,
      ),
      GoRoute(
        path: '/poll',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            CreatePostRoute.path,
      ),
      GoRoute(
        path: '/nearby',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            ChatsRoute.path,
      ),
      GoRoute(
        path: '/new-group',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            ChatCreateGroupRoute.path,
      ),
      GoRoute(
        path: '/new-message',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            ChatNewMessageRoute.path,
      ),
      GoRoute(
        path: '/people',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            ChatNewMessageRoute.path,
      ),
      GoRoute(
        path: '/contacts',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            ChatNewMessageRoute.path,
      ),
      GoRoute(
        path: '/new-channel',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            CreateChannelRoute.path,
      ),
      GoRoute(
        path: '/new-post',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            CreatePostRoute.path,
      ),
      GoRoute(
        path: '/new-reel',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            CreateReelRoute.path,
      ),
      GoRoute(
        path: '/new-story',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            StoryCreateRoute.path,
      ),
      GoRoute(
        path: '/moments',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            StoriesRoute.path,
      ),
      GoRoute(
        path: '/constructor',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            FlexConstructorRoute.path,
      ),
      GoRoute(
        path: '/shop',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            FlexShopRoute.path,
      ),
      GoRoute(
        path: '/admin',
        redirect: (context, state) =>
            shortcutPathAlias(state.uri.path, state.uri.query) ??
            ModerationDashboardRoute.path,
      ),
      GoRoute(
        path: PaidMessageExceptionsRoute.path,
        name: PaidMessageExceptionsRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: PaidMessageExceptionsScreen()),
      ),
      GoRoute(
        path: FlexSubscriptionRoute.path,
        name: FlexSubscriptionRoute.name,
        pageBuilder: (context, state) {
          final level = int.tryParse(state.uri.queryParameters['level'] ?? '');
          return MaterialPage(
            child: FlexSubscriptionScreen(initialLevel: level ?? 0),
          );
        },
      ),
      GoRoute(
        path: FlexConstructorRoute.path,
        name: FlexConstructorRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: FlexConstructorScreen()),
      ),
      GoRoute(
        path: FlexShopRoute.path,
        name: FlexShopRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: FlexShopScreen()),
      ),
      GoRoute(
        path: AdminFlexFeaturesRoute.path,
        name: AdminFlexFeaturesRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: AdminFlexFeaturesScreen()),
      ),
      GoRoute(
        path: StarsWalletRoute.path,
        name: StarsWalletRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: StarsWalletScreen()),
      ),
      GoRoute(
        path: StarGiftsInventoryRoute.path,
        name: StarGiftsInventoryRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: StarGiftsInventoryScreen()),
      ),
      GoRoute(
        path: StarGiftsMarketplaceRoute.path,
        name: StarGiftsMarketplaceRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: StarGiftsMarketplaceScreen()),
      ),
      GoRoute(
        path: StarInvoicePayRoute.path,
        name: StarInvoicePayRoute.name,
        pageBuilder: (context, state) {
          final id = parseRoutePositiveId(state.pathParameters['invoiceId']);
          if (id == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Счёт в звёздах'),
            );
          }
          return MaterialPage(child: StarInvoicePayScreen(invoiceId: id));
        },
      ),
      GoRoute(
        path: ChannelGiveawaysRoute.path,
        name: ChannelGiveawaysRoute.name,
        pageBuilder: (context, state) {
          final id =
              int.tryParse(state.pathParameters['channelId'] ?? '') ?? 0;
          final name = state.uri.queryParameters['name'] ?? 'Канал';
          final manage = state.uri.queryParameters['manage'] == '1';
          return MaterialPage(
            child: ChannelGiveawaysScreen(
              channelId: id,
              channelName: name,
              canManage: manage,
            ),
          );
        },
      ),
      GoRoute(
        path: ChannelSuggestedPostsRoute.path,
        name: ChannelSuggestedPostsRoute.name,
        pageBuilder: (context, state) {
          final id =
              int.tryParse(state.pathParameters['channelId'] ?? '') ?? 0;
          final name = state.uri.queryParameters['name'] ?? 'Канал';
          final manage = state.uri.queryParameters['manage'] == '1';
          final owner = state.uri.queryParameters['owner'] == '1';
          return MaterialPage(
            child: ChannelSuggestedPostsScreen(
              channelId: id,
              channelName: name,
              canManage: manage,
              isOwner: owner,
            ),
          );
        },
      ),
      GoRoute(
        path: StarsCheckoutSuccessRoute.path,
        name: StarsCheckoutSuccessRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: StarsCheckoutSuccessScreen()),
      ),
      GoRoute(
        path: StarsCheckoutCancelRoute.path,
        name: StarsCheckoutCancelRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: StarsCheckoutCancelScreen()),
      ),
      GoRoute(
        path: CreatorRevenueRoute.path,
        name: CreatorRevenueRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: CreatorRevenueScreen()),
      ),
      GoRoute(
        path: MyBotsRoute.path,
        name: MyBotsRoute.name,
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: MyBotsScreen()),
      ),
      GoRoute(
        path: BotDetailRoute.path,
        name: BotDetailRoute.name,
        redirect: (context, state) {
          final id = int.tryParse(state.pathParameters['botId'] ?? '') ?? 0;
          if (id <= 0) return null;
          final section =
              (state.uri.queryParameters['section'] ?? '').toLowerCase();
          final username = state.uri.queryParameters['u'];
          return switch (section) {
            'commands' || 'command' =>
              BotCommandsRoute.pathFor(id, username: username),
            'miniapps' || 'mini_apps' || 'apps' =>
              BotMiniAppsRoute.pathFor(id, username: username),
            'newapp' || 'new_app' => BotMiniAppsRoute.pathFor(
                id,
                username: username,
                newApp: true,
              ),
            _ => null,
          };
        },
        pageBuilder: (context, state) {
          final id = int.tryParse(state.pathParameters['botId'] ?? '') ?? 0;
          final username = state.uri.queryParameters['u'] ?? 'bot';
          final sectionRaw =
              (state.uri.queryParameters['section'] ?? '').toLowerCase();
          final section = switch (sectionRaw) {
            'token' => BotDetailOpenSection.token,
            _ => BotDetailOpenSection.none,
          };
          final extra = state.extra;
          final token = extra is String && extra.trim().isNotEmpty
              ? extra.trim()
              : null;
          return NoTransitionPage(
            child: BotDetailScreen(
              botId: id,
              botUsername: username,
              openSection: section,
              initialToken: token,
              showTokenOnOpen:
                  token != null || section == BotDetailOpenSection.token,
            ),
          );
        },
      ),
      GoRoute(
        path: BotCommandsRoute.path,
        name: BotCommandsRoute.name,
        pageBuilder: (context, state) {
          final id = int.tryParse(state.pathParameters['botId'] ?? '') ?? 0;
          final username = state.uri.queryParameters['u'] ?? 'bot';
          final extra = state.extra;
          final initial = extra is List<BotCommandCreate>
              ? extra
              : const <BotCommandCreate>[];
          return NoTransitionPage(
            child: BotCommandsScreen(
              botId: id,
              botUsername: username,
              initialCommands: initial,
            ),
          );
        },
      ),
      GoRoute(
        path: BotMiniAppsRoute.path,
        name: BotMiniAppsRoute.name,
        pageBuilder: (context, state) {
          final id = int.tryParse(state.pathParameters['botId'] ?? '') ?? 0;
          final username = state.uri.queryParameters['u'] ?? 'bot';
          final newRaw =
              (state.uri.queryParameters['new'] ?? '').toLowerCase();
          return NoTransitionPage(
            child: BotMiniAppsScreen(
              botId: id,
              botUsername: username,
              autoNewApp: newRaw == '1' || newRaw == 'true',
            ),
          );
        },
      ),
      GoRoute(
        path: SubscriptionSuccessRoute.path,
        name: SubscriptionSuccessRoute.name,
        pageBuilder: (context, state) {
          final sessionId = state.uri.queryParameters['session_id'];
          return MaterialPage(
            child: SubscriptionSuccessScreen(sessionId: sessionId),
          );
        },
      ),
      GoRoute(
        path: SubscriptionCancelRoute.path,
        name: SubscriptionCancelRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: SubscriptionCancelScreen()),
      ),
      GoRoute(
        path: SupportSecurityRoute.path,
        name: SupportSecurityRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: SupportSecurityScreen()),
      ),
      GoRoute(
        path: BackupRoute.path,
        name: BackupRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: BackupPage()),
      ),
      // Auth маршруты
      GoRoute(
        path: '/invite',
        name: 'invite',
        redirect: (context, state) {
          final ref = PendingReferral.queryRef(state.uri);
          if (ref != null && ref.isNotEmpty) {
            unawaited(PendingReferralStore.remember(ref));
          }
          if (AuthService.instance.currentUser != null) {
            return PartnerProgramRoute.path;
          }
          if (ref != null && ref.isNotEmpty) {
            return '${RegisterRoute.path}?ref=${Uri.encodeComponent(ref)}';
          }
          return RegisterRoute.path;
        },
      ),
      GoRoute(
        path: ChatInviteJoinRoute.path,
        name: ChatInviteJoinRoute.name,
        pageBuilder: (context, state) {
          final token = state.pathParameters['token'] ?? '';
          return MaterialPage(
            child: ChatInviteJoinScreen(token: token),
          );
        },
      ),
      GoRoute(
        path: UsernameDeepLinkRoute.path,
        name: UsernameDeepLinkRoute.name,
        pageBuilder: (context, state) {
          final username = state.pathParameters['username'] ?? '';
          return MaterialPage(
            child: UsernameDeepLinkScreen(username: username),
          );
        },
      ),
      GoRoute(
        path: LoginRoute.path,
        name: LoginRoute.name,
        pageBuilder: (context, state) => const NoTransitionPage(
          key: ValueKey('login'),
          child: LoginScreen(),
        ),
      ),
      GoRoute(
        path: RegisterRoute.path,
        name: RegisterRoute.name,
        pageBuilder: (context, state) => MaterialPage(
          child: RegisterScreen(
            initialReferralCode: PendingReferral.queryRef(state.uri),
          ),
        ),
      ),
      GoRoute(
        path: LegalConsentRoute.path,
        name: LegalConsentRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: LegalConsentScreen()),
      ),
      GoRoute(
        path: ForgotPasswordRoute.path,
        name: ForgotPasswordRoute.name,
        pageBuilder: (context, state) {
          final email = state.uri.queryParameters['email'];
          return MaterialPage(
            child: ForgotPasswordScreen(initialEmail: email),
          );
        },
      ),
      GoRoute(
        path: ResetPasswordRoute.path,
        name: ResetPasswordRoute.name,
        pageBuilder: (context, state) {
          final token = state.uri.queryParameters['token'];
          final email = state.uri.queryParameters['email'];
          return MaterialPage(
            child: ResetPasswordScreen(
              initialToken: token,
              initialEmail: email,
            ),
          );
        },
      ),
      GoRoute(
        path: VerifyEmailRoute.path,
        name: VerifyEmailRoute.name,
        pageBuilder: (context, state) {
          final email = state.uri.queryParameters['email'];
          final token = state.uri.queryParameters['token'];
          return MaterialPage(
            child: VerifyEmailScreen(email: email, initialToken: token),
          );
        },
      ),
      GoRoute(
        path: TwoFactorVerifyRoute.path,
        name: TwoFactorVerifyRoute.name,
        pageBuilder: (context, state) {
          final extra = state.extra;
          String pending = '';
          String? email;
          if (extra is Map) {
            pending = extra['pendingToken'] as String? ?? '';
            email = extra['email'] as String?;
          }
          if (pending.isEmpty) {
            return const MaterialPage(child: LoginScreen());
          }
          return MaterialPage(
            child: TwoFactorVerifyScreen(
              pendingToken: pending,
              email: email,
            ),
          );
        },
      ),
      GoRoute(
        path: ConfirmEmailChangeRoute.path,
        name: ConfirmEmailChangeRoute.name,
        pageBuilder: (context, state) {
          final token = state.uri.queryParameters['token'] ?? '';
          final email = state.uri.queryParameters['email'];
          return MaterialPage(
            child: ConfirmEmailChangeScreen(token: token, email: email),
          );
        },
      ),
      GoRoute(
        path: AccountSecurityRoute.path,
        name: AccountSecurityRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: AccountSecurityScreen()),
      ),
      GoRoute(
        path: TwoFactorSetupRoute.path,
        name: TwoFactorSetupRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: TwoFactorSetupScreen()),
      ),
      GoRoute(
        path: CloseFriendsRoute.path,
        name: CloseFriendsRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: CloseFriendsScreen()),
      ),
      // Profile
      GoRoute(
        path: SavedPostsRoute.path,
        name: SavedPostsRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: SavedPostsScreen()),
      ),
      GoRoute(
        path: ProfileRoute.path,
        name: ProfileRoute.name,
        pageBuilder: (context, state) {
          final userId = state.uri.queryParameters['userId'];
          return MaterialPage(
            child: ProfileScreen(
              userId: userId != null ? int.tryParse(userId) : null,
            ),
          );
        },
      ),
      GoRoute(
        path: ProfileFollowersRoute.path,
        name: ProfileFollowersRoute.name,
        pageBuilder: (context, state) {
          final id = parseRoutePositiveId(state.uri.queryParameters['userId']);
          if (id == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Подписчики'),
            );
          }
          return MaterialPage(
            child: FollowListScreen(userId: id, type: FollowListType.followers),
          );
        },
      ),
      GoRoute(
        path: ProfileFollowingRoute.path,
        name: ProfileFollowingRoute.name,
        pageBuilder: (context, state) {
          final id = parseRoutePositiveId(state.uri.queryParameters['userId']);
          if (id == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Подписки'),
            );
          }
          return MaterialPage(
            child: FollowListScreen(userId: id, type: FollowListType.following),
          );
        },
      ),
      // Create Post
      GoRoute(
        path: CreatePostRoute.path,
        name: CreatePostRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: CreatePostScreen()),
      ),
            GoRoute(
        path: CreateReelRoute.path,
        name: CreateReelRoute.name,
        pageBuilder: (context, state) {
          final channelId =
              parseRoutePositiveId(state.uri.queryParameters['channelId']);
          final channelName = state.uri.queryParameters['channelName'];
          return MaterialPage(
            child: CommunityUploadScreen(
              channelId: channelId,
              channelName: channelName,
            ),
          );
        },
      ),
      GoRoute(
        path: '/post/:postId/edit',
        name: 'edit_profile_post',
        pageBuilder: (context, state) {
          final postId = parseRoutePositiveId(state.pathParameters['postId']);
          if (postId == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Пост'),
            );
          }
          return MaterialPage(
            child: EditProfilePostScreen(postId: postId),
          );
        },
      ),
      // Comments
      GoRoute(
        path: '/post/:postId/comments',
        name: 'post_comments',
        pageBuilder: (context, state) {
          final postId = parseRoutePositiveId(state.pathParameters['postId']);
          if (postId == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Комментарии'),
            );
          }
          return CustomTransitionPage<void>(
            key: state.pageKey,
            fullscreenDialog: true,
            transitionDuration: const Duration(milliseconds: 280),
            reverseTransitionDuration: const Duration(milliseconds: 220),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              );
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              );
            },
            child: CommentsScreen(postId: postId),
          );
        },
      ),
      GoRoute(
        path: '/post/:postId',
        name: 'post_by_id',
        pageBuilder: (context, state) {
          final postId = int.tryParse(state.pathParameters['postId'] ?? '');
          if (postId == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Пост'),
            );
          }
          return MaterialPage(child: PostByIdScreen(postId: postId));
        },
      ),
      // Channels
      GoRoute(
        path: '/channel/:channelId',
        name: 'channel_page',
        parentNavigatorKey: hanEatRootNavigatorKey,
        pageBuilder: (context, state) {
          final channelId =
              parseRoutePositiveId(state.pathParameters['channelId']);
          if (channelId == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Канал'),
            );
          }
          return CupertinoPage<void>(
            key: state.pageKey,
            child: ChannelDetailScreen(channelId: channelId),
          );
        },
      ),
      GoRoute(
        path: ChannelSearchRoute.path,
        name: ChannelSearchRoute.name,
        pageBuilder: (context, state) {
          final channelId =
              parseRoutePositiveId(state.pathParameters['channelId']);
          if (channelId == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Поиск по каналу'),
            );
          }
          final extra = state.extra;
          return MaterialPage<void>(
            child: ChannelSearchScreen(
              channelId: channelId,
              initialQuery: state.uri.queryParameters['q'] ?? '',
              channel: extra is ChannelDetail ? extra : null,
            ),
          );
        },
      ),
      GoRoute(
        path: '/channel/:channelId/info',
        name: 'channel_info',
        pageBuilder: (context, state) {
          final channelId =
              parseRoutePositiveId(state.pathParameters['channelId']);
          if (channelId == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Канал'),
            );
          }
          return MaterialPage<void>(
            child: ChannelInfoScreen(channelId: channelId),
          );
        },
      ),
      GoRoute(
        path: '/channel/:channelId/subscribers',
        name: 'channel_subscribers',
        pageBuilder: (context, state) {
          final channelId =
              parseRoutePositiveId(state.pathParameters['channelId']);
          if (channelId == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Подписчики канала'),
            );
          }
          return MaterialPage<void>(
            child: ChannelSubscribersScreen(
              channelId: channelId,
              channelName: state.uri.queryParameters['channelName'],
            ),
          );
        },
      ),
      GoRoute(
        path: '/channel/:channelId/post/:postId',
        name: 'channel_post_detail',
        pageBuilder: (context, state) {
          final channelId =
              parseRoutePositiveId(state.pathParameters['channelId']);
          final postId = parseRoutePositiveId(state.pathParameters['postId']);
          if (channelId == null || postId == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Пост канала'),
            );
          }
          return MaterialPage(
            child: ChannelPostDetailScreen(
              channelId: channelId,
              postId: postId,
            ),
          );
        },
      ),
      GoRoute(
        path: ChannelsManagementRoute.path,
        name: ChannelsManagementRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: ChannelsManagementScreen()),
      ),
      GoRoute(
        path: CreateChannelRoute.path,
        name: CreateChannelRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: CreateChannelScreen()),
      ),
            GoRoute(
        path: '/channel/:channelId/create-post',
        name: 'create_channel_post',
        pageBuilder: (context, state) {
          final channelId =
              parseRoutePositiveId(state.pathParameters['channelId']);
          if (channelId == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Канал'),
            );
          }
          final postType = state.uri.queryParameters['type'] ?? 'text';
          return MaterialPage(
            fullscreenDialog: true,
            child: CreateChannelPostScreen(
              channelId: channelId,
              postType: postType,
            ),
          );
        },
      ),
      GoRoute(
        path: '/channel/:channelId/post/:postId/edit',
        name: 'edit_channel_post',
        pageBuilder: (context, state) {
          final channelId =
              parseRoutePositiveId(state.pathParameters['channelId']);
          final postId = parseRoutePositiveId(state.pathParameters['postId']);
          if (channelId == null || postId == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Редактирование поста'),
            );
          }
          final extra = state.extra;
          final Map<String, dynamic>? postData = extra is Map<String, dynamic>
              ? extra
              : extra is PostModel
                  ? extra.toJson()
                  : null;
          return MaterialPage(
            fullscreenDialog: true,
            child: CreateChannelPostScreen(
              channelId: channelId,
              postId: postId,
              postData: postData,
              postType: postData?['type'] ?? 'text',
            ),
          );
        },
      ),
      GoRoute(
        path: '/channel/:channelId/settings',
        name: 'channel_settings',
        pageBuilder: (context, state) {
          final channelId =
              parseRoutePositiveId(state.pathParameters['channelId']);
          if (channelId == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Настройки канала'),
            );
          }
          final channelName =
              state.uri.queryParameters['channelName'] ?? 'канал';
          return MaterialPage(
            child: ChannelSettingsScreen(
              channelId: channelId,
              channelName: channelName,
            ),
          );
        },
      ),
      GoRoute(
        path: '/channel/:channelId/management',
        name: 'channel_management',
        pageBuilder: (context, state) {
          final channelId =
              parseRoutePositiveId(state.pathParameters['channelId']);
          if (channelId == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Управление каналом'),
            );
          }
          return MaterialPage(
            child: ChannelManagementScreen(channelId: channelId),
          );
        },
      ),
      GoRoute(
        path: '/channel/:channelId/giveaways',
        redirect: (context, state) =>
            channelPaidPathAlias(state.uri.path, state.uri.query) ??
            FeedRoute.path,
      ),
      GoRoute(
        path: '/channel/:channelId/suggested-posts',
        redirect: (context, state) =>
            channelPaidPathAlias(state.uri.path, state.uri.query) ??
            FeedRoute.path,
      ),
      // Notifications List (удален дубликат - используется NotificationsRoute выше)
      // Support
      GoRoute(
        path: SupportContactRoute.path,
        name: SupportContactRoute.name,
        pageBuilder: (context, state) {
          final subject = state.uri.queryParameters['subject'];
          final message = state.uri.queryParameters['message'];
          final type = state.uri.queryParameters['type'];
          return MaterialPage<void>(
            child: SupportScreen(
              initialSubject: subject,
              initialMessage: message,
              initialType: type,
            ),
          );
        },
      ),
      // Analytics
      GoRoute(
        path: AppAnalyticsRoute.path,
        name: AppAnalyticsRoute.name,
        pageBuilder: (context, state) {
          final postId = state.uri.queryParameters['postId'];
          return MaterialPage(
            child: AnalyticsScreen(
              postId: postId != null ? int.tryParse(postId) : null,
            ),
          );
        },
      ),
      // Moderation
      GoRoute(
        path: ModerationDashboardRoute.path,
        name: ModerationDashboardRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: ModerationDashboardScreen()),
      ),
      GoRoute(
        path: ModerationQueueRoute.path,
        name: ModerationQueueRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: ModerationQueueScreen()),
      ),
      GoRoute(
        path: MiniAppsModerationRoute.path,
        name: MiniAppsModerationRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: MiniAppsModerationScreen()),
      ),
      GoRoute(
        path: AdminRefundQueueRoute.path,
        name: AdminRefundQueueRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: AdminRefundQueueScreen()),
      ),
      GoRoute(
        path: AdminPartnerPayoutsRoute.path,
        name: AdminPartnerPayoutsRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: AdminPartnerPayoutsScreen()),
      ),
      GoRoute(
        path: AdminCreatorPayoutsRoute.path,
        name: AdminCreatorPayoutsRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: AdminCreatorPayoutsScreen()),
      ),
      GoRoute(
        path: AdminSupportTicketsRoute.path,
        name: AdminSupportTicketsRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: AdminSupportTicketsScreen()),
      ),
      // Легаси: /community → главная лента; избранное — отдельный маршрут
      GoRoute(
        path: CommunityRoute.path,
        name: CommunityRoute.name,
        redirect: (context, state) => FeedRoute.path,
      ),
            GoRoute(
        path: UserSearchRoute.path,
        name: UserSearchRoute.name,
        // Legacy alias — same UI as SearchRoute.
        redirect: (context, state) => SearchRoute.path,
      ),
      GoRoute(
        path: ChatMediaGalleryRoute.path,
        name: ChatMediaGalleryRoute.name,
        parentNavigatorKey: hanEatRootNavigatorKey,
        pageBuilder: (context, state) {
          final id =
              parseRoutePositiveId(state.pathParameters['conversationId']);
          if (id == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Медиа чата'),
            );
          }
          return MaterialPage(
            child: ChatMediaGalleryScreen(conversationId: id),
          );
        },
      ),
      GoRoute(
        path: ChatGroupModerationLogRoute.path,
        name: ChatGroupModerationLogRoute.name,
        parentNavigatorKey: hanEatRootNavigatorKey,
        pageBuilder: (context, state) {
          final id =
              parseRoutePositiveId(state.pathParameters['conversationId']);
          if (id == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'История модерации'),
            );
          }
          final extra = state.extra;
          return MaterialPage(
            child: ChatGroupModerationLogScreen(
              conversationId: id,
              conversation: extra is ChatConversation ? extra : null,
            ),
          );
        },
      ),
      GoRoute(
        path: ChatGroupInfoRoute.path,
        name: ChatGroupInfoRoute.name,
        parentNavigatorKey: hanEatRootNavigatorKey,
        pageBuilder: (context, state) {
          final id =
              parseRoutePositiveId(state.pathParameters['conversationId']);
          if (id == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'О группе'),
            );
          }
          final extra = state.extra;
          return MaterialPage(
            child: ChatGroupInfoLoaderScreen(
              conversationId: id,
              initialConversation:
                  extra is ChatConversation ? extra : null,
            ),
          );
        },
      ),
      GoRoute(
        path: StickerPackManageRoute.path,
        name: StickerPackManageRoute.name,
        pageBuilder: (context, state) {
          final raw = state.pathParameters['packId'] ?? '';
          final id = parseRoutePositiveId(raw);
          if (id != null) {
            return MaterialPage(child: StickerPackManageScreen(packId: id));
          }
          if (raw.trim().isNotEmpty) {
            return MaterialPage(
              child: StickerPackPreviewScreen(slug: raw.trim()),
            );
          }
          return const MaterialPage(
            child: InvalidLinkScreen(title: 'Стикеры'),
          );
        },
      ),
      GoRoute(
        path: StickerPackPreviewRoute.path,
        name: StickerPackPreviewRoute.name,
        pageBuilder: (context, state) {
          final slug = state.pathParameters['slug']?.trim() ?? '';
          if (slug.isEmpty) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Стикеры'),
            );
          }
          return MaterialPage(child: StickerPackPreviewScreen(slug: slug));
        },
      ),
      GoRoute(
        path: '${ChatThreadRoute.path}/:conversationId',
        name: ChatThreadRoute.name,
        parentNavigatorKey: hanEatRootNavigatorKey,
        pageBuilder: (context, state) {
          final id = int.tryParse(state.pathParameters['conversationId'] ?? '');
          final extra = state.extra;
          final openArgs = extra is ChatThreadOpenArgs ? extra : null;
          final initialConversation = openArgs?.conversation ??
              (extra is ChatConversation ? extra : null);
          final initialPeer =
              openArgs?.peer ?? (extra is ChatUserBrief ? extra : null);
          if (id == null) {
            return MaterialPage(
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('Чат'),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Назад',
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go(ChatsRoute.path);
                      }
                    },
                  ),
                ),
                body: AppEmptyState(
                  icon: Icons.chat_bubble_outline,
                  title: 'Чат не найден',
                  subtitle: 'Ссылка устарела или диалог недоступен',
                  action: FilledButton(
                    onPressed: () => context.go(ChatsRoute.path),
                    child: const Text('К чатам'),
                  ),
                ),
              ),
            );
          }
          final msgParam = state.uri.queryParameters['msg'];
          final jumpFromQuery = int.tryParse(msgParam ?? '');
          final callRaw =
              (state.uri.queryParameters['call'] ?? '').toLowerCase();
          final initialCallMedia = switch (callRaw) {
            'voice' || 'audio' || 'phone' => 'voice',
            'video' || 'cam' || 'camera' => 'video',
            _ => null,
          };
          return CupertinoPage<void>(
            key: state.pageKey,
            child: ChatThreadLoaderScreen(
              conversationId: id,
              initialConversation: initialConversation,
              initialPeer: initialPeer,
              initialJumpMessageId:
                  openArgs?.jumpToMessageId ?? jumpFromQuery,
              initialDraftText: openArgs?.initialDraftText,
              initialPrivateReply: openArgs?.initialPrivateReply,
              initialCallMedia: initialCallMedia,
            ),
          );
        },
      ),
      // Search
      GoRoute(
        path: SearchRoute.path,
        name: SearchRoute.name,
        pageBuilder: (context, state) {
          final params = state.uri.queryParameters;
          return MaterialPage<void>(
            child: SearchScreen(
              initialQuery: params['q'],
              scope: searchScopeFromQuery(params['scope']),
              feedType: params['feed_type'],
              followingOnly: params['following'] == '1',
            ),
          );
        },
      ),
      // Deep link https://haneat.app/reel/28
      GoRoute(
        path: ReelByIdRoute.path,
        name: ReelByIdRoute.name,
        parentNavigatorKey: hanEatRootNavigatorKey,
        pageBuilder: (context, state) {
          final postId = parseRoutePositiveId(state.pathParameters['postId']);
          if (postId == null) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Рилс'),
            );
          }
          return CustomTransitionPage<void>(
            key: state.pageKey,
            fullscreenDialog: true,
            transitionDuration: const Duration(milliseconds: 280),
            reverseTransitionDuration: const Duration(milliseconds: 220),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              );
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              );
            },
            child: ReelByIdScreen(postId: postId),
          );
        },
      ),
      // Reels Feed
      GoRoute(
        path: ReelsRoute.path,
        name: ReelsRoute.name,
        pageBuilder: (context, state) =>
            const MaterialPage(child: ReelsFeedScreen()),
      ),
      // Reels Fullscreen (при тапе на видео в ленте — поверх shell, без нижней панели)
      GoRoute(
        path: ReelsFullscreenRoute.path,
        name: ReelsFullscreenRoute.name,
        parentNavigatorKey: hanEatRootNavigatorKey,
        pageBuilder: (context, state) {
          final extra = state.extra;
          if (extra is! PostModel) {
            return const MaterialPage(
              child: InvalidLinkScreen(title: 'Рилс'),
            );
          }
          return MaterialPage(
            child: ReelsFullscreenScreen(initialPost: extra),
          );
        },
      ),
    ],
    errorPageBuilder: (context, state) {
      if (isGoRouterShellLocation(state.uri.path) ||
          isGoRouterShellLocation(state.matchedLocation)) {
        return const MaterialPage(child: _SilentShellRedirect());
      }
      return MaterialPage(
        child: _RouterRecoveryScreen(error: state.error),
      );
    },
  );
});

/// `/app/` попал в GoRouter — сразу домой, без экрана «ошибка маршрута».
class _SilentShellRedirect extends StatefulWidget {
  const _SilentShellRedirect();

  @override
  State<_SilentShellRedirect> createState() => _SilentShellRedirectState();
}

class _SilentShellRedirectState extends State<_SilentShellRedirect> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final user = AuthService.instance.currentUser;
      if (user != null) FeedShellLaunch.skipReelsTab = true;
      context.go(user == null ? LoginRoute.path : FeedRoute.path);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF0F1319),
      child: SizedBox.expand(),
    );
  }
}

class _RouterRecoveryScreen extends StatefulWidget {
  const _RouterRecoveryScreen({this.error});

  final Object? error;

  @override
  State<_RouterRecoveryScreen> createState() => _RouterRecoveryScreenState();
}

class _RouterRecoveryScreenState extends State<_RouterRecoveryScreen> {
  bool _redirected = false;
  bool _redirectedSecondPass = false;
  bool _forcedLogout = false;

  String get _stableHomePath =>
      FeedRoute.path;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (!mounted || _redirected) return;
      _redirected = true;
      final user = AuthService.instance.currentUser;
      context.go(user == null ? LoginRoute.path : _stableHomePath);
    });
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (!mounted || !_redirected || _redirectedSecondPass) return;
      _redirectedSecondPass = true;
      final user = AuthService.instance.currentUser;
      context.go(user == null ? LoginRoute.path : _stableHomePath);
    });
    Future<void>.delayed(const Duration(seconds: 12), () {
      if (!mounted || _forcedLogout) return;
      // Ещё одна попытка домой. Logout здесь выкидывал из сессии на
      // медленном Safari, если / ещё не успел средиректить.
      _forcedLogout = true;
      final user = AuthService.instance.currentUser;
      context.go(user == null ? LoginRoute.path : _stableHomePath);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1319),
      appBar: AppBar(
        title: const Text('Восстановление'),
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Назад',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              final user = AuthService.instance.currentUser;
              context.go(user == null ? LoginRoute.path : _stableHomePath);
            }
          },
        ),
      ),
      body: AppEmptyState(
        icon: Icons.sync_problem_rounded,
        title: 'Восстанавливаем экран',
        subtitle: kDebugMode
            ? '${widget.error}'
            : 'Обнаружена ошибка маршрута. Выполняем автоматический возврат.',
        action: FilledButton(
          onPressed: () {
            final user = AuthService.instance.currentUser;
            context.go(user == null ? LoginRoute.path : _stableHomePath);
          },
          child: const Text('Продолжить'),
        ),
      ),
    );
  }
}


class CommunityRoute {
  static const path = '/community';
  static const name = 'community';
}

class ModerationDashboardRoute {
  static const path = '/moderation-dashboard';
  static const name = 'moderation_dashboard';
}

class ModerationQueueRoute {
  static const path = '/moderation';
  static const name = 'moderation';
}

class MiniAppsModerationRoute {
  static const path = '/moderation/miniapps';
  static const name = 'moderation_miniapps';
}

class AdminRefundQueueRoute {
  static const path = '/admin/refunds';
  static const name = 'admin_refunds';
}

class AdminPartnerPayoutsRoute {
  static const path = '/admin/partner-payouts';
  static const name = 'admin_partner_payouts';
}

class AdminCreatorPayoutsRoute {
  static const path = '/admin/creator-payouts';
  static const name = 'admin_creator_payouts';
}

class AdminSupportTicketsRoute {
  static const path = '/admin/support-tickets';
  static const name = 'admin_support_tickets';
}


class UserSearchRoute {
  static const path = '/users';
  static const name = 'user_search';
}

class ChannelsListRoute {
  static const path = '/channels';
  static const name = 'channels';
}

class FeedRoute {
  static const path = '/feed';
  static const name = 'feed';
}

class WebSocialHomeRoute {
  static const path = '/web-home';
  static const name = 'web_home';
}

class WebSessionLandingRoute {
  static const path = '/web-session';
  static const name = 'web_session';
}

class ChatsRoute {
  static const path = '/chats';
  static const name = 'chats';
}

class ChatArchivedRoute {
  static const path = '/chats/archived';
  static const name = 'chat_archived';
}

class ChatCreateGroupRoute {
  static const path = '/chats/new-group';
  static const name = 'chat_create_group';
}

class ChatNewMessageRoute {
  static const path = '/chats/new';
  static const name = 'chat_new_message';
}

class ChatFolderNewRoute {
  static const path = '/chats/folders/new';
  static const name = 'chat_folder_new';

  static String pathFor({
    List<int> conversationIds = const [],
    List<int> channelIds = const [],
  }) {
    final params = <String, String>{
      if (conversationIds.isNotEmpty) 'c': conversationIds.join(','),
      if (channelIds.isNotEmpty) 'ch': channelIds.join(','),
    };
    if (params.isEmpty) return path;
    return '$path?${params.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
  }

  static List<int> idsFrom(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    return raw
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .where((id) => id > 0)
        .toList();
  }
}

class ChatFolderEditRoute {
  static const path = '/chats/folders/:folderId';
  static const name = 'chat_folder_edit';

  static String pathFor(int folderId) => '/chats/folders/$folderId';
}

class ChatMediaGalleryRoute {
  static const path = '/chats/thread/:conversationId/media';
  static const name = 'chat_media_gallery';

  static String pathFor(int conversationId) =>
      '/chats/thread/$conversationId/media';
}

class ChatGroupInfoRoute {
  static const path = '/chats/thread/:conversationId/info';
  static const name = 'chat_group_info';

  static String pathFor(int conversationId) =>
      '/chats/thread/$conversationId/info';
}

class ChatGroupModerationLogRoute {
  static const path = '/chats/thread/:conversationId/log';
  static const name = 'chat_group_moderation_log';

  static String pathFor(int conversationId) =>
      '/chats/thread/$conversationId/log';
}

class StickerPackManageRoute {
  static const path = '/stickers/:packId';
  static const name = 'sticker_pack_manage';

  static String pathFor(int packId) => '/stickers/$packId';
}

class StickerPackPreviewRoute {
  static const path = '/addstickers/:slug';
  static const name = 'sticker_pack_preview';

  static String pathFor(String slug) =>
      '/addstickers/${Uri.encodeComponent(slug)}';
}

class MiniAppsRoute {
  static const path = '/mini-apps';
  static const name = 'mini_apps';
}

class MiniAppOpenRoute {
  static const path = '/webapp/:miniAppId';
  static const name = 'mini_app_open';

  static String pathFor(int miniAppId, {int? conversationId, String? start}) {
    final params = <String, String>{
      if (conversationId != null) 'chat': '$conversationId',
      if (start != null && start.trim().isNotEmpty) 'start': start.trim(),
    };
    if (params.isEmpty) return '/webapp/$miniAppId';
    return Uri(
      path: '/webapp/$miniAppId',
      queryParameters: params,
    ).toString();
  }
}

class DonateRoute {
  static const path = '/donate';
  static const name = 'donate';

  static String pathFor({
    required int recipientId,
    required String recipientName,
    int? channelId,
    int? postId,
    String? channelName,
  }) {
    final params = <String, String>{
      'to': '$recipientId',
      if (recipientName.trim().isNotEmpty) 'name': recipientName.trim(),
      if (channelId != null) 'channel': '$channelId',
      if (postId != null) 'post': '$postId',
      if (channelName != null && channelName.trim().isNotEmpty)
        'channelName': channelName.trim(),
    };
    return Uri(path: path, queryParameters: params).toString();
  }
}

class StoriesRoute {
  static const path = '/stories';
  static const name = 'stories';
}

class StoryCreateRoute {
  static const path = '/stories/create';
  static const name = 'story_create';
}

class StoryViewerRoute {
  static const path = '/stories/:storyId';
  static const name = 'story_viewer';

  static String pathFor(int storyId) => '/stories/$storyId';
}

class ChannelSearchRoute {
  static const path = '/channel/:channelId/search';
  static const name = 'channel_search';

  static String pathFor(int channelId, {String? query}) {
    final q = query?.trim() ?? '';
    if (q.isEmpty) return '/channel/$channelId/search';
    return '/channel/$channelId/search?q=${Uri.encodeQueryComponent(q)}';
  }
}

class ChatThreadRoute {
  static const path = '/chats/thread';
  static const name = 'chat_thread';

  static String pathFor(ChatConversation conv) => '$path/${conv.id}';

  static String pathForId(int conversationId) => '$path/$conversationId';
}

class ChatInviteJoinRoute {
  static const path = '/chat-invite/:token';
  static const basePath = '/chat-invite';
  static const name = 'chat_invite_join';
}

class UsernameDeepLinkRoute {
  static const path = '/u/:username';
  static const basePath = '/u';
  static const name = 'username_deep_link';

  static String pathFor(String username) {
    final handle = username.trim().replaceFirst(RegExp(r'^@'), '');
    return '$basePath/${Uri.encodeComponent(handle)}';
  }
}

class ChatThreadOpenArgs {
  const ChatThreadOpenArgs({
    this.conversation,
    this.peer,
    this.jumpToMessageId,
    this.initialDraftText,
    this.initialPrivateReply,
  });

  final ChatConversation? conversation;
  final ChatUserBrief? peer;
  final int? jumpToMessageId;
  final String? initialDraftText;
  /// Telegram-like "Reply privately" quote strip when opening a DM.
  final ChatPrivateReplyQuote? initialPrivateReply;
}

/// Вкладка «Профиль» в нижней навигации (хаб, не путать с [ProfileRoute] ленты профиля).
class ProfileTabRoute {
  static const path = '/me';
  static const name = 'profile_tab';
}

class SavedPostsRoute {
  static const path = '/saved-posts';
  static const name = 'saved_posts';
}


bool _isRetiredKitchenPath(String loc) {
  if (loc == MenuRoute.path ||
      loc == CreateRecipeRoute.path ||
      loc == '/create-recipe' ||
      loc == '/meal-plan' ||
      loc.startsWith('/meal-plan/') ||
      loc == '/shopping' ||
      loc == '/shopping-list' ||
      loc == '/shopping-import' ||
      loc == '/categories' ||
      loc == '/allergies' ||
      loc == '/diet' ||
      loc == '/diet-allergies' ||
      loc == '/favorites' ||
      loc == '/scan-result' ||
      loc == '/cooking-mode' ||
      loc.startsWith('/recipe/')) {
    return true;
  }
  return loc.startsWith('/channel/') && loc.contains('/create-recipe');
}

/// Legacy kitchen paths (redirect to feed).
class MenuRoute {
  static const path = '/menu';
}

class CreateRecipeRoute {
  static const path = '/create-recipe';
}

class SettingsRoute {
  static const path = '/settings';
  static const name = 'settings';
}

class BlockedUsersRoute {
  static const path = '/settings/blocked';
  static const name = 'blocked_users';
}

class PaidMessageExceptionsRoute {
  static const path = '/settings/paid-exceptions';
  static const name = 'paid_message_exceptions';
}









class ProfileAuthRoute {
  static const path = '/profile-auth';
  static const name = 'profile_auth';
}





class NotificationsRoute {
  static const path = '/notifications';
  static const name = 'notifications';
}

class NotificationSettingsRoute {
  static const path = '/settings/notifications';
  static const name = 'notification_settings';
}

class CreatorToolsRoute {
  static const path = '/creator/tools';
  static const name = 'creator_tools';
}

class ScheduledPostsRoute {
  static const path = '/creator/scheduled-posts';
  static const name = 'scheduled_posts';
}

class PromotedPostsRoute {
  static const path = '/creator/promoted-posts';
  static const name = 'promoted_posts';
}

class AdsHubRoute {
  static const path = '/ads';
  static const name = 'ads_hub';
}

class PartnerProgramRoute {
  static const path = '/settings/referral';
  static const name = 'partner_program';
}

class ExtraAdsRoute {
  static const path = '/settings/extra-ads';
  static const name = 'extra_ads';
}

class AdsCampaignEditorRoute {
  static const path = '/ads/new';
  static const name = 'ads_campaign_new';
  static const editPath = '/ads/:campaignId';
  static const editName = 'ads_campaign_edit';

  static String pathFor(int campaignId) => '/ads/$campaignId';
}

class AdsReviewRoute {
  static const path = '/moderation/ads';
  static const name = 'ads_review';
}

class SubscriptionRoute {
  static const path = '/subscription';
  static const name = 'subscription';

  static String pathWithProduct(String product) =>
      '$path?product=${Uri.encodeComponent(product)}';
}

class FlexSubscriptionRoute {
  static const path = '/subscription/flex';
  static const name = 'flex_subscription';

  static String pathWithLevel(int level) =>
      '$path?level=${Uri.encodeComponent('$level')}';
}

class FlexConstructorRoute {
  static const path = '/subscription/flex/constructor';
  static const name = 'flex_constructor';
}

class FlexShopRoute {
  static const path = '/subscription/flex/shop';
  static const name = 'flex_shop';
}

class AdminFlexFeaturesRoute {
  static const path = '/admin/flex-features';
  static const name = 'admin_flex_features';
}

class StarsWalletRoute {
  static const path = '/paid/wallet';
  static const name = 'stars_wallet';
}

class StarGiftsInventoryRoute {
  static const path = '/paid/gifts';
  static const name = 'star_gifts_inventory';
}

class StarGiftsMarketplaceRoute {
  static const path = '/paid/gifts/marketplace';
  static const name = 'star_gifts_marketplace';
}

class StarInvoicePayRoute {
  static const path = '/paid/invoices/:invoiceId';
  static const name = 'star_invoice_pay';

  static String pathFor(int invoiceId) => '/paid/invoices/$invoiceId';
}

class ChannelGiveawaysRoute {
  static const path = '/channels/:channelId/giveaways';
  static const name = 'channel_giveaways';

  static String pathFor(
    int channelId, {
    String? name,
    bool canManage = false,
  }) {
    final params = <String, String>{
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      if (canManage) 'manage': '1',
    };
    final q = params.isEmpty
        ? ''
        : '?${params.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
    return '/channels/$channelId/giveaways$q';
  }
}

class ChannelSuggestedPostsRoute {
  static const path = '/channels/:channelId/suggested-posts';
  static const name = 'channel_suggested_posts';

  static String pathFor(
    int channelId, {
    String? name,
    bool canManage = false,
    bool isOwner = false,
  }) {
    final params = <String, String>{
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      if (canManage) 'manage': '1',
      if (isOwner) 'owner': '1',
    };
    final q = params.isEmpty
        ? ''
        : '?${params.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
    return '/channels/$channelId/suggested-posts$q';
  }
}

class StarsCheckoutSuccessRoute {
  static const path = '/paid/success';
  static const name = 'stars_checkout_success';
}

class StarsCheckoutCancelRoute {
  static const path = '/paid/cancel';
  static const name = 'stars_checkout_cancel';
}

class CreatorRevenueRoute {
  static const path = '/paid/revenue';
  static const name = 'creator_revenue';
}

class MyBotsRoute {
  static const path = '/bots/my';
  static const name = 'my_bots';
}

class BotDetailRoute {
  static const path = '/bots/:botId';
  static const name = 'bot_detail';

  static String pathFor(
    int botId, {
    String? username,
    BotDetailOpenSection section = BotDetailOpenSection.none,
  }) {
    switch (section) {
      case BotDetailOpenSection.miniApps:
        return BotMiniAppsRoute.pathFor(botId, username: username);
      case BotDetailOpenSection.newApp:
        return BotMiniAppsRoute.pathFor(
          botId,
          username: username,
          newApp: true,
        );
      case BotDetailOpenSection.commands:
        return BotCommandsRoute.pathFor(botId, username: username);
      case BotDetailOpenSection.token:
      case BotDetailOpenSection.none:
        break;
    }
    final params = <String, String>{};
    if (username != null && username.trim().isNotEmpty) {
      params['u'] = username.trim();
    }
    if (section == BotDetailOpenSection.token) {
      params['section'] = 'token';
    }
    final uri = Uri(
      path: '/bots/$botId',
      queryParameters: params.isEmpty ? null : params,
    );
    return uri.toString();
  }
}

class BotCommandsRoute {
  static const path = '/bots/:botId/commands';
  static const name = 'bot_commands';

  static String pathFor(int botId, {String? username}) {
    final handle = username?.trim() ?? '';
    final uri = Uri(
      path: '/bots/$botId/commands',
      queryParameters: handle.isEmpty ? null : {'u': handle},
    );
    return uri.toString();
  }
}

class BotMiniAppsRoute {
  static const path = '/bots/:botId/apps';
  static const name = 'bot_miniapps';

  static String pathFor(int botId, {String? username, bool newApp = false}) {
    final params = <String, String>{};
    final handle = username?.trim() ?? '';
    if (handle.isNotEmpty) params['u'] = handle;
    if (newApp) params['new'] = '1';
    final uri = Uri(
      path: '/bots/$botId/apps',
      queryParameters: params.isEmpty ? null : params,
    );
    return uri.toString();
  }
}

class SubscriptionSuccessRoute {
  static const path = '/subscription/success';
  static const name = 'subscription_success';
}

class SubscriptionCancelRoute {
  static const path = '/subscription/cancel';
  static const name = 'subscription_cancel';
}

class SupportSecurityRoute {
  static const path = '/support-security';
  static const name = 'support_security';
}

class BackupRoute {
  static const path = '/backup';
  static const name = 'backup';
}

class LoginRoute {
  static const path = AuthPaths.login;
  static const name = 'login';
}

class RegisterRoute {
  static const path = AuthPaths.register;
  static const name = 'register';
}

class LegalConsentRoute {
  static const path = AuthPaths.legalConsent;
  static const name = 'legal_consent';
}

class ForgotPasswordRoute {
  static const path = AuthPaths.forgotPassword;
  static const name = 'forgot_password';

  static String withEmail(String email) =>
      AuthPaths.forgotPasswordWithEmail(email);
}

class ResetPasswordRoute {
  static const path = AuthPaths.resetPassword;
  static const name = 'reset_password';
}

class VerifyEmailRoute {
  static const path = AuthPaths.verifyEmail;
  static const name = 'verify_email';

  static String withEmail(String email) =>
      AuthPaths.verifyEmailWithEmail(email);
}

class TwoFactorVerifyRoute {
  static const path = AuthPaths.twoFactorVerify;
  static const name = 'two_factor_verify';
}

class ConfirmEmailChangeRoute {
  static const path = AuthPaths.confirmEmailChange;
  static const name = 'confirm_email_change';

  static String withEmail(String email) =>
      AuthPaths.confirmEmailChangeWith(email: email);
}

class AccountSecurityRoute {
  static const path = '/account-security';
  static const name = 'account_security';
}

class TwoFactorSetupRoute {
  static const path = '/two-factor-setup';
  static const name = 'two_factor_setup';
}

class CloseFriendsRoute {
  static const path = '/close-friends';
  static const name = 'close_friends';
}

class ProfileRoute {
  static const path = '/profile';
  static const name = 'profile';

  /// Ссылка на экран профиля с [userId] в query (как в GoRoute `/profile`).
  static String withUserId(int userId) => '$path?userId=$userId';
}

class ProfileFollowersRoute {
  static const path = '/profile/followers';
  static const name = 'profile_followers';

  static String withUserId(int userId) => '$path?userId=$userId';
}

class ProfileFollowingRoute {
  static const path = '/profile/following';
  static const name = 'profile_following';

  static String withUserId(int userId) => '$path?userId=$userId';
}

/// Комментарии к посту (совпадает с GoRoute `post_comments`).
class PostCommentsRoute {
  static const name = 'post_comments';

  static String pathFor(int postId) => '/post/$postId/comments';
}

/// Редактирование поста профиля (GoRoute `edit_profile_post`).
class EditProfilePostRoute {
  static const name = 'edit_profile_post';

  static String pathFor(int postId) => '/post/$postId/edit';
}

/// Карточка канала и вложенные пути (совпадают с GoRouter).
class ChannelDetailRoute {
  static String pathFor(int channelId) => '/channel/$channelId';

  static String search(int channelId, {String? query}) =>
      ChannelSearchRoute.pathFor(channelId, query: query);

  static String info(int channelId, {String? channelName}) {
    final base = '${pathFor(channelId)}/info';
    if (channelName == null || channelName.trim().isEmpty) return base;
    return '$base?channelName=${Uri.encodeComponent(channelName)}';
  }

  static String subscribers(int channelId, {String? channelName}) {
    final base = '${pathFor(channelId)}/subscribers';
    if (channelName == null || channelName.trim().isEmpty) return base;
    return '$base?channelName=${Uri.encodeComponent(channelName)}';
  }

  static String management(int channelId) => '${pathFor(channelId)}/management';

  static String settings(int channelId, String channelName) =>
      '${pathFor(channelId)}/settings?channelName=${Uri.encodeComponent(channelName)}';

  /// Query: `type`, опционально `channelName`.
  static String createPost(
    int channelId, {
    String? channelName,
    String type = 'text',
  }) {
    final params = <String, String>{'type': type};
    if (channelName != null && channelName.trim().isNotEmpty) {
      params['channelName'] = channelName.trim();
    }
    final q = Uri(queryParameters: params).query;
    return '${pathFor(channelId)}/create-post${q.isEmpty ? '' : '?$q'}';
  }


  static String post(int channelId, int postId) =>
      '${pathFor(channelId)}/post/$postId';

  static String postEdit(int channelId, int postId) =>
      '${pathFor(channelId)}/post/$postId/edit';
}

/// Пост по id (GoRoute `post_by_id`).
class PostFeedRoute {
  static String pathFor(int postId) => '/post/$postId';

  /// `https://haneat.app/post/28`, `/channel/5/post/28`, `haneat://post/28`.
  static int? postIdFromUrl(String raw) {
    final path = parseDeepLinkToGoPath(raw.trim());
    if (path == null) return null;
    final clean = path.split('?').first;
    final post = RegExp(r'^/post/(\d+)$').firstMatch(clean);
    if (post != null) return int.tryParse(post.group(1)!);
    final channel = RegExp(r'^/channel/\d+/post/(\d+)$').firstMatch(clean);
    if (channel != null) return int.tryParse(channel.group(1)!);
    return null;
  }
}

/// Экран аналитики (GoRoute `analytics`).
class AppAnalyticsRoute {
  static const path = '/analytics';
  static const name = 'analytics';

  static String pathWithPostId(int postId) => '$path?postId=$postId';
}

/// Создание нового канала.
class CreateChannelRoute {
  static const path = '/create-channel';
  static const name = 'create_channel';
}

/// Каталог каналов, поиск и фильтры.
class ChannelsManagementRoute {
  static const path = '/channels/management';
  static const name = 'channels_management';

  static String pathWithSearch(String query) =>
      '$path?search=${Uri.encodeComponent(query)}';
}

class SupportContactRoute {
  static const path = '/support';
  static const name = 'support';

  static String withSubjectMessage(
    String subject,
    String message, {
    String? type,
  }) {
    final params = <String, String>{
      'subject': subject,
      'message': message,
    };
    if (type != null && type.isNotEmpty) {
      params['type'] = type;
    }
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return '$path?$query';
  }

  static String bugReport() => withSubjectMessage(
        'Сообщение об ошибке',
        'Опишите ошибку подробно:\n\n'
            '• На каком экране это произошло\n'
            '• Что вы делали перед ошибкой\n'
            '• Что ожидали увидеть',
        type: 'technical_issue',
      );
}

class CreatePostRoute {
  static const path = '/create-post';
  static const name = 'create_post';
}


class CreateReelRoute {
  static const path = '/create-reel';
  static const name = 'create_reel';

  static String uri({int? channelId, String? channelName}) {
    if (channelId == null) return path;
    final params = <String, String>{'channelId': '$channelId'};
    if (channelName != null && channelName.trim().isNotEmpty) {
      params['channelName'] = channelName.trim();
    }
    return '$path?${Uri(queryParameters: params).query}';
  }
}

class SearchRoute {
  static const path = '/search';
  static const name = 'search';

  static String pathFor({
    String? q,
    SearchScope? scope,
    String? feedType,
    bool followingOnly = false,
  }) {
    final params = <String, String>{};
    final query = q?.trim();
    if (query != null && query.isNotEmpty) {
      params['q'] = query;
    }
    if (scope != null) {
      params['scope'] = scope.name;
    }
    // Опционально для прямых ссылок (хештеги и т.п.), не из нижней панели.
    if (feedType != null && feedType != 'all') {
      params['feed_type'] = feedType;
    }
    if (followingOnly) {
      params['following'] = '1';
    }
    if (params.isEmpty) return path;
    return '$path?${Uri(queryParameters: params).query}';
  }
}

class ReelsRoute {
  static const path = '/reels';
  static const name = 'reels';
}

class ReelByIdRoute {
  static const path = '/reel/:postId';
  static const name = 'reel_by_id';

  static String pathFor(Object postId) => '/reel/$postId';

  /// `/reel/28` и `/app/reel/28` → `/reel/28`.
  static String? goPathFromBrowserPath(String path) {
    var p = path.trim();
    if (p.contains('?')) {
      p = p.split('?').first;
    }
    if (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    if (p.startsWith('/app/')) {
      p = p.substring(4);
    }
    final match = RegExp(r'^/reel/(\d+)$').firstMatch(p);
    if (match == null) return null;
    return pathFor(match.group(1)!);
  }

  /// `https://haneat.app/reel/28`, `/app/reel/28`, `haneat://reel/28`.
  static int? postIdFromUrl(String raw) {
    final path = parseDeepLinkToGoPath(raw.trim());
    if (path == null) return null;
    final match = RegExp(r'^/reel/(\d+)$').firstMatch(path);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }
}

class ReelsFullscreenRoute {
  static const path = '/reels/fullscreen';
  static const name = 'reels_fullscreen';
}
