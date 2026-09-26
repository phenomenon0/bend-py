// The twin of bench/grammar.bend: the same 2,097,152 documents, the same mask
// derived at every one of the 85,983,692 positions, the same checksum.
//
// The transition table is transcribed from the grammar as C would write it --
// a switch over the node, the stack in one uint64_t -- and not from the Bend
// source line by line. The masks are the same 21 constants, because a constant
// is the one thing there is no second way to write.
#include <stdio.h>
#include <stdint.h>

enum {
  DEAD, VAL, VALE, KEYE, KEY, COLON, SEP, FIN, STR, ESC,
  U1, U2, U3, U4, MIN, ZERO, INT, DOT, FRAC, EXP, ESGN, EXPD,
  TR, TU, TE, FA, FL, FS, FE, NU, NL, NL2
};

typedef struct { uint32_t w[8]; } M;

static const M M_NONE = {{0, 0, 0, 0, 0, 0, 0, 0}};
static const M M_WS = {{9728, 1, 0, 0, 0, 0, 0, 0}};
static const M M_DIGIT = {{0, 67043328, 0, 0, 0, 0, 0, 0}};
static const M M_HEX = {{0, 67043328, 126, 126, 0, 0, 0, 0}};
static const M M_VSTART = {{0, 67051524, 134217728, 135282752, 0, 0, 0, 0}};
static const M M_ESCCH = {{0, 32772, 268435456, 3424324, 0, 0, 0, 0}};
static const M M_BODY = {{0, 4294967295u, 4294967295u, 4294967295u,
                          4294967295u, 4294967295u, 4294967295u, 4294967295u}};
static const M M_DOTE = {{0, 16384, 32, 32, 0, 0, 0, 0}};
static const M M_EONLY = {{0, 0, 32, 32, 0, 0, 0, 0}};
static const M M_SIGN = {{0, 10240, 0, 0, 0, 0, 0, 0}};
static const M M_COLON = {{0, 67108864, 0, 0, 0, 0, 0, 0}};
static const M M_COMMA = {{0, 4096, 0, 0, 0, 0, 0, 0}};
static const M M_RBRACE = {{0, 0, 0, 536870912, 0, 0, 0, 0}};
static const M M_RBRACK = {{0, 0, 536870912, 0, 0, 0, 0, 0}};
static const M M_QUOTE = {{0, 4, 0, 0, 0, 0, 0, 0}};
static const M M_A = {{0, 0, 0, 2, 0, 0, 0, 0}};
static const M M_E = {{0, 0, 0, 32, 0, 0, 0, 0}};
static const M M_L = {{0, 0, 0, 4096, 0, 0, 0, 0}};
static const M M_R = {{0, 0, 0, 262144, 0, 0, 0, 0}};
static const M M_S = {{0, 0, 0, 524288, 0, 0, 0, 0}};
static const M M_U = {{0, 0, 0, 2097152, 0, 0, 0, 0}};

static M mor(M a, M b) {
  for (int i = 0; i < 8; i++) a.w[i] |= b.w[i];
  return a;
}

typedef struct { uint8_t n; uint8_t d; uint8_t f; uint64_t k; } St;

static int has(M m, uint32_t c) { return (m.w[c >> 5] >> (c & 31)) & 1; }
static int is_ws(uint32_t c) { return has(M_WS, c); }
static int is_dig(uint32_t c) { return c >= 48 && c <= 57; }
static int top(St s) { return s.d && ((s.k >> (s.d - 1)) & 1); }

static St dead(void) { St s = {DEAD, 0, 0, 0}; return s; }
static St go(St s, int n) { s.n = (uint8_t)n; return s; }
// f is the one bit that says whether this string is a key, so its closing
// quote goes to a colon and not to a separator
static St gok(St s, int n, int f) { s.n = (uint8_t)n; s.f = (uint8_t)f; return s; }

// after: the byte that ends a value leaves it at the separator of its
// container, or at the end of the document
static St after(St s) { s.n = s.d ? SEP : FIN; s.f = 0; return s; }

static St push(St s, int n, int obj) {
  if (s.d >= 64) return dead();
  if (obj) s.k |= 1ull << s.d; else s.k &= ~(1ull << s.d);
  s.d++; s.n = (uint8_t)n;
  return s;
}

