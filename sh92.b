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

ModProc: adt {
  name: string;
  start: int;
};

ModVar: adt {
  name: string;
  val: string;
};

ShModule: adt {
  global_vars: list of ref ModVar;
  procs: list of ref ModProc;
};

GrammarNode: import sh9p;
TokNode: import sh9p;
mk_tok: import sh9p;
set_last_tok: import sh9p;
print_toks: import sh9p;
parse_toks: import sh9p;

reverse_list: import sh9u;
to_array: import sh9u;

S_UNKNOWN: con "UNK";
S_ID: con "ID";
S_STR: con "STR";
S_EQ: con "EQ";
S_DOL: con "DOL";
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
S_EOL: con "EOL";

S_STMT: con "STMT";
S_EXPR: con "EXPR";
S_CALL: con "CALL";

tokenize(line: string, line_n: int): array of ref TokNode {
  toks : list of ref TokNode;
  last_tok: TokNode;
  last_tok.start = -1;
  last_tok.line = -1;
  last_tok.tok = "";
  last_tok.typ = S_UNKNOWN;

  for (i := 0; i < len line; i++) {
    if (last_tok.typ == S_DQSTR) {
      case (line[i:i+1]) {
        "\"" => {
          l := len last_tok.tok;
          if ((last_tok.tok[l-1:] != "\\") || ((last_tok.tok[l-1:] == "\\") && (last_tok.tok[l-2:l-1] == "\\"))) {
            # end of str
            last_tok.tok = last_tok.tok + line[i:i+1];
            (last_tok, toks) = set_last_tok(ref last_tok, toks);
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
            (last_tok, toks) = set_last_tok(ref last_tok, toks);
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
          (last_tok, toks) = set_last_tok(ref last_tok, toks);
        };
        "=" => {
          (last_tok, toks) = set_last_tok(ref last_tok, toks);
          toks = ref mk_tok(i, line_n, "=", S_EQ) :: toks;
        };
        ";" => {
          (last_tok, toks) = set_last_tok(ref last_tok, toks);
          toks = ref mk_tok(i, line_n, ";", S_SEMIC) :: toks;
        };
        "$" => {
          (last_tok, toks) = set_last_tok(ref last_tok, toks);
          toks = ref mk_tok(i, line_n, "$", S_DOL) :: toks;
        };
        "(" => {
          (last_tok, toks) = set_last_tok(ref last_tok, toks);
          toks = ref mk_tok(i, line_n, "(", S_LPAR) :: toks;
        };
        ")" => {
          (last_tok, toks) = set_last_tok(ref last_tok, toks);
          toks = ref mk_tok(i, line_n, ")", S_RPAR) :: toks;
        };
        "{" => {
          (last_tok, toks) = set_last_tok(ref last_tok, toks);
          toks = ref mk_tok(i, line_n, "{", S_LCURLY) :: toks;
          };
          "}" => {
            (last_tok, toks) = set_last_tok(ref last_tok, toks);
            toks = ref mk_tok(i, line_n, "}", S_RCURLY) :: toks;
          };
          "\"" => {
            (last_tok, toks) = set_last_tok(ref last_tok, toks);
            last_tok.start = i;
            last_tok.line = line_n;
            last_tok.typ = S_DQSTR;
            last_tok.tok = last_tok.tok + line[i:i+1];
          };
          "'" => {
            (last_tok, toks) = set_last_tok(ref last_tok, toks);
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
  (last_tok, toks) = set_last_tok(ref last_tok, toks);
  toks = ref mk_tok(i, line_n, "", S_EOL) :: toks;
  toks = reverse_list(toks);
  return to_array(toks);
}

stmt_assign(toks: array of ref TokNode) {
  sys->print("ASSIGN STMT\n");
}

stmt_cmd_call(toks: array of ref TokNode) {
  sys->print("CMD CALL\n");
}

empty(toks: array of ref TokNode) {
  sys->print("EMPTY\n");
}

init(ctxt: ref Draw->Context, argv: list of string) {
  sys = load Sys Sys->PATH;
  sh9u = load Sh9Util Sh9Util->PATH;
  sh9p = load Sh9Parser Sh9Parser->PATH;

  assign_g_semic : GrammarNode = (array [] of {S_ID, S_EQ, S_EXPR, S_SEMIC}, S_UNKNOWN, stmt_assign);
  assign_g_eol : GrammarNode = (array [] of {S_ID, S_EQ, S_EXPR, S_EOL}, S_UNKNOWN, stmt_assign);
  sqstr_expr_g: GrammarNode = (array [] of {S_SQSTR}, S_EXPR, empty);
  str_expr_g: GrammarNode = (array [] of {S_STR}, S_EXPR, empty);
  cmd_call_g: GrammarNode = (array [] of {S_ID, S_EQ, S_EXPR, S_SEMIC}, S_UNKNOWN, stmt_cmd_call);
  grammar: array of ref GrammarNode;
  grammar = array [] of {ref assign_g_semic, ref assign_g_eol, ref sqstr_expr_g, ref str_expr_g, ref cmd_call_g};

  toks1 := tokenize("A = 'smth \"test\"  ';", 0);
  print_toks(toks1);
  sys->print("Parse\n");
  parse_toks(toks1, grammar);
  sys->print("Parse done\n");

  # toks2 := tokenize("echo \"smth \" \"test\";", 0);
  # print_toks(toks2);
  # toks3 := tokenize("if test x\"a\" = x\"b\"; then echo \"1\"; fi", 0);
  # print_toks(toks3);
  # toks4 := tokenize("echo 'smth2' 'test';", 0);
  # print_toks(toks4);
}
