# FocusFrame — бронирование фотостудии

Практическая работа 6: адаптивные экраны, релизная сборка, тесты и Render.
Порядок сборки, публикации и проверок: [docs/practice6.md](docs/practice6.md).

**Опубликованное приложение:** https://focusframe-photostudio.onrender.com

237 тестов Flutter, адаптивность на 360/768/1280/1920 px, автосборка GitHub Actions.
Без СУБД: записи на бесплатном Render временные и сбрасываются при перезапуске.

## Разработка

Из этой папки в первом терминале:
node server/mock-server.js --port 8080 --origin http://localhost:5555


Во втором терминале:
flutter pub get
flutter run -d chrome --web-port=5555 --dart-define=API_BASE_URL=http://localhost:8080/api

Проверка сервера: `http://localhost:8080/api/__health`.

Учебные аккаунты: `manager / manager123`, `admin / admin123`,
`photographer / photographer123`, `client / client123`.
Клиент бронирует залы для себя. Менеджер ведёт клиентов и бронирования.
Администратор также управляет залами, фотографами, оборудованием,
пользователями и ролями, восстанавливает и физически удаляет записи.

