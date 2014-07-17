package CoffeeML::Builder;

use Modern::Perl;
use Carp;
use IPC::Run;
use Scalar::Util qw(blessed);

=head1 NAME

CoffeeML::Builder - Builder for CoffeeML

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

    use CoffeeML::Builder;

    CoffeeML::Builder->build($document);

=head1 DESCRIPTION

This module is used internal only

=cut

use constant EOL => "\n";

my $standalone_elems = [qw[ area base basefont br col frame hr img input isindex link meta param ]];

=head1 METHODS

=head2 new

=cut

sub new {
	my ($class, $options) = @_;
	
	my $self = {};
	
	$self->{opts} = $options || {};

	return bless $self => ref $class || $class;
}

sub _dump_without_items {
	use Data::Dumper;
	use Clone qw(clone);
	
	my $e = clone(shift);
	$e->{items} = scalar @{$e->{items}} if exists $e->{items} and defined $e->{items};
	$e->{E} = scalar @{$e->{E}} if exists $e->{E} and defined $e->{E};
	say STDERR Dumper($e);
}


sub _build($_);

sub _compile_coffeescript($$) {
	my ($self, $text) = @_;
	use IPC::Run qw(run);
    my $coffeecmd = [ coffee => qw[ -bsc ] ];
    
    my $in = \$text;
    my $out = '';
    my $err = '';
    
    run ($coffeecmd, $in, \$out, \$err) or croak "coffeescript exited with status $?, errors: $err";
	
	return $out;
}

sub _indent {
	shift if ref $_[0];
	my ($str, $pre) = @_;
	return join(EOL, map { $pre.$_ } split /\n/, $str);
}

sub _outp($_) {
	my $self = shift;
	my $H = $self->{outp};
	if (ref $H eq 'GLOB') {
		print $H join EOL, @_;
	} elsif (ref $H eq 'SCALAR') {
		$H = \'' unless defined $$H;
		$self->{outp} = \($$H.join EOL, @_);
	} else {
		croak "how to what?";
	}
}

sub _flatten {
	my ($self, $e) = @_;
	given (ref $e) {
		when ('HASH') {
			if (exists $e->{items}) {
				return $self->_flatten($e->{items});
			} elsif (exists $e->{text}) {
				return $e->{text};
			}
		}
		when ('ARRAY') {
			return join EOL, map { $self->_flatten($_) } @$e;
		}
		default {
			if (defined $e) {
				return $e;
			}
		}
	}
}

sub _error {
	my ($self, $e, $msg) = @_;
	if (exists $e->{lineno}) {
		warn "error: $msg at ".$e->{file}." line ".$e->{lineno}.EOL;
	} else {
		local @_ = caller(0);
		local $" = ', ';
		die "error: $msg (catched at $_[0] line $_[2])".EOL;
	}
}

