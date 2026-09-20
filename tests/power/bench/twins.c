// The C twins of the power benches: twins <name> prints the same checksum the
// Bend bench prints. Plain single-thread C under the flags Bend builds with (clang -O3): the speed
// to be near.
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef uint32_t u32;

static u32 key(u32 i) { return ((i + 1) * 2654435761u) ^ (i >> 3); }
static u32 rot(u32 x, int l) { return (x << l) | (x >> (32 - l)); }

#define MIX(r) a += b; b = rot(b, r) ^ a;
#define A(ka, kb, n) MIX(13) MIX(15) MIX(26) MIX(6) a += ka; b += kb + n;
#define B(ka, kb, n) MIX(17) MIX(29) MIX(16) MIX(24) a += ka; b += kb + n;
static u32 threefry(u32 k0, u32 k1, u32 c0, u32 c1) {
  u32 k2 = k0 ^ k1 ^ 466688986u, a = c0 + k0, b = c1 + k1;
  A(k1, k2, 1) B(k2, k0, 2) A(k0, k1, 3) B(k1, k2, 4) A(k2, k0, 5)
  return a;
}

typedef struct { u32 *p; u32 n, cap; } vec;
static void push(vec *v, u32 x) {
  if (v->n == v->cap) { v->cap = v->cap ? v->cap * 2 : 4; v->p = realloc(v->p, v->cap * 4); }
  v->p[v->n++] = x;
}

typedef struct { u32 k, x; } ent;
static int less(ent a, ent b) { return a.k < b.k || (a.k == b.k && a.x < b.x); }
static void up(ent *h, u32 i, ent e) {
  while (i) { u32 j = (i - 1) / 2; if (!less(e, h[j])) break; h[i] = h[j]; i = j; }
  h[i] = e;
}
static void down(ent *h, u32 n, u32 i, ent e) {
  for (;;) {
    u32 c = 2 * i + 1;
    if (c >= n) break;
    if (c + 1 < n && less(h[c + 1], h[c])) c++;
    if (!less(h[c], e)) break;
    h[i] = h[c]; i = c;
  }
  h[i] = e;
}
static ent pop(ent *h, u32 *n) {
  ent top = h[0], last = h[--*n];
  if (*n) down(h, *n, 0, last);
  return top;
}

// -- the json twin: the same event scanner, the same grammar, in plain C ------
enum { EOBJ = 1, ECOBJ, EARR, ECARR, EKEY, ESTR, ENUM, ETRU, EFAL, ENUL, EEOF, EBAD };
enum { MVAL, MVAL0, MKEY, MKEY0, MPOST, MDONE, MBAD };
typedef struct { const unsigned char *b; u32 n, at, dep, left; int md; unsigned char ks[260]; } jst;
typedef struct { int k; u32 at, len; } jev;

static int d5(unsigned char *o, u32 x) {
  o[0] = '1' + (x & 7);  // never 0: a leading zero is not a json number
  for (int j = 1; j < 5; j++) o[j] = '0' + ((x >> (3 * j)) & 7);
  return 5;
}
static unsigned char *jdoc(u32 lo, u32 recs, u32 *len) {
  unsigned char *p = malloc((size_t)recs * 54 + 8);
  u32 m = 0;
  p[m++] = '[';
  for (u32 i = 0; i < recs; i++) {
    u32 h = key(lo + i);
    memcpy(p + m, "{\"i\":", 5); m += 5;
    m += d5(p + m, h);
    memcpy(p + m, ",\"s\":\"", 6); m += 6;
    for (int j = 0; j < 8; j++) p[m++] = 'a' + ((h >> (4 * j)) & 15);
    memcpy(p + m, "\",\"b\":", 6); m += 6;
    memcpy(p + m, (h & 1) ? "null" : "true", 4); m += 4;
    memcpy(p + m, ",\"a\":[", 6); m += 6;
    m += d5(p + m, h);
    p[m++] = ',';
    m += d5(p + m, h >> 7);
    memcpy(p + m, "]},", 3); m += 3;
  }
  p[m - 1] = ']';  // over the last record's comma
  *len = m;
  return p;
}

