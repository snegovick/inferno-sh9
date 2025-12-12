implement Sh9Parser;

include "sys.m";
include "sh9parser.m";
include "sh9util.m";

sys: Sys;
S_UNKNOWN: con "UNK";

sh9u: Sh9Util;

reverse_list: import sh9u;
to_array: import sh9u;

GrammarNode.print_expr(gn: self ref GrammarNode) {
  lg:= len gn.expr;
  for (i:=0; i<lg; i++) {
    sys->print("%s ", gn.expr[i]);
  }
  if (gn.transform == S_UNKNOWN) {
    sys->print("\n");
  } else {
    sys->print("-> %s\n", gn.transform);
  }
}

mk_tok(start: int, line: int, tok: string, typ: string) : TokNode {
  tok_node: TokNode;
  tok_node.start = start;
  tok_node.line = line;
  tok_node.tok = tok;
  tok_node.typ = typ;
  return tok_node;
}

set_last_tok(last_tok: ref TokNode, toks: list of ref TokNode): (TokNode, list of ref TokNode) {
  ret_tok: TokNode;
  ret_tok = *last_tok;
  if (last_tok.typ != S_UNKNOWN) {
    toks = last_tok :: toks;
    ret_tok.typ = S_UNKNOWN;
    ret_tok.start = -1;
    ret_tok.tok = "";
    ret_tok.line = -1;
  }
  return (ret_tok, toks);
}

print_toks(toks: array of ref TokNode) {
  lt := len toks;
  for (i := 0; i < lt; i ++) {
    tok := toks[i];
    sys->print("[%d/%d] %s (%s)\n", i, lt, tok.typ, tok.tok);
  }
}

print_toks_short(toks: array of ref TokNode) {
  lt := len toks;
  for (i := 0; i < lt; i ++) {
    tok := toks[i];
    sys->print("%s ", tok.typ);
  }
  sys->print("\n");
}

check_grammar_node_match(toks: array of ref TokNode, gn: ref GrammarNode): int {
  lt:= len toks;
  lg:= len gn.expr;
  if (lg > lt) {
    return 0;
  }
  #sys->print("Checking grammar ");
  gn.print_expr();
  #sys->print("Against ");
  print_toks(toks);
  for (i:= 0; i < lg; i ++) {
    if (toks[i].typ != gn.expr[i]) {
      return 0;
    }
  }
  return 1;
}

replace_toks(src: array of ref TokNode, replace_start: int, replace_len: int, replace_with: array of ref TokNode): array of ref TokNode {
  src_len:= len src;
  new_toks: list of ref TokNode;
  with_len:= len replace_with;
  for (i:=0; i<replace_start; i++) {
    new_toks = src[i] :: new_toks;
  }
  for (i=0; i<with_len; i++) {
    new_toks = replace_with[i] :: new_toks;
  }
  for (i=replace_start + replace_len; i<src_len; i++) {
    new_toks = src[i] :: new_toks;
  }
  new_toks = reverse_list(new_toks);
  return to_array(new_toks);
}

parse_toks(toks: array of ref TokNode, g: array of ref GrammarNode): array of ref TokNode {
  lgns := len g;
  changed := 0;
  ctr := 0;
  do
  {
    lt := len toks;
    sys->print("Loop %d: ", ctr);
    print_toks_short(toks);
    ctr ++;
    changed = 0;
    fast: for (i := 0; i <= lt; i ++) {
      for (j := 0; j < lgns; j++) {
        gj:= g[j];
        if (check_grammar_node_match(toks[lt - i:], gj) == 1) {
          sys->print("Something matched !\n");
          gj.print_expr();
          sys->print("Before replace: ");
          print_toks_short(toks);
          gj.callback(toks[lt-i: lt-i+len gj.expr]);
          toks = replace_toks(toks, lt-i, len gj.expr, array[] of {ref mk_tok(toks[lt - i].start, toks[lt - i].line, "", gj.transform)});
          sys->print("After replace: ");
          changed = 1;
          break fast;
        }
      }
    }
  } while(changed);
  return toks;
}
