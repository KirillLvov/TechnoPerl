use 5.016;
use Socket ':all';

sub help {
	say << 'END';
Usage:
	aesrv.pl some/dir
END
	exit;
}

help() unless $ARGV[0];
my $dir = $ARGV[0];
$dir .= "/" unless ($ARGV[0]=~m/\/$/);
unless(-d $dir){
	say "No such directory";
	exit;
};

my $srv;
socket $srv, AF_INET, SOCK_STREAM, IPPROTO_TCP or die "Socket: $!";
setsockopt $srv, SOL_SOCKET, SO_REUSEADDR, 1 or die "Reuseaddr: $!";
bind $srv, sockaddr_in(1230, INADDR_ANY) or die "Bind $!";
my ($port, $addr) = sockaddr_in(getsockname($srv));
listen $srv, SOMAXCONN;
say "Listening on ".inet_ntoa($addr).":".$port;

my %headers;

my %methods = (
	GET => my $GET = sub{
		my $cln = shift;
		my $path = $headers{"uri"};
		if(-d $dir.$path){
			opendir(my $fh, $dir.$path) or do{		
				syswrite($cln, "HTTP/1.1 503 Service Unavailable\nContent-Length: ".length($!)."\n\n$!\n") or warn "Syswrite: $!";
				exit;
			};
			my $out = "";
			$out .= "$_\t" for(grep {! m/^\./} readdir($fh));
			closedir($fh) or warn "Close: $!";
			syswrite($cln, "HTTP/1.1 200 OK\nContent-Length: ".length($out)."\n\n$out\n") or warn "Syswrite: $!";
		}elsif(-f $dir.$path){
			open(my $fh, '<', $dir.$path) or do{
				syswrite($cln, "HTTP/1.1 503 Service Unavailable\nContent-Length: ".length($!)."\n\n$!\n") or warn "Syswrite: $!";
				exit;
			};
			my $out = "";
			$out .= $_ for(<$fh>);
			close($fh) or warn "Close: $!";
			syswrite($cln, "HTTP/1.1 200 OK\nContent-Length: ".length($out)."\n\n$out\n") or warn "Syswrite: $!";
		}else{
			my $err = "Could not open $dir$path: $!";
			syswrite($cln, "HTTP/1.1 404 Not Found\nContent-Length: ".length($err)."\n\n$err\n") or warn "Syswrite: $!";
		};
		say "Get $dir$path";
		exit;
	},
	PUT => my $PUT = sub{
			my $cln = shift;
			my $left = $headers{"content-length"};
			my $path;
			if ($headers{"uri"} =~ m/^.*\/(.+?)^/){
				$path = $1;
			}else{
				$path = $headers{"uri"};
			};
			open(my $fh, '>', $dir.$path) or do {
				syswrite($cln, "HTTP/1.1 503 Service Unavailable\nContent-Length: ".length($!)."\n\n$!\n") or warn "Syswrite: $!";
				exit;
			};
			syswrite($cln, "HTTP/1.1 100 Continue\nContent-Length: 0\n\n") or warn "Syswrite: $!";
			while(<$cln>){
				syswrite($fh, $_, length $_) or warn "Syswrite: $!";
				$left -= length $_;
				last if $left <= 0;
			};
			close($fh) or warn "Close: $!";
			syswrite($cln, "HTTP/1.1 200 OK\nContent-Length: 0\n\n") or warn "Syswrite: $!";
			say "Put $dir$path";
			exit;			
		},
	POST => my $POST = sub{
			my $cln = shift;
			my $path;
			$headers{"content-type"} =~ m/boundary=(.+)$/;
			my $delimiter = $1;
			syswrite($cln, "HTTP/1.1 100 Continue\nContent-Length: 0\n\n") or warn "Syswrite: $!";
			if(<$cln> =~ m/$delimiter/){
				while(<$cln>){
					$path = $1 if($_ =~ m/Content-Disposition:.*filename="(.+)"/);
					last if($_ =~ m/^\015?\012$/);
				};	
				$path = $1 if $path =~ m/^.*\/(.+?)$/;	
				open(my $fh, '>', $dir.$path) or do {
					syswrite($cln, "HTTP/1.1 503 Service Unavailable\nContent-Length: ".length($!)."\n\n$!\n") or warn "Syswrite: $!";
					exit;
				};
				while(<$cln>){
					last if $_ =~ m/$delimiter/;
					syswrite($fh, $_) or warn "Syswrite: $!";
				};	
				close($fh) or warn "Close: $!";
				syswrite($cln, "HTTP/1.1 200 OK\nContent-Length: 0\n\n") or warn "Syswrite: $!";
			}else{
				syswrite($cln, "HTTP/1.1 400 Bad Request\nContent-Length: 0\n\n") or warn "Syswrite: $!";
			};		
			say "Put $dir$path";	
			exit;
		},
	DELETE => my $DELETE = sub{
			my $cln = shift;
			my $path = $headers{"uri"};
			if(-f $dir.$path){
				unlink $dir.$path;
				syswrite($cln, "HTTP/1.1 200 OK\nContent-Length: 0\n\n") or warn "Syswrite: $!";
			}else{
				my $err = "No such file $dir$path: $!";
				syswrite($cln, "HTTP/1.1 404 Not Found\nContent-Length: ".length($err)."\n\n$err\n") or warn "Syswrite: $!";
			};
			say "Delete $dir$path";
			exit;
		},
);

while(my $peer = accept my $cln, $srv){
	if(my $pid = fork()){
		close $cln;
		say "$$: Ready to connect";
	}else{
		close $srv;
		say "$$: I'm working with client";
		$cln->autoflush(1);
		my ($port, $addr) = sockaddr_in($peer);
		say "Accept from ".inet_ntoa($addr).":".$port;
		<$cln> =~ m/^([A-Z]+)\s\/(.+)\sHTTP/ or do{
			syswrite($cln, "HTTP/1.1 400 Bad Request\nContent-Length: 0\n\n") or warn "Syswrite: $!";
			exit;
		};
		($headers{"method"}, $headers{"uri"}) = ($1, $2);
		while(<$cln>){
			$headers{lc($1)} = $2 if($_ =~ m/^([\w-]+):\s+(.+?)\015?\012$/);
			last if($_ =~ m/^\015?\012$/);
		};
		eval{
			$methods{$headers{"method"}}->($cln);
			1;
		}or do{
			syswrite($cln, "HTTP/1.1 405 Method Not Allowed\nContent-Length: 0\n\n") or warn "Syswrite: $!";
		};
		exit;
	};	
};
