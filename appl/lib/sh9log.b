implement Sh9Log;

include "sys.m";
include "sh9log.m";

sys: Sys;

Logger.dbg(m: self ref Logger, s: string): int
{
  n:=0;
  if (m.level <= LOG_DBG) {
    n = sys->print("[D] %s\n", s);
  }
  return n;
}

Logger.inf(m: self ref Logger, s: string): int
{
  n:=0;
  if (m.level <= LOG_INF) {
    n = sys->print("[I] %s\n", s);
  }
  return n;
}

Logger.wrn(m: self ref Logger, s: string): int
{
  n:=0;
  if (m.level <= LOG_WRN) {
    n = sys->print("[W] %s\n", s);
  }
  return n;
}

Logger.err(m: self ref Logger, s: string): int
{
  n:=0;
  if (m.level <= LOG_ERR) {
    n = sys->print("[E] %s\n", s);
  }
  return n;
}

Logger.set_level(m: self ref Logger, level: int)
{
  if (m.level >= LOG_ERR) {
    m.level = LOG_ERR;
  } else if (m.level <= LOG_DBG) {
    m.level = LOG_DBG;
  } else {
    m.level = level;
  }
}

init()
{
	sys = load Sys Sys->PATH;
}
