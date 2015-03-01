implement Sh9;

include "sys.m";
sys: Sys;
FD: import Sys;

include "draw.m";
Context: import Draw;

include "filepat.m";
filepat: Filepat;
nofilepat := 0;			# true if load Filepat has failed.

include "bufio.m";
bufio: Bufio;
Iobuf: import bufio;

include "env.m";
env: Env;

include "hash.m";
hash: Hash;
HashTable: import hash;
HashVal: import hash;

stdin: ref FD;
stderr: ref FD;
waitfd: ref FD;

Quoted: con '\uFFF0';
stringQuoted: con "\uFFF0";

Sh9: module
{
	init: fn(ctxt: ref Context, argv: list of string);
};

Command: adt
{
	args: list of string;
	inf, outf: string;
	append: int;
};

Async, Seq: con iota;

Pipeline: adt
{
	cmds: list of ref Command;
	term: int;
};

usage()
{
	sys->fprint(stderr, "Usage: sh9 [-n] [-c cmd] [file]\n");
}

init(ctxt: ref Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	env = load Env Env->PATH;
  bufio = load Bufio Bufio->PATH;
  hash = load Hash Hash->PATH;

	n: int;
	arg: list of string;
	buf := array[1024] of byte;

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
		startup(ctxt);
  
	if(eflag == 0)
		sys->pctl(sys->FORKENV, nil);
	if(nflag == 0)
		sys->pctl(sys->FORKNS, nil);
	if(cmd != nil){
		arg = tokenize(cmd+"\n");
		if(arg != nil)
			runit(ctxt, parseit(arg));
		return;
	}
	if(argv != nil){
		script(ctxt, hd argv);
		return;
	}

  cctlfd := sys->open("/dev/consctl", sys->OWRITE);
	if(cctlfd == nil)
		return;
	sys->write(cctlfd, array of byte "rawon", 5);
  
  dfd := sys->open("/dev/cons", sys->OREAD);
	if(dfd == nil)
		return;
  
  
	#stdin = sys->fildes(0);
  
	prompt := sysname() + "$ ";
  offset : int = 0;
  temp : int;
  last_cmdline := array[1024] of int;
  last_cmdline_length : int = 0;
  
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
  
  sys->print("SH9 v0\n");
  sys->print("%s", prompt);
	for(;;) {
		temp = bio.getb();    
    # check if escape
    case state {
      ST_NORMAL =>
      # check if escape
      if (temp == 27) {
        state = ST_WAITCMD1;
      } else if (temp == '\b') {
        if (offset != 0) {
          sys->print("\b");
          sys->print(" ");
          sys->print("\b");
          offset --;             
        }
      } else {
        buf[offset] = byte(temp);
        offset ++;
        if ((offset >= len buf) || (buf[offset-1] == byte('\n'))) {
          history_entry_cur = 0;
          sys->print("\n");
          arg = tokenize(string buf[0:offset]);
          if(arg != nil) {
            runit(ctxt, parseit(arg));
            history.insert(sys->sprint("%d", history_len), (0,0.0,string buf[0:offset-1]));
            history_len++;
          }
          offset = 0;
          sys->print("\n%s", prompt);
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
            for (i:=0; i<offset; i++) {
              sys->print("\b");
            }        
            for (i=0; i<offset; i++) {
              sys->print(" ");
            }
            for (i=0; i<offset; i++) {
              sys->print("\b");
            }        
            
            offset = 0;
            history_entry_cur ++;
            he := history_len;
            he -= history_entry_cur;
            cmdline := history.find(sys->sprint("%d", he));
            if (cmdline != nil) {
              sys->print("%s", cmdline.s);
              offset = len cmdline.s;
              for (i=0;i<len cmdline.s;i++) {
                buf[i] = byte(cmdline.s[i]);
              }
            }
          }
          66 => { # down key
            if (history_entry_cur > 0) {
              history_entry_cur --;
              
              for (i:=0; i<offset; i++) {
                sys->print("\b");
              }        
              for (i=0; i<offset; i++) {
                sys->print(" ");
              }
              for (i=0; i<offset; i++) {
                sys->print("\b");
              }
              offset = 0;
              he := history_len;
              he -= history_entry_cur;
              cmdline := history.find(sys->sprint("%d", he));
              if (cmdline != nil) {
                sys->print("%s", cmdline.s);
                offset = len cmdline.s;
                for (i=0;i<len cmdline.s;i++) {
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
            for (i:=0; i<(offset-seek); i++) {
              sys->print("\b");
            }        
            for (i=0; i<offset; i++) {
              sys->print(" ");
            }
            for (i=0; i<offset; i++) {
              sys->print("\b");
            }
            for (i=0; i<offset; i++) {
              sys->print("%c", int(buf[i]));
            }
            if (seek > 0) {
              seek --;
            }
            for (i=0; i<seek; i++) {
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

rev(arg: list of string): list of string
{
	ret: list of string;

	while(arg != nil){
		ret = hd arg :: ret;
		arg = tl arg;
	}
	return ret;
}

waitfor(pid: int)
{
	if(pid <= 0)
		return;
	buf := array[sys->WAITLEN] of byte;
	status := "";
	for(;;){
		n := sys->read(waitfd, buf, len buf);
		if(n < 0){
			sys->fprint(stderr, "sh9: read wait: %r\n");
			return;
		}
		status = string buf[0:n];
		if(status[len status-1] != ':')
			sys->fprint(stderr, "%s\n", status);
		who := int status;
		if(who != 0){
			if(who == pid){
				return;
      }
		}
	}
}

mkprog(ctxt: ref Context, arg: list of string, infd, outfd: ref Sys->FD, waitpid: chan of int)
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

exec(ctxt: ref Context, args: list of string, console: ref Sys->FD)
{
	if (args == nil)
		return;
	cmd := hd args;
	file := cmd;
	
	if(len file<4 || file[len file-4:]!=".dis")
		file += ".dis";

	c := load Sh9 file;
	if(c == nil) {
		err := sys->sprint("%r");
		if(err != "permission denied" && err != "access permission denied" && file[0]!='/' && file[0:2]!="./"){
			c = load Sh9 "/dis/"+file;
			if(c == nil) {
				err = sys->sprint("%r");
      }
		}
		if(c == nil){
			sys->fprint(console, "%s: %s\n", cmd, err);
			return;
		}
	}
  
	c->init(ctxt, args);
}

script(ctxt: ref Context, src: string)
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
    arg := tokenize(s);
		if(arg != nil)
			runit(ctxt, parseit(arg));
	}
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

# Lexer.

tokenize(s: string): list of string
{
	tok: list of string;
	token := "";
	instring := 0;

  loop:
	for(i:=0; i<len s; i++) {
		if(instring) {
			if(s[i] != '\'')
				token = addchar(token, s[i]);
			else if(i == len s-1 || s[i+1] != '\'') {
				if(i == len s-1 || s[i+1] == ' ' || s[i+1] == '\t' || s[i+1] == '\n'){
					tok = token :: tok;
					token = "";
				}
				instring = 0;
			} else {
				token[len token] = '\'';
				i++;
			}
			continue;
		}
		case s[i] {      
		  ' ' or '\t' or '\n' or '#' or
		  '\'' or '|' or '&' or ';' or
		  '>' or '<' or '\r' =>
			if(token != "" && s[i]!='\''){
				tok = token :: tok;
				token = "";
			}
			case s[i] {
			  '#' =>
				break loop;
			  '\'' =>
				instring = 1;
			  '>' =>
				ss := "";
				ss[0] = s[i];
				if(i<len s-1 && s[i+1]==s[i])
					ss[1] = s[i++];
				tok = ss :: tok;
			  '|' or '&' or ';' or '<' =>
				ss := "";
				ss[0] = s[i];
				tok = ss :: tok;
			}
		  * =>
			token[len token] = s[i];
		}
	}
	if(instring){
		sys->fprint(stderr, "sh9: unmatched quote\n");
		return nil;
	}
	return rev(tok);
}

ismeta(char: int): int
{
	case char {
	  '*'  or '[' or '?' or
	  '#'  or '\'' or '|' or
	  '&' or ';' or '>' or
	  '<'  =>
		return 1;
	}
	return 0;
}

addchar(token: string, char: int): string
{
	if(ismeta(char) && (len token==0 || token[0]!=Quoted))
		token = stringQuoted + token;
	token[len token] = char;
	return token;
}

# Parser.

getcommand(words: list of string): (ref Command, list of string)
{
	args: list of string;
	word: string;
	si, so: string;
	append := 0;

  gather:
	do {
		word = hd words;

		case word {
		  ">" or ">>" =>
			if(so != nil)
				return (nil, nil);

			words = tl words;

			if(words == nil)
				return (nil, nil);

			so = hd words;
			if(len so>0 && so[0]==Quoted)
				so = so[1:];
			if(word == ">>")
				append = 1;
		  "<" =>
			if(si != nil)
				return (nil, nil);

			words = tl words;

			if(words == nil)
				return (nil, nil);

			si = hd words;
			if(len si>0 && si[0]==Quoted)
				si = si[1:];
		  "|" or ";" or "&" =>
			break gather;
		  * =>
			files := doexpand(word);
			while(files != nil){
				args = hd files :: args;
				files = tl files;
			}
		}

		words = tl words;
	} while (words != nil);

	return (ref Command(rev(args), si, so, append), words);
}

doexpand(file: string): list of string
{
	if(file == nil)
		return file :: nil;
	if(len file>0 && file[0]==Quoted)
		return file[1:] :: nil;
	if (nofilepat)
		return file :: nil;
	for(i:=0; i<len file; i++)
  {
		if (file[i]=='*' || file[i]=='[' || file[i]=='?'){
			if(filepat == nil) {
				if ((filepat = load Filepat Filepat->PATH) == nil) {
					sys->fprint(stderr, "sh: warning: cannot load %s: %r\n",
					Filepat->PATH);
					nofilepat = 1;
					return file :: nil;
				}
			}
			files := filepat->expand(file);
			if(files != nil)
				return files;
			break;
		}
  }
	return file :: nil;
}

revc(arg: list of ref Command): list of ref Command
{
	ret: list of ref Command;
	while(arg != nil) {
		ret = hd arg :: ret;
		arg = tl arg;
	}
	return ret;
}

getpipe(words: list of string): (ref Pipeline, list of string)
{
	cmds: list of ref Command;
	cur: ref Command;
	word: string;

	term := Seq;
  gather:
	while(words != nil) {
		word = hd words;

		if(word == "|")
			return (nil, nil);

		(cur, words) = getcommand(words);

		if(cur == nil)
			return (nil, nil);

		cmds = cur :: cmds;

		if(words == nil)
			break gather;

		word = hd words;
		words = tl words;

		case word {
		  ";" =>
			break gather;
		  "&" =>
			term = Async;
			break gather;
		  "|" =>
			continue gather;
		}
		return (nil, nil);
	}

	if(word == "|")
		return (nil, nil);

	return (ref Pipeline(revc(cmds), term), words);
}

revp(arg: list of ref Pipeline): list of ref Pipeline
{
	ret: list of ref Pipeline;

	while(arg != nil) {
		ret = hd arg :: ret;
		arg = tl arg;
	}
	return ret;
}

parseit(words: list of string): list of ref Pipeline
{
	ret: list of ref Pipeline;
	cur: ref Pipeline;

	while(words != nil) {
		(cur, words) = getpipe(words);
		if(cur == nil){
			sys->fprint(stderr, "sh9: syntax error\n");
			return nil;
		}
		ret = cur :: ret;
	}
	return revp(ret);
}

# Runner.

runpipeline(ctx: ref Context, pipeline: ref Pipeline)
{
	if(pipeline.term == Async)
		sys->pctl(sys->NEWPGRP, nil);
	pid := startpipeline(ctx, pipeline);
	if(pid < 0)
		return;
	if(pipeline.term == Seq)
		waitfor(pid);
}

startpipeline(ctx: ref Context, pipeline: ref Pipeline): int
{
	pid := 0;
	cmds := pipeline.cmds;
	first := 1;
	inpipe, outpipe: ref Sys->FD;
	while(cmds != nil) {
		last := tl cmds == nil;
		cmd := hd cmds;

		infd: ref Sys->FD;
		if(!first)
			infd = inpipe;
		else if(cmd.inf != nil){
			infd = sys->open(cmd.inf, Sys->OREAD);
			if(infd == nil){
				sys->fprint(stderr, "sh9: can't open %s: %r\n", cmd.inf);
				return -1;
			}
		}

		outfd: ref Sys->FD;
		if(!last){
			fds := array[2] of ref Sys->FD;
			if(sys->pipe(fds) < 0){
				sys->fprint(stderr, "sh9: can't make pipe: %r\n");
				return -1;
			}
			outpipe = fds[0];
			outfd = fds[1];
			fds = nil;
		}else if(cmd.outf != nil){
			if(cmd.append){
				outfd = sys->open(cmd.outf, Sys->OWRITE);
				if(outfd != nil)
					sys->seek(outfd, big 0, Sys->SEEKEND);
			}
			if(outfd == nil)
				outfd = sys->create(cmd.outf, Sys->OWRITE, 8r666);
			if(outfd == nil){
				sys->fprint(stderr, "sh9: can't open %s: %r\n", cmd.outf);
				return -1;
			}
		}

		rpid := chan of int;
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

runit(ctx: ref Context, pipes: list of ref Pipeline)
{
	while(pipes != nil) {
		pipeline := hd pipes;
		pipes = tl pipes;
		if(pipeline.term == Seq)
			runpipeline(ctx, pipeline);
		else
			spawn runpipeline(ctx, pipeline);
	}
}

strchr(s: string, c: int): int
{
	ln := len s;
	for (i := 0; i < ln; i++)
		if (s[i] == c)
			return i;
	  return -1;
}

# PROFILE: con "/lib/profile";
PROFILE: con "/lib/infernoinit";

startup(ctxt: ref Context)
{
	if (env == nil)
		return;
	# if (env->getenv("home") != nil)
	#	return;
	home := gethome();
	env->setenv("home", home);
	escript(ctxt, PROFILE);
	escript(ctxt, home + PROFILE);
}

escript(ctxt: ref Context, file: string)
{
	fd := sys->open(file, Sys->OREAD);
	if (fd != nil)
		script(ctxt, file);
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
