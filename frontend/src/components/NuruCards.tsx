import { useState, useRef, useCallback, useEffect } from 'react';
import { CreditCard, Check, Zap, Shield, Gift, Users, Clock, Star, Printer, Download, Loader2, Phone, Package, Award } from 'lucide-react';
import QrIcon from '@/assets/icons/qr-icon.svg';
import SvgIcon from '@/components/ui/svg-icon';
const QrCode = ({ className }: { className?: string }) => <SvgIcon src={QrIcon} alt="QR" className={className} />;
import LocationIcon from '@/assets/icons/location-icon.svg';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog';
import { Textarea } from '@/components/ui/textarea';
import { useWorkspaceMeta } from '@/hooks/useWorkspaceMeta';
import { useToast } from '@/hooks/use-toast';
import { useNuruCard, useNuruCardTypes } from '@/data/useNuruCards';
import { Skeleton } from '@/components/ui/skeleton';
import { QRCodeSVG } from 'qrcode.react';
import { nuruCardsApi, type NuruCardPricing } from '@/lib/api/nuruCards';
import html2canvas from 'html2canvas';
import { useLanguage } from '@/lib/i18n/LanguageContext';
import { useCurrency } from '@/hooks/useCurrency';

const NuruCards = () => {
  const { t } = useLanguage();
  useWorkspaceMeta({
    title: 'Nuru Cards',
    description: 'Get your Nuru Card for seamless event check-ins and exclusive benefits.'
  });

  const { toast } = useToast();
  const { currency, format: formatCurrency } = useCurrency();
  const { card, loading: cardLoading, error: cardError, upgradeCard, refetch } = useNuruCard();
  const { cardTypes, loading: typesLoading } = useNuruCardTypes();
  const printRef = useRef<HTMLDivElement>(null);

  // Pricing pulled from `nuru_card_pricing` table — replaces hardcoded "TZS 50,000".
  const [pricing, setPricing] = useState<NuruCardPricing[]>([]);
  useEffect(() => {
    let cancelled = false;
    nuruCardsApi.getPricing(currency).then((res) => {
      if (!cancelled && res.success) setPricing(res.data || []);
    });
    return () => { cancelled = true; };
  }, [currency]);

  const premiumPrice = pricing.find((p) => p.card_type === 'premium')?.amount ?? 0;
  const standardPrice = pricing.find((p) => p.card_type === 'standard')?.amount ?? 0;

  // Order dialog state
  const [orderOpen, setOrderOpen] = useState(false);
  const [orderType, setOrderType] = useState<'standard' | 'premium'>('standard');
  const [ordering, setOrdering] = useState(false);
  const [orderForm, setOrderForm] = useState({
    holder_name: '',
    template: 'standard_blue',
    nfc_enabled: false,
    delivery_street: '',
    delivery_city: '',
    delivery_postal_code: '',
    delivery_country: 'Tanzania',
    delivery_phone: '',
    payment_method: 'cash',
  });
  const [exporting, setExporting] = useState(false);
  const [orders, setOrders] = useState<any[]>([]);
  const [ordersLoading, setOrdersLoading] = useState(false);

  // Fetch user's card orders
  const fetchOrders = useCallback(async () => {
    setOrdersLoading(true);
    try {
      const res = await nuruCardsApi.getMyOrders();
      if (res.success) setOrders(res.data || []);
    } catch { /* silent */ }
    finally { setOrdersLoading(false); }
  }, []);

  useEffect(() => {
    fetchOrders();
  }, [fetchOrders]);

  const captureCardAsImage = async (): Promise<HTMLCanvasElement | null> => {
    if (!printRef.current) return null;
    return html2canvas(printRef.current, {
      scale: 3,
      useCORS: true,
      backgroundColor: null,
      logging: false,
    });
  };

  const handlePrint = useCallback(async () => {
    setExporting(true);
    try {
      const canvas = await captureCardAsImage();
      if (!canvas) return;
      const imgData = canvas.toDataURL('image/png');
      const printWindow = window.open('', '_blank');
      if (!printWindow) return;
      printWindow.document.write(`
        <!DOCTYPE html><html><head><title>Nuru Card</title>
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          body { display: flex; justify-content: center; align-items: center; min-height: 100vh; background: white; }
          img { max-width: 500px; width: 100%; height: auto; }
          @media print { body { background: white; } }
        </style></head>
        <body><img src="${imgData}" /></body></html>
      `);
      printWindow.document.close();
      setTimeout(() => printWindow.print(), 300);
    } finally {
      setExporting(false);
    }
  }, []);

  const handleDownload = useCallback(async () => {
    setExporting(true);
    try {
      const canvas = await captureCardAsImage();
      if (!canvas) return;
      const link = document.createElement('a');
      link.download = `nuru-card-${card?.card_number || 'card'}.png`;
      link.href = canvas.toDataURL('image/png');
      link.click();
    } finally {
      setExporting(false);
    }
  }, [card]);

  const openOrderDialog = (type: 'standard' | 'premium') => {
    setOrderType(type);
    setOrderForm(prev => ({ ...prev, template: type === 'premium' ? 'gold_premium' : 'standard_blue' }));
    setOrderOpen(true);
  };

  const handleOrderSubmit = async () => {
    if (!orderForm.holder_name.trim()) {
      toast({ title: 'Error', description: 'Please enter the cardholder name.', variant: 'destructive' });
      return;
    }
    if (!orderForm.delivery_phone.trim()) {
      toast({ title: 'Error', description: 'Please enter a delivery phone number.', variant: 'destructive' });
      return;
    }
    setOrdering(true);
    try {
      const res = await nuruCardsApi.orderCard({
        type: orderType,
        holder_name: orderForm.holder_name,
        template: orderForm.template,
        nfc_enabled: orderForm.nfc_enabled,
        delivery_address: {
          street: orderForm.delivery_street,
          city: orderForm.delivery_city,
          postal_code: orderForm.delivery_postal_code,
          country: orderForm.delivery_country,
          phone: orderForm.delivery_phone,
        },
        payment_method: orderForm.payment_method,
      });
      if (res.success) {
        toast({ title: 'Card Ordered!', description: `Your ${orderType} Nuru Card order has been placed successfully.` });
        setOrderOpen(false);
        refetch();
        fetchOrders();
      } else {
        toast({ title: 'Error', description: res.message || 'Failed to order card.', variant: 'destructive' });
      }
    } catch {
      toast({ title: 'Error', description: 'Failed to order card. Please try again.', variant: 'destructive' });
    } finally {
      setOrdering(false);
    }
  };

  const handleUpgrade = async () => {
    try {
      const premiumType = cardTypes.find(ct => ct.name.toLowerCase() === 'premium');
      if (premiumType && card) {
        await upgradeCard(premiumType.id);
        toast({ title: 'Upgraded to Premium!', description: 'You now have access to all premium features and benefits.' });
        refetch();
      } else {
        toast({ title: 'Error', description: 'Premium upgrade not available.', variant: 'destructive' });
      }
    } catch {
      toast({ title: 'Error', description: 'Failed to upgrade card.', variant: 'destructive' });
    }
  };

  const userCardType = card?.card_type?.name?.toLowerCase() || card?.type || 'none';
  const cardNumber = card?.card_number || '';
  const eventsAttended = card?.usage_stats?.events_attended || 0;
  const qrValue = cardNumber ? `https://nuru.tz/card/${cardNumber}` : '';

  const regularFeatures = [
    { icon: QrCode, text: 'QR Code Check-in' },
    { icon: Users, text: 'Access to Events' },
    { icon: Clock, text: 'Event History' },
    { icon: Shield, text: 'Verified Identity' }
  ];

  const premiumFeatures = [
    { icon: QrCode, text: 'Priority QR Check-in' },
    { icon: Users, text: 'VIP Event Access' },
    { icon: Clock, text: 'Full Event History' },
    { icon: Shield, text: 'Verified Identity' },
    { icon: Star, text: 'Priority Support' },
    { icon: Gift, text: 'Exclusive Perks' },
    { icon: Zap, text: 'Early Bird Invites' },
    { icon: Award, text: 'Premium Badge' }
  ];

  const templates = orderType === 'premium'
    ? [
        { value: 'gold_premium', label: 'Gold Premium' },
        { value: 'platinum_premium', label: 'Platinum Premium' },
        { value: 'diamond_premium', label: 'Diamond Premium' },
      ]
    : [
        { value: 'standard_blue', label: 'Standard Blue' },
        { value: 'standard_black', label: 'Standard Black' },
        { value: 'standard_white', label: 'Standard White' },
      ];

  if (cardLoading || typesLoading) {
    return (
      <div className="space-y-6">
        <div className="space-y-2">
          <Skeleton className="h-8 w-40" />
          <Skeleton className="h-4 w-64" />
        </div>
        <Card><CardContent className="p-8"><div className="flex flex-col items-center space-y-4">
          <Skeleton className="w-16 h-16 rounded-full" />
          <Skeleton className="h-6 w-64" />
          <Skeleton className="h-4 w-80" />
        </div></CardContent></Card>
      </div>
    );
  }

  if (cardError) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-center">
          <p className="text-destructive mb-4">Failed to load card information.</p>
          <Button onClick={() => refetch()}>Retry</Button>
        </div>
      </div>
    );
  }

  // ──────────────────────────────────────
  // No card yet — show request/order UI
  // ──────────────────────────────────────
  if (!card || userCardType === 'none') {
    return (
      <div className="space-y-6">
        <div>
          <h1 className="text-3xl font-bold mb-2">Nuru Cards</h1>
          <p className="text-muted-foreground">Get your Nuru Card for instant event check-ins</p>
        </div>

        {/* Hero */}
        <Card className="bg-gradient-to-br from-nuru-yellow/10 to-primary/5 border-nuru-yellow/20">
          <CardContent className="p-8 text-center">
            <div className="w-16 h-16 rounded-full bg-nuru-yellow/20 flex items-center justify-center mx-auto mb-4">
              <CreditCard className="w-8 h-8 text-primary" />
            </div>
            <h2 className="text-2xl font-bold mb-2">Tap and Walk In</h2>
            <p className="text-muted-foreground mb-6">Skip the queues and check in instantly with your Nuru Card.</p>
            <div className="flex items-center justify-center gap-4 text-sm text-muted-foreground flex-wrap">
              {['Instant Check-in', 'Secure & Verified', 'Digital Convenience'].map(t => (
                <div key={t} className="flex items-center gap-2">
                  <Check className="w-4 h-4 text-green-600" />
                  <span>{t}</span>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>

        {/* Card Options */}
        <div className="grid md:grid-cols-2 gap-6">
          {/* Regular */}
          <Card className="hover:shadow-lg transition-shadow">
            <CardHeader>
              <div className="flex items-center justify-between mb-2">
                <CardTitle>Regular Card</CardTitle>
                <Badge variant="outline">FREE</Badge>
              </div>
              <CardDescription>Perfect for event attendees</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="text-3xl font-bold">{formatCurrency(standardPrice)}</div>
              <ul className="space-y-3">
                {regularFeatures.map((f, i) => (
                  <li key={i} className="flex items-center gap-3">
                    <div className="w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center flex-shrink-0">
                      <f.icon className="w-4 h-4 text-primary" />
                    </div>
                    <span className="text-sm">{f.text}</span>
                  </li>
                ))}
              </ul>
              <Button className="w-full mt-4" onClick={() => openOrderDialog('standard')}>
                Request Regular Card
              </Button>
            </CardContent>
          </Card>

          {/* Premium */}
          <Card className="hover:shadow-lg transition-shadow border-primary/50 relative overflow-hidden">
            <div className="absolute top-4 right-4">
              <Badge className="bg-gradient-to-r from-nuru-yellow to-primary text-foreground">POPULAR</Badge>
            </div>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                Premium Card
                <Award className="w-5 h-5 text-primary" />
              </CardTitle>
              <CardDescription>Exclusive benefits and VIP access</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="flex items-baseline gap-2">
                <span className="text-3xl font-bold">{formatCurrency(premiumPrice)}</span>
                <span className="text-muted-foreground">/year</span>
              </div>
              <ul className="space-y-3">
                {premiumFeatures.map((f, i) => (
                  <li key={i} className="flex items-center gap-3">
                    <div className="w-8 h-8 rounded-full bg-gradient-to-br from-nuru-yellow/20 to-primary/20 flex items-center justify-center flex-shrink-0">
                      <f.icon className="w-4 h-4 text-primary" />
                    </div>
                    <span className="text-sm">{f.text}</span>
                  </li>
                ))}
              </ul>
              <Button className="w-full mt-4 bg-gradient-to-r from-nuru-yellow to-primary hover:opacity-90" onClick={() => openOrderDialog('premium')}>
                Request Premium Card
              </Button>
            </CardContent>
          </Card>
        </div>

        {/* How It Works */}
        <Card>
          <CardHeader><CardTitle>How Nuru Cards Work</CardTitle></CardHeader>
          <CardContent>
            <div className="grid md:grid-cols-3 gap-6">
              {[
                { step: '1', title: 'Order Your Card', desc: 'Choose Regular or Premium and fill in your delivery details' },
                { step: '2', title: 'Receive & Activate', desc: 'Get your card delivered and activate it instantly' },
                { step: '3', title: 'Scan & Enjoy', desc: 'Check in to events by scanning your unique QR code' },
              ].map(s => (
                <div key={s.step} className="text-center">
                  <div className="w-12 h-12 rounded-full bg-primary/10 flex items-center justify-center mx-auto mb-3">
                    <span className="text-xl font-bold text-primary">{s.step}</span>
                  </div>
                  <h3 className="font-semibold mb-2">{s.title}</h3>
                  <p className="text-sm text-muted-foreground">{s.desc}</p>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>

        {/* My Orders */}
        {orders.length > 0 && (
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <Package className="w-5 h-5" /> My Card Orders
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="space-y-3">
                {orders.map((order: any) => (
                  <div key={order.id} className="flex items-center justify-between p-3 rounded-lg border border-border">
                    <div>
                      <p className="font-medium capitalize">{order.card_type} Card</p>
                      <p className="text-sm text-muted-foreground">{order.delivery_name} - {order.delivery_city}</p>
                      <p className="text-xs text-muted-foreground">{order.created_at ? new Date(order.created_at).toLocaleDateString() : ''}</p>
                    </div>
                    <div className="text-right">
                      <Badge variant={order.status === 'delivered' ? 'default' : 'outline'} className="capitalize">{order.status}</Badge>
                      {order.amount > 0 && <p className="text-sm font-medium mt-1">{formatCurrency(Number(order.amount))}</p>}
                    </div>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        )}

        {/* Order Dialog */}
        <OrderDialog
          open={orderOpen}
          onClose={() => setOrderOpen(false)}
          orderType={orderType}
          form={orderForm}
          setForm={setOrderForm}
          templates={templates}
          ordering={ordering}
          onSubmit={handleOrderSubmit}
        />
      </div>
    );
  }

  // ──────────────────────────────────────
  // User has a card
  // ──────────────────────────────────────
  const isPremium = userCardType === 'premium';

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold mb-2">My Nuru Card</h1>
        <p className="text-muted-foreground">Your {userCardType} card details</p>
      </div>

      {/* Card Display — captured as image */}
      <div ref={printRef}>
        <Card className={isPremium ? 'bg-gradient-to-br from-nuru-yellow/10 to-primary/10 border-primary/50' : ''}>
          <CardContent className="p-8">
            <div className="flex flex-col md:flex-row items-center gap-8">
              <div className="w-48 h-48 bg-white rounded-xl p-4 border-2 border-border flex items-center justify-center">
                {qrValue ? (
                  <QRCodeSVG value={qrValue} size={160} level="H" includeMargin={false} />
                ) : (
                  <SvgIcon src={QrIcon} alt="QR" className="w-24 h-24 opacity-40" />
                )}
              </div>
              <div className="flex-1">
                <div className="flex items-center gap-2 mb-2">
                  <h2 className="text-2xl font-bold">{isPremium ? 'Premium' : 'Regular'} Nuru Card</h2>
                  {isPremium && (
                    <Badge className="bg-gradient-to-r from-nuru-yellow to-primary text-foreground">
                      <Award className="w-3 h-3 mr-1" />PREMIUM
                    </Badge>
                  )}
                </div>
                <p className="text-muted-foreground mb-6">Use this QR code to check in to any Nuru event</p>
                <div className="grid grid-cols-2 gap-4 mb-6">
                  <div>
                    <p className="text-sm text-muted-foreground">Card Number</p>
                    <p className="font-mono font-semibold">{cardNumber}</p>
                  </div>
                  <div>
                    <p className="text-sm text-muted-foreground">Status</p>
                    <Badge variant="outline" className="text-green-600 border-green-600">{card?.status || 'Active'}</Badge>
                  </div>
                  <div>
                    <p className="text-sm text-muted-foreground">Events Attended</p>
                    <p className="font-semibold">{eventsAttended}</p>
                  </div>
                  <div>
                    <p className="text-sm text-muted-foreground">Valid Until</p>
                    <p className="font-semibold">
                      {card?.valid_until
                        ? new Date(card.valid_until).toLocaleDateString('en-US', { month: 'short', year: 'numeric' })
                        : 'N/A'}
                    </p>
                  </div>
                </div>
                {!isPremium && (
                  <Button onClick={handleUpgrade} className="bg-gradient-to-r from-nuru-yellow to-primary hover:opacity-90">
                    <Award className="w-4 h-4 mr-2" />Upgrade to Premium
                  </Button>
                )}
              </div>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Actions */}
      <div className="flex gap-2">
        <Button variant="outline" onClick={handlePrint} disabled={exporting}>
          <Printer className="w-4 h-4 mr-2" />Print Card
        </Button>
        <Button variant="outline" onClick={handleDownload} disabled={exporting}>
          <Download className="w-4 h-4 mr-2" />Download
        </Button>
      </div>

      {/* Benefits */}
      <Card>
        <CardHeader><CardTitle>Your Benefits</CardTitle></CardHeader>
        <CardContent>
          <div className="grid md:grid-cols-2 gap-4">
            {(isPremium ? premiumFeatures : regularFeatures).map((f, i) => (
              <div key={i} className="flex items-center gap-3 p-3 rounded-lg bg-muted/50">
                <div className="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center flex-shrink-0">
                  <f.icon className="w-5 h-5 text-primary" />
                </div>
                <span className="font-medium">{f.text}</span>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>
    </div>
  );
};

// ──────────────────────────────────────
// Order Dialog Component
// ──────────────────────────────────────
interface OrderDialogProps {
  open: boolean;
  onClose: () => void;
  orderType: 'standard' | 'premium';
  form: any;
  setForm: React.Dispatch<React.SetStateAction<any>>;
  templates: { value: string; label: string }[];
  ordering: boolean;
  onSubmit: () => void;
}

const OrderDialog = ({ open, onClose, orderType, form, setForm, templates, ordering, onSubmit }: OrderDialogProps) => {
  const update = (field: string, value: any) => setForm((prev: any) => ({ ...prev, [field]: value }));

  return (
    <Dialog open={open} onOpenChange={onClose}>
      <DialogContent className="max-w-md max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Order {orderType === 'premium' ? 'Premium' : 'Regular'} Nuru Card</DialogTitle>
          <DialogDescription>Fill in your details to order your card</DialogDescription>
        </DialogHeader>

        <div className="space-y-4 py-2">
          <div className="space-y-2">
            <Label htmlFor="holder_name">Cardholder Name *</Label>
            <Input
              id="holder_name"
              placeholder="Full name as it appears on the card"
              value={form.holder_name}
              onChange={e => update('holder_name', e.target.value)}
            />
          </div>

          <div className="space-y-2">
            <Label>Card Design</Label>
            <Select value={form.template} onValueChange={v => update('template', v)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {templates.map(t => (
                  <SelectItem key={t.value} value={t.value}>{t.label}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {orderType === 'premium' && (
            <div className="flex items-center gap-3">
              <input
                type="checkbox"
                id="nfc"
                checked={form.nfc_enabled}
                onChange={e => update('nfc_enabled', e.target.checked)}
                className="rounded"
              />
              <Label htmlFor="nfc" className="font-normal">Enable NFC tap-to-check-in</Label>
            </div>
          )}

          <div className="border-t pt-4">
            <p className="font-semibold text-sm mb-3 flex items-center gap-2">
              <img src={LocationIcon} alt="Location" className="w-4 h-4" /> Delivery Address
            </p>
            <div className="space-y-3">
              <Input placeholder="Street address" value={form.delivery_street} onChange={e => update('delivery_street', e.target.value)} />
              <div className="grid grid-cols-2 gap-3">
                <Input placeholder="City" value={form.delivery_city} onChange={e => update('delivery_city', e.target.value)} />
                <Input placeholder="Postal code" value={form.delivery_postal_code} onChange={e => update('delivery_postal_code', e.target.value)} />
              </div>
              <Input placeholder="Country" value={form.delivery_country} onChange={e => update('delivery_country', e.target.value)} />
              <div className="space-y-2">
                <Label htmlFor="delivery_phone">Phone Number *</Label>
                <Input id="delivery_phone" placeholder="+255..." value={form.delivery_phone} onChange={e => update('delivery_phone', e.target.value)} />
              </div>
            </div>
          </div>

          <div className="space-y-2">
            <Label>Payment Method</Label>
            <Select value={form.payment_method} onValueChange={v => update('payment_method', v)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="cash">Cash</SelectItem>
                <SelectItem value="mobile">Mobile Money</SelectItem>
                <SelectItem value="card">Card</SelectItem>
                <SelectItem value="bank_transfer">Bank Transfer</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={ordering}>Cancel</Button>
          <Button onClick={onSubmit} disabled={ordering}>
            {ordering && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}
            Place Order
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};

export default NuruCards;
