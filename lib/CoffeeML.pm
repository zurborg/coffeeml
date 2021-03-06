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
					unless (exists $p->{command}) {
						$self->_assign_target($p);
					}
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
	$self->register_command('TT',
		parse => sub {
			my ($self, $e, $args, $items) = @_;
			return if defined $args and $args !~ m{^\s*!js_(too|only)\s*$};
			$e->{text} = [ $self->_flatten([ @$items ], $e->{indent}) ];
			@$items = ();
		},
		build => sub {
			my ($self, $e, $args) = @_;
			my $indent = ('  ' x $self->{coffeescript_indent});
			if (defined $args) {
				my $js = '';
				{
					my $re = qr{\s*!js_(too|only)\s*$};
					if ($args =~ $re) {
						$js = $1;
					}
					$args =~ s{$re}{};
				}
				$self->{coffeescript} .= $indent."#[% $args %]\n" if $js;
				if (exists $e->{items}) {
					$e->{after} = sub {
						my ($self, $e) = @_;
						$self->{coffeescript} .= $indent."#[% END %]\n";
					} if $js;
					if ($js ne 'only') {
						$e->{items} = [
							{ indent => $e->{indent}, text => '[% '.$args.' %]' },
							@{$e->{items}},
							{ indent => $e->{indent}, text => '[% END %]' }
						];
					}
				} elsif (ref $e->{text} eq 'ARRAY') {
					$self->{coffeescript} .= join '' => map { $indent.$_."\n" } ( '###', '[%', @{$e->{text}}, '%]', '###') if $js;
					$e->{items} = [
						{ indent => $e->{indent}, text => '[%' },
						@{delete $e->{text}},
						{ indent => $e->{indent}, text => '%]' }
					] if $js ne 'only';
				} else {
					$e->{text} = '[% '.$args.' %]' if $js ne 'only';
				}
			} else {
				#$self->{coffeescript} .= join '' => map { $indent.$_."\n" } ( '###', '[%', @{$e->{text}}, '%]', '###');
				$e->{text} = join "\n", '[%', @{$e->{text}}, '%]';
			}
		}
	);
	$self->register_command('PHP',
		parse => sub {
			my ($self, $e, $args, $items) = @_;
			return if defined $args;
			$e->{text} = [ $self->_flatten([ @$items ], $e->{indent}) ];
			@$items = ();
		},
		build => sub {
			my ($self, $e, $args) = @_;
			if (defined $args) {
				if (exists $e->{items}) {
					$e->{items} = [
						{ indent => $e->{indent}, text => '<?php '.$args.' { ?>' },
						@{$e->{items}},
						{ indent => $e->{indent}, text => '<?php } ?>' }
					];
				} else {
					if ($args =~ m{^=(.+)$}) {
						$e->{text} = '<?php= '.$1.' ?>';
					} else {
						$e->{text} = '<?php '.$args.' ?>';
					}
				}
			} else {
				$e->{text} = join "\n", '<?php', @{$e->{text}}, '?>';
			}
		}
	);
	$self->register_command('loop',
		parse => sub {
			my ($self, $e, $args, $items) = @_;
			die 'args?' unless defined $args;
			die 'args!' unless $args =~ m{^\s* (\S+) \s+ => \s* (.+?) \s*$}x;
			my ($id, $var) = ($1, $2);
			$e->{loop} = { id => $id, var => $var };

			$self->{anonymous_element_id_orig} ||= [];
			push @{$self->{anonymous_element_id_orig}} => delete $self->{anonymous_element_id};
			push @{$self->{id_suffix}} => $var;
			$self->{anonymous_element_id} = 0;
			$self->{assigns_orig} ||= [];
			push @{$self->{assigns_orig}} => delete $self->{assigns};
			$self->{assigns} = {};
			$e->{after} = sub {
				my ($self, $e) = @_;
				$self->{anonymous_element_id} = pop @{$self->{anonymous_element_id_orig}};
				pop @{$self->{id_suffix}};
				$e->{assigns} = delete $self->{assigns};
				$self->{assigns} = pop @{$self->{assigns_orig}};
			};
		},
		build => sub {
			my ($self, $e, $args) = @_;
			my $indent = '  ' x $self->{coffeescript_indent};
			{
				my $assigns = $e->{assigns};
				$self->{coffeescript} .= $self->_indent(join(EOL, map { sprintf q!%s = $ '%s'!, $_, delete $assigns->{$_} } keys %$assigns), $indent).EOL;
			}
			$self->{coffeescript} .= $indent.'(('.$e->{loop}->{id}.') ->'."\n";
			$self->{coffeescript_indent}++;
			
			$e->{after} = sub {
				my ($self, $e) = @_;
				$self->{coffeescript_indent}--;
				my $indent = '  ' x $self->{coffeescript_indent};
				$self->{coffeescript} .= $indent.')(`'.$e->{loop}->{var}.'`)'."\n";
			};
			
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
