import '../core/module.dart';
import 'calendar/calendar_module.dart';
import 'todo/todo_module.dart';

/// Wszystkie moduły aplikacji. Nowy widok = nowy wpis tutaj.
const List<FamilyModule> modules = [TodoModule(), CalendarModule()];
