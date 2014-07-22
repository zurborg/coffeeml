package CoffeeML::Parser;

use Modern::Perl;
use Carp;
use Clone ();

=head1 NAME

CoffeeML::Parser - Parser for CoffeeML

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

    use CoffeeML::Parser;

    my $document = CoffeeML::Parser->parse($file|\$stream);

=head1 DESCRIPTION

This module is used internal only

=cut

use constant EOL => "\n";

my $re_html_element = qr{[a-z][a-z0-9]*}i;
my $re_css_class = qr{[a-z][a-z0-9\-]*}i;
my $re_css_id = qr{[a-z][a-z0-9\_]*}i;

=head1 METHODS

=head2 new

=cut

sub new {
	my ($class, $options) = @_;

	$options ||= {};
	$options->{indent} ||= 0;
	
	my $self = {
		opts => $options
	};
	
	$self->{fastlane} = {};
	{
		local %_ = (
			href     => [qw[ a base area link ]],
			src      => [qw[ script frame iframe img ]],
			name     => [qw[ meta input button map param select textarea ]],
			cite     => [qw[ blockquote q ]],
			clear    => [qw[ br ]],
			profile  => [qw[ head ]],
			lang     => [qw[ html ]],
			for      => [qw[ label ]],
			value    => [qw[ li option ]],
			type     => [qw[ ol ul style ]],
			label    => [qw[ optgroup ]],
			align    => [qw[ caption div h1 h2 h3 h4 h5 h6 p ]],
			action   => [qw[ form ]],
		);
		foreach my $attr (keys %_) {
			$self->{fastlane}->{$_} = $attr for @{$_{$attr}};
		}
	}
	
	$self->{hooks} = {
		assign => {
			re => qr{assign\((?<name>[a-z0-9\._]+)\)},
			fn => sub {
				my ($self, $e, $m) = @_;
				$self->{assigns}->{$m->{name}} = $self->_assign_target($e);
			}
		},
		coffee => {
			fn => sub {
				my ($self, $e) = @_;
				$e->{output_coffee} = 1;
			}
		}
	};
	
	$self->{defaults} = {
		style => {
			type => 'text/css'
		},
		script => {
			type => 'text/javascript'
		},
		%{ delete $self->{opts}->{defaults} || {} }
	};

	return bless $self => ref $class || $class;
}

=head2 clone

=cut

sub clone {
	my ($self, $options) = @_;
	my $class = ref $self;
	$self = Clone::clone($self);
	
	$self->{opts} = { %{$self->{opts}}, %$options };
	
	return bless $self => $class;
}

sub _nextid {
	my $self = shift;
	return 'anonymous_element_'.$self->{anonymous_element_id}++;
}

sub _flatten {
	my ($self, $struct, $indent_offset) = @_;
	if (ref $struct eq 'ARRAY') {
		return map { $self->_flatten($_, $indent_offset) } @$struct;
	}
	pop @{$struct->{I}} for 0..$indent_offset;
	return unless defined $struct->{C};
	if (exists $struct->{comment}) {
		$struct->{C} = '###'.(exists $struct->{jsdoc} ? '*' : '').EOL.(join EOL, @{$struct->{C}}).EOL.'###';
	}
	return join('' => @{$struct->{I}}).$struct->{C}, (exists $struct->{E} ? $self->_flatten($struct->{E}, $indent_offset) : ());
}

sub _assign_target {
	my ($self, $e) = @_;
	return unless ref $e eq 'HASH';
	if ($e->{element} ~~ [qw[ html head body ]]) {
		$e->{target} = $e->{element};
	} else {
		unless (exists $e->{attrs}->{id}) {
			$e->{attrs}->{id} = $self->_nextid;
		}
		$e->{target} = '#'.$e->{attrs}->{id};
	}
	return $e->{target};
}

