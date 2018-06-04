use 5.016;
use Term::ReadLine;
use DDP;

my $term = Term::ReadLine->new('client');
$term->Attribs->{completion_entry_function} = $term->Attribs->{list_completion_function};
$term->using_history();
$term->ReadHistory('history');

#Find braces { , } and construct tree of templates
sub braces{
	my $parse = shift;
	pos($parse) = shift;
	my %tree;
	my @out;
	while(pos($parse) < length($parse)){
		#Opening braces
		if($parse =~ m/\G,?([^\{\},]+)\/\{/gc){
			my $m1 = $1;
			@out = braces($parse, pos($parse));
			$tree{$m1} = $out[0];
			pos($parse) = $out[1];
		#No braces, only enumeration
		}elsif($parse =~ m/\G,?([^\{\},]+),?/gc){
			$tree{$1} = 1;
		#Closing braces
		}elsif($parse =~ m/\G\}/gc){
			return (\%tree, pos($parse));
		};
	};
	return (\%tree, pos($parse));
}

#Use tree template to list fitted directories
sub template {
	my $parent_dir = shift;
	my %tree = %{shift @_};
	my %paths = %{shift @_};
	my $out;
	foreach my $child (keys %tree){
		#Separation regular part from part needed to parse
		if ((my $reg, my $parse) = $child =~ m/(?|^([^\?\[\*\\]*+\/)(.*[\?\[\*\\].*)$|^()(.*[\?\[\*\\].*)$)/){
			return \%paths unless (-d $parent_dir."/".$reg);
			$parse =~ s/\?/./g;
			$parse =~ s/\*/.*/g;
			#Create regex like string
			my $temp = qr/$parse/;
			opendir(my $d, $parent_dir."/".$reg) or die $!;
			#Find subdirectories which are fit to template
			for my $dir (grep {! m/^\./} readdir($d)){
				if($dir =~ m/^$temp$/){
					if($tree{$child} == 1){
						$paths{$parent_dir."/".$reg.$dir}++;
					}else{
						$out = template($parent_dir."/".$reg.$dir,$tree{$child},\%paths);
						%paths = %{$out};
					};
				};
			};
			closedir($d) or warn $!;
		}elsif(-d $parent_dir."/".$child){
			if($tree{$child} == 1){
				$paths{$parent_dir."/".$child}++;
			}else{
				$out = template($parent_dir."/".$child,$tree{$child}, \%paths);
				%paths = %{$out};
			};
		};
	};
	return \%paths;
}

#Read template
my @out;
my %paths;
while ( defined ($_ = $term->readline("> ")) ){
	$term->addhistory($_);
	@out = braces($_,0);
	p %{template("",$out[0],\%paths)};
};

END {
	$term->WriteHistory('history') or warn "Write history error\n";
}
