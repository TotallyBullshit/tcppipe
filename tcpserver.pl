
use strict;
use IO::Select;
use IO::Socket::INET;

my $sel = new IO::Select();
my $socketserver = IO::Socket::INET->new('LocalAddr' => 'localhost', 'LocalPort' => 6001, 'Proto' => 'tcp', 'Reuse' => 1, 'Type' => SOCK_STREAM, 'Listen' => SOMAXCONN);
$sel->add($socketserver);

my $end = 0;
while(!$end){
	my $rahandles;
	($rahandles) = IO::Select->select($sel, undef, undef, 0);
	if(!scalar $rahandles){
		print time().": sleep 1\n";
		sleep 1;
		$end ? last : next;
	}
	
	print "readable handles: >".@$rahandles."<\n";
	
	for my $socket (@$rahandles){
		if($socket == $socketserver){
			my $client = $socket->accept();
			$client->autoflush(1);
			$sel->add($client);
		}
		else{
			my $line = '';
			eval{
				local $SIG{'ALRM'} = sub{ die time().": alarm\n"; };
				alarm 1;
				$socket->recv($line, 1024);
				alarm 0;
			};
			if(!defined $line || $line eq ''){
				print "disconnect\n";
				$sel->remove($socket);
				next;
			}
			$socket->send("recv: >$line<\n");
			print "from client: >$line<\n";
		}
	}
}
