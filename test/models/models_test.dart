import 'package:expense_manager/models/balance.dart';
import 'package:expense_manager/models/expense.dart';
import 'package:expense_manager/models/group.dart';
import 'package:expense_manager/models/insights.dart';
import 'package:expense_manager/models/invitation.dart';
import 'package:expense_manager/models/money.dart';
import 'package:expense_manager/models/profile.dart';
import 'package:expense_manager/models/settlement.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> expenseJson({String? groupId, String? note = 'n'}) => {
  'id': 'e1',
  'user_id': 'u1',
  'group_id': groupId,
  'title': 'Lunch',
  'amount_minor': 125050,
  'currency': 'INR',
  'category': 'Food',
  'spent_at': '2026-11-15T17:00:00+00:00',
  'note': note,
  'receipt_url': null,
  'created_at': '2026-11-15T17:00:01+00:00',
  'updated_at': '2026-11-15T17:00:01+00:00',
};

Map<String, Object?> profileJson() => {
  'id': 'u1',
  'display_name': 'Asha',
  'avatar_url': 'https://cdn.example.com/a.png',
  'email': 'asha@example.com',
  'group_id': 'g1',
  'currency': 'INR',
  'timezone': 'Asia/Kolkata',
  'locale': 'en-IN',
  'theme_mode': 'dark',
  'haptics_enabled': false,
  'ai_consent': true,
  'ai_consent_at': '2026-11-01T00:00:00Z',
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-11-01T00:00:00Z',
};

