use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Radio',
    AUTHOR              => q{YOUR NAME <youremail@example.com>},
    VERSION_FROM        => 'lib/Radio.pm',
    ABSTRACT            => 'YOUR APPLICATION ABSTRACT',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More'           => 0,
        'YAML'                 => 0,
        'Dancer'               => 1.3011,
        'Dancer::Plugin::Ajax' => 0,
        'Dancer::Plugin::MPD'  => 0,
        'IO::File'             => 0,
        'MP3::Tag'             => 0,
        'POSIX'                => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'radio-*' },
);
