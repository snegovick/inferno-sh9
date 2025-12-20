implement Sh9Parser;

include "sys.m";
include "draw.m";
include "sh9parser.m";
include "sh9util.m";

sys: Sys;
S_UNKNOWN: con "UNK";
S_NONE: con "NONE";

sh9u: Sh9Util;

reverse_list: import sh9u;
to_array: import sh9u;

GrammarNode.print_expr(gn: self ref GrammarNode)
{
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

ShModule.find_var(m: self ref ShModule, name: string): ref ModVar
{
  l:= len m.vars;
  vars := m.vars;
  for (i:=0; i<l; i++) {
    v := hd vars;
    if (v.name == name) {
      return v;
    }
    vars = tl vars;
  }
  return nil;
}

ShModule.print_vars(m: self ref ShModule)
{
  l:= len m.vars;
  vars := m.vars;
  for (i:=0; i<l; i++) {
    v := hd vars;
    sys->print("%s: %s\n", v.name, v.val);
    vars = tl vars;
  }
}

ShModule.set_var(m: self ref ShModule, v: ref ModVar)
{
  m.vars = v :: m.vars;
}

ParserCtx.add_module(ctx: self ref ParserCtx, name: string)
{
  m:= ref ShModule;
  m.name = name;
  if (ctx.current_module == nil) {
    sys->print("Set current module %s\n", name);
    ctx.current_module = name;
  }
  ctx.modules = m :: ctx.modules;
}

ParserCtx.find_module(ctx: self ref ParserCtx, name: string): ref ShModule
{
  l:= len ctx.modules;
  mods := ctx.modules;
  for (i:=0; i<l; i++) {
    m := hd mods;
    if (m.name == name) {
      return m;
    }
    mods = tl mods;
  }
  return nil;
}

ParserCtx.find_var_in_current_module(ctx: self ref ParserCtx, name: string): ref ModVar
{
  m := ctx.find_module(ctx.current_module);
  if (m == nil) {
    return nil;
  }
  return m.find_var(name);
}

ParserCtx.print_all_vars(ctx: self ref ParserCtx)
{
  l:= len ctx.modules;
  mods := ctx.modules;
  for (i:=0; i<l; i++) {
    m := hd mods;
    m.print_vars();
    mods = tl mods;
  }
}

ParserCtx.get_current_module(ctx: self ref ParserCtx): ref ShModule
{
  m := ctx.find_module(ctx.current_module);
  return m;
}

init()
{
	sys = load Sys Sys->PATH;
  sh9u = load Sh9Util Sh9Util->PATH;
}

mk_tok(start: int, line: int, tok: string, typ: string) : ref TokNode
{
  tok_node: TokNode;
  tok_node.start = start;
  tok_node.line = line;
  tok_node.tok = tok;
  tok_node.typ = typ;
  return ref tok_node;
}

set_last_tok(last_tok: ref TokNode, toks: list of ref TokNode): (ref TokNode, list of ref TokNode) {
  #sys->print("last_tok: %s\n", last_tok.typ);
  ret_tok: TokNode;
  #ret_tok = *last_tok;
  ret_tok.typ = last_tok.typ;
  ret_tok.start = last_tok.start;
  ret_tok.tok = last_tok.tok;
  ret_tok.line = last_tok.line;
  if (last_tok.typ != S_UNKNOWN) {
    toks = last_tok :: toks;
    ret_tok.typ = S_UNKNOWN;
    ret_tok.start = -1;
    ret_tok.tok = "";
    ret_tok.line = -1;
  }
  #sys->print("ret_tok: %s\n", ret_tok.typ);
  return (ref ret_tok, toks);
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
  #gn.print_expr();
  #sys->print("Against ");
  #print_toks(toks);
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

parse_toks(toks: array of ref TokNode, g: array of ref GrammarNode, debug_printing: int): array of ref TokNode {
  lgns := len g;
  changed := 0;
  ctr := 0;
  do
  {
    lt := len toks;
    if (debug_printing) {
      sys->print("Loop %d: ", ctr);
    }
    print_toks_short(toks);
    ctr ++;
    changed = 0;
    fast: for (i := 0; i < lt; i ++) {
      for (j := 0; j < lgns; j++) {
        gj:= g[j];
        if (check_grammar_node_match(toks[i:], gj) == 1) {
          if (debug_printing) {
            sys->print("Something matched !\n");
            gj.print_expr();
            sys->print("Before replace: ");
            print_toks_short(toks);
          }

          if ((i+len gj.expr) > lt) {
            continue;
          }
          if (debug_printing) {
            sys->print("len toks: %d, i: %d, len gj.expr: %d\n", len toks, i, len gj.expr);
          }
          result := gj.callback(gj.ctx, toks[i:i+len gj.expr]);
          if (gj.transform == S_NONE) {
            toks = replace_toks(toks, i, len gj.expr, array[0] of ref TokNode);
          } else if (gj.transform == nil) {
            toks = replace_toks(toks, i, len gj.expr, result);
          } else {
            toks = replace_toks(toks, i, len gj.expr, array[] of {mk_tok(toks[i].start, toks[i].line, "", gj.transform)});
          }
          if (debug_printing) {
            sys->print("After replace: ");
          }
          changed = 1;
          break fast;
        }
      }
    }
  } while(changed);
  return toks;
}
