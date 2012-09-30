use strict;
use warnings;
use utf8;
use Lingua::JA::WebIDF;
use Test::More;
use Test::Warn;
use Test::TCP;
use Test::Requires qw/TokyoCabinet Plack::Loader Plack::Builder Plack::Request/;

binmode Test::More->builder->$_ => ':utf8'
    for qw/output failure_output todo_output/;


my $TOKYOCABINET_FILE = './df/utf8.tch';

my $app = sub {
    sleep(30);
    return [ 200, [ 'Content-Type' => 'text/plain' ], [ 'Hello!' ] ];
};

test_tcp(
    server => sub {

        my $port = shift;

        my $server = Plack::Loader->auto(
            port => $port,
            host => '127.0.0.1',
        );

        $server->run($app);
    },
    client => sub {

        my $port = shift;

        my $webidf = Lingua::JA::WebIDF->new(
            api       => 'Yahoo',
            appid     => 'test',
            df_file   => $TOKYOCABINET_FILE,
            driver    => 'TokyoCabinet',
            fetch_df  => 1,
            Furl_HTTP => { timeout => 5 },
        );

        no warnings 'once';
        $Lingua::JA::WebIDF::API::Yahoo::BASE_URL = "http://127.0.0.1:$port";

        $webidf->db_open;

        warning_like { $webidf->df('hoge' x 100); }
        qr/timeout/i, 'timeout';

        $webidf->db_close;
    },
);

done_testing;