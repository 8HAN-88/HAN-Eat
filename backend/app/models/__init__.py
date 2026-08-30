# Models
from app.models.user import User
from app.models.auth_session import AuthSession
from app.models.post import Post
from app.models.post_view import PostView
from app.models.community import Channel
from app.models.follower import Follower
from app.models.community_member import ChannelMember
from app.models.saved_post import SavedPost
from app.models.like import Like
from app.models.post_reaction import PostReaction
from app.models.comment import Comment
from app.models.repost import Repost
from app.models.moderation_queue import ModerationQueue
from app.models.content_report import ContentReport
from app.models.moderation_audit_log import ModerationAuditLog
from app.models.analytics_event import AnalyticsEvent
from app.models.ai_meal_plan_record import AiMealPlanRecord
from app.models.notification_preferences import NotificationPreferences
from app.models.video_processing import VideoProcessing
from app.models.image_processing import ImageProcessing
from app.models.conversation import (
    Conversation,
    ConversationMember,
    GroupMemberBan,
    GroupJoinRequest,
    GroupInviteLink,
    Message,
    Contact,
    MessageReaction,
    MessageHide,
    MessageEditHistory,
    ScheduledMessage,
)
from app.models.forum_topic import ForumTopic
from app.models.user_block import UserBlock
from app.models.call import CallSession, CallParticipant
from app.models.paid_features import (
    CreatorPayoutRequest,
    CreatorBalance,
    PaidChannelSubscription,
    PaidGroupSubscription,
    PaidContentPurchase,
    PaidMessageException,
    PaidMessageUnlock,
    PostBoost,
    StarGift,
    StarGiveaway,
    StarGiveawayParticipant,
    StarInvoice,
    StarTransaction,
    UserStarGift,
)
from app.models.story import Story, StoryReaction, StoryView
from app.models.close_friend import CloseFriend
from app.models.flex_subscription import (
    SubscriptionFeature,
    SubscriptionFeatureBlock,
    UserFlexSlot,
    UserFlexSubscription,
)
from app.models.miniapp import BotMiniApp, MiniAppInstall, MiniAppLaunch
from app.models.sticker import (
    StickerPack,
    Sticker,
    StickerPackInstall,
    StickerFavorite,
    StickerPackPin,
)

# Для обратной совместимости
Community = Channel
CommunityMember = ChannelMember

__all__ = [
    "User", "AuthSession", "Post", "PostView", "Channel", "Follower", "ChannelMember",
    "SavedPost", "Like", "PostReaction", "Comment", "Repost", "ModerationQueue",
    "ContentReport", "ModerationAuditLog", "AnalyticsEvent", "Notification",
    "Subscription", "SupportTicket", "NotificationPreferences",
    "VideoProcessing", "ImageProcessing", "Community", "CommunityMember",
    "StarTransaction", "PaidContentPurchase", "CreatorBalance",
    "PaidChannelSubscription", "PaidGroupSubscription", "PostBoost", "CreatorPayoutRequest",
    "PaidMessageUnlock", "PaidMessageException", "StarGift", "UserStarGift",
    "StarGiveaway", "StarGiveawayParticipant", "StarInvoice", "Story",
    "StoryView", "StoryReaction", "CloseFriend",

    "ScheduledMessage", "GroupMemberBan", "GroupJoinRequest", "GroupInviteLink",
    "MessageEditHistory", "ForumTopic",
    "BotMiniApp", "MiniAppInstall", "MiniAppLaunch", "StickerPack", "Sticker",
    "StickerPackInstall", "StickerFavorite", "StickerPackPin",
    "CallSession",
    "SubscriptionFeature",
    "SubscriptionFeatureBlock",
    "UserFlexSubscription",
    "UserFlexSlot",
]

