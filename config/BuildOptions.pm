%BuildOptions = (%BuildOptions,
    NAME                => 'CoffeeML',
    DISTNAME            => 'CoffeeML',
    AUTHOR              => 'David Zurborg <zurborg@cpan.org>',
    VERSION_FROM        => 'lib/CoffeeML.pm',
    ABSTRACT_FROM       => 'lib/CoffeeML.pm',
    LICENSE             => 'open-source',
    PL_FILES            => {},
    PMLIBDIRS           => [qw[ lib ]],
    EXE_FILES           => [qw[ bin/coffeemaker ]],
    PREREQ_PM           => {
        'Test::Most'        => 0,
        'Modern::Perl'      => 0,
        'IPC::Run'          => 0,
        'Text::Textile'     => 0,
        'HTML::Entities'    => 0,
    },
    dist                => {
        COMPRESS            => 'gzip -9f',
        SUFFIX              => 'gz',
        CI                  => 'git add',
        RCS_LABEL           => 'true',
    },
    clean               => { FILES => 'CoffeeML-*' },
    depend              => {
		'$(FIRST_MAKEFILE)' => 'config/BuildOptions.pm',
    },
);
