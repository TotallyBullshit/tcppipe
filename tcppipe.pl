#!/usr/bin/perl -w
# Created @ 16.01.2009 by TheFox@fox21.at
# Version: 1.0.0
# Copyright (c) 2009 TheFox

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Description:
# TCP Pipe, Bridge, TCP to UDP, UDP to TCP.


use strict;
use POSIX;
use IO::Select;
use IO::Socket::INET;
use Time::HiRes qw(usleep);

$| = 1;

# otptions:
# a = active (this is optional if you use option 'c', because a client only connects if the server gets a connection)
# t = tcp
# u = udp
# s = server
# c = client
# l = local client

my $MAXSENDBYTES = 1024 * 8; # = 8kb; if a client sends without a end, we force a end of reading
my %CONFIG = ();
#%CONFIG = (
#	0 => {
#		'_config' => 0,
#		'ip' => 'localhost',
#		'port' => 2102,
#		'_id' => 1,
#		'flags' => 'ats'
#	},
#	1 => {
#		'_config' => 1,
#		'ip' => 'fox21.at',
#		'port' => 80,
#		'_id' => 0,
#		'flags' => 'atc'
#	},
#);

%CONFIG = parseConfig('./tcppipe.conf') if -e './tcppipe.conf'; # read the config from file

my %SOCKETS = ();
my %sockets2id = ();
my $sel = new IO::Select();

sub trim{
	my($str) = @_;
	$str =~ s/^[ \t\r\n]+//s;
	$str =~ s/[ \t\r\n]+$//s;
	$str;
}

sub parseConfig{
	# yeah ik ik, this function is not exactly brilliant
	my($file) = @_;
	my %ret = ();
	if(-e $file && -s $file > 10){
		open FILE, "< $file";
		my $alllines = join '', <FILE>;
		close FILE;
		
		$alllines =~ s/\r//sg;
		my $newlines = '';
		for my $line (split "\n", $alllines){
			$line =~ s/^[ \t]+//;
			next if $line =~ /^#/;
			$newlines .= $line;
			#print "line: >$line<\n";
		}
		
		#print "FILE: >$newlines<\n";
		
		my $serverc = 0;
		my $socketid = 0;
		for my $server (split /server/i, $newlines){
			
			$server = trim $server;
			
			if($server ne ''){
				#print ">$server<\n\n";
				if($server =~ /^\{(.*)\}$/s){
					$server = $1;
					$socketid++;
					my $clientid = $socketid + 1;
					
					$ret{$socketid}{'_config'} = $socketid;
					$ret{$socketid}{'_id'} = $clientid;
					$ret{$clientid}{'_config'} = $clientid;
					$ret{$clientid}{'_id'} = $socketid;
					
					#print ">$server<\n\n";
					if($server =~ /client/si){
						if($server =~ /(client[^\{]*\{([^\}]*)\})/si){
							#print "CLIENT: >$1< >$2<\n";
							my $org = $1;
							my $client = $2;
							$server =~ s/\Q$org\E//si;
							$client = trim $client;
							for my $option (split ';', $client){
								#print "OPTION: >$option<\n";
								my @items = split ' ', $option;
								my $name = shift @items;
								my $val = join ' ', @items;
								#print "$name=$val\n";
								$ret{$clientid}{$name} = $val;
							}
							if($ret{$clientid}{'ip'} =~ /:/){
								($ret{$clientid}{'ip'}, $ret{$clientid}{'port'}) = split ':', $ret{$clientid}{'ip'};
							}
							$ret{$clientid}{'flags'} .= 'c';
						}
					}
					else{
						print STDERR "parseConfig WARNING (2): no 'client' block in 'server' block $serverc\n";
					}
					$server = trim $server;
					for my $option (split ';', $server){
						#print "OPTION: >$option<\n";
						my @items = split ' ', $option;
						my $name = shift @items;
						my $val = join ' ', @items;
						#print "$name=$val\n";
						$ret{$socketid}{$name} = $val;
					}
					$ret{$socketid}{'ip'} = '' unless defined $ret{$socketid}{'ip'};
					if($ret{$socketid}{'ip'} =~ /:/){
						($ret{$socketid}{'ip'}, $ret{$socketid}{'port'}) = split ':', $ret{$socketid}{'ip'};
					}
					$ret{$socketid}{'flags'} .= 's';
					$socketid++; # for $clientid
				}
				else{
					print STDERR "parseConfig ERROR (1): error in server block $serverc\n";
				}
			}
			$serverc++;
		}
	}
	%ret;
}

