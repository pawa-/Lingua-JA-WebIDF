use inc::Module::Install;

name     'Lingua-JA-WebIDF';
all_from 'lib/Lingua/JA/WebIDF.pm';

requires 'Carp';
requires 'URI';
requires 'Furl::HTTP';
requires 'JSON';
requires 'Storable';
requires 'TokyoCabinet';

test_requires 'Test::More' => 0.88; # done_testing
test_requires 'Test::Fatal';
test_requires 'Test::Warn';
test_requires 'Test::TCP';
test_requires 'Test::Requires';

tests 't/*.t';
author_tests 'xt';

readme_from 'lib/Lingua/JA/WebIDF.pm';

resources(
    license => 'http://dev.perl.org/licenses',
    repository => 'https://github.com/pawa-/Lingua-JA-WebIDF',
    bugtracker => 'https://github.com/pawa-/Lingua-JA-WebIDF/issues',
);

WriteAll;
