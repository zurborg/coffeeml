package CoffeeML::Parser;

use Modern::Perl;
use Carp;

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
my $re_hook_assign = qr{assign\(([a-z0-9\._]+)\)};
my $re_hooks = qr{($re_hook_assign|ignore|coffee)};

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

sub _nextid {
	my $self = shift;
	return 'anonymous_element_'.$self->{anonymous_element_id}++;
}

sub _elem($%) {
	my $self = shift;
	local %_ = @_;
	$_{indent} = scalar @{$self->{indent}};
	if (exists $_{action}) {
		$_{element} = lc $_{element} if exists $_{element};
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
		if (exists $_{element} and exists $self->{defaults}->{$_{element}}) {
			$_{attrs} = { %{$self->{defaults}->{$_{element}}}, %{$_{attrs}} };
		}
		if (exists $_{classes}) {
			$_{attrs}->{class} = join ' ' => grep length, split /\./, $_{classes};
		}
		if (exists $_{id}) {
			$_{attrs}->{id} = substr $_{id}, 1;
		}
		if (exists $_{coffee}) {
			$_{coffee} = delete $_{rest};
			unless (exists $_{attrs}->{id}) {
				$_{attrs}->{id} = $self->_nextid;
			}
		}
		if (exists $_{data}) {
			$_{attrs} = { %{$_{attrs}}, map {( split /=/, $_, 2 )} map { "data-$_" } grep length, split /
				\s+
				&
				([^=]+=\S+)
			/x, delete $_{data} };
			
		}
		if (exists $_{hooks}) {
			foreach my $hook (split /\s+/, $_{hooks}) {
				next unless $hook =~ /\S/;
				$hook =~ s{^\!}{};
				if ($hook =~ m{^$re_hook_assign$}) {
					unless (exists $_{attrs}->{id}) {
						$_{attrs}->{id} = $self->_nextid;
					}
					$self->{assigns}->{$1} = $_{attrs}->{id};
				} elsif ($hook eq 'ignore') {
					$_{ignore} = 1;
				} elsif ($hook eq 'coffee') {
					$_{output_coffee} = 1;
				} else {
					carp "cannot parse hook: $hook";
				}
			}
		}
		if (exists $_{special}) {
			$_{special} = substr $_{special}, 1, -1;
			given ($_{element}) {
				when ([qw[ a base area link ]]) {
					$_{attrs}->{href} = $_{special};
				}
				when ([qw[ script frame iframe img ]]) {
					$_{attrs}->{src} = $_{special};
				}
				when ([qw[ meta input button map param select textarea ]]) {
					$_{attrs}->{name} = $_{special};
				}
				when ([qw[ blockquote q ]]) {
					$_{attrs}->{cite} = $_{special};
				}
				when ([qw[ br ]]) {
					$_{attrs}->{clear} = $_{special};
				}
				when ([qw[ head ]]) {
					$_{attrs}->{profile} = $_{special};
				}
				when ([qw[ html ]]) {
					$_{attrs}->{lang} = $_{special};
				}
				when ([qw[ label ]]) {
					$_{attrs}->{for} = $_{special};
				}
				when ([qw[ li option ]]) {
					$_{attrs}->{value} = $_{special};
				}
				when ([qw[ ol ul style ]]) {
					$_{attrs}->{type} = $_{special};
				}
				when ([qw[ optgroup ]]) {
					$_{attrs}->{label} = $_{special};
				}
				when ([qw[ caption div h1 h2 h3 h4 h5 h6 p ]]) {
					$_{attrs}->{align} = $_{special};
				}
				when ([qw[ form ]]) {
					$_{attrs}->{action} = uc $_{special};
				}
				default {
					carp "special info specified for '$_{element}'";
				}
			}
		}
		if (exists $_{command} and $_{command} eq 'coffee') {
			$self->{capture_js_block} = 1;
			$_{coffee} = [ '# start coffeeblock' ];
			
			my $x;
			unless (exists $self->{struct}->[-1]) {
				if (exists $self->{level}->[-2]) {
					$x = $self->{level}->[-2]->[-1];
				} else {
					carp "JS at root";
				}
			} elsif ($_{indent} - $self->{struct}->[-1]->{indent} <= 1) {
				$x = $self->{struct}->[-1];
			} else {
				$x = $self->{struct}->[-1]->{items}->[-1];
			}
			
			unless (defined $x and exists $x->{attrs}->{id}) {
				$x->{attrs}->{id} = $self->_nextid;
			}
		}
	} else {
		$_{line} =~ s{^\\}{};
	}
	return \%_;
}

