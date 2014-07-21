package CoffeeML;

use Modern::Perl;
use Carp;

use CoffeeML::Parser;
use CoffeeML::Builder;

=head1 NAME

CoffeeML - Coffee Markup Language

=head1 VERSION

Version 1.00

=cut

our $VERSION = '1.00';

=head1 SYNOPSIS

    use CoffeeML;

    my $cml = CoffeeML->new;
	
	my $infile = 'in.cml';
	my $outfile = 'out.html';
    $cml->process($infile, $outfile);
	
	my $intext = \'...';
	my $outtext;
    $cml->process($intext, $outtext);
	say $outtext;
	
    $cml->process(\*STDIN, \*STDOUT);

=head1 DESCRIPTION

...

=cut

use constant EOL => "\n";

=head1 METHODS

=head2 new

=cut

sub new {
	my ($class, %options) = @_;
	$options{parser} ||= {};
	$options{builder} ||= {}; 
	my $parser = CoffeeML::Parser->new(delete $options{parser});
	my $builder = CoffeeML::Builder->new(delete $options{builder});
	
	my $self = {
		opts => \%options,
		parser => $parser,
		builder => $builder,
	};
	$self = bless $self => ref $class || $class;
	return $self->_init($parser, $builder);
}

=head2 process($in, $out, %options)

=cut

sub process {
	my ($self, $in, $out, %opts) = @_;
	%opts = ( %{$self->{opts}}, %opts );
	my $struct = $self->{parser}->parse($in);
	if (0) {
		use Data::Dumper;
		say STDERR '#' x 80;
		say STDERR Dumper($struct->{root});
		say STDERR '#' x 80;
	}
	$self->{builder}->build($struct, $out);
}

=head2 register_hook(name, coderef, regexp)

=cut

sub register_hook {
	my ($self, $name, $fn, $re) = @_;
	$self->{parser}->{hooks}->{$name} = {
		fn => $fn
	};
	$self->{parser}->{hooks}->{$name}->{re} = $re if defined $re;
}

=head2 register_fastlane(elemets, attribute)

=cut

sub register_fastlane {
	my ($self, $elements, $attr) = @_;
	$elements = [ $elements ] unless ref $elements eq 'ARRAY';
	$self->{parser}->{fastlane}->{$_} = $attr for @$elements;
}

=head2 register_command(name, (parse => coderef, build => coderef))

=cut

sub register_command {
	my ($self, $name, %fn) = @_;
	$self->{parser}->{commands}->{$name} = $fn{parse} if exists $fn{parse};
	$self->{builder}->{commands}->{$name} = $fn{build} if exists $fn{build};
}

=head2 register_filter(name, coderef)

=cut

sub register_filter {
	my ($self, $name, $fn) = @_;
	$self->{builder}->{filters}->{$name} = $fn;
}

sub _init {
	my ($self, $parser, $builder) = @_;

	$self->register_command('coffee',
		parse => sub {
			my ($self, $e, $args, $items) = @_;
			if (defined $args and $args eq 'root') {
				push @{$self->{coffee}} => $self->_flatten([ @$items ], 0);
			} elsif (exists $self->{stack}->[-2]) {
				my $p = $self->{stack}->[-2];
				if (ref $p eq 'HASH') {
					$self->_assign_target($p);
					unless (exists $p->{coffee}) {
						$p->{coffee} = [];
					}
					unless (ref $p->{coffee} eq 'ARRAY') {
						$p->{coffee} = [ $p->{coffee} ];
					}
					if (defined $args) {
						$p->{coffeeextra} ||= {};
						$p->{coffeeextra}->{$args} ||= [];
						push @{$p->{coffeeextra}->{$args}} => $self->_flatten([ @$items ], $e->{indent});
					} else {
						push @{$p->{coffee}} => $self->_flatten([ @$items ], $e->{indent});
					}
					@$items = ();
					$e->{ignore} = 1;
				} elsif (ref $p eq 'ARRAY') {
					push @{$self->{coffee}} => $self->_flatten([ @$items ], 0);
				}
			}
		},
		build => sub {}
	);
	$self->register_command('sass',
		parse => sub {
			my ($self, $e, $args, $items) = @_;
			if (exists $self->{stack}->[-2]) {
				my $p = $self->{stack}->[-2];
				if (ref $p eq 'HASH') {
					$self->_assign_target($p);
					unless (exists $p->{sass}) {
						$p->{sass} = [];
					}
					unless (ref $p->{sass} eq 'ARRAY') {
						$p->{sass} = [ $p->{sass} ];
					}
					push @{$p->{sass}} => $self->_flatten([ @$items ], $e->{indent});
					@$items = ();
					$e->{ignore} = 1;
				} elsif (ref $p eq 'ARRAY') {
					$self->{sass} ||= [];
					push @{$self->{sass}} => $self->_flatten([ @$items ], $e->{indent});
				}
			}
		},
		build => sub {}
	);
	$self->register_command('include',
		build => sub {
			my ($self, $e, $args) = @_;
			$args =~ m{^\s* (?<filename> [^\|]+)\s*$}x || croak "command include: no arguments given, filename needed";
			open my $fh, $+{filename} or croak "command inlcude: cannot open file $+{filename}: $!";
			$e->{text} = '';
			$e->{text} .= $_ for <$fh>;
			close $fh;
			if (exists $e->{items}) {
				$self->_error($e, "discarding additional content (".$self->_flatten($e->{items}).")");
			}
			return 1;
		}
	);
	$self->register_command('process',
		build => sub {
			my ($self, $e, $file) = @_;
			$file || $self->_error($e, "no arguments given, filename needed for command process");
			$self->{indentoffset}++;
			my $parser_ = $parser->clone({
				idoffset => $self->{struct}->{anonymous_element_id},
				indent => $e->{indent} + $self->{indentoffset}
			});
			$self->{indentoffset}--;
			$parser_->parse($file);
			$self->{struct}->{anonymous_element_id} = $parser_->{anonymous_element_id};
			$self->_build($parser_->{root});
			if (exists $e->{items}) {
				$self->_error($e, "discarding additional content");
			}
			return;
		}
	);
	$self->register_command('wrapper',
		build => sub {
			my ($self, $e, $file) = @_;
			$file || $self->_error($e, "no arguments given, filename needed for command process");
			unless (exists $e->{items}) {
				$self->_error($e, "no content in wrapper");
				return;
			}
			my $parser_ = $parser->clone({
				idoffset => $self->{struct}->{anonymous_element_id},
				indent => $e->{indent} + $self->{indentoffset}
			});
			$parser_->parse($file);
			$self->{struct}->{anonymous_element_id} = $parser_->{anonymous_element_id};
			push @{$self->{content}} => $e->{items};
			$self->_build($parser_->{root});
			carp "wrapper file processed, but content not inserted" if scalar(@{$self->{content}}) > 0;
			
			return;
		}
	);
	$self->register_command('content',
		build => sub {
			my ($self, $e, $args) = @_;
			unless (@{$self->{content}}) {
				$self->_error($e, "content requestet when no content available");
				return;
			}
			$self->{indentoffset}++;
			$self->_build(pop @{$self->{content}});
			$self->{indentoffset}--;
			return;
		}
	);
	$self->register_command('filter',
		build => sub {
			my ($self, $e, $args) = @_;
			$self->_error($e, 'command filter need arguments') and return unless defined $args;
			my @filters = grep { m{\S} } split m{[\s,]+}, $args;
			$self->_filter($e, @filters);
			return 1;
		}
	);
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
