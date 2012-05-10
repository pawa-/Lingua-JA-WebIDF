package Lingua::JA::WebIDF;

use 5.008_001;
use strict;
use warnings;

use Carp ();
use URI;
use Furl::HTTP;
use JSON ();
use Storable ();
use TokyoCabinet;

our $VERSION = '0.00_1';

our $BING_API_URL          = 'http://api.bing.net/json.aspx';
our $YAHOO_API_URL         = 'http://search.yahooapis.jp/WebSearchService/V2/webSearch';
our $YAHOO_PREMIUM_API_URL = 'http://search.yahooapis.jp/PremiumWebSearchService/V1/webSearch';


sub _options
{
    return {
        documents  => 250_0000_0000,
        df_file    => './df',
        fetch_df   => 1,
        default_df => 125_0000_0000,
        expires    => 365,
        Furl_HTTP  => undef,
        driver     => 'Storable',
        app        => 'Bing',
        appid      => undef,
    };
}

sub new
{
    my $class = shift;
    my %args  = (ref $_[0] eq 'HASH' ? %{$_[0]} : @_);

    my $options = $class->_options;

    for my $key (keys %args)
    {
        if (!exists $options->{$key}) { Carp::croak("Unknown option: $key"); }
        else                          { $options->{$key} = $args{$key}; }
    }

    Carp::croak('appid is needed') unless length $options->{appid};

    bless $options, $class;
}

sub idf
{
    my ($self, $word) = @_;

    my $df = $self->df($word);
    my $N  = $self->{documents};

    $df = 1 if $df == 0; # To avoid dividing by zero

    return log($N / $df);
}

sub df
{
    my ($self, $word) = @_;

    my $driver = $self->{driver};

    my $df;

    if    ($driver eq 'Storable')     { $df = $self->_fetch_df_Storable($word); }
    elsif ($driver eq 'TokyoCabinet') { $df = $self->_fetch_df_TokyoCabinet($word); }
    else                              { Carp::croak("Unknown driver: $driver"); }

    if (!defined $df)
    {
        $df = $self->_fetch_new_df($word) if $self->{fetch_df};

        if (defined $df) { $self->_save_idf($word, $df); }
        else             { return $self->{default_df}; }
    }

    return $df;
}

sub _fetch_df_Storable
{
    my ($self, $word) = @_;

    if (!exists $self->{df} && -s $self->{df_file})
    {
        $self->{df} = Storable::retrieve($self->{df_file});
    }

    my $df = $self->{df};

    return $df->{$word};
}

sub _fetch_df_TokyoCabinet
{
    my ($self, $word) = @_;

    my $hdb = TokyoCabinet::HDB->new;

    $hdb->open($self->{df_file}, $hdb->OWRITER | $hdb->OCREAT | $hdb-> ONOLCK)
        or Carp::croak( $hdb->errmsg($hdb->ecode) );

    my $df = $hdb->get($word); # or Carp::carp( $hdb->errmsg($hdb->ecode) );

    $hdb->close or Carp::croak( $hdb->errmsg($hdb->ecode) );

    return $df;
}

sub _fetch_new_df
{
    my ($self, $word) = @_;

    my $app  = $self->{app};
    my $furl = Furl::HTTP->new;

    my $df;

    if ($app eq 'Bing')
    {
        my $url = URI->new($BING_API_URL);

        $url->query_form(
            'Appid'     => $self->{appid},
            'query'     => $word,
            'sources'   => 'web',
            'web.count' => 1,
        );

        my (undef, $code, $msg, undef, $body) = $furl->get($url);

        if ($code == 200)
        {
            my $json = JSON::decode_json($body);
            $df = $json->{SearchResponse}{Web}{Total};
        }
        else { Carp::carp("$app: $code $msg"); }
    }
    elsif ($app eq 'Yahoo' || $app eq 'Yahoo_Premium')
    {
        my $url = ($app eq 'Yahoo')
                ? URI->new($YAHOO_API_URL)
                : URI->new($YAHOO_PREMIUM_API_URL)
                ;

        $url->query_form(
            'appid'    => $self->{appid},
            'query'    => $word,
            'type'     => 'all', # query type
            'format'   => 'any', # file format
            'adult_ok' => 1,
        );

        my (undef, $code, $msg, undef, $body) = $furl->get($url);

        if ($code == 200)
        {
            my $xml = $furl->get($url);

            if    ($xml =~ /totalResultsAvailable="([0-9]+)"/) { $df = $1; }
            elsif ($xml =~ m|<Message>(.*?)</Message>|)        { Carp::carp("$app: $1"); }
            else                                               { Carp::carp("$app: unknown response"); }
        }
        else { Carp::carp("$app: $code $msg"); }
    }
    else { Carp::croak("Unknown app: $app"); }

    return $df;
}

sub _save_idf
{
    my ($self, $word, $df) = @_;

    my $driver = $self->{driver};

    if ($driver eq 'Storable')
    {
        my $df_ref = $self->{df};
        $df_ref->{$word} = $df;

        Storable::nstore($df_ref, $self->{df_file})
            or Carp::croak("Can't store df data to $self->{df_file}");
    }
    elsif ($driver eq 'TokyoCabinet')
    {
        my $hdb = TokyoCabinet::HDB->new;

        $hdb->open($self->{df_file}, $hdb->OWRITER | $hdb->OCREAT | $hdb->ONOLCK)
            or Carp::croak( $hdb->errmsg($hdb->ecode) );

        # If a record with the same key exists in the database, it is overwritten.
        $hdb->put($word, $df) or Carp::carp( $hdb->errmsg($hdb->ecode) );

        $hdb->close or Carp::croak( $hdb->errmsg($hdb->ecode) );
    }
}

1;
__END__

=head1 NAME

Lingua::JA::WebIDF -

=head1 SYNOPSIS

  use Lingua::JA::WebIDF;

=head1 DESCRIPTION

Lingua::JA::WebIDF is

=head1 AUTHOR

pawa- E<lt>pawapawa@cpan.orgE<gt>

=head1 SEE ALSO

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
