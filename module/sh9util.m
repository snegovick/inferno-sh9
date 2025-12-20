Sh9Util: module
{
PATH: con "/dis/lib/sh9util.dis";
DESCR: con "Utility functions for sh9";

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

reverse_list: fn[T](toks: list of T): list of T;
to_array: fn[T](toks: list of T): array of T;
};
