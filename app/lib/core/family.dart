import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'session.dart';

class Member {
  const Member(this.id, this.name, this.color, {this.hasAccount = true});
  final String id;
  final String name;
  final Color color;

  /// Czy ktoś loguje się jako ten członek (dzieci często nie).
  final bool hasAccount;

  factory Member.fromJson(Map<String, dynamic> j) => Member(
    j['id'] as String,
    j['name'] as String,
    Color(j['color'] as int),
    hasAccount: (j['has_account'] as bool?) ?? true,
  );
}

/// Członkowie zalogowanej rodziny.
class Family {
  const Family(this.members);
  final List<Member> members;

  Member? byId(String? id) =>
      id == null ? null : members.where((m) => m.id == id).firstOrNull;
}

final familyProvider = Provider<Family>(
  (ref) => Family(ref.watch(sessionProvider)?.members ?? const []),
);

/// Rodzina w miejscach bez `ref` (np. zwykłe StatelessWidgety). Nie
/// subskrybuje zmian — rodzina zmienia się tylko przy logowaniu, a wtedy
/// i tak przebudowuje się cała aplikacja.
Family familyOf(BuildContext context) =>
    ProviderScope.containerOf(context, listen: false).read(familyProvider);

/// Id zalogowanego członka rodziny.
final currentMemberProvider = Provider<String>(
  (ref) => ref.watch(sessionProvider)?.memberId ?? '',
);

class MemberAvatar extends StatelessWidget {
  const MemberAvatar(this.member, {super.key, this.radius = 18});
  final Member member;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: member.color,
      child: Text(
        member.name.characters.first,
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
