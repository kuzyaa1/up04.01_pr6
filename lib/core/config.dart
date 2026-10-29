/// Адрес сервера задаётся параметром сборки, а не константой в коде:
///
/// ```
/// flutter run -d chrome --web-port=5555 --dart-define=API_BASE_URL=http://192.168.1.10:8080/api
/// ```
///
/// В опубликованной версии API и сайт работают на одном HTTPS-источнике.
library;

/// Базовый адрес REST API. Задаётся через `--dart-define=API_BASE_URL=...`.
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: '/api',
);

/// Токен доступа. Задаётся через `--dart-define=API_TOKEN=...`.
///
/// Пустое значение означает, что приложение работает в режиме гостя:
/// сервер разрешает чтение каталога без аутентификации, но изменять
/// записи нельзя — он вернёт 401 или 403.
const String apiToken = String.fromEnvironment('API_TOKEN');

/// Таймаут установления соединения, секунды.
const int connectTimeoutSeconds = 10;

/// Таймаут получения ответа, секунды.
const int receiveTimeoutSeconds = 15;

/// Максимальное число автоматических повторов при сетевом сбое.
/// Повторяются только операции чтения.
const int maxReadRetries = 3;

/// Пауза перед первым повтором, миллисекунды. Дальше пауза растёт
/// экспоненциально: base * 2^(номер попытки - 1).
const int retryBaseDelayMs = 400;

const apiDemoDelayMs = int.fromEnvironment('API_DEMO_DELAY_MS');
const apiDemoFail = int.fromEnvironment('API_DEMO_FAIL');

const sessionIdleSeconds =
    int.fromEnvironment('SESSION_IDLE_SECONDS', defaultValue: 180);
const sessionMaxSeconds =
    int.fromEnvironment('SESSION_MAX_SECONDS', defaultValue: 1800);
