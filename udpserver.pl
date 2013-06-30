
use strict;
use IO::Socket;

my $server = IO::Socket::INET->new(LocalPort => 6001, Proto => 'udp');

while(1){
	while(my $him = $server->recv(my $datagram, 1024 * 8)){
		print "data: >$datagram<\n";
		$server->send("recv: >$datagram<");
	}
	print "buffer overflow\n";
}

print "end\n";