static St pop(St s) {
  s.d--;
  s.k &= s.d ? ((1ull << s.d) - 1) : 0;
  s.n = s.d ? SEP : FIN;
  s.f = 0;
  return s;
}

static St sh_val(St s, uint32_t c) {
  if (is_ws(c)) return s;
  if (c == 34) return gok(s, STR, 0);
  if (c == 45) return go(s, MIN);
  if (is_dig(c)) return go(s, c == 48 ? ZERO : INT);
  if (c == 116) return go(s, TR);
  if (c == 102) return go(s, FA);
  if (c == 110) return go(s, NU);
  if (c == 91) return push(s, VALE, 0);
  if (c == 123) return push(s, KEYE, 1);
  return dead();
}

static St sh_key(St s, uint32_t c) {
  if (is_ws(c)) return s;
  return c == 34 ? gok(s, STR, 1) : dead();
}

static St lit(St s, uint32_t c, uint32_t want, int nxt) {
  if (c != want) return dead();
  return nxt < 0 ? after(s) : go(s, nxt);
}

static St shift(St s, uint32_t c) {
  switch (s.n) {
    case VAL: return sh_val(s, c);
    case VALE: return c == 93 ? pop(s) : sh_val(s, c);
    case KEYE: return c == 125 ? pop(s) : sh_key(s, c);
    case KEY: return sh_key(s, c);
    case COLON: return is_ws(c) ? s : (c == 58 ? go(s, VAL) : dead());
    case SEP:
      if (is_ws(c)) return s;
      if (c == 44) return go(s, top(s) ? KEY : VAL);
      return c == (uint32_t)(top(s) ? 125 : 93) ? pop(s) : dead();
    case FIN: return is_ws(c) ? s : dead();
    case STR:
      if (c == 34) return s.f ? gok(s, COLON, 0) : after(s);
      if (c == 92) return go(s, ESC);
      return c < 32 ? dead() : s;
    case ESC:
      if (!has(M_ESCCH, c)) return dead();
      return go(s, c == 117 ? U1 : STR);
    case U1: return has(M_HEX, c) ? go(s, U2) : dead();
    case U2: return has(M_HEX, c) ? go(s, U3) : dead();
    case U3: return has(M_HEX, c) ? go(s, U4) : dead();
    case U4: return has(M_HEX, c) ? go(s, STR) : dead();
    case MIN:
      if (c == 48) return go(s, ZERO);
      return is_dig(c) ? go(s, INT) : dead();
    case ZERO:
      if (c == 46) return go(s, DOT);
      return has(M_EONLY, c) ? go(s, EXP) : dead();
    case INT:
      if (is_dig(c)) return s;
      if (c == 46) return go(s, DOT);
      return has(M_EONLY, c) ? go(s, EXP) : dead();
    case DOT: return is_dig(c) ? go(s, FRAC) : dead();
    case FRAC:
      if (is_dig(c)) return s;
      return has(M_EONLY, c) ? go(s, EXP) : dead();
    case EXP:
      if (has(M_SIGN, c)) return go(s, ESGN);
      return is_dig(c) ? go(s, EXPD) : dead();
    case ESGN: return is_dig(c) ? go(s, EXPD) : dead();
    case EXPD: return is_dig(c) ? s : dead();
    case TR: return lit(s, c, 114, TU);
    case TU: return lit(s, c, 117, TE);
    case TE: return lit(s, c, 101, -1);
    case FA: return lit(s, c, 97, FL);
    case FL: return lit(s, c, 108, FS);
    case FS: return lit(s, c, 115, FE);
    case FE: return lit(s, c, 101, -1);
    case NU: return lit(s, c, 117, NL);
    case NL: return lit(s, c, 108, NL2);
    case NL2: return lit(s, c, 108, -1);
    default: return dead();
  }
}

// a number has no closing byte, so it ends at the first byte that cannot
// continue it and that byte is then the separator
static int cont(int n, uint32_t c) {
  switch (n) {
    case ZERO: return has(M_DOTE, c);
    case INT: return is_dig(c) || has(M_DOTE, c);
    case FRAC: return is_dig(c) || has(M_EONLY, c);
    case EXPD: return is_dig(c);
    default: return 1;
  }
}

