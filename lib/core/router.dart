import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/permissions.dart';
import '../screens/register_screen.dart';
import '../widgets/deferred_role_screen.dart';
import '../models/booking_query.dart';
import '../models/client_query.dart';
import '../models/equipment_query.dart';
import '../models/hall_query.dart';
import '../models/photographer_query.dart';
import '../screens/booking_form_screen.dart';
import '../screens/booking_list_screen.dart';
import '../screens/client_form_screen.dart';
import '../screens/client_list_screen.dart';
import '../screens/equipment_form_screen.dart';
import '../screens/equipment_list_screen.dart';
import '../screens/hall_form_screen.dart';
import '../screens/hall_list_screen.dart';
import '../screens/home_screen.dart';
import '../screens/login_screen.dart';
import '../screens/no_access_screen.dart';
import '../screens/not_found_screen.dart';
import '../screens/photographer_form_screen.dart';
import '../screens/photographer_list_screen.dart';
import '../state/session.dart';
import '../widgets/dirty_guard.dart';
import '../screens/entity_detail_screen.dart';

// This is a UI rule. The server independently checks the signed access token.
bool isRouteAllowed(String path, Permissions p) {
  if (!p.isAuthenticated) return false;
  if (path == '/my-bookings/new') return p.canBookOwn;
  if (path == '/my-bookings') return p.canUseClientPortal;
  if (path == '/manager') return p.canUseManagerWorkspace;
  if (path.startsWith('/admin/')) return p.canManageUsers;
  if (path == '/clients' || path.startsWith('/clients/')) {
    return p.canManageClients;
  }
  if (path.endsWith('/new') || path.endsWith('/edit')) {
    final collection = path.split('/')[1];
    return path.endsWith('/new')
        ? p.canCreateEntity(collection)
        : p.canManageEntity(collection);
  }
  return true;
}

String safeReturnLocation(String? from) {
  final uri = Uri.tryParse(from ?? '');
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      !uri.path.startsWith('/') ||
      uri.path.startsWith('//') ||
      uri.path == '/login' ||
      uri.path == '/register') {
    return '/';
  }
  return uri.toString();
}

/// Страница формы, если у пользователя есть право на изменение данных.
///
/// Проверка выполняется здесь, а не внутри каждой формы: правило одно
/// на все пять сущностей. Настоящая защита — на сервере.
class _GuardedForm extends StatelessWidget {
  final Widget child;

  const _GuardedForm({required this.child});

  @override
  Widget build(BuildContext context) {
    final permissions = context.watch<SessionStore>().permissions;
    if (!permissions.canUpdate) {
      return const NoAccessScreen(
        message: 'Ваша роль не позволяет изменять данные студии. '
            'Войдите под учётной записью менеджера.',
      );
    }
    return child;
  }
}

