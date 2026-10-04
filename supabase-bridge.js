/* Aura X - Supabase-only backend bridge.
 * Keeps the existing data-layer call shape so the UI/features do not need a rewrite.
 */
(function () {
  'use strict';

  const TABLE_MAP = {
    users: 'users',
    accountLinks: 'account_links',
    posts: 'posts',
    rooms: 'rooms',
    statuses: 'statuses',
    notifications: 'notifications',
    reports: 'reports',
    announcements: 'announcements',
    votes: 'votes',
    restrictions: 'restrictions',
    bannedUsers: 'banned_users',
    bannedIPs: 'banned_ips',
    bannedDevices: 'banned_devices',
    bannedEmails: 'banned_emails',
    pushTokens: 'push_tokens',
    roomMessages: 'room_messages'
  };

  const clone = (v) => v == null ? v : JSON.parse(JSON.stringify(v));
  const isObject = (v) => v && typeof v === 'object' && !Array.isArray(v);

  function getPath(obj, path) {
    return String(path).split('.').reduce((cur, key) => cur == null ? undefined : cur[key], obj);
  }

  function setPath(obj, path, value) {
    const parts = String(path).split('.');
    let cur = obj;
    for (let i = 0; i < parts.length - 1; i++) {
      const key = parts[i];
      if (!isObject(cur[key]) && !Array.isArray(cur[key])) cur[key] = {};
      cur = cur[key];
    }
    cur[parts[parts.length - 1]] = value;
  }

  function applyValue(existing, value) {
    if (value && value.__auraxType === 'serverTimestamp') return Date.now();
    if (value && value.__auraxType === 'arrayUnion') {
      const arr = Array.isArray(existing) ? clone(existing) : [];
      for (const item of value.values || []) {
        if (!arr.some(x => JSON.stringify(x) === JSON.stringify(item))) arr.push(clone(item));
      }
      return arr;
    }
    if (value && value.__auraxType === 'arrayRemove') {
      const arr = Array.isArray(existing) ? clone(existing) : [];
      return arr.filter(x => !(value.values || []).some(item => JSON.stringify(x) === JSON.stringify(item)));
    }
    return clone(value);
  }

  function applyPatch(source, patch, merge = true) {
    const out = merge ? clone(source || {}) : {};
    for (const [rawKey, rawValue] of Object.entries(patch || {})) {
      const value = applyValue(getPath(out, rawKey), rawValue);
      if (rawKey.includes('.')) setPath(out, rawKey, value);
      else out[rawKey] = value;
    }
    return out;
  }

  function errorObject(error, fallback = 'Supabase işlemi başarısız.') {
    if (!error) return null;
    const e = new Error(error.message || fallback);
    e.code = error.code || error.status || 'supabase_error';
    e.details = error.details;
    e.hint = error.hint;
    return e;
  }

  class QuerySnapshot {
    constructor(rows) {
      this.docs = rows.map(row => new DocumentSnapshot(row.id, row.data || {}));
      this.empty = this.docs.length === 0;
      this.size = this.docs.length;
    }
    forEach(fn) { this.docs.forEach(fn); }
  }

  class DocumentSnapshot {
    constructor(id, data, exists = true) {
      this.id = id;
      this._data = clone(data || {});
      this.exists = exists;
    }
    data() { return clone(this._data); }
  }

  class Transaction {
    constructor() { this.ops = []; }
    async get(ref) { return ref.get(); }
    set(ref, data, options = {}) { this.ops.push({ type: 'set', ref, data, options }); }
    update(ref, data) { this.ops.push({ type: 'update', ref, data }); }
    delete(ref) { this.ops.push({ type: 'delete', ref }); }
  }

  class DocumentRef {
    constructor(table, id, parent = null) {
      this._table = table;
      this._id = String(id);
      this.id = String(id);
      this._parent = parent;
    }

    async get() {
      const q = window.supabaseClient.from(this._table).select('id,data').eq('id', this._id).maybeSingle();
      const { data, error } = await q;
      if (error) throw errorObject(error);
      return data ? new DocumentSnapshot(data.id, data.data || {}) : new DocumentSnapshot(this._id, {}, false);
    }

    async set(value, options = {}) {
      let payload = clone(value || {});
      if (this._parent && this._parent._context) payload = { ...this._parent._context, ...payload };
      if (options.merge) {
        const current = await this.get();
        payload = applyPatch(current.exists ? current.data() : {}, payload, true);
      } else {
        payload = applyPatch({}, payload, false);
      }
      const { error } = await window.supabaseClient.from(this._table).upsert({ id: this._id, data: payload }, { onConflict: 'id' });
      if (error) throw errorObject(error);
      return this;
    }

    async update(value) {
      const current = await this.get();
      if (!current.exists) {
        const err = new Error('Belge bulunamadı.'); err.code = 'not-found'; throw err;
      }
      const payload = applyPatch(current.data(), value, true);
      const { error } = await window.supabaseClient.from(this._table).update({ data: payload }).eq('id', this._id);
      if (error) throw errorObject(error);
      return this;
    }

    async delete() {
      const { error } = await window.supabaseClient.from(this._table).delete().eq('id', this._id);
      if (error) throw errorObject(error);
    }

    collection(name) {
      if (name === 'pushTokens') return new CollectionRef(TABLE_MAP.pushTokens, { username: this._id });
      return new CollectionRef(TABLE_MAP[name] || name, {});
    }
  }

  class CollectionRef {
    constructor(table, context = {}) {
      this._table = table;
      this._filters = [];
      this._order = null;
      this._limit = null;
      this._context = context || {};
    }

    doc(id) { return new DocumentRef(this._table, id, this); }

    async add(value) {
      const id = (crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`);
      const payload = { ...(clone(value || {})) };
      Object.assign(payload, this._context);
      await this.doc(id).set(payload);
      return this.doc(id);
    }

    where(field, op, value) {
      this._filters.push({ field, op, value });
      return this;
    }
    orderBy(field, direction = 'asc') {
      this._order = { field, direction: String(direction).toLowerCase() === 'desc' ? 'desc' : 'asc' };
      return this;
    }
    limit(n) { this._limit = Math.max(0, Number(n) || 0); return this; }

    _matches(row) {
      const data = row.data || {};
      for (const f of this._filters) {
        const actual = getPath(data, f.field);
        const expected = f.value;
        switch (f.op) {
          case '==': if (JSON.stringify(actual) !== JSON.stringify(expected)) return false; break;
          case '!=': if (JSON.stringify(actual) === JSON.stringify(expected)) return false; break;
          case '<': if (!(actual < expected)) return false; break;
          case '<=': if (!(actual <= expected)) return false; break;
          case '>': if (!(actual > expected)) return false; break;
          case '>=': if (!(actual >= expected)) return false; break;
          case 'array-contains': if (!Array.isArray(actual) || !actual.some(x => JSON.stringify(x) === JSON.stringify(expected))) return false; break;
          case 'array-contains-any': if (!Array.isArray(actual) || !Array.isArray(expected) || !actual.some(x => expected.some(y => JSON.stringify(x) === JSON.stringify(y)))) return false; break;
          case 'in': if (!Array.isArray(expected) || !expected.some(x => JSON.stringify(x) === JSON.stringify(actual))) return false; break;
          case 'not-in': if (Array.isArray(expected) && expected.some(x => JSON.stringify(x) === JSON.stringify(actual))) return false; break;
          default: return false;
        }
      }
      if (this._context && this._context.username != null && String(data.username || '') !== String(this._context.username)) return false;
      return true;
    }

    async _queryRows() {
      // Keep the query shape generic: all Aura data lives in each table's JSONB `data` field.
      // Realtime changes cause a fresh query, preserving the existing application behaviour.
      const { data, error } = await window.supabaseClient.from(this._table).select('id,data').limit(1000);
      if (error) throw errorObject(error);
      let rows = (data || []).filter(r => this._matches(r));
      if (this._order) {
        const { field, direction } = this._order;
        rows.sort((a, b) => {
          const av = getPath(a.data || {}, field);
          const bv = getPath(b.data || {}, field);
          const aa = av && typeof av === 'object' && av.seconds ? av.seconds * 1000 : av;
          const bb = bv && typeof bv === 'object' && bv.seconds ? bv.seconds * 1000 : bv;
          if (aa === bb) return 0;
          return (aa < bb ? -1 : 1) * (direction === 'desc' ? -1 : 1);
        });
      }
      if (this._limit != null) rows = rows.slice(0, this._limit);
      return rows;
    }

    async get() { return new QuerySnapshot(await this._queryRows()); }

    onSnapshot(next, errorCb) {
      let stopped = false;
      let timer = null;
      let channel = null;
      const emit = async () => {
        if (stopped) return;
        try {
          const snapshot = await this.get();
          if (!stopped) next(snapshot);
        } catch (e) {
          if (!stopped && errorCb) errorCb(e);
        }
      };
      const schedule = () => {
        clearTimeout(timer);
        timer = setTimeout(emit, 50);
      };
      emit();
      channel = window.supabaseClient.channel(`aurax-${this._table}-${Math.random().toString(36).slice(2)}`)
        .on('postgres_changes', { event: '*', schema: 'public', table: this._table }, schedule)
        .subscribe();
      return () => {
        stopped = true;
        clearTimeout(timer);
        if (channel) window.supabaseClient.removeChannel(channel);
      };
    }
  }

  const supabaseFieldValue = {
    serverTimestamp: () => ({ __auraxType: 'serverTimestamp' }),
    arrayUnion: (...values) => ({ __auraxType: 'arrayUnion', values }),
    arrayRemove: (...values) => ({ __auraxType: 'arrayRemove', values })
  };

  const dataStore = {
    collection(name) {
      const table = TABLE_MAP[name] || name;
      return new CollectionRef(table);
    },
    batch() {
      const tx = new Transaction();
      return {
        set: (...a) => tx.set(...a),
        update: (...a) => tx.update(...a),
        delete: (...a) => tx.delete(...a),
        commit: async () => {
          for (const op of tx.ops) {
            if (op.type === 'set') await op.ref.set(op.data, op.options);
            else if (op.type === 'update') await op.ref.update(op.data);
            else await op.ref.delete();
          }
        }
      };
    },
    runTransaction: async (callback) => {
      const tx = new Transaction();
      const result = await callback(tx);
      for (const op of tx.ops) {
        if (op.type === 'set') await op.ref.set(op.data, op.options);
        else if (op.type === 'update') await op.ref.update(op.data);
        else await op.ref.delete();
      }
      return result;
    }
  };

  const authService = {
    currentUser: null,
    async refresh() {
      const { data, error } = await window.supabaseClient.auth.getUser();
      if (error || !data?.user) { this.currentUser = null; return null; }
      this.currentUser = data.user;
      return this.currentUser;
    },
    async signOut() {
      const { error } = await window.supabaseClient.auth.signOut();
      this.currentUser = null;
      if (error) throw errorObject(error);
    }
  };

  window.dataStore = dataStore;
  window.supabaseFieldValue = supabaseFieldValue;
  window.authService = authService;
})();
