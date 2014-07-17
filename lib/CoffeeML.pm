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
	return bless $self => ref $class || $class;
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

sub register_fastlane {
	my ($self, $elements, $attr) = @_;
	$elements = [ $elements ] unless ref $elements eq 'ARRAY';
	$self->{parser}->{fastlane}->{$_} = $attr for @$elements;
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