sub _elem {
	my ($self, $capture, $struct, $items) = @_;
	local %_ = %$capture;
	$_{indent} = scalar @{$struct->{I}};
	$_{lineno} = $struct->{L};
	$_{extra} = $struct->{X};
	$_{file} = $self->{file};
	if (exists $_{action}) {
		delete $_{action};
		$_{element} = lc $_{element};
		if (exists $_{attrs}) {
			$_{attrs} = substr $_{attrs}, 1, -1;
			$_{attrs} = { map { /=/ ? ( split /=/, $_, 2 ) : ( $_ => $_ )} grep length, split /
				\s*
				([^=]+=\S+)
				\s*
			/x, $_{attrs} };
		} else {
			$_{attrs} = {};
		}
		if (exists $self->{defaults}->{$_{element}}) {
			$_{attrs} = { %{$self->{defaults}->{$_{element}}}, %{$_{attrs}} };
		}
		if (exists $_{classes}) {
			$_{attrs}->{class} = join ' ' => grep length, split /\./, delete $_{classes};
		}
		if (exists $_{id}) {
			$_{attrs}->{id} = substr delete $_{id}, 1;
		}
		if (exists $_{coffee}) {
			$_{coffee} = delete $_{rest};
			$self->_assign_target(\%_);
		}
		if (exists $_{data}) {
			$_{attrs} = { %{$_{attrs}}, map {( split /=/, $_, 2 )} map { "data-$_" } grep length, split /
				\s+
				&
				([^=]+=\S+)
			/x, delete $_{data} };
			
		}
		if (exists $_{hooks}) {
			foreach my $hook (split /\s+/, delete $_{hooks}) {
				next unless $hook =~ /\S/;
				$hook =~ s{^\!}{};
				foreach my $hook_ (keys %{$self->{hooks}}) {
					if (exists $self->{hooks}->{$hook_}->{re} and $hook =~ $self->{hooks}->{$hook_}->{re}) {
						$self->{hooks}->{$hook_}->{fn}->($self, \%_, {%+});
					} elsif ($hook eq $hook_) {
						$self->{hooks}->{$hook_}->{fn}->($self, \%_);
					}
				}
			}
		}
		if (exists $_{fastlane}) {
			$_{fastlane} = substr $_{fastlane}, 1, -1;
			if (exists $self->{fastlane}->{$_{element}}) {
				my $attr = $self->{fastlane}->{$_{element}};
				$_{attrs}->{$attr} = $_{fastlane};
			} else {
				carp "fastlane info specified for '$_{element}'";
			}
		}
		given ($_{element}) {
			when ([qw[ style ]]) {
				$_{text} = [ $self->_flatten($items, $_{indent}) ];
				@$items = ();
			}
		}
	} elsif (exists $_{special}) {
		delete $_{special};
		$_{filters} = [ grep m{\S}, split m{\s*\|\s*}, delete $_{filter} ] if exists $_{filter};
		if (exists $self->{commands}->{$_{command}}) {
			$self->{commands}->{$_{command}}->($self, \%_, $_{args}, $items);
		}
	}
	%$struct = %_;
}

sub _parseti {
	my ($self, $line) = @_;
	my @indent = @{$self->{indent}};
	local $" = '';
	my $obj = { L => $., C => undef, I => [ @indent ] };
	if ($line =~ m{^@indent(\S.*)$}) {
		$obj->{C} = $1;
		push @{$self->{current}} => $obj;
	} elsif ($line =~ m{^@indent(\s+)(\S.*)$}) {
		push @{$self->{indent}} => $1;
		$obj->{C} = $2;
		push @{$obj->{I}} => $1;
		my $n = [ $obj ];
		$self->{current}->[-1]->{E} = $n;
		push @{$self->{stack}} => $self->{current};
		$self->{current} = $n;
	} elsif ($line =~ m{^(\s*)(\S.*)$}) {
		my $indent = $1;
		$obj->{C} = $2;
		my $i = 0;
		my $ok;
		unless (length $1) { # back to the roots
			$i = @indent;
			$ok = 1;
		} else {
			$ok = 0;
			while (pop @indent) {
				$i++;
				local $" = '';
				if ($indent eq "@indent") {
					$ok = 1;
					last;
				}
			}
		}
		if ($ok) {
			pop @{$self->{indent}} for 1..$i;
			$self->{current} = pop @{$self->{stack}} for 1..$i;
			$obj->{I} = Clone::clone($self->{indent});
			push @{$self->{current}} => $obj;
		} else {
			croak "indentation error";
		}
	} else {
		# discard empty lines
	}
	return $obj;
}

