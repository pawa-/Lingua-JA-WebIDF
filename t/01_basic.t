use strict;
use warnings;
use Lingua::JA::WebIDF;
use Test::More;
use Test::Fatal;

can_ok('Lingua::JA::WebIDF', qw/new idf df/);

like(exception { Lingua::JA::WebIDF->new },                   qr/appid is needed/);
like(exception { Lingua::JA::WebIDF->new(document => 1000) }, qr/Unknown option: document/);

my $webidf = Lingua::JA::WebIDF->new( appid => 'てすと' );
$webidf    = Lingua::JA::WebIDF->new({ appid => 'てすと' });
isa_ok($webidf, 'Lingua::JA::WebIDF');

done_testing;
