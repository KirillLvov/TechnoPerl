use 5.016;
use Socket ':all';
use IO::Select;
use Fcntl qw(F_SETFL O_NONBLOCK);
use Getopt::Long;
use Term::ReadLine;

my $term = Term::ReadLine->new('client');
$term->Attribs->{completion_entry_function} = $term->Attribs->{list_completion_function};
$term->Attribs->{completion_word} = [qw(ls cp mv rm)];
$term->using_history();
$term->ReadHistory('history');

my $mode;
GetOptions('m=s' => \$mode);
$mode = "in" unless $mode;

my $cln;
if($mode eq "in"){
	socket $cln, AF_INET, SOCK_STREAM, IPPROTO_TCP or die "Socket: $!";
	my $host = 'localhost';
	my $addr = gethostbyname($host);
	my $sa = sockaddr_in(1231, $addr) or die "Sockaddr_in: $!";
	connect($cln, $sa) or die "Connect: $!";
};
if($mode eq "un"){
	socket $cln, AF_UNIX, SOCK_STREAM, 0 or die "Socket: $!";
	my $sa = sockaddr_un("$ENV{HOME}/unix-socket.sock") or die "Sockaddr_in: $!";
	connect($cln, $sa) or die "Connect: $!";
};

my $sel = IO::Select->new();
for(\*STDIN, $cln){
	fcntl($_, F_SETFL, O_NONBLOCK) or die $!;
	$sel->add($_);
};

while(){
	for my $fd ($sel->can_read()){
		while(<$fd>){
			if($fd == $cln){
				chomp;
				say $_;
			}else{
				$term->addhistory($_);
				if($_ =~ m/^!(.*)$/){
					say "Shell escape";
					say qx($1);
				}else{
					syswrite($cln, $_) or warn "Syswrite: $!";
				};
			};
		};
		die $! unless $!{EAGAIN};
	};
};

END {
	$term->WriteHistory('history') or warn "Write history error\n";
}
