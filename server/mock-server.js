#!/usr/bin/env node
/**
 * Мок-сервер учебного API «Фотостудия FocusFrame».
 *
 * REST API для системы бронирования фотостудии:
 *   - адрес:            http://localhost:8080/api
 *   - пагинация:        { items, page, size, total, totalPages }
 *   - ошибки:           { message } и { message, errors } для 422
 *   - роли:             client / photographer / manager / admin
 *   - CORS:             разрешённый источник + обработчик OPTIONS
 *
 * Зависимостей нет — нужен только Node.js 18 или новее.
 *
 *   node mock-server.js
 *   node mock-server.js --port 8080 --origin http://localhost:5555
 *
 * Данные хранятся в памяти и сбрасываются при перезапуске
 * либо запросом POST /api/__reset
 *
 * Учебные возможности:
 *   ?__delay=1500   задержка ответа в миллисекундах (проверка индикатора загрузки)
 *   ?__fail=500     принудительный код ошибки (проверка обработки ошибок)
 */

'use strict';

const http = require('node:http');
const crypto = require('node:crypto');
const fs = require('node:fs');
const nodePath = require('node:path');

// ─────────────────────────── параметры запуска ───────────────────────────

const args = process.argv.slice(2);
function arg(name, fallback) {
  const i = args.indexOf('--' + name);
  return i !== -1 && args[i + 1] ? args[i + 1] : fallback;
}

const PORT = Number(arg('port', process.env.PORT || 8080));
const ORIGIN = arg('origin', process.env.CORS_ORIGIN || process.env.RENDER_EXTERNAL_URL || 'http://localhost:5555');
const SECRET = process.env.JWT_SECRET || crypto.randomBytes(48).toString('hex');
const ACCESS_TTL = Number(arg('ttl', 900)); // секунд
const REFRESH_TTL = 60 * 60 * 24 * 7;
const SESSION_TTL = Number(arg('session-ttl', 1800));

// ─────────────────────────────── токены ───────────────────────────────

function b64url(buf) {
  return Buffer.from(buf).toString('base64url');
}

function sign(payload) {
  // jti делает каждый токен уникальным. Без него два токена, выпущенные
  // в одну и ту же секунду для одного пользователя, совпадут побайтово,
  // и отзыв старого токена обновления отзовёт заодно и новый.
  const withId = { ...payload, jti: crypto.randomUUID() };
  const body = b64url(JSON.stringify(withId));
  const mac = crypto.createHmac('sha256', SECRET).update(body).digest('base64url');
  return body + '.' + mac;
}

function verify(token) {
  if (typeof token !== 'string' || !token.includes('.')) return null;
  const [body, mac] = token.split('.');
  const expected = crypto.createHmac('sha256', SECRET).update(body).digest('base64url');
  if (mac !== expected) return null;
  let payload;
  try {
    payload = JSON.parse(Buffer.from(body, 'base64url').toString('utf8'));
  } catch {
    return null;
  }
  if (payload.exp && payload.exp * 1000 < Date.now()) return null;
  return payload;
}

// ─────────────────────────────── данные ───────────────────────────────

let db;

function iso(y, m, d) {
  return new Date(Date.UTC(y, m - 1, d)).toISOString();
}

function hash(password) {
  return crypto.createHash('sha256').update(password + SECRET).digest('hex');
}

function push(collection, obj) {
  db.seq[collection] = (db.seq[collection] || 0) + 1;
  const id = db.seq[collection];
  db[collection].push({ id, ...obj, createdAt: new Date().toISOString(), deletedAt: null });
  return id;
}

function seed() {
  db = {
    seq: {},
    halls: [],
    photographers: [],
    clients: [],
    equipment: [],
    bookings: [],
    users: [],
    refreshTokens: new Set(),
    revokedSessions: new Set(),
  };

  const fixtures = require('./seed-pr3.json');
  for (const collection of COLLECTIONS) {
    db[collection] = fixtures[collection].map(row => ({
      ...normalize(collection, {
        ...row,
        fullName: row.fullName || row.name || [row.lastName, row.firstName].filter(Boolean).join(' '),
        city: row.city || row.bio || '',
      }),
      id: row.id, createdAt: new Date().toISOString(), deletedAt: row.deletedAt || null,
    }));
    db.seq[collection] = Math.max(0, ...db[collection].map(row => row.id));
  }

  // ── Пользователи ──
  push('users', {
    username: 'admin', passwordHash: hash('admin123'), fullName: 'Администратор студии',
    email: 'admin@focusframe.local', role: 'admin', clientId: null,
  });
  push('users', {
    username: 'manager', passwordHash: hash('manager123'), fullName: 'Руководитель смены',
    email: 'manager@focusframe.local', role: 'manager', clientId: null,
  });
  push('users', {
    username: 'photographer', passwordHash: hash('photographer123'), fullName: 'Иванова Мария Петровна',
    email: 'ivanova@focusframe.local', role: 'photographer', clientId: null,
  });
  push('users', {
    username: 'client', passwordHash: hash('client123'), fullName: 'Смирнов Пётр Алексеевич',
    email: 'smirnov@example.com', role: 'client', clientId: 1,
  });
}

// ──────────────────────── развёртывание объектов ────────────────────────

function slimName(obj) {
  return obj ? { id: obj.id, name: obj.name } : null;
}

function expandHall(h) {
  const photographerIds = db.bookings
    .filter((b) => b.hallId === h.id && !b.deletedAt)
    .flatMap((b) => b.photographerIds);
  const uniquePhotographers = [...new Set(photographerIds)];
  return {
    id: h.id,
    name: h.name,
    code: h.code,
    style: h.style,
    capacity: h.capacity,
    hourlyRate: h.hourlyRate,
    description: h.description,
    equipmentIds: db.equipment
      .filter((e) => e.hallId === h.id && !e.deletedAt)
      .map((e) => e.id),
    photographerIds: [...new Set([...uniquePhotographers, ...db.photographers.filter(p => !p.deletedAt && (p.hallIds || []).includes(h.id)).map(p => p.id)])],
    bookingIds: db.bookings.filter(b => b.hallId === h.id && !b.deletedAt).map(b => b.id),
    activeBookings: db.bookings.filter(
      (b) => b.hallId === h.id && b.status === 'active' && !b.deletedAt,
    ).length,
    createdAt: h.createdAt,
    deletedAt: h.deletedAt,
  };
}

function expandPhotographer(p) {
  const bookings = db.bookings.filter(
    (b) => b.photographerIds.includes(p.id) && !b.deletedAt,
  );
  return {
    id: p.id,
    fullName: p.fullName,
    specialization: p.specialization,
    city: p.city,
    birthYear: p.birthYear,
    experienceYears: p.experienceYears,
    hourlyRate: p.hourlyRate,
    hallIds: p.hallIds || [],
    bookingIds: bookings.map((b) => b.id),
    activeBookings: bookings.filter((b) => b.status === 'active').length,
    createdAt: p.createdAt,
    deletedAt: p.deletedAt,
  };
}

