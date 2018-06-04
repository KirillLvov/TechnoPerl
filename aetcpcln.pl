use 5.016;
use AnyEvent::Socket;
use AnyEvent::Handle;
use lib "$ENV{HOME}/perl5/lib/perl5";
use AnyEvent::ReadLine::Gnu;
use Getopt::Long;
Getopt::Long::Configure ("bundling_override");

sub help {
	say << 'END';
Usage:
	aecln.pl -v -tcp [host:port]

Commands:

cat some/file		show the content of the file
cp one/file1 two/file2	copy <one/file1> to <two/file2>
exit			stop the client session
get some/file		upload the file
help			listing available commands
ls [path/to]		listing files and directories and its size
mkdir some/dir		create the directory
mkfile some/file [text]	create the file with given content
mv one/file1 one/file2	rename <file1> to <file2> in <one> directory
objects			listing directory
put some/file		upload the file
rm some/file		remove <some/file>
END
}
my $verbose = 0;
my @tcp;
GetOptions(
	'v|verbose+' => \$verbose, 
	'tcp=s' => \$tcp[0],
);
if($tcp[0] =~ m/^(\d+\.\d+\.\d+\.\d+):(\d+)$/){
	($tcp[0], $tcp[1]) = ($1, $2);
}else{
	help();
};

my $rl;

my $cv = AE::cv;

tcp_connect $tcp[0], $tcp[1], sub {
	my ($fh,$host,$port) = @_;
	say "Connected to $host:$port";
	my $h; $h = AnyEvent::Handle->new(
		fh => $fh,
		on_error => sub {
			$h->destroy;
			$rl->WriteHistory('history') or warn "Write history error\n";
			$cv->send;
		},
		timeout => 60,
		read_size => 10000,	
	);
	$rl = AnyEvent::ReadLine::Gnu->new(
		prompt => ">",
		on_line => sub {
			my $line = shift;
			$rl->print("Command: $line\n") if ($verbose > 0);
			if($line =~ m/^put\s+(.+)/){
				my $file = $1;
				if(-f $file){
					my $left = -s $file;
					my @a = split /\//,$file;
					$h->push_write("put $left ".(pop @a)."\n");
					open(my $fd, '<:raw', $file) or warn "Open for read: $!";
					my ($size,$data);
					my $write_data; $write_data = sub {
						if($left>0){
							$size = $left>=$h->{read_size} ? $h->{read_size} : $left;
							sysread($fd, $data, $size) or warn "Sysread: $!";	
							$h->push_write($data);
							$left -= $size;
							if($h->{wbuf}){
								$h->on_drain(sub {
									$h->on_drain(undef);
									$write_data->();
								});
							}else{
								$write_data->();
							};
						}else{
							close($fd) or warn "Close: $!";
							undef $write_data;
						};	
					};$write_data->();
					$h->push_read(line => sub {
						$rl->print(@_[1]) if ($verbose > 0);
					});
				}else{
					$rl->print("No such file\n");
				};

			}elsif($line eq "exit"){
				$h->push_write("exit\n");
				$h->push_read(line => sub {
					$rl->print($_[1]."\n") if ($verbose > 0);
				});
				$rl->WriteHistory('history') or warn "Write history error\n";
				$cv->send;
			
			}elsif($line eq "help"){
				$rl->hide;
				help();
				$rl->show;

			}elsif($line =~ m/^!(.*)$/){
				$rl->print(qx($1));
		
			}elsif($line =~ m/^(\w+)\s*(.*)/){
				my $cmd = $1;
				$h->push_write($line."\n");
				my $file;
				if($cmd eq "get"){
					$line =~ m/^get\s+(.+)/;
					my @a = split /\//,$1;
					$file = pop @a;
				};
				$h->push_read(line => sub {
					if($_[1] =~ m/^Ready\s+(\d+)/){
						my $left = $1;
						my $fd;
						if($cmd eq "get"){
							open($fd, '>:raw', $file) or warn "Open for write: $!";
						};
						my $read_data; $read_data = sub {
							$h->unshift_read(chunk => $left>=$h->{read_size} ? $h->{read_size} : $left, sub {
								my (undef, $data) = @_;
								$left -= length $data;
								if($cmd eq "get"){
									syswrite($fd, $data) or warn "Syswrite: $!";
								}else{
									$rl->print($data);
								};
								if($left){
									$read_data->();
								}else{
									undef $read_data;
									if($cmd eq "get"){
										close($fd) or warn "Close file: $!";
									};
								};	
							});
						};$read_data->();
						if($cmd eq "get" || $cmd eq "cat"){
							$h->push_read(line => sub {
								$rl->print($_[1]."\n") if ($verbose > 0);
							});
						};
					}else{
						$rl->print("Error\n");
					};
				});

			}else{
				$rl->WriteHistory('history') or warn "Write history error\n";
				$cv->send;
			};
		},
	);
	$rl->Attribs->{completion_entry_function} = $rl->Attribs->{list_completion_function};
	$rl->Attribs->{completion_word} = [qw(cat cp exit get help ls mkdir mkfile mv objects put rm)];
	$rl->using_history();
	$rl->ReadHistory('history');
};

$SIG{INT} = sub {
	$rl->WriteHistory('history') or warn "Write history error\n";
	$cv->send;
};

$cv->recv;