void main() {
  group('Expense', () {
    test('fromJson reads minor units, currency and a UTC instant', () {
      final e = Expense.fromJson(expenseJson());
      expect(e.amount, Money(125050, 'INR'));
      expect(e.spentAt, DateTime.utc(2026, 11, 15, 17));
      expect(e.spentAt.isUtc, isTrue);
      expect(e.isPersonal, isTrue);
    });

    test('personal vs group comes from groupId only', () {
      expect(Expense.fromJson(expenseJson(groupId: 'g1')).isGroup, isTrue);
      final personal = Expense.fromJson(
        expenseJson(groupId: 'g1'),
      ).copyWith(groupId: null);
      expect(personal.isPersonal, isTrue);
    });

    test('copyWith clears nullable fields when null is passed', () {
      final e = Expense.fromJson(expenseJson(groupId: 'g1'));
      final cleared = e.copyWith(note: null, receiptUrl: null, userId: null);
      expect(cleared.note, isNull);
      expect(cleared.userId, isNull);
      expect(cleared.groupId, 'g1');
      expect(e.copyWith(title: 'Dinner').note, 'n');
    });

    test('update payload sends a cleared note and UTC with Z', () {
      final e = Expense.fromJson(expenseJson()).copyWith(note: null);
      final json = e.toUpdateJson();
      expect(json.containsKey('note'), isTrue);
      expect(json['note'], isNull);
      expect(json['spent_at'], '2026-11-15T17:00:00.000Z');
      expect(json.containsKey('group_id'), isFalse);
      expect(json.containsKey('id'), isFalse);
    });

    test('insert payload has no id or timestamps', () {
      final draft = ExpenseDraft(
        title: '  Taxi ',
        amount: Money(500, 'INR'),
        category: 'Transport',
        spentAt: DateTime.utc(2026, 11, 15, 17),
        note: '  ',
      );
      final json = draft.toInsertJson('u1');
      expect(json['title'], 'Taxi');
      expect(json['note'], isNull);
      expect(json.keys, isNot(contains('id')));
      expect(json.keys, isNot(contains('created_at')));
      expect(draft.validate(), isNull);
    });

    test('rejects malformed rows instead of inventing values', () {
      expect(
        () => Expense.fromJson({...expenseJson(), 'spent_at': null}),
        throwsFormatException,
      );
      expect(
        () => Expense.fromJson({...expenseJson(), 'amount_minor': '12.5'}),
        throwsFormatException,
      );
      expect(
        () => Expense.fromJson({...expenseJson(), 'currency': 'XYZ'}),
        throwsFormatException,
      );
      expect(() => Expense.fromJson('nope'), throwsFormatException);
    });

    test('permissions mirror the server rules', () {
      final personal = Expense.fromJson(expenseJson());
      expect(personal.canEdit('u1'), isTrue);
      expect(personal.canEdit('u2'), isFalse);
      expect(personal.canDelete('u2', isGroupAdmin: true), isFalse);

      final shared = Expense.fromJson(expenseJson(groupId: 'g1'));
      expect(shared.canEdit('u1', canAddToGroup: true), isTrue);
      expect(shared.canEdit('u1'), isFalse, reason: 'viewer or pending');
      expect(shared.canDelete('u2', isGroupAdmin: true), isTrue);
      expect(shared.canDelete('u1', canAddToGroup: true), isTrue);
      expect(shared.canDelete('u2'), isFalse);
      expect(shared.canDelete(null, isGroupAdmin: true), isFalse);
    });
  });

  group('UserProfile', () {
    test('fromJson', () {
      final p = UserProfile.fromJson(profileJson());
      expect(p.activeGroupId, 'g1');
      expect(p.themeMode, ThemePreference.dark);
      expect(p.hapticsEnabled, isFalse);
      expect(p.aiConsent, isTrue);
    });

    test('copyWith clears avatar, active group and locale', () {
      final p = UserProfile.fromJson(profileJson());
      final cleared = p.copyWith(
        avatarUrl: null,
        activeGroupId: null,
        locale: null,
      );
      expect(cleared.avatarUrl, isNull);
      expect(cleared.activeGroupId, isNull);
      expect(cleared.locale, isNull);
      expect(p.copyWith(displayName: 'B').avatarUrl, isNotNull);
    });

    test('ProfileUpdate only writes the fields that were set', () {
      expect(ProfileUpdate(currency: 'USD').fields, {'currency': 'USD'});
      expect(ProfileUpdate(avatarUrl: null).fields, {'avatar_url': null});
      expect(ProfileUpdate().isEmpty, isTrue);
      final f = ProfileUpdate(themeMode: ThemePreference.light).fields;
      expect(f, {'theme_mode': 'light'});
      expect(f.keys, isNot(contains('email')));
      expect(f.keys, isNot(contains('group_id')));
    });

    test('ProfileUpdate validation', () {
      expect(
        ProfileUpdate(displayName: '  ').validate(),
        'invalid_display_name',
      );
      expect(
        ProfileUpdate(avatarUrl: 'http://x').validate(),
        'invalid_avatar_url',
      );
      expect(ProfileUpdate(currency: 'XYZ').validate(), 'invalid_currency');
      expect(ProfileUpdate(currency: 'JPY').validate(), isNull);
    });

    test('apply mirrors the update for optimistic UI', () {
      final p = UserProfile.fromJson(profileJson());
      final next = p.apply(ProfileUpdate(avatarUrl: null, currency: 'USD'));
      expect(next.avatarUrl, isNull);
      expect(next.currency, 'USD');
      expect(next.displayName, 'Asha');
    });
  });

  group('Group and members', () {
    test('group from get_user_groups', () {
      final g = Group.fromJson({
        'id': 'g1',
        'name': 'Flat',
        'currency': 'INR',
        'admin_id': 'u1',
        'created_at': '2026-01-01T00:00:00Z',
        'role': 'admin',
        'status': 'approved',
        'joined_at': '2026-01-01T00:00:00Z',
        'members_count': 3,
        'invite_code': 'ABCDEFGHJKMNPQRS',
        'invite_code_expires_at': '2026-12-01T00:00:00Z',
      });
      expect(g.isAdmin, isTrue);
      expect(g.canAddExpenses, isTrue);
      expect(g.displayInviteCode, 'ABCD-EFGH-JKMN-PQRS');
      expect(g.copyWith(inviteCode: null).inviteCode, isNull);
    });

    test('pending viewer cannot add expenses', () {
      final g = Group.fromJson({
        'id': 'g1',
        'name': 'Flat',
        'currency': 'INR',
        'admin_id': 'u1',
        'created_at': '2026-01-01T00:00:00Z',
        'role': 'viewer',
        'status': 'pending',
      });
      expect(g.isPending, isTrue);
      expect(g.canAddExpenses, isFalse);
      expect(g.canRead, isFalse);
    });

    test('member has no email and a non-blank label', () {
      final m = GroupMember.fromJson({
        'user_id': 'u2',
        'display_name': ' ',
        'avatar_url': null,
        'role': 'member',
        'status': 'approved',
        'joined_at': '2026-01-01T00:00:00Z',
      });
      expect(m.label, 'Member');
      expect(m.canAddExpenses, isTrue);
    });

    test('unknown role is rejected', () {
      expect(
        () => GroupMember.fromJson({
          'user_id': 'u2',
          'role': 'owner',
          'status': 'approved',
        }),
        throwsFormatException,
      );
    });
  });

  group('Invitations', () {
    test('sent-invite result', () {
      final ok = SentInvitation.fromJson({
        'invitation_id': 'i1',
        'sent': true,
        'expires_at': '2026-11-22T00:00:00Z',
      });
      expect(ok.sent, isTrue);
      final manual = SentInvitation.fromJson({
        'invitation_id': 'i1',
        'sent': false,
        'reason': 'email_failed',
        'share_url': 'https://exevra.app/invite/tok',
      });
      expect(manual.shareUrl, 'https://exevra.app/invite/tok');
      expect(
        () => SentInvitation.fromJson({'invitation_id': 'i1', 'sent': false}),
        throwsFormatException,
      );
    });

    test('details and expiry', () {
      final d = InvitationDetails.fromJson({
        'invitation_id': 'i1',
        'group_id': 'g1',
        'group_name': 'Flat',
        'inviter_name': 'Asha',
        'role': 'member',
        'status': 'pending',
        'expires_at': '2026-11-22T00:00:00Z',
      });
      expect(d.isActionableAt(DateTime.utc(2026, 11, 21)), isTrue);
      expect(d.isActionableAt(DateTime.utc(2026, 11, 23)), isFalse);
    });
  });

  group('Settlements and balances', () {
    final json = {
      'id': 's1',
      'group_id': 'g1',
      'from_user': 'u1',
      'to_user': 'u2',
      'amount_minor': 5000,
      'currency': 'INR',
      'status': 'pending',
      'note': null,
      'created_by': 'u1',
      'created_at': '2026-11-15T00:00:00Z',
    };

    test('confirm and void rules', () {
      final s = Settlement.fromJson(json);
      expect(s.canConfirm('u2'), isTrue);
      expect(s.canConfirm('u1'), isFalse);
      expect(s.canVoid('u1', isGroupAdmin: false), isTrue);
      expect(s.canVoid('u3', isGroupAdmin: true), isTrue);
      expect(s.canVoid('u3', isGroupAdmin: false), isFalse);
      final voided = s.copyWith(status: SettlementStatus.voided);
      expect(voided.canVoid('u1', isGroupAdmin: true), isFalse);
    });

    test('balance row and former member', () {
      final b = GroupBalance.fromJson({
        'user_id': null,
        'display_name': null,
        'paid_minor': 0,
        'owed_minor': 100,
        'settled_out_minor': 0,
        'settled_in_minor': 0,
        'net_minor': -100,
        'currency': 'INR',
      });
      expect(b.isFormerMember, isTrue);
      expect(b.displayName, 'Former member');
      expect(b.net, Money(-100, 'INR'));
    });
  });

  group('ExpenseInsights', () {
    Map<String, Object?> rpc() => {
      'currency': 'INR',
      'totals': [
        {'currency': 'INR', 'total_minor': 30000, 'count': 3},
        {'currency': 'USD', 'total_minor': 1000, 'count': 1},
      ],
      'categories': [
        {
          'category': 'Food',
          'currency': 'INR',
          'total_minor': 10000,
          'count': 1,
        },
        {
          'category': 'Housing',
          'currency': 'INR',
          'total_minor': 20000,
          'count': 2,
        },
        {
          'category': 'Food',
          'currency': 'USD',
          'total_minor': 1000,
          'count': 1,
        },
      ],
      'buckets': [
        {
          'bucket': '2026-11-02',
          'currency': 'INR',
          'total_minor': 0,
          'count': 0,
        },
        {
          'bucket': '2026-11-01',
          'currency': 'INR',
          'total_minor': 30000,
          'count': 3,
        },
      ],
      'highest': {
        'id': 'e1',
        'title': 'Rent',
        'category': 'Housing',
        'amount_minor': 20000,
        'currency': 'INR',
        'spent_at': '2026-11-01T04:00:00Z',
      },
    };

    test('keeps one currency and lists the others separately', () {
      final i = ExpenseInsights.fromJson(
        rpc(),
        scope: InsightScope.personal,
        timeframe: InsightTimeframe.month,
        preferredCurrency: 'INR',
      );
      expect(i.total, Money(30000, 'INR'));
      expect(i.categories.first.category, 'Housing');
      expect(i.categories.first.share, closeTo(2 / 3, 1e-9));
      expect(i.buckets.first.date, DateTime.utc(2026, 11, 1));
      expect(i.otherCurrencyTotals, [Money(1000, 'USD')]);
      expect(i.highest?.title, 'Rent');
    });

    test('falls back to the largest currency', () {
      final i = ExpenseInsights.fromJson(
        rpc(),
        scope: InsightScope.personal,
        timeframe: InsightTimeframe.month,
        preferredCurrency: 'EUR',
      );
      expect(i.currency, 'INR');
    });

    test('empty result', () {
      final i = ExpenseInsights.fromJson(
        {'currency': 'INR'},
        scope: InsightScope.group,
        timeframe: InsightTimeframe.week,
        preferredCurrency: 'INR',
      );
      expect(i.isEmpty, isTrue);
      expect(i.total, Money.zero('INR'));
    });
  });
}