function expandClient(c) {
  const bookings = db.bookings.filter((b) => b.clientId === c.id && !b.deletedAt);
  return {
    id: c.id,
    fullName: c.fullName,
    email: c.email,
    phone: c.phone,
    clientType: c.clientType,
    company: c.company,
    notes: c.notes || '',
    card: c.cardNumber
      ? {
          number: c.cardNumber,
          issuedAt: c.cardIssuedAt,
          expiresAt: c.cardExpiresAt,
        }
      : null,
    bookingIds: bookings.map((b) => b.id),
    activeBookings: bookings.filter((b) => b.status === 'active').length,
    createdAt: c.createdAt,
    deletedAt: c.deletedAt,
  };
}

function expandEquipment(e) {
  return {
    id: e.id,
    name: e.name,
    category: e.category,
    manufacturer: e.manufacturer,
    hallId: e.hallId,
    hall: slimName(db.halls.find((h) => h.id === e.hallId)),
    quantity: e.quantity,
    pricePerDay: e.pricePerDay,
    createdAt: e.createdAt,
    deletedAt: e.deletedAt,
  };
}

function expandBooking(b) {
  const hall = db.halls.find((h) => h.id === b.hallId);
  const client = db.clients.find((c) => c.id === b.clientId);
  return {
    id: b.id,
    accessCode: b.accessCode,
    email: b.email || client?.email || '',
    hall: hall ? { id: hall.id, name: hall.name, code: hall.code } : null,
    client: client ? { id: client.id, fullName: client.fullName } : null,
    photographerIds: b.photographerIds,
    photographers: b.photographerIds
      .map((id) => db.photographers.find((p) => p.id === id))
      .filter(Boolean)
      .map((p) => ({ id: p.id, fullName: p.fullName })),
    date: b.date,
    durationHours: b.durationHours,
    participants: b.participants,
    shootingType: b.shootingType,
    comment: b.comment,
    status: b.status,
    createdAt: b.createdAt,
    deletedAt: b.deletedAt,
  };
}

const EXPANDERS = {
  halls: expandHall,
  photographers: expandPhotographer,
  clients: expandClient,
  equipment: expandEquipment,
  bookings: expandBooking,
};

// ─────────────────────────── общие операции ───────────────────────────

function searchableText(collection, item) {
  switch (collection) {
    case 'halls':
      return [item.name, item.code, item.style, item.description].join(' ');
    case 'photographers':
      return [item.fullName, item.specialization, item.city].join(' ');
    case 'clients':
      return [item.fullName, item.email, item.phone, item.company].join(' ');
    case 'equipment':
      return [item.name, item.category, item.manufacturer].join(' ');
    case 'bookings':
      return [
        item.accessCode,
        item.shootingType,
        item.comment,
        db.halls.find((h) => h.id === item.hallId)?.name ?? '',
        db.clients.find((c) => c.id === item.clientId)?.fullName ?? '',
      ].join(' ');
    default:
      return '';
  }
}

function applyFilters(collection, rows, q) {
  let result = rows;

  if (q.search) {
    const needle = String(q.search).toLowerCase();
    result = result.filter((x) =>
      searchableText(collection, x).toLowerCase().includes(needle),
    );
  }

  if (collection === 'halls') {
    if (q.style) result = result.filter((h) => h.style === q.style);
    if (q.capacityFrom) result = result.filter((h) => h.capacity >= Number(q.capacityFrom));
    if (q.capacityTo) result = result.filter((h) => h.capacity <= Number(q.capacityTo));
    if (q.priceFrom) result = result.filter((h) => h.hourlyRate >= Number(q.priceFrom));
    if (q.priceTo) result = result.filter((h) => h.hourlyRate <= Number(q.priceTo));
  }

  if (collection === 'photographers') {
    if (q.hallId) result = result.filter(p => (p.hallIds || []).includes(Number(q.hallId)));
    if (q.specialization) {
      result = result.filter((p) => p.specialization === q.specialization);
    }
    if (q.city) result = result.filter((p) => p.city === q.city);
    if (q.experienceFrom) {
      result = result.filter((p) => p.experienceYears >= Number(q.experienceFrom));
    }
    if (q.experienceTo) {
      result = result.filter((p) => p.experienceYears <= Number(q.experienceTo));
    }
    if (q.rateFrom) result = result.filter((p) => p.hourlyRate >= Number(q.rateFrom));
    if (q.rateTo) result = result.filter((p) => p.hourlyRate <= Number(q.rateTo));
  }

  if (collection === 'clients') {
    if (q.clientType) result = result.filter((c) => c.clientType === q.clientType);
    if (q.hasCard === 'true') {
      result = result.filter((c) => Boolean(c.cardNumber && c.cardNumber.trim()));
    }
    if (q.hasCard === 'false') {
      result = result.filter((c) => !c.cardNumber || !c.cardNumber.trim());
    }
    if (q.yearFrom || q.yearTo) {
      result = result.filter((c) => {
        const year = Number((c.cardIssuedAt || '').slice(0, 4)) || 0;
        if (year === 0) return !q.yearFrom && !q.yearTo;
        if (q.yearFrom && year < Number(q.yearFrom)) return false;
        if (q.yearTo && year > Number(q.yearTo)) return false;
        return true;
      });
    }
  }

  if (collection === 'equipment') {
    if (q.category) result = result.filter((e) => e.category === q.category);
    if (q.hallId) result = result.filter((e) => e.hallId === Number(q.hallId));
    if (q.quantityFrom) {
      result = result.filter((e) => e.quantity >= Number(q.quantityFrom));
    }
    if (q.quantityTo) result = result.filter((e) => e.quantity <= Number(q.quantityTo));
    if (q.priceFrom) {
      result = result.filter((e) => e.pricePerDay >= Number(q.priceFrom));
    }
    if (q.priceTo) result = result.filter((e) => e.pricePerDay <= Number(q.priceTo));
  }

  if (collection === 'bookings') {
    if (q.hallId) result = result.filter((b) => b.hallId === Number(q.hallId));
    if (q.clientId) result = result.filter((b) => b.clientId === Number(q.clientId));
    if (q.photographerId) {
      result = result.filter((b) => b.photographerIds.includes(Number(q.photographerId)));
    }
    if (q.shootingType) {
      result = result.filter((b) => b.shootingType === q.shootingType);
    }
    if (q.status) result = result.filter((b) => b.status === q.status);
    if (q.participantsFrom) {
      result = result.filter((b) => b.participants >= Number(q.participantsFrom));
    }
    if (q.participantsTo) {
      result = result.filter((b) => b.participants <= Number(q.participantsTo));
    }
    if (q.durationFrom) {
      result = result.filter((b) => b.durationHours >= Number(q.durationFrom));
    }
    if (q.durationTo) {
      result = result.filter((b) => b.durationHours <= Number(q.durationTo));
    }
    if (q.dateFrom) {
      const from = Date.parse(q.dateFrom);
      if (!Number.isNaN(from)) {
        result = result.filter((b) => Date.parse(b.date) >= from);
      }
    }
    if (q.dateTo) {
      const to = Date.parse(q.dateTo);
      if (!Number.isNaN(to)) {
        result = result.filter((b) => Date.parse(b.date) <= to);
      }
    }
  }

  return result;
}

