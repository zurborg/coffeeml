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

sub _indent($$) {
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

sub _prepare_for_textile {
	my ($self, $e) = @_;
	given (ref $e) {
		when ('HASH') {
			if (exists $e->{items}) {
				return $self->_prepare_for_textile($e->{items});
			} elsif (exists $e->{line}) {
				return $e->{line};
			}
		}
		when ('ARRAY') {
			return join EOL, map { $self->_prepare_for_textile($_) } @$e;
		}
		default {
			if (defined $e) {
				return $e;
			}
		}
	}
}

sub _build($_) {
	my ($self, $e) = @_;
	given (ref $e) {
		when ('ARRAY') {
			$self->_build($_) foreach @$e;
		}
		when ('HASH') {
			if (exists $e->{ignore}) {
				return;
			}
			if (exists $e->{action}) {
				
				if (exists $e->{command}) {
					
					given ($e->{command}) {
						when ('textile') {
							use Text::Textile qw(textile);
							$self->_outp(_indent(textile($self->_prepare_for_textile($e->{items})), ('  ' x ($e->{indent} + $self->{indentoffset}))).EOL);
						}
						when ('include') {
							my $file = $e->{args} || croak "command include: no arguments given, filename needed";
							open my $fh, $file or croak "command inlcude: cannot open file $file: $!";
							$self->_outp(('  ' x ($e->{indent} + $self->{indentoffset})).$_) for <$fh>;
							close $fh;
						}
						when ('process') {
							my $file = $e->{args} || croak "command include: no arguments given, filename needed";
							$self->{indentoffset}++;
							my $parser = CoffeeML::Parser->new({
								idoffset => $self->{struct}->{anonymous_element_id},
								indent => $e->{indent} + $self->{indentoffset}
							});
							$self->{indentoffset}--;
							my $struct = $parser->parse($file);
							$self->{struct}->{anonymous_element_id} = $parser->{anonymous_element_id};
							$self->_build($struct->{root});
						}
						when ('wrapper') {
							my $file = $e->{args} || croak "command include: no arguments given, filename needed";
							$self->{indentoffset}++;
							my $parser = CoffeeML::Parser->new({
								idoffset => $self->{struct}->{anonymous_element_id},
								indent => $e->{indent} + $self->{indentoffset}
							});
							$self->{indentoffset}--;
							my $struct = $parser->parse($file);
							$self->{struct}->{anonymous_element_id} = $parser->{anonymous_element_id};
							push @{$self->{content}} => $e->{items};
							$self->_build($struct->{root});
							carp "wrapper file processed, but content not inserted" if scalar(@{$self->{content}}) > 0;
						}
						when ('content') {
							$self->_build(pop @{$self->{content}});
						}
						when ('raw') {
							my $outp = $self->{outp};
							my $ndnt = $self->{indentoffset};
							$self->{indentoffset} = 0 - $e->{indent} - 1;
							$self->{outp} = \'';
							$self->_build($e->{items});
							my $result = ${ $self->{outp} };
							$self->{outp} = $outp;
							$result =~ s{&(?![a-z]+;)}{&amp;}g;
							$result =~ s{<}{&lt;}g;
							$result =~ s{>}{&gt;}g;
							$self->_outp($result);
							$self->{indentoffset} = $ndnt;
						}
						when ('macro') {
							unless ($e->{args} =~ m{^\s*([a-z]+)(?:\s*\(\s*(.+)\s*\))?\s*$}) {
								carp "what?? ".$e->{args};
								return;
							}
							my ($name, $args) = ($1, $2);
							my @args = split /[\s,]+/ => $args;
							$self->{macros}->{$name} = {
								name => $name,
								args => \@args,
								items => $e->{items}
							};
							return;
						}
						when ('call') {
							my $name = $e->{args};
							unless (exists $self->{macros}->{$name}) {
								carp "macro not found: $name";
								return;
							}
							my $macro = $self->{macros}->{$name};
							my $outp = $self->{outp};
							$self->{outp} = \'';
							$self->_build($macro->{items});
							my $result = ${ $self->{outp} };
							$self->{outp} = $outp;
							$self->_outp($result);
						}
						default {
							carp "unknwon command: $_";
							return;
						}
					}
					
				} elsif (exists $e->{element}) {
					
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
					}
					
					foreach my $attr (keys %{$e->{attrs}}) {
						$self->_outp(' '.$attr.'="'.$e->{attrs}->{$attr}.'"');
					}
					
					if ($e->{element} ~~ $standalone_elems) {
						$self->_outp(' />'.EOL);
						if (exists $e->{items}) {
							carp "discarding child elements";
							delete $e->{items};
						}
						return;
					}
					
					if ($e->{element} eq 'script' and exists $e->{output_coffee}) {
						$self->{indentoffset}++;
						$e->{items} = [{indent => 0, line => '' }, { indent => $e->{indent} + $self->{indentoffset}, line => $self->_javascript }];
						$self->{indentoffset}--;
					}
					
					if (exists $e->{items}) {
						if (scalar(@{$e->{items}}) == 1 and ref $e->{items}->[0] eq 'HASH' and not exists $e->{items}->[0]->{action}) {
							$self->_outp('>'.$e->{items}->[0]->{line}.'</'.$e->{element}.'>'.EOL);
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
					} else {
						$self->_outp('></'.$e->{element}.'>'.EOL);
					}
				} elsif (exists $e->{coffeeblock}) {
					# ignore
				} else {
					use Data::Dumper;
					say STDERR Dumper($e);
					croak "meh";
				}
				
			} elsif (exists $e->{indent}) {
				$self->_outp('  ' x ($e->{indent} + $self->{indentoffset}));
				$self->_outp($e->{line}.EOL);
				$self->_build($e->{items}) if exists $e->{items};
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
