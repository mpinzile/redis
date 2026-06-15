// AppRoutes.tsx
import { BrowserRouter, Routes, Route, Navigate, useParams } from "react-router-dom";
import { useCurrentUser } from "@/hooks/useCurrentUser";
import { useAuthSync } from "@/hooks/useAuthSync";
import OpenInAppBanner from "@/components/OpenInAppBanner";
import { usePageTracking } from "@/hooks/usePageTracking";
import PrivateRoute from "@/components/PrivateRoute";
import FullPageLoader from "@/components/FullPageLoader";
import { useTimezoneSync } from "@/hooks/useTimezoneSync";

import Layout from "@/components/Layout";
import Feed from "@/components/Feed";
import Messages from "@/components/Messages";
import MyEvents from "@/components/MyEvents";
import FindServices from "@/components/FindServices";
import Notifications from "@/components/Notifications";
import Help from "@/components/Help";
import Settings from "@/components/Settings";
import Wallet from "@/components/Wallet";
import ReceiptPage from "@/components/ReceiptPage";
import SettingsPayments from "@/components/SettingsPayments";
import PostDetail from "@/components/PostDetail";
import CreateEvent from "@/components/CreateEvent";
import EventManagement from "@/components/EventManagement";
import InvitationCardManagerPage from "@/features/card-designer/pages/InvitationCardManagerPage";
import InvitationTemplateGalleryPage from "@/features/card-designer/pages/InvitationTemplateGalleryPage";
import InvitationCardDesignerPage from "@/features/card-designer/pages/InvitationCardDesignerPage";
import InvitationCardPreviewPage from "@/features/card-designer/pages/InvitationCardPreviewPage";
import MyServices from "@/components/MyServices";
import AddService from "@/components/AddService";
import EditService from "@/components/EditService";
import ServiceVerification from "@/components/ServiceVerification";
import UserProfile from "@/components/UserProfile";
import ServiceDetail from "@/components/ServiceDetail";
import PublicServiceDetail from "@/components/PublicServiceDetail";
import Circle from "@/components/Circle";
import Communities from "@/components/Communities";
import ProviderChat from "@/components/ProviderChat";
import CommunityDetail from "@/components/CommunityDetail";
import MyMoments from "@/components/MyMoments";
import MyContributors from "@/components/MyContributors";
import SavedPosts from "@/components/SavedPosts";
import RemovedContent from "@/components/RemovedContent";
import LiveChat from "@/components/LiveChat";
import NuruCards from "@/components/NuruCards";
import BookingList from "@/components/bookings/BookingList";
import BrowseTickets from "@/components/BrowseTickets";
import MyTickets from "@/components/MyTickets";
import BookingDetail from "@/components/bookings/BookingDetail";
import EventView from "@/components/EventView";
import PublicProfile from "@/components/PublicProfile";
import ServiceEventsPage from "@/components/ServiceEventsPage";
import ServicePhotoLibraries from "@/components/ServicePhotoLibraries";
import PhotoLibraryDetail from "@/components/PhotoLibraryDetail";
import SharedPhotoLibrary from "@/components/SharedPhotoLibrary";
import SharedReceiptPage from "@/pages/SharedReceiptPage";
import MomentDetail from "@/components/MomentDetail";