sub getHashMax{
	my %hash = %{$_[0]};
	if(keys %hash > 0){
		my @ar = reverse sort{$a <=> $b || $a cmp $b} keys %hash;
		int(shift @ar);
	}
	else{
		0;
	}
}

sub addSocket{
	my %newsocket = @_;
	
	my $proto = 'tcp';
	$proto = 'udp' if $newsocket{'flags'} =~ /u/i;
	$proto = 'tcp' if $newsocket{'flags'} =~ /t/i;
	
	my $nid = getHashMax(\%SOCKETS) + 1;
	my $socket = undef;
	if($newsocket{'flags'} =~ /s/i){
		print "new $proto server: $nid, $newsocket{'ip'}:$newsocket{'port'}\n";
		my %new = (
			'LocalAddr' => $newsocket{'ip'},
			'LocalPort' => $newsocket{'port'},
			'Proto' => $proto,
			'Reuse' => 1
		);
		if($newsocket{'flags'} =~ /t/i){
			$new{'Type'} = SOCK_STREAM;
			$new{'Listen'} = SOMAXCONN;
		}
		unless(defined($socket = IO::Socket::INET->new(%new))){
			print STDERR "ERROR: could not create client $newsocket{'ip'}:$newsocket{'port'} ($proto) ($!)\n";
		}
	}
	elsif($newsocket{'flags'} =~ /c/i){
		print "new $proto remote client: $nid, $newsocket{'ip'}:$newsocket{'port'}\n";
		if(defined($socket = IO::Socket::INET->new('PeerAddr' => $newsocket{'ip'}, 'PeerPort' => $newsocket{'port'}, 'Proto' => $proto))){
			#print "NEW SOCKET $nid: >$socket<\n"; sleep 5;
		}
		else{
			print STDERR "ERROR: could not create client $newsocket{'ip'}:$newsocket{'port'} ($proto) ($!)\n";
		}
	}
	else{
		if(defined $newsocket{'socket'}){
			$socket = $newsocket{'socket'};
		}
	}
	
	if(defined $socket){
		my %ret = %newsocket;
		$ret{'id'} = $nid;
		$ret{'socket'} = $socket;
		$ret{'_peer'} = undef unless exists $ret{'_peer'};
		$SOCKETS{$nid} = \%ret;
		
		$sel->add($ret{'socket'});
		$sockets2id{$ret{'socket'}} = $nid;
		$nid;
	}
	else{
		-1;
	}
}

sub getSocketBySocket{
	$SOCKETS{$sockets2id{$_[0]}};
}


for my $id (sort keys %CONFIG){
	my %thisConfig = %{$CONFIG{$id}};
	next if $thisConfig{'flags'} !~ /a/i;
	addSocket(%thisConfig) if $thisConfig{'flags'} =~ /s/i;
}

