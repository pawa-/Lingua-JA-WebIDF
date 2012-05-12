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

our $VERSION = '0.00_4';

our $BING_API_URL          = 'http://api.bing.net/json.aspx';
our $YAHOO_API_URL         = 'http://search.yahooapis.jp/WebSearchService/V2/webSearch';
our $YAHOO_PREMIUM_API_URL = 'http://search.yahooapis.jp/PremiumWebSearchService/V1/webSearch';


sub _options
{
    return {
        documents     => 250_0000_0000,
        df_file       => './df_bing.st',
        fetch_df      => 1,
        default_df    => 5000,
        expires_in    => 365, # number of days
        driver        => 'Storable',
        api           => 'Bing',
        appid         => undef,
        Furl_HTTP     => undef,
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


    if (defined $options->{Furl_HTTP})
    {
        $options->{furl_http} = Furl::HTTP->new($options->{Furl_HTTP});
    }
    else { $options->{furl_http} = Furl::HTTP->new; }

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

    my $df_and_time;

    if    ($driver eq 'Storable')     { $df_and_time = $self->_fetch_df_Storable($word); }
    elsif ($driver eq 'TokyoCabinet') { $df_and_time = $self->_fetch_df_TokyoCabinet($word); }
    else                              { Carp::croak("Unknown driver: $driver"); }

    my ($df, $time, $elapsed_time);

    if (defined $df_and_time)
    {
        ($df, $time)  = split(/\t/, $df_and_time);
        $elapsed_time = time - $time;
    }

    if ( !defined $df_and_time || $elapsed_time > (60 * 60 * 24 * $self->{expires_in}) )
    {
        my $new_df;

        $new_df = $self->_fetch_new_df($word) if $self->{fetch_df};

        if (defined $new_df)
        {
            $self->_save_df($word, $new_df);
            return $new_df;
        }
        else { return (defined $df) ? $df : $self->{default_df}; }
    }

    return $df;
}

sub _fetch_df_Storable
{
    my ($self, $word) = @_;

    if (!exists $self->{df} && -s $self->{df_file})
    {
        $self->{df} = Storable::lock_retrieve($self->{df_file});
    }

    my $df = $self->{df};

    return $df->{$word};
}

sub _fetch_df_TokyoCabinet
{
    my ($self, $word) = @_;

    my $hdb = TokyoCabinet::HDB->new;

    $hdb->open($self->{df_file}, $hdb->OWRITER | $hdb->OCREAT)
        or Carp::croak( $hdb->errmsg($hdb->ecode) );

    my $df = $hdb->get($word); # or Carp::carp( $hdb->errmsg($hdb->ecode) );

    $hdb->close or Carp::croak( $hdb->errmsg($hdb->ecode) );

    return $df;
}

sub _fetch_new_df
{
    my ($self, $word) = @_;

    my $api  = $self->{api};
    my $furl = $self->{furl_http};

    my $df;

    if ($api eq 'Bing')
    {
        my $url = URI->new($BING_API_URL);

        $url->query_form(
            'Appid'     => $self->{appid},
            'query'     => qq|"$word"|,
            'sources'   => 'web',
            'web.count' => 1,
        );

        my (undef, $code, $msg, undef, $body) = $furl->get($url);

        if ($code == 200)
        {
            my $json = JSON::decode_json($body);
            $df = $json->{SearchResponse}{Web}{Total};
        }
        else { Carp::carp("$api: $code $msg"); }
    }
    elsif ($api eq 'Yahoo' || $api eq 'Yahoo_Premium')
    {
        my $url = ($api eq 'Yahoo')
                ? URI->new($YAHOO_API_URL)
                : URI->new($YAHOO_PREMIUM_API_URL)
                ;

        $url->query_form(
            'appid'    => $self->{appid},
            'query'    => qq|"$word"|,
            'type'     => 'all', # query type
            'format'   => 'any', # file format
            'adult_ok' => 1,
        );

        my (undef, $code, $msg, undef, $body) = $furl->get($url);

        if ($code == 200)
        {
            my $xml = $furl->get($url);

            if    ($xml =~ /totalResultsAvailable="([0-9]+)"/) { $df = $1; }
            elsif ($xml =~ m|<Message>(.*?)</Message>|)        { Carp::carp("$api: $1"); }
            else                                               { Carp::carp("$api: unknown response"); }
        }
        else { Carp::carp("$api: $code $msg"); }
    }
    else { Carp::croak("Unknown api: $api"); }

    return $df;
}

sub _save_df
{
    my ($self, $word, $df) = @_;

    my $driver      = $self->{driver};
    my $df_and_time = $df . "\t" . time;

    if ($driver eq 'Storable')
    {
        my $df_ref = $self->{df};
        $df_ref->{$word} = $df_and_time;

        Storable::lock_nstore($df_ref, $self->{df_file})
            or Carp::croak("Can't store df data to $self->{df_file}");
    }
    elsif ($driver eq 'TokyoCabinet')
    {
        my $hdb = TokyoCabinet::HDB->new;

        $hdb->open($self->{df_file}, $hdb->OWRITER | $hdb->OCREAT)
            or Carp::croak( $hdb->errmsg($hdb->ecode) );

        # If a record with the same key exists in the database, it is overwritten.
        $hdb->put($word, $df_and_time) or Carp::carp( $hdb->errmsg($hdb->ecode) );

        $hdb->close or Carp::croak( $hdb->errmsg($hdb->ecode) );
    }
}

1;
__END__

=encoding utf8

=head1 NAME

Lingua::JA::WebIDF - WebIDF calculator

=for test_synopsis
my ($appid);

=head1 SYNOPSIS

  use Lingua::JA::WebIDF;

  my $webidf = Lingua::JA::WebIDF->new
  (
      api       => 'Bing',
      appid     => $appid,
      driver    => 'Storable',
      df_file   => './df_bing.st',
      fetch_df  => 1,
      Furl_HTTP => { timeout => 3 }
  );

  print $webidf->idf("東京"); # low
  print $webidf->idf("スリジャヤワルダナプラコッテ"); # high

=head1 DESCRIPTION

Lingua::JA::WebIDF calculates WebIDF scores.

WebIDF(Inverse Document Frequency) scores represent the rarity of words on the Web.
The WebIDF scores of rare words are high.
Conversely, the WebIDF scores of common words are low.

=head1 METHOD

=head2 new( [%config | \%config] )

Creates a new Lingua::JA::WebIDF instance.

The following configuration is used if you don't set %config.

  KEY                 DEFAULT VALUE
  -----------         ---------------
  api                 'Bing'
  appid               undef
  driver              'Storable'
  df_file             './df_bing.st'
  fetch_df            1
  expires_in          365
  documents           250_0000_0000
  default_df          5000
  Furl_HTTP           undef

=over 4

=item api => 'Bing' | 'Yahoo' | 'Yahoo_Premium'

Uses the specified Web API when fetches WebDF(Document Frequency) scores
from the Web.

=item driver => 'Storable' | 'TokyoCabinet'

Fetches and saves WebDF scores with the specified driver.

=item df_file

Saves WebDF scores to the specified path.

I recommend that you change the file name depending on the kind of Web API
you specifies because WebDF may be different depending on Web API.

=item fech_df => 0

Doesn't fetch WebDF scores. (If 0 is specified.)

If the WebDF score you want to know is already saved, it is used.
Otherwise, the value of default_df is used.

=item expires_in

If 365 is specified, The WebDF score expires in 365 days after fetches it.

=item Furl_HTTP => HashRef

Sets the options of L<Furl::HTTP>->new.

If you want to use proxy server, you have to use this option.

=back

=head2 idf($word)

Calculates the WebIDF score of $word.

If the WebDF score of $word is not saved or is expired,
fetches it by using the Web API you specified and saves it.

=head2 df($word)

Fetches the WebDF score of $word.

If the WebDF score of $word is not saved or is expired,
fetches it by using the Web API you specified and saves it.

=head1 AUTHOR

pawa E<lt>pawapawa@cpan.orgE<gt>

=head1 SEE ALSO

L<Lingua::JA::TFIDF>

L<http://www.bing.com/toolbox/bingdeveloper/>

L<http://developer.yahoo.co.jp/>


=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
