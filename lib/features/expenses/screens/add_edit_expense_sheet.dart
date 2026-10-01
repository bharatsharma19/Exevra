import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_helpers.dart';
import '../../../core/utils/validators.dart';
import '../../../core/utils/haptics.dart';
import '../../../models/expense_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/expense_provider.dart';

class AddEditExpenseSheet extends ConsumerStatefulWidget {
  final Expense? existingExpense;

  const AddEditExpenseSheet({super.key, this.existingExpense});

  static Future<void> show(BuildContext context, {Expense? expense}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddEditExpenseSheet(existingExpense: expense),
    );
  }

  @override
  ConsumerState<AddEditExpenseSheet> createState() => _AddEditExpenseSheetState();
}

class _AddEditExpenseSheetState extends ConsumerState<AddEditExpenseSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _amountController;
  late final TextEditingController _notesController;

  late String _selectedCategory;
  late DateTime _selectedDate;
  late bool _isGroupExpense;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final expense = widget.existingExpense;
    _titleController = TextEditingController(text: expense?.title ?? '');
    _amountController = TextEditingController(
      text: expense != null ? expense.amount.toStringAsFixed(2) : '',
    );
    _notesController = TextEditingController(text: expense?.notes ?? '');
    _selectedCategory = expense?.category ?? AppConstants.categories.first.name;
    _selectedDate = expense?.date ?? DateTime.now();
    _isGroupExpense = expense != null ? !expense.isPersonal : false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    AppHaptics.selection();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedDate),
      );
      final finalTime = pickedTime ?? TimeOfDay.fromDateTime(_selectedDate);
      setState(() {
        _selectedDate = DateTime(
          picked.year,
          picked.month,
          picked.day,
          finalTime.hour,
          finalTime.minute,
        );
      });
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final amount = CurrencyFormatter.parseAmount(_amountController.text);
    if (amount == null || amount <= 0) return;

    final authState = ref.read(authNotifierProvider);
    final expenseState = ref.read(expenseProvider);
    final currentUserId = authState.user?.id;

    if (_isGroupExpense && !expenseState.canUserAddGroupExpenses(currentUserId)) {
      setState(() => _isSubmitting = false);
      AppHaptics.error();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pending Admin Review: You have view-only access until the Group Admin approves your membership to record expenses.'),
          backgroundColor: AppColors.primaryRose,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    AppHaptics.light();

    final expenseNotifier = ref.read(expenseProvider.notifier);

    bool success;
    if (widget.existingExpense == null) {
      success = await expenseNotifier.createExpense(
        title: _titleController.text.trim(),
        amount: amount,
        category: _selectedCategory,
        date: _selectedDate,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        isGroup: _isGroupExpense,
      );
    } else {
      final updated = widget.existingExpense!.copyWith(
        title: _titleController.text.trim(),
        amount: amount,
        category: _selectedCategory,
        date: _selectedDate,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        groupId: _isGroupExpense ? (widget.existingExpense!.groupId ?? ref.read(authNotifierProvider).profile?.groupId) : null,
        isPersonal: !_isGroupExpense,
      );
      success = await expenseNotifier.updateExpense(updated);
    }

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (success) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = ref.watch(authNotifierProvider);
    final currency = auth.profile?.currency ?? AppConstants.defaultCurrency;
    final symbol = AppConstants.currencies[currency] ?? '₹';
    final expenseState = ref.watch(expenseProvider);
    final hasGroup = expenseState.currentGroup != null;
    final currentUserId = auth.user?.id;
    final isViewer = expenseState.isUserViewerOnly(currentUserId);
    final isEditing = widget.existingExpense != null;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            width: 1.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Sheet Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isEditing ? 'Edit Expense' : 'Add Expense',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Amount Large Numeric Input Card
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: isDark
                        ? AppColors.darkCardElevated.withValues(alpha: 0.8)
                        : AppColors.lightCardElevated,
                    border: Border.all(
                      color: AppColors.primaryCyan.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        symbol,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryCyan,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: Validators.validateAmount,
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                          decoration: const InputDecoration(
                            hintText: '0.00',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            filled: false,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Title Input
                TextFormField(
                  controller: _titleController,
                  textCapitalization: TextCapitalization.sentences,
                  validator: (v) => Validators.validateRequired(v, 'Expense title'),
                  decoration: const InputDecoration(
                    labelText: 'Expense Title',
                    hintText: 'e.g. Whole Foods Organic Groceries',
                    prefixIcon: Icon(Icons.receipt_long_rounded),
                  ),
                ),

                const SizedBox(height: 18),

                // Expense Type Toggle: Personal vs Group
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          AppHaptics.selection();
                          setState(() => _isGroupExpense = false);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: !_isGroupExpense
                                ? AppColors.primaryCyan.withValues(alpha: 0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: !_isGroupExpense
                                  ? AppColors.primaryCyan
                                  : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                              width: !_isGroupExpense ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.person_rounded,
                                size: 18,
                                color: !_isGroupExpense ? AppColors.primaryCyan : Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Personal',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: !_isGroupExpense
                                      ? AppColors.primaryCyan
                                      : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (!hasGroup) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please join or create a Group in Profile first!'),
                                backgroundColor: AppColors.warning,
                              ),
                            );
                            return;
                          }
                          if (isViewer) {
                            AppHaptics.error();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('View-Only Access: As an invited member, the Group Admin must review & approve your membership before you can add group expenses.'),
                                backgroundColor: AppColors.primaryRose,
                              ),
                            );
                            return;
                          }
                          AppHaptics.selection();
                          setState(() => _isGroupExpense = true);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _isGroupExpense
                                ? AppColors.primaryViolet.withValues(alpha: 0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _isGroupExpense
                                  ? AppColors.primaryViolet
                                  : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                              width: _isGroupExpense ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.groups_rounded,
                                size: 18,
                                color: _isGroupExpense ? AppColors.primaryViolet : Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Group Expense',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: _isGroupExpense
                                      ? AppColors.primaryViolet
                                      : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                if (isViewer) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.shield_outlined, size: 16, color: AppColors.warning),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'View-Only Member: You can view group expenses. The Group Admin must review & approve your membership before you can record group expenses.',
                            style: TextStyle(fontSize: 11, color: AppColors.warning, height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Category Selection Horizontal/Grid Carousel
                const Text(
                  'Category',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 80,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: AppConstants.categories.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 10),
                    itemBuilder: (context, idx) {
                      final cat = AppConstants.categories[idx];
                      final isSelected = _selectedCategory == cat.name;
                      final catColor = AppColors.getCategoryColor(cat.name);

                      return GestureDetector(
                        onTap: () {
                          AppHaptics.selection();
                          setState(() => _selectedCategory = cat.name);
                        },
                        child: Container(
                          width: 76,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: isSelected
                                ? catColor.withValues(alpha: 0.18)
                                : (isDark ? AppColors.darkCardElevated : AppColors.lightCardElevated),
                            border: Border.all(
                              color: isSelected ? catColor : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                cat.icon,
                                color: isSelected ? catColor : (isDark ? Colors.white60 : Colors.black54),
                                size: 24,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                cat.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  color: isSelected ? catColor : (isDark ? Colors.white70 : Colors.black87),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 18),

                // Date Picker Tile
                GestureDetector(
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: isDark ? AppColors.darkCardElevated.withValues(alpha: 0.6) : AppColors.lightCardElevated,
                      border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.calendar_month_rounded, color: AppColors.primaryCyan, size: 20),
                            const SizedBox(width: 12),
                            Text(
                              '${DateHelpers.formatDate(_selectedDate)} • ${DateHelpers.formatTime(_selectedDate)}',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                          ],
                        ),
                        const Icon(Icons.edit_calendar_rounded, size: 18, color: Colors.grey),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Notes Optional
                TextFormField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes (Optional)',
                    hintText: 'Add description, location or tax tag...',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),

                const SizedBox(height: 24),

                // Submit Button
                ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: AppColors.primaryCyan,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.black)),
                        )
                      : Text(
                          isEditing ? 'Save Changes' : 'Record Expense',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
