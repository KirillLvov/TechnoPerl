package Local::Storage;

use 5.016000;
use strict;
use warnings;

our $VERSION = '0.01';

my $dir;

sub new {
	my $class = shift;
	my $dir = shift;
	$dir =~ s/ //g;
	return undef unless -d $dir;
	$dir .= "/" if $dir =~ m/[^\/]$/;
	my $self = bless{dir => $dir},$class;
	return $self;
}

sub dir {
	my $self = shift;
	$self->{dir} = shift if @_;
	return $self->{dir};
}

sub ls {
	my $self = shift;
	my $path = shift;
	return "Out of directory" unless $self->isin($path);
	return "No such directory" unless -d $self->{dir}.$path;
	opendir(my $d, $self->{dir}.$path) or warn $!;
	my $out;
	$out .= "$_\t" foreach(grep {! m/^\./} readdir($d));
	closedir($d) or warn $!;
	return $out;
}
 
sub objects {
	my $self = shift;
	opendir(my $d, $self->{dir}) or warn $!;
	my $out;
	$out .= "$_\t" foreach(grep {! m/^\./} readdir($d));
	closedir($d) or warn $!;
	return $out;
}

sub contains {
	my $self = shift;
	my $file = shift;
	return "Out of directory" unless $self->isin($file);
	return "No such file" unless -f $self->{dir}.$file;
	open(my $f, '<', $self->{dir}.$file) or die $!;
	my $out;
	$out .= $_ while(<$f>);
	close($f) or warn $!;
	return $out;
}

sub mkdir {
	my $self = shift;
	my $path = shift;
	return "Out of directory" unless $self->isin($path);
	my $add = "";
	foreach(split /\//,$path){
		$add .= "$_/"; 
		mkdir $self->{dir}.$add or warn $!;
	};
	return "Success";
}

sub mkfile:method {
	my $self = shift;
	my ($path,$text) = @_;
	return "Out of directory" unless $self->isin($path);
	$path =~ m/^(.*)\/.*?$/;
	unless(-d $self->{dir}.$1){
		my $add = "";
		foreach(split /\//,$1){
			$add .= "$_/"; 
			mkdir $self->{dir}.$add or warn $!;
		};
	};	
	open(my $f, '>', $self->{dir}.$path) or die $!;
	my $status = syswrite($f, $text, length $text);
	return "Error" unless defined $status;
	return "Success";
}

sub rm {
	my $self = shift;
	my $path = shift;
	return "Out of directory" unless $self->isin($path);
	if(-f $self->{dir}.$path){
		unlink $self->{dir}.$path or warn $!;
	}elsif(-d $self->{dir}.$path){
		opendir(my $d, $self->{dir}.$path) or warn $!;
		foreach(grep {! m/^\./} readdir($d)){
			$self->rm($path."/".$_);
		} 
		closedir($d) or warn $!;
		rmdir $self->{dir}.$path or warn $!;
	};
	return "Success";
}

sub isin {
	my $self = shift;
	my $path = shift;
	my $cur = 0;
	foreach(split /\//,$path){
		if($_ eq ".."){
			$cur--;
			last if $cur < 0;
		}else{
			$cur++;
		};
	};
	if($cur < 0){
		return 0;
	}else{
		return 1;
	};
}
	
sub execute {
	my $self = shift;
	my ($cmd, @args) = @_;
	return $self->ls($args[0]) if $cmd eq "ls";
	return $self->objects() if $cmd eq "objects";
	return $self->contains($args[0]) if $cmd eq "contains";
	return $self->mkdir($args[0]) if $cmd eq "mkdir";
	return $self->mkfile(@args) if $cmd eq "mkfile";
	return $self->rm($args[0]) if $cmd eq "rm";
	return "No such command";
}

1;
