Sh9Parser: module
{
PATH: con "/dis/lib/sh9parser.dis";
DESCR: con "Mostly generic parser for sh9";

mk_tok: fn(start: int, line: int, tok: string, typ: string) : ref TokNode;
set_last_tok: fn(last_tok: ref TokNode, toks: list of ref TokNode): (ref TokNode, list of ref TokNode);
print_toks: fn(toks: array of ref TokNode);
print_toks_short: fn(toks: array of ref TokNode);
check_grammar_node_match: fn(toks: array of ref TokNode, gn: ref GrammarNode): int;
replace_toks: fn(src: array of ref TokNode, replace_start: int, replace_len: int, replace_with: array of ref TokNode): array of ref TokNode;
parse_toks: fn(toks: array of ref TokNode, g: array of ref GrammarNode, debug_printing: int): array of ref TokNode;
init:	fn();

TokNode: adt {
  start: int;
  line: int;
  tok: string;
  typ: string;
  retcode: int;
};

ModProc: adt {
  name: string;
  start: int;
};

ModVar: adt {
  name: string;
  val: string;
};

ShModule: adt {
  name: string;
  vars: list of ref ModVar;
  procs: list of ref ModProc;
  find_var: fn(m: self ref ShModule, name: string): ref ModVar;
  set_var: fn(m: self ref ShModule, v: ref ModVar);
  print_vars: fn(m: self ref ShModule);
};

ParserCtx: adt {
  modules: list of ref ShModule;
  add_module: fn(ctx: self ref ParserCtx, name: string);
  current_module: string;
  get_current_module: fn(ctx: self ref ParserCtx): ref ShModule;
  find_var_in_current_module: fn(ctx: self ref ParserCtx, name: string): ref ModVar;
  find_module: fn(ctx: self ref ParserCtx, name: string): ref ShModule;
  print_all_vars: fn(ctx: self ref ParserCtx);
  ctxt: ref Draw->Context;
};

GrammarNode: adt {
  expr: array of string;
  transform: string;

  callback: ref fn(ctx: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode;
  ctx: ref ParserCtx;
  print_expr: fn(gn: self ref GrammarNode);
};
};
