implement Sh9Util;

include "sh9util.m";
include "sys.m";

reverse_list[T](toks: list of T): list of T
{
  lt := len toks;
  out : list of T;
  for (i := 0; i < lt; i ++) {
    tok := hd toks;
    toks = tl toks;
    out = tok :: out;
  }
  return out;
}

to_array[T](toks: list of T): array of T {
  lt := len toks;
  out := array[lt] of T;
  for (i := 0; i < lt; i ++) {
    tok := hd toks;
    toks = tl toks;
    out[i] = tok;
  }
  return out;
}