function applySort(rows, sort) {
  if (!sort) return rows;
  const [field, dirRaw] = String(sort).split(',');
  const dir = (dirRaw || 'asc').toLowerCase() === 'desc' ? -1 : 1;
  return [...rows].sort((a, b) => {
    const value = row => {
      if (field === 'name' && row.fullName != null) return row.fullName;
      if (field === 'lastName') return (row.fullName || '').split(/\s+/)[0];
      if (field === 'firstName') return (row.fullName || '').split(/\s+/).slice(1).join(' ');
      if (field === 'clientName') return db.clients.find(c => c.id === row.clientId)?.fullName || '';
      if (field === 'total') return row.durationHours * (db.halls.find(h => h.id === row.hallId)?.hourlyRate || 0);
      return row[field];
    };
    const av = value(a);
    const bv = value(b);
    if (av == null && bv == null) return 0;
    if (av == null) return 1;
    if (bv == null) return -1;
    if (typeof av === 'number' && typeof bv === 'number') return (av - bv) * dir;
    return String(av).localeCompare(String(bv), 'ru') * dir;
  });
}

function paginate(rows, q) {
  const page = Math.max(1, Number(q.page) || 1);
  const size = Math.min(100, Math.max(1, Number(q.size) || 10));
  const total = rows.length;
  const totalPages = Math.max(1, Math.ceil(total / size));
  return {
    items: rows.slice((page - 1) * size, page * size),
    page,
    size,
    total,
    totalPages,
  };
}

// ─────────────────────────────── валидация ───────────────────────────────

function validate(collection, body, id = null) {
  const e = {};
  const str = (v) => (typeof v === 'string' ? v.trim() : '');

  if (collection === 'halls') {
    if (!str(body.name)) e.name = 'Укажите название зала';
    else if (str(body.name).length > 120) e.name = 'Не длиннее 120 символов';

    if (!str(body.code)) e.code = 'Укажите код зала';
    else {
      const dup = db.halls.find(
        (h) => h.code.toUpperCase() === str(body.code).toUpperCase() && h.id !== id && !h.deletedAt,
      );
      if (dup) e.code = 'Зал с таким кодом уже существует';
    }

    if (!str(body.style)) e.style = 'Укажите стиль съёмки';

    const capacity = Number(body.capacity);
    if (!Number.isInteger(capacity) || capacity < 1) {
      e.capacity = 'Вместимость — положительное целое число';
    }

    const rate = Number(body.hourlyRate);
    if (!Number.isInteger(rate) || rate < 0) {
      e.hourlyRate = 'Цена за час — целое неотрицательное число';
    }
  }

  if (collection === 'photographers') {
    if (body.hallIds != null && (!Array.isArray(body.hallIds) || body.hallIds.some(id => !db.halls.some(h => h.id === Number(id) && !h.deletedAt)))) e.hallIds = 'Выберите существующие залы';
    if (!str(body.fullName)) e.fullName = 'Укажите ФИО фотографа';
    if (!str(body.specialization)) e.specialization = 'Укажите специализацию';
    if (body.experienceYears != null) {
      const y = Number(body.experienceYears);
      if (!Number.isInteger(y) || y < 0 || y > 80) {
        e.experienceYears = 'Некорректное число лет опыта';
      }
    }
    if (body.hourlyRate != null) {
      const r = Number(body.hourlyRate);
      if (!Number.isInteger(r) || r < 0) {
        e.hourlyRate = 'Ставка — целое неотрицательное число';
      }
    }
  }

  if (collection === 'clients') {
    if (!str(body.fullName)) e.fullName = 'Укажите ФИО клиента';
    if (!str(body.email)) e.email = 'Укажите адрес почты';
    else if (!/^[\w.+-]+@[\w-]+\.[\w.-]+$/.test(str(body.email))) {
      e.email = 'Некорректный адрес почты';
    } else {
      const dup = db.clients.find(
        (c) => c.email.toLowerCase() === str(body.email).toLowerCase() && c.id !== id && !c.deletedAt,
      );
      if (dup) e.email = 'Клиент с такой почтой уже зарегистрирован';
    }
    if (str(body.phone)) {
      const dup = db.clients.find(
        (c) => c.phone.trim() === str(body.phone).trim() && c.id !== id && !c.deletedAt,
      );
      if (dup) e.phone = 'Клиент с таким телефоном уже есть';
    }
    if (str(body.cardNumber)) {
      const dup = db.clients.find(
        (c) => c.cardNumber.trim().toUpperCase() === str(body.cardNumber).trim().toUpperCase() &&
          c.id !== id && !c.deletedAt,
      );
      if (dup) e.cardNumber = 'Абонемент с таким номером уже есть';
    }
  }

  if (collection === 'equipment') {
    if (!str(body.name)) e.name = 'Укажите название оборудования';
    else if (str(body.name).length > 120) e.name = 'Не длиннее 120 символов';
    if (!str(body.category)) e.category = 'Укажите категорию';
    if (!db.halls.find((h) => h.id === Number(body.hallId) && !h.deletedAt)) {
      e.hallId = 'Зал не найден';
    }
    const quantity = Number(body.quantity);
    if (!Number.isInteger(quantity) || quantity < 0) {
      e.quantity = 'Количество — целое неотрицательное число';
    }
    const price = Number(body.pricePerDay);
    if (!Number.isInteger(price) || price < 0) {
      e.pricePerDay = 'Цена — целое неотрицательное число';
    }
  }

  if (collection === 'bookings') {
    if (!str(body.accessCode)) e.accessCode = 'Укажите код бронирования';
    else {
      const dup = db.bookings.find(
        (b) => b.accessCode.trim().toUpperCase() === str(body.accessCode).toUpperCase() &&
          b.id !== id && !b.deletedAt,
      );
      if (dup) e.accessCode = 'Бронирование с таким кодом уже существует';
    }

    if (!db.halls.find((h) => h.id === Number(body.hallId) && !h.deletedAt)) {
      e.hallId = 'Зал не найден';
    }
    if (!db.clients.find((c) => c.id === Number(body.clientId) && !c.deletedAt)) {
      e.clientId = 'Клиент не найден';
    }

    if (!body.date) e.date = 'Укажите дату съёмки';
    if (body.date) {
      const d = Date.parse(body.date);
      if (Number.isNaN(d)) e.date = 'Некорректная дата съёмки';
    }

    const duration = Number(body.durationHours);
    if (!Number.isInteger(duration) || duration < 1 || duration > 24) {
      e.durationHours = 'Длительность — от 1 до 24 часов';
    }

    const participants = Number(body.participants);
    if (!Number.isInteger(participants) || participants < 1) {
      e.participants = 'Участников должно быть не меньше одного';
    }

    const hall = db.halls.find(h => h.id === Number(body.hallId));
    if (hall && participants > hall.capacity) e.participants = 'Количество участников превышает вместимость зала';
    if (body.email && !/^[\w.+-]+@[\w-]+\.[\w.-]+$/.test(str(body.email))) e.email = 'Некорректный адрес почты';
    if (body.photographerIds != null && (!Array.isArray(body.photographerIds) || body.photographerIds.some(id => !db.photographers.some(p => p.id === Number(id) && !p.deletedAt)))) e.photographerIds = 'Фотограф не найден';
    if (!str(body.shootingType)) e.shootingType = 'Укажите тип съёмки';
  }

  const unique = (field, value, label, key = field) => {
    if (value && db[collection].some(row => row.id !== id && !row.deletedAt && String(row[field] || '').trim().toLowerCase() === String(value).trim().toLowerCase())) e[key] = label;
  };
  const dateValid = text => typeof text === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(text) && !Number.isNaN(Date.parse(text)) && new Date(text).toISOString().slice(0, 10) === text;
  if (collection === 'photographers') {
    unique('fullName', str(body.fullName), 'Фотограф с таким ФИО уже есть');
    if (id && db.bookings.some(b => !b.deletedAt && b.photographerIds.includes(id) && !(body.hallIds || []).map(Number).includes(b.hallId))) e.hallIds = 'Нельзя убрать зал с действующими бронированиями фотографа';
  }
  if (collection === 'equipment') {
    if (db.equipment.some(row => row.id !== id && !row.deletedAt && row.hallId === Number(body.hallId) && row.name.toLowerCase() === str(body.name).toLowerCase())) e.name = 'Оборудование с таким названием уже есть в этом зале';
  }
  if (collection === 'clients') {
    const digits = v => String(v || '').replace(/\D/g, '');
    if (body.phone && db.clients.some(c => c.id !== id && !c.deletedAt && digits(c.phone) === digits(body.phone))) e.phone = 'Клиент с таким телефоном уже есть';
    for (const field of ['cardIssuedAt', 'cardExpiresAt']) {
      if (body[field] && !dateValid(body[field])) e[field] = 'Некорректная календарная дата';
    }
    if (body.cardNumber && !body.cardIssuedAt) e.cardIssuedAt = 'Укажите дату выдачи абонемента';
    if (body.cardIssuedAt && body.cardExpiresAt && body.cardIssuedAt > body.cardExpiresAt) e.cardExpiresAt = 'Окончание не раньше даты выдачи';
  }
  if (collection === 'bookings') {
    if (!/^[A-Za-z0-9-]{6,40}$/.test(str(body.accessCode))) e.accessCode = 'Код: латиница, цифры и дефис, от 6 до 40 символов';
    const rawDate = typeof body.date === 'string' ? body.date.slice(0, 10) : '';
    if (!dateValid(rawDate)) e.date = 'Некорректная календарная дата';
    if (!Array.isArray(body.photographerIds) || !body.photographerIds.length) e.photographerIds = 'Выберите хотя бы одного фотографа';
    else if (body.photographerIds.some(id => {
      const person = db.photographers.find(p => p.id === Number(id) && !p.deletedAt);
      return !person || (person.hallIds?.length && !person.hallIds.includes(Number(body.hallId)));
    })) e.photographerIds = 'Фотограф недоступен в выбранном зале';
  }
  return e;
}

