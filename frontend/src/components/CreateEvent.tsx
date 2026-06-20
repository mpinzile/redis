import React, { useState, useEffect, useCallback } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { ticketingApi } from "@/lib/api/ticketing";
import type { TicketClass as TicketClassType } from "@/lib/api/ticketing";
import { X, ChevronLeft, Upload } from "lucide-react";
import SvgIcon from '@/components/ui/svg-icon';
import CalendarIcon from '@/assets/icons/calendar-icon.svg';
import PackageIcon from '@/assets/icons/package-icon.svg';
import MapLocationPicker from "@/components/MapLocationPicker";
import VenueMapPreview from "@/components/VenueMapPreview";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { FormattedNumberInput } from "@/components/ui/formatted-number-input";
import { Textarea } from "@/components/ui/textarea";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { Calendar as CalendarComponent } from "@/components/ui/calendar";
import { format } from "date-fns";
import { cn } from "@/lib/utils";
import { useWorkspaceMeta } from "@/hooks/useWorkspaceMeta";
import { useEventTypes } from "@/data/useEventTypes";
import { eventsApi } from "@/lib/api";
import EventIcon from "@/components/icons/EventIcons";
import { toast } from "sonner";
import { showApiErrors, showCaughtError } from "@/lib/api";
import { agreementsApi } from "@/lib/api/agreements";
// EventRecommendations removed from create flow - moved post-creation.
import EventTicketing from "@/components/EventTicketing";
import BudgetAssistant from "@/components/BudgetAssistant";
import AgreementModal from "@/components/AgreementModal";
import type { TicketClass } from "@/components/EventTicketing";
import UserSearchInput from "@/components/events/UserSearchInput";
import type { SearchedUser } from "@/hooks/useUserSearch";
import { Switch } from "@/components/ui/switch";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { useLanguage } from '@/lib/i18n/LanguageContext';

