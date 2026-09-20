# Experimental P3 candidate, deliberately outside the production import graph.
import Base
import ../../../demos/python/syntax.bend as S
import ../../../demos/python/scanner.bend as C
import ../../../demos/python/lexer.bend as L

type Patterns is Data:
  Patterns{names: Regex, integers: Regex}

type Cursor is Data:
  Cursor{line: Nat, col: Nat, tail: String}

def compile() -> Result<&2, &2, Regex.Error, Patterns>:
  do Result<&2, &2, Regex.Error, Patterns>:
    names : Regex <- Regex.compile("[A-Za-z_][A-Za-z_0-9]*", "")
    numbers : Regex <- Regex.compile("[1-9][0-9]*|0+", "")
    return Patterns{names, numbers}

# Prepare each physical line once; then drop only the newly consumed chars.
# The reference VM scans even a dead anchored suffix, so never pass the file.
# No anchors/boundaries in these patterns: rebasing to at=0 preserves meaning.
def new_cursor(scan: C.Scan, line: Nat, col: Nat) -> Cursor:
  C.Scan{raw, rest, end} = scan
  Cursor{line, col, raw}

def prepare(st: L.State, cursor: Cursor) -> Cursor:
  L.State{+rest, S.Pos{+line, +col}, levels, brackets, bol, logical, out, done} = st
  Cursor{oldline, oldcol, tail} = cursor
  S.choose(Cursor, Nat.is_eq(line, oldline), u =>
    Cursor{line, col, String.drop(tail, (col - oldcol : Nat))}, u =>
    new_cursor(C.span(rest, 2n, S.Pos{line, col}, ""), line, col))

def tail(c: Cursor) -> String:
  Cursor{line, col, text} = c
  text

def fallback(+s: String, +p: S.Pos, number: Bool) -> C.Scan:
  S.choose(C.Scan, number, u => C.number(s, 0n, p, "", C.Scan{"", s, p}), u => C.span(s, 0n, p, ""))

def recognized(m: Maybe<&2, Match>, +s: String, +p: S.Pos, +number: Bool) -> C.Scan:
  match m:
    case None{}:
      fallback(s, p, number)
    case Some{Match{start, +end, groups}}:
      +next = C.head(String.drop(s, end))
      # Unicode names and complex/malformed numeric suffixes use the DFA.
      S.choose(C.Scan, C.word(next) || (number && Char.is_eq(next, '.')), u =>
        fallback(s, p, number), u => C.take(s, end, p, ""))

def scan(re: Regex, cursor: String, s: String, p: S.Pos, number: Bool) -> C.Scan:
  recognized(Regex.match_at(re, cursor, 0n), s, p, number)

def step(patterns: Patterns, st: L.State, +text: String) -> Result<&2, &2, S.Error, L.State>:
  Patterns{names, integers} = patterns
  L.step_with(st, s => p => scan(names, text, s, p, False{}), s => p => scan(integers, text, s, p, True{}))

def go(fuel: Nat, +st: L.State, +patterns: Patterns, cursor: Cursor) -> Result<&2, &2, S.Error, List<&2, S.Tok>>:
  match fuel:
    case 0n:
      Fail{S.PErr{S.Limit{}, S.Pos{1n, 0n}, "lexer fuel"}}
    case 1n+left:
      S.choose(Result<&2, &2, S.Error, List<&2, S.Tok>>, L.finished(st), u => Done{L.tokens(st)}, u =>
        +prepared = prepare(st, cursor)
        +text = tail(prepared)
        do Result<&2, &2, S.Error, List<&2, S.Tok>>:
          next : L.State <- step(patterns, st, text)
          go(left, next, patterns, prepared))

def lex_with(+s: String, patterns: Patterns) -> Result<&2, &2, S.Error, List<&2, S.Tok>>:
  go((3n * (String.length(s) + 1n) : Nat), L.State{s, S.Pos{1n, 0n}, [L.Indent{0n, 0n}], [], True{}, False{}, [], False{}}, patterns, Cursor{0n, 0n, ""})

def compiled(s: String, result: Result<&2, &2, Regex.Error, Patterns>) -> Result<&2, &2, S.Error, List<&2, S.Tok>>:
  match result:
    case Done{patterns}:
      lex_with(s, patterns)
    case Fail{RErr{pos, msg}}:
      Fail{S.PErr{S.Syntax{}, S.Pos{1n, 0n}, msg}}

def lex(s: String) -> Result<&2, &2, S.Error, List<&2, S.Tok>>:
  compiled(s, compile())
