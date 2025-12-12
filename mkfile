<../../../mkconfig

TARG=sh92.dis\
	sh9util.dis\
	sh9parser.dis\

INS=	$ROOT/dis/sh92.dis\
	$ROOT/dis/sh9/sh9util.dis\
	$ROOT/dis/sh9/sh9parser.dis\

SYSMODULES=\
	sys.m\

DISBIN=$ROOT/dis/sh9

<$ROOT/mkfiles/mkdis

all:V:		$TARG

install:V:	$INS
	cp $DISBIN/sh92.dis $DISBIN/..

nuke:V: clean
	rm -f $INS

clean:V:
	rm -f *.dis *.sbl

uninstall:V:
	rm -f $INS

$ROOT/dis/sh92.dis:	sh92.dis
  mkdir $DISBIN/ &&	rm -f $ROOT/dis/sh92.dis && cp sh92.dis $ROOT/dis/sh92.dis

%.dis: ${SYSMODULES:%=$MODDIR/%}
