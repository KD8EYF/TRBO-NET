use 5.006;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'TRBO::NET',
    'VERSION_FROM'	=> 'Common.pm', # finds $VERSION
    'PREREQ_PM'		=> {
        'Test::More' => '0.1',
    },
    'EXE_FILES'         => [ 'tools/arsed' ],
    ($] >= 5.005 ?
      (
       ABSTRACT_FROM   => 'Common.pm',
       AUTHOR          => 'Anonymous',
       LICENSE        => 'perl',
      ) : ()
    ),
);