sub _parseln {
	my ($self, $line) = @_;
	chomp $line;
	if (exists $self->{raw}) {
		if ($line eq $self->{raw}->{stp}) {
			$self->{raw}->{obj}->{C} = $self->{raw}->{cnt};
			delete $self->{raw};
		} else {
			if (length $line > $self->{raw}->{dnt}) {
				push @{$self->{raw}->{cnt}} => substr($line, $self->{raw}->{dnt});
			} else {
				push @{$self->{raw}->{cnt}} => '';
			}
		}
	} else {
		my $obj = $self->_parseti($line);
		if (defined $obj->{C}) {
			if ($obj->{C} =~ m{^("{3,})$}) {
				my $stp = join('', @{$obj->{I}});
				local $_ = $1;
				$self->{raw} = { stp => $stp.$_, cnt => [], obj => $obj, dnt => 0 };
			} elsif ($obj->{C} =~ m{^(<{3,})$}) {
				my $stp = join('', @{$obj->{I}});
				local $_ = $1;
				tr{<}{>};
				$self->{raw} = { stp => $stp.$_, cnt => [], obj => $obj, dnt => length($stp) };
			} elsif ($obj->{C} =~ m{^(#{3,})(\*)?$}) {
				my $stp = join('', @{$obj->{I}});
				$obj->{comment} = 1;
				$obj->{jsdoc} = $2;
				local $_ = $1;
				$self->{raw} = { stp => $stp.$_, cnt => [], obj => $obj, dnt => length($stp) };
			}
		}
	}
}

sub _process {
	my ($self, $struct) = @_;
	push @{$self->{stack}} => $struct;
	if (ref $struct eq 'ARRAY') {
		$self->_process($_) for @$struct;
		pop @{$self->{stack}};
		return;
	}
	my $items = (exists $struct->{E} ? delete $struct->{E} : undef);
	if (exists $struct->{C} and defined $struct->{C}) {
		if (not ref $struct->{C}) {
			if ($struct->{C} =~ m{^#}) {
				$struct->{ignore} = 1;
				return;
			}
			my $re_hooks = $self->{re_hooks};
			if ($struct->{C} =~ m/^
(?:
	(?<action>
		%
		(?<element> $re_html_element )
		(?<fastlane> \( .*? \) )?
		(?<classes> ( \. $re_css_class )+ )?
		(?<id> \# $re_css_id )?
		(?<attrs> \{ [^\}]* \} )?
		(?<data> ( \s+ & [^=]+ = \S+ )+ )?
		(?<hooks>
			(?: \s+ ! $re_hooks )+
		)?
		(?<coffee> \s+ -> \s+ )?
		\s*
		(?<rest> .*)?
	)
|
	(?<special>
		%%
		(?<command> [a-z]+ )
		\s*
		(?<args> [^\|]+? )?
	)
	(?<filter>
		(?:
			\s+
			\|
			\s+
			[a-z]+
		)+
	)?
)
\s*
$/xism) {
				$self->_elem({%+}, $struct, $items);
			} else {
				$struct->{C} =~ s{^\\}{};
				%$struct = (
					text => $struct->{C},
					lineno => $struct->{L},
					file => $self->{file},
					indent => scalar @{$struct->{I}}
				);
			}
		} elsif (ref $struct->{C} eq 'ARRAY') {
			%$struct = (
				text => join (EOL, @{$struct->{C}}),
				lineno => $struct->{L},
				file => $self->{file},
				indent => scalar @{$struct->{I}},
				(exists $struct->{comment} ? (comment => 1) : ()),
			);
		} else {
			croak "unknown C";
		}
	} elsif (exists $struct->{E}) {
		%$struct = (
			lineno => $struct->{L},
			file => $self->{file},
			indent => scalar @{$struct->{I}}
		);
	} else {
		%$struct = ();
	}
	$struct->{items} = $items if defined $items and @$items > 0;
	if (exists $struct->{items} and ref $struct->{items} eq 'ARRAY') {
		$self->_process($_) for @{$struct->{items}};
	}
	if (exists $struct->{after}) {
		my $sub = delete $struct->{after};
		$sub->($self, $struct);
	}
	pop @{$self->{stack}};
	if (exists $struct->{C}) {
		croak "uaah";
	}
}

=head2 parse

=cut

sub parse {
	my ($self, $in) = @_;

	$self->{struct} = [];
	$self->{indent} = [ map { '' } 1..$self->{opts}->{indent} ];
	$self->{anonymous_element_id} = $self->{opts}->{idoffset} || 0;
	$self->{current} = [];
	$self->{stack} = [ $self->{current} ];
	$self->{coffee} = [];
	
	{
		local @_ = ();
		foreach my $hook (keys %{$self->{hooks}}) {
			if (exists $self->{hooks}->{$hook}->{re}) {
				push @_ => $self->{hooks}->{$hook}->{re};
			} else {
				push @_ => quotemeta $hook;
			}
		}
		local $" = '|';
		$self->{re_hooks} = qr{@_};
	}

	$in ||= *STDIN;
	
	$self->{file} = "<".ref($in).">";
	
	if (defined $in and not ref $in) {
		$self->{file} = $in;
		open my $fh, $in or croak "cannot open $in: $!";
		$in = $fh;
	}
	
	print STDERR "parsing ".$self->{file}.'...';
	if (ref $in eq 'SCALAR') {
		$self->_parseln($_) for split /\n/, $$in;
	} elsif (ref $in eq 'GLOB') {
		$self->_parseln($_) while (<$in>);
		close $in;
	} else {
		croak "unknown type: ".ref $in;
	}
	say STDERR 'ok';
	
	if (exists $self->{raw}) {
		croak "raw block not closed, started at line ".$self->{raw}->{obj}->{L};
	}
	
	$self->{root} = $self->{stack}->[0];
	delete $self->{current};
	$self->{stack} = [ $self->{root} ];
	
	$self->_process($self->{root});
	
	delete $self->{stack};
	delete $self->{struct};
	delete $self->{indent};

	return $self;
}

=head1 AUTHOR

David Zurborg, C<< <zurborg@cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests through my project management tool
at L<projects//issues/new>.  I
will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc CoffeeML

You can also look for information at:

=over 4

=item * Redmine: Homepage of this module

L<projects/>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=CoffeeML>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/CoffeeML>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/CoffeeML>

=item * Search CPAN

L<http://search.cpan.org/dist/CoffeeML/>

=back

=head1 COPYRIGHT & LICENSE

Copyright 2014 David Zurborg, all rights reserved.

This program is released under the following license: open-source

=cut

1;
