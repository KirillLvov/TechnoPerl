package Local::Command;

use 5.016000;
use warnings;

our $VERSION = '0.01';

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

sub new {
	my $class = shift;
	my $verb = shift;
	my $path = shift;
	my $self = bless {verb => $verb, path => $path}, $class;
	return $self;
}

#@ARGS = ($verbose, $command, [$path,@args])
sub verbose {
	my $self = shift;
	say "Execute command '$_[1]' with arguments (@{$_[2]})" if($self->{verb} >= 1);
	say "qx(ls -lA $_[2]->[0])" if($self->{verb} >= 2 && $_[1] eq "ls");
	say "qx(cp $_[2]->[1] $_[2]->[0]$_[2]->[2])" if($self->{verb} >= 2 && $_[1] eq "cp" && $_[2]->[2]);
	say "qx(cp $_[2]->[1] $_[2]->[0]$_[2]->[1])" if($self->{verb} >= 2 && $_[1] eq "cp" && !$_[2]->[2]);
	say "qx(rename $_[2]->[0]$_[2]->[1],$_[2]->[0]$_[2]->[2])" if($self->{verb} >= 2 && $_[1] eq "mv");
	say "qx(unlink $_[2]->[0]$_[2]->[1])" if($self->{verb} >= 2 && $_[1] eq "rm");
}

sub execute {
	my $self = shift;
	if($_ =~ s/^!//){
		say "Shell escape" if $self->{verb}; 
		return qx($_);
	} else {
		my @args = split/ /,$_;
		my $command = shift @args;
		$self->verbose($self->{verb},$command,[$self->{path},@args]) if $self->{verb};
		eval{
			return $comHash{$command}->($self->{path},@args); 
			1;
		} or warn "No such command\n";
	};
}

1;