static u32 jat(const unsigned char *b, u32 i, u32 n) { return i < n ? b[i] : 0; }
static u32 jws(const unsigned char *b, u32 i, u32 n) {
  while (i < n && (b[i] == 32 || b[i] == 9 || b[i] == 10 || b[i] == 13)) i++;
  return i;
}
static int jhex(u32 c) { return (c >= 48 && c <= 57) || (c >= 97 && c <= 102) || (c >= 65 && c <= 70); }

// 0 ok, 1 refused; *ip is where the scan stopped, either way
static int jstr(const unsigned char *b, u32 at, u32 n, u32 left, u32 *ip) {
  u32 i = at + 1, room = n - at, fuel = (left < room ? left : room) + 1;
  while (fuel--) {
    if (i >= n) { *ip = i; return 1; }
    u32 c = b[i];
    if (c == 34) { *ip = i + 1; return 0; }
    if (c == 92) {
      u32 j = i + 1;
      if (j >= n) { *ip = j; return 1; }
      u32 e = b[j];
      if (e == '"' || e == '\\' || e == '/' || e == 'b' || e == 'f' || e == 'n' || e == 'r' || e == 't') { i = j + 1; continue; }
      if (e != 'u') { *ip = j; return 1; }
      u32 k = j + 1;
      for (int q = 0; q < 4; q++) { if (!jhex(jat(b, k, n))) { *ip = k; return 1; } k++; }
      i = k;
      continue;
    }
    if (c < 32) { *ip = i; return 1; }
    i++;
  }
  *ip = i;
  return 1;
}
static u32 jdig(const unsigned char *b, u32 i, u32 n, u32 fuel, u32 *k) {
  *k = 0;
  while (fuel--) { u32 c = jat(b, i, n); if (c < 48 || c > 57) break; i++; (*k)++; }
  return i;
}
static int jnum(const unsigned char *b, u32 at, u32 n, u32 left, u32 *ip) {
  u32 room = n - at, fuel = (left < room ? left : room) + 1, i = at, k;
  if (jat(b, i, n) == 45) i++;
  u32 c1 = jat(b, i, n);
  i = jdig(b, i, n, fuel, &k);
  if (k == 0 || (c1 == 48 && k != 1)) { *ip = i; return 1; }
  if (jat(b, i, n) == 46) { u32 k2; i = jdig(b, i + 1, n, fuel, &k2); if (!k2) { *ip = i; return 1; } }
  u32 c = jat(b, i, n);
  if (c == 101 || c == 69) {
    u32 j = i + 1, k3;
    u32 s = jat(b, j, n);
    if (s == 43 || s == 45) j++;
    i = jdig(b, j, n, fuel, &k3);
    if (!k3) { *ip = i; return 1; }
  }
  *ip = i;
  return 0;
}
static int jlit(const unsigned char *b, u32 i, u32 n, const char *w, u32 *ip) {
  for (; *w; w++) { if (jat(b, i, n) != (u32)(unsigned char)*w) { *ip = i; return 1; } i++; }
  *ip = i;
  return 0;
}
static u32 jspend(u32 left, u32 k) { return left > k ? left - k : 0; }

