package Lingua::JA::WebIDF;

use 5.008_001;
use strict;
use warnings;

use Carp ();
use Module::Load ();
use Furl::HTTP;

our $VERSION = '0.00_9';

our %API_URL = (
    Bing         => 'http://api.bing.net/json.aspx',
    Yahoo        => 'http://search.yahooapis.jp/WebSearchService/V2/webSearch',
    YahooPremium => 'http://search.yahooapis.jp/PremiumWebSearchService/V1/webSearch',
);

my @SUPPORTED_API    = keys %API_URL;
my @SUPPORTED_DRIVER = qw/Storable TokyoCabinet/;

sub _options
{
    return {
        documents     => 250_0000_0000,
        df_file       => undef,
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

    Carp::croak('appid is needed')                    unless defined $options->{appid};
    Carp::croak("Unknown driver: $options->{driver}") unless grep { $options->{driver} eq $_ } @SUPPORTED_DRIVER;
    Carp::croak("Unknown api: $options->{api}")       unless grep { $options->{api}    eq $_ } @SUPPORTED_API;

    if (defined $options->{Furl_HTTP})
    {
        $options->{furl_http} = Furl::HTTP->new($options->{Furl_HTTP});
    }
    else { $options->{furl_http} = Furl::HTTP->new; }

    Module::Load::load(__PACKAGE__ . '::API::' . $options->{api});
    Module::Load::load(__PACKAGE__ . '::Driver::' . $options->{driver});

    if (!defined $options->{df_file})
    {
        my $path = $INC{ join( '/', split('::', __PACKAGE__) ) . '.pm' };
        $path =~ s/\.pm$//;
        $path .= '/bing_utf8.st';

        $options->{df_file} = $path;
    }

    bless $options, $class;
}

sub idf
{
    my ($self, $word) = @_;

    if (!defined $word)
    {
        Carp::carp("Undefined word was set to idf method");
        return;
    }

    my $df = $self->df($word);
    my $N  = $self->{documents};

    $df = 1 if $df == 0; # To avoid dividing by zero

    return log($N / $df);
}

sub df
{
    my ($self, $word) = @_;

    if (!defined $word)
    {
        Carp::carp("Undefined word was set to df method");
        return;
    }

    my $df_and_time = $self->_fetch_df($word);

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

sub _fetch_df
{
    my ($self, $word) = @_;

    no strict 'refs';
    my $driver = __PACKAGE__ . '::Driver::' . $self->{driver};
    &{$driver . '::fetch_df'}($self, $word);
}

sub _save_df
{
    my ($self, $word, $df) = @_;

    my $df_and_time = $df . "\t" . time;

    no strict 'refs';
    my $driver = __PACKAGE__ . '::Driver::' . $self->{driver};
    &{$driver . '::save_df'}($self, $word, $df_and_time);
}

sub _fetch_new_df
{
    my ($self, $word) = @_;

    no strict 'refs';
    my $api = __PACKAGE__ . '::API::' . $self->{api};
    &{$api . '::fetch_new_df'}( $self, $word, $API_URL{ $self->{api} } );
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

=head2 new( %config || \%config )

Creates a new Lingua::JA::WebIDF instance.

The following configuration is used if you don't set %config.

  KEY                 DEFAULT VALUE
  -----------         ---------------
  api                 'Bing'
  appid               undef
  driver              'Storable'
  df_file             undef
  fetch_df            1
  expires_in          365
  documents           250_0000_0000
  default_df          5000
  Furl_HTTP           undef

=over 4

=item api => 'Bing' || 'Yahoo' || 'YahooPremium'

Uses the specified Web API when fetches WebDF(Document Frequency) scores
from the Web.

=item driver => 'Storable' || 'TokyoCabinet'

Fetches and saves WebDF scores with the specified driver.

=item df_file => $path

Saves WebDF scores to the specified path.

If undef is specified, 'bing_utf8.st' is used.
This file is located in 'Lingua/JA/WebIDF/'
and contains the WebDF scores of about 60000 words.
There are other format files in the 'df' directory of this library.

I recommend that you change the file name depending on the kind of Web API
you specifies because WebDF may be different depending on Web API.

=item fech_df => 0

Doesn't fetch WebDF scores. (If 0 is specified.)

If the WebDF score you want to know is already saved, it is used.
Otherwise, the value of default_df is used.

=item expires_in => $days

If 365 is specified, The WebDF score expires in 365 days after fetches it.

=item Furl_HTTP => \%option

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
