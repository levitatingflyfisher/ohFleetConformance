import 'dart:io';

import '../findings.dart';
import '../source_scan.dart';

const _check = 'C9-routes';

/// C9 — every screen has a way in.
///
/// A route registered in the router with nothing that navigates to it is a
/// built screen nobody can reach. It shipped that way more than once:
/// Lullaby's Growth, Calendar and Doctor Summary (lullaby:dmmt-03) and
/// Lilt's Name Detail (`/name/:nameId`, lilt finding 2), whose Shortlist
/// empty state even told users to tap a button no navigation reached.
///
/// **What counts as a way in.** For every `GoRoute(` under `lib/`, the check
/// computes its full path (relative child paths joined to their parent) and
/// asks for at least one of:
///
///  * a string literal anywhere in authored `lib/` code — comments never
///    count — that matches the path, `:param` segments matching any segment
///    (so `'/item/$id?from=home'` reaches `/item/:id`). This covers direct
///    `context.go('/x')`/`push('/x')` calls AND the fleet's indirect doors:
///    tab lists (`['/today', ...]`), path helpers (`scanPathForDay(d)`
///    returning `'/scan?day=$d'`), redirect targets, `initialLocation:`;
///  * for a route with a `name:`, a `goNamed`/`pushNamed`/
///    `pushReplacementNamed`/`replaceNamed`/`namedLocation` call whose first
///    argument is that name — a bare string equal to a route name is NOT a
///    door (it is as likely a preference key);
///  * being a top-level route of a `StatefulShellBranch` in an app that calls
///    `goBranch(` — the nav bar is the door;
///  * being `/` in a router with no `initialLocation:` — go_router's default;
///  * having no `builder:`/`pageBuilder:` — a redirect-only route (a legacy
///    path kept so bookmarks keep working) is not a screen.
///
/// The literal rule is deliberately broader than "a navigation call site":
/// Peckish and Sundial navigate through helpers and tab lists, and a
/// call-site-only rule would flag real doors. The cost, recorded honestly:
///
/// **False negatives (orphans this check misses).** A matching literal in
/// dead code, or used for something other than navigation, passes. A door
/// behind a dead `onTap` passes. A screen pushed with
/// `Navigator.push(MaterialPageRoute(...))` is not a route and is not
/// checked at all (it is reachable by construction where it is pushed;
/// whether THAT code is reachable is out of scope). `MaterialApp(routes:)`
/// named-route tables are not read — the fleet is on go_router.
///
/// **False positives (doors this check cannot see).** A path assembled by
/// concatenation (`'/history/' + day`) or computed from non-literal parts.
/// Record those, and deep-link-only routes, in
/// `FleetAppConfig.routeExemptions` with the reason.
///
/// Cannot pass by finding nothing: no Dart sources, no `GoRoute(`
/// declarations, a non-literal `path:`, an exemption without a reason, an
/// exemption naming a route that does not exist, and an exemption for a
/// route that has since gained a door are all findings.
List<ConformanceFinding> checkRouteReachability({
  required Directory root,
  Map<String, String> exemptions = const {},
}) {
  final sources = ScannedSource.under(root);
  if (sources.isEmpty) {
    return const [
      ConformanceFinding(
        _check,
        'no Dart sources found under lib/ — nothing was swept, which is not '
        'the same as nothing being wrong',
      ),
    ];
  }

  final findings = <ConformanceFinding>[];
  final routes = <_Route>[];
  var hasInitialLocation = false;
  var usesGoBranch = false;

  for (final src in sources) {
    if (RegExp(r'\binitialLocation\s*:').hasMatch(src.structure)) {
      hasInitialLocation = true;
    }
    if (RegExp(r'\bgoBranch\s*\(').hasMatch(src.structure)) {
      usesGoBranch = true;
    }
    final branches = src.calls('StatefulShellBranch').toList();
    final declared = <(int, int, _Route?)>[];
    for (final (open, close) in src.calls('GoRoute')) {
      final line = lineOf(src.original, open);
      final pathArg = namedArgument(src.structure, open, close, 'path');
      final path = pathArg == null
          ? null
          : singleStringLiteral(src.code.substring(pathArg.start, pathArg.end));
      if (path == null) {
        findings.add(ConformanceFinding(
          _check,
          '${src.relative}:$line declares a GoRoute whose path is not a '
          'string literal — C9 cannot tell where it leads; use a literal',
        ));
        declared.add((open, close, null));
        continue;
      }
      final nameArg = namedArgument(src.structure, open, close, 'name');
      final name = nameArg == null
          ? null
          : singleStringLiteral(src.code.substring(nameArg.start, nameArg.end));

      // Innermost enclosing GoRoute already seen (calls() yields in source
      // order, so every ancestor precedes its descendants).
      _Route? parent;
      int? parentOpen;
      for (final (pOpen, pClose, pRoute) in declared.reversed) {
        if (pOpen < open && close <= pClose) {
          parent = pRoute;
          parentOpen = pOpen;
          break;
        }
      }
      final String full;
      if (path.startsWith('/')) {
        full = path;
      } else if (parent != null) {
        full = parent.path.endsWith('/')
            ? '${parent.path}$path'
            : '${parent.path}/$path';
      } else {
        full = '/$path';
      }

      // A branch root: inside a StatefulShellBranch, with no GoRoute
      // between the branch and it.
      final inBranch = branches.any((b) =>
          b.$1 < open &&
          close <= b.$2 &&
          (parentOpen == null || parentOpen < b.$1));

      // A route with no builder is not a screen (a legacy path kept as a
      // redirect so bookmarks keep working, Reckon's /model-scorecard):
      // it still takes part in path joining, but needs no door.
      final isScreen =
          namedArgument(src.structure, open, close, 'builder') != null ||
              namedArgument(src.structure, open, close, 'pageBuilder') != null;

      final route = _Route(
        path: full,
        name: name,
        where: '${src.relative}:$line',
        branchRoot: inBranch,
        isScreen: isScreen,
        declaredLiterals: [
          if (pathArg != null) pathArg,
          if (nameArg != null) nameArg,
        ],
        file: src,
      );
      routes.add(route);
      declared.add((open, close, route));
    }
  }

  if (routes.isEmpty && findings.isEmpty) {
    return const [
      ConformanceFinding(
        _check,
        'no GoRoute declarations found under lib/ — C9 reads go_router '
        'routers only; an app that navigates purely with '
        'Navigator.push(MaterialPageRoute) should not enable C9',
      ),
    ];
  }

  // Every literal in authored code, minus the path:/name: arguments of the
  // declarations themselves (a route is not its own door).
  final pathRefs = <String>[];
  final namedRefs = <String>{};
  final namedCall = RegExp(
      r'(?<![A-Za-z0-9_])(goNamed|pushNamed|pushReplacementNamed|replaceNamed|namedLocation)\s*(<[^>(]*>)?\s*\(');
  for (final src in sources) {
    final excluded = routes
        .where((r) => identical(r.file, src))
        .expand((r) => r.declaredLiterals)
        .toList();
    for (final body in src.literals) {
      final isDeclaration =
          excluded.any((e) => e.start <= body.start && body.end <= e.end);
      if (!isDeclaration) pathRefs.add(src.literalText(body));
    }
    for (final m in namedCall.allMatches(src.structure)) {
      final open = m.end - 1;
      final close = matchingClose(src.structure, open);
      if (close == null) continue;
      final args = topLevelArguments(src.structure, open, close);
      if (args.isEmpty) continue;
      final first = singleStringLiteral(
          src.code.substring(args.first.start, args.first.end));
      if (first != null) namedRefs.add(first);
    }
  }

  bool reached(_Route r) {
    if (!r.isScreen) return true;
    if (r.path == '/' && !hasInitialLocation) return true;
    if (r.branchRoot && usesGoBranch) return true;
    if (r.name != null && namedRefs.contains(r.name)) return true;
    final pattern = r.pattern;
    return pathRefs.any((lit) {
      final bare = lit.split(RegExp(r'[?#]')).first;
      return pattern.hasMatch(bare);
    });
  }

  final exemptionsUsed = <String>{};
  for (final r in routes) {
    final key = exemptions.containsKey(r.path)
        ? r.path
        : (r.name != null && exemptions.containsKey(r.name) ? r.name : null);
    final isReached = reached(r);
    if (key != null) {
      exemptionsUsed.add(key);
      if (exemptions[key]!.trim().isEmpty) {
        findings.add(ConformanceFinding(
          _check,
          "routeExemptions['$key'] has no reason — an exemption is a "
          'recorded decision; say why this route needs no door (e.g. '
          '"deep link from the share sheet only")',
        ));
      } else if (isReached) {
        findings.add(ConformanceFinding(
          _check,
          "routeExemptions['$key'] is no longer needed — '${r.path}' now has "
          'a way in; delete the exemption so it cannot hide a future orphan',
        ));
      }
      continue;
    }
    if (!isReached) {
      findings.add(ConformanceFinding(
        _check,
        "route '${r.path}' (${r.where}) has no way in: nothing under lib/ "
        'navigates to it (no matching path literal'
        '${r.name != null ? ", no goNamed/pushNamed('${r.name}')" : ''}'
        ') — add a door, or record it in FleetAppConfig.routeExemptions '
        'with the reason (e.g. deep-link only)',
      ));
    }
  }
  for (final key in exemptions.keys) {
    if (!exemptionsUsed.contains(key)) {
      findings.add(ConformanceFinding(
        _check,
        "routeExemptions names '$key', which no GoRoute declares (by full "
        'path or name) — a stale exemption; delete it',
      ));
    }
  }
  return findings;
}

class _Route {
  final String path;
  final String? name;
  final String where;
  final bool branchRoot;
  final bool isScreen;
  final List<SourceRange> declaredLiterals;
  final ScannedSource file;

  _Route({
    required this.path,
    required this.name,
    required this.where,
    required this.branchRoot,
    required this.isScreen,
    required this.declaredLiterals,
    required this.file,
  });

  late final RegExp pattern = RegExp('^${path.split('/').map((seg) {
    return seg.startsWith(':') ? r'[^/]+' : RegExp.escape(seg);
  }).join('/')}/?\$');
}