// ──────────────────────────── HTTP-обвязка ────────────────────────────

function cors(res) {
  res.setHeader('Access-Control-Allow-Origin', ORIGIN);
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('Access-Control-Max-Age', '86400');
  res.setHeader('Vary', 'Origin');
}

function send(res, status, payload) {
  cors(res);
  if (payload === undefined || status === 204) {
    res.writeHead(204);
    res.end();
    return;
  }
  const body = JSON.stringify(payload, null, 2);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
  });
  res.end(body);
}

function fail(res, status, message) {
  send(res, status, { message });
}

async function readBody(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  if (!chunks.length) return {};
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    return null; // признак некорректного JSON
  }
}

function currentUser(req) {
  const header = req.headers['authorization'] || '';
  if (!header.startsWith('Bearer ')) return null;
  const payload = verify(header.slice(7));
  if (!payload || payload.type !== 'access' || db.revokedSessions.has(payload.sid) || (payload.startedAt && Math.floor(Date.now()/1000) - payload.startedAt >= SESSION_TTL)) return null;
  return db.users.find((u) => u.id === payload.sub && !u.deletedAt) || null;
}

const ROLE_LEVEL = { client: 1, photographer: 2, manager: 3, admin: 4 };

function requireRole(res, user, minRole) {
  if (!user) {
    fail(res, 401, 'Требуется аутентификация');
    return false;
  }
  if (ROLE_LEVEL[user.role] < ROLE_LEVEL[minRole]) {
    fail(res, 403, `Операция доступна начиная с роли «${minRole}»`);
    return false;
  }
  return true;
}

function requireEntityWrite(res, user, collection, hard = false) {
  if (!user) { fail(res, 401, 'Требуется вход в систему'); return false; }
  if (user.role === 'admin') return true;
  if (!hard && user.role === 'manager' && ['bookings', 'clients'].includes(collection)) return true;
  fail(res, 403, hard ? 'Физическое удаление доступно только администратору' : 'Изменение этого справочника доступно только администратору');
  return false;
}

const COLLECTIONS = ['halls', 'photographers', 'clients', 'equipment', 'bookings'];

// ─────────────────────────────── маршруты ───────────────────────────────

