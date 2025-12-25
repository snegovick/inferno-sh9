implement Sh92;

include "sys.m";
include "draw.m";
include "sh9util.m";
include "sh9parser.m";
include "sh9cmd.m";
include "bufio.m";
include "env.m";
include "hash.m";
include "workdir.m";

Sh92: module
{
  init: fn(ctxt: ref Draw->Context, argv: list of string);
  zstmt_assign: fn(c: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode;
  zstmt_cmd_call: fn(c: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode;
  zempty: fn(c: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode;
  zsqstr_to_expr: fn(c: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode;
  zvar_sub_expr: fn(c: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode;
  zexpr_expr_combiner: fn(c: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode;
  zsimple_cond: fn(c: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode;
};

sys: Sys;
sh9u: Sh9Util;
sh9p: Sh9Parser;
sh9cmd: Sh9Cmd;
bufio: Bufio;
env: Env;
hash: Hash;

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
Async, Seq: import sh9u;
Command: import sh9u;
Pipeline: import sh9u;

Iobuf: import bufio;

HashTable: import hash;
HashVal: import hash;

stdin: ref sys->FD;
stderr: ref sys->FD;
waitfd: ref sys->FD;

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

S_IF: con "IF";
S_THEN: con "THEN";
S_FI: con "FI";
S_ELIF: con "ELIF";
S_ELSE: con "ELSE";
S_WHILE: con "WHILE";
S_DO: con "DO";
S_DONE: con "DONE";

waitfor(pid: int)
{
  if (pid <= 0)
    return;
  buf := array[sys->WAITLEN] of byte;
  status := "";
  for (;;) {
    n := sys->read(waitfd, buf, len buf);
    if (n < 0) {
      sys->fprint(stderr, "sh9: read wait: %r\n");
      return;
    }
    status = string buf[0:n];
    if (status[len status-1] != ':')
      sys->fprint(stderr, "%s\n", status);
    who := int status;
    if (who != 0) {
      if (who == pid) {
        return;
      }
    }
  }
}

runpipeline(ctx: ref Draw->Context, pipeline: ref Pipeline)
{
  if (pipeline.term == Async)
    sys->pctl(sys->NEWPGRP, nil);
  pid := startpipeline(ctx, pipeline);
  if (pid < 0)
    return;
  if (pipeline.term == Seq)
    waitfor(pid);
}

startpipeline(ctx: ref Draw->Context, pipeline: ref Pipeline): int
{
  pid := 0;
  cmds := pipeline.cmds;
  first := 1;
  inpipe, outpipe: ref Sys->FD;
  while (cmds != nil) {
    last := tl cmds == nil;
    cmd := hd cmds;

    infd: ref Sys->FD;
    if (!first)
      infd = inpipe;
    else if (cmd.inf != nil) {
      infd = sys->open(cmd.inf, Sys->OREAD);
      if (infd == nil) {
        sys->fprint(stderr, "sh9: can't open %s: %r\n", cmd.inf);
        return -1;
      }
    }

    outfd: ref Sys->FD;
    if (!last) {
      fds := array[2] of ref Sys->FD;
      if (sys->pipe(fds) < 0) {
        sys->fprint(stderr, "sh9: can't make pipe: %r\n");
        return -1;
      }
      outpipe = fds[0];
      outfd = fds[1];
      fds = nil;
    } else if (cmd.outf != nil) {
      if (cmd.append){
        outfd = sys->open(cmd.outf, Sys->OWRITE);
        if (outfd != nil)
          sys->seek(outfd, big 0, Sys->SEEKEND);
      }
      if (outfd == nil)
        outfd = sys->create(cmd.outf, Sys->OWRITE, 8r666);
      if (outfd == nil) {
        sys->fprint(stderr, "sh9: can't open %s: %r\n", cmd.outf);
        return -1;
      }
    } else if (cmd.outfd != nil) {
      outfd = cmd.outfd;
    }

    rpid := chan of int;
    ta:=cmd.args;

    la:= len cmd.args;
    #sys->print("mkprog args[%d]: ", la);
    for (z:=0; z<la; z++) {
      #sys->print("%s ", hd ta);
      ta = tl ta;
    }
    #sys->print("\n");
    spawn mkprog(ctx, cmd.args, infd, outfd, rpid);
    pid = <-rpid;
    infd = nil;
    outfd = nil;

    inpipe = outpipe;
    outpipe = nil;

    first = 0;
    cmds = tl cmds;
  }
  return pid;
}

mkprog(ctxt: ref Draw->Context, arg: list of string, infd, outfd: ref Sys->FD, waitpid: chan of int)
{
  fds := list of {0, 1, 2};
  if(infd != nil)
    fds = infd.fd :: fds;
  if(outfd != nil)
    fds = outfd.fd :: fds;
  pid := sys->pctl(sys->NEWFD, fds);
  console := sys->fildes(2);

  if(infd != nil){
    sys->dup(infd.fd, 0);
    infd = nil;
  }
  if(outfd != nil){
    sys->dup(outfd.fd, 1);
    outfd = nil;
  }

  waitpid <-= pid;

  if(pid < 0 || arg == nil) {
    sys->print("no args\n");
    return;
  }

  sys->print("exec: ");
  al:= len arg;
  a:=arg;
  for (i:=0; i<al; i++) {
    ar:= hd a;
    sys->print("\"%s\" ", ar);
    a = tl a;
  }
  sys->print("\n");
  {
    exec(ctxt, arg, console);
  }exception{
    "fail:*" =>
    #sys->fprint(console, "%s:%s\n", hd arg, e.name[5:]);
    exit;
    "write on closed pipe" =>
    #sys->fprint(console, "%s: %s\n", hd arg, e.name);
    exit;
  }
}

exec(ctxt: ref Draw->Context, args: list of string, console: ref Sys->FD)
{
  if (args == nil)
    return;
  cmd := hd args;
  file := cmd;

  if (len file<4 || file[len file-4:]!=".dis")
    file += ".dis";

  cm : Sh9Cmd;
  cm = load Sh9Cmd file;
  if (cm == nil) {
    err := sys->sprint("%r");
    if (err != "permission denied" && err != "access permission denied" && file[0]!='/' && file[0:2]!="./") {
      cm = load Sh9Cmd "/dis/"+file;
      if (cm == nil) {
        err = sys->sprint("%r");
      }
    }
    if (cm == nil) {
      sys->fprint(console, "%s: %s\n", cmd, err);
      return;
    }
  }

  cm->init(ctxt, args);
}

check_keywords(t: ref TokNode): ref TokNode {
  case (t.tok) {
    "if" => t.typ = S_IF;
    "then" => t.typ = S_THEN;
    "fi" => t.typ = S_FI;
    "elif" => t.typ = S_ELIF;
    "else" => t.typ = S_ELSE;
    "while" => t.typ = S_WHILE;
    "do" => t.typ = S_DO;
    "done" => t.typ = S_DONE;
  }
  return t;
}

tokenize(line: string, line_n: int): array of ref TokNode {
  toks : list of ref TokNode;
  last_tok:= ref TokNode;
  last_tok.start = -1;
  last_tok.line = -1;
  last_tok.tok = nil;
  last_tok.typ = S_UNKNOWN;

  for (i := 0; i < len line; i++) {
    if (last_tok.typ == S_DQSTR) {
      case (line[i:i+1]) {
        "\"" => {
          l := len last_tok.tok;
          if ((last_tok.tok[l-1:] != "\\") || ((last_tok.tok[l-1:] == "\\") && (last_tok.tok[l-2:l-1] == "\\"))) {
            # end of str
            last_tok.tok = last_tok.tok + line[i:i+1];
            last_tok = check_keywords(last_tok);
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
            last_tok = check_keywords(last_tok);
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
          last_tok = check_keywords(last_tok);
          (last_tok, toks) = set_last_tok(last_tok, toks);
        };
        "\r" => {
          last_tok = check_keywords(last_tok);
          (last_tok, toks) = set_last_tok(last_tok, toks);
        };
        "\n" => {
          last_tok = check_keywords(last_tok);
          (last_tok, toks) = set_last_tok(last_tok, toks);
          toks = mk_tok(i, line_n, nil, S_EOL) :: toks;
        };
        "=" => {
          last_tok = check_keywords(last_tok);
          (last_tok, toks) = set_last_tok(last_tok, toks);
          toks = mk_tok(i, line_n, "=", S_EQ) :: toks;
        };
        ";" => {
          last_tok = check_keywords(last_tok);
          (last_tok, toks) = set_last_tok(last_tok, toks);
          toks = mk_tok(i, line_n, ";", S_SEMIC) :: toks;
        };
        ":" => {
          last_tok = check_keywords(last_tok);
          (last_tok, toks) = set_last_tok(last_tok, toks);
          toks = mk_tok(i, line_n, ":", S_COLON) :: toks;
        };
        "(" => {
          last_tok = check_keywords(last_tok);
          (last_tok, toks) = set_last_tok(last_tok, toks);
          toks = mk_tok(i, line_n, "(", S_LPAR) :: toks;
        };
        ")" => {
          last_tok = check_keywords(last_tok);
          (last_tok, toks) = set_last_tok(last_tok, toks);
          toks = mk_tok(i, line_n, ")", S_RPAR) :: toks;
        };
        "{" => {
          last_tok = check_keywords(last_tok);
          (last_tok, toks) = set_last_tok(last_tok, toks);
          toks = mk_tok(i, line_n, "{", S_LCURLY) :: toks;
          };
          "}" => {
            last_tok = check_keywords(last_tok);
            (last_tok, toks) = set_last_tok(last_tok, toks);
            toks = mk_tok(i, line_n, "}", S_RCURLY) :: toks;
          };
          "$" => {
            last_tok = check_keywords(last_tok);
            (last_tok, toks) = set_last_tok(last_tok, toks);
            toks = mk_tok(i, line_n, "$", S_DOLL) :: toks;
          };
          "\"" => {
            last_tok = check_keywords(last_tok);
            (last_tok, toks) = set_last_tok(last_tok, toks);
            last_tok.start = i;
            last_tok.line = line_n;
            last_tok.typ = S_DQSTR;
            last_tok.tok = last_tok.tok + line[i:i+1];
          };
          "'" => {
            last_tok = check_keywords(last_tok);
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
  last_tok = check_keywords(last_tok);
  (last_tok, toks) = set_last_tok(last_tok, toks);
  toks = mk_tok(i, line_n, nil, S_EOL) :: toks;
  toks = reverse_list(toks);
  return to_array(toks);
}

zstmt_assign(c: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode {
  sys->print("ASSIGN STMT\n");
  m:= c.get_current_module();
  v:= ref ModVar;
  v.name= toks[0].tok;
  v.val= toks[2].tok;
  m.set_var(v);
  return array[0] of ref TokNode;
}

unquote(s: string): string {
  if (s == nil) {
    return nil;
  }
  ls := len s;
  if (len s > 2) {
    if ((s[:1] == "\"") && (s[ls-1:] == "\"")) {
      return s[1:ls-1];
    } else if ((s[:1] == "\'") && (s[ls-1:] == "\'")) {
      return s[1:ls-1];
    }
  }
  return s;
}

zstmt_cmd_eol_call(c: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode {
  sys->print("CMD EOL CALL\n");
  pl:= ref Pipeline;
  cmd:= ref Command;
  cmd.args = unquote(toks[0].tok) :: cmd.args;
  pl.cmds = cmd :: pl.cmds;
  pl.term = Seq;
  ret := runpipeline(c.ctxt, pl);
  # TODO: check/store ret

  return array[0] of ref TokNode;
}

zstmt_cmd_call(c: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode {
  sys->print("CMD CALL\n");
  print_toks(toks);
  sys->print("tokenize \"%s\"\n", toks[1].tok);
  args:= tokenize(toks[1].tok, 0);
  print_toks(args);
  pl:= ref Pipeline;
  cmd:= ref Command;
  cmd.args = unquote(toks[0].tok) :: cmd.args;
  sys->print("args: ");
  sys->print("\"%s\" ", toks[0].tok);
  la:= len args;
  for (i:=0; i<la; i++) {
    if (args[i].typ == S_EOL) {
      continue;
    }
    cmd.args = unquote(args[i].tok) :: cmd.args;
    sys->print("\"%s\" ", args[i].tok);
  }
  cmd.args = reverse_list(cmd.args);
  pl.cmds = cmd :: pl.cmds;
  pl.term = Seq;
  #sys->print("Call runpipeline\n");
  ret := runpipeline(c.ctxt, pl);
  # TODO: check/store ret

  return array[0] of ref TokNode;
}

zempty(nil: ref ParserCtx, nil: array of ref TokNode): array of ref TokNode {
  return array[0] of ref TokNode;
}

zsqstr_to_expr(nil: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode {
  tn:= mk_tok(toks[0].start, toks[0].line, toks[0].tok, S_EXPR);
  return array[1] of {tn};
}

zvar_sub_expr(c: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode {
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

zcmd_sub_call_expr(c: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode {
  sys->print("CMD SUB\n");
  cmdname := toks[2].tok;
  args:= tokenize(toks[1].tok, 0);
  pl:= ref Pipeline;
  cmd:= ref Command;
  cmd.args = cmdname :: cmd.args;
  # sys->print("args: ");
  # sys->print("%s ", toks[0].tok);
  la:= len args;
  for (i:=0; i<la; i++) {
    cmd.args = unquote(args[i].tok) :: cmd.args;
    #sys->print("%s ", args[i].tok);
  }
  cmd.args = reverse_list(cmd.args);

  fds := array[2] of ref Sys->FD;
  if(sys->pipe(fds) < 0){
    sys->fprint(stderr, "sh92: can't make pipe: %r\n");
    return array[0] of ref TokNode;
  }
  outpipe := fds[0];
  outfd := fds[1];
  fds = nil;

  cmd.outfd = outfd;
  pl.cmds = cmd :: pl.cmds;
  pl.term = Seq;
  #sys->print("Call runpipeline\n");

  ret := runpipeline(c.ctxt, pl);

  output := "";
  buf := array[1024] of byte;
  for (;;) {
    n := sys->read(outpipe, buf, len buf);
    if (n < 0) {
      break;
    }
    chunk := string buf[0:n];
    output = output + chunk;
  }
  tn:= mk_tok(toks[0].start, toks[0].line, output, S_EXPR);
  return array[1] of {tn};
}

zexpr_expr_combiner(nil: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode {
  comb_tok:= toks[0].tok + " " + toks[1].tok;
  tn:= mk_tok(toks[0].start, toks[0].line, comb_tok, S_EXPR);
  return array[1] of {tn};
}

zid_id_combiner(nil: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode {
  t0:= mk_tok(toks[0].start, toks[0].line, toks[0].tok, S_ID);
  t1:= mk_tok(toks[0].start, toks[0].line, toks[1].tok, S_EXPR);
  return array[] of {t0, t1};
}

zexpr_id_combiner(nil: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode {
  t0:= mk_tok(toks[0].start, toks[0].line, toks[0].tok, S_EXPR);
  t1:= mk_tok(toks[0].start, toks[0].line, toks[1].tok, S_EXPR);
  return array[] of {t0, t1};
}

zsimple_cond(nil: ref ParserCtx, nil: array of ref TokNode): array of ref TokNode {
  return array[0] of ref TokNode;
}

mk_grammar(ctx: ref ParserCtx): array of ref GrammarNode
{
  semic_eol_g :            GrammarNode = (array [] of {S_SEMIC, S_EOL}, S_SEMIC, zempty, ctx);
  assign_g_semic :       GrammarNode = (array [] of {S_ID, S_EQ, S_EXPR, S_SEMIC}, S_NONE, zstmt_assign, ctx);
  sqstr_expr_g:            GrammarNode = (array [] of {S_SQSTR}, nil, zsqstr_to_expr, ctx);
  str_expr_g:              GrammarNode = (array [] of {S_STR}, S_EXPR, zempty, ctx);
  expr_combinator_g:     GrammarNode = (array [] of {S_EXPR, S_EXPR}, nil, zexpr_expr_combiner, ctx);
  id_id_combinator_g:    GrammarNode = (array [] of {S_ID, S_ID}, nil, zid_id_combiner, ctx);
  expr_id_combinator_g:  GrammarNode = (array [] of {S_EXPR, S_ID}, nil, zexpr_id_combiner, ctx);
  cmd_call_semic_g:        GrammarNode = (array [] of {S_ID, S_EXPR, S_SEMIC}, nil, zstmt_cmd_call, ctx);
  cmd_call_eol_g:        GrammarNode = (array [] of {S_ID, S_EOL}, nil, zstmt_cmd_eol_call, ctx);
  cmd_expr_call_eol_g:   GrammarNode = (array [] of {S_ID, S_EXPR, S_EOL}, nil, zstmt_cmd_call, ctx);

  var_sub_g:             GrammarNode = (array [] of {S_DOLL, S_ID}, nil, zvar_sub_expr, ctx);
  var_sub_curl_g:          GrammarNode = (array [] of {S_DOLL, S_LCURLY, S_ID, S_RCURLY}, nil, zvar_sub_expr, ctx);
  cmd_sub_call_g:          GrammarNode = (array [] of {S_DOLL, S_LPAR, S_ID, S_EXPR, S_RPAR}, nil, zcmd_sub_call_expr, ctx);
  dqstr_expr_g:            GrammarNode = (array [] of {S_DQTE, S_EXPR, S_DQTE}, nil, zempty, ctx);

  simple_cond_g:         GrammarNode = (array [] of {S_IF, S_EXPR, S_SEMIC, S_THEN, S_STMT, S_FI}, nil, zsimple_cond, ctx);
  # ifel_cond_g:       GrammarNode = (array [] of {S_IF, S_EXPR, S_SEMIC, S_THEN, S_STMT, S_ELSE, S_STMT, S_FI})
  # elifelifel_cond_g: GrammarNode = (array [] of {S_ELIF, S_EXPR, S_SEMIC, S_THEN, S_STMT, S_ELIF, S_EXPR, S_SEMIC, S_THEN, S_STMT, S_ELSE, S_STMT, S_FI})
  # elifeliffi_cond_g: GrammarNode = (array [] of {S_ELIF, S_EXPR, S_SEMIC, S_THEN, S_STMT, S_ELIF, S_EXPR, S_SEMIC, S_THEN, S_STMT, S_FI})

  #grammar:= array[0] of ref GrammarNode;
  grammar: array of ref GrammarNode;
  grammar = array [] of {
    ref semic_eol_g,
    ref assign_g_semic,
    ref sqstr_expr_g,
    ref str_expr_g,
    ref cmd_call_semic_g,
    ref cmd_call_eol_g,
    ref cmd_expr_call_eol_g,
    ref expr_combinator_g,
    ref id_id_combinator_g,
    ref expr_id_combinator_g,
    ref var_sub_g,
    ref var_sub_curl_g,
    ref simple_cond_g,
  };
  return grammar;
}

getusername(): string
{
  fd := sys->open("/dev/user", sys->OREAD);
  if(fd == nil)
    return "/";
  buf := array[128] of byte;
  n := sys->read(fd, buf, len buf);
  if(n < 0)
    return "?";
  return string buf[0:n];
}

getcwd(): string
{
  gwd := load Workdir Workdir->PATH;
  if (gwd == nil) {
    sys->fprint(stderr, "pwd: cannot load %s: %r\n", Workdir->PATH);
    raise "fail:bad module";
  }

  wd := gwd->init();
  if(wd == nil) {
    sys->fprint(stderr, "pwd: %r\n");
    raise "fail:error";
  }
  return wd;
}

sysname(): string
{
  fd := sys->open("#c/sysname", sys->OREAD);
  if(fd == nil)
    return "anon";
  buf := array[128] of byte;
  n := sys->read(fd, buf, len buf);
  if(n < 0)
    return "anon";
  return string buf[0:n];
}

gethome(): string
{
  fd := sys->open("/dev/user", sys->OREAD);
  if(fd == nil)
    return "/";
  buf := array[128] of byte;
  n := sys->read(fd, buf, len buf);
  if(n < 0)
    return "/";
  return "/usr/" + string buf[0:n];
}

script(nil: ref Draw->Context, src: string, grammar: array of ref GrammarNode)
{
  bufio = load Bufio Bufio->PATH;
  if(bufio == nil){
    sys->fprint(stderr, "sh9: load bufio: %r\n");
    return;
  }

  f := bufio->open(src, Bufio->OREAD);
  if(f == nil){
    sys->fprint(stderr, "sh9: open %s: %r\n", src);
    return;
  }
  for(;;){
    s := f.gets('\n');
    if(s == nil)
      break;
    toks := tokenize(s, 0);
    if(toks != nil) {
      parse_toks(toks, grammar, 0);
    }
  }
}

escript(ctxt: ref Draw->Context, file: string, grammar: array of ref GrammarNode)
{
  fd := sys->open(file, Sys->OREAD);
  if (fd != nil)
    script(ctxt, file, grammar);
}

# PROFILE: con "/lib/profile";
PROFILE: con "/lib/infernoinit";

startup(ctxt: ref Draw->Context, grammar: array of ref GrammarNode)
{
  if (env == nil)
    return;
  # if (env->getenv("home") != nil)
  #   return;
  home := gethome();
  env->setenv("home", home);
  escript(ctxt, PROFILE, grammar);
  escript(ctxt, home + PROFILE, grammar);
}

clean_n_chars_seek(sys: Sys, n: int, seek: int) {
  for (i:=0; i<(n-seek); i++) {
    sys->print("\b");
  }
  for (i=0; i<n; i++) {
    sys->print(" ");
  }
  for (i=0; i<n; i++) {
    sys->print("\b");
  }
}

clean_n_chars(sys: Sys, n: int) {
  clean_n_chars_seek(sys, n, 0);
}

argv_to_str(argv: list of string): string {
  out := "";
  lt := len argv;
  for (i := 0; i < lt; i ++) {
    tok := hd argv;
    argv = tl argv;
    out = out + " " + tok;
  }
  return out;
}

prompt(): string {
  prompt := "SH92/" + getusername() + "@" + sysname() + ":" + getcwd() + "; ";
  return prompt;
}

usage()
{
  sys->fprint(stderr, "Usage: sh92 [-n] [-c cmd] [file]\n");
  sys->fprint(stderr, "\t-n : start with FORKNS;\n");
  sys->fprint(stderr, "\t-c : run cmd on start;\n");
  sys->fprint(stderr, "\t[file] : run script file on start and exit, optional.\n");
}

init(ctxt: ref Draw->Context, argv: list of string) {
  sys = load Sys Sys->PATH;
  sh9u = load Sh9Util Sh9Util->PATH;
  sh9p = load Sh9Parser Sh9Parser->PATH;
  sh9p->init();
  sh9cmd = load Sh9Cmd Sh9Cmd->PATH;
  env = load Env Env->PATH;
  bufio = load Bufio Bufio->PATH;
  hash = load Hash Hash->PATH;

  #n: int;
  #arg: list of string;
  buf := array[1024] of byte;

  pctx:= ref ParserCtx;
  pctx.add_module("");
  pctx.ctxt = ctxt;
  grammar:= mk_grammar(pctx);

  stderr = sys->fildes(2);

  waitfd = sys->open("#p/"+string sys->pctl(0, nil)+"/wait", sys->OREAD);
  if(waitfd == nil){
    sys->fprint(stderr, "sh9: open wait: %r\n");
    return;
  }

  eflag := nflag := lflag := 0;
  cmd: string;
  if(argv != nil) {
    argv = tl argv;
  }
  for(; argv != nil && len hd argv && (hd argv)[0]=='-'; argv = tl argv) {
    case hd argv {
      "-e" =>
      eflag = 1;
      "-n" =>
      nflag = 1;
      "-l" =>
      lflag = 1;
      "-c" =>
      argv = tl argv;
      if(len argv != 1){
        usage();
        return;
      }
      cmd = hd argv;
      * =>
      usage();
      return;
    }
  }

  if (lflag)
    startup(ctxt, grammar);

  if(eflag == 0)
    sys->pctl(sys->FORKENV, nil);
  if(nflag == 0)
    sys->pctl(sys->FORKNS, nil);
  if(cmd != nil){
    toks := tokenize(cmd, 0);
    if(toks != nil) {
      parse_toks(toks, grammar, 0);
    }
    return;
  }
  if(argv != nil){
    script(ctxt, hd argv, grammar);
    return;
  }

  cctlfd := sys->open("/dev/consctl", sys->OWRITE);
  if(cctlfd == nil)
    return;
  sys->write(cctlfd, array of byte "rawon", 5);

  dfd := sys->open("/dev/cons", sys->OREAD);
  if(dfd == nil)
    return;

  offset : int = 0;
  temp : int;
  #last_cmdline := array[1024] of int;
  #last_cmdline_length : int = 0;

  cmd1 := 0;
  ST_NORMAL : con 0;
  ST_WAITCMD1 : con 1;
  ST_WAITCMD2 : con 2;
  state := ST_NORMAL;
  history_len := 1;
  history_entry_cur := 0;
#  history.entries = nil;
#  history.entries = ("", "") :: nil;
  history := hash->new(1024);
  history.insert("0", (0,0.0,""));
  seek := 0;

  bio := bufio->fopen(dfd, sys->OREAD);

  sys->print("%s", prompt());
  for(;;) {
    temp = bio.getb();
    # check if escape
    case state {
      ST_NORMAL =>
      # check if escape
      if (temp == 27) {
        state = ST_WAITCMD1; # is escape
      } else if (temp == '\t') {
        # tab complete rq
        sys->print("tab");
      } else if (temp == '\b') {
        if (seek == 0) {
          if (offset != 0) {
            sys->print("\b");
            sys->print(" ");
            sys->print("\b");
            offset --;
          }
        } else {
          cur_buf := array[1024] of byte;
          cur_buf[0:] = buf[0:offset];
          correction := 0;
          for (i:=0;i<offset;i++) {
            if ((offset-i-1) == seek) {
              correction = 1;
            } else {
              buf[i-correction] = cur_buf[i];
            }
          }
          clean_n_chars_seek(sys, offset, seek);
          offset --;
          for (i=0;i<offset;i++) {
            sys->print("%c", int(buf[i]));
          }
          for (i=0; i<seek; i++) {
            sys->print("\b");
          }
        }
      } else {
        buf[offset] = byte(temp);
        offset ++;
        if ((offset >= len buf) || (buf[offset-1] == byte('\n'))) {
          history_entry_cur = 0;
          seek = 0;
          sys->print("\n");
          sys->print("run: \"%s\"\n", string buf[0: offset]);
          toks := tokenize(string buf[0: offset], 0);
          print_toks(toks);
          if(toks != nil) {
            parse_toks(toks, grammar, 0);
            #runit(ctxt, parseit(arg));
            history.insert(sys->sprint("%d", history_len), (0,0.0,string buf[0:offset-1]));
            history_len++;
          }
          offset = 0;
          sys->print("%s", prompt());
        } else {
          sys->print("%c",temp);
        }
      }
      ST_WAITCMD1 =>
      if (temp == '[') {
        state = ST_WAITCMD2;
        cmd1 = temp;
      }
      ST_WAITCMD2 =>
      state = ST_NORMAL;
      case cmd1 {
        '[' =>
        case temp {
          65 => {      #up press
            seek = 0;
            clean_n_chars(sys, offset);

            offset = 0;
            he := history_len;
            if (history_entry_cur < history_len) {
              history_entry_cur ++;
              he -= history_entry_cur;
            }
            cmdline := history.find(sys->sprint("%d", he));
            if (cmdline != nil) {
              sys->print("%s", cmdline.s);
              offset = len cmdline.s;
              for (i:=0; i<len cmdline.s; i++) {
                buf[i] = byte(cmdline.s[i]);
              }
            }
          }
          66 => { # down key
            seek = 0;
            if (history_entry_cur > 0) {
              history_entry_cur --;
              clean_n_chars(sys, offset);

              offset = 0;
              he := history_len;
              he -= history_entry_cur;
              cmdline := history.find(sys->sprint("%d", he));
              if (cmdline != nil) {
                sys->print("%s", cmdline.s);
                offset = len cmdline.s;
                for (i:=0; i<len cmdline.s; i++) {
                  buf[i] = byte(cmdline.s[i]);
                }
              }
            }
          }
          68 => { # left key
            if (seek > offset) {
              seek = offset;
            } else {
              seek ++;
              sys->print("\b");
            }
          }
          67 => { # right key
            clean_n_chars_seek(sys, offset, seek);
            for (i:=0; i<offset; i++) {
              sys->print("%c", int(buf[i]));
            }
            if (seek > 0) {
              seek --;
            }
            for (i=0; i<seek; i++) {
              sys->print("\b");
            }
          }
          70 => { # end key
            clean_n_chars_seek(sys, offset, seek);
            seek = 0;
            for (i:=0; i<offset; i++) {
              sys->print("%c", int(buf[i]));
            }
          }
          72 => { # home key
            seek = offset;
            for (i:=0; i<seek; i++) {
              sys->print("\b");
            }
          }
          * => {
            sys->print("no action bind for %d\n", temp);
          }

        }
      }
    }
  }
}