static St step(St s, uint32_t c) {
  return shift(cont(s.n, c) ? s : after(s), c);
}

static M mask_sep(int obj) { return mor(M_COMMA, obj ? M_RBRACE : M_RBRACK); }
static M mask_after(St s) { return s.d ? mor(M_WS, mask_sep(top(s))) : M_WS; }

static M mask(St s) {
  switch (s.n) {
    case VAL: return mor(M_WS, M_VSTART);
    case VALE: return mor(M_WS, mor(M_VSTART, M_RBRACK));
    case KEYE: return mor(M_WS, mor(M_QUOTE, M_RBRACE));
    case KEY: return mor(M_WS, M_QUOTE);
    case COLON: return mor(M_WS, M_COLON);
    case SEP: return mor(M_WS, s.d ? mask_sep(top(s)) : M_NONE);
    case FIN: return M_WS;
    case STR: return M_BODY;
    case ESC: return M_ESCCH;
    case U1: case U2: case U3: case U4: return M_HEX;
    case MIN: return M_DIGIT;
    case ZERO: return mor(M_DOTE, mask_after(s));
    case INT: return mor(M_DIGIT, mor(M_DOTE, mask_after(s)));
    case DOT: return M_DIGIT;
    case FRAC: return mor(M_DIGIT, mor(M_EONLY, mask_after(s)));
    case EXP: return mor(M_DIGIT, M_SIGN);
    case ESGN: return M_DIGIT;
    case EXPD: return mor(M_DIGIT, mask_after(s));
    case TR: return M_R;
    case TU: case NU: return M_U;
    case TE: case FE: return M_E;
    case FA: return M_A;
    case FL: case FS: return (s.n == FL) ? M_L : M_S;
    case NL: case NL2: return M_L;
    default: return M_NONE;
  }
}

static uint32_t hsh(uint32_t acc, uint32_t x) {
  return (acc ^ x) * 16777619u;
}

static uint32_t fold1(uint32_t acc, uint32_t d, M m) {
  return hsh(acc, (m.w[0] ^ m.w[1]) ^ (m.w[2] ^ m.w[3]) ^
                      ((m.w[4] ^ m.w[5]) ^ (m.w[6] ^ (m.w[7] + d))));
}

static uint32_t byte_at(uint32_t i, uint32_t d, uint32_t w, uint32_t o) {
  if (i < d) return 91;
  if (i >= d + w) return 93;
  uint32_t j = i - d;
  return (j & 1) ? 44 : 48 + (((j >> 1) + o) & 7);
}

static uint32_t one(uint32_t acc, uint32_t d, uint32_t w, uint32_t o) {
  St s = {VAL, 0, 0, 0};
  uint32_t n = d + d + w;
  for (uint32_t i = 0; i < n; i++) {
    acc = fold1(acc, s.d, mask(s));
    s = step(s, byte_at(i, d, w, o));
  }
  int done = s.d == 0 && (s.n == FIN || s.n == ZERO || s.n == INT ||
                          s.n == FRAC || s.n == EXPD);
  return hsh(acc, (uint32_t)(done * 2 + (s.n != DEAD)));
}

// twin_grammar_par.c includes this file for the machine above rather than
// keeping a second copy of a 32-state table that would then have two places to
// drift. Its own main is the only thing it needs to write.
// the shape of document o, drawn from the high bits of a hash of o so that
// every bit of o reaches it -- multiplication carries upwards only
static uint32_t one_o(uint32_t acc, uint32_t o) {
  uint32_t x = (o ^ (o >> 15)) * 2654435761u;
  return one(acc, 1 + ((x >> 29) & 7), 2 * (1 + ((x >> 24) & 31)) - 1, o);
}

#ifndef TWIN_GRAMMAR_NO_MAIN
int main(void) {
  uint32_t acc = 0;
  for (uint32_t o = 0; o < 2097152u; o++) acc = one_o(acc, o);
  printf("%u\n", acc);
  return 0;
}
#endif
