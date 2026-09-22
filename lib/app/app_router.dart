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
      if (rest == 'posts' || rest == 'feed' || rest == 'wall') {
        return '/channel/$id$q';
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
          segs[0] == 'supergroup') &&
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
      if (segs[3] == 'search' || segs[3] == 'pinned') {
        return '/chats/thread/$id$q';
      }
      final mid = int.tryParse(segs[3]);
      if (mid != null && mid > 0) {
        return query.isEmpty
            ? '/chats/thread/$id?msg=$mid'
            : '/chats/thread/$id?$query&msg=$mid';
      }
    }
  }

  if ((segs[0] == 'invoice' || segs[0] == 'invoices') && segs.length == 2) {
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
      if (segs[2] == 'posts' || segs[2] == 'feed') {
        return ProfileRoute.withUserId(id);
      }
    }
  }
  if ((segs[0] == 'user' || segs[0] == 'users') && segs.length == 3) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) {
      if (segs[2] == 'followers') return ProfileFollowersRoute.withUserId(id);
      if (segs[2] == 'following') return ProfileFollowingRoute.withUserId(id);
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
        segs[2] == 'posts') {
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
      if (rest == 'posts' || rest == 'feed' || rest == 'wall') {
        return '/channel/$id$q';
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
          (segs[2] == 'likes' || segs[2] == 'likers' || segs[2] == 'like')) {
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
      if (segs[2] == 'likes' || segs[2] == 'likers' || segs[2] == 'like') {
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
    }
  }

  if ((segs[0] == 'bot' || segs[0] == 'bots') && segs.length == 2) {
    if (segs[1] == 'my') return null;
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/bots/$id$q';
  }
  if ((segs[0] == 'bot' || segs[0] == 'bots') && segs.length == 3) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0 && (segs[2] == 'edit' || segs[2] == 'profile')) {
      return '/bots/$id$q';
    }
  }

  const miniRoots = {
    'miniapp',
    'miniapps',
    'mini-apps',
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

  if ((segs[0] == 'group' || segs[0] == 'groups' || segs[0] == 'supergroup') &&
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
      if (segs[2] == 'likes' || segs[2] == 'likers' || segs[2] == 'like') {
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
          segs[0] == 'media') &&
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

  const extraChatRoots = {
    'direct',
    'im',
    'msg',
    'message',
    'thread',
    'convo',
    'private',
    'm',
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
  if (segs[0] == 'forward' && segs.length == 3) {
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
        _ => null,
      };
    }
  }
  if ((segs[0] == 'call' || segs[0] == 'calls') && segs.length == 2) {
    final id = int.tryParse(segs[1]);
    if (id != null && id > 0) return '/chats/thread/$id$q';
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
        _ => null,
      };
      if (short != null) return short;
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
    'analytics' =>
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
                appBar: AppBar(title: const Text('Чат')),
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
