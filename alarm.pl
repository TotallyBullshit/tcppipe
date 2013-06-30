#!/usr/bin/perl -w
# created @ 16.01.2009 by TheFox

use strict;
use Time::HiRes qw(usleep);
$| = 1;

print time().": start\n";
my $text = '';
eval{
	my $s = 30;
	local $SIG{'ALRM'} = sub{ die time().": alarm\n"; };
	alarm 3;
	#print time().": sleep $s\n";
	#$text = join '', <>;
	sysread STDIN, $text, 10;
	alarm 0;
};
print time().": ende >$text< $@\n";

