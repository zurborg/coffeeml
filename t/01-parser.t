#!perl -T

use Test::Most;

BEGIN {
	use_ok( 'CoffeeML::Parser' );
}

my $p = CoffeeML::Parser->new;

use Data::Dumper;

is_deeply($p->parse(\''), {
	'anonymous_element_id' => 0,
	'defaults' => {
		'script' => {
			'type' => 'text/javascript'
		},
		'style' => {
			'type' => 'text/css'
		}
	},
	'capture_raw_block' => 0,
	'indent' => [],
	'capture_js_block' => 0,
	'level' => [],
	'struct' => [],
	'coffee' => [],
	'opts' => {
	'indent' => 0
	},
	'root' => [
		[]
	],
	'assigns' => {}
});

is_deeply($p->parse(\'Hello')->{root}, [[{
	indent => 0,
	line => 'Hello'
}]]);

is_deeply($p->parse(\'%p Hello')->{root}, [[{
	indent => 0,
	line => '%p Hello',
	action => '%p Hello',
	attrs => {},
	element => 'p',
	rest => 'Hello'
}]]);

#diag Dumper($p->parse(\'%p Hello')->{root});

done_testing;