import Index from "@/pages/Index";
import Download from "@/pages/Download";
import Contact from "@/pages/Contact";
import FAQs from "@/pages/FAQs";
import Register from "@/pages/Register";
import Login from "@/pages/Login";
import PrivacyPolicy from "@/pages/PrivacyPolicy";
import Terms from "@/pages/Terms";
import VendorAgreement from "@/pages/VendorAgreement";
import OrganiserAgreement from "@/pages/OrganiserAgreement";
import CancellationPolicy from "@/pages/CancellationPolicy";
import CookiePolicy from "@/pages/CookiePolicy";
import CookieConsent from "@/components/CookieConsent";
import RegionSwitcher from "@/components/region/RegionSwitcher";
import CountryConfirmModal from "@/components/region/CountryConfirmModal";
import MigrationWelcomeModal from "@/components/migration/MigrationWelcomeModal";
import NotFound from "@/pages/NotFound";
import ScrollToTop from "@/components/ScrollToTop";
import EventPlanning from "@/pages/features/EventPlanning";
import FeaturesIndex from "@/pages/features/FeaturesIndex";
import ServiceProviders from "@/pages/features/ServiceProviders";
import Invitations from "@/pages/features/Invitations";
import NfcCards from "@/pages/features/NfcCards";
import Payments from "@/pages/features/Payments";
import Meetings from "@/pages/features/Meetings";
import EventGroups from "@/pages/features/EventGroups";
import Ticketing from "@/pages/features/Ticketing";
import Trust from "@/pages/features/Trust";
import VerifyEmail from "@/pages/VerifyEmail";
import VerifyPhone from "@/pages/VerifyPhone";
import ResetPassword from "@/pages/ResetPassword";
import SetPassword from "@/pages/SetPassword";
import GuestPost from "@/pages/GuestPost";
import ShortLinkRedirect from "@/pages/ShortLinkRedirect";
import RSVPConfirmation from "@/pages/RSVPConfirmation";
import InvitationView from "@/pages/InvitationView";
import ChangePassword from "@/pages/ChangePassword";
import TicketVerification from "@/pages/TicketVerification";
import EventGroupWorkspace from "@/pages/EventGroupWorkspace";
import GuestGroupJoin from "@/pages/GuestGroupJoin";
import MyGroups from "@/components/eventGroups/MyGroups";
import WhatsappLogs from "@/pages/WhatsappLogs";
import BackgroundTasks from "@/pages/BackgroundTasks";
import MyContributions from "@/pages/MyContributions";
import PublicContribute from "@/pages/PublicContribute";
import PublicContributionReceipt from "@/pages/PublicContributionReceipt";
import PublicCardView from "@/pages/PublicCardView";
import VoiceCalls from "@/pages/VoiceCalls";

// Admin
import AdminLogin from "@/pages/admin/AdminLogin";
import AdminLayout from "@/pages/admin/AdminLayout";
import AdminDashboard from "@/pages/admin/AdminDashboard";
import AdminUsers from "@/pages/admin/AdminUsers";
import AdminKyc from "@/pages/admin/AdminKyc";
import AdminServices from "@/pages/admin/AdminServices";
import AdminEvents from "@/pages/admin/AdminEvents";
import AdminEventDetail from "@/pages/admin/AdminEventDetail";
import AdminEventTypes from "@/pages/admin/AdminEventTypes";
import AdminChats from "@/pages/admin/AdminChats";
import AdminChatDetail from "@/pages/admin/AdminChatDetail";
import AdminTickets from "@/pages/admin/AdminTickets";
import AdminFaqs from "@/pages/admin/AdminFaqs";
import AdminNotifications from "@/pages/admin/AdminNotifications";
import AdminPosts from "@/pages/admin/AdminPosts";
import AdminPostDetail from "@/pages/admin/AdminPostDetail";
import AdminMoments from "@/pages/admin/AdminMoments";
import AdminMomentDetail from "@/pages/admin/AdminMomentDetail";
import AdminCommunities from "@/pages/admin/AdminCommunities";
import AdminCommunityDetail from "@/pages/admin/AdminCommunityDetail";
import AdminBookings from "@/pages/admin/AdminBookings";
import AdminNuruCards from "@/pages/admin/AdminNuruCards";
import AdminServiceCategories from "@/pages/admin/AdminServiceCategories";
import AdminAdmins from "@/pages/admin/AdminAdmins";
import AdminUserVerifications from "@/pages/admin/AdminUserVerifications";
import AdminKycDetail from "@/pages/admin/AdminKycDetail";
import AdminServiceDetail from "@/pages/admin/AdminServiceDetail";
import AdminAppeals from "@/pages/admin/AdminAppeals";
import AdminAnalytics from "@/pages/admin/AdminAnalytics";
import AdminWhatsApp from "@/pages/admin/AdminWhatsApp";
import AdminWhatsAppTemplates from "@/pages/admin/AdminWhatsAppTemplates";
import AdminIssues from "@/pages/admin/AdminIssues";
import AdminIssueDetail from "@/pages/admin/AdminIssueDetail";
import AdminIssueCategories from "@/pages/admin/AdminIssueCategories";
import AdminAgreements from "@/pages/admin/AdminAgreements";
import AdminTicketedEvents from "@/pages/admin/AdminTicketedEvents";
import AdminNameFlags from "@/pages/admin/AdminNameFlags";
import AdminMonitoring from "@/pages/admin/AdminMonitoring";
import AdminPayments from "@/pages/admin/AdminPayments";
import AdminContactMessages from "@/pages/admin/AdminContactMessages";
import AdminDeletionRequests from "@/pages/admin/AdminDeletionRequests";
import DataDeletion from "@/pages/DataDeletion";
import MyIssues from "@/components/MyIssues";
import MeetingRoom from "@/pages/MeetingRoom";
import MeetingRedirect from "@/pages/MeetingRedirect";

