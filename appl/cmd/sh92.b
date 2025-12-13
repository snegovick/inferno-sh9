implement Sh92;

include "sys.m";
include "draw.m";
include "sh9util.m";
include "sh9parser.m";

sys: Sys;
sh9u: Sh9Util;
sh9p: Sh9Parser;

Sh92: module {
  init: fn(nil: ref Draw->Context, nil: list of string);
};

GrammarNode: import sh9p;
ModProc: import sh9p;
ModVar: import sh9p;
ShModule: import sh9p;
ParserCtx: import sh9p;
TokNode: import sh9p;
mk_tok: import sh9p;
set_last_tok: import sh9p;
print_toks: import sh9p;
parse_toks: import sh9p;

reverse_list: import sh9u;
to_array: import sh9u;

S_UNKNOWN: con "UNK";
S_NONE: con "NONE";
S_ID: con "ID";
S_STR: con "STR";
S_EQ: con "EQ";
S_COLON: con "COLON";
S_SEMIC: con "SEMIC";
S_LPAR: con "LPAR";
S_RPAR: con "RPAR";
S_LCURLY: con "LCURLY";
S_RCURLY: con "RCURLY";
S_DQSTR: con "DQSTR";
S_SQSTR: con "SQSTR";
S_DQTE: con "DQTE";
S_SQTE: con "SQTE";
S_SP: con "SP";
S_TAB: con "TAB";
S_DOLL: con "DOLL";
S_EOL: con "EOL";

S_STMT: con "STMT";
S_EXPR: con "EXPR";
S_CALL: con "CALL";

tokenize(line: string, line_n: int): array of ref TokNode {
  toks : list of ref TokNode;
  last_tok:= ref TokNode;
  last_tok.start = -1;
  last_tok.line = -1;
  last_tok.tok = "";
  last_tok.typ = S_UNKNOWN;
  k:=0;

  for (i := 0; i < len line; i++) {
    if (last_tok.typ == S_DQSTR) {
      case (line[i:i+1]) {
        "\"" => {
          l := len last_tok.tok;
          if ((last_tok.tok[l-1:] != "\\") || ((last_tok.tok[l-1:] == "\\") && (last_tok.tok[l-2:l-1] == "\\"))) {
            # end of str
            last_tok.tok = last_tok.tok + line[i:i+1];
            (last_tok, toks) = set_last_tok(last_tok, toks);
          } else {
            # escaped dqte, just continue
            last_tok.tok = last_tok.tok + line[i:i+1];
          }
        };
        * => {
          last_tok.tok = last_tok.tok + line[i:i+1];
        }
      }
    } else if (last_tok.typ == S_SQSTR) {
      case (line[i:i+1]) {
        "'" => {
          l := len last_tok.tok;
          if ((last_tok.tok[l-1:] != "\\") || ((last_tok.tok[l-1:] == "\\") && (last_tok.tok[l-2:l-1] == "\\"))) {
            # end of str
            last_tok.tok = last_tok.tok + line[i:i+1];
            (last_tok, toks) = set_last_tok(last_tok, toks);
          } else {
            # escaped sqte, just continue
            last_tok.tok = last_tok.tok + line[i:i+1];
          }
        };
        * => {
          last_tok.tok = last_tok.tok + line[i:i+1];
        }
      }
    } else {
      case (line[i:i+1]) {
        " " or "\t" => {
          (last_tok, toks) = set_last_tok(last_tok, toks);
        };
        "=" => {
          (last_tok, toks) = set_last_tok(last_tok, toks);
          toks = mk_tok(i, line_n, "=", S_EQ) :: toks;
        };
        ";" => {
          (last_tok, toks) = set_last_tok(last_tok, toks);
          toks = mk_tok(i, line_n, ";", S_SEMIC) :: toks;
        };
        ":" => {
          (last_tok, toks) = set_last_tok(last_tok, toks);
          toks = mk_tok(i, line_n, ":", S_COLON) :: toks;
        };
        "(" => {
          (last_tok, toks) = set_last_tok(last_tok, toks);
          toks = mk_tok(i, line_n, "(", S_LPAR) :: toks;
        };
        ")" => {
          (last_tok, toks) = set_last_tok(last_tok, toks);
          toks = mk_tok(i, line_n, ")", S_RPAR) :: toks;
        };
        "{" => {
          (last_tok, toks) = set_last_tok(last_tok, toks);
          toks = mk_tok(i, line_n, "{", S_LCURLY) :: toks;
          };
          "}" => {
            (last_tok, toks) = set_last_tok(last_tok, toks);
            toks = mk_tok(i, line_n, "}", S_RCURLY) :: toks;
          };
          "$" => {
            (last_tok, toks) = set_last_tok(last_tok, toks);
            toks = mk_tok(i, line_n, "$", S_DOLL) :: toks;
          };
          "\"" => {
            (last_tok, toks) = set_last_tok(last_tok, toks);
            last_tok.start = i;
            last_tok.line = line_n;
            last_tok.typ = S_DQSTR;
            last_tok.tok = last_tok.tok + line[i:i+1];
          };
          "'" => {
            (last_tok, toks) = set_last_tok(last_tok, toks);
            last_tok.start = i;
            last_tok.line = line_n;
            last_tok.typ = S_SQSTR;
            last_tok.tok = last_tok.tok + line[i:i+1];
          };
          * => {
            if (last_tok.start == -1) {
              last_tok.start = i;
              last_tok.line = line_n;
              last_tok.typ = S_ID;
            }
            last_tok.tok = last_tok.tok + line[i:i+1];
        };
      }
    }
  }
  (last_tok, toks) = set_last_tok(last_tok, toks);
  toks = mk_tok(i, line_n, "", S_EOL) :: toks;
  toks = reverse_list(toks);
  return to_array(toks);
}

