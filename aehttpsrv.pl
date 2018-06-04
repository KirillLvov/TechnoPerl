use 5.016;
use warnings;
use AnyEvent::Socket;
use AnyEvent::Handle;
use lib "Local-Storage/lib";
use Local::Storage;
use JSON;
use DDP;

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
my $storage = Local::Storage->new($ARGV[0]) or die $!;

my %headers;
my $cv = AE::cv;

tcp_server '127.0.0.1', 1231, sub {
	say "Client connected";
	my $fh = shift;
	my $h; $h = AnyEvent::Handle->new(
		fh => $fh,
		on_error => sub {
			$h->destroy;
			warn "Client disconnected: $!";
		},
		timeout => 60,
	);
	my $reader; $reader = sub {
		$h->push_read(line => sub {
			if($_[1] =~ m/^([A-Z]+)\s+\/(.*)\s+HTTP/){
				($headers{"method"}, $headers{"uri"}) = ($1, $2);
				$reader->();
			}elsif($_[1] =~ m/^([\w-]+):\s+(.+?)$/){
				$headers{lc($1)} = $2;
				$reader->();
			}else{
		
				if($headers{"method"} eq "GET") {
					my $path = $headers{"uri"};
					say "GET $dir$path";
					if(-d $dir.$path){
						my $out = $storage->execute("ls",$path);
						if($out =~ m/^(?:No)|(?:Out)/){
							$h->push_write("HTTP/1.1 404 Not Found\nContent-Length: 0\n\n");
						}else{
							$h->push_write("HTTP/1.1 200 OK\nContent-Length: ".(length($out)+1)."\n\n$out\n");
						};
					}elsif(-f $dir.$path){
						my @range = ($1,$2) if ($headers{"range"} =~ m/bytes=(\d+)-(\d+)/);
						my ($size,$data);
						my $left = -s $dir.$path;
						open(my $r, '<:raw', $dir.$path) or do {
							$h->push_write("HTTP/1.1 503 Service Unavailable\nContent-Length: 0\n\n");
							return;
						};
						if (defined $range[0]){
							if ($range[1] > $left){
								$h->push_write("HTTP/1.1 400 Bad Request\nContent-Length: 0\n\n");
								return;
							};
							$left = $range[1] - $range[0];
							sysread($r, $data, $range[0]) or warn "Sysread: $!";
						};
						$h->push_write("HTTP/1.1 200 OK\nContent-Length: ".$left."\n\n");
						my $write_data; $write_data = sub {
							$size = $left>=$h->{read_size} ? $h->{read_size} : $left;
							sysread($r, $data, $size) or warn "Sysread: $!";
							$h->push_write($data);
							$left -= $size;
							if($left>0){
								if($h->{wbuf}){
									say "Buffer is not empty. Left $left bytes";
									$h->on_drain(sub {
										$h->on_drain(undef);	
										$write_data->();
									});
								}else{
									$write_data->();
								};
							}else{
								undef $write_data;
								close($r) or warn "Close file: $!";		
							};			
						};$write_data->();
					}else{
						 warn "Could not open $dir$path";
						$h->push_write("HTTP/1.1 404 Not Found\nContent-Length: 0\n\n");
					};
				
				}elsif($headers{"method"} eq "PUT"){
					my $left = $headers{"content-length"};
					my $path;
					if ($headers{"uri"} =~ m/^.*\/(.+?)^/){
						$path = $1;
					}else{
						$path = $headers{"uri"};
					};
					say "PUT $dir$path";
					open(my $w, '>:raw', $dir.$path) or do {
						$h->push_write("HTTP/1.1 503 Service Unavailable\nContent-Length: 0\n\n");
						return;
					};
					$h->push_write("HTTP/1.1 100 Continue\nContent-Length: 0\n\n");
					my $read_data; $read_data = sub {
						$h->unshift_read(chunk => $left>=$h->{read_size} ? $h->{read_size} : $left, sub {
							my (undef, $data) = @_;
							syswrite($w, $data) or warn "Syswrite: $!";
							$left -= length $data;
							if($left){
								$read_data->();
							}else{
								undef $read_data;
								close($w) or warn "Close: $!";
								$h->push_write("HTTP/1.1 200 OK\nContent-Length: 0\n\n");
							};	
						});
					};$read_data->();

				}elsif(($headers{"method"} eq "POST") && ($headers{"content-type"} eq "application/json")){
					my $left = $headers{"content-length"};
					my $json;
					$h->push_write("HTTP/1.1 100 Continue\nContent-Length: 0\n\n");
					my $read_data; $read_data = sub {
						$h->unshift_read(chunk => $left>=$h->{read_size} ? $h->{read_size} : $left, sub {
							$json .= $_[1];
							$left -= length $_[1];
							if($left){
								$read_data->();
							}else{
								undef $read_data;
								my $href =  decode_json($json);
								my $out = $storage->execute($href->{cmd},$href->{arg1},$href->{arg2});
								if($out =~ m/Success/){
									$h->push_write("HTTP/1.1 200 OK\nContent-Length: 0\n\n");
								}else{
									$h->push_write("HTTP/1.1 404 Not Found\nContent-Length: 0\n\n");
								};
								say "POST cmd=".$href->{cmd}." arg1=".$href->{arg1}." arg2=".$href->{arg2};
							};	
						});
					};$read_data->();
				
				}elsif($headers{"method"} eq "DELETE"){
					my $path = $headers{"uri"};
					say "DELETE $dir$path";
					my $out = $storage->execute("rm",$path);
					if($out =~ m/Success/){
						$h->push_write("HTTP/1.1 200 OK\nContent-Length: 0\n\n");
					}else{
						$h->push_write("HTTP/1.1 404 Not Found\nContent-Length: 0\n\n");
					};
				
				}else{
					$h->push_write("HTTP/1.1 400 Bad Request\nContent-Length: 0\n\n");
				};
				$reader->();
			};	
		});	
	};$reader->();
},
sub {
	my ($fh, $host, $port) = @_;
	say "Listening on $host:$port";
};

$cv->recv;
