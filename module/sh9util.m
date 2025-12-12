Sh9Util: module
{
PATH: con "/dis/lib/sh9util.dis";
DESCR: con "Utility functions for sh9";

reverse_list: fn[T](toks: list of T): list of T;
to_array: fn[T](toks: list of T): array of T;
};
