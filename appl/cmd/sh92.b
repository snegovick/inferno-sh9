implement Sh92;

include "sys.m";
include "draw.m";
include "sh9util.m";
include "sh9parser.m";
include "sh9cmd.m";

Sh92: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
	zstmt_assign: fn(c: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode;
	zstmt_cmd_call: fn(c: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode;
	zempty: fn(c: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode;
	zsqstr_to_expr: fn(c: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode;
	zvar_sub_expr: fn(c: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode;
	zexpr_expr_combiner: fn(c: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode;
};

sys: Sys;
sh9u: Sh9Util;
sh9p: Sh9Parser;
sh9cmd: Sh9Cmd;

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

	if(pid < 0 || arg == nil)
		return;

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
	toks = mk_tok(i, line_n, "", S_EOL) :: toks;
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

zstmt_cmd_call(c: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode {
	sys->print("CMD CALL\n");
	args:= tokenize(toks[1].tok, 0);
	pl:= ref Pipeline;
	cmd:= ref Command;
	cmd.args = unquote(toks[0].tok) :: cmd.args;
	# sys->print("args: ");
	# sys->print("%s ", toks[0].tok);
	la:= len args;
	for (i:=0; i<la; i++) {
		cmd.args = unquote(args[i].tok) :: cmd.args;
		#sys->print("%s ", args[i].tok);
	}
	cmd.args = reverse_list(cmd.args);
	pl.cmds = cmd :: pl.cmds;
	pl.term = Seq;
	#sys->print("Call runpipeline\n");
	ret := runpipeline(c.ctxt, pl);

	return array[0] of ref TokNode;
}

zempty(c: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode {
	return array[0] of ref TokNode;
}

zsqstr_to_expr(c: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode {
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

zexpr_expr_combiner(c: ref ParserCtx, toks: array of ref TokNode): array of ref TokNode {
	comb_tok:= toks[0].tok + " " + toks[1].tok;
	tn:= mk_tok(toks[0].start, toks[0].line, comb_tok, S_EXPR);
	return array[1] of {tn};
}

mk_grammar(ctx: ref ParserCtx): array of ref GrammarNode
{
	semic_eol_g :			 GrammarNode = (array [] of {S_SEMIC, S_EOL}, S_SEMIC, zempty, ctx);
	assign_g_semic :	 GrammarNode = (array [] of {S_ID, S_EQ, S_EXPR, S_SEMIC}, S_NONE, zstmt_assign, ctx);
	sqstr_expr_g:			 GrammarNode = (array [] of {S_SQSTR}, nil, zsqstr_to_expr, ctx);
	str_expr_g:				 GrammarNode = (array [] of {S_STR}, S_EXPR, zempty, ctx);
	expr_combinator_g: GrammarNode = (array [] of {S_EXPR, S_EXPR}, nil, zexpr_expr_combiner, ctx);
	cmd_call_semic_g:	 GrammarNode = (array [] of {S_ID, S_EXPR, S_SEMIC}, nil, zstmt_cmd_call, ctx);

	var_sub_g:				 GrammarNode = (array [] of {S_DOLL, S_ID}, nil, zvar_sub_expr, ctx);
	var_sub_curl_g:		 GrammarNode = (array [] of {S_DOLL, S_LCURLY, S_ID, S_RCURLY}, nil, zvar_sub_expr, ctx);
	dqstr_expr_g:			 GrammarNode = (array [] of {S_DQTE, S_EXPR, S_DQTE}, nil, zempty, ctx);

	# simple_cond_g:		 GrammarNode = (array [] of {S_IF, S_EXPR, S_SEMIC, S_THEN, S_STMT, S_FI})
	# ifel_cond_g:			 GrammarNode = (array [] of {S_IF, S_EXPR, S_SEMIC, S_THEN, S_STMT, S_ELSE, S_STMT, S_FI})
	# elifelifel_cond_g: GrammarNode = (array [] of {S_ELIF, S_EXPR, S_SEMIC, S_THEN, S_STMT, S_ELIF, S_EXPR, S_SEMIC, S_THEN, S_STMT, S_ELSE, S_STMT, S_FI})
	# elifeliffi_cond_g: GrammarNode = (array [] of {S_ELIF, S_EXPR, S_SEMIC, S_THEN, S_STMT, S_ELIF, S_EXPR, S_SEMIC, S_THEN, S_STMT, S_FI})

	#grammar:= array[0] of ref GrammarNode;
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
	sh9cmd = load Sh9Cmd Sh9Cmd->PATH;

	stderr = sys->fildes(2);

	waitfd = sys->open("#p/"+string sys->pctl(0, nil)+"/wait", sys->OREAD);
	if(waitfd == nil){
		sys->fprint(stderr, "sh9: open wait: %r\n");
		return;
	}

	sys->pctl(sys->FORKENV, nil);
	sys->pctl(sys->FORKNS, nil);

	pctx:= ref ParserCtx;
	pctx.add_module("shell");
	pctx.ctxt = ctxt;

	toks1 := tokenize("AB = 'smth \"test\"	'; echo ${AB}; echo $AB", 0);
	grammar:= mk_grammar(pctx);
	parse_toks(toks1, grammar);
}