/// Создаёт роутер приложения.
///
/// Роутеру нужна сессия: по её состоянию он решает, пускать ли гостя
/// на страницу формы и куда вернуть человека после входа.
GoRouter createRouter(SessionStore session) {
  return GoRouter(
    initialLocation: '/',

    // Пересчитать перенаправления, когда пользователь вошёл или вышел.
    // Без этого после входа человек так и останется на экране входа.
    refreshListenable: session,

    redirect: (context, state) {
      final location = state.matchedLocation;

      // Пока проверяется сохранённый токен, ничего не решаем: иначе при
      // каждой перезагрузке страницы будет мелькать экран входа.
      if (!session.isKnown) return null;

      final isPublic = location == '/login' || location == '/register';
      if (!session.isAuthenticated && !isPublic) {
        return '/login?from=${Uri.encodeComponent(state.uri.toString())}';
      }
      if (session.isAuthenticated && isPublic) {
        return safeReturnLocation(state.uri.queryParameters['from']);
      }
      if (session.isAuthenticated &&
          location != '/forbidden' &&
          !isRouteAllowed(location, session.permissions)) {
        return '/forbidden';
      }

      return null;
    },

    routes: [
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/forbidden', builder: (_, __) => const NoAccessScreen()),
      GoRoute(
          path: '/my-bookings',
          builder: (_, __) => const DeferredRoleScreen(kind: 'client')),
      GoRoute(
          path: '/my-bookings/new',
          onExit: (_, __) =>
              !session.isAuthenticated ? true : DirtyGuard.mayLeave(),
          builder: (_, state) => BookingFormScreen(
              selfService: true,
              initialHallId:
                  int.tryParse(state.uri.queryParameters['hallId'] ?? ''))),
      GoRoute(
          path: '/manager',
          builder: (_, __) => const DeferredRoleScreen(kind: 'manager')),
      GoRoute(
          path: '/admin/users',
          builder: (_, __) => const DeferredRoleScreen(kind: 'users')),
      GoRoute(
          path: '/admin/statistics',
          builder: (_, __) => const DeferredRoleScreen(kind: 'statistics')),
      // Экран входа живёт вне общего каркаса: меню разделов на нём не нужно.
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) =>
            LoginScreen(from: state.uri.queryParameters['from']),
      ),

      GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
      GoRoute(
          path: '/halls',
          builder: (_, s) => HallListScreen(query: HallQuery.fromUri(s.uri))),
      GoRoute(
        path: '/halls/new',
        onExit: (_, __) =>
            !session.isAuthenticated ? true : DirtyGuard.mayLeave(),
        builder: (_, __) => const _GuardedForm(child: HallFormScreen()),
      ),
      GoRoute(
        path: '/halls/:id/edit',
        onExit: (_, __) =>
            !session.isAuthenticated ? true : DirtyGuard.mayLeave(),
        builder: (_, s) => _GuardedForm(
          child: HallFormScreen(
              id: int.tryParse(s.pathParameters['id'] ?? '') ?? -1),
        ),
      ),
      GoRoute(
          path: '/photographers',
          builder: (_, s) =>
              PhotographerListScreen(query: PhotographerQuery.fromUri(s.uri))),
      GoRoute(
        path: '/photographers/new',
        onExit: (_, __) =>
            !session.isAuthenticated ? true : DirtyGuard.mayLeave(),
        builder: (_, __) => const _GuardedForm(child: PhotographerFormScreen()),
      ),
      GoRoute(
        path: '/photographers/:id/edit',
        onExit: (_, __) =>
            !session.isAuthenticated ? true : DirtyGuard.mayLeave(),
        builder: (_, s) => _GuardedForm(
          child: PhotographerFormScreen(
              id: int.tryParse(s.pathParameters['id'] ?? '') ?? -1),
        ),
      ),
      GoRoute(
          path: '/bookings',
          builder: (_, s) =>
              BookingListScreen(query: BookingQuery.fromUri(s.uri))),
      GoRoute(
        path: '/bookings/new',
        onExit: (_, __) =>
            !session.isAuthenticated ? true : DirtyGuard.mayLeave(),
        builder: (_, __) =>
            BookingFormScreen(selfService: session.permissions.canBookOwn),
      ),
      GoRoute(
        path: '/bookings/:id/edit',
        onExit: (_, __) =>
            !session.isAuthenticated ? true : DirtyGuard.mayLeave(),
        builder: (_, s) => _GuardedForm(
          child: BookingFormScreen(
              id: int.tryParse(s.pathParameters['id'] ?? '') ?? -1),
        ),
      ),
      GoRoute(
          path: '/clients',
          builder: (_, s) =>
              ClientListScreen(query: ClientQuery.fromUri(s.uri))),
      GoRoute(
        path: '/clients/new',
        onExit: (_, __) =>
            !session.isAuthenticated ? true : DirtyGuard.mayLeave(),
        builder: (_, __) => const _GuardedForm(child: ClientFormScreen()),
      ),
      GoRoute(
        path: '/clients/:id/edit',
        onExit: (_, __) =>
            !session.isAuthenticated ? true : DirtyGuard.mayLeave(),
        builder: (_, s) => _GuardedForm(
          child: ClientFormScreen(
              id: int.tryParse(s.pathParameters['id'] ?? '') ?? -1),
        ),
      ),
      GoRoute(
          path: '/equipment',
          builder: (_, s) =>
              EquipmentListScreen(query: EquipmentQuery.fromUri(s.uri))),
      GoRoute(
        path: '/equipment/new',
        onExit: (_, __) =>
            !session.isAuthenticated ? true : DirtyGuard.mayLeave(),
        builder: (_, __) => const _GuardedForm(child: EquipmentFormScreen()),
      ),
      GoRoute(
        path: '/equipment/:id/edit',
        onExit: (_, __) =>
            !session.isAuthenticated ? true : DirtyGuard.mayLeave(),
        builder: (_, s) => _GuardedForm(
          child: EquipmentFormScreen(
              id: int.tryParse(s.pathParameters['id'] ?? '') ?? -1),
        ),
      ),
      for (final collection in [
        'halls',
        'photographers',
        'bookings',
        'clients',
        'equipment'
      ])
        GoRoute(
            path: '/$collection/:id',
            builder: (_, state) => EntityDetailScreen(
                collection: collection,
                id: int.tryParse(state.pathParameters['id'] ?? '') ?? -1)),
    ],
    errorBuilder: (_, s) => NotFoundScreen(location: s.uri.toString()),
  );
}
