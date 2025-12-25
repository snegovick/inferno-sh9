implement Sh9Log;

include "sys.m";
include "sh9log.m";

sys: Sys;

Logger.dbg(m: self ref Logger, s: string): int
{
  n:=0;
  if (m.level <= LOG_DBG) {
    n = sys->print("[D %d/%d] %s\n", m.level, LOG_DBG, s);
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
  sys->print("level: %d\n", level);
  if (level >= LOG_ERR) {
    m.level = LOG_ERR;
    sys->print("log err\n");
  } else if (level <= LOG_DBG) {
    m.level = LOG_DBG;
    sys->print("log dbg\n");
  } else {
    m.level = level;
    sys->print("level\n");
  }
  sys->print("set level %d\n", m.level);
}

init()
{
	sys = load Sys Sys->PATH;
}
