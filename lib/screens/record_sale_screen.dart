import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/copy.dart';
import '../models/book.dart';
import '../models/contact.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../providers/theme_provider.dart';

class RecordSaleScreen extends StatefulWidget {
  final Copy? copy;
  final Book? book;

  const RecordSaleScreen({Key? key, this.copy, this.book}) : super(key: key);

  @override
  _RecordSaleScreenState createState() => _RecordSaleScreenState();
}

class _RecordSaleScreenState extends State<RecordSaleScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _priceController;
  late TextEditingController _notesController;
  DateTime _selectedDate = DateTime.now();
  Contact? _selectedContact;
  bool _isLoading = false;
  Copy? _selectedCopy;

  @override
  void initState() {
    super.initState();
    _selectedCopy = widget.copy;

    double initialPrice = 0.0;
    if (widget.copy?.price != null) {
      initialPrice = widget.copy!.price!;
    } else if (widget.book?.price != null) {
      initialPrice = widget.book!.price!;
    }

    _priceController = TextEditingController(
      text: initialPrice > 0 ? initialPrice.toString() : '',
    );
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _priceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2010),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _submitSale() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCopy == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TranslationService.translate(context, 'select_copy')),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final double price = double.parse(
        _priceController.text.replaceAll(',', '.'),
      );

      await apiService.recordSale(
        copyId: _selectedCopy!.id!,
        salePrice: price,
        contactId: _selectedContact?.id,
        notes: _notesController.text.isEmpty ? null : _notesController.text,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'sale_recorded'),
            ),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    if (!themeProvider.hasCommerce) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: const Center(child: Text('Commerce module is not enabled.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(TranslationService.translate(context, 'record_sale_title')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.book != null) ...[
                Text(
                  widget.book!.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '${TranslationService.translate(context, 'copy_label')} #${widget.copy?.id ?? '?'}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: Colors.grey),
                ),
                const Divider(height: 32),
              ],

              TextFormField(
                controller: _priceController,
                decoration: InputDecoration(
                  labelText: TranslationService.translate(
                    context,
                    'sale_price',
                  ),
                  prefixText: '€ ',
                  border: const OutlineInputBorder(),
                  helperText: _buildPriceHelperText(context),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return TranslationService.translate(
                      context,
                      'enter_sale_price',
                    );
                  }
                  if (double.tryParse(value.replaceAll(',', '.')) == null) {
                    return TranslationService.translate(
                      context,
                      'invalid_sale_price',
                    );
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              InkWell(
                onTap: () => _selectDate(context),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: TranslationService.translate(
                      context,
                      'sale_date',
                    ),
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.calendar_today),
                  ),
                  child: Text(DateFormat.yMMMd().format(_selectedDate)),
                ),
              ),
              const SizedBox(height: 24),

              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _selectedContact == null
                      ? TranslationService.translate(context, 'select_buyer')
                      : '${_selectedContact!.firstName ?? ''} ${_selectedContact!.name}',
                ),
                leading: const Icon(Icons.person),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () async {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Contact picker not implemented in this step',
                      ),
                    ),
                  );
                },
              ),
              const Divider(),
              const SizedBox(height: 16),

              TextFormField(
                controller: _notesController,
                decoration: InputDecoration(
                  labelText: TranslationService.translate(
                    context,
                    'sale_notes',
                  ),
                  border: const OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitSale,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          TranslationService.translate(context, 'confirm_sale'),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildPriceHelperText(BuildContext context) {
    List<String> parts = [];
    if (widget.copy?.price != null) {
      parts.add(
        '${TranslationService.translate(context, 'copy_price')}: €${widget.copy!.price}',
      );
    }
    if (widget.book?.price != null) {
      parts.add(
        '${TranslationService.translate(context, 'book_price')}: €${widget.book!.price}',
      );
    }
    return parts.join(' | ');
  }
}