static jev jnext(jst *s) {
  for (;;) {
    s->at = jws(s->b, s->at, s->n);
    u32 at = s->at, n = s->n, i;
    int past = at >= n;
    u32 c = past ? 0 : s->b[at];
    jev e = {EBAD, at, 0};
    if (s->md == MBAD) return e;
    if (s->md == MDONE) { if (past) { e.k = EEOF; return e; } s->md = MBAD; return e; }
    if (s->md == MPOST) {
      if (c == ',') { s->at = at + 1; s->left = jspend(s->left, 1); s->md = s->ks[s->dep - 1] ? MKEY : MVAL; continue; }
      if ((c == ']' && !s->ks[s->dep - 1]) || (c == '}' && s->ks[s->dep - 1])) {
        e.k = c == '}' ? ECOBJ : ECARR;
        s->dep--;
        s->at = at + 1;
        s->left = jspend(s->left, 1);
        s->md = s->dep ? MPOST : MDONE;
        return e;
      }
      s->md = MBAD;
      return e;
    }
    if (s->md == MKEY || s->md == MKEY0) {
      if (c == '"') {
        if (jstr(s->b, at, n, s->left, &i)) { s->at = i; s->md = MBAD; e.at = i; return e; }
        e.k = EKEY; e.at = at + 1; e.len = (i - at) - 2;
        s->left = jspend(s->left, i - at);
        u32 j = jws(s->b, i, n);
        if (jat(s->b, j, n) != 58) { s->at = j; s->md = MBAD; e.k = EBAD; e.at = j; return e; }
        s->at = j + 1;
        s->left = jspend(s->left, 1);
        s->md = MVAL;
        return e;
      }
      if (c == '}' && s->md == MKEY0 && s->ks[s->dep - 1]) {
        e.k = ECOBJ; s->dep--; s->at = at + 1; s->left = jspend(s->left, 1); s->md = s->dep ? MPOST : MDONE;
        return e;
      }
      s->md = MBAD;
      return e;
    }
    // a value, or the ] that shuts an array that never had one
    if (c == '{' || c == '[') {
      if (s->dep >= 256) { s->md = MBAD; return e; }
      s->ks[s->dep++] = c == '{';
      s->at = at + 1;
      s->left = jspend(s->left, 1);
      s->md = c == '{' ? MKEY0 : MVAL0;
      e.k = c == '{' ? EOBJ : EARR;
      return e;
    }
    if (c == ']' && s->md == MVAL0 && !s->ks[s->dep - 1]) {
      e.k = ECARR; s->dep--; s->at = at + 1; s->left = jspend(s->left, 1); s->md = s->dep ? MPOST : MDONE;
      return e;
    }
    if (c == '"' || c == '-' || (c >= 48 && c <= 57) || c == 't' || c == 'f' || c == 'n') {
      int bad, k;
      if (c == '"') { bad = jstr(s->b, at, n, s->left, &i); k = ESTR; }
      else if (c == 't') { bad = jlit(s->b, at + 1, n, "rue", &i); k = ETRU; }
      else if (c == 'f') { bad = jlit(s->b, at + 1, n, "alse", &i); k = EFAL; }
      else if (c == 'n') { bad = jlit(s->b, at + 1, n, "ull", &i); k = ENUL; }
      else { bad = jnum(s->b, at, n, s->left, &i); k = ENUM; }
      if (bad || s->left < i - at) { s->at = i; s->md = MBAD; e.at = i; return e; }
      e.k = k;
      if (k == ESTR) { e.at = at + 1; e.len = (i - at) - 2; }
      if (k == ENUM) { e.at = at; e.len = i - at; }
      s->left = jspend(s->left, i - at);
      s->at = i;
      s->md = s->dep ? MPOST : MDONE;
      return e;
    }
    s->md = MBAD;
    return e;
  }
}

// the rotate is not decoration: this event stream is 800 copies of one record,
// and a plain acc*31+x over it is a geometric series whose 2-adic valuation
// climbs -- the checksum arrived with 19 trailing zeros and the tree fold of
// 256 such blocks came out exactly 0. Feeding the high bits back kills it.
static u32 jmix(u32 acc, u32 x) { return rot(acc * 31 + x, 7); }
static u32 jscan(const unsigned char *doc, u32 n, u32 acc) {
  jst s = {doc, n, 0, 0, 4000000000u, MVAL, {0}};
  for (;;) {
    jev e = jnext(&s);
    acc = jmix(acc, (u32)e.k);
    if (e.k == EKEY || e.k == ESTR || e.k == ENUM) { acc = jmix(acc, e.at); acc = jmix(acc, e.len); }
    if (e.k == EBAD) acc = jmix(acc, e.at);
    if (e.k == EEOF || e.k == EBAD) return acc;
  }
}

// -- the bm25 twin: the same index power/bm25.bend builds, in plain C --------
// The corpus is generated from key() the same way the bench does, so the two
// hold the same pairs; the weights must match to the bit, so every float
// expression below is spelled in the order bm25.bend spells it.
static void bmsort(u32 n, u32 m, u32 *k, u32 *v, u32 *ok, u32 *ov) {
  u32 *c = calloc(m + 1, 4), s = 0;
  for (u32 i = 0; i < n; i++) c[k[i]]++;
  for (u32 j = 0; j < m; j++) { u32 t = c[j]; c[j] = s; s += t; }
  for (u32 i = 0; i < n; i++) { u32 p = c[k[i]]++; ok[p] = k[i]; ov[p] = v[i]; }
  free(c);
}