const CreateEvent: React.FC = () => {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const { t } = useLanguage();
  const editId = searchParams.get("edit");

  const [formData, setFormData] = useState({
    title: "",
    description: "",
    date: undefined as Date | undefined,
    time: "",
    location: "",
    expectedGuests: "",
    budget: "",
    eventType: "",
    venueLatitude: null as number | null,
    venueLongitude: null as number | null,
    venueName: "",
    venueAddress: "",
    reminderContactPhone: "",
    contributionPaymentInstructions: "",
  });

  type WteItem = { icon: string; label: string; description: string };
  const WTE_ICON_CHOICES = ["sparkle","calendar","clock","heart","camera","star","users","microphone","user"];
  const [whatToExpectItems, setWhatToExpectItems] = useState<WteItem[]>([]);
  const [whatToExpectNotes, setWhatToExpectNotes] = useState("");

  const [isSubmitting, setIsSubmitting] = useState(false);
  const [images, setImages] = useState<File[]>([]);
  const [previews, setPreviews] = useState<string[]>([]);
  const [selectedServices, setSelectedServices] = useState<string[]>([]);
  
  // Ticketing state
  const [ticketingEnabled, setTicketingEnabled] = useState(false);
  const [ticketClasses, setTicketClasses] = useState<TicketClass[]>([]);
  const [isPublicEvent, setIsPublicEvent] = useState(false);
  const [datePickerOpen, setDatePickerOpen] = useState(false);
  const [budgetAssistantOpen, setBudgetAssistantOpen] = useState(false);

  // Event Owner state
  const [createdForSomeoneElse, setCreatedForSomeoneElse] = useState(false);
  const [eventOwner, setEventOwner] = useState<SearchedUser | null>(null);
  const [recognizableOwnerName, setRecognizableOwnerName] = useState("");

  // Agreement gate (only for new events, not edits)
  const [agreementAccepted, setAgreementAccepted] = useState<boolean | null>(null);
  const [showAgreementModal, setShowAgreementModal] = useState(false);
  const [agreementSummary, setAgreementSummary] = useState<string | undefined>();

  useEffect(() => {
    if (editId) { setAgreementAccepted(true); return; }
    agreementsApi.check('organiser_agreement').then(res => {
      if (res.success && res.data) {
        if (res.data.accepted) {
          setAgreementAccepted(true);
        } else {
          setAgreementAccepted(false);
          setAgreementSummary(res.data.current_version > 1 ? (res.data.summary || undefined) : undefined);
          setShowAgreementModal(true);
        }
      } else {
        setAgreementAccepted(true);
      }
    }).catch(() => setAgreementAccepted(true));
  }, [editId]);

  const handleToggleService = (serviceId: string) => {
    setSelectedServices(prev =>
      prev.includes(serviceId)
        ? prev.filter(id => id !== serviceId)
        : [...prev, serviceId]
    );
  };
  const { eventTypes, loading: loadingEventTypes, fetchEventTypes } = useEventTypes();

  useEffect(() => {
    fetchEventTypes();
  }, []);

  const displayedEventTypes = eventTypes && eventTypes.length > 0 ? eventTypes : [];

  // Load existing event data when editing
  useEffect(() => {
    if (editId) {
      const loadEvent = async () => {
        try {
          const response = await eventsApi.getById(editId);
          if (response.success && response.data) {
            const event = response.data;
            setFormData({
              title: event.title || "",
              description: event.description || "",
              date: event.start_date ? new Date(event.start_date) : undefined,
              time: (event as any).start_time || "",
              location: event.location || "",
              expectedGuests: event.expected_guests ? String(event.expected_guests) : "",
              budget: event.budget ? String(event.budget) : "",
              eventType: event.event_type_id || "wedding",
              venueLatitude: (event as any).venue_coordinates?.latitude || null,
              venueLongitude: (event as any).venue_coordinates?.longitude || null,
              venueName: (event as any).venue || "",
              venueAddress: (event as any).venue_address || "",
              reminderContactPhone: (event as any).reminder_contact_phone || "",
              contributionPaymentInstructions: (event as any).contribution_payment_instructions || "",
            });

            // Restore ticketing state
            setTicketingEnabled(!!(event as any).sells_tickets);
            setIsPublicEvent(!!(event as any).is_public);

            // Restore What to Expect
            const rawWte = (event as any).what_to_expect;
            if (Array.isArray(rawWte)) {
              setWhatToExpectItems(
                rawWte
                  .map((it: any) => ({
                    icon: String(it?.icon || "sparkle"),
                    label: String(it?.label || it?.title || "").trim(),
                    description: String(it?.description || ""),
                  }))
                  .filter((it: WteItem) => it.label),
              );
            }
            setWhatToExpectNotes(String((event as any).what_to_expect_notes || ""));

            // Restore event-owner state
            const evAny = event as any;
            if (evAny.created_for_someone_else) {
              setCreatedForSomeoneElse(true);
              if (evAny.event_owner_user_id) {
                setEventOwner({
                  id: evAny.event_owner_user_id,
                  first_name: evAny.event_owner_first_name || "",
                  last_name: evAny.event_owner_last_name || "",
                  username: evAny.event_owner_username || "",
                  email: evAny.event_owner_email || "",
                  phone: evAny.event_owner_phone || "",
                  full_name: evAny.event_owner_full_name || evAny.recognizable_event_owner_name || "",
                  avatar: evAny.event_owner_avatar || undefined,
                } as SearchedUser);
              }
              setRecognizableOwnerName(evAny.recognizable_event_owner_name || "");
            }

            if (event.gallery_images && event.gallery_images.length > 0) {
              setPreviews(event.gallery_images);
            } else if ((event as any).images && (event as any).images.length > 0) {
              const imageUrls = (event as any).images.map((img: any) =>
                typeof img === 'string' ? img : (img.image_url || img.url)
              ).filter(Boolean);
              if (imageUrls.length > 0) setPreviews(imageUrls);
            }
          } else {
            showApiErrors(response, "Failed to load event");
          }
        } catch (err: any) {
          showCaughtError(err, "Failed to load event");
        }
      };
      loadEvent();

      // Load existing assigned services
      const loadExistingServices = async () => {
        try {
          const res = await eventsApi.getEventServices(editId);
          if (res.success && res.data) {
            const services = Array.isArray(res.data) ? res.data : (res.data as any).services || [];
            const existingIds = services
              .map((s: any) => s.provider_user_service_id || s.provider_service_id)
              .filter(Boolean);
            if (existingIds.length > 0) {
              setSelectedServices(existingIds);
            }
          }
        } catch {
          // Silent - no services yet
        }
      };
      loadExistingServices();

      // Load existing ticket classes
      const loadTicketClasses = async () => {
        try {
          const res = await ticketingApi.getMyTicketClasses(editId);
          if (res.success && res.data?.ticket_classes) {
            setTicketClasses(
              res.data.ticket_classes.map((tc) => ({
                id: tc.id,
                name: tc.name,
                description: tc.description || "",
                price: String(tc.price),
                quantity: String(tc.quantity),
                sold: tc.sold,
              }))
            );
          }
        } catch {
          // Silent - no ticket classes yet
        }
      };
      loadTicketClasses();
    }
  }, [editId]);

  const handleImageChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files) {
      const filesArray = Array.from(e.target.files);
      setImages(prev => [...prev, ...filesArray]);
      setPreviews(prev => [...prev, ...filesArray.map(file => URL.createObjectURL(file))]);
    }
  };

  const removeImage = (index: number) => {
    setImages(prev => prev.filter((_, i) => i !== index));
    setPreviews(prev => prev.filter((_, i) => i !== index));
  };

  // ── Inline validation helpers ──
  const guestsNum = formData.expectedGuests ? parseInt(formData.expectedGuests, 10) : null;
  const budgetNum = formData.budget ? parseInt(formData.budget, 10) : null;
  const guestsError = guestsNum !== null && guestsNum < 1 ? "Expected guests must be at least 1" : null;
  const budgetError = budgetNum !== null && budgetNum < 0 ? "Budget cannot be negative" : null;
  const titleTooLong = formData.title.length > 100;
  const descTooLong = formData.description.length > 2000;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (guestsError || budgetError || titleTooLong || descTooLong) {
      toast.error("Please fix the highlighted errors before submitting.");
      return;
    }

    if (ticketingEnabled && ticketClasses.length === 0) {
      toast.error("Add at least one ticket class, or turn ticketing off to continue.");
      return;
    }


    if (createdForSomeoneElse && !eventOwner?.id) {
      toast.error("Please select the event owner (or register them) before continuing.");
      return;
    }

    setIsSubmitting(true);
    const tid = 'save-event';
    toast.loading(editId ? 'Updating event…' : 'Creating event…', { id: tid });

    try {
      const form = new FormData();
      if (formData.eventType) form.append("event_type_id", formData.eventType);
      form.append("title", formData.title.trim());
      if (formData.description?.trim()) form.append("description", formData.description.trim());
      if (formData.date) form.append("start_date", format(formData.date, "yyyy-MM-dd"));
      if (formData.time) form.append("time", formData.time);
      if (formData.location) form.append("location", formData.location);
      if (formData.venueLatitude != null) form.append("venue_latitude", String(formData.venueLatitude));
      if (formData.venueLongitude != null) form.append("venue_longitude", String(formData.venueLongitude));
      if (formData.venueName) form.append("venue", formData.venueName);
      if (formData.venueAddress) form.append("venue_address", formData.venueAddress);
      
      const expectedGuests = formData.expectedGuests ? parseInt(String(formData.expectedGuests), 10) : null;
      if (expectedGuests !== null && !Number.isNaN(expectedGuests)) form.append("expected_guests", String(expectedGuests));

      const budgetNumber = formData.budget ? parseFloat(String(formData.budget).replace(/[^0-9.]/g, "")) : null;
      if (budgetNumber !== null && !Number.isNaN(budgetNumber)) form.append("budget", String(budgetNumber));

      // Always send reminder_contact_phone (empty string clears it on update)
      form.append("reminder_contact_phone", formData.reminderContactPhone.trim());
      // Always send contribution_payment_instructions (empty string clears it on update)
      form.append("contribution_payment_instructions", formData.contributionPaymentInstructions.trim());

      // What to Expect (always send so it can be cleared)
      const wte = whatToExpectItems
        .map((it) => ({
          icon: (it.icon || "sparkle").trim(),
          label: it.label.trim(),
          description: it.description.trim(),
        }))
        .filter((it) => it.label);
      form.append("what_to_expect", wte.length ? JSON.stringify(wte) : "");
      form.append("what_to_expect_notes", whatToExpectNotes.trim());

      // Ticketing flags
      form.append("sells_tickets", ticketingEnabled ? "true" : "false");
      form.append("is_public", isPublicEvent ? "true" : "false");

      // Event owner fields
      form.append("created_for_someone_else", createdForSomeoneElse ? "true" : "false");
      if (createdForSomeoneElse) {
        if (eventOwner?.id) form.append("event_owner_user_id", eventOwner.id);
        if (recognizableOwnerName.trim()) {
          form.append("recognizable_event_owner_name", recognizableOwnerName.trim());
        }
      } else {
        // Explicitly clear on update when toggled back off
        if (editId) {
          form.append("event_owner_user_id", "");
          form.append("recognizable_event_owner_name", "");
        }
      }

      if (images.length > 0) {
        images.forEach((file) => form.append("images", file));
      }

      const response = editId
        ? await eventsApi.update(editId, form)
        : await eventsApi.create(form);

      if (showApiErrors(response, "Failed to save event")) {
        return;
      }

      const createdId = (response.data as any)?.id || editId;

      // Assign selected services to the event
      if (selectedServices.length > 0 && createdId) {
        for (const svcId of selectedServices) {
          try {
            await eventsApi.addEventService(createdId, { provider_service_id: svcId });
          } catch {
            // Silent fail for individual service assignments
          }
        }
      }

      // Sync ticket classes if ticketing enabled
      if (ticketingEnabled && createdId) {
        for (const tc of ticketClasses) {
          const tcData = {
            name: tc.name,
            description: tc.description,
            price: parseFloat(String(tc.price).replace(/[^0-9.]/g, "")) || 0,
            quantity: parseInt(String(tc.quantity).replace(/[^0-9]/g, ""), 10) || 1,
          };
          try {
            if (tc.id) {
              // Update existing ticket class
              await ticketingApi.updateTicketClass(tc.id, tcData);
            } else {
              // Create new ticket class
              await ticketingApi.createTicketClass(createdId, tcData);
            }
          } catch {
            // Silent fail for individual ticket classes
          }
        }
      }

      toast.success(response.message || (editId ? "Event updated successfully." : "Event created successfully."), { id: tid });
      if (!editId) {
        navigate(`/event-management/${createdId}`);
      }
    } catch (err: any) {
      console.error("Event API error:", err);
      toast.dismiss(tid);
      showCaughtError(err);
    } finally {
      setIsSubmitting(false);
    }
  };

  useWorkspaceMeta({
    title: t("create_event"),
    description: "Plan your perfect event with comprehensive tools for weddings, birthdays, memorials, and more.",
  });

  return (
    <div>
      <div className="flex items-center gap-2 mb-4">
        <div className="flex-1 min-w-0">
          <h1 className="text-xl sm:text-2xl md:text-3xl font-bold text-foreground mb-1 break-words leading-tight">
            {editId ? 'Edit Event' : 'Create New Event'}
          </h1>
          <p className="text-sm text-muted-foreground">
            {editId ? 'Update your event details' : 'Plan your perfect event with our comprehensive toolkit'}
          </p>
        </div>
        <Button
          variant="ghost"
          size="icon"
          className="flex-shrink-0"
          aria-label="Back"
          onClick={() => navigate('/my-events')}
        >
          <ChevronLeft className="w-5 h-5" />
        </Button>
      </div>

      <AgreementModal
          open={showAgreementModal}
          onClose={() => { setShowAgreementModal(false); if (!agreementAccepted) navigate('/my-events'); }}
          onAccepted={() => { setAgreementAccepted(true); setShowAgreementModal(false); }}
          agreementType="organiser_agreement"
          updateSummary={agreementSummary}
        />

      <form onSubmit={handleSubmit} className="space-y-6">
        <Card>
          <CardHeader>
            <CardTitle>Event Details</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            {/* Event Type Selection */}
            <div>
              <label className="block text-sm font-medium mb-3">
                What type of event are you planning? <span className="text-destructive">*</span>
              </label>
              {loadingEventTypes ? (
                <div className="grid grid-cols-3 md:grid-cols-4 gap-3">
                  {[1,2,3,4,5,6].map(i => (
                    <div key={i} className="p-4 rounded-xl border border-border animate-pulse">
                      <div className="w-10 h-10 bg-muted rounded-lg mx-auto mb-2" />
                      <div className="h-3 bg-muted rounded w-16 mx-auto" />
                    </div>
                  ))}
                </div>
              ) : displayedEventTypes.length === 0 ? (
                <p className="text-sm text-muted-foreground p-4 text-center border border-dashed rounded-lg">No event types available</p>
              ) : (
                <div className="grid grid-cols-3 md:grid-cols-4 gap-3">
                  {displayedEventTypes.map((type) => (
                    <button
                      key={type.id}
                      type="button"
                      onClick={() => setFormData({ ...formData, eventType: type.id })}
                      className={cn(
                        "flex flex-col items-center gap-2 p-4 rounded-xl border-2 text-center transition-all duration-200 group cursor-pointer",
                        formData.eventType === type.id
                          ? "border-primary bg-primary/10 shadow-sm ring-1 ring-primary/20"
                          : "border-border hover:border-primary/30 hover:bg-muted/50"
                      )}
                    >
                      <div className={cn(
                        "w-10 h-10 rounded-lg flex items-center justify-center transition-transform duration-200",
                        formData.eventType === type.id
                          ? "bg-primary/15 scale-110"
                          : "bg-muted group-hover:scale-105"
                      )}>
                        <EventIcon iconName={type.icon} size={24} />
                      </div>
                      <span className={cn(
                        "text-xs font-medium leading-tight",
                        formData.eventType === type.id ? "text-primary" : "text-foreground"
                      )}>{type.name}</span>
                    </button>
                  ))}
                </div>
              )}
              {!formData.eventType && !loadingEventTypes && displayedEventTypes.length > 0 && (
                <p className="text-xs text-destructive mt-1">Please select an event type</p>
              )}
            </div>

            {/* Title and Location */}
            <div className="grid md:grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium mb-2">{t('event_title_label')}</label>
                <Input
                  placeholder={t('event_title_placeholder')}
                  value={formData.title}
                  onChange={(e) => setFormData({ ...formData, title: e.target.value })}
                  className={cn(titleTooLong && "border-destructive focus-visible:ring-destructive")}
                  required
                  autoComplete="off"
                />
                {titleTooLong && (
                  <p className="text-xs text-destructive mt-1">Title must be under 100 characters ({formData.title.length}/100)</p>
                )}
              </div>
              <div>
                <label className="block text-sm font-medium mb-2">
                  {t('location_label')} <span className="text-muted-foreground font-normal">(optional)</span>
                </label>
                <Input
                  placeholder={t('event_venue_placeholder')}
                  value={formData.location}
                  onChange={(e) => setFormData({ ...formData, location: e.target.value })}
                  autoComplete="off"
                />
                <p className="text-xs text-muted-foreground mt-1">You can add or change the venue later.</p>
              </div>
            </div>

            {/* Venue Map Picker */}
            <div className="space-y-3">
              <div className="flex items-center justify-between gap-3">
                <label className="block text-sm font-medium">{t('pin_venue_map')}</label>
                {formData.venueLatitude !== null && formData.venueLongitude !== null && (
                  <span className="text-xs text-muted-foreground">
                    {formData.venueLatitude.toFixed(5)}, {formData.venueLongitude.toFixed(5)}
                  </span>
                )}
              </div>

              {formData.venueAddress && (
                <p className="text-xs text-muted-foreground">
                  📍 {formData.venueAddress}
                </p>
              )}

              <MapLocationPicker
                onChange={(location) => {
                  if (!location) {
                    setFormData((prev) => ({
                      ...prev,
                      venueLatitude: null,
                      venueLongitude: null,
                      venueAddress: "",
                      venueName: "",
                    }));
                    return;
                  }

                  setFormData((prev) => ({
                    ...prev,
                    venueLatitude: location.latitude,
                    venueLongitude: location.longitude,
                    venueAddress: location.address || "",
                    venueName: location.name || "",
                    location: prev.location || location.address || location.name || "",
                  }));
                }}
                value={
                  formData.venueLatitude !== null && formData.venueLongitude !== null
                    ? {
                        latitude: formData.venueLatitude,
                        longitude: formData.venueLongitude,
                        name: formData.venueName,
                        address: formData.venueAddress,
                      }
                    : null
                }
              />

              {formData.venueLatitude !== null && formData.venueLongitude !== null && (
                <VenueMapPreview
                  key={`${formData.venueLatitude}-${formData.venueLongitude}`}
                  latitude={formData.venueLatitude}
                  longitude={formData.venueLongitude}
                  venueName={formData.venueName || formData.location || undefined}
                  address={formData.venueAddress || undefined}
                  height="240px"
                />
              )}
            </div>

            {/* Description */}
            <div>
              <label className="block text-sm font-medium mb-2">{t('description')}</label>
              <Textarea
                placeholder={t('describe_event')}
                value={formData.description}
                onChange={(e) => setFormData({ ...formData, description: e.target.value })}
                className={cn(descTooLong && "border-destructive focus-visible:ring-destructive")}
                rows={4}
              />
              {descTooLong && (
                <p className="text-xs text-destructive mt-1">Description must be under 2,000 characters ({formData.description.length}/2,000)</p>
              )}
            </div>

            {/* Event Owner - creating for someone else */}
            <div className="rounded-xl border-2 border-primary/40 bg-amber-50/60 dark:bg-primary/10 p-4 space-y-3 shadow-sm">
              <div className="flex items-start justify-between gap-3">
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium">I am creating this event for someone else</p>
                  <p className="text-xs text-muted-foreground mt-0.5">
                    Turn this on if the actual event owner is a different person. You will remain the
                    creator.
                  </p>
                </div>
                <Switch
                  checked={createdForSomeoneElse}
                  onCheckedChange={(v) => {
                    setCreatedForSomeoneElse(v);
                    if (!v) {
                      setEventOwner(null);
                      setRecognizableOwnerName("");
                    }
                  }}
                />
              </div>

              {createdForSomeoneElse && (
                <div className="space-y-3 pt-1">
                  <div>
                    <label className="block text-xs font-medium mb-1.5 text-muted-foreground">
                      Search owner by name, phone or email <span className="text-destructive">*</span>
                    </label>
                    {eventOwner ? (
                      <div className="flex items-center gap-3 p-3 rounded-lg border border-border bg-background">
                        <Avatar className="w-9 h-9">
                          <AvatarImage src={eventOwner.avatar || undefined} />
                          <AvatarFallback className="text-xs font-semibold bg-primary text-primary-foreground">
                            {eventOwner.first_name?.charAt(0)}{eventOwner.last_name?.charAt(0)}
                          </AvatarFallback>
                        </Avatar>
                        <div className="flex-1 min-w-0">
                          <p className="text-sm font-medium truncate">
                            {eventOwner.full_name || `${eventOwner.first_name} ${eventOwner.last_name}`.trim()}
                          </p>
                          <p className="text-xs text-muted-foreground truncate">
                            {eventOwner.username ? `@${eventOwner.username}` : ""}
                            {eventOwner.phone ? ` - ${eventOwner.phone}` : ""}
                            {eventOwner.email ? ` - ${eventOwner.email}` : ""}
                          </p>
                        </div>
                        <Button type="button" variant="ghost" size="sm" onClick={() => setEventOwner(null)}>
                          Change
                        </Button>
                      </div>
                    ) : (
                      <UserSearchInput
                        onSelect={(u) => setEventOwner(u)}
                        placeholder="Search by name, phone or email…"
                        allowRegister
                      />
                    )}
                    <p className="text-[11px] text-muted-foreground mt-1.5">
                      Can't find them? Register them with name and phone · we'll send them a secure
                      link to claim the account.
                    </p>
                  </div>

                  <div>
                    <label className="block text-xs font-medium mb-1.5 text-muted-foreground">
                      How should the owner be referred to in messages?{" "}
                      <span className="text-muted-foreground/70 font-normal">(optional)</span>
                    </label>
                    <Input
                      placeholder='e.g. "Mr. & Mrs. Mwangi" or "The Juma Family"'
                      value={recognizableOwnerName}
                      onChange={(e) => setRecognizableOwnerName(e.target.value)}
                      autoComplete="off"
                    />
                    <p className="text-[11px] text-muted-foreground mt-1">
                      Leave blank to use the owner's account name in all notifications.
                    </p>
                  </div>
                </div>
              )}
            </div>

            {/* Reminder contact phone (used in contributor reminder messages) */}
            <div>
              <label className="block text-sm font-medium mb-2">
                Reminder contact phone <span className="text-muted-foreground font-normal">(optional)</span>
              </label>
              <Input
                type="tel"
                placeholder="e.g. 0712 345 678"
                value={formData.reminderContactPhone}
                onChange={(e) => setFormData({ ...formData, reminderContactPhone: e.target.value })}
              />
              <p className="text-[11px] text-muted-foreground mt-1">
                Shown in reminder & thank-you messages so contributors know who to call.
                Defaults to your account phone if left blank.
              </p>
            </div>

            {/* Contributor payment instructions */}
            <div>
              <label className="block text-sm font-medium mb-2">
                Contributor payment instructions <span className="text-muted-foreground font-normal">(optional)</span>
              </label>
              <Textarea
                placeholder="e.g. Send via M-Pesa to 0712 345 678 (Lipa Namba 12345), or deposit to CRDB account 0150123456789."
                value={formData.contributionPaymentInstructions}
                onChange={(e) => setFormData({ ...formData, contributionPaymentInstructions: e.target.value })}
                rows={3}
                maxLength={500}
              />
              <p className="text-[11px] text-muted-foreground mt-1">
                Explain how contributors should complete their payment. This will be included in contribution target messages.
              </p>
            </div>

            {/* What to Expect */}
            <div>
              <label className="block text-sm font-medium mb-2">
                What to expect <span className="text-muted-foreground font-normal">(optional)</span>
              </label>
              <p className="text-[11px] text-muted-foreground mb-3">
                Short list so guests know what to look forward to. Leave blank to hide this section on the public page.
              </p>
              <div className="space-y-2.5">
                {whatToExpectItems.map((it, idx) => (
                  <div key={idx} className="rounded-lg border border-border p-3 bg-background">
                    <div className="flex items-start gap-2.5">
                      <select
                        value={it.icon}
                        onChange={(e) => {
                          const next = [...whatToExpectItems];
                          next[idx] = { ...next[idx], icon: e.target.value };
                          setWhatToExpectItems(next);
                        }}
                        className="h-9 rounded-md border border-input bg-background px-2 text-xs"
                        aria-label="Icon"
                      >
                        {WTE_ICON_CHOICES.map((n) => (
                          <option key={n} value={n}>{n}</option>
                        ))}
                      </select>
                      <Input
                        placeholder="e.g. Live music"
                        value={it.label}
                        onChange={(e) => {
                          const next = [...whatToExpectItems];
                          next[idx] = { ...next[idx], label: e.target.value };
                          setWhatToExpectItems(next);
                        }}
                        maxLength={60}
                        className="flex-1"
                      />
                      <Button
                        type="button"
                        variant="ghost"
                        size="icon"
                        className="h-9 w-9 flex-shrink-0"
                        onClick={() => setWhatToExpectItems(whatToExpectItems.filter((_, i) => i !== idx))}
                        aria-label="Remove"
                      >
                        <X className="w-4 h-4" />
                      </Button>
                    </div>
                    <Input
                      placeholder="Short description (optional)"
                      value={it.description}
                      onChange={(e) => {
                        const next = [...whatToExpectItems];
                        next[idx] = { ...next[idx], description: e.target.value };
                        setWhatToExpectItems(next);
                      }}
                      maxLength={120}
                      className="mt-2"
                    />
                  </div>
                ))}
                {whatToExpectItems.length < 12 && (
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    onClick={() => setWhatToExpectItems([...whatToExpectItems, { icon: "sparkle", label: "", description: "" }])}
                  >
                    + Add item
                  </Button>
                )}
              </div>
              <div className="mt-4">
                <label className="block text-sm font-medium mb-2">
                  Additional notes <span className="text-muted-foreground font-normal">(optional)</span>
                </label>
                <Textarea
                  placeholder="Anything else guests should know · schedule notes, parking, dress code reminders, etc."
                  value={whatToExpectNotes}
                  onChange={(e) => setWhatToExpectNotes(e.target.value)}
                  rows={3}
                  maxLength={1000}
                />
              </div>
            </div>


            {/* Date, Time, Guests */}
            <div className="grid md:grid-cols-3 gap-4">
              <div>
                <label className="block text-sm font-medium mb-2">{t('event_date')}</label>
                <Popover open={datePickerOpen} onOpenChange={setDatePickerOpen}>
                  <PopoverTrigger asChild>
                    <Button
                      variant="outline"
                      className={cn(
                        "w-full justify-start text-left font-normal",
                        !formData.date && "text-muted-foreground"
                      )}
                    >
                      <img src={CalendarIcon} alt="Calendar" className="mr-2 h-4 w-4" />
                      {formData.date ? format(formData.date, "PPP") : t("select_date")}
                    </Button>
                  </PopoverTrigger>
                  <PopoverContent className="w-auto p-0" align="start">
                    <CalendarComponent
                      mode="single"
                      selected={formData.date}
                      onSelect={(date) => { setFormData({ ...formData, date }); setDatePickerOpen(false); }}
                      initialFocus
                      className="p-3 pointer-events-auto"
                    />
                  </PopoverContent>
                </Popover>
              </div>
              <div>
                <label className="block text-sm font-medium mb-2">{t('time')}</label>
                <Input
                  type="time"
                  value={formData.time}
                  onChange={(e) => setFormData({ ...formData, time: e.target.value })}
                  required
                />
              </div>
              <div>
                <label className="block text-sm font-medium mb-2">{t('expected_guests')}</label>
                <FormattedNumberInput
                  placeholder="50"
                  value={formData.expectedGuests}
                  onChange={(v) => setFormData({ ...formData, expectedGuests: v })}
                  className={cn(guestsError && "border-destructive focus-visible:ring-destructive")}
                />
                {guestsError && (
                  <p className="text-xs text-destructive mt-1">{guestsError}</p>
                )}
              </div>
            </div>

            {/* Budget */}
            <div>
              <div className="flex items-center justify-between mb-2">
                <label className="block text-sm font-medium">{t('estimated_budget')}</label>
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  className="gap-1.5 text-xs h-8 rounded-lg border-foreground/20 hover:bg-foreground hover:text-background transition-colors"
                  onClick={() => setBudgetAssistantOpen(true)}
                >
                  <SvgIcon src={PackageIcon} alt="" className="w-4 h-4" />
                  Budget Assistant
                </Button>
              </div>
              <FormattedNumberInput
                placeholder="e.g., 5,000,000"
                value={formData.budget}
                onChange={(v) => setFormData({ ...formData, budget: v })}
                className={cn(budgetError && "border-destructive focus-visible:ring-destructive")}
              />
              {budgetError && (
                <p className="text-xs text-destructive mt-1">{budgetError}</p>
              )}
            </div>
          </CardContent>
        </Card>

        {/* Budget Assistant Dialog */}
        <BudgetAssistant
          open={budgetAssistantOpen}
          onOpenChange={setBudgetAssistantOpen}
          eventContext={{
            eventType: formData.eventType,
            eventTypeName: displayedEventTypes.find(t => t.id === formData.eventType)?.name,
            title: formData.title,
            location: formData.location,
            expectedGuests: formData.expectedGuests,
            budget: formData.budget,
          }}
          onSaveBudget={(amount) => setFormData(prev => ({ ...prev, budget: amount }))}
        />

        {/* Ticketing */}
        <EventTicketing
          enabled={ticketingEnabled}
          onEnabledChange={setTicketingEnabled}
          ticketClasses={ticketClasses}
          onTicketClassesChange={setTicketClasses}
          isPublicEvent={isPublicEvent}
          onPublicChange={setIsPublicEvent}
          onDeleteTicketClass={async (classId) => {
            try {
              await ticketingApi.deleteTicketClass(classId);
            } catch {
              // Will be removed from local state regardless
            }
          }}
        />

        <Card>
          <CardHeader>
            <CardTitle>{t('event_media')}</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            {/* Image Upload */}
            <div>
              <label className="block text-sm font-medium mb-2">{t('event_images_optional')}</label>
              <div className="space-y-4">
                {previews.length > 0 && (
                  previews.length === 1 ? (
                    <div className="relative w-full h-64 rounded-lg overflow-hidden border border-border">
                      <img src={previews[0]} alt="preview" className="w-full h-full object-cover" />
                      <button
                        type="button"
                        onClick={() => removeImage(0)}
                        className="absolute top-2 right-2 bg-black/50 text-white p-1 rounded-full hover:bg-black/70 transition-colors"
                      >
                        <X className="w-4 h-4" />
                      </button>
                    </div>
                  ) : (
                    <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
                      {previews.map((src, index) => (
                        <div key={index} className="relative group">
                          <img src={src} alt={`preview ${index}`} className="w-full h-32 object-cover rounded-lg" />
                          <Button
                            type="button"
                            variant="destructive"
                            size="icon"
                            className="absolute top-2 right-2 h-6 w-6 opacity-0 group-hover:opacity-100 transition-opacity"
                            onClick={() => removeImage(index)}
                          >
                            <X className="w-4 h-4" />
                          </Button>
                        </div>
                      ))}
                    </div>
                  )
                )}

                <div className="border-2 border-dashed border-border rounded-lg p-8 text-center">
                  <Upload className="w-12 h-12 mx-auto mb-4 text-muted-foreground" />
                  <p className="text-muted-foreground mb-2">{t('click_upload_drag')}</p>
                  <p className="text-sm text-muted-foreground">{t('file_format_hint')}</p>
                  <label htmlFor="event-image-upload">
                    <Button
                      type="button"
                      variant="outline"
                      className="mt-4"
                      onClick={() => document.getElementById('event-image-upload')?.click()}
                    >
                      {t('choose_files')}
                    </Button>
                  </label>
                  <input
                    id="event-image-upload"
                    type="file"
                    multiple
                    accept="image/*"
                    className="hidden"
                    onChange={handleImageChange}
                  />
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Service recommendations and invitation card picker intentionally
            removed here - they can be set later from the event management
            page once the event exists. */}

        <div className="flex justify-end gap-3">
          <Button type="button" variant="outline" onClick={() => navigate(-1)}>
            {t("cancel")}
          </Button>
          <Button
            type="submit"
            disabled={!formData.title || !formData.date || !formData.eventType || isSubmitting}
          >
            {isSubmitting ? (editId ? t("updating_event") : t("creating_event")) : (editId ? t("update_event") : t("create_event"))}
          </Button>
        </div>
      </form>
    </div>
  );
};

export default CreateEvent;
