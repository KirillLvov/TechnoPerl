use 5.016;
use DDP;
use Getopt::Long;
use Socket ':all';
use lib "Local-Storage/lib";
use Local::Storage;

my $mode;
my $maxconn;

sub help {
	say << 'END';
Usage:
	server.pl [-m][mode] [-mc][maxconn] [-h] /path/to/somewhere
	-m	un	- use unix socket
	 	in 	- use host:port
	-mc	maxconn	- set SOMAXCONN
	-h | --help	- print usage and exit
END
	exit;
}

GetOptions(
	'm=s' => \$mode, 
	'mc=i' => \$maxconn,
	'h|help' => \&help,
);
help() unless $ARGV[0];
$mode = "in" unless $mode;
$maxconn = SOMAXCONN unless $maxconn;

my $storage = Local::Storage->new($ARGV[0]) or die $!;

my $srv;
if($mode eq "in"){
	socket $srv, AF_INET, SOCK_STREAM, IPPROTO_TCP or die "Socket: $!";
	setsockopt $srv, SOL_SOCKET, SO_REUSEADDR, 1 or die "Reuseaddr: $!";
	bind $srv, sockaddr_in(1231, INADDR_ANY) or die "Bind $!";
	my ($port, $addr) = sockaddr_in(getsockname($srv));
	listen $srv, $maxconn;
	say "Listening on ".inet_ntoa($addr).":".$port;
}
if($mode eq "un"){
	socket $srv, AF_UNIX, SOCK_STREAM, 0 or die "Socket: $!";
	setsockopt $srv, SOL_SOCKET, SO_REUSEADDR, 1 or die "Reuseaddr: $!";
	unlink "$ENV{HOME}/unix-socket.sock" or die "Delete unix-socket: $!" if -S "$ENV{HOME}/unix-socket.sock";
	bind $srv, sockaddr_un("$ENV{HOME}/unix-socket.sock") or die "Bind: $!";
	listen $srv, $maxconn;
	say "Listening on $ENV{HOME}/unix-socket.sock";
}

while(my $peer = accept my $cln, $srv){
	if(my $pid = fork()){
		close $cln;
		say "$$: Ready to connect";
	}else{
		close $srv;
		say "$$: I'm working with client";
		$cln->autoflush(1);
		if($mode eq "in"){
			my ($port, $addr) = sockaddr_in($peer);
			say "Accept from ".inet_ntoa($addr).":".$port;
		}
		while(<$cln>){
			chomp $_;		
			say "$$: Got line: $_";
			my ($cmd,@args) = split / /,$_; 
			my $answer = $storage->execute($cmd,@args);
			print {$cln} $answer or warn "Syswrite: $!";
		};
		exit;
	};	
};
