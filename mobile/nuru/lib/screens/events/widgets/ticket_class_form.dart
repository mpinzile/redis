import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/widgets/app_snackbar.dart';

class TicketClassData {
  String? id;
  String name;
  String description;
  double price;
  int quantity;
  int sold;

  TicketClassData({
    this.id,
    this.name = '',
    this.description = '',
    this.price = 0,
    this.quantity = 0,
    this.sold = 0,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'price': price,
    'quantity': quantity,
  };

  factory TicketClassData.fromJson(Map<String, dynamic> json) {
    return TicketClassData(
      id: json['id']?.toString(),
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      price: double.tryParse(json['price']?.toString() ?? '0') ?? 0,
      quantity: int.tryParse(json['quantity']?.toString() ?? '0') ?? 0,
      sold: int.tryParse(json['sold']?.toString() ?? '0') ?? 0,
    );
  }
}

class TicketClassFormSheet extends StatefulWidget {
  final TicketClassData? editData;
  final void Function(TicketClassData data) onSave;

  const TicketClassFormSheet({super.key, this.editData, required this.onSave});

  @override
  State<TicketClassFormSheet> createState() => _TicketClassFormSheetState();
}

class _TicketClassFormSheetState extends State<TicketClassFormSheet> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();

  static const List<String> _suggestions = ['Regular', 'VIP', 'VVIP', 'Early Bird', 'Student', 'Group'];

  bool get _isEdit => widget.editData != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final d = widget.editData!;
      _nameCtrl.text = d.name;
      _descCtrl.text = d.description;
      _priceCtrl.text = d.price > 0 ? d.price.toStringAsFixed(0) : '';
      _qtyCtrl.text = d.quantity > 0 ? d.quantity.toString() : '';
    }
    _nameCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_nameCtrl.text.trim().isEmpty) {
      AppSnackbar.error(context, 'Ticket class name is required');
      return;
    }
    final price = double.tryParse(_priceCtrl.text.replaceAll(',', '')) ?? 0;
    if (price <= 0) {
      AppSnackbar.error(context, 'Price must be greater than 0');
      return;
    }
    final qty = int.tryParse(_qtyCtrl.text.replaceAll(',', '')) ?? 0;
    if (qty <= 0) {
      AppSnackbar.error(context, 'Quantity must be greater than 0');
      return;
    }

    widget.onSave(TicketClassData(
      id: widget.editData?.id,
      name: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      price: price,
      quantity: qty,
      sold: widget.editData?.sold ?? 0,
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.borderLight, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 18),
              // Header with icon
              Row(children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: SvgPicture.asset('assets/icons/ticket-icon.svg', width: 20, height: 20,
                      colorFilter: const ColorFilter.mode(AppColors.primary, BlendMode.srcIn)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_isEdit ? 'Edit ticket class' : 'New ticket class',
                    style: appText(size: 17, weight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text('Set the name, price and quantity available.',
                    style: appText(size: 12, color: AppColors.textTertiary)),
                ])),
              ]),
              const SizedBox(height: 20),

              _label('Class name'),
              _textField(_nameCtrl, 'e.g. Regular, VIP, Early Bird'),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: _suggestions.map((s) {
                final active = _nameCtrl.text.trim().toLowerCase() == s.toLowerCase();
                return InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () { _nameCtrl.text = s; _nameCtrl.selection = TextSelection.collapsed(offset: s.length); },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: active ? AppColors.primary.withOpacity(0.12) : AppColors.surfaceVariant.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: active ? AppColors.primary : AppColors.borderLight),
                    ),
                    child: Text(s, style: appText(
                      size: 11.5,
                      weight: FontWeight.w600,
                      color: active ? AppColors.primary : AppColors.textSecondary,
                    )),
                  ),
                );
              }).toList()),
              const SizedBox(height: 18),

              _label('Description'),
              _textField(_descCtrl, 'What is included in this ticket?', maxLines: 2),
              const SizedBox(height: 18),

              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _label('Price (${getActiveCurrency()})'),
                  _textField(_priceCtrl, '50,000', keyboard: TextInputType.number),
                ])),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _label('Quantity'),
                  _textField(_qtyCtrl, '100', keyboard: TextInputType.number),
                ])),
              ]),
              const SizedBox(height: 24),

              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.borderLight),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Cancel', style: appText(size: 14, weight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(_isEdit ? 'Save changes' : 'Add ticket class',
                      style: appText(size: 14, weight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: appText(size: 12.5, weight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.2)),
  );

  Widget _textField(TextEditingController ctrl, String hint, {int maxLines = 1, TextInputType? keyboard}) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboard,
      autocorrect: false,
      style: appText(size: 14.5),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: appText(size: 13, color: AppColors.textHint),
        filled: true,
        fillColor: AppColors.surfaceVariant.withOpacity(0.55),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.primary.withOpacity(0.55), width: 1.2),
        ),
      ),
    );
  }
}