async function handle(req, res, url) {
  const q = Object.fromEntries(url.searchParams.entries());
  const path = url.pathname.replace(/\/+$/, '') || '/';
  const method = req.method.toUpperCase();
  const user = currentUser(req);

  // Учебные переключатели поведения
  if (q.__fail) {
    return fail(res, Number(q.__fail), 'Ошибка вызвана намеренно параметром __fail');
  }

  // ── служебные ──
  if (path === '/api/__reset' && method === 'POST') {
    if (!requireRole(res, user, 'admin')) return;
    seed();
    return send(res, 200, { message: 'Данные восстановлены в исходное состояние' });
  }

  if (path === '/api/__health' && method === 'GET') {
    return send(res, 200, { status: 'ok', service: 'focusframe', time: new Date().toISOString() });
  }

  // Справочник адресов. Нужен, чтобы при открытии http://localhost:8080/api
  // в браузере было видно, что сервер работает и какие у него адреса,
  // а не сообщение об ошибке.
  if ((path === '/api' || path === '/api/') && method === 'GET') {
    return send(res, 200, {
      service: 'Учебное API «Фотостудия FocusFrame»',
      version: '1.0',
      time: new Date().toISOString(),
      collections: COLLECTIONS,
      endpoints: {
        'POST /api/auth/login': 'Вход: { username, password } → { accessToken, refreshToken, user }',
        'GET /api/auth/me': 'Текущий пользователь по токену',
        'GET /api/:collection': 'Список записей с поиском, фильтрами, сортировкой и страницами',
        'GET /api/:collection/{id}': 'Одна запись',
        'POST /api/:collection': 'Создать запись (роль manager и выше)',
        'PUT /api/:collection/{id}': 'Изменить запись (роль manager и выше)',
        'DELETE /api/:collection/{id}': 'Логическое удаление (роль manager и выше)',
        'DELETE /api/:collection/{id}?hard=true': 'Физическое удаление (роль admin)',
        'POST /api/:collection/bulk-delete': 'Множественное удаление: { ids: [...] }',
        'POST /api/:collection/{id}/restore': 'Восстановить запись (роль admin)',
        'POST /api/bookings/{id}/cancel': 'Отменить бронирование',
        'POST /api/bookings/{id}/complete': 'Завершить бронирование',
        'GET /api/__health': 'Проверка живости сервера',
        'POST /api/__reset': 'Сброс данных в исходное состояние',
      },
      queryParameters: {
        search: 'Поиск по нескольким полям сущности',
        sort: 'Сортировка, например name,asc или year,desc',
        page: 'Номер страницы, с 1',
        size: 'Размер страницы, до 100',
        includeDeleted: 'true — показать удалённые записи',
      },
      accounts: [
        { username: 'admin', password: 'admin123', role: 'admin' },
        { username: 'manager', password: 'manager123', role: 'manager' },
        { username: 'photographer', password: 'photographer123', role: 'photographer' },
        { username: 'client', password: 'client123', role: 'client' },
      ],
      teachingSwitches: {
        '?__delay=1500': 'задержка ответа на 1,5 с — проверка индикатора загрузки',
        '?__fail=500': 'принудительный код ошибки — проверка состояния ошибки',
      },
    });
  }

  // ── аутентификация ──
  if (path === '/api/auth/register' && method === 'POST') {
    const body = await readBody(req);
    if (!body) return fail(res, 400, 'Тело запроса не является корректным JSON');

    const errors = {};
    const username = String(body.username || '').trim();
    const password = String(body.password || '');
    if (username.length < 3) errors.username = 'Логин не короче трёх символов';
    else if (db.users.find((u) => u.username === username)) errors.username = 'Такой логин уже занят';
    if (password.length < 8) errors.password = 'Пароль не короче восьми символов';
    else if (!/\d/.test(password)) errors.password = 'Пароль должен содержать цифру';
    else if (!/[^\p{L}\p{N}\s]/u.test(password)) errors.password = 'Пароль должен содержать специальный символ';
    if (!String(body.fullName || '').trim()) errors.fullName = 'Укажите имя';
    if (!String(body.email || '').trim()) errors.email = 'Укажите почту';
    else if (db.users.some(u => u.email.toLowerCase() === String(body.email).trim().toLowerCase())) errors.email = 'Пользователь с такой почтой уже есть';
    if (body.email && !/^[\w.+-]+@[\w-]+\.[\w.-]+$/.test(String(body.email))) {
      errors.email = 'Некорректный адрес почты';
    }

    if (Object.keys(errors).length) {
      return send(res, 422, { message: 'Ошибка валидации', errors });
    }

    const clientId = push('clients', normalize('clients', {fullName: body.fullName, email: String(body.email).trim(), clientType: 'Частный'}));
    const id = push('users', {
      username,
      passwordHash: hash(password),
      fullName: String(body.fullName || username),
      email: String(body.email || ''),
      role: 'client',
      clientId,
    });
    return send(res, 201, expandUser(db.users.find((u) => u.id === id)));
  }

  if (path === '/api/auth/login' && method === 'POST') {
    const body = await readBody(req);
    if (!body) return fail(res, 400, 'Тело запроса не является корректным JSON');

    const found = db.users.find(
      (u) => u.username === String(body.username || '').trim() && !u.deletedAt,
    );
    if (!found || found.passwordHash !== hash(String(body.password || ''))) {
      return fail(res, 401, 'Неверный логин или пароль');
    }

    const now = Math.floor(Date.now() / 1000);
    const sid = crypto.randomUUID();
    const accessToken = sign({ sub: found.id, role: found.role, type: 'access', sid, startedAt: now, exp: now + ACCESS_TTL });
    const refreshToken = sign({ sub: found.id, type: 'refresh', sid, startedAt: now, exp: now + REFRESH_TTL });
    db.refreshTokens.add(refreshToken);

    return send(res, 200, {
      accessToken,
      refreshToken,
      expiresIn: ACCESS_TTL,
      user: expandUser(found),
    });
  }

  if (path === '/api/auth/refresh' && method === 'POST') {
    const body = await readBody(req);
    const token = body && body.refreshToken;
    const payload = verify(token);
    if (!payload || payload.type !== 'refresh' || !db.refreshTokens.has(token) || db.revokedSessions.has(payload.sid) || (payload.startedAt && Math.floor(Date.now()/1000) - payload.startedAt >= SESSION_TTL)) {
      return fail(res, 401, 'Токен обновления недействителен');
    }
    const found = db.users.find((u) => u.id === payload.sub);
    if (!found || found.deletedAt) return fail(res, 401, 'Пользователь не найден');

    db.refreshTokens.delete(token);
    const now = Math.floor(Date.now() / 1000);
    const accessToken = sign({ sub: found.id, role: found.role, type: 'access', sid: payload.sid, startedAt: payload.startedAt, exp: now + ACCESS_TTL });
    const refreshToken = sign({ sub: found.id, type: 'refresh', sid: payload.sid, startedAt: payload.startedAt, exp: now + REFRESH_TTL });
    db.refreshTokens.add(refreshToken);

    return send(res, 200, { accessToken, refreshToken, expiresIn: ACCESS_TTL, user: expandUser(found) });
  }

  if (path === '/api/auth/me' && method === 'GET') {
    if (!user) return fail(res, 401, 'Требуется аутентификация');
    return send(res, 200, expandUser(user));
  }

  if (path === '/api/auth/logout' && method === 'POST') {
    const body = await readBody(req);
    if (body && body.refreshToken) {
      const payload = verify(body.refreshToken);
      if (payload?.sid) db.revokedSessions.add(payload.sid);
      db.refreshTokens.delete(body.refreshToken);
    }
    return send(res, 204);
  }

  // ── управление пользователями (только admin) ──
  if (path === '/api/users' && method === 'GET') {
    if (!requireRole(res, user, 'admin')) return;
    const rows = applySort(db.users.filter((u) => !u.deletedAt), q.sort);
    const page = paginate(rows, q);
    return send(res, 200, { ...page, items: page.items.map(expandUser) });
  }

  // Role-specific workspaces. Roles are read from the server user record.
  if (path === '/api/account/bookings' && method === 'GET') {
    if (!user) return fail(res, 401, 'Требуется вход');
    if (user.role !== 'client') return fail(res, 403, 'Личный кабинет доступен клиенту');
    return send(res, 200, db.bookings.filter(b => b.clientId === user.clientId && !b.deletedAt).map(expandBooking));
  }
  if (path === '/api/manager/workspace' && method === 'GET') {
    if (!user) return fail(res, 401, 'Требуется вход');
    if (user.role !== 'manager') return fail(res, 403, 'Рабочее место доступно менеджеру');
    return send(res, 200, {activeBookings: db.bookings.filter(b => !b.deletedAt && b.status === 'active').length,
      clients: db.clients.filter(c => !c.deletedAt).length,
      halls: db.halls.filter(h => !h.deletedAt).length});
  }
  if (path === '/api/admin/statistics' && method === 'GET') {
    if (!requireRole(res, user, 'admin')) return;
    return send(res, 200, {users: db.users.filter(u => !u.deletedAt).length,
      halls: db.halls.filter(h => !h.deletedAt).length, clients: db.clients.filter(c => !c.deletedAt).length,
      bookings: db.bookings.filter(b => !b.deletedAt).length,
      activeBookings: db.bookings.filter(b => !b.deletedAt && b.status === 'active').length,
      deletedRecords: COLLECTIONS.reduce((n,c) => n+db[c].filter(r => r.deletedAt).length,0)});
  }
  const roleChange = path.match(/^\/api\/users\/(\d+)\/role$/);
  if (roleChange && method === 'PATCH') {
    if (!requireRole(res, user, 'admin')) return;
    const target = db.users.find(u => u.id === Number(roleChange[1]) && !u.deletedAt);
    if (!target) return fail(res, 404, 'Пользователь не найден');
    const body = await readBody(req);
    if (!body || !Object.hasOwn(ROLE_LEVEL, body.role)) return send(res, 422, {message: 'Ошибка валидации', errors: {role: 'Неизвестная роль'}});
    if (target.id === user.id && body.role !== 'admin') return fail(res, 409, 'Нельзя понизить собственную роль администратора');
    if (body.role === 'client' && !target.clientId) target.clientId = push('clients', normalize('clients', {fullName: target.fullName, email: target.email, clientType: 'Частный'}));
    target.role = body.role;
    return send(res, 200, expandUser(target));
  }
  const extension = path.match(/^\/api\/bookings\/(\d+)\/extend$/);
  if (extension && method === 'POST') {
    if (!user) return fail(res, 401, 'Требуется вход');
    if (user.role !== 'client') return fail(res, 403, 'Продление доступно клиенту в личном кабинете');
    const row = db.bookings.find(b => b.id === Number(extension[1]) && !b.deletedAt);
    if (!row) return fail(res, 404, 'Бронирование не найдено');
    if (row.clientId !== user.clientId) return fail(res, 403, 'Нельзя продлить чужую бронь');
    if (row.status !== 'active' || row.durationHours >= 24) return fail(res, 409, 'Эту бронь нельзя продлить');
    row.durationHours += 1;
    return send(res, 200, expandBooking(row));
  }

  // ── специальные операции с бронированиями ──
  if (path === '/api/bookings' && method === 'POST') {
    if (!user) return fail(res, 401, 'Требуется вход в систему');
    if (!['client','manager','admin'].includes(user.role)) return fail(res, 403, 'Создание брони недоступно вашей роли');
    const body = await readBody(req);
    if (!body) return fail(res, 400, 'Тело запроса не является корректным JSON');
    if (user.role === 'client') {
      if (!user.clientId) return fail(res, 403, 'Аккаунт не связан с профилем клиента');
      if (body.clientId != null && Number(body.clientId) !== 0 && Number(body.clientId) !== user.clientId) return fail(res, 403, 'Можно бронировать только от своего имени');
      body.clientId = user.clientId;
      body.accessCode = 'BR-' + crypto.randomUUID().toUpperCase();
      body.status = 'active';
      body.email = body.email || user.email;
      const today = new Intl.DateTimeFormat('sv-SE', {timeZone:'Europe/Moscow'}).format(new Date());
      if (typeof body.date === 'string' && body.date.slice(0,10) < today) return send(res, 422, {message:'Ошибка валидации', errors:{date:'Нельзя бронировать прошедшую дату'}});
    }

    const errors = validate('bookings', body);
    if (Object.keys(errors).length) return send(res, 422, { message: 'Ошибка валидации', errors });
    const conflict = bookingConflict(body);
    if (conflict) return fail(res, 409, conflict);

    const id = push('bookings', normalize('bookings', body));
    return send(res, 201, expandBooking(db.bookings.find((b) => b.id === id)));
  }

  let m = path.match(/^\/api\/bookings\/(\d+)\/cancel$/);
  if (m && method === 'POST') {
    if (!requireRole(res, user, 'manager')) return;
    const booking = db.bookings.find((b) => b.id === Number(m[1]) && !b.deletedAt);
    if (!booking) return fail(res, 404, 'Бронирование не найдено');
    if (booking.status !== 'active') {
      return fail(res, 409, 'Отменить можно только активное бронирование');
    }
    booking.status = 'cancelled';
    return send(res, 200, expandBooking(booking));
  }

  m = path.match(/^\/api\/bookings\/(\d+)\/complete$/);
  if (m && method === 'POST') {
    if (!requireRole(res, user, 'manager')) return;
    const booking = db.bookings.find((b) => b.id === Number(m[1]) && !b.deletedAt);
    if (!booking) return fail(res, 404, 'Бронирование не найдено');
    if (booking.status !== 'active') {
      return fail(res, 409, 'Завершить можно только активное бронирование');
    }
    booking.status = 'completed';
    return send(res, 200, expandBooking(booking));
  }

  // ── единообразный CRUD ──
  const bulk = path.match(/^\/api\/([a-z]+)\/bulk-delete$/);

  if (bulk && method === 'POST') {
    const collection = bulk[1];
    if (!COLLECTIONS.includes(collection)) return fail(res, 404, 'Ресурс не найден');
    const hard = q.hard === 'true';
    if (!requireEntityWrite(res, user, collection, hard)) return;

    const body = await readBody(req);
    const ids = Array.isArray(body && body.ids) ? body.ids.map(Number) : [];
    if (!ids.length) {
      return send(res, 422, {
        message: 'Ошибка валидации',
        errors: { ids: 'Передайте непустой список идентификаторов' },
      });
    }

    const conflict = deletionConflict(collection, ids, hard);
    if (conflict) return fail(res, 409, conflict);
    if (hard) {
      const before = db[collection].length;
      db[collection] = db[collection].filter(row => !ids.includes(row.id));
      return send(res, 200, { deleted: before - db[collection].length });
    }
    let deleted = 0;
    for (const row of db[collection]) {
      if (ids.includes(row.id) && !row.deletedAt) {
        row.deletedAt = new Date().toISOString();
        deleted += 1;
      }
    }
    return send(res, 200, { deleted });
  }

  m = path.match(/^\/api\/([a-z]+)(?:\/(\d+))?(?:\/(restore))?$/);

  if (m) {
    const collection = m[1];
    const id = m[2] ? Number(m[2]) : null;
    const action = m[3] || null;

    if (!COLLECTIONS.includes(collection)) return fail(res, 404, 'Ресурс не найден');
    const expand = EXPANDERS[collection];
    if (!user) return fail(res, 401, 'Требуется вход в систему');
    if (collection === 'clients' && !requireRole(res, user, 'manager')) return;

    // восстановление
    if (action === 'restore' && method === 'POST') {
      if (!requireRole(res, user, 'admin')) return;
      const row = db[collection].find((x) => x.id === id);
      if (!row) return fail(res, 404, 'Объект не найден');
      const errors = validate(collection, row, id);
      if (Object.keys(errors).length) return send(res, 422, { message: 'Ошибка валидации', errors });
      if (collection === 'bookings') {
        const conflict = bookingConflict(row, id);
        if (conflict) return fail(res, 409, conflict);
      }
      row.deletedAt = null;
      return send(res, 200, expand(row));
    }

    // список
    if (id === null && method === 'GET') {
      let rows = db[collection];
      if (q.includeDeleted !== 'true') rows = rows.filter((x) => !x.deletedAt);

      // клиент видит только свои бронирования
      if (collection === 'bookings' && user && user.role === 'client') {
        rows = rows.filter((b) => b.clientId === user.clientId);
      }

      rows = applyFilters(collection, rows, q);
      rows = applySort(rows, q.sort);
      const page = paginate(rows, q);
      return send(res, 200, { ...page, items: page.items.map(expand) });
    }

    // одна запись
    if (id !== null && method === 'GET') {
      const row = db[collection].find(
        (x) => x.id === id && (q.includeDeleted === 'true' || !x.deletedAt),
      );
      if (!row) return fail(res, 404, 'Объект не найден');
      if (collection === 'bookings' && user?.role === 'client' && row.clientId !== user.clientId) return fail(res, 403, 'Это бронирование другого клиента');
      return send(res, 200, expand(row));
    }

    // создание
    if (id === null && method === 'POST') {
      if (!requireEntityWrite(res, user, collection)) return;
      const body = await readBody(req);
      if (!body) return fail(res, 400, 'Тело запроса не является корректным JSON');

      const errors = validate(collection, body);
      if (Object.keys(errors).length) {
        return send(res, 422, { message: 'Ошибка валидации', errors });
      }

      const newId = push(collection, normalize(collection, body));
      return send(res, 201, expand(db[collection].find((x) => x.id === newId)));
    }

    // изменение
    if (id !== null && (method === 'PUT' || method === 'PATCH')) {
      if (!requireEntityWrite(res, user, collection)) return;
      const row = db[collection].find((x) => x.id === id && !x.deletedAt);
      if (!row) return fail(res, 404, 'Объект не найден');

      const body = await readBody(req);
      if (!body) return fail(res, 400, 'Тело запроса не является корректным JSON');

      const merged = method === 'PATCH' ? { ...row, ...body } : body;
      const errors = validate(collection, merged, id);
      if (Object.keys(errors).length) {
        return send(res, 422, { message: 'Ошибка валидации', errors });
      }

      if (collection === 'bookings') {
        const conflict = bookingConflict({ ...merged, status: row.status }, id);
        if (conflict) return fail(res, 409, conflict);
      }
      Object.assign(row, normalize(collection, { ...merged, ...(collection === 'bookings' ? { status: row.status } : {}) }));
      return send(res, 200, expand(row));
    }

    // удаление
    if (id !== null && method === 'DELETE') {
      const hard = q.hard === 'true';
      if (!requireEntityWrite(res, user, collection, hard)) return;

      const index = db[collection].findIndex((x) => x.id === id);
      if (index === -1) return fail(res, 404, 'Объект не найден');

      const conflict = deletionConflict(collection, [id], hard);
      if (conflict) return fail(res, 409, conflict);
      if (hard) {
        if (collection === 'halls') {
          const active = db.bookings.some(
            (b) => b.hallId === id && b.status === 'active' && !b.deletedAt,
          );
          if (active) return fail(res, 409, 'В зале есть активные бронирования, удалить его нельзя');
        }
        if (collection === 'clients') {
          const active = db.bookings.some(
            (b) => b.clientId === id && b.status === 'active' && !b.deletedAt,
          );
          if (active) return fail(res, 409, 'У клиента есть активные бронирования');
        }
        db[collection].splice(index, 1);
      } else {
        db[collection][index].deletedAt = new Date().toISOString();
      }
      return send(res, 204);
    }
  }

  return fail(res, 404, `Адрес ${method} ${path} не обслуживается`);
}

