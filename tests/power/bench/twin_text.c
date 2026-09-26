// twin of tests/power/bench/text.bend: the same 16,776,384-byte corpus built
// the same way -- one 48-byte unit repeated, not a data file -- segmented into
// extended grapheme clusters by the same UAX #29 rules, checksummed the same.
//
// The table below is power/text.bend's gtab() flattened out of its BST into the
// 54 sorted ranges it was built from, and gcb/gg/gnl/join/brk/flag are line for
// line the defs of the same name. The Bend side is the one under test; this
// file exists to say what the answer should have been.
#include <stdio.h>
#include <stdlib.h>

#define N 16776384u
#define UL 48u

static const unsigned char UNIT[UL] = {
  67, 97, 102, 195, 169, 32, 234, 176, 128, 225, 134, 168, 32, 240, 159, 135,
  186, 240, 159, 135, 184, 32, 101, 204, 129, 204, 163, 32, 240, 159, 145,
  168, 226, 128, 141, 240, 159, 145, 169, 32, 228, 184, 173, 230, 150, 135,
  13, 10
};

// 0 Other  1 CR  2 LF  3 Control  4 Extend  5 ZWJ  6 Regional_Indicator
// 7 Prepend  8 SpacingMark  9 L  10 V  11 T  12 LV  13 LVT  14 ExtPict
static const struct { unsigned lo, hi, k; } GR[] = {
  {0x0,0x9,3},      {0xA,0xA,2},      {0xB,0xC,3},      {0xD,0xD,1},
  {0xE,0x1F,3},     {0x7F,0x9F,3},    {0xA9,0xA9,14},   {0xAD,0xAD,3},
  {0xAE,0xAE,14},   {0x300,0x36F,4},  {0x600,0x605,7},  {0x6DD,0x6DD,7},
  {0x70F,0x70F,7},  {0x890,0x891,7},  {0x8E2,0x8E2,7},  {0x900,0x902,4},
  {0x903,0x903,8},  {0x93A,0x93A,4},  {0x93B,0x93B,8},  {0x93C,0x93C,4},
  {0x93E,0x940,8},  {0x941,0x948,4},  {0x949,0x94C,8},  {0x94D,0x94D,4},
  {0x94E,0x94F,8},  {0x951,0x957,4},  {0x962,0x963,4},  {0xD4E,0xD4E,7},
  {0x1100,0x115F,9},{0x1160,0x11A7,10},{0x11A8,0x11FF,11},{0x200B,0x200B,3},
  {0x200C,0x200C,4},{0x200D,0x200D,5},{0x2028,0x2029,3},{0x203C,0x203C,14},
  {0x2049,0x2049,14},{0x2600,0x27BF,14},{0x2B00,0x2BFF,14},{0xAC00,0xD7A3,12},
  {0xFE00,0xFE0F,4},{0xFEFF,0xFEFF,3},{0x1F000,0x1F0FF,14},{0x1F10D,0x1F1AD,14},
  {0x1F1E6,0x1F1FF,6},{0x1F200,0x1F2FF,14},{0x1F300,0x1F3FA,14},
  {0x1F3FB,0x1F3FF,4},{0x1F400,0x1F5FF,14},{0x1F600,0x1F64F,14},
  {0x1F680,0x1F6FF,14},{0x1F7E0,0x1F7EB,14},{0x1F900,0x1F9FF,14},
  {0x1FA70,0x1FAFF,14}
};
#define NGR (sizeof GR / sizeof GR[0])

// gtab() folds all 11,172 Hangul syllables into one LV row: LV and LVT differ
// by arithmetic, not by range, so the row is patched after the lookup
static unsigned gcb(unsigned cp) {
  int lo = 0, hi = (int)NGR - 1, k = 0;
  while (lo <= hi) {
    int m = (lo + hi) / 2;
    if (cp < GR[m].lo) hi = m - 1;
    else if (cp > GR[m].hi) lo = m + 1;
    else { k = (int)GR[m].k; break; }
  }
  if (k == 12) return ((cp - 44032u) % 28u == 0u) ? 12u : 13u;
  return (unsigned)k;
}

