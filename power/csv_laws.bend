# The laws of power/csv.bend. They are stated here and proved in
# csv_proof.bend; `bun bend2/main.ts power/csv_proof.bend` is the gate,
# and prints "All terms check." only when every one of them holds.
#
# Three things a streaming reader of a byte-at-a-time grammar has to
# get right, and the one thing a writer has to:
#   the reads    -- however the input is cut into reads, the parse is
#                   the same (feed_split, feed_buf_split), and the walk
#                   that cuts runs from a read is the byte machine
#                   (feed_buf_is_feed); these, and bad_feeds, are the
#                   reader kit's laws (wire/reader.bend) at Csv.step;
#   the grammar  -- for every dialect and every input the reader agrees
#                   with csv_spec.bend, the whole-input reading of RFC
#                   4180's ABNF (csv_sim), over one read and over any
#                   split into reads (csv_sim_buf, csv_sim_reads);
#   the refusal  -- a refused document stays refused (bad_feeds);
#   the writer   -- what show writes reads back as the records it was
#                   given, for every list of records a sane dialect can
#                   carry (round_trip), and the reference accepts it
#                   (show_valid).
import Base
import ../wire/reader.bend as Wr
import ./csv.bend as Csv
import ./csv_spec.bend as Spec

# The reads
# =========

# LAW: chunking does not change the parse. Feeding a read and then the
# next lands exactly where feeding the two joined would have: a quoted
# field cut anywhere, a CRLF cut between its CR and its LF, a doubled
# quote cut between its quotes all read as the document whole.
law feed_split:
  for +d: Csv.Dialect
  for +a: List<&2, U32>
  for +b: List<&2, U32>
  for +p: Csv.P
  {Csv.feed(d, List.append(&2, U32, a, b), p) == Csv.feed(d, b, Csv.feed(d, a, p)) : Csv.P}

# LAW: a refusal is terminal. No byte moves the reader out of Bad, so
# nothing after a refused byte can revive the document.
law bad_feeds:
  for +d: Csv.Dialect
  for +s: List<&2, U32>
  for +at: Nat
  for +why: Csv.Why
  for +fl: Nat
  for +cur: List<&2, Bytes()>
  for +out: List<&2, List<&2, Bytes()>>
  for +w: Maybe<&2, Nat>
  for +pos: Nat
  {Csv.feed(d, s, Csv.P{Csv.Bad{at, why}, fl, cur, out, w, pos}) ==
    Csv.P{Csv.Bad{at, why}, fl, cur, out, w, pos} : Csv.P}

# LAW: the walk the reader runs is the byte machine. feed_buf takes a
# read as one packed block and cuts whole runs out of it -- an unquoted
# field, the text between quotes -- where feed steps a byte at a time;
# for every dialect, every block and every reader state the two land in
# the same place. So every law of feed is a law of feed_buf.
law feed_buf_is_feed:
  for +d: Csv.Dialect
  for +b: Bytes()
  for +p: Csv.P
  {Csv.feed_buf(d, b, p) == Csv.feed(d, Bytes.to_list(b), p) : Csv.P}

# LAW: and chunking does not change the parse on blocks either.
law feed_buf_split:
  for +d: Csv.Dialect
  for +a: Bytes()
  for +b: Bytes()
  for +p: Csv.P
  {Csv.feed_buf(d, Bytes.append(a, b), p) == Csv.feed_buf(d, b, Csv.feed_buf(d, a, p)) : Csv.P}

# The grammar
# ===========

# LAW: the reader is the grammar. For every dialect and every input, a
# fresh reader fed the input and then its end reads exactly what
# csv_spec.bend's whole-input reading of RFC 4180 reads: the same header
# and records, field for field and byte for byte, or a refusal at the
# same offset for the same reason.
law csv_sim:
  for +d: Csv.Dialect
  for +bs: List<&2, U32>
  {Csv.result(d, Csv.finish(d, Csv.feed(d, bs, Csv.new(d)))) == Spec.parse(bs, d) : Csv.Out}

# LAW: the same for a document read in one block ...
law csv_sim_buf:
  for +d: Csv.Dialect
  for +b: Bytes()
  {Csv.read(d, b) == Spec.parse(Bytes.to_list(b), d) : Csv.Out}

# ... and for a document however its reads were cut: the reader fed
# each read in turn reads what the grammar reads of them all, joined.
# (the reader kit's walk over a list of reads, wire/reader.bend)
def reads(+d: Csv.Dialect, rs: List<&2, Bytes()>, p: Csv.P) -> Csv.P:
  Wr.reads(~Csv.Dialect, ~Csv.P, ~Csv.wstep, ~Csv.wadv, d, rs, p)

law csv_sim_reads:
  for +d: Csv.Dialect
  for +rs: List<&2, Bytes()>
  {Csv.result(d, Csv.finish(d, reads(d, rs, Csv.new(d)))) ==
    Spec.parse(Bytes.to_list(Bytes.concat(rs)), d) : Csv.Out}

# The writer
# ==========

# LAW: what show writes reads back as the records it was given, for
# every list of records a sane dialect can carry (Csv.fits): every field
# byte for byte -- the ones with a quote, a delimiter, a CR or an LF in
# them too, and the empty ones -- and the first as the header when the
# dialect has one.
law round_trip:
  for +d: Csv.Dialect
  for +rs: List<&2, List<&2, Bytes()>>
  for ok: {Csv.fits(d, rs) == True{} : Bool}
  {Csv.read(d, Csv.show(d, rs)) == Csv.table(d, rs) : Csv.Out}

# LAW: and what show writes is RFC 4180 as csv_spec.bend reads it: the
# reference accepts it, and reads the same records.
law show_valid:
  for +d: Csv.Dialect
  for +rs: List<&2, List<&2, Bytes()>>
  for ok: {Csv.fits(d, rs) == True{} : Bool}
  {Spec.parse(Bytes.to_list(Csv.show(d, rs)), d) == Csv.table(d, rs) : Csv.Out}