// Формы выбирают дату без времени: один активный заказ на зал в день.
function bookingConflict(body, id = null) {
  if (body.status && body.status !== 'active') return null;
  const day = new Date(body.date).toISOString().slice(0, 10);
  const others = db.bookings.filter(b => b.id !== id && !b.deletedAt && b.status === 'active' && b.date.slice(0, 10) === day);
  if (others.some(b => b.hallId === Number(body.hallId))) return 'На эту дату в зале уже есть активное бронирование';
  if (others.some(b => b.photographerIds.some(id => (body.photographerIds || []).map(Number).includes(id)))) return 'Фотограф уже занят на выбранную дату';
  return null;
}

function deletionConflict(collection, ids, hard = false) {
  const active = row => hard || !row.deletedAt;
  const bookings = db.bookings.filter(b => active(b) && (
    collection === 'halls' ? ids.includes(b.hallId) :
    collection === 'clients' ? ids.includes(b.clientId) :
    collection === 'photographers' ? b.photographerIds.some(id => ids.includes(id)) : false));
  const equipment = collection === 'halls' ? db.equipment.filter(e => active(e) && ids.includes(e.hallId)) : [];
  const people = collection === 'halls' ? db.photographers.filter(p => active(p) && (p.hallIds || []).some(id => ids.includes(id))) : [];
  return bookings.length + equipment.length + people.length
    ? `Удаление невозможно: связанных бронирований — ${bookings.length}, оборудования — ${equipment.length}, фотографов — ${people.length}` : null;
}

