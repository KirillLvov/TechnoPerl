package Local::Context;

use 5.016000;
use warnings;

use Exporter 'import';

our @ISA = qw(Exporter);
our %EXPORT_TAGS = ( 'all' => [ qw(
	cmd param keys env host port
) ] );
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT = qw(
	cmd param keys env host port
);
our $VERSION = '0.01';

use Class::XSAccessor {
		constructor => 'new',
		accessors => [qw(cmd param keys env host port)],
	};

1;