sub _build($_) {
	my ($self, $e) = @_;
	given (ref $e) {
		when ('ARRAY') {
			$self->_build($_) foreach @$e;
		}
		when ('HASH') {
			unless (keys %$e) {
				return;
			}
			if (exists $e->{ignore}) {
				return;
			}
			if (exists $e->{command}) {
				if (exists $self->{commands}->{$e->{command}}) {
					return unless $self->{commands}->{$e->{command}}->($self, $e, $e->{args});
				} else {
					$self->_error($e, "unknwon command: ".$e->{command});
				}
			}
			if (exists $e->{element}) {
				
				$self->_outp('  ' x ($e->{indent} + $self->{indentoffset}));
				
				$self->_outp('<'.$e->{element});
				
				given ($e->{element}) {
					when ([qw[ input ]]) {
						$e->{attrs}->{value} = delete $e->{rest} if exists $e->{rest};
					}
					when ([qw[ meta ]]) {
						$e->{attrs}->{content} = delete $e->{rest} if exists $e->{rest};
					}
					when ([qw[ area ]]) {
						$e->{attrs}->{alt} = $e->{attrs}->{title} = delete $e->{rest} if exists $e->{rest};
					}
					when ([qw[ script ]]) {
						if (exists $e->{output_coffee}) {
							$self->{indentoffset}++;
							$e->{items} = [{indent => 0, line => '' }, { indent => $e->{indent} + $self->{indentoffset}, line => $self->_javascript }];
							$self->{indentoffset}--;
						}
					}
				}
				
				foreach my $attr (keys %{$e->{attrs}}) {
					$self->_outp(' '.$attr.'="'.$e->{attrs}->{$attr}.'"');
				}
				
				if ($e->{element} ~~ $standalone_elems) {
					$self->_outp(' />'.EOL);
					if (exists $e->{items}) {
						$self->_error($e, "discarding child elements");
						delete $e->{items};
					}
					return;
				}
				
				if (exists $e->{items} and defined $e->{items}) {
					if (scalar(@{$e->{items}}) == 1 and ref $e->{items}->[0] eq 'HASH' and not exists $e->{items}->[0]->{command} and not exists $e->{items}->[0]->{element}) {
						$self->_outp('>'.$e->{items}->[0]->{text}.'</'.$e->{element}.'>'.EOL);
					} elsif ($e->{element} eq 'pre') {
						$self->_outp('>');
						$self->_build($e->{items});
						$self->_outp('</'.$e->{element}.'>'.EOL);
					} else {
						$self->_outp('>'.EOL);
						$self->_build($e->{items});
						$self->_outp('  ' x ($e->{indent} + $self->{indentoffset}));
						$self->_outp('</'.$e->{element}.'>'.EOL);
					}
				} elsif (exists $e->{rest} and defined $e->{rest} and $e->{rest} =~ /\S/) {
					$self->_outp('>'.$e->{rest}.'</'.$e->{element}.'>'.EOL);
				} elsif (exists $e->{text} and defined $e->{text}) {
					if (ref $e->{text} eq 'ARRAY') {
						$self->_outp('>'.EOL);
						my $indent = '  ' x ($e->{indent} + $self->{indentoffset});
						$self->_outp(_indent(join(EOL, @{$e->{text}}), $indent.'  ').EOL);
						$self->_outp($indent.'</'.$e->{element}.'>'.EOL);
					} else {
						$self->_outp('>'.$e->{text}.'</'.$e->{text}.'>'.EOL);
					}
				} else {
					$self->_outp('></'.$e->{element}.'>'.EOL);
				}
			} elsif (exists $e->{coffeeblock}) {
				# ignore
			} elsif (exists $e->{indent}) {
				$self->_outp('  ' x ($e->{indent} + $self->{indentoffset}));
				#_dump_without_items($e);
				if (exists $e->{text}) {
					$self->_outp($e->{text});
				} elsif (exists $e->{rest}) {
					$self->_outp($e->{rest});
				}
				$self->_outp(EOL);
				$self->_build($e->{items}) if exists $e->{items};
			} elsif (exists $e->{items}) {
				$self->_build($e->{items});
			} else {
				_dump_without_items($e);
				$self->_error($e, "meh");
			}
			
			if (exists $e->{coffee}) {
				my $id = $e->{attrs}->{id};
				my $coffee = $e->{coffee};
				if (ref $coffee eq 'ARRAY') {
					$coffee = join EOL, @$coffee, 'undefined';
				}
				if (defined $id) {
					$self->{coffeescript} .= sprintf q!(->%s).call($('#%s'))!.EOL.EOL, EOL._indent($coffee, '  ').EOL, $id;
				} else {
					$self->{coffeescript} .= sprintf q!(->%s).call($)!.EOL.EOL, EOL._indent($coffee, '  ').EOL;
				}
			}
		}
		default {
			$self->_outp($e.EOL) if defined $e;
		}
	}
}

sub _javascript {
	my ($self) = @_;
	
	return '';
	
	my $JS = '';
	
	my $assigns = $self->{struct}->{assigns};
	
	if (keys %$assigns or length $self->{coffeescript} or scalar @{$self->{struct}->{coffee}}) {
		$JS .= $self->_compile_coffeescript(
			'window.jQuery ($) ->'.EOL.
			_indent(join(EOL, map { sprintf q!%s = $('#%s')!, $_, $assigns->{$_} } keys %$assigns), '  ').EOL.
			EOL.
			_indent($self->{coffeescript}, '  ').EOL.
			EOL.
			_indent((join EOL, @{$self->{struct}->{coffee}}), '  ').EOL.
			EOL.
			'  undefined'.EOL
		);
	}
	$self->{coffeescript} = '';
	
	return $JS;
}

=head2 build($document, $output_handle)

=cut

sub build {
	my ($self, $struct, $outp) = @_;

	croak "bad: $struct" unless blessed $struct and $struct->isa('CoffeeML::Parser');
	
	$self->{indentoffset} ||= 0;
	$self->{coffeescript} = '';
	$self->{macros} = {};
	$self->{content} = [];
	$self->{struct} = $struct;
	if (defined $outp and not ref $outp) {
		open my $fh, ">$outp" or croak "cannot open $outp: $!";
		$outp = $fh;
	}
	$self->{outp} = $outp || *STDOUT;

	$self->_build($self->{struct}->{root});
	
	$$outp = ${$self->{outp}} if ref $outp eq 'SCALAR';
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