static unsigned gg(unsigned k) { return k == 14u ? 0u : k; }
static int gnl(unsigned k) { return k >= 1u && k <= 3u; }
static int in2(unsigned k, unsigned a, unsigned b) { return k == a || k == b; }

// GB6 through GB13, in order
static int joinr(unsigned p, unsigned k, unsigned raw, unsigned fl) {
  return in2(k, 4, 5) || k == 8u || p == 7u
    || (p == 9u && (in2(k, 9, 10) || in2(k, 12, 13)))
    || (in2(p, 12, 10) && in2(k, 10, 11))
    || (in2(p, 13, 11) && k == 11u)
    || ((fl & 1u) == 1u && raw == 14u)
    || (p == 6u && k == 6u && (fl & 4u) == 4u);
}

// GB3 keeps CR LF together, GB4 and GB5 break at every other control, and only
// then do the join rules get a say
static int brk(unsigned p, unsigned k, unsigned raw, unsigned fl) {
  return !((p == 1u && k == 2u)
    || (!(gnl(p) || gnl(k)) && joinr(p, k, raw, fl)));
}

// 1 the last was a ZWJ closing a pictographic run; 2 a pictographic run is
// live; 4 the regional indicators since the last break are odd
static unsigned flagof(unsigned raw, unsigned fl) {
  unsigned a = (raw == 5u && (fl & 2u) == 2u) ? 1u : 0u;
  unsigned b = (raw == 14u || ((fl & 2u) == 2u && raw == 4u)) ? 2u : 0u;
  unsigned c = (raw == 6u && (fl & 4u) == 0u) ? 4u : 0u;
  return a | b | c;
}

// the unchecked fold power/text.bend's decode() does, width and all
static unsigned dec(const unsigned char *b, unsigned i, unsigned *w) {
  unsigned c0 = b[i];
  if (c0 < 128u) { *w = 1u; return c0; }
  if (c0 < 224u) { *w = 2u; return ((c0 & 31u) << 6) | (b[i+1] & 63u); }
  if (c0 < 240u) {
    *w = 3u;
    return ((c0 & 15u) << 12) | ((b[i+1] & 63u) << 6) | (b[i+2] & 63u);
  }
  *w = 4u;
  return ((c0 & 7u) << 18) | ((b[i+1] & 63u) << 12)
    | ((b[i+2] & 63u) << 6) | (b[i+3] & 63u);
}

static unsigned hh(unsigned p) { return ((p + 1u) * 2654435761u) ^ (p >> 3); }
static unsigned rot7(unsigned v) { return (v << 7) | (v >> 25); }
static unsigned mix(unsigned a, unsigned x) { return rot7(a * 31u + x); }

// bytes [s, e) of the endless repetition of UNIT, into a caller's buffer
static void corpus(unsigned char *out, unsigned s, unsigned e) {
  unsigned j = s % UL;
  for (unsigned i = 0; i < e - s; i++) {
    out[i] = UNIT[j];
    j = (j + 1u == UL) ? 0u : j + 1u;
  }
}

// sum hh(offset) over the cluster starts in [lo, hi), and count them. The walk
// begins at `from`, which may be before lo: a leaf needs a run-up to know the
// state it is in, and the starts it finds there are not its to report.
void scan(const unsigned char *b, unsigned from, unsigned end,
          unsigned lo, unsigned hi, unsigned *sum, unsigned *cnt) {
  unsigned q = 255u, fl = 0u, i = from;
  while (i < end) {
    unsigned w, cp = dec(b, i - from, &w);
    unsigned raw = gcb(cp);
    if (q == 255u || brk(gg(q), gg(raw), raw, fl)) {
      if (i >= lo && i < hi) { *sum += hh(i); (*cnt)++; }
    }
    fl = flagof(raw, fl);
    q = raw;
    i += w;
  }
}

#ifndef TWIN_TEXT_NO_MAIN
int main(void) {
  unsigned char *b = malloc(N + 8u);
  if (!b) return 1;
  corpus(b, 0u, N);
  unsigned sum = 0u, cnt = 0u;
  scan(b, 0u, N, 0u, N, &sum, &cnt);
  free(b);
  printf("%u\n", mix(sum, cnt));
  return 0;
}
#endif