// nt terms, nd docs, occ occurrences from key(lo + i); qn queries of qt terms,
// the best k of each folded into the running checksum
static u32 bm25(u32 nt, u32 nd, u32 occ, u32 qn, u32 qt, u32 k, double k1, double bb, u32 lo) {
  u32 *ts = malloc(occ * 4), *ds = malloc(occ * 4);
  u32 *dl = calloc(nd, 4);
  for (u32 i = 0; i < occ; i++) {
    u32 a = key(lo + i), b = key(a);
    ts[i] = (a % nt) * (b % nt) / nt;
    ds[i] = key(b) % nd;
    dl[ds[i]]++;
  }
  // by document, then by term: the second pass is stable, so the documents stay
  // ascending inside every term
  u32 *sd = malloc(occ * 4), *st = malloc(occ * 4);
  bmsort(occ, nd, ds, ts, sd, st);
  bmsort(occ, nt, st, sd, ts, ds);  // ts := terms sorted, ds := their documents
  u32 *pd = malloc(occ * 4 + 4), *tf = malloc(occ * 4 + 4), *dfs = calloc(nt, 4), np = 0;
  if (occ) {
    u32 ck = ts[0], cd = ds[0], run = 1;
    for (u32 i = 1; i < occ; i++) {
      if (ts[i] == ck && ds[i] == cd) { run++; continue; }
      pd[np] = cd; tf[np] = run; dfs[ck]++; np++;
      ck = ts[i]; cd = ds[i]; run = 1;
    }
    pd[np] = cd; tf[np] = run; dfs[ck]++; np++;
  }
  u32 *ptr = malloc((nt + 1) * 4), s = 0;
  for (u32 t = 0; t < nt; t++) { ptr[t] = s; s += dfs[t]; }
  ptr[nt] = s;
  double avgdl = (double)occ / (double)nd;
  u32 *wgt = malloc(np * 4 + 4);
  for (u32 t = 0; t < nt; t++) {
    double df = (double)(ptr[t + 1] - ptr[t]);
    double id = log(1.0 + (((double)nd - df) + 0.5) / (df + 0.5));
    for (u32 i = ptr[t]; i < ptr[t + 1]; i++) {
      double tfi = (double)tf[i];
      double norm = k1 * ((1.0 - bb) + bb * ((double)dl[pd[i]] / avgdl));
      wgt[i] = (u32)(id * (tfi / (tfi + norm)) * 1048576.0 + 0.5);
    }
  }
  u32 *av = malloc(nd * 4), acc = 0;
  ent *h = malloc(k * sizeof(ent) + sizeof(ent)), *o = malloc(k * sizeof(ent) + sizeof(ent));
  for (u32 j = 0; j < qn; j++) {
    memset(av, 0, nd * 4);
    for (u32 m = 0; m < qt; m++) {
      u32 a = key(lo + 1073741824u + j * 8 + m), t = (a % nt) * (key(a) % nt) / nt;
      for (u32 i = ptr[t]; i < ptr[t + 1]; i++) {
        u32 d = pd[i];
        av[d] = (0xFFFFFFFFu - av[d] < wgt[i]) ? 0xFFFFFFFFu : av[d] + wgt[i];
      }
    }
    u32 n = 0;
    for (u32 d = 0; d < nd; d++) {
      if (!av[d]) continue;  // a document no query term touched is not a hit
      ent e = {av[d], d};
      if (n < k) up(h, n++, e);
      else if (less(h[0], e)) down(h, n, 0, e);
    }
    u32 n0 = n;
    for (u32 i = 0; i < n0; i++) o[i] = pop(h, &n);
    for (u32 i = n0; i-- > 0;) acc = acc * 31 + (o[i].k ^ o[i].x);
  }
  free(ts); free(ds); free(dl); free(sd); free(st);
  free(pd); free(tf); free(dfs); free(ptr); free(wgt); free(av); free(h); free(o);
  return acc;
}

