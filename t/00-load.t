#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'CoffeeML' );
}

diag( "Testing CoffeeML $CoffeeML::VERSION, Perl $], $^X" );