function normalize(collection, body) {
  const num = (v) => (v == null || v === '' ? null : Number(v));
  const str = (v) => (v == null ? '' : String(v).trim());
  const ids = (v) =>
    Array.isArray(v) ? v.map(Number).filter((n) => Number.isInteger(n)) : [];

  switch (collection) {
    case 'halls':
      return {
        name: str(body.name),
        code: str(body.code).toUpperCase(),
        style: str(body.style),
        capacity: num(body.capacity),
        hourlyRate: num(body.hourlyRate),
        description: str(body.description),
      };
    case 'photographers':
      return {
        fullName: str(body.fullName),
        hallIds: ids(body.hallIds),
        specialization: str(body.specialization),
        city: str(body.city),
        birthYear: num(body.birthYear),
        experienceYears: num(body.experienceYears),
        hourlyRate: num(body.hourlyRate),
      };
    case 'clients':
      return {
        fullName: str(body.fullName),
        email: str(body.email),
        phone: str(body.phone),
        clientType: str(body.clientType) || 'Частный',
        company: str(body.company),
        notes: str(body.notes),
        cardNumber: str(body.cardNumber).toUpperCase(),
        cardIssuedAt: str(body.cardIssuedAt),
        cardExpiresAt: str(body.cardExpiresAt),
      };
    case 'equipment':
      return {
        name: str(body.name),
        category: str(body.category),
        manufacturer: str(body.manufacturer),
        hallId: num(body.hallId),
        quantity: num(body.quantity),
        pricePerDay: num(body.pricePerDay),
      };
    case 'bookings':
      return {
        accessCode: str(body.accessCode).toUpperCase(),
        email: str(body.email),
        hallId: num(body.hallId),
        clientId: num(body.clientId),
        photographerIds: ids(body.photographerIds),
        date: body.date ? new Date(body.date).toISOString() : new Date().toISOString(),
        durationHours: num(body.durationHours),
        participants: num(body.participants),
        shootingType: str(body.shootingType),
        comment: str(body.comment),
        status: str(body.status) || 'active',
      };
    default:
      return { ...body };
  }
}