int main(int argc, char **argv) {
  const char *b = argc > 1 ? argv[1] : "";
  u32 acc = 0;
  if (!strcmp(b, "rng")) {
    for (u32 i = 0; i < 204800000; i++) acc += threefry(1, 0, i, 0);
  } else if (!strcmp(b, "vec")) {
    vec v = {0};
    for (u32 i = 0; i < 64000000; i++) push(&v, key(i));
    for (int k = 0; k < 4; k++) for (u32 i = 0; i < v.n; i++) acc = acc * 31 + v.p[i];
  } else if (!strcmp(b, "bytes")) {
    unsigned char *p = 0; u32 n = 0, cap = 0;
    for (u32 i = 0; i < 64000000; i++) {
      if (n == cap) { cap = cap ? cap * 2 : 16; p = realloc(p, cap); }
      p[n++] = (unsigned char)key(i);
    }
    for (int k = 0; k < 4; k++) for (u32 i = 0; i < n; i++) acc = acc * 31 + p[i];
  } else if (!strcmp(b, "bitset")) {
    u32 W = 1u << 22, *a = calloc(W, 4);
    for (u32 i = 0; i < 16000000; i++) { u32 j = key(i) & 134217727; a[j >> 5] |= 1u << (j & 31); }
    for (u32 k = 80; k-- > 0;) {
      u32 *o = calloc(W, 4), j = key(k) & 134217727, n = 0;
      o[j >> 5] |= 1u << (j & 31);
      for (u32 i = 0; i < W; i++) a[i] ^= o[i];
      for (u32 i = 0; i < W; i++) n += __builtin_popcount(a[i]);
      free(o);
      acc = acc * 31 + n;
    }
  } else if (!strcmp(b, "heap")) {
    u32 N = 8000000, n = 0;
    ent *h = malloc(N * sizeof(ent)), *out = malloc(N * sizeof(ent));
    for (u32 i = 0; i < N; i++) { ent e = {key(i) & 1048575, i}; up(h, n++, e); }
    for (u32 i = 0; i < N; i++) out[i] = pop(h, &n);
    for (u32 i = N; i-- > 0;) acc = acc * 31 + (out[i].k ^ out[i].x);
  } else if (!strcmp(b, "topk")) {
    u32 K = 100, n = 0;
    ent h[100], out[100];
    for (u32 i = 0; i < 400000000; i++) {
      ent e = {key(i), i};
      if (n < K) up(h, n++, e);
      else if (less(h[0], e)) down(h, n, 0, e);
    }
    for (u32 i = 0; i < K; i++) out[i] = pop(h, &n);
    for (u32 i = K; i-- > 0;) acc = acc * 31 + (out[i].k ^ out[i].x);
  } else if (!strcmp(b, "scan")) {
    vec v = {0};
    for (u32 i = 0; i < 64000000; i++) push(&v, key(i));
    for (int k = 0; k < 20; k++) {
      u32 t = 0;
      for (u32 i = 0; i < v.n; i++) { t += v.p[i]; v.p[i] = t; }
      acc = acc * 31 + t;
    }
  } else if (!strcmp(b, "scan_par")) {
    u32 B = 250000, *v = malloc(B * 4), bs[256];
    for (u32 blk = 0; blk < 256; blk++) {
      u32 lo = blk * (64000000u >> 8), a = 0;
      for (u32 i = 0; i < B; i++) v[i] = key(lo + i);
      for (int k = 0; k < 20; k++) {
        u32 t = 0;
        for (u32 i = 0; i < B; i++) { t += v[i]; v[i] = t; }
        a = a * 31 + t;
      }
      bs[blk] = a;
    }
    // the same tree fold the fork does on the way up, not a left fold
    for (u32 w = 256; w > 1; w /= 2)
      for (u32 i = 0; i < w / 2; i++) bs[i] = bs[2 * i] * 31 + bs[2 * i + 1];
    acc = bs[0];
  } else if (!strcmp(b, "radix")) {
    u32 N = 8000000, *a = malloc(N * 4), *t = malloc(N * 4);
    for (u32 i = 0; i < N; i++) a[i] = key(i);
    for (int r = 0; r < 4; r++) {
      for (int s = 0; s < 32; s += 8) {  // four passes, so a ends up the sorted one
        u32 c[256] = {0}, o[256], sum = 0;
        for (u32 i = 0; i < N; i++) c[(a[i] >> s) & 255]++;
        for (int d = 0; d < 256; d++) { o[d] = sum; sum += c[d]; }
        for (u32 i = 0; i < N; i++) t[o[(a[i] >> s) & 255]++] = a[i];
        u32 *sw = a; a = t; t = sw;
      }
      for (u32 i = 0; i < N; i++) acc = acc * 31 + a[i];
    }
  } else if (!strcmp(b, "radix_par")) {
    u32 B = 31250, bs[256], *a0 = malloc(B * 4), *t0 = malloc(B * 4);
    for (u32 blk = 0; blk < 256; blk++) {
      u32 lo = blk * B, *a = a0, *t = t0, h = 0;
      for (u32 i = 0; i < B; i++) a[i] = key(lo + i);
      for (int r = 0; r < 4; r++) {
        for (int s = 0; s < 32; s += 8) {
          u32 c[256] = {0}, o[256], sum = 0;
          for (u32 i = 0; i < B; i++) c[(a[i] >> s) & 255]++;
          for (int d = 0; d < 256; d++) { o[d] = sum; sum += c[d]; }
          for (u32 i = 0; i < B; i++) t[o[(a[i] >> s) & 255]++] = a[i];
          u32 *sw = a; a = t; t = sw;
        }
        for (u32 i = 0; i < B; i++) h = h * 31 + a[i];
      }
      bs[blk] = h;
    }
    // the same tree fold the fork does on the way up, not a left fold
    for (u32 w = 256; w > 1; w /= 2)
      for (u32 i = 0; i < w / 2; i++) bs[i] = bs[2 * i] * 31 + bs[2 * i + 1];
    acc = bs[0];
  } else if (!strcmp(b, "json")) {
    u32 n;
    unsigned char *doc = jdoc(0, 200000, &n);
    for (int k = 0; k < 4; k++) acc = jscan(doc, n, acc);
  } else if (!strcmp(b, "json_par")) {
    u32 bs[256];
    for (u32 blk = 0; blk < 256; blk++) {
      u32 n, a = 0;
      // an odd stride: with 800 the true/null pattern repeats per block, every
      // block checksums the same, and the tree fold of 256 equal values is 0
      unsigned char *doc = jdoc(blk * 801, 800, &n);
      for (int k = 0; k < 4; k++) a = jscan(doc, n, a);
      free(doc);
      bs[blk] = a;
    }
    // the same tree fold the fork does on the way up, not a left fold
    for (u32 w = 256; w > 1; w /= 2)
      for (u32 i = 0; i < w / 2; i++) bs[i] = jmix(bs[2 * i], bs[2 * i + 1]);
    acc = bs[0];
  } else if (!strcmp(b, "bm25")) {
    acc = bm25(16384, 2048, 4000000, 250000, 8, 8, 1.2, 0.75, 0);
  } else if (!strcmp(b, "bm25_par")) {
    u32 bs[256];
    // a shard a leaf: the index holds arrays, and an array has one owner, so a
    // fork cannot share one -- each leaf indexes its own documents
    for (u32 blk = 0; blk < 256; blk++) bs[blk] = bm25(256, 256, 16384, 1000, 8, 8, 1.2, 0.75, blk * 16384);
    // the same tree fold the fork does on the way up, not a left fold, and
    // jmix's rotate: a leaf checksum is an acc * 31 + x fold, so every leaf is
    // congruent mod 32, and a plain a * 31 + b tree folds 256 of those to 0
    for (u32 w = 256; w > 1; w /= 2)
      for (u32 i = 0; i < w / 2; i++) bs[i] = jmix(bs[2 * i], bs[2 * i + 1]);
    acc = bs[0];
  } else { fprintf(stderr, "twins: unknown bench %s\n", b); return 2; }
  printf("%u\n", acc);
  return 0;
}
