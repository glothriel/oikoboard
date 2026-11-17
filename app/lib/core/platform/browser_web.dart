import 'package:web/web.dart' as web;

void redirectTo(String url) => web.window.location.assign(url);

void replaceUrl(String url) => web.window.history.replaceState(null, '', url);