function expandUser(u) {
  return {
    id: u.id,
    username: u.username,
    fullName: u.fullName,
    email: u.email,
    role: u.role,
    clientId: u.clientId,
  };
}

// ─────────────────────────────── запуск ───────────────────────────────

seed();
const dataFile = nodePath.join(__dirname, '.local-state.json');
const ephemeral = args.includes('--ephemeral');
function saveData() {
  if (ephemeral) return;
  const state = {...db, refreshTokens: [...db.refreshTokens], revokedSessions: [...db.revokedSessions]};
  fs.writeFileSync(dataFile + '.tmp', JSON.stringify(state));
  fs.renameSync(dataFile + '.tmp', dataFile);
}
if (!ephemeral && fs.existsSync(dataFile)) {
  const state = JSON.parse(fs.readFileSync(dataFile, 'utf8'));
  db = {...state, refreshTokens: new Set(state.refreshTokens || []), revokedSessions: new Set(state.revokedSessions || [])};
} else if (!ephemeral && arg('import', null)) {
  const imported = JSON.parse(fs.readFileSync(arg('import'), 'utf8'));
  for (const collection of COLLECTIONS) {
    db[collection] = imported[collection].map(row => ({...normalize(collection, {
      ...row, fullName: row.fullName, hallId: row.hallId ?? row.hall?.id,
      clientId: row.clientId ?? row.client?.id,
      cardNumber: row.card?.number, cardIssuedAt: row.card?.issuedAt, cardExpiresAt: row.card?.expiresAt,
    }), id: row.id, createdAt: row.createdAt, deletedAt: row.deletedAt}));
    db.seq[collection] = Math.max(0, ...db[collection].map(row => row.id));
  }
  saveData();
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  if (process.env.STATIC_DIR && !/^\/api(?:\/|$)/.test(url.pathname)) {
    return require('./static-files').serveStatic(req, res, process.env.STATIC_DIR);
  }

  // Предварительный запрос браузера. Без этого обработчика
  // на web не заработает ни один запрос с заголовком Authorization.
  if (req.method === 'OPTIONS') {
    cors(res);
    res.writeHead(204);
    return res.end();
  }

  // Учебная задержка: включается переменной окружения DEMO_DELAY_MS.
  const delay = Number(url.searchParams.get('__delay') || process.env.DEMO_DELAY_MS || 0);
  if (delay > 0) await new Promise((r) => setTimeout(r, Math.min(delay, 10000)));

  const started = Date.now();
  try {
    await handle(req, res, url);
    if (!['GET','HEAD','OPTIONS'].includes(req.method) && res.statusCode < 400) saveData();
  } catch (err) {
    console.error(err);
    if (!res.headersSent) fail(res, 500, 'Внутренняя ошибка сервера: ' + err.message);
  }
  console.log(
    `${req.method.padEnd(6)} ${url.pathname}${url.search}  → ${res.statusCode}  ${Date.now() - started} мс`,
  );
});

server.listen(PORT, () => {
  console.log('');
  console.log('  Учебное API «Фотостудия FocusFrame»');
  console.log(`  Адрес:              http://localhost:${PORT}/api`);
  console.log(`  Разрешённый источник: ${ORIGIN}`);
  console.log(`  Срок жизни токена:  ${ACCESS_TTL} с`);
  console.log('');
  console.log('  Учётные записи:  admin/admin123   manager/manager123');
  console.log('                   photographer/photographer123   client/client123');
  console.log('  Сброс данных:    POST /api/__reset');
  console.log('  Задержка ответа: любой запрос с ?__delay=1500');
  console.log('  Ошибка по требованию: любой запрос с ?__fail=500');
  console.log('');
});
