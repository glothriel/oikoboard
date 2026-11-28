import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'avatar_cache.dart';
import 'backend.dart';
import 'data.dart';
import 'l10n.dart';
import 'session.dart';

class Member {
  const Member(
    this.id,
    this.name,
    this.color, {
    this.hasAccount = true,
    this.picture,
    this.removed = false,
  });
  final String id;
  final String name;
  final Color color;

  /// Profile picture URL of the member's account (Google), if any.
  final String? picture;

  /// Czy ktoś loguje się jako ten członek (dzieci często nie).
  final bool hasAccount;

  /// Neutral stand-in for an id with no member (removed, or stale data).
  factory Member.removed(String id) => Member(
    id,
    '?',
    const Color(0xFF9E9E9E),
    hasAccount: false,
    removed: true,
  );

  /// True for the [Member.removed] placeholder.
  final bool removed;

  factory Member.fromJson(Map<String, dynamic> j) => Member(
    j['id'] as String,
    j['name'] as String,
    Color(j['color'] as int),
    hasAccount: (j['has_account'] as bool?) ?? true,
    picture: j['picture'] as String?,
  );
}

/// Członkowie zalogowanej rodziny.
class Family {
  const Family(this.members);
  final List<Member> members;

  Member? byId(String? id) =>
      id == null ? null : members.where((m) => m.id == id).firstOrNull;

  /// Like [byId], but an id with no member (a removed one) gives the
  /// [Member.removed] placeholder; null only for a null id.
  Member? byIdOrRemoved(String? id) =>
      id == null ? null : byId(id) ?? Member.removed(id);
}

/// The household's `family.members` view (API mode only).
final _liveMembersProvider = StreamProvider<List<Member>>((ref) {
  ref.watch(sessionProvider); // a new login is a new socket and a new view
  return ref
      .watch(syncClientProvider)
      .watch('family.members', const {}, (e, _) => e == 'members')
      .map((v) => v.rows('members').map(Member.fromJson).toList());
});

/// Members of the signed-in household. API: live (added, edited and removed
/// members follow the server), the session's list until the first snapshot;
/// mock: the session's list.
final membersProvider = Provider<List<Member>>((ref) {
  final session = ref.watch(sessionProvider);
  if (session == null) return const [];
  if (ref.watch(backendProvider) is! ApiBackend) return session.members;
  return ref.watch(_liveMembersProvider).value ?? session.members;
});

final familyProvider = Provider<Family>(
  (ref) => Family(ref.watch(membersProvider)),
);

/// Feeds the live [familyProvider] to [familyOf] below it: a widget that
/// called [familyOf] is rebuilt when the family changes.
class FamilyScope extends ConsumerWidget {
  const FamilyScope({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _FamilyInherited(ref.watch(familyProvider), child: child);
}

class _FamilyInherited extends InheritedWidget {
  const _FamilyInherited(this.family, {required super.child});
  final Family family;

  @override
  bool updateShouldNotify(_FamilyInherited old) =>
      !identical(family, old.family);
}

/// The live family in places without a `ref` (plain widgets); rebuilds
/// [context] when it changes. Without a [FamilyScope] above (some tests) it
/// is the provider's current value.
Family familyOf(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<_FamilyInherited>()?.family ??
    ProviderScope.containerOf(context, listen: false).read(familyProvider);

/// Id zalogowanego członka rodziny.
final currentMemberProvider = Provider<String>(
  (ref) => ref.watch(sessionProvider)?.memberId ?? '',
);

/// Ids of the members online right now. API: the server's `presence`; mock:
/// the store's set plus the signed-in member.
final onlineMembersProvider = StreamProvider<Set<String>>((ref) async* {
  final backend = ref.watch(backendProvider);
  if (backend is MockBackend) {
    final me = ref.watch(currentMemberProvider);
    final store = backend.store;
    yield {...store.online, me};
    yield* store.onlineChanges.map((s) => {...s, me});
    return;
  }
  if (ref.watch(sessionProvider) == null) return;
  final client = ref.watch(syncClientProvider);
  yield client.online;
  yield* client.presence;
});

class MemberAvatar extends ConsumerWidget {
  const MemberAvatar(this.member, {super.key, this.radius = 18});
  final Member member;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online =
        member.hasAccount &&
        !member.removed &&
        (ref.watch(onlineMembersProvider).value?.contains(member.id) ?? false);
    final picture = member.picture;
    // A stored picture shows (almost) at once: no initial flashing under it.
    final stored = picture == null ? null : AvatarCache.cached(picture);
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: member.color,
      foregroundImage: picture == null ? null : AvatarCache.image(picture),
      // the initial stays underneath if the picture fails to load
      onForegroundImageError: picture == null ? null : (_, _) {},
      child: member.removed
          ? Icon(Icons.person_outline, size: radius * 1.1, color: Colors.white)
          : stored != null
          ? null
          : Text(
              member.name.characters.first,
              style: TextStyle(
                color: Colors.white,
                fontSize: radius * 0.9,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
    if (!online) return avatar;
    final dot = (radius * 0.55).clamp(7.0, 12.0);
    return Semantics(
      label: context.l10n.memberOnline,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