sub _parseln($_) {
	my ($self, $line) = @_;
	chomp $line;
	my @indent = @{$self->{indent}};
	$" = '';
	if ($self->{capture_raw_block}) {
		if ($line =~ m{^@indent"""$}) {
			my $rawdata = join EOL, @{$self->{struct}};
			$self->{struct} = pop @{$self->{level}};
			push @{$self->{struct}} => { indent => scalar(@indent), line => $rawdata } if $self->{capture_raw_block} < 2;
			$self->{capture_raw_block} = 0;
			pop @{$self->{indent}};
			return;
		} else {
#			say ">$line";
			push @{$self->{struct}} => $line;
			return;
		}
	} elsif ($line =~ m{^\s*$}) {
		push @{$self->{struct}} => undef unless exists $self->{struct}->[-1]->{action};
		return;
	} elsif ($self->{capture_js_block} and $line =~ m{^@indent}) {
		if ($self->{capture_js_block} == 2 and $line =~ m{^@indent(.+)$}) {
#			say "%$line";
			push @{$self->{struct}} => $1;
			return;
		} elsif ($self->{capture_js_block} == 1 and $line =~ m{^@indent(\s+)(.+)$}) {
#			say "%$line";
			push @{$self->{indent}} => $1;
			my $n = $self->{struct}->[-1]->{coffee} = [ $2 ];
			push @{$self->{level}} => $self->{struct};
			$self->{struct} = $n;
			$self->{capture_js_block} = 2;
			return;
		} else {
			carp "capture js: step $self->{capture_js_block} and line={{$line}} - bad";
			carp "                indentation: |@indent|";
		}
	} elsif ($line =~ m/^
(?<indent> \s* )
(?<line>
	(?<action>
		(?:
			%
			(?<element> $re_html_element )
			(?<special> \( .*? \) )?
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
		(?:
			%%
			(?<command> [a-z]+ )
			\s*
			(?<args> .+? )?
		)
	)?
	|
	.*
)
\s*
$/xism) {
		local %_ = %+;
		if ($_{indent} eq "@indent") { # same level
#			say "=$line";
			if ($line =~ m{^\s*"""$}) {
				$self->{capture_raw_block} = 1;
				push @{$self->{level}} => $self->{struct};
				$self->{struct} = [];
				push @{$self->{indent}} => '';
			} else {
				push @{$self->{struct}} => $self->_elem(%_);
			}
		} elsif (substr($_{indent}, 0, length "@indent") eq "@indent") { # level up
#			say "+$line";
			push @{$self->{indent}} => substr($_{indent}, length "@indent");
			if ($line =~ m{^\s*"""$}) {
				$self->{capture_raw_block} = 2;
				my $n = $self->{struct}->[-1]->{items} = [];
				push @{$self->{level}} => $self->{struct};
				$self->{struct} = $n;
			} else {
				my $n = [ ];
				$self->{struct}->[-1]->{items} = $n;
				push @{$self->{level}} => $self->{struct};
				$self->{struct} = $n;
				push @$n => $self->_elem(%_);
			}
		} else { # level down
#			say "-$line";
			if ($self->{capture_js_block}) {
				$self->{capture_js_block} = 0;
				my $x = delete($self->{level}->[-1]->[-1])->{coffee};
				if (@{$self->{level}} > 1) {
					push @{$self->{level}->[-2]->[-1]->{coffee}} => @{ $x };
				} else {
					push @{$self->{coffee}} => @$x;
				}
			}
			while (pop @{$self->{indent}}) {
				$self->{struct} = pop @{$self->{level}};
				if ($_{indent} eq join '', @{$self->{indent}}) {
					push @{$self->{struct}} => $self->_elem(%_);
					return;
				}
			}
			carp "LOST: $line";
		}
	} else {
		carp "unparsable line: <<$line>>"
	}
}

=head2 parse

=cut

sub parse {
	my ($self, $in) = @_;

	$self->{struct} = [];
	$self->{root} = [ $self->{struct} ];
	$self->{level} = [];
	$self->{indent} = [ map { '' } 1..$self->{opts}->{indent} ];
	$self->{capture_js_block} = 0;
	$self->{capture_raw_block} = 0;
	$self->{anonymous_element_id} = $self->{opts}->{idoffset} || 0;
	$self->{assigns} = {};
	$self->{coffee} = [];

	$in ||= *STDIN;
	
	if (defined $in and not ref $in) {
		open my $fh, $in or croak "cannot open $in: $!";
		$in = $fh;
	}

	if (ref $in eq 'SCALAR') {
		$self->_parseln($_) for split /\n/, $$in;
	} elsif (ref $in eq 'GLOB') {
		$self->_parseln($_) while (<$in>);
		close $in;
	} else {
		croak "unknown type: ".ref $in;
	}

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
