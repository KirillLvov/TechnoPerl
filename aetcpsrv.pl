use 5.016;
use warnings;
use AnyEvent::Socket;
use AnyEvent::Handle;
use lib "Local-Storage/lib";
use Local::Storage;

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
			$reader->();
			my (undef, $line) = @_;
			say "receive $line";

			if($line =~ m/^put\s+(\d+)\s+(.+)/){
				my ($left,$file) = ($1,$2);
				say "put $left bytes to $dir$file";
				$storage->mkfile($file) unless -f $dir.$file;
				open(my $fd, '>:raw', $dir.$file) or warn "Open for write: $!";
				my $read_data; $read_data = sub {
					$h->unshift_read(chunk => $left>=$h->{read_size} ? $h->{read_size} : $left, sub {
						my (undef, $data) = @_;
						syswrite($fd, $data) or warn "Syswrite: $!";
						$left -= length $data;
						say "Recieved ".(length $data)." bytes. Left $left";
						if($left){
							$read_data->();
						}else{
							undef $read_data;
							say "Finish reading of  data";
							$h->push_write("Success\n");
							close($fd) or warn "Close file: $!";
						};	
					});
				};$read_data->();
			
			}elsif($line =~ m/^(?:get||cat)\s+(.+)/){
				my $file = $1;
				if(-f $dir.$file){
					my $left = -s $dir.$file;
					$h->push_write("Ready $left\n");
					say "File size = $left";
					open(my $fd, '<:raw', $dir.$file) or warn "Open for read: $!";
					my ($size,$data);
					my $write_data; $write_data = sub {
						$size = $left>=$h->{read_size} ? $h->{read_size} : $left;
						sysread($fd, $data, $size) or warn "Sysread: $!";
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
							say "Finish transmition of data";
							close($fd) or warn "Close file: $!";		
							undef $write_data;
							$h->push_write("Success\n");
						};			
					};$write_data->();
				}else{
					my $out = "No such file\n";
					$h->push_write("Ready ".(length $out)."\n".$out);
				};
			
			}elsif($line eq "exit"){
				$h->push_write("Goodbye!\n");

			}else{
				my ($cmd,@args) = split / /,$line,3;
				my $out = $storage->execute($cmd,@args);
				$h->push_write("Ready ".(length $out)."\n".$out);
			};
		});
	};$reader->();
},
sub {
	my ($fh, $host, $port) = @_;
	say "Listening on $host:$port";
};

$cv->recv;