my $running = 0;
my $end = 0;
while(!$end){
	my $rahandles;
	($rahandles) = IO::Select->select($sel, undef, undef, 0);
	if(!scalar $rahandles){
		$running++;
		if($running >= 600){ # 600 = every minute
			$running = 0;
			print time()." running: ".$sel->count().", ".keys(%SOCKETS)."\n";
		}
		usleep 100 * 1000;
		$end ? last : next;
	}
	
	#print "readable handles: >".@$rahandles."<\n";
	
	for my $socket (@$rahandles){
		next unless defined $SOCKETS{$sockets2id{$socket}};
		my $thisSocket = $SOCKETS{$sockets2id{$socket}};
		
		#print "THIS\n"; for(keys %{$thisSocket}){ print "\t>$_< = >".(defined $$thisSocket{$_} ? $$thisSocket{$_} : '')."<\n"; }
		
		if($$thisSocket{'flags'} =~ /s/i){
			my $proto = 't';
			if($$thisSocket{'flags'} =~ /(t|u)/i){
				$proto = $1;
			}
			my $configPeer = $CONFIG{$$thisSocket{'_id'}};
			
			if($proto eq 't'){
				my $remoteId = addSocket(%{$configPeer});
				my $remoteClient = $SOCKETS{$remoteId};
				my $localClient = $socket->accept();
				my $localId = addSocket('ip' => undef, 'port' => undef, '_id' => $remoteId, 'flags' => 'a'.$proto.'l', 'socket' => $localClient, '_peer' => $$remoteClient{'socket'});
				$$remoteClient{'_id'} = $localId;
				$$remoteClient{'_peer'} = $localClient;
				print "remote: $remoteId, local: $localId ($localClient)\n";
			}
			elsif($proto eq 'u'){
				print "READING UDP\n";
				my $udpline = '';
				eval{
					local $SIG{'ALRM'} = sub{ die time().": alarm\n"; };
					alarm 1;
					$socket->recv($udpline, $MAXSENDBYTES);
					alarm 0;
				};
				
				if($$configPeer{'flags'} =~ /t/i){
					#for(keys %{$configPeer}){ print "peer: >$_< >$$configPeer{$_}<\n"; sleep 1; }
					if(my @ar = grep{$SOCKETS{$_}{'_config'} == $$configPeer{'_config'} && $SOCKETS{$_}{'_id'} == $$configPeer{'_id'}} keys %SOCKETS){
						my $remoteId = shift @ar;
						print "OLD FOUND >$remoteId<\n";
						my $remoteClient = $SOCKETS{$remoteId};
						my $remoteClientSocket = $$remoteClient{'socket'};
						print $remoteClientSocket $udpline if defined $remoteClientSocket;
					}
					else{
						my $remoteId = addSocket(%{$configPeer});
						my $remoteClient = $SOCKETS{$remoteId};
						my $remoteClientSocket = $$remoteClient{'socket'};
						print $remoteClientSocket $udpline if defined $remoteClientSocket;
						print "add new tcp socket: $remoteId\n";
					}
				}
				elsif($$configPeer{'flags'} =~ /u/i){
					#while($udpline =~ /(.)/g){ printf '%03d', ord $1; } print "\n";
					print "UDP LINE to >$$configPeer{'ip'}:$$configPeer{'port'}< ($$configPeer{'flags'}): >".length($udpline)."<\n";
					my $udpsocket = IO::Socket::INET->new('PeerAddr' => $$configPeer{'ip'}, 'PeerPort' => $$configPeer{'port'}, 'Proto' => 'udp');
					print $udpsocket $udpline if defined $udpsocket;
					
					#print "receive\n";
					#my $msg = '';
					#eval{
					#	local $SIG{ALRM} = sub { die "alarm time out\n" };
					#	alarm 5;
					#	$udpsocket->recv($msg, $MAXSENDBYTES) || die "recv: $!\n";
					#	alarm 0;
					#	1;
					#} || die "recv from $$configPeer{'ip'}:$$configPeer{'port'} timed out after 5 seconds\n";
					#print "receive end ($msg)\n";
					#print $socket $msg;
				}
			}
		}
		elsif($$thisSocket{'flags'} =~ /(c|l)/i){
			my $peerSocket = undef;
			if(defined $$thisSocket{'_peer'}){
				if(defined $sockets2id{$$thisSocket{'_peer'}}){
					if(defined $SOCKETS{$sockets2id{$$thisSocket{'_peer'}}}){
						$peerSocket = getSocketBySocket($$thisSocket{'_peer'});
					}
				}
			}
			
			#print time()." READING START\n";
			my $line = '';
			my $n = 0;
			#my $cr = new IO::Select(); # for non-blocking IO. $handle->blocking(0) is B U L L S H I T!
			#$cr->add($socket);
			#while($cr->can_read(0) && $n++ < $MAXSENDBYTES){ # with 0 sec timeout for reading buffer
			#	sysread $socket, my $char, 1;
			#	$line .= $char;
			#}
			#undef $cr;
			
			eval{
				local $SIG{'ALRM'} = sub{ die time().": alarm\n"; };
				alarm 1 if $^O =~ /win/i;
				Time::HiRes::ualarm(250 * 1000) if $^O !~ /win/i;
				#sysread $socket, $line, $MAXSENDBYTES;
				$socket->recv($line, $MAXSENDBYTES);
				alarm 0 if $^O =~ /win/i;
				Time::HiRes::ualarm(0) if $^O !~ /win/i;
			};
			#print time()." READING END ($line)\n";
			
			my $disconnect = 0;
			if(!defined $line || $line eq ''){
				print "disconnect A: $$thisSocket{'id'}\n";
				$sel->remove($socket);
				$socket->close();
				delete $SOCKETS{$$thisSocket{'id'}};
				delete $sockets2id{$socket};
				$disconnect = 1;
				
				if(defined $peerSocket){
					print "disconnect B: $$peerSocket{'id'}\n";
					$sel->remove($$peerSocket{'socket'});
					$$peerSocket{'socket'}->close();
					delete $SOCKETS{$$peerSocket{'id'}};
					delete $sockets2id{$$peerSocket{'socket'}};
				}
				
				next;
			}
			
			if(defined $peerSocket){
				my $ps = $$peerSocket{'socket'};
				print $ps $line;
				print "send from $$thisSocket{'id'} to $$peerSocket{'id'}: >".length($line)."<\n";
			}
			
		}
	}
}



