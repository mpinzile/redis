import { useState } from 'react';
import { User, LogOut, Bookmark, Search } from 'lucide-react';
import { useLanguage } from '@/lib/i18n/LanguageContext';
import LanguageSwitcher from '@/components/LanguageSwitcher';
import SvgIcon from '@/components/ui/svg-icon';
import CameraIcon from '@/assets/icons/camera-icon.svg';
import SettingsIcon from '@/assets/icons/settings-icon.svg';
import GlobalSearchBar from './GlobalSearchBar';
import { Button } from '@/components/ui/button';
import { NavLink, useNavigate } from 'react-router-dom';
import nuruLogo from '@/assets/nuru-logo.png';
import MenuIcon from '@/assets/icons/menu-icon.svg';
import CloseIcon from '@/assets/icons/close-icon.svg';
import BellIcon from '@/assets/icons/bell-icon.svg';
import ChatIcon from '@/assets/icons/chat-icon.svg';
import CardIcon from '@/assets/icons/card-icon.svg';

import PanelRightIcon from '@/assets/icons/panel-right-icon.svg';
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { Separator } from '@/components/ui/separator';
import { useLogout } from '@/api/useLogout';
import { useCurrentUser } from '@/hooks/useCurrentUser';
import { useNotifications, useConversations } from '@/data/useSocial';
import BackgroundTaskBadge from '@/components/background/BackgroundTaskBadge';

interface HeaderProps {
  onMenuToggle?: () => void;
  onRightPanelToggle?: () => void;
}