// Inner component that uses router hooks (must be inside BrowserRouter)

function EventAutomationsRedirect() {
  const { id } = useParams();
  return <Navigate to={`/event-management/${id || ""}?tab=reminders`} replace />;
}

function InnerRoutes() {
  const { userIsLoggedIn, isLoading, data: currentUser } = useCurrentUser();
  useAuthSync();
  usePageTracking();
  useTimezoneSync(currentUser?.id);

  if (isLoading) return <FullPageLoader />;

  return (
    <>
      <ScrollToTop />
        <OpenInAppBanner />
        <CookieConsent />
        <RegionSwitcher />
        <CountryConfirmModal />
        <MigrationWelcomeModal />
      <Routes>
        {/* Root: marketing landing when logged out; app feed when logged in */}
        <Route
          path="/"
          element={userIsLoggedIn ? (
            <Layout>
              <Feed />
            </Layout>
          ) : (
            <Index />
          )}
        />

        {/* Protected app pages */}
        <Route
          element={
            <PrivateRoute userIsLoggedIn={userIsLoggedIn}>
              <Layout />
            </PrivateRoute>
          }
        >
          <Route path="/messages" element={<Messages />} />
          <Route path="/my-events" element={<MyEvents />} />
          <Route path="/find-services" element={<FindServices />} />
          <Route path="/notifications" element={<Notifications />} />
          <Route path="/help" element={<Help />} />
          <Route path="/settings" element={<Settings />} />
          <Route path="/settings/payments" element={<SettingsPayments />} />
          <Route path="/wallet" element={<Wallet />} />
          <Route path="/wallet/receipt/:transaction_code" element={<ReceiptPage />} />
          {/* /post/:id moved to public routes below */}
          <Route path="/create-event" element={<CreateEvent />} />
          <Route path="/tickets" element={<BrowseTickets />} />
          <Route path="/my-tickets" element={<MyTickets />} />
          <Route path="/event-management/:id" element={<EventManagement />} />
          <Route path="/events/:eventId/invitations/cards" element={<InvitationCardManagerPage />} />
          <Route path="/events/:eventId/invitations/cards/new" element={<InvitationTemplateGalleryPage />} />
          <Route path="/events/:eventId/invitations/cards/new/edit" element={<InvitationCardDesignerPage />} />
          <Route path="/events/:eventId/invitations/cards/:templateId/edit" element={<InvitationCardDesignerPage />} />
          <Route path="/events/:eventId/invitations/cards/:templateId/preview" element={<InvitationCardPreviewPage />} />
          <Route path="/event-group/:groupId" element={<EventGroupWorkspace />} />
          <Route path="/my-groups" element={<MyGroups />} />
          <Route path="/my-contributions" element={<MyContributions />} />
          <Route path="/my-services" element={<MyServices />} />
          <Route path="/services/new" element={<AddService />} />
          <Route path="/services/edit/:id" element={<EditService />} />
          <Route path="/services/verify/:serviceId/:serviceType" element={<ServiceVerification />} />
          <Route path="/service/:id" element={<ServiceDetail />} />
          {/* /services/view/:id moved to public routes below */}
          <Route path="/profile" element={<UserProfile />} />
          <Route path="/circle" element={<Circle />} />
          <Route path="/communities" element={<Communities />} />
          <Route path="/communities/:id" element={<CommunityDetail />} />
          <Route path="/provider-chat" element={<ProviderChat />} />
          <Route path="/my-posts" element={<MyMoments />} />
          <Route path="/saved-posts" element={<SavedPosts />} />
          <Route path="/live-chat" element={<LiveChat />} />
          <Route path="/nuru-cards" element={<NuruCards />} />
          <Route path="/bookings" element={<BookingList />} />
          <Route path="/bookings/:id" element={<BookingDetail />} />
          {/* /event/:id moved to public routes below */}
          <Route path="/event/:id/automations" element={<EventAutomationsRedirect />} />
          <Route path="/my-contributors" element={<MyContributors />} />
          <Route path="/voice-calls" element={<VoiceCalls />} />
          <Route path="/change-password" element={<ChangePassword />} />
          <Route path="/removed-content" element={<RemovedContent />} />
          <Route path="/my-issues" element={<MyIssues />} />
          {/* /u/:username moved to public routes below */}
          <Route path="/services/events/:serviceId" element={<ServiceEventsPage />} />
          <Route path="/services/photo-libraries/:serviceId" element={<ServicePhotoLibraries />} />
          <Route path="/photo-library/:libraryId" element={<PhotoLibraryDetail />} />
          <Route path="/whatsapp-logs" element={<WhatsappLogs />} />
          <Route path="/background-tasks" element={<BackgroundTasks />} />
          
          
        </Route>

        {/* Public deep-link routes — viewable without login, with auth-aware actions */}
        <Route path="/u/:username" element={<Layout><PublicProfile /></Layout>} />
        <Route path="/event/:id" element={<Layout><EventView /></Layout>} />
        <Route path="/post/:id" element={<Layout><PostDetail /></Layout>} />
        <Route path="/moment/:id" element={<Layout><MomentDetail /></Layout>} />
        <Route path="/services/view/:id" element={<Layout><PublicServiceDetail /></Layout>} />

        {/* Public Pages */}
        <Route path="/contact" element={<Contact />} />
        <Route path="/data-deletion" element={<DataDeletion />} />
        <Route path="/faqs" element={<FAQs />} />
        <Route path="/download" element={<Download />} />
        <Route path="/register" element={userIsLoggedIn ? <Navigate to="/" replace /> : <Register />} />
        <Route path="/login" element={userIsLoggedIn ? <Navigate to="/" replace /> : <Login />} />
        <Route path="/verify-email" element={<VerifyEmail />} />
        <Route path="/verify-phone" element={<VerifyPhone />} />
        <Route path="/reset-password" element={<ResetPassword />} />
        <Route path="/set-password/:token" element={<SetPassword />} />
        <Route path="/privacy-policy" element={<PrivacyPolicy />} />
        <Route path="/terms" element={<Terms />} />
        <Route path="/vendor-agreement" element={<VendorAgreement />} />
        <Route path="/organiser-agreement" element={<OrganiserAgreement />} />
        <Route path="/cancellation-policy" element={<CancellationPolicy />} />
        <Route path="/cookie-policy" element={<CookiePolicy />} />
        <Route path="/shared/post/:id" element={<GuestPost />} />
        <Route path="/s/:shortId" element={<ShortLinkRedirect />} />
        <Route path="/shared/photo-library/:token" element={<SharedPhotoLibrary />} />
        <Route path="/shared/receipt/:transaction_code" element={<SharedReceiptPage />} />
        <Route path="/rsvp/:code" element={<RSVPConfirmation />} />
        <Route path="/i/:code" element={<InvitationView />} />
        <Route path="/ticket/:code" element={<TicketVerification />} />
        <Route path="/g/:token" element={<GuestGroupJoin />} />
        <Route path="/c/:token" element={<PublicContribute />} />
        <Route path="/c/:token/r/:txCode" element={<PublicContributionReceipt />} />
        <Route path="/cards/:id" element={<PublicCardView />} />
        <Route path="/card/:token" element={<PublicCardView />} />
        <Route path="/features" element={<FeaturesIndex />} />
        <Route path="/features/event-planning" element={<EventPlanning />} />
        <Route path="/features/service-providers" element={<ServiceProviders />} />
        <Route path="/features/invitations" element={<Invitations />} />
        <Route path="/features/nfc-cards" element={<NfcCards />} />
        <Route path="/features/payments" element={<Payments />} />
        <Route path="/features/meetings" element={<Meetings />} />
        <Route path="/features/event-groups" element={<EventGroups />} />
        <Route path="/features/ticketing" element={<Ticketing />} />
        <Route path="/features/trust" element={<Trust />} />
        <Route path="/meet/:roomId" element={<MeetingRoom />} />
        <Route path="/m/:token" element={<MeetingRedirect />} />

        {/* Admin Panel */}
        <Route path="/admin/login" element={<AdminLogin />} />
        <Route path="/admin" element={<AdminLayout />}>
          <Route index element={<AdminDashboard />} />
          <Route path="users" element={<AdminUsers />} />
          <Route path="name-flags" element={<AdminNameFlags />} />
          <Route path="kyc" element={<AdminKyc />} />
          <Route path="services" element={<AdminServices />} />
          <Route path="events" element={<AdminEvents />} />
          <Route path="events/:id" element={<AdminEventDetail />} />
          <Route path="event-types" element={<AdminEventTypes />} />
          <Route path="chats" element={<AdminChats />} />
          <Route path="chats/:chatId" element={<AdminChatDetail />} />
          <Route path="tickets" element={<AdminTickets />} />
          <Route path="faqs" element={<AdminFaqs />} />
          <Route path="notifications" element={<AdminNotifications />} />
          <Route path="posts" element={<AdminPosts />} />
          <Route path="posts/:id" element={<AdminPostDetail />} />
          <Route path="moments" element={<AdminMoments />} />
          <Route path="moments/:id" element={<AdminMomentDetail />} />
          <Route path="communities" element={<AdminCommunities />} />
          <Route path="communities/:id" element={<AdminCommunityDetail />} />
          <Route path="bookings" element={<AdminBookings />} />
          <Route path="nuru-cards" element={<AdminNuruCards />} />
          <Route path="service-categories" element={<AdminServiceCategories />} />
          <Route path="admins" element={<AdminAdmins />} />
          <Route path="user-verifications" element={<AdminUserVerifications />} />
          <Route path="kyc/:id" element={<AdminKycDetail />} />
          <Route path="services/:id" element={<AdminServiceDetail />} />
          <Route path="appeals" element={<AdminAppeals />} />
          <Route path="analytics" element={<AdminAnalytics />} />
          <Route path="whatsapp" element={<AdminWhatsApp />} />
          <Route path="whatsapp/templates" element={<AdminWhatsAppTemplates />} />
          <Route path="whatsapp-logs" element={<WhatsappLogs />} />
          <Route path="issues" element={<AdminIssues />} />
          <Route path="issues/:id" element={<AdminIssueDetail />} />
          <Route path="issue-categories" element={<AdminIssueCategories />} />
          <Route path="agreements" element={<AdminAgreements />} />
          <Route path="ticketed-events" element={<AdminTicketedEvents />} />
          <Route path="monitoring" element={<AdminMonitoring />} />
          <Route path="payments" element={<AdminPayments />} />
          <Route path="contact-messages" element={<AdminContactMessages />} />
          <Route path="deletion-requests" element={<AdminDeletionRequests />} />
        </Route>


        {/* 404 */}
        <Route path="*" element={<NotFound />} />
      </Routes>
    </>
  );
}

export default function AppRoutes() {
  return (
    <BrowserRouter future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
      <InnerRoutes />
    </BrowserRouter>
  );
}