stmt_assign(c: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode {
  sys->print("ASSIGN STMT\n");
  m:= c.get_current_module();
  v:= ref ModVar;
  v.name= toks[0].tok;
  v.val= toks[2].tok;
  m.set_var(v);
  return array[0] of ref TokNode;
}

stmt_cmd_call(c: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode {
  sys->print("CMD CALL\n");
  return array[0] of ref TokNode;
}

sqstr_to_expr(c: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode {
  tn:= mk_tok(toks[0].start, toks[0].line, toks[0].tok, S_EXPR);
  return array[1] of {tn};
}

empty(c: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode {
  return array[0] of ref TokNode;
}

var_sub_expr(c: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode {
  sys->print("VAR SUB\n");
  varname:=toks[1].tok;
  if (varname == "{") {
    varname = toks[2].tok;
  }
  v:= c.find_var_in_current_module(varname);
  if (v == nil) {
    sys->print("Var %s is nil\nAll vars:\n", varname);
    c.print_all_vars();
  }
  sys->print("VAR %s SUB: %s\n", v.name, v.val);
  tn:= mk_tok(toks[0].start, toks[0].line, v.val, S_EXPR);
  return array[1] of {tn};
}

expr_expr_combiner(c: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode {
  comb_tok:= toks[0].tok + " " + toks[1].tok;
  tn:= mk_tok(toks[0].start, toks[0].line, comb_tok, S_EXPR);
  return array[1] of {tn};
}

mk_grammar(ctx: ref ParserCtx): array of ref GrammarNode
{
  semic_eol_g :      GrammarNode = (array [] of {S_SEMIC, S_EOL}, S_EOL, empty, ctx);
  assign_g_semic :   GrammarNode = (array [] of {S_ID, S_EQ, S_EXPR, S_SEMIC}, S_NONE, stmt_assign, ctx);
  assign_g_eol :     GrammarNode = (array [] of {S_ID, S_EQ, S_EXPR, S_EOL}, S_NONE, stmt_assign, ctx);
  sqstr_expr_g:      GrammarNode = (array [] of {S_SQSTR}, nil, sqstr_to_expr, ctx);
  str_expr_g:        GrammarNode = (array [] of {S_STR}, S_EXPR, empty, ctx);
  expr_combinator_g: GrammarNode = (array [] of {S_EXPR, S_EXPR}, nil, expr_expr_combiner, ctx);
  cmd_call_semic_g:  GrammarNode = (array [] of {S_ID, S_EXPR, S_SEMIC}, nil, stmt_cmd_call, ctx);
  cmd_call_eol_g:    GrammarNode = (array [] of {S_ID, S_EXPR, S_EOL}, nil, stmt_cmd_call, ctx);

  var_sub_g:         GrammarNode = (array [] of {S_DOLL, S_ID}, nil, var_sub_expr, ctx);
  var_sub_curl_g:    GrammarNode = (array [] of {S_DOLL, S_LCURLY, S_ID, S_RCURLY}, nil, var_sub_expr, ctx);
  dqstr_expr_g:      GrammarNode = (array [] of {S_DQTE, S_EXPR, S_DQTE}, nil, empty, ctx);

  grammar: array of ref GrammarNode;
  grammar = array [] of {
    ref semic_eol_g,
    ref assign_g_semic,
    ref assign_g_eol,
    ref sqstr_expr_g,
    ref str_expr_g,
    ref cmd_call_semic_g,
    ref cmd_call_eol_g,
    ref expr_combinator_g,
    ref var_sub_g,
    ref var_sub_curl_g,
  };
  return grammar;
}

init(ctxt: ref Draw->Context, argv: list of string) {
  sys = load Sys Sys->PATH;
  sh9u = load Sh9Util Sh9Util->PATH;
  sh9p = load Sh9Parser Sh9Parser->PATH;
  sh9p->init();

  pctx:= ref ParserCtx;
  pctx.add_module("shell");

  toks1 := tokenize("AB = 'smth \"test\"  '; echo ${AB}; echo $AB", 0);
  #print_toks(toks1);
  #sys->print("Parse\n");
  grammar:= mk_grammar(pctx);
  parse_toks(toks1, grammar);
  #sys->print("Parse done\n");

  # toks2 := tokenize("echo \"smth \" \"test\";", 0);
  # print_toks(toks2);
  # toks3 := tokenize("if test x\"a\" = x\"b\"; then echo \"1\"; fi", 0);
  # print_toks(toks3);
  # toks4 := tokenize("echo 'smth2' 'test';", 0);
  # print_toks(toks4);
}