const Header = ({ onMenuToggle, onRightPanelToggle }: HeaderProps) => {
  const [popoverOpen, setPopoverOpen] = useState(false);
  const { t } = useLanguage();
  const [mobileSearchOpen, setMobileSearchOpen] = useState(false);
  const navigate = useNavigate();
  const { logout } = useLogout();
  const { data: currentUser } = useCurrentUser();
  const { unreadCount: notificationCount } = useNotifications();
  const { unreadCount: messageCount } = useConversations();

  const renderAvatar = () => {
    if (currentUser?.avatar) {
      return (
        <img
          src={currentUser.avatar}
          alt={t("profile")}
          className="w-full h-full object-cover"
        />
      );
    } else if (currentUser) {
      const initials = `${currentUser.first_name[0]}${currentUser.last_name[0]}`.toUpperCase();
      return (
        <div className="w-full h-full flex items-center justify-center bg-muted text-muted-foreground text-xs md:text-sm font-semibold">
          {initials}
        </div>
      );
    } else {
      return (
        <div className="w-full h-full flex items-center justify-center bg-muted text-muted-foreground font-semibold">
          ?
        </div>
      );
    }
  };

  return (
    <header className="bg-card border-b border-border h-16 flex items-center justify-between px-4 md:px-6 w-full relative">
      {/* Left side - Menu & Logo */}
      <div className="flex items-center gap-2">
        <Button 
          variant="ghost" 
          size="icon"
          className="md:hidden"
          onClick={onMenuToggle}
        >
          <SvgIcon src={MenuIcon} alt="Menu" className="w-5 h-5" />
        </Button>
        
        <NavLink to="/">
          <img src={nuruLogo} alt="Nuru" className="h-6 md:h-8 w-auto" />
        </NavLink>
      </div>

      {/* Search Bar - Desktop & Tablet */}
      <div className="hidden tablet:block flex-1 max-w-3xl mx-4 lg:mx-8">
        <GlobalSearchBar />
      </div>

      {/* Mobile Search Overlay */}
      {mobileSearchOpen && (
        <div className="fixed inset-0 z-50 bg-background flex flex-col tablet:hidden">
          <div className="flex items-center gap-2 px-3 py-3 border-b border-border">
            <div className="flex-1 min-w-0">
              <GlobalSearchBar autoFocus onNavigate={() => setMobileSearchOpen(false)} fullScreen />
            </div>
            <Button variant="ghost" size="sm" onClick={() => setMobileSearchOpen(false)} className="text-muted-foreground shrink-0">
              Cancel
            </Button>
          </div>
        </div>
      )}

      {/* Right Actions */}
      <div className="flex items-center gap-2 md:gap-4">
        {/* Mobile Search */}
        <Button variant="ghost" size="icon" className="tablet:hidden" onClick={() => setMobileSearchOpen(true)}>
          <Search className="w-5 h-5" />
        </Button>

        {/* Messages */}
        <NavLink to="/messages">
          <Button variant="ghost" size="icon" className="relative">
            <SvgIcon src={ChatIcon} alt={t("messages")} className="w-5 h-5" />
            {messageCount > 0 && (
              <span className="absolute -top-1 -right-1 bg-primary text-primary-foreground text-xs rounded-full w-4 h-4 md:w-5 md:h-5 flex items-center justify-center text-[10px] md:text-xs">
                {messageCount > 99 ? '99+' : messageCount}
              </span>
            )}
          </Button>
        </NavLink>

        {/* Notifications */}
        <NavLink to="/notifications">
          <Button variant="ghost" size="icon" className="relative">
            <SvgIcon src={BellIcon} alt={t("notifications")} className="w-5 h-5" />
            {notificationCount > 0 && (
              <span className="absolute -top-1 -right-1 bg-primary text-primary-foreground text-xs rounded-full w-4 h-4 md:w-5 md:h-5 flex items-center justify-center text-[10px] md:text-xs">
                {notificationCount > 99 ? '99+' : notificationCount}
              </span>
            )}
          </Button>
        </NavLink>

        {/* Background tasks (uploads, bulk actions, exports…) */}
        <BackgroundTaskBadge />

        {/* Mobile Right Panel Toggle */}
        <Button 
          variant="ghost" 
          size="icon"
          className="lg:hidden"
          onClick={onRightPanelToggle}
        >
          <SvgIcon src={PanelRightIcon} alt="Toggle right panel" className="w-5 h-5" />
        </Button>

        {/* Profile */}
        <Popover open={popoverOpen} onOpenChange={setPopoverOpen}>
          <PopoverTrigger asChild>
            <button className="focus:outline-none">
              <div className="w-7 h-7 md:w-10 md:h-10 rounded-full overflow-hidden cursor-pointer hover:ring-2 hover:ring-primary transition">
                {renderAvatar()}
              </div>
            </button>
          </PopoverTrigger>
          <PopoverContent className="w-56 p-4" align="end">
            {currentUser && (
              <div className="flex items-center gap-3 mb-3">
                <div className="w-10 h-10 rounded-full overflow-hidden flex-shrink-0">
                  {renderAvatar()}
                </div>
                <div className="flex flex-col">
                  <span className="font-semibold text-foreground flex items-center gap-1">
                    {`${currentUser.first_name.charAt(0).toUpperCase()}${currentUser.first_name.slice(1)} ${currentUser.last_name.charAt(0).toUpperCase()}${currentUser.last_name.slice(1)}`}

                  </span>
                  <span className="text-sm text-muted-foreground">@{currentUser.username}</span>
                </div>
              </div>
            )}

            <div className="flex flex-col gap-1">
              <Button
                variant="ghost"
                className="justify-start gap-2"
                onClick={() => {
                  setPopoverOpen(false);
                  navigate('/profile');
                }}
              >
                <User className="w-4 h-4" />
                {t('profile')}
              </Button>
              <Button
                variant="ghost"
                className="justify-start gap-2"
                onClick={() => {
                  setPopoverOpen(false);
                  navigate('/settings');
                }}
              >
                <SvgIcon src={SettingsIcon} alt="" className="w-4 h-4" />
                {t('settings')}
              </Button>
              <Button
                variant="ghost"
                className="justify-start gap-2"
                onClick={() => {
                  setPopoverOpen(false);
                  navigate('/my-posts');
                }}
              >
                <SvgIcon src={CameraIcon} alt={t("moments")} className="w-4 h-4" />
                {t('moments')}
              </Button>
              <Button
                variant="ghost"
                className="justify-start gap-2"
                onClick={() => {
                  setPopoverOpen(false);
                  navigate('/nuru-cards');
                }}
              >
                <SvgIcon src={CardIcon} alt="Cards" className="w-4 h-4" />
                Nuru Cards
              </Button>
              <Button
                variant="ghost"
                className="justify-start gap-2"
                onClick={() => {
                  setPopoverOpen(false);
                  navigate('/saved-posts');
                }}
              >
                <Bookmark className="w-4 h-4" />
                {t('saved_posts')}
              </Button>
              <Separator className="my-1" />
              <Button
                variant="ghost"
                className="justify-start gap-2 text-destructive hover:text-destructive hover:bg-destructive/10"
                onClick={() => {
                  setPopoverOpen(false);
                  logout();
                }}
              >
                <LogOut className="w-4 h-4" />
                {t('sign_out')}
              </Button>
            </div>
          </PopoverContent>
        </Popover>
      </div>
    </header>
  );
};

export default Header;