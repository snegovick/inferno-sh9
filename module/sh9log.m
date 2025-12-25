Sh9Log: module
{
PATH: con "/dis/lib/sh9log.dis";
DESCR: con "Log functions for sh9";

LOG_DBG, LOG_INF, LOG_WRN, LOG_ERR: con iota;

Logger: adt
{
outf: string;
level: int;
format: string;

set_level: fn(m: self ref Logger, level: int);
dbg: fn(m: self ref Logger, s: string): int;
inf: fn(m: self ref Logger, s: string): int;
wrn: fn(m: self ref Logger, s: string): int;
err: fn(m: self ref Logger, s: string): int;
};

init: fn();
};
