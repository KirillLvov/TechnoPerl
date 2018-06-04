# TechnoPerl
use 5.016;
use Getopt::Long;
Getopt::Long::Configure ("bundling");
use Term::ReadLine;

my %comHash = (
	#@ARGS = ($path, @args)
	"ls" => my $ls = sub {
			return "Give no arguments" if($_[1]);
			return qx(ls -lA $_[0]);
		}, 
	"cp" => my $cp = sub {
			return "Give 1 or 2 arguments" if (!$_[1] || $_[3]);
			if($_[2]){
				return qx(cp $_[1] $_[0]$_[2]);
			}else{
				return qx(cp $_[1] $_[0]$_[1]);
			};
		}, 
	"mv" => my $mv = sub {
			return "Give 2 arguments" if (!$_[1] || !$_[2] || $_[3]);
			rename $_[0].$_[1],$_[0].$_[2];
			return "";
		}, 
	"rm" => my $rm = sub {
			return "Give 1 argument" if (!$_[1] || $_[2]);
			unlink $_[0].$_[1];
			return "";
		},
);

#@ARGS = ($verbose, $command, \@args)
sub verbose {
	my $out = "Execute command '$_[1]' with arguments (@{$_[2]})\n" if($_[0] >= 1);
	$out .= "qx(ls -lA $_[2]->[0])" if($_[0] >= 2 && $_[1] eq "ls");
	$out .= "qx(cp $_[2]->[1] $_[2]->[0]$_[2]->[2])" if($_[0] >= 2 && $_[1] eq "cp" && $_[2]->[2]);
	$out .= "qx(cp $_[2]->[1] $_[2]->[0]$_[2]->[1])" if($_[0] >= 2 && $_[1] eq "cp" && !$_[2]->[2]);
	$out .= "qx(rename $_[2]->[0]$_[2]->[1] $_[2]->[0]$_[2]->[2] $_[2]->[0]$_[2]->[1])" if($_[0] >= 2 && $_[1] eq "mv");
	$out .= "qx(unlink $_[2]->[0]$_[2]->[1])" if($_[0] >= 2 && $_[1] eq "rm");
	return $out;
}

sub help {
	say << 'END';
Usage:
	client.pl [-h] [-v] /path/to/somewhere
	-h | --help	- print usage and exit
	-v | --verbose	- be verbose

Commands:

ls			listing files and directories in chosen directory
cp source [target]	copy source file to remote target file
mv source target	rename remote source file to target file
rm target		remove remote target file
t!...			shell escape
END
	exit;
}

my $verbose = 0;

GetOptions(
	'v|verbose+' => \$verbose, 
	'h|help' => \&help,
);
help() unless $ARGV[0];

my $path = $ARGV[0];
$path .= ("/")x !($ARGV[0]=~m/\/$/);
die "No such directory" unless -d $path;

my $term = Term::ReadLine->new('client');
$term->Attribs->{completion_entry_function} = $term->Attribs->{list_completion_function};
$term->Attribs->{completion_word} = [qw(ls cp mv rm)];
$term->using_history();
$term->ReadHistory('history');

my @args;
my $command;

while ( defined ($_ = $term->readline("> ")) ){
	if($_ =~ s/^!//){
		say "Shell escape" if $verbose; 
		say qx($_);
	} else {
		@args = split/ /,$_;
		$command = shift @args;
		say verbose($verbose,$command,[$path,@args]) if $verbose;
		eval{
			say $comHash{$command}->($path,@args);
			1;
		} or warn "No such command\n";
	};
};

END {
	$term->WriteHistory('history') or warn "Write history error\n";
}
