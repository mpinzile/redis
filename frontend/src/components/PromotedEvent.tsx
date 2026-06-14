import { Users } from 'lucide-react';
import SvgIcon from '@/components/ui/svg-icon';
import CalendarIcon from '@/assets/icons/calendar-icon.svg';
import LocationIcon from '@/assets/icons/location-icon.svg';
import { Button } from '@/components/ui/button';
import { useLanguage } from '@/lib/i18n/LanguageContext';

interface PromotedEventProps {
  title: string;
  date: string;
  location: string;
  image: string;
  attendees: number;
}

const PromotedEvent = ({ title, date, location, image, attendees }: PromotedEventProps) => {
  const { t } = useLanguage();
  return (
    <div className="bg-card rounded-lg border border-border overflow-hidden">
      {/* Header — subtle accent, no shadow */}
      <div className="flex items-center justify-between px-3 py-2 border-b border-border bg-gradient-to-r from-primary/6 to-transparent">
        <span className="text-xs font-medium text-primary">Promoted Event</span>
        <span className="text-xs text-muted-foreground">Sponsored</span>
      </div>

      {/* Body */}
      <div className="p-3 md:p-4">
        <div className="flex flex-col sm:flex-row gap-3 md:gap-4 items-start">
          {/* Image — same radius, subtle separation */}
          <div className="w-full sm:w-20 md:w-24 h-32 sm:h-20 md:h-24 flex-shrink-0 rounded-lg overflow-hidden">
            <img
              src={image}
              alt={title}
              className="w-full h-full object-cover"
            />
          </div>

          {/* Info */}
          <div className="flex-1 w-full">
            <h3 className="font-semibold text-foreground mb-1 text-base md:text-lg leading-tight">
              {title}
            </h3>

            <div className="flex flex-col gap-1 text-xs md:text-sm text-muted-foreground mb-3">
              <div className="flex items-center gap-1.5 md:gap-2">
                <img src={CalendarIcon} alt="Calendar" className="w-3.5 h-3.5 md:w-4 md:h-4" />
                <span>{date}</span>
              </div>

              <div className="flex items-center gap-1.5 md:gap-2">
                <img src={LocationIcon} alt="Location" className="w-3.5 h-3.5 md:w-4 md:h-4" />
                <span className="truncate">{location}</span>
              </div>

              <div className="flex items-center gap-1.5 md:gap-2">
                <Users className="w-3.5 h-3.5 md:w-4 md:h-4" />
                <span>{attendees} attending</span>
              </div>
            </div>

            {/* Actions — consistent radius with Glow/Echo/Spark */}
            <div className="flex gap-2 items-center flex-wrap">
              <Button
                size="sm"
                className="px-3 md:px-4 py-1.5 md:py-2 rounded-lg bg-nuru-yellow text-black font-medium hover:bg-nuru-yellow/95 focus:outline-none focus:ring-2 focus:ring-primary/20 text-xs md:text-sm"
                aria-label={`Mark interest for ${title}`}
              >
                Interested
              </Button>

              <Button
                size="sm"
                variant="outline"
                className="px-2.5 md:px-3 py-1.5 md:py-2 rounded-lg text-xs md:text-sm"
                aria-label={`Share ${title}`}
              >
                Share
              </Button>
            </div>
          </div>
        </div>
      </div>

      {/* Footer — minimal */}
      <div className="px-3 md:px-4 py-2 md:py-3 border-t border-border text-xs text-muted-foreground">
        <span className="block sm:inline">Event promoted by Nuru - You can trust promoted content on the platform</span>
      </div>
    </div>
  );
};

export default PromotedEvent;
